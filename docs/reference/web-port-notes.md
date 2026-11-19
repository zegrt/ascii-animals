# Web port notes

Web is a port of [ascii-spiders](https://github.com/stackedlol/ascii-spiders) by @stackedlol (MIT), commit 89a7721.

The port keeps the original's structure, names (camelCase), constants, comments, timings and order of
operations, including the order of random draws. Seeded with the same stream, `OrbWeb` reproduces the
original `web.ts` to the 12 digits node prints (check `orbWebMatchesOriginal`). What differs, and why:

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
- **`prey` is `[AnyObject]`** until flies.ts is ported (Task 9 types it `[Fly]`).
- **Sorts are stable.** `Array.prototype.sort` is stable; Swift's `sort` doesn't promise to be, so the
  anchor and frame-point sorts keep ties in their original order.
- **`buildInstant(upTo)` defaults to `nil`** meaning `route.length` (Swift default arguments can't read
  `self`).
- **`step` reads `isFree`'s inputs once per call** (pin, held, hub, hubPinned). None of them change
  before the break pass, so it's the same test, without a property access per thread per iteration.
