# Review mp: the rest of the Meadow port

Brief: briefs/mp.md      Reviewed commit: 3134721

## Design

Meadow uses the fixed-step habitat interface and the shared cell renderer. The normal app menu, Settings picker and welcome chips use `HabitatKind.offered`, which still contains Ocean and Web in the same order. The menu handler uses that same list for its tags. The settings codec and snapshot override also recognize the new raw value. I checked the app integration from source and by building the app.

### Verification

- `swift build` and `swift build -c release --product ASCIIAnimals` succeeded with Swift 6.4. `swift run -c release OceanChecks` passed **215 checks**, including Metal, the m1 fixtures and m1's warm-step allocation check. The baseline passed 181 checks. I used `debce4e` for the baseline. The subsequent `origin/main` update to `5a113b8` changes only the board entry for CI.
- `OceanTool bench --digest` matched the baseline in shared mode (`612a0c22c778b40b`) and with `--separate` (`d4d23789aedfab08`). That command hashes Web. I also hashed the Ocean uniforms and fish grids over 900 frames with scripted pointer input in both layouts. They matched in shared mode (`e75c964a451182f9`) and in separate mode (`f8b54bcbc0beaabd`).
- All eight before-and-after PNG pairs matched byte for byte. For each of Ocean and Web I rendered seed 4242 at 800 × 500 in dark and light, at 1800 × 900 in live Calm at 1.25× scale, and at 340 × 150 in live light Calm.
- I rendered the live Meadow at 340 × 150 and 7680 × 4320 and a flower sheet at 16 × 8192. Independent seeded 30-minute runs at 340 × 150, 7680 × 4320 and on a desk with a 2560 × 1440 display offset below the 7680 × 4320 screen stayed finite and kept seven butterflies. The checked-in 30-minute run and 40 relayouts also passed. On a 1440 × 900 pair with a 260 pt vertical offset and a shared edge, all seven crossed to the other display within 60 simulated seconds at seed 3. The count was seven across the desk.
- A warmed, unclicked two-display render probe recorded zero heap allocations over 300 frames. Findings 1 and 5 cover the cache lifetime and the frames after input.
- CI on this exact commit used **Swift 6.3.3**. The Checks step passed 192 checks with GPU checks disabled, and the universal app built for arm64 and x86_64. [CI job](https://github.com/zegrt/ascii-animals/actions/runs/44790899444/job/136477954371)

Two release runs per habitat of `OceanTool bench --desk --habitat <habitat>` used the default shared desk at 2560 × 1440 and 1800 × 1169 points. CPU costs are milliseconds per simulated second.

| Frame rate | Meadow thread | Web thread | Meadow process | Web process |
|---|---:|---:|---:|---:|
| 30 fps | 14.64–14.97 | 18.57–18.89 | 18.06–18.31 | 21.80–22.22 |
| 15 fps | 7.69–7.77 | 14.46–14.56 | 9.44–9.53 | 16.06–16.17 |

## What is missing?

- Exercise a narrow gap, an offset pair, a count change, an unplug at the old seam and a pointer held between displays. Check the segment, every position update and the immediate post-layout state. The current gap check uses one static layout at the default count. Its second-screen assertion can pass from initial placement. The relayout check allows a quarter-span outside and skips waiting and departing butterflies.
- Measure allocations after clicking and through the fade and cache eviction. Check retained cache counts on **both** screens during alternating paints and bound the number of fading flowers under an input burst with no simulation ticks.
- Add bad-input probes for the Meadow tool commands and the layout cases below. The current world check passes huge values to pointer input and passes small or empty rectangles to layout.

## Findings

| # | Finding | Where | Cause group | Fix size |
|---|---|---|---|---|
| 1 | **Flower recordings grow without bound on the first of two displays.** Each paint increments the same counter. Alternating A then B means only B ever sees a multiple of 600 and prunes. After 1,201 paired frames with clicks, A had 53 cached flowers, 26 stale by the code's own cutoff. B had 28 entries, one stale. Prune by each viewport's own paint count or sweep all caches and cap their retained storage. | `MeadowPainter.swift:232`, `FlowerPainter.swift:75`, `FlowerPainter.swift:119` | Painter cache lifetime | medium |
| 2 | **Several-screen motion can go through or into a gap.** On two 1440 × 900 displays separated by one point, with the right display offset 2 pt down, `wayOpen(840, 400, 2040, 400)` returns true. A controlled flight step went from x=1439.5 to x=1444.63 through the same gap because only the endpoint is checked. In a controlled landed state the pull moved the body to x=1440.625, inside the gap. Clip the actual segments against the screen union and apply gap handling to the approach and landed pulls as well as normal flight. | `MeadowWorld.swift:149`, `MeadowWorld.swift:167`, `MeadowBehaviour.swift:34`, `MeadowFlight.swift:415`, `:447`, `:529` | Screen geometry | medium |
| 3 | **Facing edges can spawn into a gap or strand a departure.** With two 1440 × 900 screens at (0, 0) and (1760, 2), seed 1, increasing the count from seven to twelve put newcomer #8 at (1619.63, 355.68), inside the gap. In a controlled departure at (1439, 450) with a 40 pt gap to the right display, the nearest edge sent the butterfly to (1875.39, 450), on the other screen. It was still present after 120 simulated seconds. Validate the entry position and choose an exit with a clear route to an off-desk destination. | `MeadowWorld.swift:267`, `:292`, `:325`, `MeadowFlight.swift:209` | Screen geometry | medium |
| 4 | **Relayout can leave butterflies outside the new screens.** In a one-to-two-to-one layout probe a flyer at (1441, 450) was initially on the right display and remained a point outside the surviving 1440 × 900 display after unplug. The quarter-span flight allowance is applied to the relayout, and waiting and departing butterflies are skipped outright. Four waiting arrivals were also left outside in the count-change probe. Project displaced butterflies onto a surviving screen at layout time and revalidate their targets for the new geometry. | `MeadowWorld.swift:457`, `:475` | Screen geometry | medium |
| 5 | **A click allocates in subsequent warmed paint frames.** The independent allocation probe measured 0 allocations over 300 unclicked frames, 4 in the first frame after a successful click, and 15 across 900 frames after a second click, including bloom, fade and stale eviction. A new ID creates a cache and grows recorded operations in paint. Cleanup builds a replacement dictionary. Reuse bounded recording slots and evict without allocating during paint. | `FlowerPainter.swift:74`, `:119`, `:233`, `MeadowPainter.swift:366` | Painter cache lifetime | medium |
| 6 | **Bad numbers trap in Meadow tools.** `meadow-sheet out.png 340x150 --sheet flowers --scale nan` and `meadow-desk out --scale nan` trap, as do `meadow-desk out --warmup 1e300` and `meadow-desk out --seconds 1e300`. All exited by SIGTRAP in release. The shared `frames --fps 0` and `still nanx150` paths also trap with `--habitat meadow`. Validate ranges and derived frame counts and pixel sizes before converting to integers, allocating or creating output directories. | `Sources/OceanTool/main.swift:70`, `:90`, `:133`, `:157`, `MeadowDesk.swift:21`, `StillRenderer.swift:114` | Tool input validation | small |
| 7 | **Invalid terrain can trap or leave non-finite state.** Two positive, 1e-10 pt square rects have no terrain edges. At seed 1, raising the count to twelve and calling `syncFlies()` traps when it indexes the last edge. A rect at x=1.5e308 with width 1e308 and height 900 passes the individual finite checks but has an infinite far edge. The world begins with non-finite butterfly positions and they remain non-finite after a tick. Validate derived bounds and guard edge selection when the terrain has no usable edges. | `MeadowWorld.swift:115`, `:287`, `Terrain.swift:73` | Model input validation | small |
| 8 | **A still pointer in the gap can trigger a landing.** At seed 5 on the 40 pt gap layout in finding 3, feeding (1442, 430) into `pointerMoved` brought a butterfly to `.cursor` after 8.3 s. The sitter was clamped onto the left screen, but the pointer itself was in the gap. The app's desktop router normally provides on-screen input. Guard cursor eligibility in the Meadow world so off-screen inputs cannot start the approach. | `MeadowWorld.swift:492`, `:674`, `MeadowBehaviour.swift:127` | Model input validation | small |
| 9 | **Retaining the public `Flowers` object past its world can crash.** `let f = MeadowWorld(…).flowers` followed by `f.replant(fresh: false, rng: …)` aborts when the callback reads the destroyed world through an `unowned` capture. The same lifetime assumption applies to touch and close. Use weak callbacks or clear them at teardown. | `MeadowWorld.swift:26`, `:94–102`, `Flowers.swift:692` | Callback lifetime | small |
| 10 | **m1's click limit leaves fading flowers uncapped.** With the supported click limit of one, alternating 2,000 clicks between two open spots before the next tick retained 2,000 flower records, one open. After 121 ticks the count returned to one. Fades are skipped by hit detection but counted or traversed by the click, step and paint loops. Bound the fading pool when input arrives faster than the simulation advances. | `Flowers.swift:495`, `:513`, `:594`, `:410` | Flower lifetime (m1) | medium |

---

## Re-review (after fixes)

| # | Fixed / not fixed | Evidence (file:line or check output) |
|---|---|---|
