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
