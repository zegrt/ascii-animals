import CoreGraphics
import Foundation
import OceanKit

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
        if sketchPointer { breeze.setPathLag(0) }
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
    try expect(rig.flowers.sparks.count == Int(num(clicks["dust"])),
               "pollen sparks \(rig.flowers.sparks.count) vs the sketch's dust \(num(clicks["dust"]))")

    rig.step(120)
    let t180 = d["t180"] as? [String: Any] ?? [:]
    try expectClose(rig.breeze.time, num(t180["t"]), tol: 1e-9, "time")
    for row in t180["air"] as? [[Any]] ?? [] { try expectAir(row, rig.breeze, "t180", tol: 1e-3) }
    let end = t180["flowers"] as? [[Any]] ?? []
    try expect(end.count == rig.flowers.all.count, "at the end \(rig.flowers.all.count) vs \(end.count)")
    for (row, f) in zip(end, rig.flowers.all) { try expectFlower(row, f, "t180", tol: 1e-3) }
}

// ── the pointer at different input rates ──

/// A gesture over 2 s: a sweep across with a swing, 300–900 pt/s.
private func gesture(_ t: Double) -> SIMD2<Double> {
    let x: Double = 400 + 300 * t + 150 * sin(3 * t)
    let y: Double = 450 + 200 * sin(2.2 * t)
    return SIMD2(x, y)
}

/// The pointer's stir field (px, py at a grid of points, every 0.25 s for 3 s) when the gesture's samples, taken at
/// `rate` Hz, arrive as `delivery` says: the step before which sample e (taken at t) is delivered, the first
/// possible being `ceil(60 t) + 1`. Each carries the time it was taken, unless `stamped` is off (then it is taken
/// to be as old as its arrival), and `sketchRule` plays it back with no lag.
private func stirTrace(rate: Double, stamped: Bool = true, sketchRule: Bool = false,
                       delivery: (Int, Double) -> Int) -> [Double] {
    let terrain = Terrain.single(width: 1600, height: 1000)
    let breeze = Breeze(terrain: terrain, cell: CGSize(width: 13, height: 19))
    if sketchRule { breeze.setPathLag(0) }
    var samples: [(step: Int, t: Double, p: SIMD2<Double>)] = []
    var e = 0
    while Double(e) / rate <= 2 + 1e-9 {
        let t: Double = Double(e) / rate
        samples.append((delivery(e, t), t, gesture(t)))
        e += 1
    }
    var out: [Double] = []
    var next = 0
    for k in 1...180 {
        while next < samples.count && samples[next].step <= k {
            let s = samples[next]
            breeze.pointerMoved(x: s.p.x, y: s.p.y, at: stamped ? s.t : nil)
            next += 1
        }
        breeze.step(meadowStep)
        if k % 15 == 0 {
            var y = 150.0
            while y <= 850 {
                var x = 200.0
                while x <= 1400 {
                    let a = breeze.sample(x, y)
                    out.append(a.pointerX)
                    out.append(a.pointerY)
                    x += 50
                }
                y += 50
            }
        }
    }
    return out
}

/// The largest relative difference between two traces, time by time (L2 over the grid).
private func worstDifference(_ a: [Double], _ ref: [Double]) -> Double {
    let per = ref.count / 12
    var worst = 0.0
    for t in 0..<12 {
        var dd = 0.0, rr = 0.0
        for i in (t * per)..<((t + 1) * per) {
            let d: Double = a[i] - ref[i]
            dd += d * d
            rr += ref[i] * ref[i]
        }
        if rr > 1 { worst = max(worst, (dd / rr).squareRoot()) }
    }
    return worst
}

func meadowChecks() {
    check("meadowMathMatchesSketch") {
        // Golden values made by the sketch's own functions (html:140–177) under node.
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

    check("meadowReplaysTheSketchProbe") {
        try replayProbe("meadow-probe-1600x913")
        try replayProbe("meadow-probe-1280x713")
    }

    check("meadowSameSeedSameMeadow") {
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

    check("meadowStirHalfLifeAndLocal") {
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
        for (dx, dy) in [(reach + 1, 0.0), (0, reach + 1), (-reach - 1, 0), (reach, reach)] {
            let a = rig.breeze.sample(800 + dx, 500 + dy)
            try expect(a.pointerX == 0 && a.pointerY == 0, "stir reached (\(dx), \(dy)): \(a.pointerX)")
        }
        try expect(rig.breeze.sample(800 + 2 * rig.breeze.spacing, 500).pointerX > 0, "stir didn't spread at all")
    }

    check("meadowStirSameAtEveryInputRate") {
        // Delivered as soon as it can be: before the first step after it was taken.
        let first = { (t: Double) -> Int in Int((t * 60 - 1e-9).rounded(.up)) + 1 }
        // The reference: 60 Hz, one sample a step.
        let ref = stirTrace(rate: 60) { _, t in first(t) }
        func regular(_ rate: Double) -> [Double] { stirTrace(rate: rate) { _, t in first(t) } }
        var worst: [String: Double] = [:]
        for rate in [15.0, 30, 120] { worst["\(Int(rate)) Hz"] = worstDifference(regular(rate), ref) }
        // Bursts: 60 Hz samples held and delivered four at a time; 120 Hz samples six at a time.
        worst["60 Hz in fours"] = worstDifference(stirTrace(rate: 60) { e, _ in (e / 4 + 1) * 4 + 1 }, ref)
        worst["120 Hz in sixes"] = worstDifference(stirTrace(rate: 120) { e, _ in (e / 6 + 1) * 3 + 1 }, ref)
        // Irregular: each 60 Hz or 30 Hz sample late by 0–3 steps, in order.
        func jittered(_ rate: Double) -> [Double] {
            var last = 0
            return stirTrace(rate: rate) { e, t in
                let late = Int(MeadowMath.hash3(Double(e), 5, 7) * 4)
                last = max(last, first(t) + late)
                return last
            }
        }
        worst["60 Hz jittered"] = worstDifference(jittered(60), ref)
        worst["30 Hz jittered"] = worstDifference(jittered(30), ref)
        let text = worst.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.1f", $0.value * 100)) %" }
        print("  stir vs 60 Hz: " + text.joined(separator: ", "))
        // For the record (not held): the sketch's own rule, and moves taken as old as their arrival.
        let sketch60 = stirTrace(rate: 60, sketchRule: true) { _, t in first(t) }
        let sketch30 = worstDifference(stirTrace(rate: 30, sketchRule: true) { _, t in first(t) }, sketch60)
        let sketch15 = worstDifference(stirTrace(rate: 15, sketchRule: true) { _, t in first(t) }, sketch60)
        let unstamped = worstDifference(stirTrace(rate: 60, stamped: false) { e, _ in (e / 4 + 1) * 4 + 1 }, ref)
        print("  (the sketch's rule: 30 Hz \(String(format: "%.1f", sketch30 * 100)) %, 15 Hz \(String(format: "%.1f", sketch15 * 100)) %;"
              + " unstamped fours \(String(format: "%.1f", unstamped * 100)) %)")
        for (k, v) in worst { try expect(v <= 0.05, "\(k): the air differs by \(v * 100) % (limit 5 %)") }
        // Every rate keeps the whole way: two steps' worth arriving at once stirs as much as two steps.
        let sum = { (t: [Double]) -> Double in t.reduce(0) { $0 + abs($1) } }
        try expect(abs(sum(regular(30)) / sum(ref) - 1) < 0.05, "30 Hz lost air: \(sum(regular(30)) / sum(ref))")
    }

    check("meadowDownwashOnlyUnderLowButterflies") {
        let rig = MeadowRig(Terrain.single(width: 1200, height: 800), cell: 13, seed: 3, plant: false)
        func washAt() -> Double {
            var m = 0.0
            for r in 0..<rig.breeze.rows { for c in 0..<rig.breeze.columns { m = max(m, abs(rig.breeze.washSample(c, r).x)) } }
            return m
        }
        let span: Double = 22 * 13 * 0.6
        for z in [0.35, 0.5, 0.9, 1.0] { rig.breeze.downstroke(x: 600, y: 400, z: z, sinStroke: 1, span: span, dt: meadowStep) }
        try expect(washAt() == 0, "downwash from z ≥ 0.35: \(washAt())")
        rig.breeze.downstroke(x: 600, y: 400, z: 0.1, sinStroke: -0.5, span: span, dt: meadowStep)
        try expect(washAt() == 0, "downwash on the upstroke")
        rig.breeze.downstroke(x: 600, y: 400, z: 0.34, sinStroke: 1, span: span, dt: meadowStep)
        let weak = washAt()
        rig.breeze.downstroke(x: 600, y: 400, z: 0.0, sinStroke: 1, span: span, dt: meadowStep)
        let strong: Double = washAt() - weak
        try expect(weak > 0 && strong > weak * 10, "low butterflies wash more: \(weak) at 0.34, \(strong) at 0")
        // Outward from the butterfly: to its right the air moves right.
        let right = rig.breeze.sample(600 + 60, 400)
        let left = rig.breeze.sample(600 - 60, 400)
        try expect(right.x - right.landedX > 0 && left.x - left.landedX < 0, "downwash not outward")
        try expect(right.landedX == rig.breeze.sample(600 + 60, 400).landedX && right.pointerX == 0,
                   "downwash counted in the landed air or the pointer's")
    }

    check("meadowWindPeaksAtTheSketchSpeed") {
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

    check("meadowNoFlowerInAGap") {
        // Offset screens (a strip beside the shorter one), a gap between two, and a laptop under a monitor.
        let layouts: [[CGRect]] = [
            [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1080)],
            [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1500, y: 100, width: 1280, height: 800)],
            [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1800, height: 1169)],
        ]
        for (li, rects) in layouts.enumerated() {
            let terrain = Terrain(rects: rects)
            let b = terrain.bounds
            for seed in Int32(1)...Int32(24) {
                let rig = MeadowRig(terrain, cell: 13, seed: seed, tuning: { var t = MeadowTuning(); t.density = 3; return t }())
                for f in rig.flowers.all {
                    let inBounds = Double(b.minX) <= f.x && f.x <= Double(b.maxX) && Double(b.minY) <= f.y && f.y <= Double(b.maxY)
                    try expect(terrain.contains(SIMD2(f.x, f.y)) || !inBounds,
                               "layout \(li) seed \(seed): flower \(f.id) at (\(f.x), \(f.y)) in a gap")
                    // At most 10 pt past a real edge on either axis (the sketch's per-axis slack).
                    var off = Double.infinity
                    for r in rects {
                        let ox: Double = max(Double(r.minX) - f.x, f.x - Double(r.maxX), 0)
                        let oy: Double = max(Double(r.minY) - f.y, f.y - Double(r.maxY), 0)
                        off = min(off, max(ox, oy))
                    }
                    try expect(off <= MeadowTuning.Flowers.edgeSlack + 1e-9, "layout \(li) seed \(seed): flower \(off) pt off")
                }
            }
        }
    }

    check("meadowNoOverlapAndPatchesFollowArea") {
        for (w, h, density) in [(1440.0, 900.0, 0.85), (2560, 1440, 0.85), (2560, 1440, 2.5), (800, 500, 0.2), (3000, 300, 1)] {
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

    check("meadowHeadSpringRings") {
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

    check("meadowClicksTouchNeverStack") {
        let rig = MeadowRig(Terrain.single(width: 1600, height: 1000), cell: 13, seed: 31)
        rig.step(30)
        // An open spot: far from every flower.
        var spot = SIMD2<Double>(0, 0)
        var best = -1.0
        for y in stride(from: 60.0, to: 940, by: 20) {
            for x in stride(from: 60.0, to: 1540, by: 20) {
                var d = 1e9
                for f in rig.flowers.all { d = min(d, ((f.x - x) * (f.x - x) + (f.y - y) * (f.y - y)).squareRoot() - f.radius) }
                if d > best { best = d; spot = SIMD2(x, y) }
            }
        }
        let before = rig.flowers.all.count
        var blooms = 0, touches = 0
        var kinds: [String] = []
        for _ in 0..<30 {
            switch rig.flowers.click(x: spot.x, y: spot.y, rng: rig.input) {
            case .bloomed: blooms += 1; kinds.append("bloom")
            case .touched: touches += 1; kinds.append("touch")
            case .ignored: kinds.append("ignored")
            }
            rig.step(6)
        }
        try expect(blooms == 1 && touches == 29, "30 clicks on one spot: \(blooms) blooms, \(touches) touches")
        try expect(rig.flowers.all.count == before + 1, "flowers \(before) -> \(rig.flowers.all.count)")
        // A touch nods the head and stays inside 0.45 R however fast the clicks.
        for f in rig.flowers.all {
            try expect((f.ox * f.ox + f.oy * f.oy).squareRoot() <= 0.45 * f.radius + 1e-9, "a touched head swung too far")
        }
        // A click off the meadow does nothing.
        try expect(rig.flowers.click(x: -50, y: 300, rng: rig.input) == .ignored, "a click off the meadow counted")
    }

    check("meadowClickLimitAndFade") {
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

    check("meadowRelayoutFadesClickedOffScreen") {
        // A small resize (under the sketch's 80 pt) leaves a clicked flower off the screen: it fades all the same.
        let rig = MeadowRig(Terrain.single(width: 1600, height: 1000), cell: 13, seed: 51,
                            tuning: { var t = MeadowTuning(); t.density = 0.2; return t }())
        var id = 0
        for x in stride(from: 1590.0, to: 1500, by: -10) {
            if case .bloomed(let i, _) = rig.flowers.click(x: x, y: 500, rng: rig.input) { id = i; break }
        }
        try expect(id > 0, "no bloom near the right edge")
        let x = rig.flowers.flower(id: id)?.x ?? 0
        var gone: [Int] = []
        rig.flowers.onClosing = { gone.append($0) }
        rig.flowers.relayout(terrain: Terrain.single(width: x - 30, height: 1000), cell: CGSize(width: 13, height: 19), rng: rig.input)
        try expect(rig.flowers.flower(id: id)?.fading == true && gone.contains(id), "clicked flower off screen not fading")
        rig.step(121)
        try expect(rig.flowers.flower(id: id) == nil, "it didn't go")
        // A big change replants: planted flowers new, every centre where a bloom may stand.
        rig.flowers.relayout(terrain: Terrain(rects: [CGRect(x: 0, y: 0, width: 1000, height: 700),
                                                      CGRect(x: 1000, y: 200, width: 900, height: 600)]),
                             cell: CGSize(width: 12, height: 17), rng: rig.input)
        for f in rig.flowers.all where !f.fading {
            try expect(rig.flowers.mayStand(f.x, f.y), "after the replant a flower stands at (\(f.x), \(f.y))")
        }
    }

    check("meadowFiniteOnBadInput") {
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
            for p in [(0.0, 0.0), (700, 400), (1e9, 1e9)] {
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
            for cell in [13.0, 0, -5, .nan] {
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
    }

    check("meadowStepAllocatesNothing") {
        let terrain = Terrain(rects: [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 2560, height: 1440)])
        let rig = MeadowRig(terrain, cell: 13, seed: 71)
        _ = rig.flowers.click(x: 700, y: 500, rng: rig.input)
        rig.step(120)
        var k = 0
        let n = allocations {
            for _ in 0..<600 {
                let t: Double = Double(k) / 60
                rig.breeze.pointerMoved(x: 1500 + 900 * sin(t), y: 600 + 400 * cos(1.7 * t))
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

    check("meadowReplaysTheSketchFixture") {
        guard fixture("air-flowers") != nil else {
            throw CheckFailure(detail: "Fixtures/air-flowers.json (the sketch's fix round 2) has not landed yet")
        }
        try replaySketchFixture()
    }
}

/// The sketch's own replay fixture (fix round 2). Filled in when its format is known.
private func replaySketchFixture() throws {
    throw CheckFailure(detail: "the fixture's replay is not written yet")
}
