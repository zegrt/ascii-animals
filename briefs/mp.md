# Brief mp: the rest of the Meadow, in one translation pass

Size: Content (large; judged by the director's eye on films; one review)
Board commit: the commit that adds this brief (main)
Branch: meadow-mp, made from `meadow-m1` (after its fix round 2), with `meadow-m3` merged in

## Objective
The director tuned a live web sketch until they liked it (`Tools/meadow-sketch/meadow.html` on `meadow-sketch` at
4e1b869, about 3,100 lines). Port the rest of it into the app's Swift, in the family's shape, so the Meadow on the
desktop looks and moves like the sketch, and runs **performantly** (the director's word). m1 (air, flowers, clicks
on flowers) and m3 (a ground colour per cell in the shared canvas) are already built; build on them.

This is a translation, not a redesign: when in doubt, do what the sketch does. Don't add rules, tolerances or
behaviour the sketch doesn't have. The director judges fidelity by eye on films next to the sketch, so getting to
a watchable film early matters more than exhaustive proof.

Read: `docs/plans/2026-11-20-meadow-port-plan.md` (especially "Revised the same day"), the inventory
`docs/plans/2026-11-20-meadow-port-inventory.md` (§1 is the sketch section by section with line references; §3 is
the family's shape), WORKBOARD.md (Corrections and Decisions: the director's notes; Review routing for s1, m1 and m3:
rules carried into the port).

## Do
1. **Flight:** the species table and the sketch's flight from above (height z, wingbeat, lurch, zig-zag, glides,
   bob, turning, bank, soft take-off and landing, edges: 0.25 span past real edges, shared edges open, never in a
   gap). Fixed 1/60 s steps; the 7.5 Hz beat cap; nothing depends on the frame rate.
2. **World and behaviours** (`MeadowWorld`): wants (hunger, warmth), waypoints, flower choice and senses,
   approach and touch-and-go, landed poses and small life, gusts, flush and relay, spacing by height, count and
   species mix kept through real edges (leaving and entering, the sketch's fixed rules), the opening moment, the
   cursor landing on a still pointer (the sitter's whole body stays on a screen, even at a corner), clicks calling
   one butterfly at a time, several screens (per terrain rect; crossing touching screens).
3. **Painter** (`MeadowPainter` on `CellCanvas`, with m3's ground): the ground and its green hints, grass, motes,
   flowers and leaves, shadows, depth push and the rim, the butterflies (wings, markings, veins, carved ramp,
   coverage edges, shimmer, body, eyes, legs, antennae, proboscis), dark and paper palettes, Calm. Port the
   sketch's hash so glyph and shimmer patterns match.
4. **Habitat for tools:** `.meadow` in `HabitatKind`/`HabitatSim` and a `MeadowSim` (as Web's `WebSim`), usable by
   `OceanTool still|frames|bench --habitat meadow`, with the minimal `.meadow` switch cases the app needs to
   compile. **Not offered in the app** yet (the `offered` list is unchanged; m8 does that).
5. **Performant:**
   - `OceanTool bench --desk --habitat meadow` costs no more CPU than `--habitat web` on the same desk sizes at 30
     and 15 fps (report both).
   - Nothing allocated per frame once warm.
   - Cache what doesn't move (the ground; each flower's cells until its head moves about a quarter cell).
   - Sample the air on its grid once per step rather than per grass cell; rasterise each wing once per frame.
   - Cull what's off screen.
6. **Checks, only what can hurt** (in `OceanChecks`):
   - Ocean and Web unchanged (the existing checks and digests).
   - Finite on bad input; a 30-minute run stays sane.
   - Nothing allocated per frame.
   - At the director's defaults most butterflies are in the air (the sketch measures about 75 %).
   - Several screens: nothing in a gap, and relayout keeps everyone on a screen.
   - The tiny 340 × 150 viewport works.
   - Deterministic for a seed.
   - The bench budget above.
   Keep m1's checks.

## Output and done when
Code on `meadow-mp`; `swift build` (including the app) and `swift run -c release OceanChecks` pass, with the output
in `reports/mp.md`. For the director, side by side with the sketch at the same seed and size (render the sketch
headless):
- a 30 s film at real speed in dark;
- a 30 s film at real speed in light;
- a 10 s film at quarter speed;
- a 30 s film at 15 fps;
- stills of a butterfly sheet and a flower sheet.

Watch them and say in the report where the app still differs from the sketch. Bench numbers against Web. Board
Project rules apply, including the CI Swift 6.3.3 typing rule. No local folder paths in commits or files; film paths
only in the final message.

## Out of scope
Offering the Meadow in the app, presets and settings UI (m8), the welcome and what's-new (t9), energy measured on
the desktop (t8). Monarch life cycle and courtship (dropped from 3.1).

## Fix round 1 (from the review, 2026-11-20)
Read `git show origin/review-mp:reviews/mp.md` and the board's routing (Review routing, mp). Fix findings 1–10 and
the review's "What is missing", on `meadow-mp`. Stay out of m8's Files (board, m8 row): `Domain/{HabitatKind,Settings}`,
MeadowSim's settings hooks, and the app's Presets, SettingsView, StatusMenu, OceanStatus, SettingsStore. `Terrain.swift`
may get a guard if finding 7 needs one, without changing Ocean or Web (prove with the digests and stills).
Each fix comes with the check that would have caught it (the review's probes). Keep the Meadow within Web's CPU.
Add a "Fix round 1" section to `reports/mp.md`.

## Fix round 2 (from the re-check, 2026-11-21; small)
Read `git show origin/review-mp:reviews/mp.md` ("Re-review" and "What is missing after fixes"). Fix, each with a
check that fails without the fix, and stay out of m8's Files:
1. Finding 2's corner: a zero-length clip at an exact screen corner counts as crossing the gap.
2. Finding 4: relayout also projects departing flyers that ended up off the surviving screens, and revalidates an
   approach's route (not only its target) for the new geometry.
3. Finding 8: an approach or a sitter ends when the pointer leaves the terrain, however small the move.
4. No allocation while newcomers arrive after a count change: a Meadow-local, allocation-free edge-distance scan
   instead of `Terrain.signedOutside` (leave `Terrain` unchanged); cover the arrival phase in the allocation check.
5. Initial butterflies are spread across screens that can't reach each other (a real gap), when the count allows,
   so no display starts empty.
Single-screen Meadow, Ocean and Web unchanged; within Web's CPU. Add a "Fix round 2" section to `reports/mp.md`.
