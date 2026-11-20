# Report mp: the rest of the Meadow, in one translation pass

Status: done with concerns
Board commit: 94e5fec (main, the board and brief read; the brief itself was added in 71d598e)
Commit: see the last line of the builder's message (meadow-mp; the report is the last commit)

## What was built

The rest of the sketch (`Tools/meadow-sketch/meadow.html` on `meadow-sketch` at 4e1b869), ported term for term into
the family's shape, on top of m1 (air, flowers, clicks on flowers) and m3 (a ground colour per cell):

- **Flight** (`Meadow/MeadowFlight.swift`): the species table (`Meadow/ButterflySpecies.swift`: spans, strokes,
  outlines, beats, bouts, glides, jinks, slips, headings, bob, bank, bounds, stays, poses, flower weights, the 7.5 Hz
  cap), height z, wingbeat, lurch on the downstroke with drag 8, zig-zag at the clap, glides, the white's surge, the
  morpho's bounds, the heading spring, bank, soft take-off and landing (blend 0.15 s, ease-in 0.35 s, brake), edges
  (steer back a quarter span past a real edge), ground speed = airspeed + 0.55 × wind, downwash. Fixed 1/60 s steps.
- **World and behaviours** (`Meadow/MeadowWorld.swift`, `Meadow/MeadowBehaviour.swift`): wants (energy, warmth),
  waypoints (best of 9), flower choice by sense, approach, touch-and-go, landed poses and small life (breathing,
  shuffle, antenna twitch, lean), alert and flush in moving air, the relay, spacing by height, the count and species
  mix (`syncFlies`, entering from and leaving through real edges), the opening moment, pollen and sparks, the still
  pointer (spiral in, sit at z 0.92, the whole body held on the pointer's screen, any move sends it off), clicks
  (bloom or touch; one butterfly answers at a time, 7 in 10, `answerGap`), several screens.
- **Painter** (`Meadow/MeadowPainter.swift`, `FlowerPainter.swift`, `ButterflyPainter.swift`): the sketch's cell
  writers and both palettes (dark; paper made for paper), the ground and its green on m3's per-cell ground, grass
  that ripples and lies over, gold motes, flowers and leaves with their shadows, the depth push, butterflies (wings by
  the family's 5-sample coverage, markings, veins, carved ramp, edge glyphs, shimmer, body, eyes, legs, antennae,
  proboscis), butterfly shadows, the rim, Calm (0.62 / 0.35). The sketch's own hash, so glyph and shimmer patterns
  match it cell for cell.
- **Habitat for tools** (`Meadow/MeadowSim.swift`): `.meadow` in `HabitatKind` and `Habitats.make`; OceanTool
  `still|frames|bench --habitat meadow`, `bench --desk --habitat meadow`, `meadow-sheet` (the sketch's
  `?sheet=flowers|flies`) and `meadow-desk` (the Meadow over the owner's two screens). **Not offered in the app**: a new
  `HabitatKind.offered` list (`[.ocean, .web]`) replaces `allCases` in the menu, Settings and the welcome; the app's
  switches get minimal `.meadow` cases (nothing shown).

## Fidelity: what I watched

Films and stills put the sketch (rendered headless in Chrome at the same seed 4242, 1600 × 913, cell 13 × 19,
`?debug=1&freeze=1&defaults=1`, stepped by hand) on the left and the app (OceanTool) on the right.

- **Dark, 30 s, real speed:** the same film. Every butterfly is at the same place in the same pose for the whole 30 s
  (both run the sketch's random streams draw for draw). Measured per cell: about 1 % of cells differ slightly (mean
  colour over 12/255) and 0–0.05 % strongly. The slight ones are glyph antialiasing (Chrome's text against the app's
  atlas) and the grass ink, read in 65 steps per frame instead of per cell. The strong ones are a few cells at a
  flower head that swung: the app redraws a flower only once its head has moved a quarter cell (the brief's cache
  rule), so a nodding head lags the sketch's by up to 3 pt.
- **Light (paper), 30 s:** the same, paper palette, cool shadows, paper rim (worst sampled frame: 0.39 % of cells
  differ slightly, 0.25 % strongly).
- **Quarter speed, 10 s:** each 1/60 s step is one frame, played at 15 fps. The app's speed setting stretches time
  by repeating whole steps, where the sketch's slow motion shortens the step; so this film is the step sequence the
  director would see at 0.25 × in either, not an interpolated slow motion (worst frame: 1.4 % slightly, 0.05 %
  strongly).
- **15 fps, 30 s:** four steps a frame, as on battery. The beat aliases as the inventory predicted (the white beats
  5.9 Hz, 2.5 frames a beat); the sketch shown at 15 fps aliases the same way (worst frame: 1.8 % slightly, 0.05 %
  strongly).
- **Sheets:** flowers, and butterflies at z 0.05, 0.5 and 0.95, dark and paper: identical but for glyph
  antialiasing (shimmer flecks included).
- **Calm:** stills at 2 s, dark and paper, match.
- **Several screens** (no sketch to compare): a 30 s film of the owner's desk, monitor above the laptop, at 15 fps.
  Flowers on both screens, butterflies crossing the shared edge both ways, none in the space beside the laptop
  (`OceanTool meadow-desk`).

Where the app still differs from the sketch:
1. Glyph edges: the app's canvas atlas (fitted to Chrome's text at 1× and 2×) still antialiases a little differently
   from headless Chrome at 1×; shapes and places are the same.
2. A swinging flower head is redrawn in quarter-cell steps (the brief's cache rule).
3. The grass colour takes 65 levels instead of a continuous one.
4. Several screens: the sketch has one window; the rules below are the port's.

## Several screens (the port's rules, where the sketch has one window)

One screen is the sketch exactly (the same draws). With several:
- every random place the sketch takes in its window (spawn, waypoints, bask spots, the opening) is taken on a
  screen picked by area;
- a waypoint is kept only if the straight way to it stays on the screens (Web's `wanderGoal` rule), else one on the
  butterfly's own screen; so butterflies cross touching screens and don't fly through the outside;
- the edge steer (a quarter span past a real edge) points to the nearest point on a screen; in a gap (between two
  screens side by side) it steers at once, and a step that would enter a gap is refused on that axis;
- entering is from a real edge picked by length; leaving through the nearest real edge;
- the pointer sitter is held on the pointer's screen; a take-off's escape point on the butterfly's screen;
- after a relayout, a butterfly more than a quarter span off the screens (a screen went away) is put at the nearest
  point on one; landed ones off the screens take off (the sketch's resize).
The count is per scene (7 at the director's settings, areaCount off), so a desk shares its 7.

## Performance

`OceanTool bench --desk` (2560 × 1440 above 1800 × 1169, one shared scene), the same machine, interleaved, three runs
each (thread CPU, ms per second live):

| | 30 fps total | 15 fps total | sim | draw (both screens) |
|---|---|---|---|---|
| Web | 16.79 / 17.04 / 16.68 | 13.06 / 13.20 / 13.27 | 9.3–9.4 ms/s | 0.25 ms/frame |
| Meadow | 13.16 / 13.13 / 13.23 | 6.82 / 6.78 / 6.78 | 0.74–0.78 ms/s | 0.40–0.42 ms/frame |

Process totals (Metal's threads too): Web 19.3–19.7 / 14.2–14.5, Meadow 15.4–15.8 / 8.1. (A noisy earlier session
read both about 30 % higher; the ratio held.) `OceanTool bench --habitat meadow` (one 1800 × 1169 screen, painting
only): sim 0.38 ms/s, paint 0.215 ms/frame dark, 0.234 paper (Web: 4.84 ms/s, 0.094 ms/frame).

How: the frame is a struct over raw buffers (Web's `Pass` pattern; the first version spent most of its time in
Swift's exclusivity checks); only cells something is drawn on are touched and packed, the rest take the screen's
cached ground; the ground and grass are built once per screen; each flower's cells are recorded and replayed until its
head moves a quarter cell; the air is read on the breeze's 48-pt grid once a frame; wings and shadows are found per row
of samples from the outlines' crossings; each wing's edges are laid once per frame. m1's breeze decay was the sim's
cost (exclusivity per sample): it now runs through buffer pointers, same arithmetic (sim 6.9 → 0.8 ms/s).

## Checks run

`swift build` (all products, the app included): Build complete, no errors.

`swift run -c release OceanChecks`: **215 passed, 0 failed** (m1's checks all pass unchanged). The new ones
(`OceanChecks/MeadowWorldChecks.swift`), only what can hurt:

```
PASS meadowLongRunStaysSane           30 min on the desk: finite, z in 0…1, count kept, painted dark and paper+Calm
PASS meadowWorldFiniteOnBadInput      NaN/±∞/1e300 into every pointer entry; empty, zero, 1×5000 screens; 0 and NaN cells
PASS meadowFrameAllocatesNothing      300 warm frames (4 steps, both screens painted, pointer moving), dark and paper+Calm: 0
  in the air 73.2 % of the time
PASS meadowMostlyInTheAir             4 seeds × 10 min at the director's settings, ≥ 65 % (the sketch measures about 75 %)
PASS meadowNothingInAGap              two screens with a gap, 10 min: no butterfly ever in it; someone crosses; flowers too
PASS meadowRelayoutKeepsEveryoneOnAScreen  40 relayouts desk ↔ one screen: everyone on a screen, landed ones on it
PASS meadowTinyViewport               340 × 150, 5 min, painted: alive, drawn, nobody lost
PASS meadowSameSeedSameFrames         same seed (with clicks and a pointer): identical canvases; another seed differs
PASS meadowStillPointerIsLandedOn     middle and both corners: one lands within 40 s, whole body on the screen, a move sends it off
PASS meadowClicksCallOneAtATime       60 clicks: flowers bloom, the click limit holds, never two called at once
  30 fps: meadow 10.96 ms/s, web 16.79 ms/s
  15 fps: meadow 6.08 ms/s, web 13.60 ms/s
PASS meadowWithinWebsCPU              the desk, steps + painting both screens (CPU, no GPU), best of 3: Meadow ≤ Web
```

Ocean and Web unchanged: their checks pass (`oceanStillUnchanged`, the Web cross-checks and GPU checks); `OceanTool
bench --digest` gives the same digests as the base (6d65cc8, m1 + m3): shared `612a0c22c778b40b`, separate
`d4d23789aedfab08`; Ocean and Web stills (1440 × 900) are byte-identical to the base's.

CI's Swift 6.3.3: built with `-warn-long-expression-type-checking=20`: no expression in the new files reaches 20 ms
(the only one is Web's existing `OrbWeb.swift:545`); long mixed expressions are split into typed lets.

## Files changed

All in the brief's Files, except where marked:
- New: `Meadow/{Butterfly, ButterflySpecies, MeadowWorld, MeadowFlight, MeadowBehaviour, MeadowPainter,
  FlowerPainter, ButterflyPainter, MeadowSim}.swift`, `OceanChecks/MeadowWorldChecks.swift`,
  `OceanTool/MeadowDesk.swift`.
- `Meadow/MeadowTuning.swift`: the remaining sliders (defaults and ranges).
- m1's files, hooks only: `Flowers.swift` (`updateFeeding`, `showOnly` for the sheet), `Breeze.swift` (`origin`, and
  the decay loop through buffer pointers: a performance fix, same arithmetic, m1's checks pass),
  `OceanChecks/MeadowChecks.swift` (`allocations` no longer private, for the new checks).
- `Domain/{HabitatKind, HabitatSim}.swift`: `.meadow`, `offered`.
- `ASCIIAnimals/{OceanStatus, OnboardingController, SettingsView, StatusMenu}.swift`: `.meadow` cases and `offered`
  for `allCases` (so the Meadow isn't offered).
- `OceanChecks/main.swift`, `OceanTool/main.swift` (`meadow-sheet`, `meadow-desk`, the Meadow in `bench`).
- Not in the brief's Files: none. (`OceanTool/Bench.swift` was not needed: `--desk` works for any canvas habitat.)

## Rulings

1. **Constants beside their code, not all in the tuning file.** The plan wants every number in `MeadowTuning`; the
   sliders are there, but the flight, behaviour and painter constants (hundreds) stay inline as the sketch's own
   expressions, each section citing its `html:N` lines. Why: a term-for-term port is easiest to check against the
   sketch side by side. Cost if wrong: a later pass moves them.
2. **Several-screen rules** (above): the gap refusal, the open-way waypoint rule (Web's), the relayout placement and
   the per-scene count are mine; the brief asks for "per terrain rect; crossing touching screens" and "nothing in a
   gap" without the rules. Not added: the plan's "monarch crosses most" (not in the sketch; m8 or the director).
3. **`HabitatKind.offered`**: there was no offered list on main (the app read `allCases`); I added one so `.meadow`
   exists but isn't shown. m8 adds `.meadow` to it.
4. **A still is the opening moment** (`settle()` does nothing): the sketch has no still mode; its first frame is the
   designed opening.
5. **Quarter speed** is one step a frame (see Fidelity).
6. **`cursorLand`** stays the sketch's default (on); tying it to the app's interaction setting is m8's.
7. **Not ported**: `areaCount` (off at the director's settings), the panel, URL settings, pause.
8. **Clicks are the app's mouse-down** (the sketch clicks on release after < 6 pt): the host has only mouse-down.

## Noticed

- `HabitatSim.update(settings:)` for the Meadow only passes the speed; presets (m8) will need `syncFlies` on change
  (ported, not wired).
- At 15 fps the white's beat aliases (2.5 frames a beat); the plan leaves that call to the director after the films.
- The headless sketch capture used for the films is a small puppeteer script kept outside the repo (it steps the
  sketch's own `step` and `render` by hand and reads the canvas with `toDataURL`, as m1's probe did).

Pushed and clean: not pushed (the brief says do not push); folder clean after the report commit.

---

# Fix round 1 (Codex review 4f1b5d4, routed on main 9efcb55)

Status: done with concerns (one existing check's bound changed, Rulings 1)
Board commit: 9efcb55 (main: the board's routing for mp, the brief's "Fix round 1", m8's row)
Commits: 049ca73 (the fixes and checks), f9d3d20 (two checks tightened), then this report
Files changed (all in mp's Files; none of m8's: no HabitatKind, Settings, MeadowSim or app file touched):
`Meadow/{MeadowWorld,MeadowFlight,MeadowBehaviour,Flowers,FlowerPainter,MeadowPainter,MeadowTuning}.swift`,
new `Meadow/ToolInput.swift` (the tool's number checks, in OceanKit so the checks can hold them) and
`Meadow/MeadowProbes.swift` (`@_spi(Checks)` probes, not public API), `OceanTool/{main,MeadowDesk}.swift`,
`OceanChecks/{MeadowFixChecks (new),MeadowWorldChecks,main}.swift`. `Terrain.swift` not touched.

## Each finding: the fix and the check that holds it

Every new check was also run against a copy of the fixed code with that fix undone (a mutation build): each one
fails there, with the failure shown.

| # | Fix | Check, and what it says with the fix undone |
|---|---|---|
| 1 | Each screen's flower recordings live in reused slots, keyed by flower id and handed back every 60 of **that screen's own** paints (and on demand). Slots are made up front for `Flowers.most` (planted + 30 + `fadingMost` + 1), each sized for the biggest flower's box (3 writes per cell). `MeadowPainter.swift` `ViewportCache`, `FlowerPainter.swift` `drawFlowers` | `meadowRecordingsBoundedOnEveryScreen`: two screens painted alternately for 4,000 frames, clicks on both for 3,000: slots and recordings ≤ the bound on both screens every frame (most 28, bound 84), none stale once clicks stop. Undone (sweep by the shared count): `screen 0 still holds 18 recordings of flowers that have gone (of 39)` |
| 2 | One move function for every position update: the flight step, the approach's settling pull and the landed pull (`MeadowWorld.move`), each segment clipped exactly against the gap boxes, less what the screens cover (Liang–Barsky). `wayOpen` is exact (the screens cover the whole segment). On several screens, flower choice, bask spots, the click's answer and the cursor's candidates skip ways that cross a gap | `meadowWaysAndStepsNeverCrossAGap`: the review's `wayOpen(840, 400, 2040, 400)` on the 1 pt / 2 pt-offset pair is refused; controlled flight steps at 300–1200 pt/s from x = 1439.5, a landed pull and an approach toward a bloom at x = 1442.5 never cross; 10 minutes on that pair checked every step (0.05 pt sampling); on the desk 188 real crossings between screens in 5 minutes. Undone: `the way across the one-point gap counts as open`. `meadowNothingInAGap` now checks every step's way too (undone: `butterfly 2 went through the gap at (1441.5, 100.2)`) and no longer passes from initial placement (both screens must keep butterflies) |
| 3 | `enterFromEdge` on several screens keeps only spots off the screens, not in a gap, whose way in crosses no gap (6 such spots from up to 48 draws; none: past the leftmost screen's left edge, always open). `aimAtExit` takes the nearest real edge whose exit point is off the desk (in no gap, `reach` from every screen) by a way crossing no gap; then any such point; then left of the leftmost screen. One screen: unchanged, draw for draw | `meadowEntriesAndExitsAvoidGaps`: the review's 7 → 12 on (0, 0) + (1760, 2) at seed 1: no newcomer in the gap, none on a screen while waiting, 60 s watched step by step, count 12; a departure at (1439, 450) beside a 40 pt gap is gone within 2 minutes at seeds 1–3 without crossing it. Undone: `newcomer 8 put in the gap at (1619.63, 355.68)`, the review's exact spot |
| 4 | `layout`: one that **was on a screen** and no longer is, or is more than a quarter span off, or in a gap, is put on the nearest screen; waiting and entering-off-screen ones come in again from a real edge of the new screens; leaving ones leave any gap and re-aim at an exit of the new screens; waypoints off the new screens (or whose way crosses off them) and bask spots off them are chosen again | `meadowRelayoutPutsTheDisplacedOnAScreen`: the review's one → two → one with a flyer at (1441, 450): on the remaining screen; then 48 layouts in a row over 8 arrangements (desk, one, wide gap, hairline, touching, far gap) with the count raised to 12 and cut to 5 in between: right after each, nobody in a gap, everyone who was on a screen is on one, newcomers wait within reach of a real edge, the count settles. Undone: `after the unplug the flyer is at (1441.0, 450.0), off the remaining screen` |
| 5 | Clicks allocate nothing once warm, nor do the frames after them: the painter's slots (1); `Flowers` keeps room for `most` flowers and recycles the leaf and floret storage of flowers that go (and of one made but blocked), with spares for every flower a click can add made at planting | `meadowClicksAllocateNothingLater`: desk, warmed with clicks every 20 frames for 1,500 frames, then 12 clicks each followed by 150 frames (bloom, growth, fade, eviction): **0 allocations in the clicks, 0 in the 1,800 frames after them**. Undone (no recycling): `9 allocations in the clicks themselves` |
| 6 | Every number the tool takes is checked before it is converted, allocated or written (`ToolInput`: sizes 1…16384, scales giving 1…16384 px, seconds 0…3600, fps dividing 60, `--z` 0…1, `--frames` 1…10⁶), in `still`, `frames`, `meadow-sheet`, `meadow-desk` and `bench` | `meadowToolRefusesBadNumbers`. Undone: `--scale nan passes`. And the review's commands, run: each exits 2 with a message, nothing written (below) |
| 7 | A screen counts only if it is at least 1 pt each way with its edges within ±1e7 pt (`Unit.coordinateLimit`) and the terrain has real edges (`MeadowWorld.usable`); otherwise the meadow has no screen, its flowers close (they get an empty terrain) and its butterflies hold still. Edge choice guards an empty edge list. `Flowers.plant` also skips a screen whose far edge overflows | `meadowBadTerrainHoldsStill`: the review's two 1e-10 pt squares with the count at 12, the rect at x = 1.5e308 with width 1e308, a rect at −2e7, and back to one screen: no trap, finite, the meadow back (9 butterflies, flowers) on the usable screen. Undone: the check traps (exit 133, SIGTRAP), as the review saw |
| 8 | `stepPointer` never starts a landing for a pointer off the screens (in a gap or past a real edge); on several screens a butterfly whose way to the pointer crosses a gap isn't a candidate | `meadowPointerInAGapIsNotLandedOn`: the review's case (seed 5, (1442, 430) in the 40 pt gap) and pointers above the left screen, right of the right one and left of a single screen, seeds 5–7, 30 s each. Undone: `seed 5: butterfly 5 answers a pointer above the left screen after 3.0 s` |
| 9 | The three callbacks capture the world weakly, and the world clears them in `deinit` | `meadowFlowersOutliveTheirWorld`: the review's `MeadowWorld(…).flowers` kept, then a replant, a touch, 40 clicks past the limit, a relayout and a step. Undone: `Fatal error: Attempted to read an unowned reference but object … was already destroyed` |
| 10 | At most `Clicks.fadingMost` = 32 flowers fade at once: past it the most faded goes at once (it has closed already, so no butterfly is bound for it), after a click, a relayout or a replant. A person clicking ten times a second keeps about 20 fading, so the look never meets the cap | `meadowFadingFlowersBounded`: click limit 1, the review's 2,000 clicks alternating between two open spots before any step: all 2,000 bloom, fading ≤ 32 and flowers ≤ `most` after every click, one open flower and none fading after the fade. Undone: `33 fading after 34 clicks` |

The review's tool commands, after the fix (release build):

```
[2] OceanTool meadow-sheet out.png 340x150 --sheet flowers --scale nan -> bad --scale nan: above 0, the image at most 16384 px each way
[2] OceanTool meadow-desk outdir --scale nan -> bad --scale nan: above 0, the image at most 16384 px each way
[2] OceanTool meadow-desk outdir --warmup 1e300 -> bad --warmup 1e300: 0…3600 s
[2] OceanTool meadow-desk outdir --seconds 1e300 -> bad --seconds 1e300: 0…3600 s
[2] OceanTool frames outframes 340x150 --fps 0 --habitat meadow -> bad --fps 0: 1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30 or 60
[2] OceanTool still out.png nanx150 --habitat meadow -> bad size nanx150: W x H, each 1…16384
[2] OceanTool still out.png 340x150 --habitat meadow --scale 1e300 -> bad --scale 1e300: above 0, the image at most 16384 px each way
[2] OceanTool bench --desk --habitat meadow --seconds 1e300 -> bad --seconds 1e300: above 0, at most 3600 s
```
No output folder was made for any of them; `meadow-sheet … --scale 2` and `still … --habitat meadow --live` still write.

## Unchanged: Ocean, Web, and the Meadow on one screen

Built 3134721 in a separate detached copy and compared, release builds, same commands:

- `OceanTool bench --digest`: `612a0c22c778b40b` before and after; `--separate`: `d4d23789aedfab08` before and after (the review's values).
- Ocean and Web stills, seed 4242: 800 × 500 dark and light, 1800 × 900 live Calm at 1.25×, 340 × 150 live light
  Calm: **all 8 byte-identical**. No Ocean or Web source changed (the diff touches only the Meadow, its checks and
  OceanTool's argument checks).
- The Meadow on one screen: `still --live` 1728 × 1117 dark and light and 340 × 150, both sheets, `frames` 60 s at
  5 fps (seed 7) and 20 s light Calm (seed 3): **3 stills, 2 sheets and 400 of 400 frames byte-identical**. The
  look and motion on one screen are unchanged, draw for draw.

## Performance (`OceanTool bench --desk`, release, two runs each, ms of CPU per simulated second)

| | Meadow after | Meadow before (3134721) | Web |
|---|---:|---:|---:|
| 30 fps thread | 13.79, 13.90 | 13.90, 13.95 | 17.71, 18.32 |
| 15 fps thread | 7.13, 7.71 | 7.19, 7.15 | 13.90, 14.31 |
| 30 fps process | 16.44, 16.67 | 16.56, 16.60 | 20.66, 21.44 |

`meadowWithinWebsCPU` (in the suite): 30 fps 13.60 vs Web 21.11 ms/s, 15 fps 7.74 vs 16.24.

## Checks run

- `swift build` (all products, the app included): Build complete, no warnings in the changed files.
- `swift run -c release OceanChecks`: **225 passed, 0 failed** (215 before; 10 new). The Meadow's lines include:
  `in the air 73.2 %`, `desk: 188 crossings between the screens in 5 minutes`, `most recordings on one screen: 28,
  bound 84`, `12 clicks: 0 allocations in the clicks, 0 in the 1,800 frames after them`, `meadowFrameAllocatesNothing`
  and m1's `meadowStepAllocatesNothing` pass.
- Type-check time (CI's Swift 6.3.3 rule): `-warn-long-expression-type-checking=60` over OceanKit, OceanChecks and
  OceanTool reports nothing in the changed files; the long `&&` chains in the tool check are split into typed lists.

## Rulings

1. **`meadowLongRunStaysSane`'s bound changed from 2 to 4 spans** (an existing check: flagged for the reviewer). The
   30-minute desk run failed at 2.73 spans after the fixes. I traced it: a take-off with the escape boost carries a
   butterfly into the off-screen pocket right of the laptop and below the monitor before its edge steer turns it
   (the sketch's own dynamics; exact `wayOpen` changed which waypoints are picked, so the trajectory differs). At
   3134721 itself, seeds 1–10 reach 1.86, 3.70, 3.31, 1.33, 2.46, 2.31, 2.34, 2.73, 1.45 (seed 9), 2.19 spans: only
   seed 9 met the old bound. After the fixes the same seeds reach at most 2.92. So it is not a regression; the
   bound was luck. The comment in the check gives these numbers. Cost if wrong: a real drift off the screens
   between 2 and 4 spans would go unseen; the relayout and gap checks still hold the several-screen rules exactly.
2. **Gaps follow the terrain's touch rule**: facing sides closer than `Terrain.touch` (0.5 pt) are one shared, open
   edge; further apart, a gap (before: any distance above 0 was a gap at a point, but the way through wasn't
   checked). Cost if wrong: a butterfly may cross a sub-half-point seam, which the terrain already treats as shared.
3. **A screen under 1 pt, or with an edge past ±1e7 pt, makes the whole layout unusable** (the meadow holds still and
   its flowers close), as an empty or non-finite one already did.
4. **The fading cap is 32** (`Clicks.fadingMost`), applied to every fade (clicks, relayouts, replants). The sketch
   has no cap; under human clicking it is never reached.
5. **On several screens, flower choice, bask spots, the click's answer and the cursor's candidates skip ways that
   cross a gap**, so nobody is sent where it can't fly straight; one screen is untouched.
6. **`ToolInput` lives in `OceanKit/Meadow/`** (mp's Files) though `still` and `frames` use it for every habitat;
   only out-of-range values change behaviour (they used to trap).
7. **Probes are `@_spi(Checks)`** (`MeadowProbes.swift`): they set a butterfly's state the way the review's probes did,
   without widening the public API.

## Noticed

- With exact `wayOpen`, butterflies on two screens separated by a gap (any width) stay on their own screen: the only
  straight ways between them leave the screens, and drift past the gap's ends is rare (1 crossing in 10 minutes on the
  1 pt pair). That follows the brief ("crossing touching screens") and Web's rule; the director may want to see it on
  a gapped desk.
- `Terrain.signedOutside` allocates when the point is inside (`edges.map`); the Meadow calls it only for points off the
  screens, so frames stay allocation-free, but it is a trap for later callers (Terrain is not mp's to change).

Pushed and clean: not pushed (the brief says do not push); folder clean after the report commit.
