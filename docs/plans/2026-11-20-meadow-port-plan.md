# Meadow 3.1: porting the sketch to the app (plan, 2026-11-20)

Status: proposal for the director. Nothing is built from it until the director approves it.

## What we port
The director tuned a live web sketch, `Tools/meadow-sketch/meadow.html` on `meadow-sketch`, over six rounds and
said "ok for now", then "dbbl check shit then go". Codex reviewed it (`reviews/s1.md` on `review-s1`); its fixes
are being made in the sketch first (fix round 1), and Codex re-checks them. **The sketch at that re-checked commit
is the original.** The app must look and move like it at the director's settings, in dark, on paper and in Calm.

The full map of the sketch against the Swift code is `docs/plans/2026-11-20-meadow-port-inventory.md` (research r2).
In short: the family shell (habitat, canvas, settings, theme and Calm, clock, power policy, terrain, Web's maths) is
reused; almost all the side-view Meadow code on the task branches (breeze, flowers, flight, painter, most checks)
is replaced, because it assumes a ground band, gravity on screen y and wings seen from the side.

## How we keep it faithful
- **One place for the numbers:** every sketch default and constant goes into one tuning file, named as in the
  sketch, so a number can be traced to its slider.
- **The same clock as the family:** a fixed 1/60 s step (`OceanClock`), never the frame's time; the sketch's
  springs and decays are tuned at that step. The sketch's "slow motion" is the app's existing speed setting.
- **The same randomness:** the sketch's hash and seeded random streams are ported, so a seed gives the same meadow,
  and stills can be compared with the sketch's cell by cell.
- **A replay fixture** (from the review): the sketch exports a seed, settings, viewport, cell size and a timed pointer
  trace with expected samples; the Swift checks replay it.
- **Judged by eye:** every painter and world task ends with stills or films next to the sketch's at the same seed,
  dark and light, for the review and the director.
- Pointer air is computed once per step from the position change (as Web does), never per input event.

## The tasks (a fresh stack from main)
Each task's branch is made from the previous one's; nothing merges until the whole Meadow is approved (the
director's rule). The side-view branches (t1-2, t5/t5r, t5v, t3, p1, p2a) are superseded: they stay as references
and are deleted at the end with the director's OK. Each task gets a brief, a builder, a Codex review and its CI run.

| # | Task | What it proves |
|---|---|---|
| m1 | **Air and flowers from above** (breeze, pointer air, downwash, flowers, planting, clicks on flowers, the tuning file) | same seed, same meadow; the same pointer path gives the same air at 15–120 Hz; clicks never stack; no flower in a gap between screens |
| m2 | **Flight from above** (species, height z, wingbeat, lurch, zig-zag, glides, turning, edges) | the sketch's numbers: beat, lurch pulse, glide share at 0.1, z in range, covers the screen, body never in a gap |
| m3 | **A ground colour per cell** in the shared canvas (only if the director approves; see Q1) | Ocean and Web draw exactly as before |
| m4 | **Painter: the meadow** (ground, grass, motes, flowers, leaves, shadows, depth push, shimmer, Calm, paper) | stills next to the sketch's flower sheet, dark and light; nothing allocated per frame |
| m5 | **Painter: the butterflies** (wings, markings, veins, carving, shimmer, body, eyes, legs, antennae, rim, shadow) | sheets next to the sketch's butterfly sheet at three heights and four wing phases |
| m6 | **World and behaviours** (wants, flower visits, touch-and-go, landed life, gusts, flush and relay, spacing, entering and leaving through real edges, the opening moment, several screens) | ≥ 70 % of the time in the air at the defaults; long run stays sane; 60 s films at 30 and 15 fps |
| m7 | **Pointer and clicks** (hold still and one lands on it, stirring flushes, clicks touch or bloom, one answer at a time) | the review's pointer scenarios replayed; never lands outside the screens |
| m8 | **The Meadow habitat** (`.meadow` in the app, its settings, OceanTool support) | Ocean and Web unchanged; tiny viewport; screens added and removed |

Then the original plan's last steps, unchanged in shape: **t7** the director watches the films (a gate), **t8**
energy measured with the director, **t9** the Meadow in the menu, Settings and welcome, **t10** words, watch and
release (the director approves the release).

m3 runs beside m1 and m2 (different files). Files never overlap between open tasks; the two registration files
(`OceanChecks/main.swift`, `OceanTool/main.swift`) are touched by one open task at a time.

## Carried from the sketch review (routed to this plan)
- Frame budget at extreme legal settings: profile shadows, flower scans and glyph drawing separately; keep the step
  apart from the draw; cache still flowers (m4, m5, then t8).
- The clock and tick policy; slow motion as the app's speed setting (all tasks).
- The replay fixture; the unit mapping (sketch points = cell / 13); the 7.5 Hz wingbeat cap (m2, m6).
- Display edges: entering on a small screen, leaving on a large one, landing while screens change (m6, m8).

## Decided by the manager (say if you disagree)
- A fresh stack from main instead of stacking on `meadow-t1-2` (every file t1-2 made is replaced, so stacking on it
  would review whole-file rewrites).
- Butterflies may fly part-way off real screen edges and out through them; edges shared with another screen are
  open doors, and nothing is ever placed in a gap between screens.
- Butterflies cross between touching screens like Web's flies; the monarch crosses most.
- The butterfly that lands on a still pointer sits up near the glass and leaves after 25–45 s (round 3's call).
- The wingbeat stays as the director set it; the 15 fps film in m6 shows whether it looks choppy on battery, and the
  director decides then.

## Questions for the director
1. **Ground colour per cell.** The family's canvas has one background colour. The sketch's green hints and every
   shadow on bare ground need a colour per cell, a change to the shared drawing code that the sharks and spiders use
   (their pictures would be checked to stay identical). Recommended: yes.
2. **The monarch's life cycle and the courtship chases** (in the original plan, not in the sketch). The hanging
   chrysalis is a side-view image. Recommended: leave both out of 3.1 and ship what the sketch shows.
3. **What users can change** in Settings. Recommended: which species, and how many (scaled by screen size from your
   7 on a laptop); "land on a still pointer" follows the app's existing interaction setting; everything else is
   fixed at your numbers.
