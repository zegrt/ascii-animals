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
