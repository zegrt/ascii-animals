# Meadow replay fixtures

Recorded from the Meadow sketch (`Tools/meadow-sketch/meadow.html` on `meadow-sketch`), never edited by hand. The
checks in `MeadowChecks.swift` replay them in Swift.

- `air-flowers.json`: the sketch's own replay fixture (fix round 2, `?debug=1&fixture=air-flowers`), copied from
  `meadow-sketch:Tools/meadow-sketch/fixtures/air-flowers.json`. Its format is documented at the top of the sketch's
  export code.
- `meadow-probe-1600x913.json`, `meadow-probe-1280x713.json`: the m1 builder's probe of the sketch at f20b833, made
  before the fixture landed. A copy of the sketch with `meadow-probe.js.txt` appended before `</body>` was opened in
  headless Chrome (a fresh profile, so the sketch's defaults) with `?seed=4242&debug=1&freeze=1&panel=0` at window
  sizes 1600 x 1000 and 1280 x 800 (viewports 1600 x 913 and 1280 x 713), and the JSON it writes into the page read
  with `--dump-dom`. The probe empties the butterflies after the opening (so the air is the breeze and the pointer
  only), then records: the planted flowers; the air at four points and every flower after 60 steps; a pointer
  stirred along a line for 30 steps (set once a step, the sketch's `stirStep` at 60 Hz); eight clicks, one step
  apart; and 120 steps more. Numbers are rounded to 6 decimals. A flower row is `[id, kind, x, y, R, rot, seed, n,
  f0, leaves, florets, ox, oy, age, clicked, fade or -1]`; an air row is `[x, y, wind.x, wind.y, ax, ay, px, py, g]`.
