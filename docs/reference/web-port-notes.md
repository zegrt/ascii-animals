# Web port notes

Web is a port of [ascii-spiders](https://github.com/stackedlol/ascii-spiders) by @stackedlol (MIT), commit 89a7721.

The port keeps the original's structure, names (camelCase), constants, comments, timings and order of
operations, including the order of random draws. Seeded with the same stream, `OrbWeb` reproduces the
original `web.ts` to the 12 digits node prints (check `orbWebMatchesOriginal`), and `WebWorld` reproduces the
whole original wall (webs, weavers, jumper, flies, pointer, clicks) for ten simulated minutes to ~1e-13, drawing from
the stream exactly as often (check `webWorldMatchesOriginal`, below). What differs, and why:

## math.ts → Web/WebMath.swift

- **`rand`, `randInt` and `Math.random()` live on `WebRandom`** (`range`, `int`, `unit`), a seeded
  SplitMix64 stream (the Ocean's `Rng`) passed in explicitly. Swift has no global seeded random, and
  checks need replays. Same formulas: `lo + unit() * (hi - lo)`, `floor(rand(lo, hi + 1))`.
- **`Vec` is a struct.** The original passes a `Vec` (or `ThreadPoint`) in to be written into, only so
  hot loops don't allocate; a returned Swift struct doesn't allocate either, so `pos`, `snap` and
  `catches` return `Vec` / `ThreadPoint?` instead of filling an `out` argument.
- **Two JavaScript number helpers are spelled out:** `mathRound` (`Math.round` rounds halves up, Swift's
  `.rounded()` rounds them away from zero) and `toInt32` (`x | 0`, used by `hash3`).
- **`angleDiff` is shared with the Ocean**, which had an identical internal copy in World.swift; the Ocean's private
  `clamp` is renamed `oceanClamp` so the Web's public `clamp` can keep the original's name and
  definition. The Ocean's behaviour is unchanged.

## web.ts → Web/OrbWeb.swift

- **Typed arrays are `WebBuffer`s**: a small class owning a fixed-size buffer, shared by reference as
  `const { x } = this` aliases a typed array. `generate` replaces them; a buffer held from before keeps
  its memory, as an old typed array would. Hot loops index its raw buffer (`web.x.p`). Element types
  follow the original where they change behaviour: positions, `rest`, `dew` and `speed` are `Float`
  (Float32Array; maths in `Double`, rounded on store, as JS does), `deg` is wrapping `UInt16`,
  `pin`/`on` are `UInt8`. Node and link indices (`la`, `lb`) and the small enums (`kind`, `state`) are
  `Int`, because Swift indexes with `Int`; their values never exceed the original's ranges.
- **Stale link indices read as "not laid".** A leg can hold a link index from before a rebuild; in JS
  `state[l]` past the end is `undefined`, so `cut`, `jolt` and `load` do nothing and `state[l] === 1`
  is false. Swift buffers have no `undefined`, so those methods also check `l < m` (as does `lay`, where
  JS would only miscount `laid`; nothing lays a stale link), and
  `isLaid(l)` stands for `web.state[l] === 1`: **ports of spider.ts, weaver.ts and flies.ts write every
  `web.state[x] === 1` as `web.isLaid(x)`.** `pos` on a stale link returns NaN, as JS does.
- **`WebOptions` is the initialiser's labelled arguments**, plus `random: WebRandom`.
- **`prey` is `[Fly]`**, as in the original.
- **Sorts are stable.** `Array.prototype.sort` is stable; Swift's `sort` doesn't promise to be, so the
  anchor and frame-point sorts keep ties in their original order.
- **`buildInstant(upTo)` defaults to `nil`** meaning `route.length` (Swift default arguments can't read
  `self`).
- **`step` reads `isFree`'s inputs once per call** (pin, held, hub, hubPinned). None of them change
  before the break pass, so it's the same test, without a property access per thread per iteration.

## spider.ts → Web/Spider.swift

- **`SpiderKind` lives here** (moved from Domain/HabitatKind.swift), with its raw values, `Codable` and
  `defaultCast` (the original's `DEFAULT_SPIDERS`), which Settings stores. `SpeciesKind` is the original's
  `SpiderKind | "jumper"`; `SPECIES` is a dictionary keyed by it; `Species.pattern` is an enum.
- **A `Leg` is a struct in `spider.legs`**, and the methods that took a leg take its index. Its `wait` list (the
  neighbours it waits for) is a bitmask of leg indices, and `raise` an index. Every read and write happens in the
  same order as the original's, on the live array, so a foot still sees its neighbours' state as the loop leaves it.
- **`Snap` and `land` are one `Silk` object** (the weaver passes both; the jumper neither), so a step builds no
  closures: `updateLegs(dt, snap, land)` → `updateLegs(dt, silk)`, `place(x, y, h, snap)`, `stepTo(…, snap)`.
- **Out-parameters are returned structs**: `toWorld`, `restWorld`, `spinneret`, `hipLocal` return `Vec` / `(u, v)`,
  `snap` a `SilkHit?` (the shared `tmpW`, `tmpP`, `tmpL`, `tmpS` are gone).
- **`x || 1`** keeps JavaScript's meaning (0 and NaN are falsy): `jsOr`.
- `t` and `id` draw from the world's `WebRandom`, in the original's field order (`t`, then `id`).

## weaver.ts → Web/Weaver.swift

- **Fixed: the original hangs when a weaver moves house.** In `move`, `glide`'s waypoint callback is
  `k === 0 ? goal : null`: it ignores `wp`, so once the spider reaches the goal with distance to spare, `glide`'s
  `while (dist > 0)` advances to the same point forever (distance 0, nothing left to subtract). The page freezes the
  first time a weaver finishes eating a web and walks to the new site (seed 7 at 1800 × 1169: step 19171, about
  5 min 20 s in); a faithful port would freeze the app. The port counts from `wp` (`wp + k == 0`), as hunt, carry and
  return already do, so the walk ends where it was meant to and the weaver starts building. Up to that moment
  nothing changes. The reference runs patch the original the same way.
- **The weaver is the spider's `Silk`**: `snap` and `land` are methods instead of stored closures.
- **`route[step]` out of range** (JS `undefined`) is a bounds check. `path` and `glide`'s points are the same;
  points are tuples from a non-escaping closure, so a glide allocates nothing.
- `.return` is spelled with backticks (`return` is a keyword); `world` is `unowned` (the world owns its weavers).
- **Relocating on several screens** keeps the web on its own screen with its frame inside it (see below).

## jumper.ts → Web/Jumper.swift

- `Interest`, `Leap` and the dragline are structs; `crouch` keeps the interest as it was when the crouch began, as
  the original's freshly built object does.
- **On several screens** its wander goal and its clamp follow the screens (see below).

## flies.ts → Web/Flies.swift

- **`Fly.web` and `Fly.aimWeb` are `weak`.** A stuck fly and its web point at each other (`web.prey`, `fly.web`);
  JavaScript's collector frees that cycle, Swift's reference counting wouldn't. Nothing outlives the world, so
  `weak` never reads nil where the original would read a web.
- `web.state[f.link] !== 1` is `!web.isLaid(f.link)`; `pos(…, f)` returns the point, then `f.x`, `f.y` are set.
- A fly holds the world's `WebRandom` (for `free` and `stick`).
- **On several screens** spawning, edge-steering, the off-page clamp, resting and entering follow the screens.

## world.ts and engine.ts → Web/WebWorld.swift

- **Configuration is the demo page's** (`/`, no options): no clear centre, no build-from-scratch, the first web in
  the bottom-left, default web and fly counts. **The nav-bar gap is dropped** (a desktop has no floating nav bar;
  the menu bar is already above the wallpaper). The original skips such candidates only after drawing them, so
  the random stream is unchanged; only which candidate wins can differ.
- **`spiders: [SpiderKind]`**: `SpiderKind.defaultCast` is the demo page without `?spiders=` (no roster: the wall
  holds as many webs as the area gives, spiders on the first six); any other list is `?spiders=` (a roster: every
  spider gets a web). Spider `size` is always 1. **`flies: Bool`**: true is the original's default count, false 0.
  **`jumper: Bool`** is `options.jumper`.
- **`layout(terrain:cell:settled:)`**: W × H is the terrain's bounds; nothing is laid out for an empty terrain (the
  engine skips a canvas under 1 px).
- **The pointer, as engine.ts feeds it**: `pointerMoved(x:y:)` (`onPointerMove`: a pointer that wasn't active
  starts its stroke where it is; active while over the terrain), `pointerLeft()` and `pointerDown(x:y:)` (a click
  over the terrain drops a fly). The engine's fixed-step loop (1/60 s, at most 4 steps a frame), its 120 steps after
  a settled layout, and its "no clicks on a still wall" belong to the host (WebSim).
- `heat` is filtered in place; `swarm` is created lazily (it needs the world).

## Several screens (a platform addition; one screen is the original, formula for formula)

The original lays out one W × H page. A desktop can be several screens with gaps between them (a monitor above
a laptop, offset). With one screen every formula above runs verbatim; with several:

- **Webs are drawn inside one screen and fit on it.** Each candidate picks a screen in proportion to its area (one
  extra draw), draws x, y within it as the original draws them on the page, caps R so a whole frame (anchors reach
  R · 1.3 · 1.15 ≤ 1.5 R from the hub) fits, clamps the hub so it does, and is scored against that screen's edges
  and every placed web. The corner web goes in the bottom-left of the lowest screen. Web sizes come from the
  screens' total area, capped by the biggest screen; a relocated web stays on its screen, frame inside.
- **The jumper and the flies stay on the screens; outside every screen is a wall.** "Clear of the walls by m" means
  the square of half-side m round the point lies on the screens, so a shared edge between touching screens is no
  wall and both may cross it. The jumper is clamped back into the screen it came from when it would leave that
  clearance; its wander goal is on any screen when the straight way there is clear, else on its own. Flies may be
  20 px off a screen (the original lets them 20 px off the page); they steer for their screen's middle near a
  wall, rest only clear of walls, spawn on a screen picked by area, and enter over a real edge picked by length.

## Verification

`webWorldMatchesOriginal` holds the numbers the original world.ts printed for two runs, made by
`world-ref.mjs` (kept with the scratch reference tools, not in the repo): the original's sources with import paths
given `.ts` and parameter properties spelled out (for node's type stripping), the nav-bar gap dropped and the move
glide fixed as above, `Math.random` replaced by the `WebRandom` stream. The script moves the pointer through the
near web, drops a fly on its spiral and one in the air, holds the pointer still by the jumper, and later frees a
hunted fly. Compared: every web (laid, broken, generation, seed, held end, hub, node sums), every weaver (state,
route step, waypoint, catches, age, alert, body, heading and its spring, weight shift, feet), the jumper (state,
body, scale, dragline, feet) and every fly (mode, position, heading, speed), plus the next random number. Run 1 is
the demo wall at 1800 × 1169 for ten minutes and passes through every weaver, jumper and fly state; run 2 is
700 × 450 with a five-spider roster (more than the room), laid out settled. During the port the same comparison
also agreed for 2560 × 1440, 1440 × 900, 900 × 600 and 340 × 150, a 20-minute run, a lone nephila, a thirteen-spider
roster, no flies and no jumper, and an empty roster. Not covered by the original: several screens (it has one
page), checked instead by `webWorldOnSeveralScreens`.
