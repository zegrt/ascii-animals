import CoreGraphics
import Foundation

/// The seven kinds, in the sketch's `KINDS` order (html:761); their numbers are `MeadowTuning.kinds`.
public enum FlowerKind: Int, CaseIterable, Sendable {
    case daisy, coneflower, milkweed, fennel, clover, mustard, dandelion

    public var spec: MeadowTuning.Kind { MeadowTuning.kinds[rawValue] }
    public var name: String { String(describing: self) }
}

/// A leaf of a bloom's rosette, lying on the ground under it (it doesn't sway with the head). Lengths in pt.
public struct FlowerLeaf: Equatable, Sendable {
    public var angle: Double
    public var length: Double
    public var width: Double
    /// 0 plain, 1 thread (fennel), 2 toothed, 3 trefoil (clover), 4 lobed (dandelion).
    public var kind: Int
}

/// One of mustard's florets, placed from the bloom's centre (pt).
public struct Floret: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var size: Double
    public var open: Bool
    public var turn: Double
}

/// A bloom seen from above (the sketch's flower object, html:774–802). Found by `id`, never by its place in the array:
/// the array is reordered by a replant and shrinks as faded flowers go.
public struct Flower: Equatable, Sendable {
    public let id: Int
    public let kind: FlowerKind
    /// Centre of the plant on the ground (pt, ocean space).
    public var x: Double
    public var y: Double
    /// Bloom radius (pt), at full growth.
    public var radius: Double
    /// The bloom's turn (rad) and its own seed (for the painter's patterns).
    public let turn: Double
    public let seed: Int
    /// Growth, 0…1: drawn at `MeadowMath.easeOutBack(age)` (overshoots before it settles).
    public var age: Double
    /// Petals (`n`), 0 where the kind has none.
    public let petals: Int
    /// The head's natural frequency on its stem, Hz.
    public let f0: Double
    /// The head's offset from the centre (pt) and its velocity (pt/s): a damped spring in the wind.
    public var ox = 0.0
    public var oy = 0.0
    public var vx = 0.0
    public var vy = 0.0
    /// The butterfly bound for or on it (0: none). The world sets it.
    public var busy = 0
    public var leaves: [FlowerLeaf]
    public var florets: [Floret]
    /// Planted by a click (kept by a replant, counted against the click limit).
    public let clicked: Bool
    /// The visited dim: seconds left, of `dimMax`.
    public var dimT = 0.0
    public var dimMax = 1.0
    /// Fed: 0…1, eased toward 1 while a butterfly feeds on it.
    public var lift = 0.0
    /// The world sets this each step: a butterfly is feeding on it (`state === 'nectar'` on this flower).
    public var feeding = false
    /// Closing and fading: `fade` runs 1 → 0 over `Clicks.fadeTime`, then it goes.
    public var fading = false
    public var fade = 1.0
    /// When it was last touched (simulation s).
    public var touchedAt = -9.0
    /// `flowerSize · S` it was made at (a replant rescales it to the current one).
    public var sizeK: Double
    /// How far its drawing reaches from the centre (pt).
    public var reach: Double

    /// Drawn growth: `easeOutBack(age)`, 1 once grown (`growOf`, html:880).
    public var grow: Double { age >= 1 ? 1 : MeadowMath.easeOutBack(age) }
    /// The visited dim, 0…1 (`visitDim`, html:978).
    public var visitDim: Double { dimT > 0 ? MeadowMath.smooth(0, 0.35, dimT / dimMax) : 0 }
}

/// A pollen spark a click let off (the sketch pushes them onto its dust, html:900–903, 926–930). The flowers draw
/// them so the input stream keeps the sketch's order; the world takes them for its dust (`takeSparks`).
public struct PollenSpark: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public var life: Double
    public var max: Double
}

/// What a click did.
public enum FlowerClick: Equatable, Sendable {
    /// Off the meadow, or not a number: nothing.
    case ignored
    /// It touched a bloom (the one under it, or the one in the way of a new one).
    case touched(id: Int, sparks: Int)
    /// It planted a new bloom where there was room.
    case bloomed(id: Int, sparks: Int)
}

/// The meadow's flowers, ported from the sketch (html:761–968): planted in patches per screen, each head a damped
/// spring in the wind, growing in with an overshoot, lit while fed, dimmed after a visit; clicks touch a bloom or
/// bloom one where there's room, with the click limit and the 2 s fade; and the replant transition.
///
/// Fixed 1/60 s steps only, with the `Breeze` it reads the wind from (step the breeze first, then the flowers, as
/// the sketch's `step` does). Nothing allocates per step once planted.
public final class Flowers {
    /// The flowers, small first (the sketch's draw order); clicked blooms are added on top.
    public private(set) var all: [Flower] = []
    /// The air they sway in.
    public let breeze: Breeze
    public private(set) var terrain: Terrain
    public private(set) var cell: CGSize
    public var tuning: MeadowTuning
    /// The last flower id given (`flowerId`, html:772): every made flower takes one, kept or not, as the sketch's.
    public private(set) var lastId = 0
    /// Patches the last planting laid out.
    public private(set) var patches = 0
    /// Pollen sparks let off by clicks, not yet taken.
    public private(set) var sparks: [PollenSpark] = []

    /// A touch on a bloom: any butterfly feeding on flower `id` takes off away from (x, y) (the sketch's
    /// `takeOff(b, x, y, true)` in `touchFlower`). Called after the puff is drawn, as the sketch.
    public var onTouched: ((_ id: Int, _ x: Double, _ y: Double) -> Void)?
    /// Flower `id` is closing (over the limit, off the screens, or crowded out by a replant): every butterfly bound
    /// for or on it leaves it (`fadeFlower` → `leaveFlower`).
    public var onClosing: ((_ id: Int) -> Void)?
    /// A replant finished: butterflies whose flower is gone (`flower(id:) == nil`) leave it (html:870).
    public var onReplanted: (() -> Void)?

    private var unit: Double { breeze.unit }
    private var cw: Double {
        let w = Double(cell.width)
        return w.isFinite && w > 0 ? min(w, 1000) : MeadowTuning.Unit.referenceCell
    }
    private static let sparkCapacity = 256

    public init(terrain: Terrain, cell: CGSize, breeze: Breeze, tuning: MeadowTuning = .director) {
        self.terrain = terrain
        self.cell = cell
        self.breeze = breeze
        self.tuning = tuning.sanitized()
        sparks.reserveCapacity(Flowers.sparkCapacity)
    }

    // ── finding ──

    /// Where flower `id` is in `all` now, or nil once it has gone.
    public func index(of id: Int) -> Int? {
        for i in all.indices where all[i].id == id { return i }
        return nil
    }

    /// Flower `id`, or nil once it has gone (`flowerById`, html:970).
    public func flower(id: Int) -> Flower? { index(of: id).map { all[$0] } }

    // ── making and planting ──

    /// `pickKind` (html:804–807): a kind by weight, one draw.
    public func pickKind(_ rng: MeadowRandom) -> FlowerKind {
        var tot = 0.0
        for k in FlowerKind.allCases { tot += k.spec.weight }
        var u: Double = rng.unit() * tot
        for k in FlowerKind.allCases {
            u -= k.spec.weight
            if u <= 0 { return k }
        }
        return .daisy
    }

    private func pick(_ p: MeadowTuning.Pick, _ rng: MeadowRandom) -> Double {
        switch p {
        case .fixed(let v): return v
        case .between(let a, let b): return rng.range(a, b)
        }
    }

    /// `makeFlower(kind, x, y, grown)` (html:774–802): draws its size, turn, seed, petals, f0, rosette and florets
    /// in the sketch's order, and takes the next id.
    public func make(_ kind: FlowerKind, x: Double, y: Double, grown: Bool, rng: MeadowRandom) -> Flower {
        let K = kind.spec
        let size: Double = K.r * unit * tuning.flowerSize
        let R0: Double = size * rng.range(MeadowTuning.Flowers.sizeLow, MeadowTuning.Flowers.sizeHigh)
        lastId += 1
        let id = lastId
        let turn = rng.range(0, TAU)
        let seed = rng.int(1, 1_000_000)
        let petals = rng.int(K.petals.lowerBound, K.petals.upperBound)
        let f0 = rng.range(K.f0.0, K.f0.1)
        var leaves: [FlowerLeaf] = []
        let a0 = rng.range(0, TAU)
        switch K.rosette {
        case let .ring(count, step, jitter, length, width, leafKind):
            let n = rng.int(count.lowerBound, count.upperBound)
            leaves.reserveCapacity(n)
            for i in 0..<n {
                let gap: Double = step ?? TAU / Double(n)
                let a: Double = a0 + Double(i) * gap + rng.range(-jitter, jitter)
                let len = pick(length, rng) * R0
                let wid = pick(width, rng) * R0
                leaves.append(FlowerLeaf(angle: a, length: len, width: wid, kind: leafKind))
            }
        case let .cross(main, chance, extra):
            for l in main {
                let len = pick(l.length, rng) * R0
                let wid = pick(l.width, rng) * R0
                leaves.append(FlowerLeaf(angle: a0 + l.offset, length: len, width: wid, kind: l.kind))
            }
            if rng.unit() < chance {
                for l in extra {
                    let len = pick(l.length, rng) * R0
                    let wid = pick(l.width, rng) * R0
                    leaves.append(FlowerLeaf(angle: a0 + l.offset, length: len, width: wid, kind: l.kind))
                }
            }
        }
        var florets: [Floret] = []
        if kind == .mustard {
            typealias F = MeadowTuning.Florets
            let m = rng.int(F.count.lowerBound, F.count.upperBound)
            let md = Double(m)
            for i in 0..<m {
                let di = Double(i)
                let r: Double = R0 * (F.inner + F.spread * ((di + 0.5) / md).squareRoot())
                let a: Double = di * F.turn + turn
                let s: Double = R0 * rng.range(F.sizeLow, F.sizeHigh) * (1 - F.shrink * (di / md))
                let rot = rng.range(0, TAU)
                florets.append(Floret(x: cos(a) * r, y: sin(a) * r, size: s, open: i > 0, turn: rot))
            }
        }
        var f = Flower(id: id, kind: kind, x: x, y: y, radius: R0, turn: turn, seed: seed, age: grown ? 1 : 0,
                       petals: petals, f0: f0, leaves: leaves, florets: florets, clicked: !grown,
                       sizeK: tuning.flowerSize * unit, reach: 0)
        f.reach = reach(of: f)
        return f
    }

    private func reach(of f: Flower) -> Double {
        var longest: Double = f.radius * MeadowTuning.Flowers.reachHead
        for l in f.leaves { longest = max(longest, l.length) }
        return longest + MeadowTuning.Flowers.reachCells * cw
    }

    /// Whether a bloom of the screen `r` may stand at p (the sketch: up to 10 pt past the window's edge,
    /// html:829). The port: on screen `r`, or up to 10 pt past one of its real edges; never on another screen
    /// (a patch doesn't cross an edge two screens share) and never in a gap between screens (a point inside the
    /// terrain's bounds that no screen holds).
    public func mayStand(_ x: Double, _ y: Double, screen r: CGRect) -> Bool {
        guard x.isFinite && y.isFinite else { return false }
        let s = MeadowTuning.Flowers.edgeSlack
        let minX = Double(r.minX), maxX = Double(r.maxX), minY = Double(r.minY), maxY = Double(r.maxY)
        if x < minX - s || y < minY - s || x > maxX + s || y > maxY + s { return false }
        if x >= minX && x <= maxX && y >= minY && y <= maxY { return true }
        if terrain.contains(SIMD2(x, y)) { return false }   // past a shared edge, on the next screen
        let b = terrain.bounds
        let inBounds = x >= Double(b.minX) && x <= Double(b.maxX) && y >= Double(b.minY) && y <= Double(b.maxY)
        return !inBounds
    }

    /// Whether a flower centre at p is somewhere a bloom may stand at all (on some screen, or just past a real edge).
    public func mayStand(_ x: Double, _ y: Double) -> Bool {
        terrain.rects.contains { mayStand(x, y, screen: $0) }
    }

    /// `plant()` (html:809–843): the meadow's patches around the flowers already there, screen by screen, then all
    /// sorted small first. Per screen: `max(1, round(area / (190000 · S²) · density))` patches, each centre the best
    /// of 10 for distance from the others, 20 · S in from the edges; blooms within the patch's spread, up to 14 tries
    /// each, never overlapping (centres `(R1 + R2) · 1.05` apart).
    public func plant(rng: MeadowRandom) {
        typealias F = MeadowTuning.Flowers
        patches = 0
        var centres: [SIMD2<Double>] = []
        let margin: Double = F.patchMargin * unit
        for r in terrain.rects {
            let rx = Double(r.minX), ry = Double(r.minY), W = Double(r.width), H = Double(r.height)
            guard W.isFinite && H.isFinite && rx.isFinite && ry.isFinite && W > 0 && H > 0 else { continue }
            let perArea: Double = W * H / (F.patchArea * unit * unit) * tuning.density
            let count = Int(min(Double(F.maxPatches), max(1, MeadowMath.round(perArea))))
            for _ in 0..<count {
                var best = SIMD2<Double>(rx + W / 2, ry + H / 2)
                var bestD = -1.0
                for _ in 0..<F.patchCandidates {
                    let x: Double = rx + rng.range(margin, W - margin)
                    let y: Double = ry + rng.range(margin, H - margin)
                    var d = 1e9
                    for c in centres {
                        let ex: Double = c.x - x
                        let ey: Double = c.y - y
                        d = min(d, (ex * ex + ey * ey).squareRoot())
                    }
                    if d > bestD { bestD = d; best = SIMD2(x, y) }
                }
                centres.append(best)
                patches += 1
                let kind = pickKind(rng)
                let K = kind.spec
                let n = rng.int(K.perPatch.lowerBound, K.perPatch.upperBound)
                let spread: Double = K.r * unit * tuning.flowerSize * (F.patchSpread + F.patchSpreadPerBloom * Double(n))
                for _ in 0..<n {
                    for _ in 0..<F.bloomTries {
                        let a = rng.range(0, TAU)
                        let rr: Double = spread * rng.unit().squareRoot()
                        let x: Double = best.x + cos(a) * rr
                        let y: Double = best.y + sin(a) * rr
                        if !mayStand(x, y, screen: r) { continue }
                        let cand = make(kind, x: x, y: y, grown: true, rng: rng)
                        if !overlapsAny(cand) { all.append(cand); break }
                    }
                }
            }
        }
        sortSmallFirst()
    }

    private func overlapsAny(_ f: Flower) -> Bool {
        for o in all {
            let dx: Double = o.x - f.x
            let dy: Double = o.y - f.y
            if (dx * dx + dy * dy).squareRoot() < (o.radius + f.radius) * MeadowTuning.Flowers.spacing { return true }
        }
        return false
    }

    /// Small ones first so the big blooms lie over them (a stable sort, as the sketch's).
    private func sortSmallFirst() {
        let order = all.indices.sorted { all[$0].radius < all[$1].radius || (all[$0].radius == all[$1].radius && $0 < $1) }
        all = order.map { all[$0] }
    }

    // ── stepping ──

    /// One fixed step of every flower (`stepFlowers`, html:948–968): lift, fade, growth, the visited dim and the
    /// head's spring in the wind at its centre. Faded flowers go (their ids are never reused).
    public func step(_ dt: Double) {
        guard dt.isFinite && dt > 0 else { return }
        typealias F = MeadowTuning.Flowers
        var gone = false
        let liftK: Double = min(1, dt * F.liftRate)
        let dragSize: Double = F.dragSize * unit
        for i in all.indices {
            let fed: Double = all[i].feeding ? 1 : 0
            all[i].lift += (fed - all[i].lift) * liftK
            if all[i].fading {
                all[i].fade -= dt / MeadowTuning.Clicks.fadeTime
                if all[i].fade <= 0 { gone = true }
            }
            if all[i].age < 1 { all[i].age = min(1, all[i].age + dt / F.growTime) }
            if all[i].dimT > 0 { all[i].dimT = max(0, all[i].dimT - dt) }
            let air = breeze.sample(all[i].x, all[i].y)
            let w: Double = TAU * all[i].f0
            let k: Double = F.drag * (1 + F.dragBySize * (all[i].radius / dragSize))
            let fx: Double = air.x * air.speed * k
            let fy: Double = air.y * air.speed * k
            let ax: Double = fx - w * w * all[i].ox - 2 * F.zeta * w * all[i].vx
            let ay: Double = fy - w * w * all[i].oy - 2 * F.zeta * w * all[i].vy
            all[i].vx += ax * dt
            all[i].vy += ay * dt
            all[i].ox += all[i].vx * dt
            all[i].oy += all[i].vy * dt
            let lim: Double = F.swingLimit * all[i].radius
            let m: Double = (all[i].ox * all[i].ox + all[i].oy * all[i].oy).squareRoot()
            if m > lim {
                all[i].ox *= lim / m
                all[i].oy *= lim / m
            }
            if !(all[i].ox.isFinite && all[i].oy.isFinite && all[i].vx.isFinite && all[i].vy.isFinite) {
                all[i].ox = 0; all[i].oy = 0; all[i].vx = 0; all[i].vy = 0
            }
        }
        if gone { all.removeAll { $0.fading && $0.fade <= 0 } }
    }

    // ── what the butterflies do to them (the world calls these) ──

    /// `nodFlower` (html:1514–1518): an impulse to the head along (dx, dy), peaking near 0.12 R × size × k. A
    /// landing nods with k 1 along the butterfly's way, a take-off with k 0.5 back.
    public func nod(id: Int, dx: Double, dy: Double, size: Double, k: Double) {
        guard tuning.nod > 0, let i = index(of: id), dx.isFinite, dy.isFinite, size.isFinite, k.isFinite else { return }
        let v: Double = MeadowTuning.Clicks.landingNod * all[i].radius * size * TAU * all[i].f0 * tuning.nod * k
        all[i].vx += dx * v
        all[i].vy += dy * v
    }

    /// A butterfly fed on flower `id` and left: its disc dims for 20–40 s (one draw, html:1525).
    public func visited(id: Int, rng: MeadowRandom) {
        guard let i = index(of: id) else { return }
        all[i].dimMax = rng.range(MeadowTuning.Flowers.dimLow, MeadowTuning.Flowers.dimHigh)
        all[i].dimT = all[i].dimMax
    }

    /// Who is bound for or on flower `id` (0 frees it).
    public func setBusy(id: Int, by butterfly: Int) {
        if let i = index(of: id) { all[i].busy = butterfly }
    }

    /// Whether a butterfly is feeding on flower `id`, for this step's lift.
    public func setFeeding(id: Int, _ on: Bool) {
        if let i = index(of: id) { all[i].feeding = on }
    }

    // ── clicks ──

    /// `clickAt(x, y)`'s flower part (html:882–906): on or near a bloom (within about its drawn radius, from the head
    /// as it sways), touch the nearest; on open ground, a new bloom only where it has room by the planting rule,
    /// else touch the bloom in the way whose edge is nearest; then the click limit. Draws from `rng` (the input
    /// stream) in the sketch's order. A click off the meadow does nothing. Answering a fresh bloom with a butterfly
    /// is the world's (after this returns, as the sketch's order).
    @discardableResult
    public func click(x: Double, y: Double, rng: MeadowRandom) -> FlowerClick {
        guard x.isFinite && y.isFinite && terrain.contains(SIMD2(x, y)) else { return .ignored }
        typealias C = MeadowTuning.Clicks
        var hit = -1
        var hd = 1e9
        for i in all.indices where !all[i].fading {
            let f = all[i]
            let ex: Double = f.x + f.ox - x
            let ey: Double = f.y + f.oy - y
            let d: Double = (ex * ex + ey * ey).squareRoot()
            let rr: Double = max(f.radius * f.grow, C.hitBloom * f.radius) + C.hitCells * cw
            if d < rr && d / rr < hd { hd = d / rr; hit = i }
        }
        if hit >= 0 { return touch(index: hit, x: x, y: y, rng: rng) }
        let kind = pickKind(rng)
        let f = make(kind, x: x, y: y, grown: false, rng: rng)
        var block = -1
        var bd = 1e9
        for i in all.indices where !all[i].fading {
            let o = all[i]
            let ex: Double = o.x - x
            let ey: Double = o.y - y
            let d: Double = (ex * ex + ey * ey).squareRoot()
            let need: Double = (o.radius + f.radius) * MeadowTuning.Flowers.spacing
            if d - need < 0 && abs(d - o.radius) < bd { bd = abs(d - o.radius); block = i }
        }
        if block >= 0 { return touch(index: block, x: x, y: y, rng: rng) }
        all.append(f)
        for _ in 0..<C.bloomSparks {
            let a = rng.range(0, TAU)
            let v: Double = rng.range(20, 70) * unit
            let life = rng.range(1.2, 2.2)
            addSpark(PollenSpark(x: x, y: y, vx: cos(a) * v, vy: sin(a) * v, life: life, max: 2.2))
        }
        limitClicked()
        return .bloomed(id: f.id, sparks: C.bloomSparks)
    }

    /// `touchFlower` (html:917–931): the head nods away from the click on its spring (less if already swung far),
    /// a small puff of pollen, and a butterfly feeding on it takes off (`onTouched`).
    private func touch(index i: Int, x: Double, y: Double, rng: MeadowRandom) -> FlowerClick {
        typealias C = MeadowTuning.Clicks
        let hx: Double = all[i].x + all[i].ox
        let hy: Double = all[i].y + all[i].oy
        var dx: Double = hx - x
        var dy: Double = hy - y
        let d: Double = (dx * dx + dy * dy).squareRoot()
        if d < C.touchCentre * all[i].radius {
            let a = rng.range(0, TAU)
            dx = cos(a)
            dy = sin(a)
        } else {
            dx /= d
            dy /= d
        }
        if tuning.nod > 0 {
            let swung: Double = (all[i].ox * all[i].ox + all[i].oy * all[i].oy).squareRoot()
            let room: Double = clamp(1 - swung / (MeadowTuning.Flowers.swingLimit * all[i].radius), C.touchLeast, 1)
            let v: Double = C.touchNod * all[i].radius * TAU * all[i].f0 * tuning.nod * room
            all[i].vx += dx * v
            all[i].vy += dy * v
        }
        let now = breeze.time
        let n = now - all[i].touchedAt < C.puffWithin ? C.puffAgain : C.puff
        all[i].touchedAt = now
        let R = all[i].radius
        for _ in 0..<n {
            let a = rng.range(0, TAU)
            let v: Double = rng.range(15, 45) * unit
            let r: Double = rng.range(0, 0.3) * R
            let life = rng.range(0.7, 1.4)
            let push: Double = 20 * unit
            let sx: Double = cos(a) * v + dx * push
            let sy: Double = sin(a) * v + dy * push
            addSpark(PollenSpark(x: hx + cos(a) * r, y: hy + sin(a) * r, vx: sx, vy: sy, life: life, max: 1.4))
        }
        let id = all[i].id
        onTouched?(id, x, y)
        return .touched(id: id, sparks: n)
    }

    private func addSpark(_ s: PollenSpark) {
        if sparks.count < Flowers.sparkCapacity { sparks.append(s) }
    }

    /// The sparks clicks let off since the last call, for the world's dust; the buffer is kept (no allocation).
    public func takeSparks(_ into: (PollenSpark) -> Void) {
        for s in sparks { into(s) }
        sparks.removeAll(keepingCapacity: true)
    }

    /// Clicked flowers still open (not fading).
    public var clickedOpen: Int {
        var n = 0
        for f in all where f.clicked && !f.fading { n += 1 }
        return n
    }

    /// `limitClicked` (html:933–936): beyond the limit, the oldest clicked flowers close and fade.
    public func limitClicked() {
        var open = clickedOpen
        while open > tuning.clickLimit {
            var oldest = -1
            for i in all.indices where all[i].clicked && !all[i].fading {
                if oldest < 0 || all[i].id < all[oldest].id { oldest = i }
            }
            guard oldest >= 0 else { break }
            close(index: oldest)
            open -= 1
        }
    }

    /// `fadeFlower` (html:937–941): it closes and fades over 2 s; every butterfly bound for or on it leaves it.
    private func close(index i: Int) {
        all[i].fading = true
        all[i].fade = 1
        let id = all[i].id
        onClosing?(id)
        if let j = index(of: id) { all[j].busy = 0 }
    }

    // ── relayout and replant ──

    /// The screens changed (the sketch's `resize`, html:2881–2886, with the port's rules). Any clicked flower the new
    /// screens leave off the meadow closes and fades, at any size of change (the re-check's finding 4); a planted
    /// one whose centre may no longer stand there (off the screens or in a gap) fades too. If any screen changed by
    /// more than 80 pt (or screens came or went), the meadow is replanted (`replant(false)`); a cell size change
    /// rescales the clicked flowers then. Draws from `rng` (the input stream, as the sketch's resize).
    public func relayout(terrain new: Terrain, cell: CGSize, rng: MeadowRandom) {
        let old = terrain
        terrain = new
        self.cell = cell
        var big = old.rects.count != new.rects.count
        if !big {
            for (a, b) in zip(old.rects, new.rects) {
                let lim = MeadowTuning.Relayout.replantBeyond
                if abs(Double(a.width - b.width)) > lim || abs(Double(a.height - b.height)) > lim
                    || abs(Double(a.minX - b.minX)) > lim || abs(Double(a.minY - b.minY)) > lim { big = true; break }
            }
        }
        for i in all.indices where !all[i].fading {
            let f = all[i]
            if !mayStand(f.x, f.y) || (f.clicked && !terrain.contains(SIMD2(f.x, f.y))) { close(index: i) }
        }
        if big { replant(fresh: false, rng: rng) }
    }

    /// `replant(fresh)` (html:855–871), the one replant transition: keeps the flowers you clicked (none when
    /// `fresh`) that are still on the meadow, at the current flower size (a clicked one off it is already fading,
    /// and finishes); of two now overlapping, the newer closes and fades; plants the rest; applies the click limit;
    /// then `onReplanted`, so butterflies whose flower has gone leave it.
    public func replant(fresh: Bool, rng: MeadowRandom) {
        if fresh {
            all.removeAll()
        } else {
            all.removeAll { f in !(f.clicked && (f.fading || terrain.contains(SIMD2(f.x, f.y)))) }
        }
        for i in all.indices { resize(index: i) }
        var mine: [Int] = all.indices.filter { !all[$0].fading }
        mine.sort { all[$0].id < all[$1].id }
        if mine.count > 1 {
            for a in 1..<mine.count {
                let fi = all[mine[a]]
                for b in 0..<a {
                    let o = all[mine[b]]
                    if o.fading { continue }
                    let dx: Double = o.x - fi.x
                    let dy: Double = o.y - fi.y
                    if (dx * dx + dy * dy).squareRoot() < (o.radius + fi.radius) * MeadowTuning.Flowers.spacing {
                        close(index: mine[a])
                        break
                    }
                }
            }
        }
        plant(rng: rng)
        limitClicked()
        onReplanted?()
    }

    /// `sizeFlower` (html:845–852): a clicked flower follows the flower size and the cell, scaled from the size it was
    /// made at.
    private func resize(index i: Int) {
        let now: Double = tuning.flowerSize * unit
        let k: Double = now / all[i].sizeK
        guard k.isFinite && k > 0 && abs(k - 1) >= 1e-9 else { return }
        all[i].radius *= k
        for j in all[i].leaves.indices {
            all[i].leaves[j].length *= k
            all[i].leaves[j].width *= k
        }
        for j in all[i].florets.indices {
            all[i].florets[j].x *= k
            all[i].florets[j].y *= k
            all[i].florets[j].size *= k
        }
        all[i].sizeK = now
        all[i].reach = reach(of: all[i])
    }
}
