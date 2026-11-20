# Report t5v: a film of the butterflies flying

Status: done
Board commit: 36482a7 (main, "board: t5v briefed"; read at 97bfdbe)
Commit: 298dc66 (the command); this report on top of it, on `meadow-t5v` (made from `meadow-t5r` @ 56d339e)
Files changed: `Sources/OceanTool/MeadowFrames.swift` (new), `Sources/OceanTool/main.swift` (the command, its usage
lines, and the `<W>x<H>` check moved into `meadowSize`, now shared by `meadow-still` and `meadow-frames`). Nothing
outside Files; nothing in OceanKit.

## The command

`OceanTool meadow-frames <dir> <W>x<H> [--seconds S] [--fps F] [--slow K] [--light] [--seed N] [--scale N]`

- The `meadow-still` scene: same land, breeze, the still's 8 butterflies (two of each species) made from the same
  random numbers, the same flower-or-roam choice every 3–8 s, natural weather, no behaviours.
- Stepped at the fixed 60 Hz from the first step (no warm-up): frame i shows the world after
  floor(i · 60 / (fps · K)) steps. At real speed and 30 fps that is 2 steps a frame.
- `--slow K` (1–16): each frame shows 1/K of the time. The world still only steps at 60 Hz, so in slow motion a
  state is held over the frames it lasts (at 30 fps and K = 4, every step on exactly 2 frames). Nothing in between
  is made up, so a change that happens in one step shows as one jump: that is what lets the director judge the
  clap. A held state is painted once and its file copied for the repeats.
- Validation: the still's (seconds finite, here > 0 and ≤ 3600; seed a whole number; scale 1–4; the strict
  `<W>x<H>` 64–8192 pt, ≤ 16384 px), plus fps one of 10, 12, 15, 20, 30, 60, K a whole number 1–16, at most
  100,000 frames.
- Defaults: 10 s, 30 fps, K = 1, scale 1, seed 1.

## The films

Made with `ffmpeg -framerate 30 -i f%05d.png -c:v libx264 -pix_fmt yuv420p -crf 18`, all 1440 × 900, 30 fps, seed 1,
126 plants, 8 butterflies. Not committed; their paths are in the builder's final message to the manager.

1. `meadow-1-real-speed-dark.mp4`: dark, 30 s, real speed (1,798 steps).
2. `meadow-2-quarter-speed-dark.mp4`: dark, 10 s of film at 1/4 speed = the first 2.5 s of film 1 (149 steps, each
   on 2 frames).
3. `meadow-3-real-speed-light.mp4`: light, 15 s, real speed.

Same seed, so film 2 is exactly the start of film 1, and film 3 is the same flight as film 1's first 15 s, in light.
Rebuilding all three from the committed code gives byte-identical frames.

## How I watched them

I read stills and step-by-step crops of every film (ffmpeg crops and tiles), and a scratch 60 fps copy of film 1's
first 12 s, so each frame is one step. To find the claps and gusts without guessing, I logged every butterfly's
position, stroke, bank, heading and the breeze at it, every step, from a temporary build: seed 1 for 12 s, seeds
1–6 for 60 s each, and seeds 1–3 with the wind. Then I removed the logging; it is not in the commit. I put the
painter's own formulas (the side blend, tuck and underside sweep from `MeadowPainter.Pose`) over those logs to count
events, then looked at the worst ones. Numbers below are from those logs (12 butterfly-minutes per species unless
said otherwise).

## How each species moves, at a glance

| | Monarch | Morpho | Swallowtail | Cabbage white |
|---|---|---|---|---|
| Drawn span | ~160 pt | ~185 pt | ~160 pt | ~110 pt |
| Wingbeat (clap to clap, median) | 0.37 s | 0.53 s, the slowest | 0.43 s | 0.33 s, quick and even |
| Glides (wings held still ≥ 0.2 s) | 40, average 1.6 s, up to 4.4 s: clear sail-and-flap | 35, about 1 s | 31, about 1.4 s, up to 3 s | 11, about 0.3 s: hardly glides |
| Bob per beat (median, 90th pct) | 12 pt, 36 | 20 pt, 47: the most up-and-down | 12 pt, 35 | 9 pt, 27 |
| Speed (median, 90th pct) | 93 pt/s, 177 | 81 pt/s, 148 | 77 pt/s, 167 | 80 pt/s, 158 |
| Turning (median, 90th pct) | 7°/s, 180: straight lines, then a sharp turn | 25°/s, 193: weaving | 11°/s, 239: straight, the sharpest turns | 23°/s, 204: weaving |
| Turn reversals (zig-zag) | 0.6 a second | 1.0 a second | 0.7 a second | 1.0 a second |

- On screen: the monarch and swallowtail read as purposeful (long straight runs with glides, then a bank and a
  turn). The morpho is a slow, deep, bouncing flap with a brown flash every beat. The white is a fast, even
  flutter that weaves and hardly ever glides. The four are easy to tell apart by motion alone.
- Gusts: the breeze at the butterflies is mostly 20–35 pt/s, with gusts up to ~130 pt/s (top 3% at ≥ 74 pt/s). In
  those gusts the average sideways speed moves downwind by about 50 pt/s for the monarch and the white, 66 for the
  morpho and 21 for the swallowtail, and flight speed drops by 10–25 pt/s. Over all the time the link between the
  wind and their sideways speed is weak (correlation 0.06–0.15). So a gust nudges them and they keep flying their
  own way; it never carries them off. On film it hardly shows.

## At the clap (the top of each wingbeat): what I see

1. **The clap is a snap, every beat, every species.** The open pair turns into the folded side profile (one wing
   pair beside the body, the far pair gone) in one 60 Hz step. It holds for about 5–6 steps (~90 ms), then snaps
   open in one step. It is the same for all four species. At real speed it reads as a blink, not as wings closing
   over the back.
2. **The colour flips in one or two steps, every beat (t5 review finding 2): yes, visible.** The underside sweep
   (`turn`) moves 0.7–0.9 of its whole range in a single step around every clap. Over 6 seeds × 60 s that is
   2,579–4,231 one-step flips per species. The morpho is the loudest: bright blue, then the next step half blue and
   half brown (the tip-first sweep lasts one frame), then solid brown with yellow eyespots, then blue again. In
   dark, every few seconds a brown block flashes somewhere on screen. The monarch, swallowtail and white flip to
   paler undersides (light orange, pale yellow with dark vein dashes, pale green), which is milder. In light, all
   the undersides are close to the cream ground, so the flip is gentler there.
3. **The folded pair jumping sides (t5 review finding 1): yes, sometimes, and visible when it happens.** In most
   claps the side blends slowly. In seed 1's first 12 s, the three claps where the bank crossed level moved
   smoothly (e.g. 0.55 → 0.69 → 0.81). But over 6 seeds × 60 s the fold moved more than half-way across in one
   step 78 times (cabbage white 38, morpho 22, swallowtail 11, monarch 7). That is about one somewhere on screen
   every 5 s. The worst (seed 5, morpho, step 3201 → 3202): the brown folded pair sits left of the body, then is a
   narrow pair right of the body one step later. I saw it plainly in the 60 fps frames. Cause, from the numbers:
   it happens only in fast bank reversals (median 4.1° of bank per step at these events; the top 1% of all bank
   changes are ≥ 4°/step). The painter's side blend is 8° of bank wide, so these reversals cross it in one or two
   steps. About half happen low by the flowers (y ≥ 700 of 900).

## Checks run

- `swift run -c release OceanChecks` (whole suite): `220 passed, 0 failed`.
- `swift build -c release --product ASCIIAnimals`: `Build complete! (17.86 sec)`.
- `swift build -c release --product OceanTool`: `Build complete!`, no warnings from the new file.
- The command's validation, by hand: `--fps 7` → `bad --fps 7: 10, 12, 15, 20, 30 or 60`; `--slow 0` →
  `bad --slow 0: a whole number 1 to 16`; `--seconds nan` and `--seconds 0` → `bad --seconds …: more than 0, up to
  3600`; `10x10` → `bad size 10x10: …`; `--scale 20` → `bad --scale 20: 1 to 4`; `--seed -1` →
  `bad --seed -1: a whole number from 0`. No folder made on a refusal.
- `meadow-still` after the shared size check: `96xx96`, `96x96xgarbage`, `9000x100`, `8000x8000 --scale 3`, `.5x100`,
  `100x100.` all refused with the same message as before; `340x150 --seconds 1` writes its still.
- Slow motion holds states: at 200 × 150, 0.5 s, `--slow 3`, frames 0 and 1 are byte-identical and frames 2 and 3
  differ (2/3 of a step per frame); it reports `9 steps … 1/3 speed`.
- The three films: ffprobe gives 1440 × 900, 30/1 fps, 30.0 s, 10.0 s and 15.0 s. Rebuilt from the final code,
  all frames are byte-identical to the frames the films were made from.
- No local folder paths in the two source files or this report (grep).

## Rulings

- **`--scale N` added** (not in the brief's signature) because `meadow-still` has it and the brief asks for "the
  same validation". Default 1, so the films are 1440 × 900 pixels. Cost if wrong: one unused option.
- **No warm-up:** the film starts at step 0, as the brief says ("stepped at the fixed 60 Hz"). The first second
  shows the butterflies setting off from where they were made. Cost if wrong: an odd-looking first second; a
  `--warmup` option would be a few lines.
- **Slow motion holds the 60 Hz states and makes up nothing between them,** rather than stepping the world with a
  smaller dt. A smaller step would change the flight's physics and would hide exactly the one-step events the
  director is judging. Each held state is painted once, as the app paints each state once; the repeat frames are
  file copies. Cost if wrong: slow motion looks steppy (it is meant to).
- **`meadowSize` shared by both commands:** the still's `<W>x<H>` check moved into a function in `main.swift`
  rather than being copied. Its behaviour is unchanged (checked above).
- **The scene is rebuilt inside `MeadowFrames.run`,** not shared with `MeadowStill.run`, because `MeadowStill.swift`
  is not in this task's Files. It reuses `MeadowStill.Scene`, `MeadowStill.flower` and `MeadowStill.perSpecies`. A
  later change to the still's loop has to be made in both files. Cost if wrong: the two drift apart.

## Noticed

Nothing fixed; all for the director's watch. The two clap items are above (At the clap, 2 and 3).

1. **Butterflies crowd and overlap at the low flowers.** From about 8 s on, most of the eight sit in one or two
   tight stacks just above the flower band, drawn over each other, and the upper half of the screen is empty
   (film 1 from 0:08, and its last frame). This is the still's scene (70% of choices are a flower, all flowers are
   low, nothing keeps butterflies apart), not the app. t3's behaviours will decide it, but nothing yet stops a
   pile-up.
2. **Overlapping butterflies merge into one patch of cells.** Where two overlap, their wing cells interleave, so
   the pair reads as one mottled shape rather than one in front of the other (for example two whites with a morpho
   and a monarch at one flower, seed 1, 11.3–11.5 s).
3. **Cabbage whites spend 17.6% of their time within 60 pt of the bottom edge** (others 3–5%), body at the low
   flowers and wings partly below the screen. That is allowed (board, 2026-11-20) but very frequent for the white.
4. **The far wing as a dotted ghost.** As the morpho opens after a clap, the wing coming up on the far side is
   drawn for a few steps as dim `: . %` dots in dark blue, a speckled ghost beside the solid near wing (film 2,
   around 0:04). It may be meant as the foreshortened wing; at real speed it reads as noise around the morpho.
5. **Low contrast in light:** the cabbage white is pale grey on the cream ground and reads faintly; the light-mode
   undersides (pale tan, pale green) are close to the background, so in light the clap reads as the butterfly
   briefly half-vanishing.
6. **The clap's look is the same for every species** (fold to one side, ~90 ms, snap back). If the director wants
   a gentler flash, the timings live in `MeadowPainter`'s `TUCK_*` / `UNDER_*` / `SIDE_BLEND` constants and the
   speed of the bank reversals in the flight. Both are out of this task's scope.

Pushed and clean: committed on `meadow-t5v`, folder clean after the report commit; not pushed (the manager's
instruction for this run: do not push).
