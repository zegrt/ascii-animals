import CoreGraphics
import Foundation
import OceanKit
import simd

// The Meadow's air and flowers (task m1), ported from the sketch. Each check names the rule it holds; the sketch's
// numbers come from the sketch itself (golden values made by its own functions, its replay fixture, and the m1
// probe; see Fixtures/README.md).

private let meadowStep: Double = 1.0 / 60.0

/// A meadow's air and flowers on a terrain, with the sketch's two streams.
private struct MeadowRig {
    let breeze: Breeze
    let flowers: Flowers
    let sim: MeadowRandom
    let input: MeadowRandom

    init(_ terrain: Terrain, cell: Double, seed: Int32, tuning: MeadowTuning = .director, plant: Bool = true) {
        let size = CGSize(width: cell, height: (cell * 1.45).rounded())
        breeze = Breeze(terrain: terrain, cell: size, tuning: tuning)
        flowers = Flowers(terrain: terrain, cell: size, breeze: breeze, tuning: tuning)
        let streams = MeadowRandom.pair(seed: seed)
        sim = streams.sim
        input = streams.input
        if plant { flowers.plant(rng: sim) }
    }

    func step(_ n: Int = 1) {
        for _ in 0..<n {
            breeze.step(meadowStep)
            flowers.step(meadowStep)
        }
    }
}

// ── allocation counting (the system allocator's logging hook) ──

private typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void
nonisolated(unsafe) private let mallocCount: UnsafeMutablePointer<Int> = {
    let p = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    p.pointee = 0
    return p
}()
@inline(never) private func mallocCounter() -> UnsafeMutablePointer<Int> { mallocCount }

// Where counted allocations came from, kept without allocating (a fixed buffer, filled from the logger): the first
// `traceSlots` of them since the last `allocationSites()`, each with its thread and up to `traceDepth` return
// addresses. Read only to explain a failure; it changes no count.
private let traceSlots = 8, traceDepth = 24
nonisolated(unsafe) private let traceState: UnsafeMutablePointer<Int> = {
    // [0] traces kept, [1] logger busy, [2] counted off the main thread, then per slot: main?, depth.
    let p = UnsafeMutablePointer<Int>.allocate(capacity: 3 + 2 * 8)
    p.initialize(repeating: 0, count: 3 + 2 * 8)
    return p
}()
nonisolated(unsafe) private let traceFrames: UnsafeMutablePointer<UnsafeMutableRawPointer?> = {
    let p = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 8 * 24)
    p.initialize(repeating: nil, count: 8 * 24)
    return p
}()
@inline(never) private func noteAllocation() {
    let st = traceState
    let main = pthread_main_np() != 0
    if !main { st[2] += 1 }
    let k = st[0]
    guard k < traceSlots, st[1] == 0 else { return }
    st[1] = 1
    st[3 + 2 * k] = main ? 1 : 0
    st[4 + 2 * k] = Int(backtrace(traceFrames + k * traceDepth, Int32(traceDepth)))
    st[0] = k + 1
    st[1] = 0
}
private let countingLogger: MallocLogger = { type, _, _, _, _, _ in
    if type & 2 != 0 { mallocCounter().pointee += 1; noteAllocation() }
}

/// The allocations counted since the last call: how many off the main thread, and where the first few were made
/// (thread, then the frames past the allocator, as symbol+offset). Clears what it read.
func allocationSites() -> String {
    let st = traceState
    var out = "\(st[2]) off the main thread"
    for k in 0..<min(st[0], traceSlots) {
        out += "\n    allocation \(k + 1) (\(st[3 + 2 * k] == 1 ? "main thread" : "another thread")):"
        var shown = 0
        for f in 0..<st[4 + 2 * k] where shown < 10 {
            guard let pc = traceFrames[k * traceDepth + f] else { continue }
            var info = Dl_info()
            var name = "?"
            if dladdr(pc, &info) != 0, let sym = info.dli_sname {
                name = String(cString: sym) + "+\(Int(bitPattern: pc) - Int(bitPattern: info.dli_saddr))"
            }
            if name.contains("noteAllocation") || name.contains("countingLogger") || name.hasPrefix("malloc")
                || name.hasPrefix("_malloc") { continue }
            out += "\n      \(name)"
            shown += 1
        }
    }
    st[0] = 0
    st[2] = 0
    return out
}

/// Heap allocations `body` makes, or nil where the allocator can't be watched.
func allocations(_ body: () -> Void) -> Int? {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else { return nil }
    let slot = sym.assumingMemoryBound(to: MallocLogger?.self)
    guard slot.pointee == nil else { return nil }
    _ = mallocCounter()
    mallocCount.pointee = 0
    slot.pointee = countingLogger
    body()
    slot.pointee = nil
    return mallocCount.pointee
}

// ── fixtures ──

private func fixture(_ name: String) -> [String: Any]? {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
          let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return json
}

private func num(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return .nan
}

/// An integer field: a JSON number that is a whole number a Double holds exactly (|v| ≤ 2⁵³), else nil (missing, not
/// a number, fractional or out of range), so a broken fixture fails a check with a diagnostic instead of trapping in
/// `Int(_:)`.
private func integer(_ v: Any?) -> Int? {
    let d = num(v)
    guard d.isFinite && d == d.rounded() && abs(d) <= 9_007_199_254_740_992 else { return nil }
    return Int(d)
}

/// A sketch flower row `[id, kind, x, y, R, rot, seed, n, f0, leaves, florets, ox, oy, age, clicked, fade]` against
/// a Swift flower.
private func expectFlower(_ row: [Any], _ f: Flower, _ at: String, tol: Double) throws {
    guard let id = integer(row[0]) else { throw CheckFailure(detail: "\(at): a flower row's id \(row.first ?? "none") isn't an integer") }
    try expect(f.id == id, "\(at): id \(f.id) vs \(id)")
    try expect(f.kind.name == (row[1] as? String ?? ""), "\(at) id \(id): kind \(f.kind.name) vs \(row[1])")
    try expect(f.seed == integer(row[6]) && f.petals == integer(row[7]), "\(at) id \(id): seed/petals")
    try expect(f.leaves.count == integer(row[9]) && f.florets.count == integer(row[10]), "\(at) id \(id): leaves/florets")
    try expect(f.clicked == (num(row[14]) == 1), "\(at) id \(id): clicked")
    let pairs: [(String, Double, Double, Double)] = [
        ("x", f.x, num(row[2]), 1e-5), ("y", f.y, num(row[3]), 1e-5), ("R", f.radius, num(row[4]), 1e-5),
        ("rot", f.turn, num(row[5]), 1e-5), ("f0", f.f0, num(row[8]), 1e-5), ("ox", f.ox, num(row[11]), tol),
        ("oy", f.oy, num(row[12]), tol), ("age", f.age, num(row[13]), 1e-5),
        ("fade", f.fading ? f.fade : -1, num(row[15]), 1e-5),
    ]
    for (name, got, want, t) in pairs {
        try expect(abs(got - want) <= t, "\(at) id \(id): \(name) \(got) vs \(want) (tol \(t))")
    }
}

/// A sketch air row `[x, y, wind.x, wind.y, ax, ay, px, py, g]` against the Swift air there.
private func expectAir(_ row: [Any], _ b: Breeze, _ at: String, tol: Double) throws {
    let x = num(row[0]), y = num(row[1])
    let a = b.sample(x, y)
    let pairs: [(String, Double, Double)] = [
        ("x", a.x, num(row[2])), ("y", a.y, num(row[3])), ("ax", a.landedX, num(row[4])), ("ay", a.landedY, num(row[5])),
        ("px", a.pointerX, num(row[6])), ("py", a.pointerY, num(row[7])), ("g", a.gust, num(row[8])),
    ]
    for (name, got, want) in pairs {
        try expect(abs(got - want) <= tol, "\(at) (\(x), \(y)): \(name) \(got) vs \(want) (tol \(tol))")
    }
}

/// A sketch geometry row `[id, leaves [[a, len, wid, k]…], florets [[x, y, s, open, rot]…]]` against a flower.
private func expectGeometry(_ leaves: [Any], _ florets: [Any], _ f: Flower, _ at: String) throws {
    try expect(leaves.count == f.leaves.count && florets.count == f.florets.count,
               "\(at) id \(f.id): \(f.leaves.count) leaves, \(f.florets.count) florets vs \(leaves.count), \(florets.count)")
    for (row, l) in zip(leaves, f.leaves) {
        let v = row as? [Any] ?? []
        try expect(v.count == 4 && abs(l.angle - num(v[0])) <= 1e-5 && abs(l.length - num(v[1])) <= 1e-5
                   && abs(l.width - num(v[2])) <= 1e-5 && l.kind == integer(v[3]), "\(at) id \(f.id): leaf \(l) vs \(v)")
    }
    for (row, u) in zip(florets, f.florets) {
        let v = row as? [Any] ?? []
        try expect(v.count == 5 && abs(u.x - num(v[0])) <= 1e-5 && abs(u.y - num(v[1])) <= 1e-5 && abs(u.size - num(v[2])) <= 1e-5
                   && u.open == (num(v[3]) == 1) && abs(u.turn - num(v[4])) <= 1e-5, "\(at) id \(f.id): floret \(u) vs \(v)")
    }
}

/// Every flower's geometry against the sketch's rows, by id.
private func expectGeometry(_ rows: [[Any]], _ flowers: [Flower], _ at: String) throws {
    try expect(rows.count == flowers.count, "\(at): \(rows.count) geometry rows for \(flowers.count) flowers")
    for (row, f) in zip(rows, flowers) {
        try expect(row.count == 3 && integer(row[0]) == f.id, "\(at): geometry row for \(row.first ?? "none"), flower \(f.id)")
        try expectGeometry(row[1] as? [Any] ?? [], row[2] as? [Any] ?? [], f, at)
    }
}

/// The m1 probe of the sketch (Fixtures/README.md), replayed.
private func replayProbe(_ name: String) throws {
    guard let d = fixture(name) else { throw CheckFailure(detail: "fixture \(name).json missing") }
    let W = num(d["W"]), H = num(d["H"]), S = num(d["S"])
    let terrain = Terrain.single(width: W, height: H)
    let rig = MeadowRig(terrain, cell: S * 13, seed: 4242)
    let planted = d["planted"] as? [[Any]] ?? []
    try expect(!planted.isEmpty && planted.count == rig.flowers.all.count,
               "planted \(rig.flowers.all.count) vs the sketch's \(planted.count)")
    for (row, f) in zip(planted, rig.flowers.all) { try expectFlower(row, f, "planted", tol: 1e-6) }
    try expectGeometry(d["plantedGeometry"] as? [[Any]] ?? [], rig.flowers.all, "planted")

    rig.step(60)
    let t60 = d["t60"] as? [String: Any] ?? [:]
    for row in t60["air"] as? [[Any]] ?? [] { try expectAir(row, rig.breeze, "t60", tol: 1e-4) }
    for (row, f) in zip(t60["flowers"] as? [[Any]] ?? [], rig.flowers.all) { try expectFlower(row, f, "t60", tol: 1e-4) }

    // The stir pass: the pointer set once a step, as the sketch's input at 60 Hz.
    rig.breeze.pointerMoved(x: 300, y: 300)
    for i in 0..<30 {
        let x: Double = 300 + Double(i) * 12
        let y: Double = 300 + Double(i) * 5
        rig.breeze.pointerMoved(x: x, y: y)
        rig.step()
    }
    let stir = d["stir"] as? [String: Any] ?? [:]
    for row in stir["air"] as? [[Any]] ?? [] { try expectAir(row, rig.breeze, "stir", tol: 1e-3) }
    for row in stir["samples"] as? [[Any]] ?? [] {
        let a = rig.breeze.sample(num(row[0]), num(row[1]))
        try expect(abs(a.pointerX - num(row[2])) < 1e-3 && abs(a.pointerY - num(row[3])) < 1e-3,
                   "stir at (\(row[0]), \(row[1])): (\(a.pointerX), \(a.pointerY)) vs (\(row[2]), \(row[3]))")
    }
    rig.breeze.pointerLeft()

    // The clicks, one step apart after the first.
    let points = d["clickPoints"] as? [[Any]] ?? []
    try expect(points.count == 8, "click points \(points.count)")
    for (k, p) in points.enumerated() {
        rig.flowers.click(x: num(p[0]), y: num(p[1]), rng: rig.input)
        if k > 0 { rig.step() }
    }
    let clicks = d["clicks"] as? [String: Any] ?? [:]
    let after = clicks["flowers"] as? [[Any]] ?? []
    try expect(after.count == rig.flowers.all.count, "after the clicks \(rig.flowers.all.count) vs \(after.count)")
    for (row, f) in zip(after, rig.flowers.all) { try expectFlower(row, f, "clicks", tol: 1e-4) }
    try expectGeometry(clicks["geometry"] as? [[Any]] ?? [], rig.flowers.all, "clicks")
    try expect(rig.flowers.sparks.count == integer(clicks["dust"]),
               "pollen sparks \(rig.flowers.sparks.count) vs the sketch's dust \(num(clicks["dust"]))")

    rig.step(120)
    let t180 = d["t180"] as? [String: Any] ?? [:]
    try expectClose(rig.breeze.time, num(t180["t"]), tol: 1e-9, "time")
    for row in t180["air"] as? [[Any]] ?? [] { try expectAir(row, rig.breeze, "t180", tol: 1e-3) }
    let end = t180["flowers"] as? [[Any]] ?? []
    try expect(end.count == rig.flowers.all.count, "at the end \(rig.flowers.all.count) vs \(end.count)")
    for (row, f) in zip(end, rig.flowers.all) { try expectFlower(row, f, "t180", tol: 1e-3) }
    // Every kind, made by the sketch's own `makeFlower` on a fresh stream, mulberry32(777): one of each, in the
    // sketch's order, at (100, 100), grown.
    let kinds = d["kinds"] as? [[Any]] ?? []
    try expect(kinds.count == FlowerKind.allCases.count, "\(kinds.count) kinds in the probe")
    let kindStream = MeadowRandom(777)
    for (row, kind) in zip(kinds, FlowerKind.allCases) {
        let f = rig.flowers.make(kind, x: 100, y: 100, grown: true, rng: kindStream)
        let at = "kind \(kind.name)"
        try expect(row.count == 10 && integer(row[0]) == f.id && (row[1] as? String) == kind.name, "\(at): id \(f.id) vs \(row.first ?? "none")")
        try expect(f.seed == integer(row[4]) && f.petals == integer(row[5]), "\(at): seed \(f.seed), petals \(f.petals), R \(f.radius) vs \(row.prefix(8))")
        let pairs: [(String, Double, Double)] = [("R", f.radius, num(row[2])), ("rot", f.turn, num(row[3])),
                                                 ("f0", f.f0, num(row[6])), ("reach", f.reach, num(row[7]))]
        for (n, got, want) in pairs { try expect(abs(got - want) <= 1e-5, "\(at): \(n) \(got) vs \(want)") }
        try expectGeometry(row[8] as? [Any] ?? [], row[9] as? [Any] ?? [], f, at)
    }
}

// ── the pointer ──

/// A gesture over 2 s: a sweep across with a swing, 300–900 pt/s.
private func gesture(_ t: Double) -> SIMD2<Double> {
    let x: Double = 400 + 300 * t + 150 * sin(3 * t)
    let y: Double = 450 + 200 * sin(2.2 * t)
    return SIMD2(x, y)
}

/// A slower gesture: a loop at 150–450 pt/s.
private func loop(_ t: Double) -> SIMD2<Double> {
    let x: Double = 800 + 260 * sin(1.2 * t)
    let y: Double = 500 + 200 * sin(1.7 * t)
    return SIMD2(x, y)
}

/// One thing the host tells the breeze before a step: the pointer at a place, or gone.
private enum PointerInput {
    case move(Double, Double)
    case leave
}

/// The pointer's stir field (px, py on a 25 × 15 grid of points) after each of `steps` steps, `events(k)` delivered
/// before step k (1-based).
private func stirTrace(steps: Int = 180, speed: Double = 1, _ events: (Int) -> [PointerInput]) -> [[Double]] {
    let breeze = Breeze(terrain: Terrain.single(width: 1600, height: 1000), cell: CGSize(width: 13, height: 19))
    var out: [[Double]] = []
    out.reserveCapacity(steps)
    for k in 1...steps {
        for e in events(k) {
            switch e {
            case .move(let x, let y): breeze.pointerMoved(x: x, y: y)
            case .leave: breeze.pointerLeft()
            }
        }
        breeze.step(meadowStep, speed: speed)
        out.append(stirGrid(breeze))
    }
    return out
}

/// The pointer's stir (px, py) on a 25 × 15 grid of points over 1600 × 1000.
private func stirGrid(_ breeze: Breeze) -> [Double] {
    var field: [Double] = []
    field.reserveCapacity(750)
    var y = 150.0
    while y <= 850 {
        var x = 200.0
        while x <= 1400 {
            let a = breeze.sample(x, y)
            field.append(a.pointerX)
            field.append(a.pointerY)
            x += 50
        }
        y += 50
    }
    return field
}

/// A path's moves at `rate` Hz, regularly: sample e is taken at e / rate s and delivered before the first step at or
/// after it (step k starts at (k − 1) / 60 s), for `seconds`.
private func regular(_ path: @escaping (Double) -> SIMD2<Double>, rate: Double, seconds: Double = 2)
    -> (Int) -> [PointerInput] {
    return { k in
        var out: [PointerInput] = []
        // Taken in ((k − 2) / 60, (k − 1) / 60]; the first step takes the sample at 0.
        let from = Double(k - 2) / 60, to = Double(k - 1) / 60
        var e = max(0, Int((from * rate + 1e-6).rounded(.down)))
        while Double(e) / rate <= to + 1e-9 && Double(e) / rate <= seconds + 1e-9 {
            let t: Double = Double(e) / rate
            if k == 1 || t > from + 1e-9 { let p = path(t); out.append(.move(p.x, p.y)) }
            e += 1
        }
        return out
    }
}

/// The relative difference (L2 over the grid) between two fields; 0 where the reference is still.
private func difference(_ a: [Double], _ ref: [Double]) -> Double {
    var dd = 0.0, rr = 0.0
    for i in ref.indices {
        let d: Double = a[i] - ref[i]
        dd += d * d
        rr += ref[i] * ref[i]
    }
    return rr > 1 ? (dd / rr).squareRoot() : 0
}

/// The largest difference between two traces at the steps `at` says (0-based step indices).
private func worstDifference(_ a: [[Double]], _ ref: [[Double]], at: (Int) -> Bool = { _ in true }) -> Double {
    var worst = 0.0
    for t in 0..<min(a.count, ref.count) where at(t) { worst = max(worst, difference(a[t], ref[t])) }
    return worst
}

/// A percentage for the record.
private func pct(_ v: Double) -> String { String(format: "%.1f %%", v * 100) }

func meadowChecks() {
    check("meadowMathMatchesSketch", meadowMathMatchesSketch)
    check("meadowReplaysTheSketchProbe", meadowReplaysTheSketchProbe)
    check("meadowSameSeedSameMeadow", meadowSameSeedSameMeadow)
    check("meadowStirHalfLifeAndLocal", meadowStirHalfLifeAndLocal)
    check("meadowStirMatchesTheSketch", meadowStirMatchesTheSketch)
    check("meadowStirSameAtEveryInputRate", meadowStirSameAtEveryInputRate)
    check("meadowStirAcrossReentry", meadowStirAcrossReentry)
    check("meadowStirFiniteAndBounded", meadowStirFiniteAndBounded)
    check("meadowDownwashOnlyUnderLowButterflies", meadowDownwashOnlyUnderLowButterflies)
    check("meadowWindPeaksAtTheSketchSpeed", meadowWindPeaksAtTheSketchSpeed)
    check("meadowNoFlowerInAGap", meadowNoFlowerInAGap)
    check("meadowNoOverlapAndPatchesFollowArea", meadowNoOverlapAndPatchesFollowArea)
    check("meadowHeadSpringRings", meadowHeadSpringRings)
    check("meadowClicksTouchNeverStack", meadowClicksTouchNeverStack)
    check("meadowClickLimitAndFade", meadowClickLimitAndFade)
    check("meadowRelayoutFadesClickedOffScreen", meadowRelayoutFadesClickedOffScreen)
    check("meadowGrowthLiftAndDim", meadowGrowthLiftAndDim)
    check("meadowFiniteOnBadInput", meadowFiniteOnBadInput)
    check("meadowStepAllocatesNothing", meadowStepAllocatesNothing)
    check("meadowReplaysTheSketchFixture", meadowReplaysTheSketchFixture)
}

private func meadowMathMatchesSketch() throws {
    // Golden values made by the sketch's own functions (html:140–182) under node.
    var a = Mulberry32(12345)
    var b = Mulberry32(12345 ^ Int32(bitPattern: 0x5BD1_E995))
    var c = Mulberry32(-7)
    let sim: [Double] = [0.9797282677609473, 0.3067522644996643, 0.484205421525985, 0.817934412509203, 0.5094283693470061]
    let ui: [Double] = [0.5790900862775743, 0.9958807048387825, 0.5389305409044027, 0.4330787805374712, 0.7108245396520942]
    let neg: [Double] = [0.43306733411736786, 0.32539576734416187, 0.5442695003002882, 0.48018999374471605, 0.048719558166339993]
    for i in 0..<5 {
        try expect(a.next() == sim[i] && b.next() == ui[i] && c.next() == neg[i], "mulberry32 draw \(i)")
    }
    let pair = MeadowRandom.pair(seed: 12345)
    try expect(pair.sim.unit() == sim[0] && pair.input.unit() == ui[0], "the two streams")
    let hashes: [(Double, Double, Double, Double)] = [
        (0, 0, 0, 0), (1, 2, 3, 0.3797727196943015), (-5, 17, 91, 0.7035144788678735),
        (123456, -98765, 9, 0.5443396402988583), (2.9, -2.9, 5, 0.3795370028819889),
    ]
    for (x, y, z, want) in hashes {
        try expect(MeadowMath.hash3(x, y, z) == want, "hash3(\(x), \(y), \(z)) = \(MeadowMath.hash3(x, y, z)), want \(want)")
    }
    try expectClose(MeadowMath.vnoise(0.3, 0.7, 5), 0.37999970526361465, tol: 1e-15, "vnoise 1")
    try expectClose(MeadowMath.vnoise(-12.25, 3.5, 9), 0.4215527166998072, tol: 1e-15, "vnoise 2")
    try expectClose(MeadowMath.vnoise(1000.1, 0.5, 91), 0.3880003628139448, tol: 1e-15, "vnoise 3")
    try expectClose(MeadowMath.n1(0.013 * 100, 91), 0.29374473418109126, tol: 1e-15, "n1 1")
    try expectClose(MeadowMath.n1(0.05 * 37.5, 17), 0.283753879831238, tol: 1e-15, "n1 2")
    let g = MeadowRandom(42)
    try expectClose(g.gauss(), -0.956162229384149, tol: 1e-12, "gauss 1")
    try expectClose(g.gauss(), -0.2730261048826104, tol: 1e-12, "gauss 2")
    var deck = Array(0..<10)
    MeadowRandom(42).shuffle(&deck)
    try expect(deck == [0, 7, 3, 5, 2, 1, 8, 9, 4, 6], "shuffle \(deck)")
}

private func meadowReplaysTheSketchProbe() throws {
    try replayProbe("meadow-probe-1600x913")
    try replayProbe("meadow-probe-1280x713")
}

private func meadowSameSeedSameMeadow() throws {
    let terrain = Terrain(rects: [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1080)])
    func run(_ seed: Int32) -> ([Flower], [MeadowAir]) {
        let rig = MeadowRig(terrain, cell: 13, seed: seed)
        for k in 0..<400 {
            let t: Double = Double(k) / 60
            rig.breeze.pointerMoved(x: 900 + 400 * cos(t), y: 500 + 300 * sin(1.3 * t))
            if k == 100 || k == 160 || k == 220 { rig.flowers.click(x: 300 + Double(k) * 7, y: 260, rng: rig.input) }
            rig.step()
        }
        var air: [MeadowAir] = []
        for p in stride(from: 50.0, to: 3400, by: 170) { air.append(rig.breeze.sample(p, p * 0.28)) }
        return (rig.flowers.all, air)
    }
    let (f1, a1) = run(77)
    let (f2, a2) = run(77)
    try expect(!f1.isEmpty && f1 == f2, "same seed, different flowers")
    try expect(a1 == a2, "same seed, different air")
    let (f3, _) = run(78)
    try expect(f3.map(\.x) != f1.map(\.x), "another seed, the same meadow")
}

private func meadowStirHalfLifeAndLocal() throws {
    let rig = MeadowRig(Terrain.single(width: 1600, height: 1000), cell: 13, seed: 1,
                        tuning: { var t = MeadowTuning(); t.breeze = 0; return t }(), plant: false)
    rig.breeze.stir(800, 500, 100, 0)
    let start = rig.breeze.sample(800, 500).pointerX
    // ln 2 / 1.6 ≈ 0.433 s: 26 steps is 0.4333 s.
    rig.step(26)
    let half = rig.breeze.sample(800, 500).pointerX / start
    try expect(abs(half - 0.5) < 0.01, "after 26 steps \(half) of the stir is left")
    let halfLife: Double = log(2) / MeadowTuning.Stir.decay
    try expect(abs(halfLife - 0.433) < 0.001, "half-life \(halfLife)")
    // Local: 3 grid cells of reach plus one cell of interpolation; nothing beyond.
    let reach: Double = 4 * rig.breeze.spacing
    let beyond: [(Double, Double)] = [(reach + 1, 0), (0, reach + 1), (-reach - 1, 0), (reach, reach)]
    for (dx, dy) in beyond {
        let a = rig.breeze.sample(800 + dx, 500 + dy)
        try expect(a.pointerX == 0 && a.pointerY == 0, "stir reached (\(dx), \(dy)): \(a.pointerX)")
    }
    try expect(rig.breeze.sample(800 + 2 * rig.breeze.spacing, 500).pointerX > 0, "stir didn't spread at all")
}

/// The sketch's own `stirStep`, through its own pointer handlers, for the same per-step positions (the stir probe,
/// Fixtures/README.md): 60, 30 and 120 Hz moves, a fast way past the speed clamp, a leave and re-entry, and Slow
/// motion 0.4. Every sample of the field is compared at every snapshot.
private func meadowStirMatchesTheSketch() throws {
    let name = "meadow-stir-probe-1600x913"
    guard let d = fixture(name) else { throw CheckFailure(detail: "fixture \(name).json missing") }
    let W = num(d["W"]), H = num(d["H"]), S = num(d["S"])
    let scenarios = d["scenarios"] as? [String: Any] ?? [:]
    let names = ["rate60", "rate30", "rate120", "fast", "reentry", "slow"]
    try expect(Set(scenarios.keys) == Set(names), "the probe's scenarios \(scenarios.keys.sorted()), want \(names)")
    guard let columns = integer(d["columns"]), let length = integer(d["length"]) else {
        throw CheckFailure(detail: "the probe's grid size isn't an integer: \(d["columns"] ?? "none"), \(d["length"] ?? "none")")
    }
    var worst = 0.0, snaps = 0, ops = 0
    for scenario in names {
        let sc = scenarios[scenario] as? [String: Any] ?? [:]
        let breeze = Breeze(terrain: Terrain.single(width: W, height: H), cell: CGSize(width: 13 * S, height: 19 * S))
        try expect(breeze.columns == columns && breeze.columns * breeze.rows == length,
                   "grid \(breeze.columns) × \(breeze.rows) vs the sketch's \(columns) columns, \(length) samples")
        let shots = sc["snaps"] as? [[Any]] ?? []
        let list = sc["ops"] as? [[Any]] ?? []
        try expect(!list.isEmpty && !shots.isEmpty, "\(scenario): no ops or no snapshots")
        var speed = 1.0
        var next = 0
        for op in list {
            switch op.first as? String ?? "" {
            case "m":
                try expect(op.count == 3, "\(scenario): a move \(op)")
                breeze.pointerMoved(x: num(op[1]), y: num(op[2]))
            case "l": breeze.pointerLeft()
            case "s": breeze.step(meadowStep, speed: speed)
            case "t":
                try expect(op.count == 2, "\(scenario): a speed \(op)")
                speed = num(op[1])
            case "snap":
                try expect(next < shots.count, "\(scenario): more snapshots than the sketch's \(shots.count)")
                var want = [SIMD2<Double>](repeating: SIMD2(0, 0), count: length)
                for c in shots[next] {
                    let v = c as? [Any] ?? []
                    guard v.count == 3, let i = integer(v[0]), i >= 0 && i < length else {
                        throw CheckFailure(detail: "\(scenario) snapshot \(next): a bad row \(v)")
                    }
                    want[i] = SIMD2(num(v[1]), num(v[2]))
                }
                for i in 0..<length {
                    let got = breeze.stirSample(i % columns, i / columns)
                    let e: Double = max(abs(got.x - want[i].x), abs(got.y - want[i].y))
                    worst = max(worst, e)
                    try expect(e <= 1e-4, "\(scenario) snapshot \(next) sample \(i): \(got) vs the sketch's \(want[i])")
                }
                next += 1
            default:
                throw CheckFailure(detail: "\(scenario): an unknown op \(op)")
            }
            ops += 1
        }
        try expect(next == shots.count, "\(scenario): \(next) snapshots vs the sketch's \(shots.count)")
        snaps += next
    }
    print(String(format: "  the sketch's stirStep: %d scenarios, %d snapshots, %d ops; worst %.1e pt/s", names.count,
                 snaps, ops, worst))
}

/// Regular input at 30, 60 and 120 Hz against 60 Hz (the sketch's claim for `stirStep`, html:1983–1986, measured on
/// its rule as ported). Only the latest position counts, so 120 Hz input stirs as 60 Hz does. 30 Hz reports every
/// other step; in between the sketch stirs nothing, so it is compared on the steps after a report. There the sketch's
/// rule holds 5 % on the slower loop (150–450 pt/s) once the stroke is under way (from 0.25 s); the first strokes and
/// the faster gesture (300–900 pt/s) are printed for the record, not held (m1 fix round 2's report).
private func meadowStirSameAtEveryInputRate() throws {
    let paths: [(String, (Double) -> SIMD2<Double>, Bool)] = [("loop", loop, true), ("gesture", gesture, false)]
    for (name, path, held) in paths {
        let ref = stirTrace(regular(path, rate: 60))
        let at120 = worstDifference(stirTrace(regular(path, rate: 120)), ref)
        let trace30 = stirTrace(regular(path, rate: 30))
        let underWay = worstDifference(trace30, ref, at: { $0 % 2 == 0 && $0 >= 15 })
        let first = worstDifference(trace30, ref, at: { $0 % 2 == 0 && $0 < 15 })
        let between = worstDifference(trace30, ref, at: { $0 % 2 == 1 && $0 >= 15 })
        print("  \(name): 120 Hz \(pct(at120)); 30 Hz \(pct(underWay)) under way, \(pct(first)) in the first 0.25 s, "
              + "\(pct(between)) on the steps between reports under way\(held ? "" : " (not held)")")
        try expect(at120 <= 0.05, "\(name): 120 Hz differs from 60 Hz by \(pct(at120))")
        if held { try expect(underWay <= 0.05, "\(name): 30 Hz differs from 60 Hz by \(pct(underWay))") }
    }
}

/// Leaving and coming back: no way is lost (the way since the last step before leaving is stirred by the next step,
/// even when the pointer left, or left and came back, within that step), and nothing is stirred along the jump.
private func meadowStirAcrossReentry() throws {
    // The first way, (300, 300) to (580, 400) over 20 steps; the second from (1250, 800), away from it.
    func a(_ k: Int) -> PointerInput { .move(300 + 14 * Double(k), 300 + 5 * Double(k)) }
    func b(_ k: Int) -> PointerInput { .move(1250 + 8 * Double(k), 800 + 3 * Double(k)) }
    func first(_ k: Int) -> [PointerInput] { k <= 20 ? [a(k)] : (k == 21 ? [.leave] : []) }
    func second(from e: Int) -> (Int) -> [PointerInput] { { k in k >= e && k < e + 30 ? [b(k - e)] : [] } }
    // Each case against the two ways stirred apart (the first left after a step, as the sketch's leave).
    func afterAStep(_ k: Int) -> [PointerInput] { first(k) + second(from: 31)(k) }
    func withItsLastMove(_ k: Int) -> [PointerInput] {
        if k == 20 { return [a(20), .leave] }
        return k == 21 ? [] : first(k) + second(from: 31)(k)
    }
    func backWithinAStep(_ k: Int) -> [PointerInput] {
        if k == 20 { return [a(20), .leave, b(0)] }
        return k == 21 ? [b(1)] : first(k) + second(from: 20)(k)
    }
    // Each case (and the step the second way comes in) against the two ways stirred apart, the first left after a
    // step, as the sketch's leave.
    let cases: [(String, (Int) -> [PointerInput], Int)] = [
        ("left after a step, back 10 steps later", afterAStep, 31),
        ("left with its last move, back 10 steps later", withItsLastMove, 31),
        ("left and back within one step", backWithinAStep, 20),
    ]
    let onlyFirst = stirTrace(steps: 90, first)
    // Along the jump from (580, 400) to (1250, 800), out of reach of both ways.
    let jump: [(Double, Double)] = [(803, 533), (915, 600), (1027, 667)]
    for (name, events, entry) in cases {
        let onlySecond = stirTrace(steps: 90, second(from: entry))
        let both = stirTrace(steps: 90, events)
        var worst = 0.0
        for t in 0..<90 {
            let sum: [Double] = zip(onlyFirst[t], onlySecond[t]).map { $0 + $1 }
            worst = max(worst, difference(both[t], sum))
        }
        try expect(worst <= 1e-6, "\(name): the air differs from the two ways apart by \(worst)")
        try expectNoJumpAir(events, jump, name)
    }
    // Left, back and left again within one step: the first way's end is stirred then (a step early), the second's
    // by the step; both ways all there.
    func twice(_ k: Int) -> [PointerInput] { k == 20 ? [a(20), .leave, b(0), b(1), .leave] : first(k) }
    func twiceApart(_ k: Int) -> [PointerInput] { k == 20 ? [b(0), b(1), .leave] : [] }
    let apart = stirTrace(steps: 90, twiceApart)
    let both = stirTrace(steps: 90, twice)
    var worst = 0.0
    for t in 0..<90 { worst = max(worst, difference(both[t], zip(onlyFirst[t], apart[t]).map { $0 + $1 })) }
    print("  left, back and left again within one step: \(pct(worst)) from the two ways apart")
    try expect(worst <= 0.05, "left twice within a step: the air differs by \(pct(worst))")
    try expectNoJumpAir(twice, jump, "left twice within a step")
    // The sketch's order (a step between the last move and the leave) and the leave in the move's step stir the same.
    let sketchOrder = stirTrace(steps: 40, first)
    func sameStepLeave(_ k: Int) -> [PointerInput] {
        if k == 20 { return [a(20), .leave] }
        return k == 21 ? [] : first(k)
    }
    let sameStep = stirTrace(steps: 40, sameStepLeave)
    try expect(sketchOrder == sameStep, "a leave in the last move's step lost the way to it")
}

/// No air at the points along a jump, at any step.
private func expectNoJumpAir(_ events: @escaping (Int) -> [PointerInput], _ points: [(Double, Double)], _ what: String) throws {
    let breeze = Breeze(terrain: Terrain.single(width: 1600, height: 1000), cell: CGSize(width: 13, height: 19))
    for k in 1...90 {
        for e in events(k) {
            switch e {
            case .move(let x, let y): breeze.pointerMoved(x: x, y: y)
            case .leave: breeze.pointerLeft()
            }
        }
        breeze.step(meadowStep)
        for (x, y) in points {
            let s = breeze.sample(x, y)
            try expect(s.pointerX == 0 && s.pointerY == 0, "\(what): air along the jump at (\(x), \(y)) after step \(k)")
        }
    }
}

/// Any pointer input at any speed setting (wild jumps, huge and broken points, leaves, several moves a step): every
/// sample of the stir stays finite and within ±260 pt/s, and the air is finite everywhere.
private func meadowStirFiniteAndBounded() throws {
    let breeze = Breeze(terrain: Terrain.single(width: 1600, height: 1000), cell: CGSize(width: 13, height: 19))
    let rng = MeadowRandom(99)
    let speeds: [Double] = [1, 0.05, 1.5, 0.5, 0, -1, .nan, .infinity, 1e300, Double.leastNonzeroMagnitude]
    let wild: [Double] = [.nan, .infinity, -.infinity, 1e300, -1e300, 1e12, Double.greatestFiniteMagnitude]
    // First the same 25 pt stroke at 1500 pt/s again and again at one place (coming back without stirring), to
    // drive the samples there to the clamp.
    for _ in 0..<30 {
        breeze.pointerMoved(x: 825, y: 500)
        breeze.step(meadowStep)
        breeze.pointerLeft()
        breeze.pointerMoved(x: 800, y: 500)
    }
    var peak = 0.0
    for r in 0..<breeze.rows { for c in 0..<breeze.columns { peak = max(peak, abs(breeze.stirSample(c, r).x)) } }
    try expect(peak == 260, "repeated strokes reached \(peak) pt/s, not the clamp of 260")
    for k in 0..<1200 {
        for _ in 0..<Int(rng.unit() * 4) {
            let r = rng.unit()
            if r < 0.1 {
                breeze.pointerLeft()
            } else if r < 0.2 {
                breeze.pointerMoved(x: wild[Int(rng.unit() * Double(wild.count))], y: rng.unit() * 1000)
            } else if r < 0.3 {
                breeze.pointerMoved(x: rng.unit() * 1600, y: wild[Int(rng.unit() * Double(wild.count))])
            } else {
                breeze.pointerMoved(x: rng.unit() * 2400 - 400, y: rng.unit() * 1600 - 300)
            }
        }
        breeze.step(meadowStep, speed: speeds[k % speeds.count])
        if k % 5 == 0 {
            for r in 0..<breeze.rows {
                for c in 0..<breeze.columns {
                    let v = breeze.stirSample(c, r)
                    try expect(v.x.isFinite && v.y.isFinite && abs(v.x) <= 260 && abs(v.y) <= 260,
                               "step \(k): stir \(v) at sample (\(c), \(r))")
                    peak = max(peak, abs(v.x), abs(v.y))
                }
            }
            for (x, y) in [(800.0, 500.0), (0, 0), (1600, 1000), (-1e9, 1e9)] {
                let a = breeze.sample(x, y)
                try expect(a.x.isFinite && a.y.isFinite && a.speed.isFinite, "step \(k): air at (\(x), \(y)) \(a)")
            }
        }
    }
    print(String(format: "  wild input over 1200 steps after the clamp was reached: peak stir %.1f pt/s (limit 260)", peak))
}

private func meadowDownwashOnlyUnderLowButterflies() throws {
    let rig = MeadowRig(Terrain.single(width: 1200, height: 800), cell: 13, seed: 3, plant: false)
    func washAt() -> Double {
        var m = 0.0
        for r in 0..<rig.breeze.rows { for c in 0..<rig.breeze.columns { m = max(m, abs(rig.breeze.washSample(c, r).x)) } }
        return m
    }
    let span: Double = 22 * 13 * 0.6
    let high: [Double] = [0.35, 0.5, 0.9, 1.0]
    for z in high { rig.breeze.downstroke(x: 600, y: 400, z: z, sinStroke: 1, span: span, dt: meadowStep) }
    try expect(washAt() == 0, "downwash from z ≥ 0.35: \(washAt())")
    rig.breeze.downstroke(x: 600, y: 400, z: 0.1, sinStroke: -0.5, span: span, dt: meadowStep)
    try expect(washAt() == 0, "downwash on the upstroke")
    // The air before any wash, at points round the butterfly (the breeze and a pointer's stir), both axes.
    rig.breeze.stir(600, 400, 90, -60)
    let points: [(Double, Double)] = [(660, 400), (540, 400), (600, 460), (600, 340), (650, 450)]
    let before = points.map { rig.breeze.sample($0.0, $0.1) }
    rig.breeze.downstroke(x: 600, y: 400, z: 0.34, sinStroke: 1, span: span, dt: meadowStep)
    let weak = washAt()
    rig.breeze.downstroke(x: 600, y: 400, z: 0.0, sinStroke: 1, span: span, dt: meadowStep)
    let strong: Double = washAt() - weak
    try expect(weak > 0 && strong > weak * 10, "low butterflies wash more: \(weak) at 0.34, \(strong) at 0")
    for (p, b) in zip(points, before) {
        let a = rig.breeze.sample(p.0, p.1)
        // Landed air and the pointer's stir don't feel the wash, on either axis; all the air does, outward.
        try expect(a.landedX == b.landedX && a.landedY == b.landedY, "downwash in the landed air at \(p)")
        try expect(a.pointerX == b.pointerX && a.pointerY == b.pointerY, "downwash in the pointer's air at \(p)")
        let ox: Double = p.0 - 600, oy: Double = p.1 - 400
        let push: Double = (a.x - b.x) * ox + (a.y - b.y) * oy
        try expect(push > 0, "the wash at \(p) doesn't push outward (\(a.x - b.x), \(a.y - b.y))")
    }
    let below = rig.breeze.sample(600, 460)
    try expect(below.y - below.landedY > 0, "no downwash on the y axis")
    // A swallowtail's flutter: 300 of the flight's 520, within one span; nothing on the upstroke or with downwash 0.
    let f = MeadowRig(Terrain.single(width: 1200, height: 800), cell: 13, seed: 3, plant: false)
    func washMax(_ b: Breeze) -> Double {
        var m = 0.0
        for r in 0..<b.rows { for c in 0..<b.columns { m = max(m, simd_length(b.washSample(c, r))) } }
        return m
    }
    f.breeze.flutter(x: 600, y: 400, sinStroke: -1, span: span)
    try expect(washMax(f.breeze) == 0, "a flutter on the upstroke washed")
    f.breeze.flutter(x: 600, y: 400, sinStroke: 1, span: span)
    let flutter = washMax(f.breeze)
    let g = MeadowRig(Terrain.single(width: 1200, height: 800), cell: 13, seed: 3, plant: false)
    g.breeze.downstroke(x: 600, y: 400, z: 0, sinStroke: 1, span: span / 1.2)
    let flight = washMax(g.breeze)
    try expect(flutter > 0 && abs(flutter / flight - 300.0 / 520.0) < 1e-3,
               "a flutter washes \(flutter), the flight \(flight): not 300 to 520")
    let reach: Double = f.breeze.sample(600 + span + 2 * f.breeze.spacing, 400).x - f.breeze.sample(600 + span + 2 * f.breeze.spacing, 400).landedX
    try expect(reach == 0, "a flutter reached past its span")
    var still = MeadowTuning()
    still.downwash = 0
    let h = MeadowRig(Terrain.single(width: 1200, height: 800), cell: 13, seed: 3, tuning: still, plant: false)
    h.breeze.flutter(x: 600, y: 400, sinStroke: 1, span: span)
    h.breeze.downstroke(x: 600, y: 400, z: 0, sinStroke: 1, span: span)
    try expect(washMax(h.breeze) == 0, "downwash 0 still washed")
}

private func meadowWindPeaksAtTheSketchSpeed() throws {
    // Breeze 1.7 (the director's): the speed's theoretical top is 26 · 1.7 · 1.1 · 1.9 ≈ 92.4 pt/s.
    let rig = MeadowRig(Terrain.single(width: 2560, height: 1440), cell: 13, seed: 5, plant: false)
    var peak = 0.0, sum = 0.0, n = 0.0
    for k in 0..<(60 * 3600) {
        rig.breeze.step(meadowStep)
        if k % 30 != 0 { continue }
        for j in 0..<24 {
            let x: Double = 100 + Double(j % 6) * 450
            let y: Double = 100 + Double(j / 6) * 400
            let a = rig.breeze.sample(x, y)
            peak = max(peak, a.speed)
            sum += a.speed
            n += 1
        }
    }
    print("  wind over an hour: peak \(String(format: "%.1f", peak)) pt/s, mean \(String(format: "%.1f", sum / n)) pt/s")
    try expect(peak >= 88 && peak <= 100, "peak \(peak) pt/s, the sketch's about 90–100")
}

/// Whether a flower planted for screen `i` stands where the port allows, tested on its own terms: on its screen; or
/// past it by at most 10 pt on each axis, on no screen, outside the terrain's bounds (not in a gap), with the nearest
/// point of its screen on no other screen, and the segment from its patch's centre (on its screen) to it touching no
/// other screen (so not across a shared edge, offset or not, nor round a seam's end).
private func standsOwn(_ f: Flower, _ terrain: Terrain) -> String? {
    guard f.screen >= 0 && f.screen < terrain.rects.count else { return "no screen \(f.screen)" }
    let r = terrain.rects[f.screen]
    let minX = Double(r.minX), maxX = Double(r.maxX), minY = Double(r.minY), maxY = Double(r.maxY)
    if f.x >= minX && f.x <= maxX && f.y >= minY && f.y <= maxY { return nil }
    let ox: Double = max(minX - f.x, f.x - maxX, 0)
    let oy: Double = max(minY - f.y, f.y - maxY, 0)
    if max(ox, oy) > MeadowTuning.Flowers.edgeSlack + 1e-9 { return "\(max(ox, oy)) pt past its screen" }
    if terrain.contains(SIMD2(f.x, f.y)) { return "on another screen" }
    let b = terrain.bounds
    if Double(b.minX) <= f.x && f.x <= Double(b.maxX) && Double(b.minY) <= f.y && f.y <= Double(b.maxY) { return "in a gap" }
    let q = SIMD2(min(maxX, max(minX, f.x)), min(maxY, max(minY, f.y)))
    for (j, o) in terrain.rects.enumerated() where j != f.screen {
        if Double(o.minX) <= q.x && q.x <= Double(o.maxX) && Double(o.minY) <= q.y && q.y <= Double(o.maxY) {
            return "across the edge it shares with screen \(j)"
        }
    }
    guard Double(r.minX) <= f.rootX && f.rootX <= Double(r.maxX) && Double(r.minY) <= f.rootY && f.rootY <= Double(r.maxY)
    else { return "its patch centre (\(f.rootX), \(f.rootY)) is off its screen" }
    for (j, o) in terrain.rects.enumerated() where j != f.screen {
        if let y = crossing(SIMD2(f.rootX, f.rootY), SIMD2(f.x, f.y), o) {
            return "reached from (\(f.rootX), \(f.rootY)) across screen \(j) (at \(y))"
        }
    }
    return nil
}

/// Where the segment a → b first touches rect `o` (closed), sampled finely; nil if it doesn't. Independent of the
/// port's clipping.
private func crossing(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ o: CGRect) -> SIMD2<Double>? {
    let n = 4000
    for k in 0...n {
        let p: SIMD2<Double> = a + (b - a) * (Double(k) / Double(n))
        if Double(o.minX) <= p.x && p.x <= Double(o.maxX) && Double(o.minY) <= p.y && p.y <= Double(o.maxY) { return p }
    }
    return nil
}

private func meadowNoFlowerInAGap() throws {
    // Offset screens (a strip beside the shorter one), a gap between two, a laptop under a monitor, two aligned
    // screens (the review's corner), three in a row with offsets, and screens meeting at a corner only.
    let layouts: [[CGRect]] = [
        [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1080)],
        [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1500, y: 100, width: 1280, height: 800)],
        [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1800, height: 1169)],
        [CGRect(x: 0, y: 0, width: 1000, height: 700), CGRect(x: 1000, y: 0, width: 1000, height: 700)],
        [CGRect(x: 0, y: 100, width: 900, height: 600), CGRect(x: 900, y: 0, width: 1000, height: 800),
         CGRect(x: 1900, y: 200, width: 800, height: 500)],
        [CGRect(x: 0, y: 0, width: 800, height: 600), CGRect(x: 800, y: 600, width: 800, height: 600)],
        // Offset by a few points: side by side (the re-check's 2 pt, both ways) and one above the other.
        [CGRect(x: 0, y: 0, width: 1000, height: 700), CGRect(x: 1000, y: 2, width: 1000, height: 700)],
        [CGRect(x: 0, y: 0, width: 1000, height: 700), CGRect(x: 1000, y: -3, width: 1000, height: 700)],
        [CGRect(x: 0, y: 0, width: 1000, height: 700), CGRect(x: 4, y: 700, width: 1000, height: 700)],
    ]
    var past = 0
    for (li, rects) in layouts.enumerated() {
        let terrain = Terrain(rects: rects)
        for seed in Int32(1)...Int32(24) {
            let rig = MeadowRig(terrain, cell: 13, seed: seed, tuning: { var t = MeadowTuning(); t.density = 3; return t }())
            for f in rig.flowers.all {
                if let why = standsOwn(f, terrain) {
                    throw CheckFailure(detail: "layout \(li) seed \(seed): flower \(f.id) of screen \(f.screen) at (\(f.x), \(f.y)) \(why)")
                }
                let r = rects[f.screen]
                if !r.contains(CGPoint(x: f.x, y: f.y)) { past += 1 }
            }
        }
    }
    try expect(past > 0, "no bloom ever stood in the slack past a real edge: the test proves nothing")
    // The review's corner: two aligned 1000 × 700 screens; a patch on the left can't take (1005, −4) round the shared
    // edge's end, nor (1005, 300) across it; past the real top edge (500, −4) is fine, and so past the outer corner.
    let two = MeadowRig(Terrain(rects: layouts[3]), cell: 13, seed: 1, plant: false)
    let cases: [(Double, Double, Int, Bool)] = [
        (1005, -4, 0, false), (1005, 300, 0, false), (1005, 704, 0, false), (995, -4, 1, false), (500, -4, 0, true),
        (-5, -5, 0, true), (2005, 705, 1, true), (1500, 705, 1, true), (995, 705, 0, true),
    ]
    for (x, y, i, ok) in cases {
        try expect(two.flowers.mayStand(x, y, screen: i) == ok, "(\(x), \(y)) for screen \(i): \(!ok) (want \(ok))")
    }
    // The re-check's offset seam: the right screen 2 pt lower. A bloom past the top-right corner is beside the real
    // 2 pt of the shared side, but the way from its patch crosses the shared span: refused. Without the patch centre
    // (the nearest point of the screen) the same place is allowed, which is what the earlier test checked alone.
    let offset = MeadowRig(Terrain(rects: layouts[6]), cell: 13, seed: 1, plant: false)
    try expect(!offset.flowers.mayStand(1005, -4, screen: 0, from: SIMD2(970, 50)),
               "(1005, −4) reached from (970, 50) across the shared edge of the offset screens")
    try expect(!offset.flowers.mayStand(1004.84, -1.28, screen: 0, from: SIMD2(943.43, 74.54))
               && offset.flowers.mayStand(1004.84, -1.28, screen: 0),
               "seed 7773's bloom: refused from its patch, allowed from the screen's nearest point")
    try expect(offset.flowers.mayStand(1004, -4, screen: 0, from: SIMD2(1000, 0)) && offset.flowers.mayStand(500, -4, screen: 0, from: SIMD2(500, 40)),
               "past the real 2 pt of the side and past the top, reached straight out: allowed")
    // Seed 7773 there, planted (the re-check's case: its patch at (943.43, 74.54) put bloom 5 at (1004.84, −1.28)).
    let seeded = MeadowRig(Terrain(rects: layouts[6]), cell: 13, seed: 7773)
    let patch = seeded.flowers.all.filter { abs($0.rootX - 943.43) < 0.01 && abs($0.rootY - 74.54) < 0.01 }
    try expect(!patch.isEmpty, "seed 7773 no longer plants the patch at (943.43, 74.54): the case isn't tested")
    for f in seeded.flowers.all {
        if let why = standsOwn(f, seeded.flowers.terrain) { throw CheckFailure(detail: "seed 7773: flower \(f.id) at (\(f.x), \(f.y)) \(why)") }
    }
    // Screens meeting at a corner only: nothing reaches round it.
    let corner = MeadowRig(Terrain(rects: layouts[5]), cell: 13, seed: 1, plant: false)
    try expect(!corner.flowers.mayStand(805, 595, screen: 0) && !corner.flowers.mayStand(795, 605, screen: 1),
               "a bloom reached round the corner two screens meet at")
}

private func meadowNoOverlapAndPatchesFollowArea() throws {
    let sizes: [(Double, Double, Double)] = [(1440, 900, 0.85), (2560, 1440, 0.85), (2560, 1440, 2.5), (800, 500, 0.2), (3000, 300, 1)]
    for (w, h, density) in sizes {
        let rig = MeadowRig(Terrain.single(width: w, height: h), cell: 13, seed: 11,
                            tuning: { var t = MeadowTuning(); t.density = density; return t }())
        let want = max(1, Int(MeadowMath.round(w * h / 190_000 * density)))
        try expect(rig.flowers.patches == want, "\(w)x\(h) at \(density): \(rig.flowers.patches) patches, want \(want)")
        let all = rig.flowers.all
        for i in all.indices {
            for j in all.indices where j > i {
                let d: Double = ((all[i].x - all[j].x) * (all[i].x - all[j].x) + (all[i].y - all[j].y) * (all[i].y - all[j].y)).squareRoot()
                let need: Double = (all[i].radius + all[j].radius) * 1.05
                try expect(d >= need, "\(w)x\(h): flowers \(all[i].id) and \(all[j].id) overlap (\(d) < \(need))")
            }
        }
        for i in all.indices.dropFirst() { try expect(all[i - 1].radius <= all[i].radius, "not small first") }
    }
    // Per screen: two screens get each its own share, and twice the density about twice the flowers.
    let two = Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)])
    let r2 = MeadowRig(two, cell: 13, seed: 4)
    let want2 = Int(MeadowMath.round(1440 * 900 / 190_000 * 0.85)) + Int(MeadowMath.round(1920 * 1080 / 190_000 * 0.85))
    try expect(r2.flowers.patches == want2, "two screens: \(r2.flowers.patches) patches, want \(want2)")
    var lo = 0, hi = 0
    for seed in Int32(1)...Int32(10) {
        lo += MeadowRig(Terrain.single(width: 2560, height: 1440), cell: 13, seed: seed).flowers.all.count
        hi += MeadowRig(Terrain.single(width: 2560, height: 1440), cell: 13, seed: seed,
                        tuning: { var t = MeadowTuning(); t.density = 1.7; return t }()).flowers.all.count
    }
    let ratio: Double = Double(hi) / Double(lo)
    try expect(ratio > 1.6 && ratio < 2.2, "twice the density gives \(ratio) × the flowers")
}

private func meadowHeadSpringRings() throws {
    // No wind: a nod rings the head at f0 with ζ 0.12.
    var calm = MeadowTuning()
    calm.breeze = 0
    let rig = MeadowRig(Terrain.single(width: 1600, height: 1000), cell: 13, seed: 21, tuning: calm)
    var worstF = 0.0, worstZ = 0.0
    for f in rig.flowers.all.prefix(6) {
        rig.flowers.nod(id: f.id, dx: 1, dy: 0, size: 1, k: 1)
        var xs: [Double] = []
        for _ in 0..<600 {
            rig.step()
            xs.append(rig.flowers.flower(id: f.id)?.ox ?? 0)
        }
        // Upward zero crossings give the period; successive positive peaks the decay.
        var ups: [Double] = []
        var peaks: [Double] = []
        for i in 1..<(xs.count - 1) {
            if xs[i - 1] < 0 && xs[i] >= 0 { ups.append(Double(i - 1) + -xs[i - 1] / (xs[i] - xs[i - 1])) }
            if xs[i] > xs[i - 1] && xs[i] >= xs[i + 1] && xs[i] > 0 { peaks.append(xs[i]) }
        }
        try expect(ups.count >= 4 && peaks.count >= 4, "flower \(f.id) doesn't ring")
        let period: Double = (ups[3] - ups[0]) / 3 * meadowStep
        let freq: Double = 1 / period
        let decrement: Double = log(peaks[0] / peaks[3]) / 3
        let zeta: Double = decrement / (4 * Double.pi * Double.pi + decrement * decrement).squareRoot()
        worstF = max(worstF, abs(freq / f.f0 - 1))
        worstZ = max(worstZ, abs(zeta - 0.12))
        try expect(abs(freq / f.f0 - 1) < 0.05, "\(f.kind.name) rings at \(freq) Hz, f0 \(f.f0)")
        try expect(abs(zeta - 0.12) < 0.02, "\(f.kind.name) ζ \(zeta)")
    }
    print("  head spring: frequency within \(String(format: "%.1f", worstF * 100)) % of f0, ζ within \(String(format: "%.3f", worstZ)) of 0.12")
    // The strongest breeze and a stirring pointer never swing a head past 0.45 R.
    var wild = MeadowTuning()
    wild.breeze = 3
    let gale = MeadowRig(Terrain.single(width: 1600, height: 1000), cell: 13, seed: 22, tuning: wild)
    for k in 0..<3600 {
        let t: Double = Double(k) / 60
        gale.breeze.pointerMoved(x: 800 + 700 * sin(7 * t), y: 500 + 450 * cos(5 * t))
        gale.step()
        for f in gale.flowers.all {
            let m: Double = (f.ox * f.ox + f.oy * f.oy).squareRoot()
            try expect(m <= 0.45 * f.radius + 1e-9, "step \(k): \(f.kind.name) swung \(m / f.radius) R")
        }
    }
}

/// The open spot furthest from every flower, on a 20 pt lattice 60 pt in from the edges.
private func openSpot(_ rig: MeadowRig) -> SIMD2<Double> {
    let b = rig.flowers.terrain.bounds
    var spot = SIMD2<Double>(0, 0)
    var best = -1.0
    for y in stride(from: 60.0, to: Double(b.height) - 60, by: 20) {
        for x in stride(from: 60.0, to: Double(b.width) - 60, by: 20) {
            var d = 1e9
            for f in rig.flowers.all { d = min(d, ((f.x - x) * (f.x - x) + (f.y - y) * (f.y - y)).squareRoot() - f.radius) }
            if d > best { best = d; spot = SIMD2(x, y) }
        }
    }
    return spot
}

private func meadowClicksTouchNeverStack() throws {
    let rig = MeadowRig(Terrain.single(width: 1600, height: 1000), cell: 13, seed: 31)
    rig.step(30)
    let spot = openSpot(rig)
    let before = rig.flowers.all.count
    var blooms = 0, touches = 0
    var bloomId = 0
    var told: [(Int, Double, Double)] = []
    rig.flowers.onTouched = { told.append(($0, $1, $2)) }
    for k in 0..<30 {
        switch rig.flowers.click(x: spot.x, y: spot.y, rng: rig.input) {
        case .bloomed(let id, _):
            blooms += 1
            bloomId = id
        case .touched(let id, _):
            touches += 1
            // The touch callback names the touched flower, by id, with the click's place.
            let last = told.last
            try expect(told.count == touches && last?.0 == id && last?.1 == spot.x && last?.2 == spot.y,
                       "click \(k): touched \(id), callback \(String(describing: last))")
            try expect(id == bloomId, "click \(k) touched \(id), not the bloom \(bloomId) it made")
        case .ignored:
            break
        }
        rig.step(6)
    }
    try expect(blooms == 1 && touches == 29, "30 clicks on one spot: \(blooms) blooms, \(touches) touches")
    // The puff (the port's documented rule): 8 sparks, 3 when touched again within 0.5 s, counted from a touch at
    // time 0 too.
    let fresh = MeadowRig(Terrain.single(width: 1600, height: 1000), cell: 13, seed: 31)
    let f0 = fresh.flowers.all[fresh.flowers.all.count - 1]
    let puffs: [FlowerClick] = [fresh.flowers.click(x: f0.x, y: f0.y, rng: fresh.input),
                                fresh.flowers.click(x: f0.x, y: f0.y, rng: fresh.input)]
    fresh.step(31)
    let third = fresh.flowers.click(x: f0.x, y: f0.y, rng: fresh.input)
    try expect(puffs == [.touched(id: f0.id, sparks: 8), .touched(id: f0.id, sparks: 3)] && third == .touched(id: f0.id, sparks: 8),
               "puffs \(puffs), then \(third) after 0.52 s")
    try expect(rig.flowers.all.count == before + 1, "flowers \(before) -> \(rig.flowers.all.count)")
    // A touch nods the head and stays inside 0.45 R however fast the clicks.
    for f in rig.flowers.all {
        try expect((f.ox * f.ox + f.oy * f.oy).squareRoot() <= 0.45 * f.radius + 1e-9, "a touched head swung too far")
    }
    // A click off the meadow does nothing.
    try expect(rig.flowers.click(x: -50, y: 300, rng: rig.input) == .ignored, "a click off the meadow counted")
}

private func meadowClickLimitAndFade() throws {
    var t = MeadowTuning()
    t.density = 0.2
    t.clickLimit = 5
    let rig = MeadowRig(Terrain.single(width: 2560, height: 1440), cell: 13, seed: 41, tuning: t)
    var closed: [Int] = []
    rig.flowers.onClosing = { closed.append($0) }
    var bloomed: [Int] = []
    var k = 0
    for y in stride(from: 120.0, to: 1400, by: 230) {
        for x in stride(from: 120.0, to: 2500, by: 230) {
            if case .bloomed(let id, _) = rig.flowers.click(x: x, y: y, rng: rig.input) { bloomed.append(id) }
            try expect(rig.flowers.clickedOpen <= 5, "\(rig.flowers.clickedOpen) clicked flowers open, limit 5")
            k += 1
            rig.step()
        }
    }
    try expect(bloomed.count >= 9, "only \(bloomed.count) blooms")
    try expect(closed == Array(bloomed.prefix(bloomed.count - 5)), "closed \(closed), bloomed \(bloomed): not oldest first")
    // The newest closing fades from 1 to 0 over 2 s, then goes.
    let last = closed[closed.count - 1]
    let fade0 = rig.flowers.flower(id: last)?.fade ?? -1
    try expect(fade0 > 0.95 && rig.flowers.flower(id: last)?.fading == true, "a closing flower isn't fading: \(fade0)")
    var steps = 0
    while rig.flowers.flower(id: last) != nil && steps < 400 { rig.step(); steps += 1 }
    let expected = Int(((fade0 * 2) / meadowStep).rounded(.up))
    try expect(abs(steps - expected) <= 1, "faded in \(steps) steps, want \(expected) (2 s)")
    // A smaller limit closes the oldest at once.
    rig.flowers.tuning.clickLimit = 2
    rig.flowers.limitClicked()
    try expect(rig.flowers.clickedOpen == 2, "limit 2 leaves \(rig.flowers.clickedOpen)")
    try sparkBufferHolds()
}

/// The spark buffer's real limit (`Clicks.sparkBuffer`): 30 new blooms in one step let off 480 sparks and it keeps
/// 256; the dropped sparks still draw their random numbers, so the input stream is where it would be had every spark
/// been taken.
private func sparkBufferHolds() throws {
    func thirty(takingEach: Bool) throws -> (kept: Int, asked: Int, next: Double) {
        let rig = MeadowRig(Terrain.single(width: 2600, height: 1600), cell: 13, seed: 5, plant: false)
        var asked = 0, kept = 0
        for k in 0..<30 {
            let x: Double = 150 + 260 * Double(k % 10)
            let y: Double = 200 + 400 * Double(k / 10)
            guard case .bloomed(_, let n) = rig.flowers.click(x: x, y: y, rng: rig.input) else {
                throw CheckFailure(detail: "click \(k) at (\(x), \(y)) didn't bloom")
            }
            asked += n
            if takingEach { rig.flowers.takeSparks { _ in kept += 1 } }
        }
        if !takingEach { rig.flowers.takeSparks { _ in kept += 1 } }
        return (kept, asked, rig.input.unit())
    }
    let burst = try thirty(takingEach: false)
    let taken = try thirty(takingEach: true)
    try expect(burst.asked == 480 && burst.kept == MeadowTuning.Clicks.sparkBuffer && burst.kept == 256,
               "30 blooms in a step: \(burst.asked) sparks asked, \(burst.kept) kept (want 480, 256)")
    try expect(taken.kept == 480, "taken after each click, \(taken.kept) of 480 sparks kept")
    try expect(burst.next == taken.next, "dropping sparks moved the input stream")
}

/// Flower `id` closes now (its callback, by id), fades over 2 s, and is gone.
private func expectFadesOut(_ rig: MeadowRig, _ id: Int, closed: [Int], _ what: String) throws {
    try expect(closed.contains(id), "\(what): no closing callback for \(id) (closed \(closed))")
    guard let f = rig.flowers.flower(id: id) else { throw CheckFailure(detail: "\(what): \(id) vanished at once") }
    try expect(f.fading && f.fade > 0.99, "\(what): \(id) isn't fading (\(f.fading), \(f.fade))")
    rig.step(60)
    let half = rig.flowers.flower(id: id)?.fade ?? -1
    try expect(abs(half - 0.5) < 0.01, "\(what): \(id) after 1 s fade \(half)")
    rig.step(61)
    try expect(rig.flowers.flower(id: id) == nil, "\(what): \(id) didn't go after 2 s")
}

private func meadowRelayoutFadesClickedOffScreen() throws {
    let cellSize = CGSize(width: 13, height: 19)
    // Small (under 80 pt): a clicked flower left off the screen fades.
    do {
        let rig = MeadowRig(Terrain.single(width: 1600, height: 1000), cell: 13, seed: 51,
                            tuning: { var t = MeadowTuning(); t.density = 0.2; return t }())
        var id = 0
        for x in stride(from: 1590.0, to: 1500, by: -10) {
            if case .bloomed(let i, _) = rig.flowers.click(x: x, y: 500, rng: rig.input) { id = i; break }
        }
        try expect(id > 0, "no bloom near the right edge")
        let x = rig.flowers.flower(id: id)?.x ?? 0
        var closed: [Int] = []
        rig.flowers.onClosing = { closed.append($0) }
        rig.flowers.relayout(terrain: Terrain.single(width: x - 30, height: 1000), cell: cellSize, rng: rig.input)
        try expectFadesOut(rig, id, closed: closed, "a clicked flower after a small resize")
    }
    // Planted flowers: the top edge moved 5 pt past one (inside the planting slack), and the bottom edge 40 pt past
    // another in a big resize (over 80 pt): both fade by id, the second through the replant.
    for big in [false, true] {
        let rig = MeadowRig(Terrain.single(width: 1600, height: 913), cell: 13, seed: 4242)
        rig.step(10)
        let planted = rig.flowers.all.filter { !$0.clicked && (big ? $0.y > 300 && $0.y < 853 : $0.y > 0 && $0.y < 70) }
        guard let near = big ? planted.max(by: { $0.y < $1.y }) : planted.min(by: { $0.y < $1.y }) else {
            throw CheckFailure(detail: "no planted flower to move an edge past")
        }
        var closed: [Int] = []
        var replanted = 0
        rig.flowers.onClosing = { closed.append($0) }
        rig.flowers.onReplanted = { replanted += 1 }
        let terrain: Terrain
        if big {
            // 40 pt past it at the bottom, and the window 120 pt narrower: a replant.
            terrain = Terrain(rects: [CGRect(x: 0, y: 0, width: 1480, height: near.y - 40)])
        } else {
            terrain = Terrain(rects: [CGRect(x: 0, y: near.y + 5, width: 1600, height: 913 - near.y - 5)])
        }
        rig.flowers.relayout(terrain: terrain, cell: cellSize, rng: rig.input)
        try expect(replanted == (big ? 1 : 0), "big \(big): replanted \(replanted) times")
        try expectFadesOut(rig, near.id, closed: closed, big ? "a planted flower in a big resize" : "a planted flower 5 pt off")
        for f in rig.flowers.all where !f.fading {
            try expect(rig.flowers.mayStand(f.x, f.y), "after the relayout flower \(f.id) stands at (\(f.x), \(f.y))")
        }
    }
    // A cell-only change goes through the sizing transition: a clicked flower is resized (13 → 15: × 15/13).
    do {
        var t = MeadowTuning()
        t.density = 0.2
        let rig = MeadowRig(Terrain.single(width: 1600, height: 1000), cell: 13, seed: 52, tuning: t)
        var id = 0
        for x in stride(from: 300.0, to: 1300, by: 50) {
            if case .bloomed(let i, _) = rig.flowers.click(x: x, y: 500, rng: rig.input) { id = i; break }
        }
        let r0 = rig.flowers.flower(id: id)?.radius ?? 0
        var replanted = 0
        rig.flowers.onReplanted = { replanted += 1 }
        rig.flowers.relayout(terrain: Terrain.single(width: 1600, height: 1000), cell: CGSize(width: 15, height: 22),
                             rng: rig.input)
        let f = rig.flowers.flower(id: id)
        let k: Double = 15.0 / 13.0
        try expect(replanted == 1, "a cell change didn't replant")
        try expect(abs((f?.sizeK ?? 0) - 1.32 * k) < 1e-9 && abs((f?.radius ?? 0) - r0 * k) < 1e-9,
                   "after 13 → 15 the clicked flower's size factor is \(f?.sizeK ?? -1), radius \(f?.radius ?? -1) (want \(1.32 * k), \(r0 * k))")
        try expect(abs(rig.breeze.unit - k) < 1e-12 && abs(rig.breeze.spacing - 48 * k) < 1e-9, "the breeze wasn't laid out at the new cell")
    }
    // A big change replants: every open centre where a bloom may stand, each on its own screen's terms.
    let rig = MeadowRig(Terrain.single(width: 1600, height: 1000), cell: 13, seed: 53)
    let two = Terrain(rects: [CGRect(x: 0, y: 0, width: 1000, height: 700), CGRect(x: 1000, y: 200, width: 900, height: 600)])
    rig.flowers.relayout(terrain: two, cell: CGSize(width: 12, height: 17), rng: rig.input)
    for f in rig.flowers.all where !f.fading {
        if let why = standsOwn(f, two) { throw CheckFailure(detail: "after the replant flower \(f.id) \(why)") }
    }
}

/// Growth overshoots, then settles; a fed flower lights up; a visited one dims for 20–40 s and eases back.
private func meadowGrowthLiftAndDim() throws {
    var calm = MeadowTuning()
    calm.breeze = 0
    let rig = MeadowRig(Terrain.single(width: 1600, height: 1000), cell: 13, seed: 81, tuning: calm)
    let spot = openSpot(rig)
    guard case .bloomed(let id, _) = rig.flowers.click(x: spot.x, y: spot.y, rng: rig.input) else {
        throw CheckFailure(detail: "no bloom at \(spot)")
    }
    var peak = 0.0
    var steps = 0
    while (rig.flowers.flower(id: id)?.age ?? 1) < 1 && steps < 400 {
        rig.step()
        steps += 1
        peak = max(peak, rig.flowers.flower(id: id)?.grow ?? 0)
    }
    // easeOutBack with c1 1.4 peaks at 1 + 2.4 u³ + 1.4 u², u = −2.8 / 7.2 (age ≈ 0.61): about 1.0706; grown in 2.2 s.
    let u: Double = -2.8 / 7.2
    let top: Double = 1 + 2.4 * u * u * u + 1.4 * u * u
    try expect(abs(peak - top) < 0.002, "growth peaks at \(peak), want the overshoot \(top)")
    try expect(abs(Double(steps) - 132) <= 1, "grown in \(steps) steps, want 2.2 s")
    try expect(rig.flowers.flower(id: id)?.grow == 1, "not settled at 1 once grown")
    // Fed: eased toward 1 at 1.6/s; and back down when the butterfly goes.
    let target = rig.flowers.all[0].id
    rig.flowers.setFeeding(id: target, true)
    rig.step()
    let one = rig.flowers.flower(id: target)?.lift ?? 0
    try expect(abs(one - meadowStep * 1.6) < 1e-12, "lift after one step \(one)")
    rig.step(179)
    let lit = rig.flowers.flower(id: target)?.lift ?? 0
    let want: Double = 1 - pow(1 - meadowStep * 1.6, 180)
    try expect(abs(lit - want) < 1e-9, "lift after 3 s \(lit), want \(want)")
    rig.flowers.setFeeding(id: target, false)
    rig.step(300)
    try expect((rig.flowers.flower(id: target)?.lift ?? 1) < 0.001, "the lift stays up after the feeding")
    // Visited: dims fully for the first 65 % of its 20–40 s, then eases back to none.
    rig.flowers.visited(id: target, rng: rig.sim)
    guard let v = rig.flowers.flower(id: target) else { throw CheckFailure(detail: "visited flower gone") }
    try expect(v.dimMax >= 20 && v.dimMax <= 40 && v.dimT == v.dimMax && v.visitDim == 1, "visited: \(v.dimMax) s, dim \(v.visitDim)")
    rig.step(Int(v.dimMax * 0.6 * 60))
    try expect(rig.flowers.flower(id: target)?.visitDim == 1, "the dim eased before 65 % of its time")
    rig.step(Int(v.dimMax * 0.25 * 60))
    let easing = rig.flowers.flower(id: target)?.visitDim ?? 0
    try expect(easing > 0 && easing < 1, "the dim isn't easing back (\(easing))")
    rig.step(Int(v.dimMax * 0.2 * 60))
    try expect(rig.flowers.flower(id: target)?.visitDim == 0, "still dim after its time")
    // A nod by id moves only that head.
    let others = rig.flowers.all.filter { $0.id != target }.map { ($0.id, $0.vx) }
    rig.flowers.nod(id: target, dx: 1, dy: 0, size: 1, k: 1)
    try expect((rig.flowers.flower(id: target)?.vx ?? 0) > 0, "the nod didn't move its head")
    for (oid, vx) in others { try expect(rig.flowers.flower(id: oid)?.vx == vx, "a nod moved flower \(oid)") }
}

private func meadowFiniteOnBadInput() throws {
    let bad: [Double] = [.nan, .infinity, -.infinity, 1e300, -1e300]
    let rig = MeadowRig(Terrain.single(width: 1440, height: 900), cell: 13, seed: 61)
    for v in bad {
        rig.breeze.pointerMoved(x: v, y: 300)
        rig.breeze.pointerMoved(x: 300, y: v)
        rig.breeze.stir(v, 300, 50, 50)
        rig.breeze.stir(300, 300, v, 50)
        rig.breeze.wash(300, 300, v, 100)
        rig.breeze.wash(v, 300, 10, v)
        rig.breeze.downstroke(x: 300, y: 300, z: v, sinStroke: 1, span: 100, dt: meadowStep)
        rig.breeze.downstroke(x: 300, y: 300, z: 0.1, sinStroke: v, span: v, dt: v)
        _ = rig.flowers.click(x: v, y: 200, rng: rig.input)
        _ = rig.flowers.click(x: 200, y: v, rng: rig.input)
        if let f = rig.flowers.all.first { rig.flowers.nod(id: f.id, dx: v, dy: 1, size: 1, k: 1) }
        rig.breeze.step(v)
        rig.flowers.step(v)
        let a = rig.breeze.sample(v, v)
        if v.isFinite {
            try expect(a.x.isFinite && a.y.isFinite && a.speed.isFinite, "air at \(v): \(a)")
        } else {
            try expect(a == MeadowAir(), "air at a broken point: \(a)")
        }
    }
    rig.breeze.pointerMoved(x: 1e15, y: -1e15)
    rig.step(30)
    func finite(_ rig: MeadowRig, _ at: String) throws {
        for f in rig.flowers.all {
            try expect(f.ox.isFinite && f.oy.isFinite && f.x.isFinite && f.radius.isFinite, "\(at): flower \(f.id) not finite")
        }
        let points: [(Double, Double)] = [(0, 0), (700, 400), (1e9, 1e9)]
        for p in points {
            let a = rig.breeze.sample(p.0, p.1)
            try expect(a.x.isFinite && a.y.isFinite && a.speed.isFinite && a.gust.isFinite, "\(at): air at \(p) \(a)")
        }
    }
    try finite(rig, "bad input")
    // Zero, empty, huge and broken viewports and cells.
    let terrains: [(String, Terrain)] = [
        ("zero", Terrain.single(width: 0, height: 0)), ("empty", Terrain(rects: [])),
        ("thin", Terrain.single(width: 1, height: 5000)), ("huge", Terrain.single(width: 1e6, height: 1e6)),
    ]
    for (name, terrain) in terrains {
        let cells: [Double] = [13, 0, -5, .nan]
        for cell in cells {
            let r = MeadowRig(terrain, cell: cell, seed: 62)
            r.breeze.pointerMoved(x: 10, y: 10)
            r.breeze.pointerMoved(x: 400, y: 300)
            _ = r.flowers.click(x: 5, y: 5, rng: r.input)
            r.step(3)
            try finite(r, "\(name) at cell \(cell)")
            try expect(r.breeze.columns * r.breeze.rows <= MeadowTuning.Stir.maxSamples, "\(name): grid too big")
        }
    }
    // A broken tuning is put right: a value that isn't a number keeps the default (the sketch's `normalize`
    // keeps the base's), one out of range is held to it.
    var t = MeadowTuning()
    t.breeze = .nan
    t.density = .infinity
    t.flowerSize = 9
    t.clickLimit = -4
    let s = t.sanitized()
    try expect(s.breeze == 1.7 && s.density == 0.85 && s.flowerSize == 2 && s.clickLimit == 1, "sanitized \(s)")
    try meadowBoundsAtTheEntryPoints()
}

/// The review's bad inputs, through the model's own entry points.
private func meadowBoundsAtTheEntryPoints() throws {
    let started = Date()
    // A subnormal, a tiny, a huge and a broken cell width: the unit stays a usable scale and layout ends.
    let widths: [Double] = [Double.leastNonzeroMagnitude, Double.leastNormalMagnitude, 1e-300, 0.5, 1e300, -0.0, .nan]
    for w in widths {
        let terrain = Terrain.single(width: 1600, height: 913)
        let rig = MeadowRig(terrain, cell: w, seed: 64)
        try expect(rig.breeze.unit >= 2.0 / 13 - 1e-12 && rig.breeze.unit <= 100.0 / 13 + 1e-12 && rig.breeze.spacing > 0,
                   "cell \(w): unit \(rig.breeze.unit), spacing \(rig.breeze.spacing)")
        rig.flowers.relayout(terrain: terrain, cell: CGSize(width: w, height: w), rng: rig.input)
        rig.step(2)
        try expect(rig.breeze.columns * rig.breeze.rows <= MeadowTuning.Stir.maxSamples, "cell \(w): grid too big")
    }
    try expect(Date().timeIntervalSince(started) < 20, "layout at broken cell widths took \(Date().timeIntervalSince(started)) s")
    // Sampling at the largest coordinates: finite air (no overflow in the gust bands).
    let rig = MeadowRig(Terrain.single(width: 1600, height: 913), cell: 13, seed: 65)
    rig.step(10)
    let big = Double.greatestFiniteMagnitude
    let far: [(Double, Double)] = [(big, big), (-big, big), (big, -big), (1e300, 3), (3, -1e300)]
    for (x, y) in far {
        let a = rig.breeze.sample(x, y)
        try expect(a.x.isFinite && a.y.isFinite && a.speed.isFinite && a.gust.isFinite && a.landedX.isFinite,
                   "air at (\(x), \(y)): \(a)")
        rig.breeze.pointerMoved(x: x, y: y)
    }
    rig.step(20)
    try expect(rig.breeze.sample(800, 400).speed.isFinite, "a pointer at the largest coordinates broke the air")
    // A pace that isn't usable: subnormal, zero, negative, huge, NaN. A step is a step's real time at the pace held to
    // 0.05…1.5 (1 when it isn't a positive number): the same 10 pt move stirs as at that pace, finite.
    let paces: [(Double, Double)] = [(Double.leastNonzeroMagnitude, 0.05), (0, 1), (-1, 1), (1e300, 1.5), (.infinity, 1), (.nan, 1)]
    func stroke(_ speed: Double) -> SIMD2<Double> {
        let b = Breeze(terrain: Terrain.single(width: 1600, height: 913), cell: CGSize(width: 13, height: 19))
        b.pointerMoved(x: 800, y: 400)
        b.step(meadowStep, speed: 1)
        b.pointerMoved(x: 810, y: 400)
        b.step(meadowStep, speed: speed)
        return SIMD2(b.sample(810, 400).pointerX, b.sample(810, 400).pointerY)
    }
    for (v, held) in paces {
        let got = stroke(v), want = stroke(held)
        try expect(got.x.isFinite && got.y.isFinite && got == want && want.x > 0, "pace \(v): the stroke \(got), want \(want) (pace \(held))")
        rig.breeze.step(meadowStep, speed: v)
        try expect(rig.breeze.sample(800, 400).speed.isFinite, "pace \(v): air not finite")
    }
    try expect(stroke(0.05) != stroke(1) && stroke(1.5) != stroke(1), "the pace doesn't change the stroke: the test proves nothing")
    // Tuning written after start is put right: a NaN breeze keeps the default; a huge one is held to 3.
    rig.breeze.tuning.breeze = .nan
    rig.flowers.tuning.flowerSize = .infinity
    rig.flowers.tuning.clickLimit = 1000
    try expect(rig.breeze.tuning.breeze == 1.7 && rig.flowers.tuning.flowerSize == 1.32 && rig.flowers.tuning.clickLimit == 30,
               "tuning after a bad write: \(rig.breeze.tuning.breeze), \(rig.flowers.tuning.flowerSize), \(rig.flowers.tuning.clickLimit)")
    rig.breeze.tuning.breeze = 1e9
    try expect(rig.breeze.tuning.breeze == 3, "a huge breeze wasn't held to 3")
    rig.step()
    try expect(rig.breeze.sample(700, 300).speed.isFinite, "air not finite after bad tuning writes")
    // Only the clock's tick steps: anything else is refused, the clock and fields unchanged (a pointer moved before
    // them stirs nothing).
    let tick = rig.breeze.time, steps = rig.breeze.steps
    rig.breeze.pointerLeft()
    rig.breeze.pointerMoved(x: 700, y: 300)
    rig.breeze.pointerMoved(x: 900, y: 420)
    var stirred = 0.0
    for r in 0..<rig.breeze.rows { for c in 0..<rig.breeze.columns { stirred += simd_length(rig.breeze.stirSample(c, r)) } }
    let heads = rig.flowers.all.map { SIMD2($0.ox, $0.oy) }
    let odd: [Double] = [1.0 / 30, 1.0 / 120, 0.1, 1e-300, 1.0 / 60 + 1e-15, -meadowStep, .nan]
    for dt in odd {
        rig.breeze.step(dt)
        rig.flowers.step(dt)
        rig.breeze.downstroke(x: 700, y: 300, z: 0, sinStroke: 1, span: 100, dt: dt)
        rig.breeze.flutter(x: 700, y: 300, sinStroke: 1, span: 100, dt: dt)
    }
    try expect(rig.breeze.time == tick && rig.breeze.steps == steps, "a step that isn't the tick was taken")
    var stirredAfter = 0.0
    for r in 0..<rig.breeze.rows { for c in 0..<rig.breeze.columns { stirredAfter += simd_length(rig.breeze.stirSample(c, r)) } }
    try expect(stirredAfter == stirred, "a step that isn't the tick stirred or decayed the air")
    try expect(rig.flowers.all.map { SIMD2($0.ox, $0.oy) } == heads, "the flowers stepped at a length that isn't the tick")
    var washed = 0.0
    for r in 0..<rig.breeze.rows { for c in 0..<rig.breeze.columns { washed += simd_length(rig.breeze.washSample(c, r)) } }
    try expect(washed == 0, "a downstroke at a length that isn't the tick washed")
}

private func meadowStepAllocatesNothing() throws {
    let terrain = Terrain(rects: [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 2560, height: 1440)])
    let rig = MeadowRig(terrain, cell: 13, seed: 71)
    _ = rig.flowers.click(x: 700, y: 500, rng: rig.input)
    rig.step(120)
    var k = 120
    let n = allocations {
        for _ in 0..<600 {
            // Moves at 30 Hz and on every seventh step, a leave every 2 s (back with the next move), and once in
            // those 2 s left and back within one step.
            if k % 2 == 0 || k % 7 == 0 {
                let te: Double = Double(k) / 60
                rig.breeze.pointerMoved(x: 1500 + 900 * sin(te), y: 600 + 400 * cos(1.7 * te))
            }
            if k % 120 == 60 { rig.breeze.pointerLeft() }
            if k % 120 == 90 { rig.breeze.pointerLeft(); rig.breeze.pointerMoved(x: 300, y: 300) }
            rig.breeze.downstroke(x: 1200, y: 500, z: 0.1, sinStroke: 0.8, span: 170, dt: meadowStep)
            rig.breeze.flutter(x: 1300, y: 520, sinStroke: 0.8, span: 120, dt: meadowStep)
            rig.step()
            _ = rig.breeze.sample(400, 300)
            k += 1
        }
    }
    guard let n else { print("  (allocator not watchable here: skipped the count)"); return }
    try expect(n == 0, "\(n) allocations in 600 warmed steps")
}

private func meadowReplaysTheSketchFixture() throws {
    guard fixture("air-flowers") != nil else {
        throw CheckFailure(detail: "Fixtures/air-flowers.json (the sketch's fix round 2) has not landed yet")
    }
    try replaySketchFixture()
}

/// The fixture's sample ticks, as the sketch's `FIXTURE_TICKS` (html:2906).
private let fixtureTicks = [0, 1, 60, 600, 1800]

/// The sketch's own replay fixture (`air-flowers`, format 2, from `meadow-sketch` at 4e1b869; its format is at the top
/// of the sketch's export code, html:2842–2905). Validated first (version 2, the scenario, a clock of the integer rate
/// 60 with the declared last tick, no `problems`, the documented sample ticks, every wind row there), then replayed:
/// the seed's planting, then the ticks with the pointer trace fed as the sketch's handlers take it (a move stirs from
/// where the pointer was; a press and release moving under 6 pt clicks; leaving ends it). The replay clock is exactly
/// `OceanClock.step` a tick, never the file's `t`. The wind is sampled at the points the sketch's `windPoints` makes,
/// derived here from the viewport and the documented fractions, the stir pass's ends, and the pointer if it is on the
/// meadow; the file's rounded points must agree with them.
private func replaySketchFixture() throws {
    guard let d = fixture("air-flowers") else { throw CheckFailure(detail: "fixture missing") }
    try expect(num(d["fixture"]) == 2, "fixture format \(d["fixture"] ?? "none"), want 2")
    try expect(d["scenario"] as? String == "air-flowers", "scenario \(d["scenario"] ?? "none")")
    try expect(d["problems"] == nil, "the fixture has problems: \(d["problems"] ?? "")")
    let step = d["step"] as? [String: Any] ?? [:]
    try expect(step["rate"] as? Int == 60, "the clock's rate is \(step["rate"] ?? "none"), want the integer 60")
    try expect(meadowStep == OceanClock.step, "the replay's tick isn't the family clock's")
    let view = d["viewport"] as? [String: Any] ?? [:]
    let cell = view["cell"] as? [String: Any] ?? [:]
    let W = num(view["width"]), H = num(view["height"]), cw = num(cell["w"])
    let seed = MeadowRandom.seed(num(d["seed"]))
    let settings = d["settings"] as? [String: Any] ?? [:]
    var t = MeadowTuning()
    t.breeze = num(settings["breeze"])
    t.downwash = num(settings["downwash"])
    t.nod = num(settings["nod"])
    t.density = num(settings["density"])
    t.flowerSize = num(settings["flowerSize"])
    t.leaves = num(settings["leaves"])
    guard let clickLimit = integer(settings["clickLimit"]) else {
        throw CheckFailure(detail: "the fixture's clickLimit \(settings["clickLimit"] ?? "none") isn't an integer")
    }
    t.clickLimit = clickLimit
    try expect(t.sanitized() == t, "the fixture's settings are out of range: \(t)")
    try expect(num(settings["timeScale"]) == 1, "the fixture runs at a time scale of \(num(settings["timeScale"]))")
    let rig = MeadowRig(Terrain.single(width: W, height: H), cell: cw, seed: seed, tuning: t)

    let trace = d["trace"] as? [[String: Any]] ?? []
    let samples = d["samples"] as? [[String: Any]] ?? []
    let ticks = samples.map { integer($0["tick"]) }
    try expect(ticks == fixtureTicks.map { Optional($0) }, "sample ticks \(ticks), want \(fixtureTicks)")
    let last = fixtureTicks[fixtureTicks.count - 1]
    try expect(step["ticks"] as? Int == last, "the declared last tick \(step["ticks"] ?? "none"), want \(last)")
    try expect(!trace.isEmpty, "no trace")
    // Every event's tick an integer, in order, before the last tick.
    var previous = 0
    for (i, e) in trace.enumerated() {
        guard let tick = integer(e["tick"]), tick >= previous && tick < last else {
            throw CheckFailure(detail: "trace event \(i): tick \(e["tick"] ?? "none") isn't an integer in order below \(last)")
        }
        previous = tick
    }
    // The trace's places, derived as the sketch does (html:2909–2918) and checked against the file's points.
    let points = d["points"] as? [String: Any] ?? [:]
    let stirA = SIMD2(0.3 * W, 0.75 * H), stirB = SIMD2(0.7 * W, 0.75 * H)
    let hold = SIMD2(0.5 * W, 0.6 * H)
    var ground = SIMD2(0.5 * W, 0.5 * H)
    var room = -1e9
    for i in 0...20 {
        for j in 0...12 {
            let x: Double = (0.15 + 0.7 * Double(i) / 20) * W
            let y: Double = (0.15 + 0.7 * Double(j) / 12) * H
            var dd = 1e9
            for f in rig.flowers.all { dd = min(dd, ((f.x - x) * (f.x - x) + (f.y - y) * (f.y - y)).squareRoot() - f.radius) }
            if dd > room { room = dd; ground = SIMD2(x, y) }
        }
    }
    var bloom: Flower? = nil
    var bd = 1e9
    for f in rig.flowers.all where !f.fading && !f.clicked {
        let dd: Double = ((f.x - W / 2) * (f.x - W / 2) + (f.y - H / 2) * (f.y - H / 2)).squareRoot()
        if dd < bd { bd = dd; bloom = f }
    }
    func near(_ a: Any?, _ p: SIMD2<Double>, _ what: String) throws {
        let v = a as? [Any] ?? []
        try expect(v.count >= 2 && abs(num(v[0]) - p.x) <= 1e-6 && abs(num(v[1]) - p.y) <= 1e-6, "\(what): \(v) vs \(p)")
    }
    try near(points["ground"], ground, "the open ground")
    try near(points["hold"], hold, "the hold")
    let stirPts = points["stir"] as? [Any] ?? []
    try expect(stirPts.count == 2, "stir points \(stirPts)")
    try near(stirPts.first, stirA, "the stir pass's start")
    try near(stirPts.last, stirB, "the stir pass's end")
    let bloomRow = points["bloom"] as? [Any] ?? []
    try expect(bloom != nil && bloomRow.count == 3 && integer(bloomRow[2]) == bloom?.id,
               "the bloom: \(bloomRow) vs \(String(describing: bloom?.id))")
    if let b = bloom { try near(bloomRow, SIMD2(b.x, b.y), "the bloom's place") }
    // The sketch's pointer handlers, as far as the air and the flowers see them (html:2684–2710).
    var has = false, down = false
    var moved = 0.0, px = 0.0, py = 0.0
    func send(_ e: [String: Any]) {
        let x = num(e["x"]), y = num(e["y"])
        switch e["type"] as? String ?? "" {
        case "move":
            if has { moved += ((x - px) * (x - px) + (y - py) * (y - py)).squareRoot() }
            px = x
            py = y
            has = true
            rig.breeze.pointerMoved(x: x, y: y)
        case "down":
            down = true
            moved = 0
        case "up":
            if down && moved < 6 { rig.flowers.click(x: x, y: y, rng: rig.input) }
            down = false
        case "leave":
            down = false
            has = false
            rig.breeze.pointerLeft()
        default:
            break
        }
    }
    // `windPoints` (html:2938–2944): a 4 × 3 grid at x 1/8, 3/8, 5/8, 7/8 and y 1/6, 1/2, 5/6, the stir pass's start,
    // middle and end, then the pointer if it is on the meadow.
    func windPoints() -> [SIMD2<Double>] {
        var pts: [SIMD2<Double>] = []
        let fys: [Double] = [1.0 / 6, 1.0 / 2, 5.0 / 6]
        let fxs: [Double] = [1.0 / 8, 3.0 / 8, 5.0 / 8, 7.0 / 8]
        for fy in fys { for fx in fxs { pts.append(SIMD2(fx * W, fy * H)) } }
        pts.append(stirA)
        pts.append(SIMD2((stirA.x + stirB.x) / 2, stirA.y))
        pts.append(stirB)
        if has { pts.append(SIMD2(px, py)) }
        return pts
    }
    var ev = 0
    var sampled = 0
    var rows = 0
    for tick in 0...last {
        if let s = samples.first(where: { integer($0["tick"]) == tick }) {
            rows += try expectSample(s, rig, tick: tick, points: windPoints())
            sampled += 1
        }
        if tick == last { break }
        while ev < trace.count && integer(trace[ev]["tick"]) == tick {
            send(trace[ev])
            ev += 1
        }
        rig.step()
    }
    try expect(sampled == samples.count && ev == trace.count, "replayed \(sampled) samples, \(ev) events")
    try expect(rig.breeze.steps == last, "stepped \(rig.breeze.steps) ticks, want \(last)")
    print(String(format: "  air-flowers: %d samples, %d wind rows, %d events; worst air %.1e pt/s, worst head %.1e pt", sampled,
                 rows, ev, replayWorst.air, replayWorst.head))
}

/// The largest differences a fixture replay met (air, head), for the record.
nonisolated(unsafe) private var replayWorst = (air: 0.0, head: 0.0)

/// One sample of the fixture against the replay; returns the wind rows compared.
private func expectSample(_ s: [String: Any], _ rig: MeadowRig, tick: Int, points: [SIMD2<Double>]) throws -> Int {
    let at = "tick \(tick)"
    try expectClose(rig.breeze.time, Double(tick) * OceanClock.step, tol: 1e-12, "\(at): clock")
    try expectClose(rig.breeze.time, num(s["t"]), tol: 1e-6, "\(at): the file's clock")
    let wind = s["wind"] as? [[String: Any]] ?? []
    try expect(wind.count == points.count, "\(at): \(wind.count) wind rows, want \(points.count)")
    for (w, p) in zip(wind, points) {
        try expect(abs(num(w["x"]) - p.x) <= 1e-6 && abs(num(w["y"]) - p.y) <= 1e-6, "\(at): wind row at (\(num(w["x"])), \(num(w["y"]))), want \(p)")
        let a = rig.breeze.sample(p.x, p.y)
        let all = w["all"] as? [Any] ?? [], landed = w["landed"] as? [Any] ?? [], stir = w["stir"] as? [Any] ?? []
        try expect(all.count == 2 && landed.count == 2 && stir.count == 2, "\(at): a wind row lacks a vector")
        let pairs: [(String, Double, Double)] = [
            ("all.x", a.x, num(all[0])), ("all.y", a.y, num(all[1])),
            ("landed.x", a.landedX, num(landed[0])), ("landed.y", a.landedY, num(landed[1])),
            ("stir.x", a.pointerX, num(stir[0])), ("stir.y", a.pointerY, num(stir[1])),
        ]
        for (name, got, want) in pairs {
            replayWorst.air = max(replayWorst.air, abs(got - want))
            try expect(abs(got - want) <= 1e-3, "\(at) air at \(p) \(name): \(got) vs \(want)")
        }
    }
    let rows = s["flowers"] as? [[String: Any]] ?? []
    try expect(rows.count == rig.flowers.all.count, "\(at): \(rig.flowers.all.count) flowers vs \(rows.count)")
    for (row, f) in zip(rows, rig.flowers.all) {
        let head = row["head"] as? [Any] ?? []
        try expect(f.id == integer(row["id"]) && f.kind.name == (row["kind"] as? String ?? ""),
                   "\(at): flower \(f.id) \(f.kind.name) vs \(num(row["id"])) \(row["kind"] ?? "")")
        let pairs: [(String, Double, Double, Double)] = [
            ("x", f.x, num(row["x"]), 1e-5), ("y", f.y, num(row["y"]), 1e-5), ("r", f.radius, num(row["r"]), 1e-5),
            ("head.x", f.ox, num(head.first), 1e-3), ("head.y", f.oy, num(head.last), 1e-3), ("age", f.age, num(row["age"]), 1e-5),
        ]
        for (name, got, want, tol) in pairs {
            if name.hasPrefix("head") { replayWorst.head = max(replayWorst.head, abs(got - want)) }
            try expect(abs(got - want) <= tol, "\(at) flower \(f.id) \(name): \(got) vs \(want)")
        }
    }
    try expect(s["butterflies"] is [Any] && (s["butterflies"] as? [Any] ?? [1]).isEmpty, "\(at): the air-flowers fixture has butterflies")
    return wind.count
}
