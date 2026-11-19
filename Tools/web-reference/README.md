# Web reference tools

These scripts run the original [ascii-spiders](https://github.com/stackedlol/ascii-spiders) (MIT) under node, using
the same seeded random stream as the Swift port (`WebRandom`). Their output is the set of reference numbers that
`OceanChecks` compares the port against: `webMathMatchesOriginal`, `orbWebMatchesOriginal` and
`webWorldMatchesOriginal`. The original's sources are not kept here; `ascii-spiders-89a7721.patch` lists the
edits made to them:

- import paths get `.ts`, and parameter properties are spelled out, so node can strip the types and run them;
- the nav-bar gap is dropped from the layout (the port drops it);
- the weaver's `move` glide counts from `wp`, the port's fix for the original's hang
  (see `docs/reference/web-port-notes.md`).

## Running

Needs node 22.18 or later, for type stripping (tested with node 26).

```sh
git clone https://github.com/stackedlol/ascii-spiders.git
cd ascii-spiders
git checkout 89a7721
git apply <this repo>/Tools/web-reference/ascii-spiders-89a7721.patch

# from inside the clone:
node <this repo>/Tools/web-reference/math-ref.mjs     # webMathMatchesOriginal's values
node <this repo>/Tools/web-reference/web-ref.mjs      # orbWebMatchesOriginal's values
node <this repo>/Tools/web-reference/world-ref.mjs 7 1800 1169 13 19 36000 600,36000   # one run, as JSON
```

To regenerate `Sources/OceanChecks/WebWorldReference.swift` (both runs), from this repo:

```sh
python3 Tools/web-reference/gen-swift.py <the patched clone> > Sources/OceanChecks/WebWorldReference.swift
```

`world-ref.mjs` takes `seed W H cw ch steps [checkpoints] [--trace]`, plus optional `WEB_OPTS` JSON
(`spiders`, `flies`, `jumper`, `settled`). The scripted pointer, clicks and torn-free fly match `runWebScript` in
`Sources/OceanChecks/WebChecks.swift`, and its features match `webWorldFeatures`. If you change either side, change
the other to match.

## Parity with the original (`parity/`)

The side-by-side behind `docs/reference/web-original*.png` / `web-native*.png` and the numbers
`webGlyphsMatchChrome` pins (Task 11). The original runs in Google Chrome from a reference page: the demo page `/`
(the default cast, no options) with `Math.random` replaced by the `WebRandom` stream, the engine's animation-frame
clock stopped so it steps only when told, `?seed=`, `?theme=dark|light` and `?still=1` (the engine's `still`
option; `/?still=1` on the demo route is not a still). Same seed, size, scale and steps as `OceanTool`: the same
scene, so what differs is rendering.

- `parity/page/`: `parity.html` and `parity/parity.ts`, copied into the patched clone. `parity.ts`'s interaction
  script and `Sources/OceanTool/WebScript.swift` (`OceanTool frames --interact`) are the same script: change both.
- `parity/capture.mjs`: a still, or frames at a fixed step cadence (optionally with the script).
- `parity/sheet.mjs` + `parity/sheet-boxes.py`: Chrome's glyph sheet at 1x and 2x, and the boxes and ink
  `webGlyphsMatchChrome` holds. `parity/measure.mjs`: Chrome's font metrics and the faces the page loaded.
- `parity/compare.py`: lit pixels, luminance, mean difference, best shift and silk-only cells for two renders.

Needs Google Chrome (`CHROME` overrides its path), node, `puppeteer-core` installed in the directory you
run the scripts from (they resolve it from the current directory), and Python 3 with numpy and Pillow.

```sh
# the patched clone, as above, plus the page; serve it
cd ascii-spiders && npm install
cp -R <this repo>/Tools/web-reference/parity/page/. .
npx vite --port 5199 --strictPort          # PARITY_URL overrides http://localhost:5199

# elsewhere: a work directory with puppeteer-core
mkdir parity-work && cd parity-work && npm init -y && npm install puppeteer-core
P=<this repo>/Tools/web-reference/parity
T=<this repo>/.build/release/OceanTool     # swift build -c release --product OceanTool

# the stills (docs/reference: 1440 x 900 at 2x, seed 1)
node $P/capture.mjs still web-original.png --seed 1
node $P/capture.mjs still web-original-light.png --seed 1 --theme light
$T still web-native.png 1440x900 --habitat web --seed 1 --scale 2
$T still web-native-light.png 1440x900 --habitat web --seed 1 --scale 2 --light
python3 $P/compare.py web-original.png web-native.png 24 34
python3 $P/compare.py web-original-light.png web-native-light.png 24 34 light

# 20 s with the interaction, from load, at 1x and 20 fps (both print the script's click and aim)
node $P/capture.mjs frames frames-original --seed 1 --seconds 20 --fps 20 --warmup 0 --interact
$T frames frames-native 1440x900 --habitat web --seed 1 --seconds 20 --fps 20 --scale 1 --warmup 0 --interact

# Chrome's glyphs, for webGlyphsMatchChrome
node $P/sheet.mjs sheets && python3 $P/sheet-boxes.py sheets
node $P/measure.mjs
```

Seed 1 at 1440 × 900 gave (Chrome 158, macOS): mean absolute difference 0.31 of 255 (dark) and 0.30 (light), lit
pixels within 1 %, silk ink within 1 %, every frame of the 20 s run within 0.24. Results and the differences that
remain are in `docs/reference/web-port-notes.md` ("Parity with the original, side by side").
