# Meadow replay fixtures

Recorded from the Meadow sketch (`Tools/meadow-sketch/meadow.html` on `meadow-sketch` at 4e1b869, the sketch the
port copies), never edited by hand. The checks in `MeadowChecks.swift` replay them in Swift.

- `air-flowers.json`: the sketch's own replay fixture, format 2 (`?debug=1&fixture=air-flowers`), copied unchanged from
  `meadow-sketch:Tools/meadow-sketch/fixtures/air-flowers.json` at 4e1b869. Its format is documented at the top of the
  sketch's export code ("Replay fixture"). The replay validates it before replaying (version 2, the scenario, the clock
  as the integer rate 60 with the declared last tick, no `problems`, the documented sample ticks, every wind row),
  steps exactly `OceanClock.step` a tick and never reads the file's `t` as its clock, and samples the air at the
  points it derives from the viewport and the documented fractions (checking the file's rounded points against them).
- `meadow-probe-1600x913.json`, `meadow-probe-1280x713.json`: the m1 builder's probe of the sketch at 4e1b869. A copy
  of the sketch with `meadow-probe.js.txt` appended before `</body>`, and two hooks added before its `if (FIXTURE)`
  line (`window.__makeFlower`, the sketch's `makeFlower` run on a given stream, and `window.__stream`, a fresh
  `mulberry32`), was opened in headless Chrome (`--headless=old`, a fresh profile, so the sketch's defaults) with
  `?seed=4242&debug=1&freeze=1&panel=0` at window sizes 1600 x 1000 and 1280 x 800 (viewports 1600 x 913 and
  1280 x 713), and the JSON it writes into the page read with `--dump-dom`. The probe empties the butterflies after
  the opening (so the air is the breeze and the pointer only), then records: the planted flowers and their leaf and
  floret geometry; the air at four points and every flower after 60 steps; a pointer stirred along a line for 30
  steps (set once a step, the sketch's `stirStep` at 60 Hz); eight clicks, one step apart, and every flower's geometry
  after them; 120 steps more; and one flower of each of the seven kinds made by `makeFlower` on the stream
  `mulberry32(777)`. Numbers are rounded to 6 decimals. A flower row is `[id, kind, x, y, R, rot, seed, n, f0,
  leaves, florets, ox, oy, age, clicked, fade or -1]`; a geometry row `[id, [[a, len, wid, k]…], [[x, y, s, open,
  rot]…]]`; a kind row `[id, kind, R, rot, seed, n, f0, reach, leaves, florets]`; an air row `[x, y, wind.x, wind.y,
  ax, ay, px, py, g]`. Re-recorded in m1's fix round 1 at 4e1b869: the rows the earlier probe (at f20b833) had are
  unchanged; the geometry and the kinds are new.
- `meadow-stir-probe-1600x913.json`: m1 fix round 2's probe of the sketch's pointer stir at 4e1b869. A copy of the
  sketch with `meadow-stir-probe.js.txt` appended before `</body>`, and one hook added before its `if (FIXTURE)` line
  (`window.__run = () => { paused = false; };`), opened in headless Chrome (`--headless=old`, a fresh profile, window
  1600 x 1000, viewport 1600 x 913) with `?seed=4242&debug=1&freeze=1&panel=0`, and the JSON it writes read with
  `--dump-dom`. `freeze=1` keeps the frame loop from running and `__run` lifts the pause, so the probe steps by hand
  (`step(1/60)`) while the sketch's own `pointermove` and `pointerleave` handlers take the moves. It empties the
  butterflies, then runs six scenarios, each from a still field: `rate60`, `rate30`, `rate120` (one path, moves at 60,
  30 and 120 Hz), `fast` (150 pt a step, past the speed clamp), `reentry` (a leave after a step, back far off) and
  `slow` (Slow motion 0.4). Each scenario is its list of ops (`['m', x, y]` a move, `['l']` a leave, `['s']` a step,
  `['t', v]` the Slow motion setting, `['snap']`) and, at each snap, the stir field's non-zero samples
  `[index, PFX, PFY]`, rounded to 6 decimals. `meadowStirMatchesTheSketch` replays the ops and compares every sample.
