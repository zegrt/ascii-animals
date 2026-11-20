# Brief t5v: a film of the butterflies flying

Size: Content (small: OceanTool only)
Board commit: the commit that adds this brief (main)
Branch: meadow-t5v, made from `meadow-t5r` (tasks stack; nothing merges into main yet)

## Objective
The director has seen only stills and path diagrams. Before behaviours (t3) are built, they watch the butterflies
move, at real speed and slowed down, and decide per species how realistic the motion should be (board decision of
2026-11-20: the realism line is set after this film).

## Output
`OceanTool meadow-frames` and three films (H.264 .mp4, made with ffmpeg from the frames), plus `reports/t5v.md`
describing what each film shows. Films are not committed; give their absolute paths only in your final message.

## Tools and sources
- `OceanTool frames` (how the Ocean and Web habitats write frame sequences) and `OceanTool meadow-still` (t5's
  scene: land, breeze, butterflies flown toward random flowers).
- ffmpeg: `ffmpeg -framerate F -i f%05d.png -c:v libx264 -pix_fmt yuv420p -crf 18 out.mp4`.

## What to build
`OceanTool meadow-frames <dir> <W>x<H> [--seconds S] [--fps F] [--slow K] [--light] [--seed N]`: the
`meadow-still` scene stepped at the fixed 60 Hz, one PNG per frame named `f%05d.png` (five digits), `--slow K`
stepping only 1/K of the time per frame (slow motion). Free flight plus flights to random flowers, as the still
does, with natural weather; no behaviours (that is t3). Same validation as `meadow-still`.

## Films
1. 1440 × 900, dark, 30 s at 30 fps, real speed, all four species (about 8 butterflies).
2. The same scene, 10 s of film at 1/4 speed (`--slow 4`).
3. 1440 × 900, light, 15 s at 30 fps.
Watch each one yourself before reporting, and say in the report how each species moves at a glance: wingbeat,
glides, bob, zig-zag, turns, how it reacts to gusts. Report anything that looks wrong (jitter, flicker, popping,
butterflies stuck at edges, overlaps), but don't fix the flight or the painter: it goes under Noticed for the
director's watch.

## Files
Create `Sources/OceanTool/MeadowFrames.swift`; modify `Sources/OceanTool/main.swift` (the command and its usage
line). Nothing in OceanKit.

## Done when
The command works; the three films are made and watched; the whole suite still passes
(`swift run -c release OceanChecks`); the report holds no local folder paths.

## Out of scope
Any change to the flight, the painter, the flowers or the checks. Behaviours (t3).
