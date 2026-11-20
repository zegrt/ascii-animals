# Brief t5w: both wings beat together

Size: Content
Board commit: the commit that adds this brief (main)
Branch: meadow-t5w, made from `meadow-t3` (tasks stack; runs after t3 because both change MeadowPainter.swift)

## Objective
The director, watching the first films: "it looks like onyl the left wing is moving and the right wing dissapears
on motion towards close". At the top of each wingbeat the painter folds the wings into one solid pair on one side
of the body (t5 restart's side profile), so one wing seems to vanish every beat. Make the wingbeat read as two
wings beating together.

## What to change
- **In flight, both wings stay visible and move in step.** From open to the top of the beat, the left and right
  wings narrow together toward the body and come back out together. At the top of the beat they stand as a solid,
  narrow pair, one on each side of the body (body and antennae visible between them), in the underside colours
  blending in as before. No beat ever shows only one wing.
- Banked flight may still make one wing narrower than the other (that's the model's signed width), but never makes
  one disappear outright except in a hard bank where the far wing is edge-on (column 5 of the pose sheet).
- **At rest** (perched, wings closed for seconds, the poses past flight's reach): keep the solid side profile for
  now; the director judges it in the next film.
- Keep: the open poses, colours and markings, no per-frame allocation, the flicker rule, every check (none
  loosened). Checks that assert the one-sided fold in flight (`foldedSideNeverFlips` and any like it) describe the
  design being replaced: name them in the report and replace them with checks of the new rule (both wings present
  on every flight frame, each at least a third of its open width at the top of the beat); the director's correction
  is the authority for that change.

## Output and done when
Code on `meadow-t5w`; the whole suite passes; new pose sheets (dark and light) and a 10 s quarter-speed film and a
30 s real-speed film at 1440 × 900 (`OceanTool meadow-frames`), watched and described in `reports/t5w.md`. No local
folder paths in commits or files.

## Files
`Sources/OceanKit/Meadow/MeadowPainter.swift`, `Sources/OceanChecks/MeadowChecks.swift`.

## Out of scope
Behaviours, flight, flowers. Anything else goes under Noticed.
