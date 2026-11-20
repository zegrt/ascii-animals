import CoreGraphics
import Foundation
import simd

/// A grain of pollen or a spark (the sketch's `dust`, html:1291): drifts with the air and fades.
public struct MeadowDust: Sendable {
    public var x: Double, y: Double, vx: Double, vy: Double, life: Double, max: Double
    public var spark: Bool
}

/// The Meadow's world, ported from the sketch (`Tools/meadow-sketch/meadow.html` on `meadow-sketch` at 4e1b869;
/// `html:N` below is a line of it): the air and the flowers (m1's `Breeze` and `Flowers`), the butterflies' flight
/// from above with height, their wants and visits, the pointer (a still pointer is landed on; a click blooms or
/// touches a flower and may call one butterfly), the pollen, and the count kept through real edges.
///
/// Fixed 1/60 s steps only (`OceanClock.step`); nothing depends on the frame rate. Two random streams from one seed,
/// as the sketch: the meadow's own for planting, flight and the opening, the input's for everything a pointer event
/// causes. Nothing allocates per step once the butterflies are made.
///
/// **Several screens** (the terrain's rects; the sketch has one window): where the sketch reads its window `W × H`,
/// the port reads the screen in question, picked by area where the sketch picks a random point (so one screen is the
/// sketch exactly, draw for draw). Real edges are the sketch's window edges; an edge two screens share is open; the
/// space between two screens side by side (a gap) is never entered.
public final class MeadowWorld {
    public let breeze: Breeze
    public let flowers: Flowers
    public private(set) var terrain: Terrain
    public private(set) var cell: CGSize
    /// The director's settings, put right on every write.
    public var tuning: MeadowTuning {
        didSet {
            tuning = tuning.sanitized()
            breeze.tuning = tuning
            flowers.tuning = tuning
        }
    }
    /// The most butterflies this scene holds with `areaCount` on: `MeadowTuning.areaCountLimit`, or this screen's
    /// share of it when each screen of the desk is its own scene (`MeadowTuning.areaCountShares`; 0 once the 12 are
    /// all placed on other screens). A new limit takes effect at the next `syncFlies`.
    public var countLimit: Int = MeadowTuning.areaCountLimit
    /// With `areaCount` on: the most butterflies this scene may draw now, the ones leaving included (the desk's 12 less
    /// what its other scenes draw; `MeadowSim.room`). Unset, 12. Newcomers wait for room, so the desk never draws more
    /// than 12, also while a change is on its way. With `areaCount` off (the sketch) there is no such limit.
    public var room: (() -> Int)?
    /// The app's speed setting: the pointer's real time per step is `OceanClock.step / speed` (the sketch's Slow motion).
    public var speed = 1.0

    let simRandom: MeadowRandom
    let inputRandom: MeadowRandom
    /// The stream drawing now (`rnd`, html:161): the meadow's, or the input's inside a pointer event.
    var rng: MeadowRandom

    /// The butterflies, in the order they joined.
    public internal(set) var flies: [Butterfly] = []
    var flyId = 1
    /// Pollen and sparks, at most `dustCapacity` (a grain past it is dropped).
    public private(set) var dust: [MeadowDust] = []
    static let dustCapacity = 2048
    var cursorCd = 0.0
    var answerAt = -1e9

    // The pointer (the sketch's `ptr`, html:2683): where it is, where it came to rest, how long it has been still.
    public private(set) var pointerX = 0.0, pointerY = 0.0
    public private(set) var pointerHas = false
    var pointerAX = 0.0, pointerAY = 0.0, pointerStill = 0.0

    // The screens, as plain numbers.
    struct Screen {
        var minX: Double, minY: Double, w: Double, h: Double
        var maxX: Double { minX + w }
        var maxY: Double { minY + h }
        var diag: Double { (w * w + h * h).squareRoot() }
    }
    var screens: [Screen] = []
    /// The gaps between screens side by side (not touching, by the terrain's rule), as boxes: the one between two
    /// screens, across the span where both are level. A point in one that no screen holds is in a gap.
    var gaps: [Screen] = []
    var screenArea = 0.0
    var wallLength = 0.0
    /// For each screen, the group it belongs to: screens joined by shared edges, so a butterfly can fly between them.
    /// Screens in different groups have no way between them (a gap, or only a corner).
    var groupOf: [Int] = []
    var groupCount = 0
    /// The terrain's real edges, the world's own copy (read every step by `signedOutside`).
    var walls: [Terrain.Edge] = []
    var single: Bool { screens.count == 1 }

    // Reused buffers (no allocation per step).
    var candFlower: [Int] = []
    var candWeight: [Double] = []
    var candFly: [Butterfly] = []

    /// The meadow for `seed` on `terrain`: planted, its butterflies made and the opening moment set (the sketch's
    /// `start`, html:3033–3038).
    public init(terrain: Terrain, cell: CGSize, tuning: MeadowTuning = .director, seed: Int32,
                countLimit: Int = MeadowTuning.areaCountLimit, room: (() -> Int)? = nil) {
        let t = tuning.sanitized()
        self.tuning = t
        self.countLimit = max(0, countLimit)
        self.room = room
        self.terrain = terrain
        self.cell = cell
        let usable = MeadowWorld.usable(terrain) ? terrain : Terrain(rects: [])
        breeze = Breeze(terrain: usable, cell: cell, tuning: t)
        flowers = Flowers(terrain: usable, cell: cell, breeze: breeze, tuning: t)
        let streams = MeadowRandom.pair(seed: seed)
        simRandom = streams.sim
        inputRandom = streams.input
        rng = simRandom
        dust.reserveCapacity(MeadowWorld.dustCapacity)
        candFlower.reserveCapacity(512)
        candWeight.reserveCapacity(512)
        candFly.reserveCapacity(64)
        setScreens()
        // Weak: the public `flowers` may outlive its world (then a touch, close or replant tells nobody).
        flowers.onTouched = { [weak self] id, x, y in
            guard let self else { return }
            for b in self.flies where b.flower == id && b.state == .nectar { self.takeOff(b, away: (x, y), escape: true) }
        }
        flowers.onClosing = { [weak self] id in
            guard let self else { return }
            for b in self.flies where b.flower == id { self.leaveFlower(b) }
        }
        flowers.onReplanted = { [weak self] in
            guard let self else { return }
            for b in self.flies where b.flower != 0 && self.flowers.index(of: b.flower) == nil { self.leaveFlower(b) }
        }
        guard !screens.isEmpty else { return }
        flowers.plant(rng: simRandom)
        syncFlies(initial: true)
        openingMoment()
    }

    deinit {
        flowers.onTouched = nil
        flowers.onClosing = nil
        flowers.onReplanted = nil
    }

    public var time: Double { breeze.time }
    /// `S`: sketch points per point.
    @inline(__always) var S: Double { breeze.unit }
    /// The cell width the meadow uses (`cw`).
    @inline(__always) var cw: Double { MeadowTuning.Unit.cellWidth(Double(cell.width)) }

    /// Whether every screen of `t` is one the meadow can live on: at least 1 pt each way, its edges within
    /// ±`Unit.coordinateLimit` (so nothing derived from it overflows), and real edges to come and go by. Otherwise the
    /// meadow has no screen: its butterflies hold still and nothing is planted until a usable layout comes.
    static func usable(_ t: Terrain) -> Bool {
        let lim = MeadowTuning.Unit.coordinateLimit
        for r in t.rects {
            let x0 = Double(r.minX), y0 = Double(r.minY), w = Double(r.width), h = Double(r.height)
            guard x0.isFinite && y0.isFinite && w.isFinite && h.isFinite && w >= 1 && h >= 1 else { return false }
            let x1: Double = x0 + w, y1: Double = y0 + h
            guard abs(x0) <= lim && abs(y0) <= lim && abs(x1) <= lim && abs(y1) <= lim else { return false }
        }
        var wall = 0.0
        for e in t.edges { wall += e.length }
        return !t.rects.isEmpty && wall.isFinite && wall > 0
    }

    private func setScreens() {
        screens = []
        gaps = []
        screenArea = 0
        wallLength = 0
        groupOf = []
        groupCount = 0
        walls = []
        guard MeadowWorld.usable(terrain) else { return }
        screens = terrain.rects.map { r in Screen(minX: Double(r.minX), minY: Double(r.minY), w: Double(r.width), h: Double(r.height)) }
        walls = terrain.edges
        screenArea = screens.reduce(0) { $0 + $1.w * $1.h }
        wallLength = terrain.edges.reduce(0) { $0 + $1.length }
        groupOf = [Int](repeating: -1, count: screens.count)
        for start in 0..<screens.count where groupOf[start] < 0 {
            var todo = [start]
            groupOf[start] = groupCount
            while let i = todo.popLast() {
                for j in terrain.neighbours[i] where groupOf[j] < 0 { groupOf[j] = groupCount; todo.append(j) }
            }
            groupCount += 1
        }
        // Facing sides closer than the terrain's touch are one shared edge (open); further apart, a gap.
        for a in screens {
            for b in screens {
                if b.minX - a.maxX >= Terrain.touch {
                    let lo = max(a.minY, b.minY), hi = min(a.maxY, b.maxY)
                    if lo <= hi { gaps.append(Screen(minX: a.maxX, minY: lo, w: b.minX - a.maxX, h: hi - lo)) }
                }
                if b.minY - a.maxY >= Terrain.touch {
                    let lo = max(a.minX, b.minX), hi = min(a.maxX, b.maxX)
                    if lo <= hi { gaps.append(Screen(minX: lo, minY: a.maxY, w: hi - lo, h: b.minY - a.maxY)) }
                }
            }
        }
    }

    // ── the screens (the sketch's W × H, per screen) ──

    /// A screen picked in proportion to its area: one draw, none with one screen (so one screen is the sketch).
    func screenByArea() -> Int {
        if screens.count <= 1 { return 0 }
        var u = rng.unit() * screenArea
        for (i, s) in screens.enumerated() {
            u -= s.w * s.h
            if u < 0 { return i }
        }
        return screens.count - 1
    }

    /// A screen of group `g` picked in proportion to its area (one draw); any screen when `g` is nil.
    func screenByArea(inGroup g: Int?) -> Int {
        guard let g, groupCount > 1 else { return screenByArea() }
        var area = 0.0
        for (i, s) in screens.enumerated() where groupOf[i] == g { area += s.w * s.h }
        var u = rng.unit() * area
        var last = 0
        for (i, s) in screens.enumerated() where groupOf[i] == g {
            last = i
            u -= s.w * s.h
            if u < 0 { return i }
        }
        return last
    }

    /// The group of the screen holding (x, y), else of the nearest.
    @inline(__always) func group(near x: Double, _ y: Double) -> Int {
        groupCount > 1 ? groupOf[screen(near: x, y)] : 0
    }

    /// The screen holding (x, y), else the nearest.
    @inline(__always) func screen(near x: Double, _ y: Double) -> Int {
        if screens.count <= 1 { return 0 }
        return terrain.rectIndex(near: SIMD2(x, y))
    }

    @inline(__always) func onScreens(_ x: Double, _ y: Double) -> Bool {
        for s in screens where x >= s.minX && x <= s.maxX && y >= s.minY && y <= s.maxY { return true }
        return false
    }

    /// In a gap: off every screen, between two screens side by side (one on each side of it, both level with it,
    /// further apart than the terrain's touch).
    func inGap(_ x: Double, _ y: Double) -> Bool {
        if gaps.isEmpty { return false }
        var inside = false
        for g in gaps where x >= g.minX && x <= g.maxX && y >= g.minY && y <= g.maxY { inside = true; break }
        return inside && !onScreens(x, y)
    }

    /// The part of the segment a → b (as t in 0…1) inside the closed box, or nil (Liang–Barsky).
    @inline(__always) static func clip(_ ax: Double, _ ay: Double, _ dx: Double, _ dy: Double, _ s: Screen) -> (Double, Double)? {
        var t0 = 0.0, t1 = 1.0
        @inline(__always) func side(_ p: Double, _ q: Double) -> Bool {
            if p == 0 { return q >= 0 }
            let t: Double = q / p
            if p < 0 { if t > t1 { return false }; if t > t0 { t0 = t } } else { if t < t0 { return false }; if t < t1 { t1 = t } }
            return true
        }
        guard side(-dx, ax - s.minX), side(dx, s.maxX - ax), side(-dy, ay - s.minY), side(dy, s.maxY - ay), t0 <= t1 else { return nil }
        return (t0, t1)
    }

    /// Whether the screens together cover the segment a → b from t0 to t1. A piece of no length (a segment that only
    /// touches a box, as at an exact corner where the gap between two screens is a line) is covered only if its
    /// point is on a screen.
    func covered(_ ax: Double, _ ay: Double, _ dx: Double, _ dy: Double, _ t0: Double, _ t1: Double) -> Bool {
        if t1 - t0 <= 1e-12 {
            let px: Double = ax + dx * t0, py: Double = ay + dy * t0
            return distanceToScreens(px, py) <= 1e-9
        }
        var cur = t0
        var moved = true
        while cur < t1 - 1e-12 && moved {
            moved = false
            for s in screens {
                guard let (c0, c1) = MeadowWorld.clip(ax, ay, dx, dy, s) else { continue }
                if c0 <= cur + 1e-12 && c1 > cur + 1e-12 { cur = c1; moved = true }
            }
        }
        return cur >= t1 - 1e-12
    }

    /// Whether any point of the segment a → b is in a gap (exact: each gap box clipped, less what the screens cover).
    public func segmentEntersGap(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Bool {
        if gaps.isEmpty { return false }
        let dx: Double = bx - ax, dy: Double = by - ay
        if dx == 0 && dy == 0 { return inGap(ax, ay) }
        for g in gaps {
            guard let (t0, t1) = MeadowWorld.clip(ax, ay, dx, dy, g) else { continue }
            if !covered(ax, ay, dx, dy, t0, t1) { return true }
        }
        return false
    }

    /// Whether the straight way from a to b stays on the screens (exact; Web's `wanderGoal` asks the same).
    public func wayOpen(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Bool {
        guard !screens.isEmpty else { return false }
        return covered(ax, ay, bx - ax, by - ay, 0, 1)
    }

    /// Moves `b` to (nx, ny), never into a gap: the whole way, else along x only, else along y only, else it stays.
    /// One already in a gap (it can't be, but if it were) moves freely and the edge steer takes it out. One screen:
    /// it just moves (the sketch).
    @inline(__always) func move(_ b: Butterfly, _ nx: Double, _ ny: Double) {
        if gaps.isEmpty || !segmentEntersGap(b.x, b.y, nx, ny) || inGap(b.x, b.y) { b.x = nx; b.y = ny }
        else if !segmentEntersGap(b.x, b.y, nx, b.y) { b.x = nx }
        else if !segmentEntersGap(b.x, b.y, b.x, ny) { b.y = ny }
    }

    /// Distance from (x, y) to the nearest screen (0 on one).
    func distanceToScreens(_ x: Double, _ y: Double) -> Double {
        var best = Double.infinity
        for s in screens {
            let dx: Double = max(s.minX - x, 0, x - s.maxX), dy: Double = max(s.minY - y, 0, y - s.maxY)
            best = min(best, (dx * dx + dy * dy).squareRoot())
        }
        return best
    }

    /// The terrain's signed distance (`Terrain.signedOutside`: positive off the screens, minus the distance to the
    /// nearest real edge on them), the same numbers, without building an array (it runs every step for entrants).
    /// It reads only the world's own copies (`screens`, `walls`): no copy of the terrain, no closure, no generic call.
    func signedOutside(_ x: Double, _ y: Double) -> Double {
        let p = SIMD2(x, y)
        if screens.isEmpty { return terrain.signedOutside(p) }
        if !onScreens(x, y) {
            // The nearest point on the nearest screen (`Terrain.nearestInside`: the first screen at the least distance).
            var k = 0
            var bestD = Double.infinity
            for (i, s) in screens.enumerated() {
                let q = SIMD2(min(s.maxX, max(s.minX, x)), min(s.maxY, max(s.minY, y)))
                let d: Double = simd_length_squared(p - q)
                if d < bestD { bestD = d; k = i }
            }
            let s = screens[k]
            let near = SIMD2(min(s.maxX, max(s.minX, x)), min(s.maxY, max(s.minY, y)))
            return simd_length(p - near)
        }
        var best = Double.infinity
        for e in walls {
            let d = e.b - e.a
            let t: Double = min(1, max(0, simd_dot(p - e.a, d) / max(simd_length_squared(d), 1e-12)))
            best = min(best, simd_length(p - (e.a + d * t)))
        }
        return best == .infinity ? -0.0 : -best
    }

    // ── sizes (html:1296–1313) ──

    /// `boldOf` (html:1296).
    @inline(__always) func bold(_ b: Butterfly) -> Double { 1 + b.boldU * 0.4 * tuning.boldness }
    /// `spanRef` (html:1298): the wingspan the flight's distances use, pt.
    @inline(__always) func spanRef(_ b: Butterfly) -> Double { b.sp.span * 13 * S * b.size * 0.6 }
    /// `depthScale` (html:2016).
    @inline(__always) public func depthScale(_ z: Double) -> Double {
        let lo = tuning.sizeLow, hi = max(tuning.sizeLow, tuning.sizeHigh)
        return lo * pow(hi / lo, z)
    }
    /// `drawReach` (html:1300).
    func drawReach(_ b: Butterfly) -> Double {
        let span: Double = b.sp.span * 13 * S * b.size * depthScale(b.z)
        return span * 0.5 * 1.15 + 2 * cw
    }

    /// `footprint` (html:1303–1308): left, right, up, down of what it draws, wings and shadow, at height z.
    func footprint(_ b: Butterfly, _ z: Double) -> (l: Double, r: Double, u: Double, d: Double) {
        let base: Double = b.sp.span * 13 * S * b.size
        let r: Double = base * depthScale(z) * 0.5 * 1.15 + 2 * cw
        let g: Double = base * depthScale(0) * 0.5
        let sr: Double = max(g, g * b.sp.aspect * 1.5) + 3 * cw
        let off: Double = z * 150 * S + 3 * S
        let sx: Double = -MeadowLight.x * off, sy: Double = -MeadowLight.y * off
        return (max(r, sr - sx), max(r, sx + sr), max(r, sr - sy), max(r, sy + sr))
    }

    /// `outOfSight` (html:1310–1313): nothing it draws is on any screen.
    func outOfSight(_ b: Butterfly) -> Bool {
        let f = footprint(b, b.z)
        for s in screens where b.x + f.r >= s.minX && b.x - f.l <= s.maxX && b.y + f.d >= s.minY && b.y - f.u <= s.maxY {
            return false
        }
        return true
    }

    // ── making them (html:1316–1446) ──

    /// `makeFly(kind, mode)` (html:1316–1342), drawing in the sketch's order. `group`: on screen at load, put it on a
    /// screen of that group (several screens with no way between them; see `syncFlies`).
    func makeFly(_ kind: ButterflyKind, edge: Bool, group: Int? = nil) -> Butterfly {
        let b = Butterfly(id: flyId, kind: kind)
        flyId += 1
        let sp = b.sp
        let k0 = screenByArea(inGroup: group)
        let s0 = screens[k0]
        b.x = s0.minX + rng.range(0.1, 0.9) * s0.w
        b.y = s0.minY + rng.range(0.1, 0.9) * s0.h
        b.heading = rng.range(0, TAU)
        b.phase = rng.range(0, TAU)
        b.zs = rng.range(0.35, 0.75)
        b.size = 1 + rng.range(-0.12, 0.12)
        b.beatF = 1 + rng.range(-0.1, 0.1)
        b.jinkF = 1 + rng.range(-0.3, 0.3)
        b.seed = rng.int(1, 1_000_000)
        b.beatsLeft = rng.int(sp.bout.0, sp.bout.1)
        b.boundLeft = rng.int(2, 4)
        b.slow = rng.range(0, 10)
        b.flash = rng.range(10, 30)
        b.t = rng.range(0, 100)
        b.boldU = rng.range(-1, 1)
        b.energy = rng.range(0.4, 0.95)
        b.warmth = rng.range(0.45, 1)
        b.airT = rng.range(0, 50)
        b.senseT = rng.range(0, 0.7)
        b.shuffleT = rng.range(4, 9)
        b.stroke = sp.mid + sp.amp * cos(b.phase)
        b.zs = clamp(b.zs + 0.375 * (bold(b) - 1), 0.06, 0.96)
        b.z = b.zs
        pickWaypoint(b)
        let v0: Double = sp.cruise * S * 0.6
        b.ux = cos(b.heading) * v0
        b.uy = sin(b.heading) * v0
        if edge {
            enterFromEdge(b)
        } else {
            // On screen at load: the best of 12 spots for room from the others.
            var bs = -1.0
            for _ in 0..<12 {
                let s = screens[screenByArea(inGroup: group)]
                let x: Double = s.minX + rng.range(0.08, 0.92) * s.w
                let y: Double = s.minY + rng.range(0.08, 0.92) * s.h
                var d = 1e9
                for o in flies { d = min(d, hypot(o.x - x, o.y - y)) }
                if d > bs { bs = d; b.x = x; b.y = y }
            }
        }
        return b
    }

    /// `enterFromEdge` (html:1346–1365): from a real edge, picked by length, 0.15–0.85 along it, just out of sight,
    /// heading inward ± 0.6 rad at cruise; the best of 6 for room from the others. Several screens: a spot counts
    /// only if it is off the screens, not in a gap and its way in to the edge crosses no gap (up to 48 draws for 6
    /// such spots); with none, it comes in over the left edge of the leftmost screen, which always faces open space.
    func enterFromEdge(_ b: Butterfly) {
        let out: Double = drawReach(b) + 20 * S
        var best = (x: 0.0, y: 0.0, a: 0.0)
        var bs = -1.0
        var found = 0, draws = 0
        while found < 6 && draws < 48 {
            draws += 1
            var x = 0.0, y = 0.0, a = 0.0
            if single {
                let s = screens[0]
                let W = s.w, H = s.h
                let u: Double = rng.unit() * 2 * (W + H)
                let t = rng.range(0.15, 0.85)
                if u < W { x = t * W; y = -out; a = .pi / 2 }
                else if u < 2 * W { x = t * W; y = H + out; a = -.pi / 2 }
                else if u < 2 * W + H { x = -out; y = t * H; a = 0 }
                else { x = W + out; y = t * H; a = .pi }
                x += s.minX
                y += s.minY
            } else {
                guard let last = terrain.edges.last else { break }
                var u: Double = rng.unit() * wallLength
                let t = rng.range(0.15, 0.85)
                var e = last
                for edge in terrain.edges {
                    u -= edge.length
                    if u < 0 { e = edge; break }
                }
                let p = e.a + (e.b - e.a) * t
                x = p.x - e.normal.x * out
                y = p.y - e.normal.y * out
                a = atan2(e.normal.y, e.normal.x)
                if onScreens(x, y) || inGap(x, y) || segmentEntersGap(x, y, p.x, p.y) { continue }
            }
            found += 1
            var d = 1e9
            for o in flies where o !== b {
                d = min(d, hypot(o.x - x, o.y - y), hypot(o.wx - x, o.wy - y) * 1.5)
            }
            if d > bs { bs = d; best = (x, y, a) }
        }
        if found == 0, var left = screens.first {
            for s in screens where s.minX < left.minX { left = s }
            best = (left.minX - out, left.minY + rng.range(0.15, 0.85) * left.h, 0)
        }
        b.x = best.x
        b.y = best.y
        let a: Double = best.a + rng.range(-0.6, 0.6)
        b.heading = a
        b.turn = 0
        b.jink = 0
        let v: Double = b.sp.cruise * S * tuning.speed
        b.ux = cos(a) * v
        b.uy = sin(a) * v
        pickWaypoint(b)
        b.entering = true
    }

    /// `sendAway` (html:1368–1373): out through the nearest real edge, gone once out of sight.
    func sendAway(_ b: Butterfly) {
        if b.leaving { return }
        if b.landed { takeOff(b) } else { releaseFlower(b); b.state = .fly; b.goal = .none; b.spiral = nil }
        b.leaving = true
        b.entering = false
        aimAtExit(b)
    }

    /// `aimAtExit` (html:1374–1380): well past the nearest real edge. Several screens: the nearest real edge whose
    /// point well past it is off the desk (on no screen, in no gap, out of sight of every screen) and reached by a
    /// way that crosses no gap; failing that, any such point; failing that, past the leftmost screen's left edge.
    func aimAtExit(_ b: Butterfly) {
        guard !screens.isEmpty else { return }
        let f1 = footprint(b, 1), f0 = footprint(b, 0)
        let reach: Double = max(f1.l, f1.r, f1.u, f1.d, f0.l, f0.r, f0.u, f0.d)
        let out: Double = max(400 * S, reach + 200 * S)
        if single {
            let s = screens[0]
            let dl = b.x - s.minX, dr = s.maxX - b.x, dtp = b.y - s.minY, db = s.maxY - b.y
            let m = min(dl, dr, dtp, db)
            if m == dl { b.wx = s.minX - out; b.wy = b.y }
            else if m == dr { b.wx = s.maxX + out; b.wy = b.y }
            else if m == dtp { b.wx = b.x; b.wy = s.minY - out }
            else { b.wx = b.x; b.wy = s.maxY + out }
            return
        }
        let p = SIMD2(b.x, b.y)
        for pass in 0..<2 {
            let routed = pass == 0
            var best = Double.infinity
            for e in terrain.edges {
                let d = e.b - e.a
                let t: Double = min(1, max(0, simd_dot(p - e.a, d) / max(simd_length_squared(d), 1e-12)))
                let q = e.a + d * t
                let dist = simd_length(p - q)
                if dist >= best { continue }
                let wx: Double = q.x - e.normal.x * out, wy: Double = q.y - e.normal.y * out
                if inGap(wx, wy) || distanceToScreens(wx, wy) < reach { continue }
                if routed && segmentEntersGap(b.x, b.y, wx, wy) { continue }
                best = dist
                b.wx = wx
                b.wy = wy
            }
            if best < .infinity { return }
        }
        var left = screens[0]
        for s in screens where s.minX < left.minX { left = s }
        b.wx = left.minX - out
        b.wy = clamp(b.y, left.minY, left.maxY)
    }

    /// The count on the meadow (`wantedCount`, html:1382; the director's settings have area scaling off). With
    /// `areaCount` on, each screen counts by its own area (`MeadowTuning.areaCount`) and the scene holds their sum,
    /// at most `countLimit` (12 across all its screens, or this screen's share of the desk's 12).
    var wantedCount: Int {
        guard tuning.areaCount, !screens.isEmpty else { return tuning.count }
        var n = 0
        for s in screens { n += MeadowTuning.areaCount(tuning.count, width: s.w, height: s.h) }
        return min(countLimit, n)
    }

    /// The most butterflies drawn at once (leaving ones included): `room` with `areaCount` on, else no limit.
    var drawLimit: Int {
        guard tuning.areaCount else { return Int.max }
        return room?() ?? MeadowTuning.areaCountLimit
    }

    /// With `areaCount` on: fewer than the count are staying (newcomers waiting for room on the desk).
    var shortOfCount: Bool {
        guard tuning.areaCount, !screens.isEmpty, tuning.species.contains(true) else { return false }
        var active = 0
        for b in flies where !b.leaving { active += 1 }
        return active < wantedCount
    }

    /// For a held frame (`MeadowSim.settle`): takes out every butterfly still on its way out or not yet in (waiting,
    /// or coming in off the screens). Whether there were any. Only with `areaCount` on (the app).
    func dropInTransit() -> Bool {
        guard tuning.areaCount, !screens.isEmpty else { return false }
        var any = false
        flies.removeAll { b in
            let gone: Bool = b.leaving || b.wait > 0 || (b.entering && !onScreens(b.x, b.y))
            if gone { releaseFlower(b); any = true }
            return gone
        }
        return any
    }

    /// For a held frame: the line-up made up at once, on the screens, as at a fresh start (`syncFlies(initial:)`),
    /// within the room the desk has. Only with `areaCount` on (the app).
    func fillAtOnce() {
        guard tuning.areaCount, !screens.isEmpty else { return }
        let prev = rng
        rng = inputRandom
        defer { rng = prev }
        syncFlies(initial: true)
    }

    /// `syncFlies(initial)` (html:1386–1446): keeps the number to the setting and the species mix even. At load they
    /// start on screen; later, newcomers fly in from a real edge and spare ones leave through the nearest.
    public func syncFlies(initial: Bool = false) {
        let on = ButterflyKind.allCases.filter { tuning.species[$0.rawValue] }
        if initial { flies.removeAll { !on.contains($0.kind) } }
        for b in flies where !on.contains(b.kind) { sendAway(b) }
        guard !screens.isEmpty else { return }
        let want = on.isEmpty ? 0 : wantedCount
        var active = flies.filter { !$0.leaving }
        func countOf(_ k: ButterflyKind) -> Int { active.reduce(0) { $0 + ($1.kind == k ? 1 : 0) } }
        func edgeDistance(_ b: Butterfly) -> Double {
            let s = screens[screen(near: b.x, b.y)]
            return min(b.x - s.minX, s.maxX - b.x, b.y - s.minY, s.maxY - b.y)
        }
        func leaver(_ kinds: [ButterflyKind], spareCursor: Bool) -> Butterfly? {
            var best: Butterfly? = nil
            var bs = 1e18
            for b in active {
                if !kinds.contains(b.kind) || (spareCursor && b.goal == .cursor) { continue }
                var e: Double = edgeDistance(b)
                if b.landed { e += 1e6 }
                if b.goal == .cursor { e += 1e7 }
                if b.state == .approach { e += 600 }
                if e < bs { bs = e; best = b }
            }
            return best
        }
        while active.count > want {
            var m = 0
            for k in on { m = max(m, countOf(k)) }
            guard let best = leaver(on.filter { countOf($0) == m }, spareCursor: false) else { break }
            if initial {
                releaseFlower(best)
                flies.removeAll { $0 === best }
            } else {
                sendAway(best)
            }
            active = flies.filter { !$0.leaving }
        }
        var share: [ButterflyKind: Int] = [:]
        if !on.isEmpty {
            let base = want / on.count, extra = want - base * on.count
            // A stable sort, as the sketch's.
            let order = on.enumerated().sorted { a, c in
                let ca = countOf(a.element), cc = countOf(c.element)
                return ca != cc ? ca > cc : a.offset < c.offset
            }
            for (i, k) in order.enumerated() { share[k.element] = base + (i < extra ? 1 : 0) }
        }
        if !initial {
            for k in on {
                while countOf(k) > share[k, default: 0] {
                    guard let b = leaver([k], spareCursor: true) else { break }
                    sendAway(b)
                    active = flies.filter { !$0.leaving }
                }
            }
        }
        for b in flies where active.count < want && b.leaving && on.contains(b.kind) && countOf(b.kind) < share[b.kind, default: 0] {
            b.leaving = false
            pickWaypoint(b)
            active.append(b)
        }
        var wait = 0.0
        let limit = drawLimit
        while active.count < want {
            var order = on
            rng.shuffle(&order)
            // The app's fresh line-up takes the species in order, the odd places to the first, as the preset says
            // (`MeadowLineUp.shares`: Mixed's 7 is 2, 2, 2, 1); the sketch's draws them at random.
            if initial && tuning.areaCount { order = on }
            var best = order[0]
            var bc = Int.max
            for k in order {
                let c = countOf(k) + (!initial && countOf(k) >= share[k, default: 0] ? 1_000_000 : 0)
                if c < bc { bc = c; best = k }
            }
            if !initial, let back = flies.first(where: { $0.leaving && $0.kind == best }) {
                back.leaving = false
                pickWaypoint(back)
                active.append(back)
                continue
            }
            // No room on the desk (others still leaving): the rest come once there is (`step`).
            if flies.count >= limit { break }
            // At load on screens with no way between them: once only as many are left to make as groups still
            // empty, each goes to an empty group (the largest first), so no screen group starts without butterflies.
            var group: Int? = nil
            if initial && groupCount > 1 { group = emptyGroup(left: want - active.count, among: active) }
            let b = makeFly(best, edge: !initial, group: group)
            if !initial {
                b.wait = wait
                wait += rng.range(0.4, 0.9)
            }
            flies.append(b)
            active.append(b)
        }
        if !initial {
            flies.removeAll { b in
                let gone = b.leaving && outOfSight(b)
                if gone { releaseFlower(b) }
                return gone
            }
        }
    }

    /// The largest group with none of `active` on it, if no more than `left` groups are empty; else nil.
    func emptyGroup(left: Int, among active: [Butterfly]) -> Int? {
        var has = [Bool](repeating: false, count: groupCount)
        for b in active { has[group(near: b.x, b.y)] = true }
        var empty = 0, pick = -1, pickArea = -1.0
        for g in 0..<groupCount where !has[g] {
            empty += 1
            var area = 0.0
            for (i, s) in screens.enumerated() where groupOf[i] == g { area += s.w * s.h }
            if area > pickArea { pickArea = area; pick = g }
        }
        return empty > 0 && empty >= left ? pick : nil
    }

    // ── layout ──

    /// The screens or the cell changed (the sketch's `resize`, html:3076–3083, on the input stream): a pointer off
    /// the screens has gone; a landed one off them takes off; the flowers follow their relayout rules (m1). The
    /// port's rules for screens that come and go, so everyone stays on a screen:
    /// - one that was on a screen and no longer is (its screen went, moved or shrank), or is more than a quarter span
    ///   off the screens, or in a gap, is put at the nearest point on a screen;
    /// - one waiting to come in, or coming in and still off the screens, comes in again from a real edge of the new
    ///   screens; one leaving is taken out of a gap, or put on a screen if its screen went from under it, and aims at
    ///   an exit of the new screens;
    /// - a waypoint off the new screens, or whose way crosses off them, and a bask spot off them, are chosen again;
    ///   an approach whose way to its target now crosses a gap is given up.
    /// With no usable screen the flowers close (their terrain is empty) and the butterflies hold still.
    public func layout(terrain new: Terrain, cell: CGSize) {
        let prev = rng
        rng = inputRandom
        defer { rng = prev }
        let old = screens
        terrain = new
        self.cell = cell
        setScreens()
        guard !screens.isEmpty else {
            flowers.relayout(terrain: Terrain(rects: []), cell: cell, rng: inputRandom)
            return
        }
        if pointerHas && !onScreens(pointerX, pointerY) { pointerGone() }
        for b in flies where b.landed && b.state != .cursor && !onScreens(b.x, b.y) { takeOff(b) }
        flowers.relayout(terrain: new, cell: cell, rng: inputRandom)
        func wasOn(_ b: Butterfly) -> Bool {
            for s in old where b.x >= s.minX && b.x <= s.maxX && b.y >= s.minY && b.y <= s.maxY { return true }
            return false
        }
        func project(_ b: Butterfly) {
            let q = terrain.nearestInside(SIMD2(b.x, b.y))
            b.x = q.x
            b.y = q.y
        }
        for b in flies {
            if b.leaving {
                if inGap(b.x, b.y) || !(b.x.isFinite && b.y.isFinite) || (wasOn(b) && !onScreens(b.x, b.y)) { project(b) }
                aimAtExit(b)
                continue
            }
            if b.wait > 0 || (b.entering && !onScreens(b.x, b.y)) {
                enterFromEdge(b)
                continue
            }
            if !onScreens(b.x, b.y) {
                let out = distanceToScreens(b.x, b.y)
                if wasOn(b) || out > 0.25 * spanRef(b) || inGap(b.x, b.y) || !out.isFinite {
                    project(b)
                    if !b.landed && b.state == .fly { pickWaypoint(b) }
                }
            }
            if b.state == .fly && (!onScreens(b.wx, b.wy) || (!single && !wayOpen(b.x, b.y, b.wx, b.wy) && onScreens(b.x, b.y))) {
                pickWaypoint(b)
            }
            if b.state == .approach && b.goal == .bask && !onScreens(b.gx, b.gy) { leaveFlower(b) }
            // An approach whose way to its bloom, bask spot or pointer now crosses a gap is given up.
            if b.state == .approach && !gaps.isEmpty {
                let (tx, ty) = target(b)
                if segmentEntersGap(b.x, b.y, tx, ty) {
                    if b.goal == .cursor { giveUpCursor(b) } else { leaveFlower(b) }
                }
            }
        }
        if flies.isEmpty { syncFlies(initial: true) } else if tuning.areaCount { syncFlies() }   // html:3082
    }

    // ── the pointer (html:2683–2710), on the input stream ──

    /// The pointer is at (x, y) (a move or a drag): the air is stirred along its way by the next step; a move of more
    /// than 2.5 pt from where it came to rest sends off the one on it and restarts the still time, and so does any
    /// move off the screens while one is coming to it or on it (the pointer has left the meadow).
    public func pointerMoved(x: Double, y: Double) {
        guard x.isFinite && y.isFinite else { return }
        breeze.pointerMoved(x: x, y: y)
        if !pointerHas { pointerAX = x; pointerAY = y; pointerStill = 0 }
        pointerX = x
        pointerY = y
        pointerHas = true
        let movedAway: Bool = hypot(x - pointerAX, y - pointerAY) > 2.5
        if movedAway || (!screens.isEmpty && !onScreens(x, y) && answeringPointer()) {
            pointerAX = x
            pointerAY = y
            let prev = rng
            rng = inputRandom
            pointerMovedAway(x, y)
            rng = prev
        }
    }

    /// Whether a butterfly is coming to the pointer or sitting on it.
    func answeringPointer() -> Bool {
        for b in flies where b.goal == .cursor || b.state == .cursor { return true }
        return false
    }

    /// The pointer left the meadow (`pointerleave` → `pointerGone`, html:2710).
    public func pointerLeft() {
        breeze.pointerLeft()
        let prev = rng
        rng = inputRandom
        pointerGone()
        rng = prev
    }

    /// A click (the app's mouse-down; the sketch's click on release, html:2701–2706): not holding still, and on the
    /// meadow it touches a bloom or blooms one, which may call one butterfly. Off the screens: nothing.
    public func pointerDown(x: Double, y: Double) {
        guard x.isFinite && y.isFinite, onScreens(x, y) else { return }
        pointerMoved(x: x, y: y)
        let prev = rng
        rng = inputRandom
        defer { rng = prev }
        pointerMovedAway(x, y)
        clickAt(x, y)
    }

    /// `clickAt` (html:890–921): the flowers' part, then a fresh bloom may call the nearest travelling butterfly
    /// (7 in 10), one at a time and not within `answerGap` of the last.
    func clickAt(_ x: Double, _ y: Double) {
        let r = flowers.click(x: x, y: y, rng: rng)
        guard case .bloomed(let id, _) = r else { return }
        for b in flies where b.called && b.state == .approach { return }
        if time - answerAt < tuning.answerGap { return }
        var best: Butterfly? = nil
        var bd = 1e9
        for b in flies where b.state == .fly && !b.leaving && !b.entering && b.wait <= 0 {
            if !gaps.isEmpty && segmentEntersGap(b.x, b.y, x, y) { continue }
            let d = hypot(b.x - x, b.y - y)
            if d < bd { bd = d; best = b }
        }
        if let best, rng.unit() < 0.7, let f = flowers.index(of: id) {
            goToFlower(best, f)
            best.timer = 16
            best.called = true
            answerAt = time
        }
    }

    /// `pointerMoved` (html:1928–1934): the one on the pointer bursts away; one on its way gives up.
    func pointerMovedAway(_ x: Double, _ y: Double) {
        pointerStill = 0
        for b in flies {
            if b.state == .cursor { takeOff(b, away: (x, y), escape: true); cursorCd = 3 }
            else if b.goal == .cursor { giveUpCursor(b) }
        }
    }

    /// `giveUpCursor` (html:1936).
    func giveUpCursor(_ b: Butterfly) {
        b.state = .fly
        b.goal = .none
        b.spiral = nil
        b.boost = max(b.boost, 0.4)
        b.boostK = 1.8
        pickWaypoint(b)
        cursorCd = 3
    }

    /// `pointerGone` (html:1939–1942).
    func pointerGone() {
        pointerHas = false
        pointerStill = 0
        for b in flies where b.goal == .cursor && b.state != .cursor { giveUpCursor(b) }
    }

    // ── stepping (html:1998–2009) ──

    /// One step of exactly `OceanClock.step` (any other is refused): the air, the pointer's still time, the
    /// flowers, every butterfly, the pollen.
    public func step(_ dt: Double = OceanClock.step) {
        guard dt == OceanClock.step else { return }
        rng = simRandom
        breeze.step(dt, speed: speed)
        stepPointer(dt)
        flowers.updateFeeding { id in
            for b in self.flies where b.flower == id && b.state == .nectar { return true }
            return false
        }
        flowers.step(dt)
        flowers.takeSparks { s in
            self.addDust(MeadowDust(x: s.x, y: s.y, vx: s.vx, vy: s.vy, life: s.life, max: s.max, spark: true))
        }
        // With no screen (a broken layout) the butterflies hold still until there is one.
        if !screens.isEmpty { for b in flies { stepFly(b, dt) } }
        var anyDead = false
        for b in flies where b.dead { anyDead = true; releaseFlower(b) }
        if anyDead { flies.removeAll { $0.dead } }
        // With `areaCount` on (the app): newcomers that waited for room on the desk come in once there is. The
        // shortage first: the desk's room is asked only while some are waiting.
        if tuning.areaCount && !screens.isEmpty && shortOfCount && flies.count < drawLimit { syncFlies() }
        stepDust(dt)
    }

    @inline(__always) func addDust(_ d: MeadowDust) {
        if dust.count < MeadowWorld.dustCapacity { dust.append(d) }
    }

    /// `stepDust` (html:1974–1981).
    func stepDust(_ dt: Double) {
        var n = 0
        let k: Double = min(1, 1.5 * dt)
        for i in 0..<dust.count {
            var d = dust[i]
            d.life -= dt
            if d.life <= 0 { continue }
            let a = breeze.sample(d.x, d.y)
            d.vx += (a.x * 0.6 - d.vx) * k
            d.vy += (a.y * 0.6 - d.vy) * k
            d.x += d.vx * dt
            d.y += d.vy * dt
            dust[n] = d
            n += 1
        }
        if n < dust.count { dust.removeLast(dust.count - n) }
    }

    // ── flowers and butterflies ──

    /// `releaseFlower` (html:1448).
    func releaseFlower(_ b: Butterfly) {
        if b.flower != 0, let i = flowers.index(of: b.flower), flowers.all[i].busy == b.id { flowers.setBusy(id: b.flower, by: 0) }
        b.flower = 0
        b.called = false
    }

    /// `leaveFlower` (html:951–954): a landed one takes off, one on its way turns away.
    func leaveFlower(_ b: Butterfly) {
        if b.landed { takeOff(b); return }
        releaseFlower(b)
        b.state = .fly
        b.goal = .none
        b.tag = 0
        b.circleT = 0
        b.called = false
        pickWaypoint(b)
    }

    /// `goToFlower` (html:1496), `f` an index into `flowers.all`.
    func goToFlower(_ b: Butterfly, _ f: Int) {
        releaseFlower(b)
        b.called = false
        b.state = .approach
        b.goal = .nectar
        let id = flowers.all[f].id
        b.flower = id
        flowers.setBusy(id: id, by: b.id)
        b.timer = 18
        b.tag = 0
        b.tagTries = 0
        b.circleT = 0
    }

    /// `target` (html:1525–1529).
    func target(_ b: Butterfly) -> (Double, Double) {
        if b.goal == .cursor { return cursorSpot(b) }
        if b.flower != 0, let i = flowers.index(of: b.flower) {
            let f = flowers.all[i]
            return (f.x + f.ox, f.y + f.oy)
        }
        return (b.gx, b.gy)
    }

    /// `cursorSpot` (html:1516–1523): the proboscis at the pointer, the body behind it, held on the pointer's screen
    /// so its whole body stays on it.
    func cursorSpot(_ b: Butterfly) -> (Double, Double) {
        guard !screens.isEmpty else { return (b.x, b.y) }
        let hh: Double = b.sp.span * 13 * S * b.size * depthScale(b.z) * b.sp.aspect / 2
        let off: Double = 0.4 * hh + 1.0 * cw
        let s = screens[screen(near: pointerX, pointerY)]
        let mx: Double = min(0.78 * hh + cw, 0.5 * s.w)
        let my: Double = min(0.78 * hh + cw, 0.5 * s.h)
        let x: Double = clamp(pointerX - cos(b.heading) * off, s.minX + mx, s.maxX - mx)
        let y: Double = clamp(pointerY - sin(b.heading) * off, s.minY + my, s.maxY - my)
        return (x, y)
    }

    /// `nodFlower` (html:1532–1536).
    func nodFlower(_ id: Int, _ hx: Double, _ hy: Double, _ b: Butterfly, _ k: Double) {
        flowers.nod(id: id, dx: hx, dy: hy, size: b.size, k: k)
    }
}

/// The light, from the top-left a little above (html:989–990).
public enum MeadowLight {
    public static let x = -0.42, y = -0.58, z = 0.70
    public static let angle = atan2(-0.58, -0.42)
}
