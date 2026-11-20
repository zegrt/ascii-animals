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

    init(_ terrain: Terrain, cell: Double, seed: Int32, tuning: MeadowTuning = .director, plant: Bool = true,
         sketchPointer: Bool = false) {
        let size = CGSize(width: cell, height: (cell * 1.45).rounded())
        breeze = Breeze(terrain: terrain, cell: size, tuning: tuning)
        if sketchPointer { breeze.setPlayback(.sketch) }
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
private let countingLogger: MallocLogger = { type, _, _, _, _, _ in
    if type & 2 != 0 { mallocCounter().pointee += 1 }
}

/// Heap allocations `body` makes, or nil where the allocator can't be watched.
private func allocations(_ body: () -> Void) -> Int? {
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

/// A sketch flower row `[id, kind, x, y, R, rot, seed, n, f0, leaves, florets, ox, oy, age, clicked, fade]` against
/// a Swift flower.
private func expectFlower(_ row: [Any], _ f: Flower, _ at: String, tol: Double) throws {
    let id = Int(num(row[0]))
    try expect(f.id == id, "\(at): id \(f.id) vs \(id)")
    try expect(f.kind.name == (row[1] as? String ?? ""), "\(at) id \(id): kind \(f.kind.name) vs \(row[1])")
    try expect(f.seed == Int(num(row[6])) && f.petals == Int(num(row[7])), "\(at) id \(id): seed/petals")
    try expect(f.leaves.count == Int(num(row[9])) && f.florets.count == Int(num(row[10])), "\(at) id \(id): leaves/florets")
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
                   && abs(l.width - num(v[2])) <= 1e-5 && l.kind == Int(num(v[3])), "\(at) id \(f.id): leaf \(l) vs \(v)")
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
        try expect(row.count == 3 && Int(num(row[0])) == f.id, "\(at): geometry row for \(row.first ?? "none"), flower \(f.id)")
        try expectGeometry(row[1] as? [Any] ?? [], row[2] as? [Any] ?? [], f, at)
    }
}

/// The m1 probe of the sketch (Fixtures/README.md), replayed.
private func replayProbe(_ name: String) throws {
    guard let d = fixture(name) else { throw CheckFailure(detail: "fixture \(name).json missing") }
    let W = num(d["W"]), H = num(d["H"]), S = num(d["S"])
    let terrain = Terrain.single(width: W, height: H)
    let rig = MeadowRig(terrain, cell: S * 13, seed: 4242, sketchPointer: true)
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
    try expect(rig.flowers.sparks.count == Int(num(clicks["dust"])),
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
        try expect(row.count == 10 && Int(num(row[0])) == f.id && (row[1] as? String) == kind.name, "\(at): id \(f.id) vs \(row.first ?? "none")")
        try expect(f.seed == Int(num(row[4])) && f.petals == Int(num(row[5])), "\(at): seed \(f.seed), petals \(f.petals), R \(f.radius) vs \(row.prefix(8))")
        let pairs: [(String, Double, Double)] = [("R", f.radius, num(row[2])), ("rot", f.turn, num(row[3])),
                                                 ("f0", f.f0, num(row[6])), ("reach", f.reach, num(row[7]))]
        for (n, got, want) in pairs { try expect(abs(got - want) <= 1e-5, "\(at): \(n) \(got) vs \(want)") }
        try expectGeometry(row[8] as? [Any] ?? [], row[9] as? [Any] ?? [], f, at)
    }
}

// ── the pointer at different input rates ──

/// A gesture over 2 s: a sweep across with a swing, 300–900 pt/s.
private func gesture(_ t: Double) -> SIMD2<Double> {
    let x: Double = 400 + 300 * t + 150 * sin(3 * t)
    let y: Double = 450 + 200 * sin(2.2 * t)
    return SIMD2(x, y)
}

/// The review's straight sweep: 540 pt/s across the middle.
private func sweep(_ t: Double) -> SIMD2<Double> {
    let x: Double = 300 + 540 * t
    return SIMD2(x, 500)
}

/// One pointer sample: taken at `t` (s) at `p`, delivered before step `step` (the first possible being
/// `ceil(60 t) + 1`), or a leave (`p` nil) delivered then.
private struct PointerSample {
    var step: Int
    var t: Double
    var p: SIMD2<Double>?
}

/// The step before which a sample taken at `t` can first be delivered.
private func firstStep(_ t: Double) -> Int { Int((t * 60 - 1e-9).rounded(.up)) + 1 }

/// How a rate's samples arrive.
private enum Delivery: CaseIterable {
    /// Each as soon as it can be.
    case regular
    /// Two at a time: each with the one after it (the older arrives a sample interval late).
    case paired
    /// Each 0–3 steps late (in order), by a fixed hash.
    case jittered

    var name: String { String(describing: self) }
}

/// A path's samples at `rate` Hz for `seconds`, delivered as `delivery` says.
private func samples(_ path: (Double) -> SIMD2<Double>, rate: Double, seconds: Double = 2,
                     delivery: Delivery) -> [PointerSample] {
    var out: [PointerSample] = []
    var e = 0
    while Double(e) / rate <= seconds + 1e-9 {
        let t: Double = Double(e) / rate
        out.append(PointerSample(step: firstStep(t), t: t, p: path(t)))
        e += 1
    }
    switch delivery {
    case .regular:
        break
    case .paired:
        for i in stride(from: 0, to: out.count - 1, by: 2) { out[i].step = out[i + 1].step }
    case .jittered:
        var last = 0
        for i in out.indices {
            let late = Int(MeadowMath.hash3(Double(i), 5, 7) * 4)
            last = max(last, out[i].step + late)
            out[i].step = last
        }
    }
    return out
}

/// The pointer's stir field (px, py on a 25 × 15 grid of points) after every step for `steps` steps, the samples fed
/// as they arrive, with their own times (or as old as their arrival when `stamped` is off).
private func stirTrace(_ feed: [PointerSample], playback: PointerPlayback, stamped: Bool = true,
                       steps: Int = 180) -> [[Double]] {
    let breeze = Breeze(terrain: Terrain.single(width: 1600, height: 1000), cell: CGSize(width: 13, height: 19))
    breeze.setPlayback(playback)
    var out: [[Double]] = []
    out.reserveCapacity(steps)
    var next = 0
    for k in 1...steps {
        while next < feed.count && feed[next].step <= k {
            let s = feed[next]
            if let p = s.p {
                breeze.pointerMoved(x: p.x, y: p.y, at: stamped ? s.t : nil)
            } else {
                breeze.pointerLeft()
            }
            next += 1
        }
        breeze.step(meadowStep)
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
        out.append(field)
    }
    return out
}

/// The largest relative difference (L2 over the grid) between two traces: at every step (`every` 1) or every
/// `every` steps, wherever the reference has air.
private func worstDifference(_ a: [[Double]], _ ref: [[Double]], every: Int = 1) -> Double {
    var worst = 0.0
    for t in stride(from: every - 1, to: min(a.count, ref.count), by: every) {
        var dd = 0.0, rr = 0.0
        for i in ref[t].indices {
            let d: Double = a[t][i] - ref[t][i]
            dd += d * d
            rr += ref[t][i] * ref[t][i]
        }
        if rr > 1 { worst = max(worst, (dd / rr).squareRoot()) }
    }
    return worst
}

/// The input-rate matrix at a lag: every rate and delivery of both paths against the same path at 60 Hz delivered
/// regularly, measured at every step. Returns each case's worst difference.
private func inputMatrix(lag: Double) -> [(String, Double)] {
    let play = PointerPlayback.played(lag: lag)
    var out: [(String, Double)] = []
    let paths: [(String, (Double) -> SIMD2<Double>)] = [("gesture", gesture), ("sweep", sweep)]
    for (name, path) in paths {
        let ref = stirTrace(samples(path, rate: 60, delivery: .regular), playback: play)
        for rate in [15.0, 30, 60, 120] {
            for d in Delivery.allCases where !(rate == 60 && d == .regular) {
                let v = stirTrace(samples(path, rate: rate, delivery: d), playback: play)
                out.append(("\(name) \(Int(rate)) Hz \(d.name)", worstDifference(v, ref)))
            }
        }
    }
    return out
}

func meadowChecks() {
    check("meadowMathMatchesSketch", meadowMathMatchesSketch)
    check("meadowReplaysTheSketchProbe", meadowReplaysTheSketchProbe)
    check("meadowSameSeedSameMeadow", meadowSameSeedSameMeadow)
    check("meadowStirHalfLifeAndLocal", meadowStirHalfLifeAndLocal)
    check("meadowStirSameAtEveryInputRate", meadowStirSameAtEveryInputRate)
    check("meadowStirAcrossReentry", meadowStirAcrossReentry)
    check("meadowStirLateBeyondTheLag", meadowStirLateBeyondTheLag)
    check("meadowStirThroughTheHostClock", meadowStirThroughTheHostClock)
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

private func meadowStirSameAtEveryInputRate() throws {
    let lag = MeadowTuning.Stir.pathLag
    let play = PointerPlayback.played(lag: lag)
    // The matrix at the port's lag: 15, 30, 60 and 120 Hz, regular, paired and jittered, two paths, every step.
    let matrix = inputMatrix(lag: lag)
    let worst = matrix.max { $0.1 < $1.1 } ?? ("none", 0)
    print("  at the lag \(String(format: "%.3f", lag)) s, worst of \(matrix.count) cases \(pct(worst.1)) (\(worst.0))")
    for (k, v) in matrix { try expect(v <= 0.05, "\(k): the air differs by \(pct(v)) (limit 5 %)") }
    // Bursts beyond pairs: 60 Hz in fours, 120 Hz in sixes (each a twentieth of a second or more late).
    let ref = stirTrace(samples(gesture, rate: 60, delivery: .regular), playback: play)
    func burst(_ rate: Double, _ n: Int) -> [PointerSample] {
        var f = samples(gesture, rate: rate, delivery: .regular)
        for g in stride(from: 0, to: f.count, by: n) {
            let last = min(f.count, g + n) - 1
            for i in g...last { f[i].step = f[last].step }
        }
        return f
    }
    let fours = worstDifference(stirTrace(burst(60, 4), playback: play), ref)
    let sixes = worstDifference(stirTrace(burst(120, 6), playback: play), ref)
    print("  bursts: 60 Hz in fours \(pct(fours)), 120 Hz in sixes \(pct(sixes))")
    try expect(fours <= 0.05 && sixes <= 0.05, "bursts differ: fours \(pct(fours)), sixes \(pct(sixes))")
    // Every rate keeps the whole way: the total stirred at 30 Hz in pairs is the 60 Hz total.
    let sum = { (t: [[Double]]) -> Double in t.reduce(0) { $0 + $1.reduce(0) { $0 + abs($1) } } }
    let pairs30 = stirTrace(samples(gesture, rate: 30, delivery: .paired), playback: play)
    try expect(abs(sum(pairs30) / sum(ref) - 1) < 0.01, "30 Hz in pairs lost air: \(sum(pairs30) / sum(ref))")
    // The lag is the smallest that passes: a step less fails the matrix (15 Hz pairs need more than 8 steps).
    var sweep: [String] = []
    for k in [5.0, 6, 7, 8] {
        let w = inputMatrix(lag: k / 60).map(\.1).max() ?? 0
        sweep.append("\(Int(k))/60 s \(pct(w))")
        if k == 8 { try expect(w > 0.05, "a lag of 8/60 s passes too (\(pct(w))): the lag isn't the smallest") }
    }
    try expect(lag > 8.0 / 60 && lag < 9.0 / 60, "the lag \(lag) isn't within a step above the 8/60 s that fails")
    print("  smaller lags, worst case: " + sweep.joined(separator: ", "))
    // For the record (not held): the sketch's own rule, and samples taken as old as their arrival.
    let s60 = stirTrace(samples(gesture, rate: 60, delivery: .regular), playback: .sketch)
    let s30 = worstDifference(stirTrace(samples(gesture, rate: 30, delivery: .regular), playback: .sketch), s60, every: 15)
    let s15 = worstDifference(stirTrace(samples(gesture, rate: 15, delivery: .regular), playback: .sketch), s60, every: 15)
    let unstamped = worstDifference(stirTrace(samples(gesture, rate: 15, delivery: .paired), playback: play, stamped: false), ref)
    print("  (the sketch's rule, every 0.25 s: 30 Hz \(pct(s30)), 15 Hz \(pct(s15)); unstamped 15 Hz pairs \(pct(unstamped)))")
}

/// A percentage for the record.
private func pct(_ v: Double) -> String { String(format: "%.1f %%", v * 100) }

/// The pointer leaves and comes back before its way has played out: the way before it left is all stirred, nothing
/// along the jump, and every rate and delivery gives the same air.
private func meadowStirAcrossReentry() throws {
    let play = PointerPlayback.played(lag: MeadowTuning.Stir.pathLag)
    func way(_ rate: Double, _ d: Delivery) -> [PointerSample] {
        let a = samples({ t in SIMD2(300 + 750 * t, 300 + 90 * sin(6 * t)) }, rate: rate, seconds: 0.4, delivery: d)
        let leaveAt: Double = 0.4 + 1e-6
        // Back 0.05 s later, far off: well inside the lag, so the first way is still playing out.
        var b = samples({ t in SIMD2(1200 + 300 * t, 800 - 150 * t + 60 * sin(7 * t)) }, rate: rate, seconds: 0.8,
                        delivery: d)
        for i in b.indices {
            b[i].t += 0.45
            b[i].step = max(b[i].step + firstStep(0.45) - 1, firstStep(leaveAt))
        }
        let last = a.map(\.step).max() ?? 0
        return a + [PointerSample(step: max(last, firstStep(leaveAt)), t: leaveAt, p: nil)] + b
    }
    let ref = stirTrace(way(60, .regular), playback: play, steps: 120)
    var worst = 0.0, name = ""
    for rate in [15.0, 30, 60, 120] {
        for d in Delivery.allCases where !(rate == 60 && d == .regular) {
            let v = worstDifference(stirTrace(way(rate, d), playback: play, steps: 120), ref)
            if v > worst { worst = v; name = "\(Int(rate)) Hz \(d.name)" }
        }
    }
    print("  across a re-entry: worst \(pct(worst)) (\(name))")
    try expect(worst <= 0.05, "across a re-entry the air differs by \(pct(worst)) (\(name))")
    // The way before it left is all stirred: the end of the first way has air after the re-entry.
    let breeze = Breeze(terrain: Terrain.single(width: 1600, height: 1000), cell: CGSize(width: 13, height: 19))
    breeze.setPlayback(play)
    let feed = way(60, .regular)
    var next = 0
    var endAir = 0.0, jumpAir = 0.0
    for k in 1...60 {
        while next < feed.count && feed[next].step <= k {
            if let p = feed[next].p { breeze.pointerMoved(x: p.x, y: p.y, at: feed[next].t) } else { breeze.pointerLeft() }
            next += 1
        }
        breeze.step(meadowStep)
        endAir = max(endAir, abs(breeze.sample(590, 300 + 90 * sin(2.4)).pointerX))
        // Midway along the jump, out of reach of both ways: no air.
        jumpAir = max(jumpAir, abs(breeze.sample(900, 550).pointerX) + abs(breeze.sample(900, 550).pointerY))
    }
    try expect(endAir > 20, "the way before the pointer left wasn't stirred to its end (\(endAir) pt/s)")
    try expect(jumpAir == 0, "the jump back onto the meadow stirred the air (\(jumpAir) pt/s)")
}

/// Input later than the lag: 60 Hz samples held back and delivered in bursts every 0.3 s (up to 0.3 s late, twice
/// the lag). The steps they were due on wait and are played when they arrive, decayed for the wait, so once a burst is
/// in, the air is the on-time air.
private func meadowStirLateBeyondTheLag() throws {
    let play = PointerPlayback.played(lag: MeadowTuning.Stir.pathLag)
    let ref = stirTrace(samples(gesture, rate: 60, delivery: .regular), playback: play)
    var late = samples(gesture, rate: 60, delivery: .regular)
    for i in late.indices { late[i].step = ((late[i].step - 1) / 18 + 1) * 18 + 1 }
    let v = stirTrace(late, playback: play)
    // Compared just after each burst is in (the step a burst arrives before), every steps' place known.
    var worst = 0.0
    for k in stride(from: 18, to: 180, by: 18) {
        worst = max(worst, worstDifference([v[k]], [ref[k]]))
    }
    print("  input up to 0.3 s late, once each burst is in: \(pct(worst))")
    try expect(worst <= 0.05, "input later than the lag gives other air once in: \(pct(worst))")
}

/// The host's side of the input contract: events stamped with their own host times, delivered in frame batches at
/// 30, 60 and 120 Hz frames (even and uneven), through `OceanClock` and `syncInputClock`, at a steady speed and with
/// speed changes, give the same air as the same path at 60 Hz, step for step.
private func meadowStirThroughTheHostClock() throws {
    let h0 = 5000.0
    func run(rate: Double, delivery: Delivery, frameRate: Double, uneven: Bool, speedChanges: Bool) -> [[Double]] {
        let breeze = Breeze(terrain: Terrain.single(width: 1600, height: 1000), cell: CGSize(width: 13, height: 19))
        breeze.setPlayback(.played(lag: MeadowTuning.Stir.pathLag))
        // When each sample reaches the host: as taken, with its partner, or 0–50 ms late (in order).
        var feed: [(due: Double, t: Double, p: SIMD2<Double>)] = []
        var e = 0
        var lastDue = 0.0
        while Double(e) / rate <= 2 {
            let t: Double = Double(e) / rate
            var due = t
            switch delivery {
            case .regular: break
            case .paired: if e % 2 == 0 { due = Double(e + 1) / rate }
            case .jittered: due = t + 0.05 * MeadowMath.hash3(Double(e), 5, 7)
            }
            lastDue = max(lastDue, due)
            feed.append((lastDue, t, gesture(t)))
            e += 1
        }
        var clock = OceanClock()
        var out: [[Double]] = []
        var next = 0
        var ts = h0
        var f = 0
        while out.count < 180 {
            while next < feed.count && h0 + feed[next].due <= ts {
                breeze.pointerMoved(x: feed[next].p.x, y: feed[next].p.y, hostTime: h0 + feed[next].t)
                next += 1
            }
            let real = ts - h0
            let speed: Double = speedChanges ? (real < 1 ? 1 : (real < 2 ? 1.5 : 0.5)) : 1
            let n = clock.advance(to: ts, speed: speed)
            for _ in 0..<n where out.count < 180 {
                breeze.step(OceanClock.step, speed: speed)
                var field: [Double] = []
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
                out.append(field)
            }
            breeze.syncInputClock(hostTime: ts, speed: speed)
            f += 1
            let wobble: Double = uneven ? 0.6 * (MeadowMath.hash3(Double(f), 9, 3) - 0.5) : 0
            ts = h0 + (Double(f) + wobble) / frameRate
        }
        return out
    }
    // The playback, against the same path at 60 Hz through the same frames and speeds.
    var worst = 0.0, name = ""
    for changes in [false, true] {
        for frameRate in [30.0, 60, 120] {
            for uneven in [false, true] {
                let ref = run(rate: 60, delivery: .regular, frameRate: frameRate, uneven: uneven, speedChanges: changes)
                for rate in [15.0, 30, 60, 120] {
                    for d in Delivery.allCases where !(rate == 60 && d == .regular) {
                        let v = worstDifference(run(rate: rate, delivery: d, frameRate: frameRate, uneven: uneven,
                                                    speedChanges: changes), ref)
                        if v > worst {
                            worst = v
                            name = "\(Int(rate)) Hz \(d.name), \(Int(frameRate)) Hz frames\(uneven ? " uneven" : "")\(changes ? ", speed changes" : "")"
                        }
                    }
                }
            }
        }
    }
    // The frames themselves: at a steady speed, every frame rate, even or not, gives the air of even 60 Hz frames.
    // (With speed changes the family clock re-times what it had accumulated, so step n lands up to a step apart in
    // real time on different frames: compared step for step they differ by that, not by the pointer.)
    let even60 = run(rate: 60, delivery: .regular, frameRate: 60, uneven: false, speedChanges: false)
    var frames = 0.0
    for frameRate in [30.0, 60, 120] {
        for uneven in [false, true] {
            frames = max(frames, worstDifference(run(rate: 60, delivery: .jittered, frameRate: frameRate, uneven: uneven,
                                                     speedChanges: false), even60))
        }
    }
    print("  through the host clock, frame rates against even 60 Hz frames: worst \(pct(frames))")
    try expect(frames <= 0.05, "frame rates change the air by \(pct(frames))")
    print("  through the host clock: worst \(pct(worst)) (\(name))")
    try expect(worst <= 0.05, "through the host clock the air differs by \(pct(worst)) (\(name))")
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
/// point of its screen on no other screen (so not across a shared edge, nor round a seam's end).
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
    // A pace that isn't usable: subnormal, zero, negative, huge, NaN. The input clock stays finite and moves by a
    // step's real time at a pace held to 0.05…1.5.
    let paces: [Double] = [Double.leastNonzeroMagnitude, 0, -1, 1e300, .infinity, .nan]
    for v in paces {
        let before = rig.breeze.inputClock
        rig.breeze.step(meadowStep, speed: v)
        let moved: Double = rig.breeze.inputClock - before
        try expect(moved.isFinite && moved > 0 && moved <= meadowStep / 0.05 + 1e-12, "pace \(v): the input clock moved \(moved)")
        try expect(rig.breeze.sample(800, 400).speed.isFinite, "pace \(v): air not finite")
    }
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
    // Only the clock's tick steps: anything else is refused, the clocks and fields unchanged.
    let tick = rig.breeze.time, steps = rig.breeze.steps, clock = rig.breeze.inputClock
    let heads = rig.flowers.all.map { SIMD2($0.ox, $0.oy) }
    let odd: [Double] = [1.0 / 30, 1.0 / 120, 0.1, 1e-300, 1.0 / 60 + 1e-15, -meadowStep, .nan]
    for dt in odd {
        rig.breeze.step(dt)
        rig.flowers.step(dt)
        rig.breeze.downstroke(x: 700, y: 300, z: 0, sinStroke: 1, span: 100, dt: dt)
        rig.breeze.flutter(x: 700, y: 300, sinStroke: 1, span: 100, dt: dt)
    }
    try expect(rig.breeze.time == tick && rig.breeze.steps == steps && rig.breeze.inputClock == clock,
               "a step that isn't the tick was taken")
    try expect(rig.flowers.all.map { SIMD2($0.ox, $0.oy) } == heads, "the flowers stepped at a length that isn't the tick")
    var washed = 0.0
    for r in 0..<rig.breeze.rows { for c in 0..<rig.breeze.columns { washed += simd_length(rig.breeze.washSample(c, r)) } }
    try expect(washed == 0, "a downstroke at a length that isn't the tick washed")
}

private func meadowStepAllocatesNothing() throws {
    let terrain = Terrain(rects: [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 2560, height: 1440)])
    let rig = MeadowRig(terrain, cell: 13, seed: 71)
    _ = rig.flowers.click(x: 700, y: 500, rng: rig.input)
    rig.breeze.syncInputClock(hostTime: 100)
    rig.step(120)
    rig.breeze.syncInputClock(hostTime: 100 + 120.0 / 60)
    var k = 120
    let n = allocations {
        for _ in 0..<600 {
            // Late input: 15 Hz samples in pairs, stamped with host times, so steps wait and are played late; a
            // leave and a re-entry every 2 s.
            if k % 8 == 0 {
                for j in stride(from: -8, through: -4, by: 4) {
                    let te: Double = Double(k + j) / 60
                    rig.breeze.pointerMoved(x: 1500 + 900 * sin(te), y: 600 + 400 * cos(1.7 * te), hostTime: 100 + te)
                }
            }
            if k % 120 == 60 { rig.breeze.pointerLeft() }
            rig.breeze.downstroke(x: 1200, y: 500, z: 0.1, sinStroke: 0.8, span: 170, dt: meadowStep)
            rig.breeze.flutter(x: 1300, y: 520, sinStroke: 0.8, span: 120, dt: meadowStep)
            rig.step()
            _ = rig.breeze.sample(400, 300)
            rig.breeze.syncInputClock(hostTime: 100 + Double(k + 1) / 60)
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
    t.clickLimit = Int(num(settings["clickLimit"]))
    try expect(t.sanitized() == t, "the fixture's settings are out of range: \(t)")
    try expect(num(settings["timeScale"]) == 1, "the fixture runs at a time scale of \(num(settings["timeScale"]))")
    let rig = MeadowRig(Terrain.single(width: W, height: H), cell: cw, seed: seed, tuning: t, sketchPointer: true)

    let trace = d["trace"] as? [[String: Any]] ?? []
    let samples = d["samples"] as? [[String: Any]] ?? []
    let ticks = samples.map { Int(num($0["tick"])) }
    try expect(ticks == fixtureTicks, "sample ticks \(ticks), want \(fixtureTicks)")
    let last = fixtureTicks[fixtureTicks.count - 1]
    try expect(step["ticks"] as? Int == last, "the declared last tick \(step["ticks"] ?? "none"), want \(last)")
    try expect(!trace.isEmpty, "no trace")
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
    try expect(bloom != nil && bloomRow.count == 3 && Int(num(bloomRow[2])) == bloom?.id,
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
        if let s = samples.first(where: { Int(num($0["tick"])) == tick }) {
            rows += try expectSample(s, rig, tick: tick, points: windPoints())
            sampled += 1
        }
        if tick == last { break }
        while ev < trace.count && Int(num(trace[ev]["tick"])) == tick {
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
        try expect(f.id == Int(num(row["id"])) && f.kind.name == (row["kind"] as? String ?? ""),
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
