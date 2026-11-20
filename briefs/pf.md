# Brief pf: headroom under Web's CPU

Size: Content (performance only; nothing visible changes)
Board commit: the commit that adds this brief (main)
Branch: meadow-pf, made from `meadow-m8` (8e215f0)

## Objective
The director wants the Meadow "performant": no more CPU than Web. With the director's cap of 12 butterflies on the
owner's desk (2560 × 1440 + 1800 × 1169), the Meadow now costs 0.98–1.03 × Web at 30 fps, so `meadowWithinWebsCPU`
sits on its limit and flakes (board, m8 row and Review routing). Make the Meadow cheaper so it has real headroom,
**without changing a single pixel or step**: the same frames for the same seed.

## Do
1. Profile the Meadow at the default on the owner's desk at 30 and 15 fps (`OceanTool bench --desk --habitat
   meadow`, Instruments or sampling), split into simulation and painting, and find where the time goes per
   butterfly (the review measured about 0.7 ms/s each).
2. Make it cheaper. Ideas from the research (docs/plans/2026-11-20-family-details.md §3.7) and the port inventory:
   rasterise each wing once per frame into a small mask and read coverage from it; skip cells and work for
   butterflies and flowers off the viewport; reuse per-frame computations shared by wings, shadow and rim; avoid
   repeated trig and noise; anything the profile shows.
3. Target: at the default on the owner's desk, **at most 0.8 × Web at 30 fps** (median of the steady check's
   paired runs) and lower at 15 fps. The check's rule stays "no more than Web"; the headroom is what stops it
   flaking.
4. Prove nothing visible changed: Meadow stills, sheets and a 30 s film byte for byte against 8e215f0 at the same
   seeds (dark, light, Calm, two screens); Ocean and Web digests and stills unchanged; no allocation per frame.

## Output and done when
Code on `meadow-pf`; `swift build` (app) and `swift run -c release OceanChecks` pass, run three times in a row
without a CPU-check failure; before and after numbers (profile split and `bench --desk`) in `reports/pf.md`. CI Swift
6.3.3 typing rule. No local folder paths in commits or files.

## Files
`Sources/OceanKit/Meadow/*` (painting and simulation hot paths only), `Sources/OceanChecks/Meadow*.swift` (only to
add equivalence checks).

## Out of scope
Any visible change, the cap, the check's rule, app UI.

## Fix round 1 (from the review, 2026-11-21; small)
Read `git show origin/review-pf:reviews/pf.md` (finding 1 and its evidence). The flower-cache records grew from 36 to
64 bytes, so a relayout that adds large viewports reallocates every retained slot (4,331 allocations once) and the
extreme probe's peak memory rose from 156 to 233 MiB. Keep the cached colours in storage that scales with the
recorded ops (not in every record), so relayouts allocate no more than 8e215f0 did and peak memory is back near it.
Keep the CPU gain, the same frames (byte for byte against 8e215f0) and allocation-free warm frames. Report peak
memory on the owner's desk and in the review's probe, before and after. Add a "Fix round 1" section to
`reports/pf.md`.
