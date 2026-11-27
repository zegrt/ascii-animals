# Report pf: headroom under Web's CPU

Status: done
Board commit: e884b7e (main; adds briefs/pf.md)
Commit: 6d95f89 (code); this report is the commit after it, on `meadow-pf` (from `meadow-m8` 8e215f0)
Files changed: Sources/OceanKit/Meadow/MeadowPainter.swift, Sources/OceanKit/Meadow/FlowerPainter.swift,
Sources/OceanKit/Meadow/ButterflyPainter.swift (painting hot paths only; nothing outside Files; no check changed or
added, see Rulings)

## Result

`meadowWithinWebsCPU` (the check as it is: 12 butterflies on the owner's desk, median of 9 paired runs), this machine:

| | 30 fps, Meadow ÷ Web | 15 fps, Meadow ÷ Web |
|---|---|---|
| before (8e215f0, two runs) | 0.98 (0.88–1.13), 0.98 (0.96–1.04) | 0.66, 0.67 |
| after (6d95f89, the three full runs below) | **0.76** (0.73–0.80), 0.76 (0.74–0.78), 0.76 (0.70–0.82) | **0.53**, 0.53, 0.53 |

Target was at most 0.8 at 30 fps and lower at 15 fps: met in every run. Not a pixel or a step changed (below).

## Where the time went (profile)

Measured in the check's own regime (Meadow alone, 12 butterflies, desk, 10 s warm-up then 4 s at 30 fps), with a
scratch probe (not committed): sampled with `sample`, and A/B'd by cycle counts (`/usr/bin/time -l`, stable to
±0.3 %, unlike wall or thread time on this machine, which drifts up to 2× between runs).

Simulation vs painting: simulation ~6 % (about 1.1 ms/s), painting ~94 %. Painting, share of the Meadow's total:

| | before | after |
|---|---|---|
| butterflies: wings, body, rim | 30.5 % | 34.4 % |
| butterflies: shadows | 12.7 % | 12.0 % |
| flowers (mostly replaying recorded cells) | 15.5 % | 12.3 % |
| grass tufts | 12.8 % | 9.7 % |
| the air on the breeze grid (`readAir`) | 12.0 % | 8.3 % |
| blit to the canvas | 8.8 % | 13.8 % |
| simulation (`MeadowWorld.step`) | 5.9 % | 7.6 % |

(Shares of a total that fell by about a fifth; the whole probe run went from 5.70 to 4.43 G cycles.) Per butterfly
(wings + shadow), roughly 0.8 ms/s before and 0.55 ms/s after at 30 fps.

The main finding: the painter waits on memory more than it computes. Skipping only the three ground-colour loads in
a cell's first write saved 7 % of all cycles at the same instruction count; the flower replay ran ~37 cycles per
recorded write. So most of the gain is data layout.

## What changed (each exact: the same sums, in the same order, on the same values)

1. The gust on the breeze grid: `vnoise`'s corner hashes come from a small per-frame table per octave (the grid's
   ~3,000 points share a few hundred corners); outside the table, or if one wouldn't fit, the corners are hashed as
   before. The tables are sized once per grid from its diagonal, so no frame allocates.
2. Grass: each tuft's four air samples and weights are worked out once per layout, not per frame.
3. Flowers: a recording's colours are pushed back (`far`) once per push instead of on every replay.
4. Wings and shadows: samples along a row walk the sorted crossings with a cursor instead of rescanning; a shadow's
   rows scan only the columns where a sample or the body strip can land (a cell of slack each way).
5. The cell writers (`touch`, block, glyph, shade) live on a struct of pointers that the grass and replay loops hold
   in locals; the arithmetic is in one place.
6. Layout: the cached ground colour is one record per cell (was three arrays, −7 % cycles); the painter's per-cell
   state (block, ink, alpha, glyph, flags, stamp) is one 36-byte record per cell (`MCell`, with array-like
   `CellField` views so drawing code reads as before, −2.5 %); a tuft is one record; the butterfly marks (wing,
   record, rim, rim weight) are one record per cell.

Tried and dropped (no gain by cycles): SIMD pairs for the wing edge distances; caching a sample's part until the next
crossing; marking coverage a run of columns at a time.

## Checks run

- `swift build` (app, debug): Build complete.
- `swift run -c release OceanChecks`, three times in a row on 6d95f89: **250 passed, 0 failed** each time, exit 0;
  `meadowWithinWebsCPU` 0.76 / 0.53 each run (table above); `meadowFrameAllocatesNothing`,
  `meadowStepAllocatesNothing`, `meadowHostedStepsAllocateNothing`, `meadowClicksAllocateNothingLater` ("0
  allocations in the clicks, 0 in the 1,800 frames after them"), `meadowArrivalsAllocateNothing` all pass.
- Byte for byte against 8e215f0, the same `OceanTool` commands from both builds, 1,446 files, every SHA-1 equal:
  Meadow stills at seeds 1 and 7 in dark, light, Calm, light + Calm and live (20 s); the flowers and flies sheets in
  dark, light and Calm; a 30 s two-screen film on the owner's desk (`meadow-desk`, 15 fps, 450 frames) in dark and
  in light; a 30 s Calm film (`frames --habitat meadow`, 450 frames); Ocean stills (dark, light) and a 5 s Ocean film;
  Web stills (settled and live); `bench --digest` (Web) `612a0c22c778b40b`, the same.
- Canvas fingerprint (scratch probe, both builds): every Meadow canvas (block, ink, glyph, overlays, ground,
  background) and every butterfly's position, height, heading, stroke and phase, painted at 30 and at 15 fps over
  30 s with a pointer script (a pass, a hold to a landing, a click, leaving, a second pass), on the desk and on one
  1440 × 900 screen, seeds 1–3, in dark, light, light + Calm, dark + Calm and with the theme switching every 7 frames
  (60 runs): all equal, total `dd36d49c2283fdd1` before and after. Re-run after every change.
- `OceanTool bench --desk` (ms/s, total = sim + draw × fps; five alternating runs each, medians; this machine drifts a
  lot between runs, so the paired check above is the measure):

  | | 30 fps | 15 fps |
  |---|---|---|
  | Meadow before | 26.1 (runs 16.2, 16.2, 26.4, 26.1, 27.3) | 14.3 (9.4, 9.9, 14.3, 15.1, 16.1) |
  | Meadow after | 21.6 (13.0, 14.8, 21.6, 24.8, 24.3) | 12.2 (7.9, 9.7, 12.2, 12.8, 14.9) |
  | Web | 28.4 (16.7, 32.7, 25.6, 28.4, 31.4) | 21.2 (12.9, 21.2, 19.6, 21.7, 24.5) |

## Rulings

- No equivalence check added to OceanChecks: the code it would compare against is the code replaced, and the new
  internals aren't reachable from the checks (no `@testable`); a golden digest would tie CI to this machine's libm.
  The proof is the byte-for-byte runs above. If wrong: the reviewer wants a committed guard; the scratch probe
  (canvas fingerprint) can be added to OceanTool as a task.
- Kept the flower colour cache (item 3) although its cycle gain is within noise: it does fewer instructions.
- A table that wouldn't fit its room falls back to hashing rather than growing, so allocation-free holds whatever the
  grid; costs only speed in a case that can't arise on a laid-out grid.

## Noticed

- The allocation tracer in `MeadowChecks.swift` (`traceState`, a lazily made global read inside the malloc hook)
  traps re-entering its own `dispatch_once` on the first traced allocation, so an allocation in a frame crashes the
  whole run (exit 133, buffered output lost) instead of reporting FAIL. It caught my first version that way (the gust
  table grew mid-run, fixed in 6d95f89). Out of my Files.
- Thread CPU time on this machine drifts up to 2× between runs; cycle counts from `/usr/bin/time -l` were stable to
  0.3 % and are a better A/B tool for performance work (the check's paired median copes, `bench --desk` doesn't).
- What is left: wing cells (~100 ns each, a third in `edgeInfo`), the flower replay (memory-bound), and the blit,
  whose four output arrays are `CellCanvas`'s layout.

Pushed and clean: no push (instructed not to push); folder clean, everything committed on `meadow-pf`.

## Fix round 1

Status: done
Board commit: 8fbf6ed (main; "pf review routed; small fix round 1")
Commit: 246777b (code); this report is the commit after it, on `meadow-pf` (from 45103eb)
Files changed: Sources/OceanKit/Meadow/MeadowPainter.swift, Sources/OceanKit/Meadow/FlowerPainter.swift (in Files)

### What changed

1. **The flower record is 36 bytes again (8e215f0's size).** The three pushed-back doubles are gone from
   `FlowerOp`. A block's pushed-back colour goes in the record's last three words, which only a shimmer uses (its
   key, tick and roll; a block has no shimmer), stored as `Float`. That is exact, because `block` stores the colour
   as a `Float` anyway. So a block's colour is still pushed back once per push, not on every replay. The colour
   costs no storage, and a relayout reserves what 8e215f0 reserved.
2. **A glyph's colour is pushed back as it is replayed**, as 8e215f0 did. `glyph` flattens it toward the block
   under it in `Double` before storing it, so a `Float` copy would change pixels, and 24 more bytes per record was
   the finding.
3. **A grass tuft is 32 bytes, not 64.** This is the rest of the memory rise; the flower records were not all of
   it. pf's `Tuft` kept its four air indices as an `SIMD4<Int32>`, aligned to 16, so the stride was 64; 8e215f0
   spent about 17 bytes per tuft in five arrays. Now a tuft keeps its first air sample and a column step and a row
   step (0 or 1 each), and the other three indices come from them with the same values as before
   (`j1 = j + dx`, `j2 = j + dy × columns`, `j3 = j2 + dx`).

### Peak memory and allocations

A scratch probe (not committed) built from the review's evidence uses seed 42 and one world and painter
throughout, stepping 4 times a frame and painting 31 frames per stage. The stages are: the owner's desk (dark);
1 × 1; the desk plus `(-6000, -3500, 6144, 3456)`, `(180, -3500, 5120, 2880)` and `(2560, -580, 3008, 1692)` at
8 × 12, light Calm; the same five at 13 × 19, dark; the same five at 8 × 12, dark; and the desk again. Footprint
is `peak memory footprint` from `/usr/bin/time -l`; allocations are counted on the painting thread around the
paints.

| | 8e215f0 | 45103eb (pf) | fix |
|---|---:|---:|---:|
| Review's probe, peak footprint | 151.5 MiB | 231.0 MiB | **157.8 MiB** |
| Owner's desk alone (300 frames), peak footprint | 8.3 MiB | 8.8 MiB | **8.3 MiB** |
| First paint at 13 × 19 (the finding), allocations | 5 | 4,052 | **5** |
| First paints of the other stages, allocations | 654, 142, 13,311, 205, 2 | 559, 136, 13,118, 205, 2 | 559, 136, 13,118, 205, 2 |
| The 30 frames after each first paint | 0 | 0 | 0 |
| Canvas digests, all six stages | — | equal to 8e215f0 | equal to 8e215f0 |

The probe's figures repeated exactly over two runs of each build. My reconstruction of the probe counts 4,052 where
the review counted 4,331 on 45103eb, and its baseline footprint is 151.5 MiB where the review's was 156 MiB.
The stages differ slightly, but it shows the same fault and the same jump. The remaining 6 MiB above 8e215f0 in the
probe comes from pf's other records, which are the CPU gain: the ground colour is padded to 16 bytes a cell, and a
32-byte tuft against 8e215f0's 17 bytes. On the owner's desk the peak is the same as 8e215f0's.

### CPU

- `meadowWithinWebsCPU`, three full runs: **0.78, 0.77, 0.75** at 30 fps; **0.55, 0.54, 0.54** at 15 fps. Before
  this fix: 0.76 and 0.53 here, 0.75 and 0.53 in the review.
- Cycles (`/usr/bin/time -l`) on the desk alone for 900 frames, two runs each: 8e215f0 3.39 G and 3.42 G; 45103eb
  2.98 G and 2.97 G; fix 3.02 G and 2.99 G. The fix keeps about 90–97 % of pf's saving.

### Checks run

- `swift build` (app, debug): Build complete. The only warnings are the linker's search-path warnings from this
  machine's Command Line Tools.
- `swift run -c release OceanChecks`, three times in a row: **250 passed, 0 failed** each time, exit 0. The
  allocation checks passed every run: `meadowFrameAllocatesNothing`, `meadowStepAllocatesNothing`,
  `meadowHostedStepsAllocateNothing`, `meadowArrivalsAllocateNothing`, and `meadowClicksAllocateNothingLater`
  ("0 allocations in the clicks, 0 in the 1,800 frames after them").
- Byte for byte against 8e215f0: the same `OceanTool` commands from both builds produced 1,673 files, and
  `diff -qr` found no difference. The files:
  - Meadow stills, 1800 × 1169, at seeds 1, 42 and 4242, in dark, light, Calm, and light with Calm, after 9 s of
    warm-up.
  - The flowers and flies sheets in dark, light, and light with Calm.
  - Two two-screen films of the owner's desk (`meadow-desk`, seed 4242, 30 s): 900 dark frames at 30 fps and 450
    light frames at 15 fps.
  - A 20 s Calm film (`frames --habitat meadow`, 300 frames).
  - Ocean and Web stills in dark, and in light with Calm.
  - `bench --digest` (Web): `612a0c22c778b40b`, the same.
- Types: no long mixed-literal expressions were added. The new index arithmetic is all `Int`, typed.

### Rulings

- Glyph colours are not cached; block colours are. This is the only exact cache that adds no storage. If wrong:
  the CPU stays within about 1.5 % of 45103eb by cycles and the check medians are unchanged within this machine's
  noise; caching glyph colours too would need a side buffer of 24 bytes per glyph op.
- The tuft change is outside the finding's two lines, but it is in a listed file and is the same kind of fault (a
  pf record that grew). Without it the probe peaked at 164.6 MiB, not near 151.5. If wrong: revert that one
  commit's tuft hunk; the flower fix stands alone.

### Noticed

- none

Pushed and clean: not pushed (instructed not to push); folder clean, everything committed on `meadow-pf`.
