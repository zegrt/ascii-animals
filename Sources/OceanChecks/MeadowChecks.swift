import CoreGraphics
import Foundation
import OceanKit
import simd

/// The full-size cell (13 × 19 pt), as `GridSpec.cell(forWidth:)` gives a large display.
private let meadowCell = CGSize(width: 13, height: 19)

/// The owner's offset layout: a 2560 × 1440 monitor above a laptop whose top edge touches its bottom.
private let twoScreens = Terrain(rects: [CGRect(x: 0, y: 0, width: 2560, height: 1440),
                                         CGRect(x: 375, y: 1440, width: 1800, height: 1169)])

/// A breeze with the weather off: only what the pointer writes.
private func calmBreeze(_ bounds: CGRect = CGRect(x: 0, y: 0, width: 2560, height: 1440)) -> Breeze {
    let b = Breeze(bounds: bounds, cell: meadowCell)
    b.ambient = false
    return b
}

/// A breeze sample node: one per 4 × 3 cells from the bounds' origin.
private func node(_ i: Int, _ j: Int) -> (Double, Double) {
    (Double(i) * 4 * Double(meadowCell.width), Double(j) * 3 * Double(meadowCell.height))
}

/// Peaks of |x| (local maxima of a sampled oscillation) and the upward zero crossings, interpolated.
private struct Ringing {
    var peaks: [(t: Double, a: Double)] = []
    var crossings: [Double] = []
}

private func ringing(_ xs: [Double], dt: Double) -> Ringing {
    var r = Ringing()
    for k in 1..<(xs.count - 1) {
        let a: Double = abs(xs[k - 1]), b: Double = abs(xs[k]), c: Double = abs(xs[k + 1])
        if b > a && b >= c && b > 1e-6 { r.peaks.append((t: Double(k) * dt, a: b)) }
        if xs[k - 1] < 0 && xs[k] >= 0 {
            let f: Double = -xs[k - 1] / (xs[k] - xs[k - 1])
            r.crossings.append((Double(k - 1) + f) * dt)
        }
    }
    return r
}

func meadowChecks() {
    func breezeHalfLife() throws {
        let b = calmBreeze()
        let (x, y) = node(10, 8)
        b.write(x, y, vx: 100 / 0.6, vy: 0)   // the pointer writes velocity × 0.6: the field holds 100 pt/s
        try expectClose(b.sample(x, y).x, 100, tol: 1e-6, "written")
        let random = WebRandom(seed: 3)
        for _ in 0..<48 { b.step(1.0 / 60.0, random: random) }
        let v: SIMD2<Double> = b.sample(x, y)
        try expectClose(v.x, 50, tol: 5, "after 0.8 s")
        try expect(abs(v.y) < 1e-9, "no sideways wind from a sideways write: \(v.y)")
    }
    check("breezeHalfLife", breezeHalfLife)

    func breezeWriteIsLocal() throws {
        let b = calmBreeze()
        let (x, y) = node(20, 12)
        b.write(x, y, vx: 0, vy: -150)
        let random = WebRandom(seed: 4)
        for frame in 0..<30 {
            let centre: Double = simd_length(b.sample(x, y))
            let sx: Double = 6 * 4 * Double(meadowCell.width), sy: Double = 6 * 3 * Double(meadowCell.height)
            let away: [(Double, Double)] = [(x + sx, y), (x - sx, y), (x, y + sy), (x, y - sy)]
            for (ax, ay) in away {
                let far: Double = simd_length(b.sample(ax, ay))
                try expect(far < 0.05 * centre, "frame \(frame): \(far) six samples from \(centre)")
            }
            b.step(1.0 / 60.0, random: random)
        }
    }
    check("breezeWriteIsLocal", breezeWriteIsLocal)

    func stemsRingAndSettle() throws {
        let land = Meadowland(random: WebRandom(seed: 11))
        land.layout(terrain: .single(width: 2560, height: 1440), cell: meadowCell)
        guard let i = land.flowers.firstIndex(where: { $0.kind.isTall && (4...7).contains($0.rows) }) else {
            throw CheckFailure(detail: "no tall stem of 4–7 rows in the layout")
        }
        let f0: Double = land.flowers[i].f0, zeta: Double = land.flowers[i].zeta
        try expect((0.7...1.2).contains(f0) && (0.08...0.15).contains(zeta), "tall stem f0 \(f0) zeta \(zeta)")
        let breeze = calmBreeze()
        let random = WebRandom(seed: 12)
        land.dip(i, impulse: SIMD2<Double>(40, 0))
        let dt: Double = 1.0 / 60.0
        var xs: [Double] = []
        for _ in 0..<(60 * 12) {
            breeze.step(dt, random: random)
            land.step(dt, breeze: breeze)
            xs.append(land.flowers[i].tip.x)
        }
        let r = ringing(xs, dt: dt)
        try expect(r.crossings.count >= 4 && r.peaks.count >= 6, "rang \(r.crossings.count) crossings, \(r.peaks.count) peaks")
        let n: Int = r.crossings.count - 1
        let period: Double = (r.crossings[n] - r.crossings[0]) / Double(n)
        try expectClose(1 / period, f0, tol: 0.1 * f0, "ring frequency")
        // Envelope: a least-squares line through ln(peak) against time.
        let ps = r.peaks.filter { $0.a > r.peaks[0].a * 0.02 }
        let mt: Double = ps.map { $0.t }.reduce(0, +) / Double(ps.count)
        let ml: Double = ps.map { log($0.a) }.reduce(0, +) / Double(ps.count)
        var num: Double = 0, den: Double = 0
        for p in ps { num += (p.t - mt) * (log(p.a) - ml); den += (p.t - mt) * (p.t - mt) }
        let halfLife: Double = log(2) / -(num / den)
        let want: Double = log(2) / (zeta * TAU * f0)
        try expectClose(halfLife, want, tol: 0.2 * want, "amplitude half-life")
        try expect(abs(xs[xs.count - 1]) < 0.05 * r.peaks[0].a, "settles: \(xs[xs.count - 1]) of \(r.peaks[0].a)")
    }
    check("stemsRingAndSettle", stemsRingAndSettle)

    func flowersOnEveryRectBottom() throws {
        let land = Meadowland(random: WebRandom(seed: 21))
        land.layout(terrain: twoScreens, cell: meadowCell)
        let ch = Double(meadowCell.height), cw = Double(meadowCell.width)
        for (k, f) in land.flowers.enumerated() {
            try expect(f.rect >= 0 && f.rect < twoScreens.rects.count, "flower \(k) rect \(f.rect)")
            let r = twoScreens.rects[f.rect]
            try expectClose(f.base.y, Double(r.maxY), tol: 1e-9, "flower \(k) \(f.kind) base y")
            try expect(f.base.x >= Double(r.minX) && f.base.x <= Double(r.maxX), "flower \(k) x \(f.base.x) outside \(r)")
            try expect(twoScreens.contains(f.base), "flower \(k) in the gap at \(f.base)")
            try expect(f.base.y - Double(f.rows) * ch >= Double(r.minY), "flower \(k) head above its screen")
            try expect(Double(f.rows) * ch <= 0.4 * Double(r.height) + ch, "flower \(k) \(f.rows) rows taller than 40 %")
            try expect(f.bloom == 1 && f.bornAt == -1, "laid-out flower \(k) is open")
        }
        for (i, r) in twoScreens.rects.enumerated() {
            let plants = land.flowers.filter { $0.rect == i && $0.kind != .grass }.count
            let grass = land.flowers.filter { $0.rect == i && $0.kind == .grass }.count
            let cols = Double(r.width) / cw
            try expect(Double(plants) >= cols / 5, "rect \(i): \(plants) plants over \(Int(cols)) columns")
            try expect(grass > 0, "rect \(i): no grass")
            let tall = land.flowers.filter { $0.rect == i && $0.rows > 7 }.count
            try expect((6...14).contains(tall), "rect \(i): \(tall) scattered stems")
        }
        // A click in the gap (below the monitor, left of the laptop) blooms nothing; one on the laptop roots there.
        try expect(land.bloom(atX: 100, y: 1600, terrain: twoScreens, time: 0) == nil, "bloomed in the gap")
        guard let k = land.bloom(atX: 1000, y: 1700, terrain: twoScreens, time: 0) else {
            throw CheckFailure(detail: "no bloom on the laptop")
        }
        let f = land.flowers[k]
        try expect(f.rect == 1 && f.base.y == 2609 && abs(f.base.x - 1000) < cw, "laptop bloom at \(f.base) rect \(f.rect)")
    }
    check("flowersOnEveryRectBottom", flowersOnEveryRectBottom)

    func bloomTimeline() throws {
        let terrain = Terrain.single(width: 2560, height: 1440)
        for seed in UInt64(1)...UInt64(16) {
            let land = Meadowland(random: WebRandom(seed: seed))
            land.layout(terrain: terrain, cell: meadowCell)
            let breeze = Breeze(bounds: terrain.bounds, cell: meadowCell)
            let random = WebRandom(seed: seed + 100)
            let dt: Double = 1.0 / 60.0
            var t: Double = 0
            for _ in 0..<120 { breeze.step(dt, random: random); land.step(dt, breeze: breeze); t += dt }
            guard let i = land.bloom(atX: 300 + Double(seed) * 100, y: 500, terrain: terrain, time: t) else {
                throw CheckFailure(detail: "seed \(seed): no bloom")
            }
            try expect(land.flowers[i].base.y == 1440 && land.flowers[i].kind != .grass, "seed \(seed): \(land.flowers[i])")
            var last: Double = land.flowers[i].bloom, openedAt: Double = -1
            try expect(last == 0, "seed \(seed): starts as a bud, bloom \(last)")
            for s in 1...(60 * 6) {
                breeze.step(dt, random: random)
                land.step(dt, breeze: breeze)
                let b: Double = land.flowers[i].bloom
                try expect(b >= last && b <= 1, "seed \(seed): bloom went \(last) → \(b)")
                if b == 1 && openedAt < 0 { openedAt = Double(s) * dt }
                last = b
            }
            try expect(openedAt >= 2.6 && openedAt <= 4.2, "seed \(seed): open after \(openedAt) s")
            try expect(land.flowers[i].grown == 1 && land.flowers[i].sparkle == 0, "seed \(seed): done \(land.flowers[i])")
        }
    }
    check("bloomTimeline", bloomTimeline)

    func run(_ seed: UInt64) -> [Flower] {
        let land = Meadowland(random: WebRandom(seed: seed))
        land.layout(terrain: twoScreens, cell: meadowCell)
        let breeze = Breeze(bounds: twoScreens.bounds, cell: meadowCell)
        let random = WebRandom(seed: seed ^ 0x5EED)
        let dt: Double = 1.0 / 60.0
        for s in 0..<(60 * 20) {
            let t = Double(s) * dt
            if s < 120 { breeze.write(200 + Double(s) * 7, 1300, vx: 420, vy: -30) }
            if s == 180 { _ = land.bloom(atX: 900, y: 1200, terrain: twoScreens, time: t) }
            if s == 400 { land.dip(5, impulse: SIMD2<Double>(0, 30)) }
            breeze.step(dt, random: random)
            land.step(dt, breeze: breeze)
        }
        return land.flowers
    }
    func meadowlandDeterministic() throws {
        let a = run(31), b = run(31), c = run(32)
        try expect(!a.isEmpty && a == b, "same seed, different meadows")
        try expect(a != c, "different seeds, same meadow")
        try expect(a.allSatisfy { $0.tip.x.isFinite && $0.tip.y.isFinite }, "non-finite tip")
        try expect(a.contains { simd_length($0.tip) > 1 }, "nothing swayed in 20 s of breeze")
    }
    check("meadowlandDeterministic", meadowlandDeterministic)

    butterflyChecks()
}

// ── Butterfly flight (Task 2) ──

private let flightDt: Double = 1.0 / 60.0
/// An open sky far from any wall, for free-flight statistics.
private let openSky = Terrain.single(width: 200_000, height: 4000)
private let skyStart = SIMD2<Double>(100_000, 2000)

/// One butterfly's flight, sampled after every step.
private struct FlightLog {
    var x: [Double] = [], y: [Double] = [], vx: [Double] = [], vy: [Double] = []
    var heading: [Double] = [], phase: [Double] = [], bank: [Double] = []
    var gliding: [Bool] = [], claps: [Int] = []
    var left: [Double] = [], right: [Double] = []
    var count: Int { x.count }

    mutating func add(_ b: Butterfly) {
        x.append(b.x); y.append(b.y); vx.append(b.vx); vy.append(b.vy)
        heading.append(b.heading); phase.append(b.phase); bank.append(b.bank)
        gliding.append(b.gliding); claps.append(b.claps)
        let w = b.wings()
        left.append(w.left); right.append(w.right)
    }

    /// Steps at which a clap happened (the clap count went up during the step into it).
    var clapSteps: [Int] { (1..<count).filter { claps[$0] > claps[$0 - 1] } }

    /// Whether the butterfly glided at any step in a...b.
    func glidedIn(_ a: Int, _ b: Int) -> Bool { (a...b).contains { gliding[$0] } }

    /// The clap's time, interpolated inside its step from the phase wrapping past 2π.
    func clapTime(_ k: Int) -> Double {
        let p0: Double = phase[k - 1], p1: Double = phase[k] + TAU
        let f: Double = clamp((TAU - p0) / max(p1 - p0, 1e-12), 0, 1)
        return (Double(k - 1) + f) * flightDt
    }

    /// Frequencies of the beats flown without a glide in between, Hz.
    var beatRates: [Double] {
        let c = clapSteps
        guard c.count > 1 else { return [] }
        return (1..<c.count).compactMap { i -> Double? in
            glidedIn(c[i - 1], c[i]) ? nil : 1 / (clapTime(c[i]) - clapTime(c[i - 1]))
        }
    }

    /// Per-beat vertical bob: y less the straight line between the two claps, half its range.
    var bobs: [Double] {
        let c = clapSteps
        guard c.count > 1 else { return [] }
        return (1..<c.count).compactMap { i -> Double? in
            let a = c[i - 1], b = c[i]
            if glidedIn(a, b) { return nil }
            var lo = Double.infinity, hi = -Double.infinity
            for k in a...b {
                let f: Double = Double(k - a) / Double(b - a)
                let r: Double = y[k] - lerp(y[a], y[b], f)
                lo = min(lo, r); hi = max(hi, r)
            }
            return (hi - lo) / 2
        }
    }

    var glideFraction: Double { Double(gliding.filter { $0 }.count) / Double(max(1, count)) }

    /// Distance gone per height lost in steady glides (calm air: ground track = air track): from 0.3 s after the
    /// wings stop, once the airspeed has settled from the bout's climb onto the glide slope.
    var glideRatio: Double {
        var run: Double = 0, drop: Double = 0, gliding: Int = 0
        for k in 1..<count {
            gliding = self.gliding[k] ? gliding + 1 : 0
            guard gliding > 18 else { continue }
            run += abs(x[k] - x[k - 1])
            drop += y[k] - y[k - 1]
        }
        return run / max(drop, 1e-9)
    }

    /// Mean |normal| over mean |tangential| acceleration of the ground track, from 60 Hz differences.
    var normalOverTangential: Double {
        var an: Double = 0, at: Double = 0
        for k in 1..<count {
            let v = SIMD2<Double>(vx[k], vy[k])
            let speed: Double = simd_length(v)
            guard speed > 1e-6 else { continue }
            let t: SIMD2<Double> = v / speed
            let a: SIMD2<Double> = (v - SIMD2<Double>(vx[k - 1], vy[k - 1])) / flightDt
            at += abs(simd_dot(a, t))
            an += abs(a.x * t.y - a.y * t.x)
        }
        return an / max(at, 1e-9)
    }

    /// Turning angle between successive beats' ground displacements (clap to clap), radians.
    var beatTurns: [Double] {
        let c = clapSteps
        guard c.count > 2 else { return [] }
        var out: [Double] = []
        for i in 2..<c.count {
            let a = c[i - 2], b = c[i - 1], e = c[i]
            if glidedIn(a, e) { continue }
            let h0: Double = atan2(y[b] - y[a], x[b] - x[a]), h1: Double = atan2(y[e] - y[b], x[e] - x[b])
            out.append(angleDiff(h0, h1))
        }
        return out
    }

    /// Mean square of the heading's change over half a second.
    var headingVariance: Double {
        let lag = 30
        guard count > lag else { return 0 }
        var s: Double = 0
        for k in lag..<count {
            let d: Double = angleDiff(heading[k - lag], heading[k])
            s += d * d
        }
        return s / Double(count - lag)
    }
}

/// Fly one butterfly for `seconds`, logging every step. `aim` gives the target each step (nil: free flight).
private func flyLog(_ b: Butterfly, seconds: Double, terrain: Terrain = openSky, breeze: Breeze? = nil,
                    random: WebRandom, aim: (Butterfly) -> SIMD2<Double>? = { _ in nil }) -> FlightLog {
    let air = breeze ?? calmBreeze(terrain.bounds)
    var log = FlightLog()
    log.add(b)
    for _ in 0..<Int(seconds * 60) {
        air.step(flightDt, random: random)
        b.fly(flightDt, target: aim(b), breeze: air, terrain: terrain, random: random)
        log.add(b)
    }
    return log
}

private func mean(_ xs: [Double]) -> Double { xs.isEmpty ? .nan : xs.reduce(0, +) / Double(xs.count) }

/// The 10° bin (of 36, bin 18 centred on 0) holding the most per-beat turns.
private func turnMode(_ turns: [Double]) -> (bin: Int, counts: [Int]) {
    var counts = [Int](repeating: 0, count: 36)
    for t in turns {
        let deg: Double = t * 180 / Double.pi
        counts[Int(floor((deg + 185) / 10)) % 36] += 1
    }
    let best = counts.indices.max { counts[$0] < counts[$1] } ?? 0
    return (best, counts)
}

func butterflyChecks() {
    func wingbeatRates() throws {
        let want: [ButterflyKind: Double] = [.monarch: 2.6, .morpho: 1.7, .swallowtail: 2.0, .cabbageWhite: 3.0]
        for kind in ButterflyKind.allCases {
            var rates: [Double] = []
            for seed in UInt64(1)...UInt64(20) {
                let random = WebRandom(seed: seed * 7 + 1)
                let b = Butterfly(kind: kind, x: skyStart.x, y: skyStart.y, random: random)
                let log = flyLog(b, seconds: 20, random: random) { _ in SIMD2<Double>(skyStart.x + 1e6, skyStart.y) }
                rates += log.beatRates
            }
            let f: Double = mean(rates), target: Double = want[kind]!
            try expect(rates.count > 100, "\(kind): only \(rates.count) beats")
            try expect(abs(f - target) <= 0.05 * target, "\(kind): mean beat \(f) Hz, want \(target)")
            let top: Double = rates.max() ?? 0
            try expect(top <= 3 + 1e-6, "\(kind): a beat at \(top) Hz")
        }
    }
    check("wingbeatRates", wingbeatRates)

    func bodyBobsInRange() throws {
        let want: [(ButterflyKind, Double)] = [(.monarch, 0.25), (.cabbageWhite, 0.2)]
        for (kind, rows) in want {
            var bobs: [Double] = []
            for seed in UInt64(1)...UInt64(6) {
                let random = WebRandom(seed: seed + 40)
                let b = Butterfly(kind: kind, x: skyStart.x, y: skyStart.y, random: random)
                b.jinkFactor = 0   // level cruise
                let log = flyLog(b, seconds: 20, random: random) { b in SIMD2<Double>(b.x + 1e5, b.y) }
                bobs += log.bobs
            }
            let bob: Double = mean(bobs) / Double(meadowCell.height)
            try expect(bobs.count > 20, "\(kind): \(bobs.count) beats")
            try expectClose(bob, rows, tol: 0.1, "\(kind) bob, rows")
        }
    }
    check("bodyBobsInRange", bodyBobsInRange)

    func liftOnlyOnDownstroke() throws {
        for kind in ButterflyKind.allCases {
            let random = WebRandom(seed: 50)
            let b = Butterfly(kind: kind, x: skyStart.x, y: skyStart.y, random: random)
            b.jinkFactor = 0
            b.glide(for: 1000)
            let claps = b.claps
            let log = flyLog(b, seconds: 6, random: random)
            let a = 60, e = log.count - 1   // after a second to settle onto the slope
            let angle: Double = atan2(log.y[e] - log.y[a], abs(log.x[e] - log.x[a]))
            let want: Double = ButterflySpecies.of(kind).glideAngle
            try expect(abs(angle - want) <= 3 * Double.pi / 180, "\(kind): glides at \(angle * 180 / .pi)°, want \(want * 180 / .pi)°")
            try expect(b.claps == claps && b.gliding, "\(kind): beat while the stroke was frozen")
        }
    }
    check("liftOnlyOnDownstroke", liftOnlyOnDownstroke)

    func monarchCalmerThanWhite() throws {
        var variance: [ButterflyKind: Double] = [:], glide: [ButterflyKind: Double] = [:]
        for kind in [ButterflyKind.monarch, .cabbageWhite] {
            let random = WebRandom(seed: 60)
            let b = Butterfly(kind: kind, x: skyStart.x, y: skyStart.y, random: random)
            let log = flyLog(b, seconds: 60, random: random)
            variance[kind] = log.headingVariance
            glide[kind] = log.glideFraction
        }
        let vm: Double = variance[.monarch]!, vw: Double = variance[.cabbageWhite]!
        try expect(vm < 0.5 * vw, "heading variance monarch \(vm) vs white \(vw)")
        let gm: Double = glide[.monarch]!, gw: Double = glide[.cabbageWhite]!
        try expect(gm > 0.15 && 0.15 > gw, "glide fraction monarch \(gm), white \(gw)")
    }
    check("monarchCalmerThanWhite", monarchCalmerThanWhite)

    func morphoFlashes() throws {
        let random = WebRandom(seed: 70)
        let b = Butterfly(kind: .morpho, x: skyStart.x, y: skyStart.y, random: random)
        b.jinkFactor = 0
        // Always aim a wingspan off to the right of the heading: a tight continuous turn.
        let log = flyLog(b, seconds: 8, random: random) { b in
            let a: Double = b.heading + Double.pi / 2
            return SIMD2<Double>(b.x + 200 * cos(a), b.y + 200 * sin(a))
        }
        let maxBank: Double = ButterflySpecies.of(.morpho).maxBank
        let c = log.clapSteps.filter { $0 > 120 }
        var checked = 0
        for i in 1..<max(1, c.count) where !log.glidedIn(c[i - 1], c[i]) {
            let a = c[i - 1], e = c[i]
            try expect(abs(log.bank[a]) > 0.8 * maxBank, "bank \(log.bank[a] * 180 / .pi)° in a hard turn")
            let ls = (a...e).map { log.left[$0] > 0 }, rs = (a...e).map { log.right[$0] > 0 }
            try expect(ls.contains(true) && ls.contains(false), "left wing kept one face over the beat at step \(a)")
            try expect(rs.contains(true) && rs.contains(false), "right wing kept one face over the beat at step \(a)")
            checked += 1
        }
        try expect(checked >= 3, "only \(checked) flapping beats in the turn")
    }
    check("morphoFlashes", morphoFlashes)

    func butterfliesStayInside() throws {
        let random = WebRandom(seed: 80)
        let breeze = Breeze(bounds: twoScreens.bounds, cell: meadowCell)   // weather on: breeze and gusts
        var flock: [Butterfly] = []
        let kinds = ButterflyKind.allCases
        for i in 0..<10 {
            var p = SIMD2<Double>(0, 0)
            repeat { p = SIMD2<Double>(random.range(0, 2560), random.range(0, 2609)) } while !twoScreens.contains(p)
            flock.append(Butterfly(kind: kinds[i % kinds.count], x: p.x, y: p.y, random: random))
        }
        for step in 0..<(5 * 60 * 60) {
            breeze.step(flightDt, random: random)
            for (i, b) in flock.enumerated() {
                b.fly(flightDt, target: nil, breeze: breeze, terrain: twoScreens, random: random)
                let p = SIMD2<Double>(b.x, b.y)
                let finite = b.x.isFinite && b.y.isFinite && b.vx.isFinite && b.vy.isFinite && b.heading.isFinite
                try expect(finite, "butterfly \(i) not finite at step \(step)")
                let out: Double = simd_length(p - twoScreens.nearestInside(p))
                let span: Double = ButterflySpecies.of(b.kind).span * Double(meadowCell.width) * b.size
                try expect(out <= span, "butterfly \(i) (\(b.kind)) \(out) pt outside at \(p), step \(step)")
            }
        }
    }
    check("butterfliesStayInside", butterfliesStayInside)

    func freeFlightCoversTheField() throws {
        let field = Terrain.single(width: 1800, height: 1169)
        for (i, kind) in ButterflyKind.allCases.enumerated() {
            let random = WebRandom(seed: 85 + UInt64(i))
            let b = Butterfly(kind: kind, x: 900, y: 585, random: random)
            let log = flyLog(b, seconds: 180, terrain: field, random: random)
            var seen = [Bool](repeating: false, count: 9)
            for k in 0..<log.count {
                let cx = Int(clamp(log.x[k] / 600, 0, 2)), cy = Int(clamp(log.y[k] / (1169.0 / 3), 0, 2))
                seen[cy * 3 + cx] = true
            }
            let visited = seen.filter { $0 }.count
            let wide: Double = ((log.x.max() ?? 0) - (log.x.min() ?? 0)) / 1800
            let tall: Double = ((log.y.max() ?? 0) - (log.y.min() ?? 0)) / 1169
            try expect(visited >= 6, "\(kind) visited \(visited) of 9 cells: \(seen)")
            try expect(seen[6] || seen[7] || seen[8], "\(kind) never in the bottom third: \(seen)")
            // Not a band: the track spans most of the field both ways.
            try expect(wide >= 0.7 && tall >= 0.6, "\(kind) spans \(wide) of the width, \(tall) of the height")
        }
    }
    check("freeFlightCoversTheField", freeFlightCoversTheField)

    func flightPathsMatchMeasurements() throws {
        // Cabbage white: turning acceleration about equal to forward acceleration (7.6 vs 8.5 m/s², Jantzen & Eisner 2008).
        let rw = WebRandom(seed: 90)
        let white = flyLog(Butterfly(kind: .cabbageWhite, x: skyStart.x, y: skyStart.y, random: rw), seconds: 120, random: rw)
        let ratio: Double = white.normalOverTangential
        try expectClose(ratio, 0.9, tol: 0.35, "white a_n / a_t")
        // Monarch: flap bouts and glides at 3.6:1 (Gibo).
        let rm = WebRandom(seed: 91)
        let monarch = flyLog(Butterfly(kind: .monarch, x: skyStart.x, y: skyStart.y, random: rm), seconds: 120, random: rm)
        try expect(monarch.glideFraction >= 0.15, "monarch glides \(monarch.glideFraction) of the time")
        try expectClose(monarch.glideRatio, 3.6, tol: 0.5, "monarch glide ratio")
        // Every species: a correlated random walk, per-beat turning angles peaked at 0 (Kareiva & Shigesada 1983).
        // Four 2-minute flights each: the slow morpho beats only ~100 times in one.
        for kind in ButterflyKind.allCases {
            var turns: [Double] = []
            for seed in UInt64(92)...UInt64(95) {
                let r = WebRandom(seed: seed)
                turns += flyLog(Butterfly(kind: kind, x: skyStart.x, y: skyStart.y, random: r), seconds: 120, random: r).beatTurns
            }
            let (bin, counts) = turnMode(turns)
            try expect(turns.count > 200 && bin == 18, "\(kind): turning angles peak in bin \(bin) (18 is 0°): \(counts)")
        }
    }
    check("flightPathsMatchMeasurements", flightPathsMatchMeasurements)
}

