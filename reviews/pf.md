# Review pf: Meadow CPU headroom

Brief: briefs/pf.md. Reviewed commit: `45103eb` (baseline `8e215f0`).

## Design

The changes are confined to painting. The field offsets come from the layout of the initialized cell and wing-mark records. The painter grows the shared buffers before taking frame-local pointers and refreshes the ground pointer after growing a viewport cache. Stamps bound the touched, recorded and rim lists to one entry per cell. Changes in viewport geometry, dimensions or cell size invalidate the corresponding ground and flower caches. Grass sample indices are rebuilt when the breeze grid changes. The gust lookup bounds all four corner reads and falls back to hashing when a lookup lies outside the table.

Wing cursors preserve the original crossing rule, including samples exactly on a crossing. The shadow bounds cover the wing sample offsets and the body's perpendicular strip. Flower replay keeps the original per-cell blend and keys the cached colour on the inputs to the depth transform.

## What is missing?

The steady-state CPU and frame-equivalence targets were met. The resize probe found a one-time spike in flower-cache allocations and a higher peak memory footprint (finding 1).

### Frame equivalence

`diff -qr` found no differences across 1,372 outputs from the same release `OceanTool` commands on both commits.

| Command | Comparison |
|---|---|
| `still --habitat meadow` | 12 PNGs at 1800 × 1169, seeds 1, 42 and 4242, dark and light with Calm on and off, 9 s warmup |
| `meadow-sheet` | Flowers and flies sheets at 1800 × 1169, seed 42, dark and light with Calm |
| `meadow-desk` | 900 dark frames at 30 fps and 450 light frames at 15 fps, 30 s each on the two-screen desk, seed 4242, 6 s warmup, scale 0.5 |
| `still --habitat ocean` and `still --habitat web` | Four PNGs at 1800 × 1169, seed 42, dark and light with Calm |
| `bench --digest` | 900 frames per Web scene. Shared desk digest `612a0c22c778b40b`, separate desk digest `d4d23789aedfab08` |

### Resize and allocations

An independent probe reused a world and painter across six stages. It started on the owner's desk, shrank to 1 × 1, expanded to five viewports including 6144 × 3456, changed cells between 8 × 12 and 13 × 19, and returned to the desk. Both commits returned the same canvas digests for all six stages, and both recorded zero allocations on the painting thread across 300 warm frames per stage. A second probe measured the first paint after each normal relayout and the next 30 frames. Those 30 frames also allocated nothing on either commit. An AddressSanitizer run with 24 frames per stage exited cleanly.

### CPU and builds

`swift run -c release OceanChecks` passed all 250 checks three times in a row locally. `meadowWithinWebsCPU` reported nine-pair median ratios of 0.75, 0.75 and 0.76 at 30 fps, and 0.52, 0.53 and 0.53 at 15 fps. The focused baseline check measured 0.95 and 0.67. The allocation checks passed on each full run, including zero allocations in 12 clicks and in the 1,800 frames that followed them.

Five interleaved runs per habitat and commit of release `OceanTool bench --desk --habitat meadow|web` used the default 20 s stages and shared 2560 × 1440 + 1800 × 1169 desk. The Meadow drew 12 butterflies on both commits. Times below are medians. Ratios are the medians of the five same-trial ratios. Unchanged Web timing varied across runs, so the paired check above is the brief's acceptance measurement.

| Commit | fps | Meadow sim (ms/s) | Meadow draw (ms/frame) | Meadow total (ms/s) | Web total (ms/s) | Meadow ÷ Web |
|---|---:|---:|---:|---:|---:|---:|
| `8e215f0` | 30 | 3.58 | 1.663 | 53.47 | 51.92 | 1.02 |
| `45103eb` | 30 | 3.13 | 1.110 | 36.44 | 47.80 | 0.71 |
| `8e215f0` | 15 | 3.87 | 1.883 | 32.07 | 37.30 | 0.86 |
| `45103eb` | 15 | 3.34 | 1.332 | 23.32 | 37.84 | 0.60 |

The app passed `swift build` locally on Swift 6.4. CI for `45103eb` passed the universal app build and all 227 GPU-skipped checks on Apple Swift 6.3.3. CI's paired CPU ratios were 0.62 at 30 fps and 0.51 at 15 fps. [CI run](https://github.com/zegrt/ascii-animals/actions/runs/44835802157)

## Findings

| # | Finding | Where | Cause group | Fix size |
|---|---|---|---|---|
| 1 | The larger flower records trigger thousands of allocations on one relayout and substantially increase peak memory. Keep the cached colours in storage that scales with the recorded ops and preserves allocation-free warm frames. | `Sources/OceanKit/Meadow/MeadowPainter.swift:105` and `:256` | Flower-cache storage | Medium |

**Finding 1 evidence.** Start on the shared desk with seed 42 and warm the painter. Shrink to 1 × 1, then relayout with the desk and three additional viewports at `(-6000, -3500, 6144, 3456)`, `(180, -3500, 5120, 2880)` and `(2560, -580, 3008, 1692)`. Paint the five viewports on light Calm with 8 × 12 cells for 31 frames, then relayout the same five viewports on dark with 13 × 19 cells. Step four times per frame and reuse the world and painter throughout. The first frame at 13 × 19 allocated 8 times on `8e215f0` and 4,331 times on `45103eb`. The op reserve rises from 2,964 to 3,078. Reserving 2,964 ops yielded capacity for 3,184 records at the old 36-byte stride and 3,071 at the new 64-byte stride. The new stride forces a reallocation for all 1,441 retained slots on each of the three added viewports. Peak process memory footprint through the six-stage probe grew from 156 MiB to 233 MiB (`/usr/bin/time -l`). The next 30 frames allocated nothing.

---

## Re-review (after fixes)

| # | Fixed / not fixed | Evidence (file:line or check output) |
|---|---|---|
