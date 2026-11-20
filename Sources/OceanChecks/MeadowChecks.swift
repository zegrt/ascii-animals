import CoreGraphics
import Foundation
import Metal
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
        // The falloff is the Gaussian exp(-(d / 2.5)²), samples: e⁻¹ of the centre at 2.5 samples, and the right
        // weight at every node out to 4. A flat write, or one of another radius, fails here.
        let centre0: Double = simd_length(b.sample(x, y))
        let sxPt: Double = 4 * Double(meadowCell.width), syPt: Double = 3 * Double(meadowCell.height)
        let mid: Double = simd_length(b.sample(x + 2.5 * sxPt, y)) / centre0
        try expectClose(mid, exp(-1.0), tol: 0.03, "2.5 samples out, share of the centre")
        for d in 1...4 {
            let dd: Double = Double(d)
            let want: Double = exp(-(dd * dd) / 6.25)
            let alongX: Double = simd_length(b.sample(x + dd * sxPt, y)) / centre0
            let alongY: Double = simd_length(b.sample(x, y - dd * syPt)) / centre0
            try expectClose(alongX, want, tol: 0.02, "\(d) samples along x, share of the centre")
            try expectClose(alongY, want, tol: 0.02, "\(d) samples along y, share of the centre")
        }
        let random = WebRandom(seed: 4)
        for frame in 0..<30 {
            let centre: Double = simd_length(b.sample(x, y))
            let sx: Double = 6 * sxPt, sy: Double = 6 * syPt
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

    func bloomKeepsTheLandsClock() throws {
        let terrain = Terrain.single(width: 2560, height: 1440)
        let land = Meadowland(random: WebRandom(seed: 33))
        land.layout(terrain: terrain, cell: meadowCell)
        let breeze = Breeze(bounds: terrain.bounds, cell: meadowCell)
        let random = WebRandom(seed: 34)
        let dt: Double = 1.0 / 60.0
        for _ in 0..<60 { breeze.step(dt, random: random); land.step(dt, breeze: breeze) }
        let t1: Double = land.time
        guard let first = land.bloom(atX: 800, y: 900, terrain: terrain, time: t1) else {
            throw CheckFailure(detail: "no bloom at 1 s")
        }
        try expectClose(land.flowers[first].bornAt, t1, tol: 1e-12, "first bloom's bornAt")
        for _ in 0..<(60 * 9) { breeze.step(dt, random: random); land.step(dt, breeze: breeze) }
        let t10: Double = land.time
        try expect(land.flowers[first].bloom == 1 && land.flowers[first].grown == 1, "first bloom open by 10 s")
        // A caller passing another clock: the land keeps its own; the time is only the new flower's bornAt.
        guard let second = land.bloom(atX: 1600, y: 900, terrain: terrain, time: 0) else {
            throw CheckFailure(detail: "no bloom at 10 s")
        }
        try expectClose(land.time, t10, tol: 1e-12, "the land's clock after bloom(time: 0)")
        try expectClose(land.flowers[second].bornAt, 0, tol: 1e-12, "second bloom's bornAt")
        breeze.step(dt, random: random)
        land.step(dt, breeze: breeze)
        try expectClose(land.time, t10 + dt, tol: 1e-9, "the land's clock steps on")
        let f = land.flowers[first]
        try expect(f.bloom == 1 && f.grown == 1 && f.sparkle == 0, "the first bloom rewound: \(f)")
    }
    check("bloomKeepsTheLandsClock", bloomKeepsTheLandsClock)

    func weatherAndLeanScaleWithCell() throws {
        // Speeds are given at 13-pt cells and scale with cell.width / 13. The same meadow laid out on a smaller
        // grid (8 × 12 cells, the terrain shrunk with them) gets the same weather at 8/13 the speed, and its
        // stems lean the same share of their length.
        let small = CGSize(width: 8, height: 12)
        let s: Double = 8.0 / 13.0, sy: Double = 12.0 / 19.0
        let bigT = Terrain.single(width: 2560, height: 1440)
        let smallT = Terrain.single(width: 2560 * s, height: 1440 * sy)
        let bigB = Breeze(bounds: bigT.bounds, cell: meadowCell), smallB = Breeze(bounds: smallT.bounds, cell: small)
        let bigL = Meadowland(random: WebRandom(seed: 41)), smallL = Meadowland(random: WebRandom(seed: 41))
        bigL.layout(terrain: bigT, cell: meadowCell)
        smallL.layout(terrain: smallT, cell: small)
        try expect(bigL.flowers.count == smallL.flowers.count, "layouts differ: \(bigL.flowers.count) vs \(smallL.flowers.count)")
        let rb = WebRandom(seed: 42), rs = WebRandom(seed: 42)
        let dt: Double = 1.0 / 60.0
        var peak: Double = 0
        var bigLean: Double = 0, smallLean: Double = 0
        for step in 0..<(60 * 90) {
            bigB.step(dt, random: rb)
            smallB.step(dt, random: rs)
            bigL.step(dt, breeze: bigB)
            smallL.step(dt, breeze: smallB)
            guard step % 30 == 0 else { continue }
            for i in [0, 7, 19, 33, 48] {
                let bx: Double = Double(i) * 4 * 13, by: Double = 5 * 3 * 19
                let ws: SIMD2<Double> = smallB.sample(bx * s, by * sy), wb: SIMD2<Double> = bigB.sample(bx, by)
                peak = max(peak, simd_length(wb))
                try expectClose(ws.x, wb.x * s, tol: 1e-6 * max(1, abs(wb.x)), "step \(step) column \(i): wind x")
                try expectClose(ws.y, wb.y * s, tol: 1e-6 * max(1, abs(wb.y)), "step \(step) column \(i): wind y")
            }
            for k in 0..<bigL.flowers.count where bigL.flowers[k].kind != .grass {
                let fb = bigL.flowers[k], fs = smallL.flowers[k]
                bigLean += abs(fb.tip.x) / (Double(fb.rows) * 19)
                smallLean += abs(fs.tip.x) / (Double(fs.rows) * 12)
            }
        }
        try expect(peak > 60, "no gust in 90 s: peak \(peak) pt/s")
        try expectClose(smallLean / bigLean, 1, tol: 0.05, "stems lean a share of their length on 8-pt cells vs 13-pt")
    }
    check("weatherAndLeanScaleWithCell", weatherAndLeanScaleWithCell)

    butterflyChecks()
    meadowPainterChecks()
    meadowRestartChecks()
    meadowRestartFixChecks()
    meadowRestart2Checks()
    // CI runners have no GPU: OCEAN_SKIP_GPU=1 skips the Metal checks (main.swift skips its own the same way).
    if ProcessInfo.processInfo.environment["OCEAN_SKIP_GPU"] == nil { meadowRenderChecks() }
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

    /// Mean |normal| over mean |tangential| acceleration of the per-beat-averaged velocity (clap to clap), so
    /// the bob and the clap's lurch inside a beat drop out and what is left is how the path turns and speeds up
    /// from beat to beat.
    var perBeatNormalOverTangential: Double {
        let c = clapSteps
        guard c.count > 2 else { return 0 }
        var an: Double = 0, at: Double = 0
        for i in 2..<c.count {
            let a = c[i - 2], b = c[i - 1], e = c[i]
            if glidedIn(a, e) { continue }
            let t0: Double = clapTime(b) - clapTime(a), t1: Double = clapTime(e) - clapTime(b)
            guard t0 > 1e-6 && t1 > 1e-6 else { continue }
            let v0 = SIMD2<Double>(x[b] - x[a], y[b] - y[a]) / t0
            let v1 = SIMD2<Double>(x[e] - x[b], y[e] - y[b]) / t1
            let v: SIMD2<Double> = (v0 + v1) / 2
            let speed: Double = simd_length(v)
            guard speed > 1e-6 else { continue }
            let tan: SIMD2<Double> = v / speed
            let acc: SIMD2<Double> = (v1 - v0) / ((t0 + t1) / 2)
            at += abs(simd_dot(acc, tan))
            an += abs(acc.x * tan.y - acc.y * tan.x)
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
        let shifted: Double = (deg + 185) / 10
        let bin: Int = Int(floor(shifted)) % 36
        counts[bin] += 1
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
            let angleDeg: Double = angle * 180 / Double.pi, wantDeg: Double = want * 180 / Double.pi
            try expect(abs(angle - want) <= 3 * Double.pi / 180, "\(kind): glides at \(angleDeg)°, want \(wantDeg)°")
            try expect(b.claps == claps && b.gliding, "\(kind): beat while the stroke was frozen")
        }
        // The stroke frozen outside a glide (no beats, gravity on), at one θ after another, the same butterfly
        // each time. Held anywhere on the upstroke the wings give nothing: every such flight is the same as
        // one held at θ = π (no lift at all), to the last digit, and without a bound that flight sinks. Held at
        // mid-downstroke the lift beats gravity and it climbs away from that line. Lift on the upstroke too
        // would part the upstroke flights from it.
        for kind in ButterflyKind.allCases {
            func frozen(_ theta: Double) throws -> [Double] {
                let random = WebRandom(seed: 51)
                let b = Butterfly(kind: kind, x: skyStart.x, y: skyStart.y, random: random)
                b.jinkFactor = 0
                b.beatFactor = 0   // no beats: θ stays where it is put
                b.phase = theta
                let log = flyLog(b, seconds: 1.5, random: random) { b in SIMD2<Double>(b.x + 1e5, b.y) }
                try expect(b.claps == 0 && !b.gliding && b.phase == theta, "\(kind) θ \(theta): the stroke moved")
                return log.y
            }
            let none: [Double] = try frozen(Double.pi)
            let sink: Double = none[none.count - 1] - none[30]   // y down: positive is sinking
            if ButterflySpecies.of(kind).boundAngle == 0 {
                try expect(sink > 30, "\(kind) with no lift sank only \(sink) pt in 1 s")
            }
            for k in 1..<12 {
                let up: Double = Double.pi + Double(k) * Double.pi / 12
                let ys: [Double] = try frozen(up)
                let apart: Double = zip(ys, none).map { abs($0 - $1) }.max() ?? 0
                try expect(apart < 1e-9, "\(kind) held at θ \(up) (upstroke): \(apart) pt off the no-lift flight")
            }
            for k in 2..<11 {
                let down: Double = Double(k) * Double.pi / 12
                let ys: [Double] = try frozen(down)
                let rose: Double = none[none.count - 1] - ys[ys.count - 1]
                try expect(rose > 30, "\(kind) held at θ \(down) (downstroke): only \(rose) pt above the no-lift flight")
            }
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
            let bankDeg: Double = log.bank[a] * 180 / Double.pi
            try expect(abs(log.bank[a]) > 0.8 * maxBank, "bank \(bankDeg)° in a hard turn")
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

    /// Per species, over several seeds and random starts: where the free flight spends its time on a field.
    func coverage(_ field: Terrain, cell: CGSize, seconds: Double, seeds: ClosedRange<UInt64>,
                  _ assert: (ButterflyKind, UInt64, FlightLog) throws -> Void) throws {
        let r = field.rects[0]
        for (i, kind) in ButterflyKind.allCases.enumerated() {
            for seed in seeds {
                let random = WebRandom(seed: seed * 31 + UInt64(i))
                let x0: Double = random.range(Double(r.minX), Double(r.maxX))
                let y0: Double = random.range(Double(r.minY), Double(r.maxY))
                let b = Butterfly(kind: kind, x: x0, y: y0, random: random)
                b.scale = Double(cell.width) / 13
                let air = Breeze(bounds: field.bounds, cell: cell)
                air.ambient = false
                let log = flyLog(b, seconds: seconds, terrain: field, breeze: air, random: random)
                try assert(kind, seed, log)
            }
        }
    }

    /// Which of a 3 × 3 grid over the rect the log visited, and its share of time in each third of the height.
    func grid(_ log: FlightLog, _ r: CGRect) -> (seen: [Bool], thirds: [Double], wide: Double, tall: Double) {
        var seen = [Bool](repeating: false, count: 9)
        var thirds: [Double] = [0, 0, 0]
        let w: Double = Double(r.width), h: Double = Double(r.height)
        for k in 0..<log.count {
            let u: Double = (log.x[k] - Double(r.minX)) / (w / 3), v: Double = (log.y[k] - Double(r.minY)) / (h / 3)
            let cx = Int(clamp(u, 0, 2)), cy = Int(clamp(v, 0, 2))
            seen[cy * 3 + cx] = true
            thirds[cy] += 1 / Double(log.count)
        }
        let wide: Double = ((log.x.max() ?? 0) - (log.x.min() ?? 0)) / w
        let tall: Double = ((log.y.max() ?? 0) - (log.y.min() ?? 0)) / h
        return (seen, thirds, wide, tall)
    }

    func freeFlightCoversTheField() throws {
        // The director's correction: free flight roams the whole field. Eight seeds and random starts per
        // species, every one of them held to it.
        let field = Terrain.single(width: 1800, height: 1169)
        try coverage(field, cell: meadowCell, seconds: 180, seeds: 1...8) { kind, seed, log in
            let g = grid(log, field.rects[0])
            let visited = g.seen.filter { $0 }.count
            try expect(visited >= 6, "\(kind) seed \(seed) visited \(visited) of 9 cells: \(g.seen)")
            try expect(g.seen[6] || g.seen[7] || g.seen[8], "\(kind) seed \(seed) never in the bottom third: \(g.seen)")
            // Not a band: the track spans most of the field both ways.
            try expect(g.wide >= 0.7 && g.tall >= 0.6, "\(kind) seed \(seed) spans \(g.wide) of the width, \(g.tall) of the height")
        }
    }
    check("freeFlightCoversTheField", freeFlightCoversTheField)

    func freeFlightRoamsATinyScreen() throws {
        // The Settings preview: 340 × 150 pt at its 8-pt cell (GridSpec.cell(forWidth: 340)). Free flight is not
        // a band through the middle: it spends no more than 70 % of its time in the middle third of the height,
        // at least 5 % in the top third and 10 % in the bottom one, and still visits 6 of the 9 cells.
        let field = Terrain.single(width: 340, height: 150)
        let cell = GridSpec.cell(forWidth: 340)
        try expect(cell.width == 8, "the preview's cell is \(cell)")
        try coverage(field, cell: cell, seconds: 300, seeds: 1...5) { kind, seed, log in
            let g = grid(log, field.rects[0])
            let visited = g.seen.filter { $0 }.count
            let t: [Double] = g.thirds
            try expect(t[1] <= 0.7, "\(kind) seed \(seed): \(t[1]) of the time in the middle third (thirds \(t))")
            try expect(t[0] >= 0.05 && t[2] >= 0.1, "\(kind) seed \(seed): thirds \(t)")
            try expect(visited >= 6, "\(kind) seed \(seed) visited \(visited) of 9 cells: \(g.seen)")
        }
    }
    check("freeFlightRoamsATinyScreen", freeFlightRoamsATinyScreen)

    func flowerSeekersReachLowHeads() throws {
        // A butterfly flying at a flower (.approach) reaches its head right down to the shortest, one-row
        // flowers: the ground doesn't push it off. Within half a cell of the head, from up to ~600 pt away above
        // it (15 s at foraging speed covers ~1200 pt).
        let field = Terrain.single(width: 1800, height: 1169)
        var head: SIMD2<Double>? = nil
        for seed in UInt64(1)...UInt64(20) where head == nil {
            let land = Meadowland(random: WebRandom(seed: seed))
            land.layout(terrain: field, cell: meadowCell)
            let low: [Int] = land.flowers.indices.filter { land.flowers[$0].kind != .grass && land.flowers[$0].rows == 1 }
            if let i = low.min(by: { abs(land.flowers[$0].base.x - 900) < abs(land.flowers[$1].base.x - 900) }) {
                head = land.head(i)
            }
        }
        guard let h = head else { throw CheckFailure(detail: "no one-row flower in 20 layouts") }
        try expectClose(h.y, 1169 - 19, tol: 1e-9, "a one-row head's height")
        for kind in ButterflyKind.allCases {
            for seed in UInt64(1)...UInt64(5) {
                let random = WebRandom(seed: 200 + seed)
                let x0: Double = h.x + random.range(-400, 400), y0: Double = random.range(700, 1000)
                let b = Butterfly(kind: kind, x: x0, y: y0, random: random)
                b.state = .approach
                let log = flyLog(b, seconds: 15, terrain: field, random: random) { _ in h }
                var closest: Double = .infinity
                for k in 0..<log.count {
                    let d: Double = simd_length(SIMD2<Double>(log.x[k], log.y[k]) - h)
                    closest = min(closest, d)
                    let p = SIMD2<Double>(log.x[k], log.y[k])
                    let out: Double = simd_length(p - field.nearestInside(p))
                    try expect(out <= b.wingspan, "\(kind) seed \(seed): \(out) pt outside at step \(k)")
                }
                try expect(closest <= 0.5 * Double(meadowCell.width), "\(kind) seed \(seed): closest \(closest) pt to a one-row head at \(h)")
            }
        }
    }
    check("flowerSeekersReachLowHeads", flowerSeekersReachLowHeads)

    func badInputStaysFinite() throws {
        // A non-finite position, target or wind never crashes the breeze or leaves a butterfly non-finite.
        let bad: [Double] = [.nan, .infinity, -.infinity]
        let terrain = Terrain.single(width: 1800, height: 1169)
        let breeze = Breeze(bounds: terrain.bounds, cell: meadowCell)
        let random = WebRandom(seed: 300)
        for _ in 0..<600 { breeze.step(flightDt, random: random) }
        for v in bad {
            for (x, y) in [(v, 10.0), (10.0, v), (v, v)] {
                let w: SIMD2<Double> = breeze.sample(x, y)
                try expect(w.x.isFinite && w.y.isFinite, "sample(\(x), \(y)) = \(w)")
            }
        }
        func finite(_ b: Butterfly) -> Bool {
            let parts: [Double] = [b.x, b.y, b.vx, b.vy, b.heading, b.phase, b.bank, b.pitch, b.stroke]
            return parts.allSatisfy { $0.isFinite }
        }
        for kind in ButterflyKind.allCases {
            for v in bad {
                let targets: [SIMD2<Double>] = [SIMD2<Double>(v, 3), SIMD2<Double>(900, v), SIMD2<Double>(v, v)]
                for target in targets {
                    let b = Butterfly(kind: kind, x: 900, y: 500, random: random)
                    for step in 0..<120 {
                        b.fly(flightDt, target: step % 2 == 0 ? target : nil, breeze: breeze, terrain: terrain, random: random)
                        try expect(finite(b), "\(kind) target \(target) step \(step): not finite")
                    }
                    try expect(terrain.contains(SIMD2<Double>(b.x, b.y)), "\(kind) target \(target): left at \(b.x), \(b.y)")
                }
                // A position poisoned from outside: the next step puts it back where it last was finite.
                let b = Butterfly(kind: kind, x: 900, y: 500, random: random)
                for _ in 0..<30 { b.fly(flightDt, target: nil, breeze: breeze, terrain: terrain, random: random) }
                b.x = v
                b.y = v
                for step in 0..<120 {
                    b.fly(flightDt, target: nil, breeze: breeze, terrain: terrain, random: random)
                    try expect(finite(b), "\(kind) poisoned with \(v), step \(step): not finite")
                }
                try expect(terrain.contains(SIMD2<Double>(b.x, b.y)), "\(kind) poisoned with \(v): at \(b.x), \(b.y)")
            }
        }
    }
    check("badInputStaysFinite", badInputStaysFinite)

    func flightPathsMatchMeasurements() throws {
        // Cabbage white: turning acceleration about equal to forward acceleration (7.6 vs 8.5 m/s², Jantzen & Eisner 2008),
        // on the per-beat-averaged velocity so the bob and the lurch inside a beat don't count. The zig-zag is what
        // turns it: the same white without jinks falls well short.
        for seed in UInt64(88)...UInt64(92) {
            let rw = WebRandom(seed: seed)
            let white = Butterfly(kind: .cabbageWhite, x: skyStart.x, y: skyStart.y, random: rw)
            let ratio: Double = flyLog(white, seconds: 120, random: rw).perBeatNormalOverTangential
            try expectClose(ratio, 0.9, tol: 0.35, "seed \(seed): white a_n / a_t, per beat")
            let rs = WebRandom(seed: seed)
            let calm = Butterfly(kind: .cabbageWhite, x: skyStart.x, y: skyStart.y, random: rs)
            calm.jinkFactor = 0
            let still: Double = flyLog(calm, seconds: 120, random: rs).perBeatNormalOverTangential
            try expect(still < 0.55, "seed \(seed): a white without jinks still has a_n / a_t \(still)")
        }
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


// ── The meadow painter (Task 5) ──

private func meadowTheme(light: Bool = false, calm: Bool = false) -> ThemeParams {
    var s = Settings.defaults
    s.appearance = light ? .light : .dark
    s.calm = calm
    return ThemeParams.make(s, systemIsDark: true, accent: SIMD3<Float>(0, 0, 0))
}

/// A butterfly held in a pose: full size at 13 × 19 pt cells, body upright (heading straight up), not banked, wings
/// level (stroke 0, both wings fully open).
private func posed(_ kind: ButterflyKind, x: Double, y: Double) -> Butterfly {
    let b = Butterfly(kind: kind, x: x, y: y, random: WebRandom(seed: 1))
    b.size = 1
    b.scale = 1
    b.heading = 1.5 * Double.pi
    b.bank = 0
    b.pitch = 0
    b.phase = 0
    b.stroke = 0
    b.gliding = false
    return b
}

/// Paints one frame of the meadow over `size` (viewport at the origin) into `canvas` (a new one when nil).
private func paintMeadow(_ painter: MeadowPainter, land: Meadowland, flies: [Butterfly], breeze: Breeze, time: Double = 0,
                         size: CGSize, theme: ThemeParams, into canvas: CellCanvas? = nil) -> CellCanvas {
    let grid = GridSpec.make(viewportSize: size, cell: meadowCell)
    let c: CellCanvas = canvas ?? CellCanvas(cols: grid.cols, rows: grid.rows)
    c.clear()
    painter.paint(land: land, butterflies: flies, breeze: breeze, time: time, viewport: CGRect(origin: .zero, size: size),
                  grid: grid, theme: theme, into: c)
    return c
}

/// The colour channels of a packed RGBA8, 0…255.
private func unpack(_ v: UInt32) -> SIMD4<Double> {
    SIMD4<Double>(Double(v & 0xff), Double((v >> 8) & 0xff), Double((v >> 16) & 0xff), Double(v >> 24))
}

private func luminance(_ v: UInt32) -> Double {
    let c: SIMD4<Double> = unpack(v)
    return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
}

/// A cell holds something: a glyph or a block.
private func drawn(_ c: CellCanvas, _ i: Int) -> Bool { c.glyph[i] != CellCanvas.noGlyph || c.block[i] >> 24 != 0 }

/// A meadow laid out on one screen, with the weather off.
private func meadowScene(_ size: CGSize, seed: UInt64) -> (land: Meadowland, breeze: Breeze) {
    let land = Meadowland(random: WebRandom(seed: seed))
    land.layout(terrain: .single(width: Double(size.width), height: Double(size.height)), cell: meadowCell)
    return (land, calmBreeze(CGRect(origin: .zero, size: size)))
}

/// One butterfly hovering in calm air, beating and bobbing, painted at 30 fps for `frames` frames, with its body
/// `dx`, `dy` pt off a cell's centre and banked by `bank`. Returns the most switches between empty and full any one
/// cell made inside one beat window (the frames whose `floor(t · beat)` agree), with the cell and the window, and how
/// many full cells it drew in all. Edge frames (a glyph, no block) count as neither.
private func flickerInBeatWindows(_ kind: ButterflyKind, dx: Double, dy: Double, bank: Double, frames: Int = 120)
    -> (most: Int, cell: Int, window: Int, full: Int, cols: Int) {
    let size = CGSize(width: 640, height: 400)
    let land = Meadowland(random: WebRandom(seed: 2))
    let breeze = calmBreeze(CGRect(origin: .zero, size: size))
    let b = posed(kind, x: 318.5 + dx, y: 199.5 + dy)
    b.bank = bank
    let y0: Double = b.y
    let sp = b.species
    let painter = MeadowPainter()
    let theme = meadowTheme()
    let grid = GridSpec.make(viewportSize: size, cell: meadowCell)
    let canvas = CellCanvas(cols: grid.cols, rows: grid.rows)
    let n = grid.cols * grid.rows
    let dt: Double = 1.0 / 30.0
    var last = [Int8](repeating: 0, count: n)
    var window = [Int](repeating: -1, count: n), inWindow = [Int](repeating: 0, count: n)
    var most = 0, mostCell = -1, mostWindow = -1, full = 0
    for k in 0..<frames {
        let t: Double = Double(k) * dt
        let theta: Double = fmod(TAU * sp.beat * t, TAU)
        b.phase = theta
        b.stroke = sp.strokeMid + sp.strokeAmp * cos(theta)
        b.y = y0 - sp.bobRows * Double(meadowCell.height) * sin(theta)
        _ = paintMeadow(painter, land: land, flies: [b], breeze: breeze, time: t, size: size, theme: theme, into: canvas)
        let w = Int(floor(t * sp.beat + 1e-9))
        for i in 0..<n {
            let isFull: Bool = canvas.block[i] >> 24 != 0
            let empty: Bool = !drawn(canvas, i)
            let now: Int8 = isFull ? 1 : (empty ? 0 : last[i])
            if isFull { full += 1 }
            if k > 0 && now != last[i] {
                if window[i] != w { window[i] = w; inWindow[i] = 0 }
                inWindow[i] += 1
                if inWindow[i] > most { most = inWindow[i]; mostCell = i; mostWindow = w }
            }
            last[i] = now
        }
    }
    return (most, mostCell, mostWindow, full, grid.cols)
}

func meadowPainterChecks() {
    func wingsDoNotFlicker() throws {
        // A monarch hovering in calm air, its wings beating at 2.6 Hz and its body bobbing, painted at 30 fps for
        // 120 frames. A cell may go from empty to full and back once a beat (the wings open and close), never more:
        // any three switches of one cell span at least a beat (less a frame, for where the frames fall). Edge frames
        // in between count as neither, so a cell only switches when it really empties or fills.
        let size = CGSize(width: 520, height: 380)
        let land = Meadowland(random: WebRandom(seed: 2))
        let breeze = calmBreeze(CGRect(origin: .zero, size: size))
        let b = posed(.monarch, x: 266.5, y: 199.5)
        let y0: Double = b.y
        let sp = b.species
        let painter = MeadowPainter()
        let theme = meadowTheme()
        let grid = GridSpec.make(viewportSize: size, cell: meadowCell)
        let canvas = CellCanvas(cols: grid.cols, rows: grid.rows)
        let n = grid.cols * grid.rows
        let dt: Double = 1.0 / 30.0
        let beat: Double = 1 / sp.beat
        // 0 empty, 1 full: the last of those each cell was in, and the frames of its last two switches.
        var last = [Int8](repeating: 0, count: n)
        var before = [Int](repeating: -1_000, count: n), latest = [Int](repeating: -1_000, count: n)
        var total = 0, everFull = 0, closest: Double = .infinity, closestCell = -1
        for k in 0..<120 {
            let t: Double = Double(k) * dt
            let theta: Double = fmod(TAU * sp.beat * t, TAU)
            b.phase = theta
            b.stroke = sp.strokeMid + sp.strokeAmp * cos(theta)
            b.y = y0 - sp.bobRows * Double(meadowCell.height) * sin(theta)
            _ = paintMeadow(painter, land: land, flies: [b], breeze: breeze, time: t, size: size, theme: theme, into: canvas)
            for i in 0..<n {
                let full: Bool = canvas.block[i] >> 24 != 0
                let empty: Bool = !drawn(canvas, i)
                let now: Int8 = full ? 1 : (empty ? 0 : last[i])
                if full { everFull += 1 }
                if k > 0 && now != last[i] {
                    total += 1
                    // This switch and the two before it.
                    let span: Double = Double(k - before[i]) * dt
                    if span < closest { closest = span; closestCell = i }
                    before[i] = latest[i]
                    latest[i] = k
                }
                last[i] = now
            }
        }
        try expect(everFull > 120 * 10, "the monarch hardly drew: \(everFull) full cells over 120 frames")
        try expect(total > 20, "nothing beat: \(total) switches")
        try expect(closest >= beat - dt,
                   "cell (\(closestCell % grid.cols), \(closestCell / grid.cols)) switched empty↔full three times in \(closest) s (a beat is \(beat) s)")
        // The same rule measured in the beat's own windows (the frames whose floor(t · 2.6) agree): at most two
        // switches of any cell in any window, for every species, from several places within a cell, level and
        // banked (review t5, finding 2).
        let offsets: [(Double, Double)] = [(0, 0), (5, 0), (2.5, 4), (-4, 7), (6.2, -3.1)]
        for kind in ButterflyKind.allCases {
            for (dx, dy) in offsets {
                for bank in [0.0, 0.45] {
                    let r = flickerInBeatWindows(kind, dx: dx, dy: dy, bank: bank)
                    try expect(r.full > 120 * 10, "\(kind) at (\(dx), \(dy)) hardly drew: \(r.full) full cells")
                    try expect(r.most <= 2,
                               "\(kind) at (\(dx), \(dy)) bank \(bank): cell (\(r.cell % r.cols), \(r.cell / r.cols)) switched \(r.most) times in beat window \(r.window)")
                }
            }
        }
    }
    check("wingsDoNotFlicker", wingsDoNotFlicker)

    func wingsUseSignedWidth() throws {
        // Review t5, finding 3: the painter draws the model's signed projected width, cos(stroke ± bank). At the bottom
        // of the downstroke (stroke −35°, s = 0.82) the open wings span fewer columns than level (s = 1), and banked
        // there the two wings differ.
        let size = CGSize(width: 640, height: 400)
        let land = Meadowland(random: WebRandom(seed: 2))
        let breeze = calmBreeze(CGRect(origin: .zero, size: size))
        /// Columns holding a block on either side of the body, over the whole butterfly.
        func reach(_ kind: ButterflyKind, stroke: Double, bank: Double) -> (left: Int, right: Int) {
            let b = posed(kind, x: 318.5, y: 199.5)
            b.stroke = stroke
            b.bank = bank
            let c = paintMeadow(MeadowPainter(), land: land, flies: [b], breeze: breeze, size: size, theme: meadowTheme())
            let body = Int(floor(b.x / Double(meadowCell.width)))
            var lo = body, hi = body
            for i in 0..<(c.cols * c.rows) where c.block[i] >> 24 != 0 {
                lo = min(lo, i % c.cols)
                hi = max(hi, i % c.cols)
            }
            return (body - lo, hi - body)
        }
        let down: Double = -35 * Double.pi / 180
        for kind in ButterflyKind.allCases {
            let level = reach(kind, stroke: 0, bank: 0)
            let bottom = reach(kind, stroke: down, bank: 0)
            try expect(bottom.left < level.left && bottom.right < level.right,
                       "\(kind): at the bottom of the downstroke the wings reach \(bottom), level \(level)")
            let banked = reach(kind, stroke: down, bank: 0.3)
            try expect(banked.left != banked.right, "\(kind): banked at the bottom of the downstroke the wings reach \(banked)")
        }
    }
    check("wingsUseSignedWidth", wingsUseSignedWidth)

    func edgeOnIsALine() throws {
        // The left wing forced edge-on (s = cos(bank + stroke) = 0.1), the right one open (bank = stroke): every cell
        // left of the body is a line glyph from | / \ and has no block; the open wing still has its blocks.
        let size = CGSize(width: 520, height: 380)
        let land = Meadowland(random: WebRandom(seed: 2))
        let breeze = calmBreeze(CGRect(origin: .zero, size: size))
        let painter = MeadowPainter()
        let lines: Set<UInt8> = Set("|/\\".map { (c: Character) -> UInt8 in GlyphAtlas.index(c)! })
        for kind in ButterflyKind.allCases {
            let b = posed(kind, x: 266.5, y: 199.5)
            let half: Double = acos(0.1) / 2
            b.bank = half
            b.stroke = half
            let left: Double = b.wings().left
            try expectClose(left, 0.1, tol: 1e-9, "\(kind) left wing s")
            let c = paintMeadow(painter, land: land, flies: [b], breeze: breeze, size: size, theme: meadowTheme())
            let bodyCol = Int(floor(b.x / Double(meadowCell.width)))
            var leftCells = 0, rightBlocks = 0
            for i in 0..<(c.cols * c.rows) where drawn(c, i) {
                let col = i % c.cols
                if col < bodyCol {
                    leftCells += 1
                    let g: String = c.glyph[i] == CellCanvas.noGlyph ? "nothing" : GlyphAtlas.glyphs[Int(c.glyph[i])]
                    try expect(lines.contains(c.glyph[i]), "\(kind): edge-on cell (\(col), \(i / c.cols)) holds \(g)")
                    try expect(c.block[i] >> 24 == 0, "\(kind): edge-on cell (\(col), \(i / c.cols)) has a block")
                } else if col > bodyCol && c.block[i] >> 24 != 0 {
                    rightBlocks += 1
                }
            }
            try expect(leftCells >= 2, "\(kind): the edge-on wing drew \(leftCells) cells")
            try expect(rightBlocks >= 5, "\(kind): the open wing drew \(rightBlocks) block cells")
        }
    }
    check("edgeOnIsALine", edgeOnIsALine)

    func whiteVisibleOnPaper() throws {
        // Review Focus 4: on paper a cabbage white is a pale graphite block, not white on white. Through a whole
        // beat every block it draws is at least 12/255 darker or lighter than the paper.
        let size = CGSize(width: 520, height: 380)
        let land = Meadowland(random: WebRandom(seed: 2))
        let breeze = calmBreeze(CGRect(origin: .zero, size: size))
        let painter = MeadowPainter()
        let b = posed(.cabbageWhite, x: 266.5, y: 199.5)
        let sp = b.species
        let paper: Double = 0.2126 * 247 + 0.7152 * 246 + 0.0722 * 243
        var blocks = 0
        for k in 0..<12 {
            b.phase = TAU * Double(k) / 12
            b.stroke = sp.strokeMid + sp.strokeAmp * cos(b.phase)
            let c = paintMeadow(painter, land: land, flies: [b], breeze: breeze, size: size, theme: meadowTheme(light: true))
            try expect(c.background == SIMD3<Float>(247, 246, 243) / 255, "light background \(c.background)")
            for i in 0..<(c.cols * c.rows) where c.block[i] >> 24 != 0 {
                blocks += 1
                let l: Double = luminance(c.block[i])
                try expect(abs(l - paper) >= 12, "phase \(k): block \(String(c.block[i], radix: 16)) luminance \(l) vs paper \(paper)")
            }
        }
        try expect(blocks >= 12 * 8, "the white drew \(blocks) blocks over a beat")
        // The same on paper in Calm, where everything mixes toward the paper (review t5, finding 9).
        var calmBlocks = 0
        for k in 0..<12 {
            b.phase = TAU * Double(k) / 12
            b.stroke = sp.strokeMid + sp.strokeAmp * cos(b.phase)
            let c = paintMeadow(MeadowPainter(), land: land, flies: [b], breeze: breeze, size: size,
                                theme: meadowTheme(light: true, calm: true))
            for i in 0..<(c.cols * c.rows) where c.block[i] >> 24 != 0 {
                calmBlocks += 1
                let l: Double = luminance(c.block[i])
                try expect(abs(l - paper) >= 12, "Calm, phase \(k): block \(String(c.block[i], radix: 16)) luminance \(l) vs paper \(paper)")
            }
        }
        try expect(calmBlocks >= 12 * 8, "in Calm the white drew \(calmBlocks) blocks over a beat")
    }
    check("whiteVisibleOnPaper", whiteVisibleOnPaper)

    func meadowCalmIsDimmer() throws {
        // Dark Calm: the same scene's ink is dimmer, mean luminance under 0.8 of normal's; the glyphs stay.
        let size = CGSize(width: 900, height: 600)
        let scene = meadowScene(size, seed: 6)
        var flies: [Butterfly] = []
        for (k, kind) in ButterflyKind.allCases.enumerated() {
            let b = posed(kind, x: 120 + 220 * Double(k), y: 180 + 40 * Double(k % 2))
            b.stroke = 0.3
            flies.append(b)
        }
        let normal = paintMeadow(MeadowPainter(), land: scene.land, flies: flies, breeze: scene.breeze, time: 3, size: size,
                                 theme: meadowTheme())
        let calm = paintMeadow(MeadowPainter(), land: scene.land, flies: flies, breeze: scene.breeze, time: 3, size: size,
                               theme: meadowTheme(calm: true))
        var sumN: Double = 0, sumC: Double = 0, n = 0
        for i in 0..<(normal.cols * normal.rows) where normal.glyph[i] != CellCanvas.noGlyph && calm.glyph[i] != CellCanvas.noGlyph {
            sumN += luminance(normal.ink[i])
            sumC += luminance(calm.ink[i])
            n += 1
        }
        try expect(n > 300, "ink cells \(n)")
        try expect(normal.background == SIMD3<Float>(0, 0, 0) && calm.background == normal.background, "calm changed the background")
        try expect(sumC / Double(n) < 0.8 * sumN / Double(n), "calm ink \(sumC / Double(n)) vs normal \(sumN / Double(n))")
        // The glyphs stay: Calm draws a glyph in exactly the cells normal does (review t5, finding 9).
        for i in 0..<(normal.cols * normal.rows) {
            let a: Bool = normal.glyph[i] != CellCanvas.noGlyph, c: Bool = calm.glyph[i] != CellCanvas.noGlyph
            try expect(a == c, "cell (\(i % normal.cols), \(i / normal.cols)): a glyph in normal \(a), in Calm \(c)")
        }
    }
    check("meadowCalmIsDimmer", meadowCalmIsDimmer)

    func stemsLeanWithTheBreeze() throws {
        // A steady 60 pt/s breeze to the right (written at every sample node, weather off, never decayed): once the
        // stems settle, most stem cells between the ground and the head lean right, `/`, and almost none left.
        let size = CGSize(width: 1300, height: 600)
        let scene = meadowScene(size, seed: 8)
        let land = scene.land, breeze = scene.breeze
        let sx: Double = 4 * Double(meadowCell.width), sy: Double = 3 * Double(meadowCell.height)
        var y: Double = 0
        while y <= Double(size.height) + sy {
            var x: Double = 0
            while x <= Double(size.width) + sx {
                breeze.write(x, y, vx: 100, vy: 0)
                x += sx
            }
            y += sy
        }
        let wind: SIMD2<Double> = breeze.sample(400, 560)
        try expectClose(wind.x, 60, tol: 0.5, "the breeze at the stems")
        for _ in 0..<480 { land.step(1.0 / 60.0, breeze: breeze) }
        let c = paintMeadow(MeadowPainter(), land: land, flies: [], breeze: breeze, size: size, theme: meadowTheme())
        let slash = GlyphAtlas.index("/")!, back = GlyphAtlas.index("\\")!
        let cw = Double(meadowCell.width), ch = Double(meadowCell.height)
        var stem = 0, right = 0, left = 0
        for (i, f) in land.flowers.enumerated() where f.kind != .grass && f.rows >= 3 {
            let head: SIMD2<Double> = land.head(i)
            let len: Double = Double(f.rows) * ch
            let headRow = Int(floor(head.y / ch)), baseRow = Int(floor((f.base.y - 0.01) / ch))
            // Between the row under the head (leaves, drooping petals) and the grass in the bottom two rows.
            guard headRow + 2 <= baseRow - 2 else { continue }
            for row in (headRow + 2)...(baseRow - 2) {
                let yc: Double = (Double(row) + 0.5) * ch
                let t: Double = (f.base.y - yc) / len
                let xc: Double = f.base.x + f.tip.x * t * t
                let i = row * c.cols + Int(floor(xc / cw))
                stem += 1
                if c.glyph[i] == slash { right += 1 }
                if c.glyph[i] == back { left += 1 }
            }
        }
        try expect(stem > 40, "stem cells sampled \(stem)")
        try expect(right * 2 > stem, "\(right) of \(stem) stem cells lean right")
        try expect(left * 10 < stem, "\(left) of \(stem) stem cells lean left")
    }
    check("stemsLeanWithTheBreeze", stemsLeanWithTheBreeze)

    func paintAllocatesNothing() throws {
        // After a warm-up frame, 30 more frames of a moving meadow (stems swaying, butterflies flying, one leaving a
        // flower) leave every reusable buffer the painter keeps at the capacity it had.
        let size = CGSize(width: 1300, height: 700)
        let scene = meadowScene(size, seed: 9)
        let land = scene.land
        let breeze = Breeze(bounds: CGRect(origin: .zero, size: size), cell: meadowCell)
        let terrain = Terrain.single(width: Double(size.width), height: Double(size.height))
        let random = WebRandom(seed: 9)
        var flies: [Butterfly] = []
        for (k, kind) in ButterflyKind.allCases.enumerated() {
            flies.append(Butterfly(kind: kind, x: 200 + 260 * Double(k), y: 300, random: random))
        }
        flies[0].state = .nectar
        let painter = MeadowPainter()
        let grid = GridSpec.make(viewportSize: size, cell: meadowCell)
        let canvas = CellCanvas(cols: grid.cols, rows: grid.rows)
        var t: Double = 0
        func frame() {
            for _ in 0..<2 {
                breeze.step(1.0 / 60.0, random: random)
                land.step(1.0 / 60.0, breeze: breeze)
                for b in flies where b.state != .nectar {
                    b.fly(1.0 / 60.0, target: nil, breeze: breeze, terrain: terrain, random: random)
                }
                t += 1.0 / 60.0
            }
            _ = paintMeadow(painter, land: land, flies: flies, breeze: breeze, time: t, size: size, theme: meadowTheme(), into: canvas)
        }
        frame()
        let warm: [Int] = painter.bufferCapacities
        try expect(!warm.isEmpty && warm.allSatisfy { $0 > 0 }, "buffers \(warm)")
        flies[0].state = .fly
        for _ in 0..<30 { frame() }
        try expect(painter.bufferCapacities == warm, "buffers grew: \(warm) -> \(painter.bufferCapacities)")
        // Review t5, finding 4: a full screen in ordinary weather, painted every step once warm, its heads rising
        // and falling across rows as gusts pass, and two flowers clicked into bloom.
        let big = CGSize(width: 2560, height: 1440)
        let land2 = Meadowland(random: WebRandom(seed: 2))
        let terrain2 = Terrain.single(width: 2560, height: 1440)
        land2.layout(terrain: terrain2, cell: meadowCell)
        let breeze2 = Breeze(bounds: CGRect(origin: .zero, size: big), cell: meadowCell)
        let random2 = WebRandom(seed: 2)
        let painter2 = MeadowPainter()
        let grid2 = GridSpec.make(viewportSize: big, cell: meadowCell)
        let canvas2 = CellCanvas(cols: grid2.cols, rows: grid2.rows)
        var t2: Double = 0
        for _ in 0..<60 {
            breeze2.step(1.0 / 60.0, random: random2)
            land2.step(1.0 / 60.0, breeze: breeze2)
            t2 += 1.0 / 60.0
        }
        _ = paintMeadow(painter2, land: land2, flies: [], breeze: breeze2, time: t2, size: big, theme: meadowTheme(), into: canvas2)
        let warm2: [Int] = painter2.bufferCapacities
        for step in 0..<600 {
            if step == 500 || step == 550 { _ = land2.bloom(atX: 400 + Double(step), y: 1400, terrain: terrain2, time: land2.time) }
            breeze2.step(1.0 / 60.0, random: random2)
            land2.step(1.0 / 60.0, breeze: breeze2)
            t2 += 1.0 / 60.0
            _ = paintMeadow(painter2, land: land2, flies: [], breeze: breeze2, time: t2, size: big, theme: meadowTheme(), into: canvas2)
            try expect(painter2.bufferCapacities == warm2, "step \(step): buffers grew: \(warm2) -> \(painter2.bufferCapacities)")
        }
        // The restart's change 4: butterflies added after warm-up, one at a time up to the cap of 16 a screen (the
        // biggest of each species among them), grow nothing either.
        let painter3 = MeadowPainter()
        var flock: [Butterfly] = Array(flies.prefix(4))
        _ = paintMeadow(painter3, land: land2, flies: flock, breeze: breeze2, time: t2, size: big, theme: meadowTheme(), into: canvas2)
        let warm3: [Int] = painter3.bufferCapacities
        for k in 0..<12 {
            let kind: ButterflyKind = ButterflyKind.allCases[k % 4]
            let b = Butterfly(kind: kind, x: 150 + 190 * Double(k), y: 400 + 40 * Double(k % 5), random: random2)
            b.size = 1 + b.species.sizeSpread
            flock.append(b)
            t2 += 1.0 / 60.0
            _ = paintMeadow(painter3, land: land2, flies: flock, breeze: breeze2, time: t2, size: big, theme: meadowTheme(), into: canvas2)
            try expect(painter3.bufferCapacities == warm3,
                       "butterfly \(flock.count) added: buffers grew: \(warm3) -> \(painter3.bufferCapacities)")
        }
    }
    check("paintAllocatesNothing", paintAllocatesNothing)

    func groundRedrawsOnlyWhatMoved() throws {
        // Review t5, finding 5: the cached ground is reused where nothing changed. In still air a warm meadow redraws
        // no column; one plant knocked redraws only the columns around it; and whatever was redrawn, the canvas is
        // what a fresh painter draws.
        let size = CGSize(width: 2560, height: 1440)
        let scene = meadowScene(size, seed: 3)
        let land = scene.land, breeze = scene.breeze
        let painter = MeadowPainter()
        let grid = GridSpec.make(viewportSize: size, cell: meadowCell)
        let canvas = CellCanvas(cols: grid.cols, rows: grid.rows)
        _ = paintMeadow(painter, land: land, flies: [], breeze: breeze, time: 0, size: size, theme: meadowTheme(), into: canvas)
        try expect(painter.groundColumnsRedrawn == grid.cols, "the first frame redrew \(painter.groundColumnsRedrawn) columns")
        for _ in 0..<3 {
            land.step(1.0 / 60.0, breeze: breeze)
            _ = paintMeadow(painter, land: land, flies: [], breeze: breeze, time: 0, size: size, theme: meadowTheme(), into: canvas)
            try expect(painter.groundColumnsRedrawn == 0, "still air redrew \(painter.groundColumnsRedrawn) columns")
        }
        guard let i = land.flowers.indices.first(where: { land.flowers[$0].kind == .daisy && land.flowers[$0].base.x > 1000 }) else {
            throw CheckFailure(detail: "no daisy in the middle")
        }
        land.dip(i, impulse: SIMD2<Double>(60, 0))
        var most = 0
        for frame in 0..<60 {
            land.step(1.0 / 60.0, breeze: breeze)
            _ = paintMeadow(painter, land: land, flies: [], breeze: breeze, time: 0, size: size, theme: meadowTheme(), into: canvas)
            most = max(most, painter.groundColumnsRedrawn)
            let fresh = paintMeadow(MeadowPainter(), land: land, flies: [], breeze: breeze, time: 0, size: size, theme: meadowTheme())
            for k in 0..<(grid.cols * grid.rows) {
                let same: Bool = canvas.glyph[k] == fresh.glyph[k] && canvas.ink[k] == fresh.ink[k] && canvas.block[k] == fresh.block[k]
                    && canvas.overGlyph[k] == fresh.overGlyph[k]
                if !same {
                    // A cell may differ only where a plant moved less than the 0.05-cell redraw threshold.
                    try expect(abs(Double(k % grid.cols) * Double(meadowCell.width) - land.flowers[i].base.x) < 200,
                               "frame \(frame): cell (\(k % grid.cols), \(k / grid.cols)) differs from a fresh paint")
                }
            }
        }
        try expect(most > 0 && most <= 30, "a knocked daisy redrew up to \(most) of \(grid.cols) columns")
    }
    check("groundRedrawsOnlyWhatMoved", groundRedrawsOnlyWhatMoved)

    func relayoutRedrawsTheGarden() throws {
        // Review t5, finding 7: the same land laid out again on the same screen (same count, same top row, perhaps)
        // never keeps the old garden. The land is laid out twice between paints (as a display change can), and each
        // time the painter that drew the garden before last draws what a fresh one does.
        let size = CGSize(width: 2560, height: 1440)
        let land = Meadowland(random: WebRandom(seed: 2))
        let terrain = Terrain.single(width: 2560, height: 1440)
        let breeze = calmBreeze(CGRect(origin: .zero, size: size))
        let painter = MeadowPainter()
        let grid = GridSpec.make(viewportSize: size, cell: meadowCell)
        let canvas = CellCanvas(cols: grid.cols, rows: grid.rows)
        for trial in 0..<12 {
            land.layout(terrain: terrain, cell: meadowCell)
            land.layout(terrain: terrain, cell: meadowCell)
            _ = paintMeadow(painter, land: land, flies: [], breeze: breeze, size: size, theme: meadowTheme(), into: canvas)
            let fresh = paintMeadow(MeadowPainter(), land: land, flies: [], breeze: breeze, size: size, theme: meadowTheme())
            var differ = 0
            for k in 0..<(grid.cols * grid.rows) where canvas.glyph[k] != fresh.glyph[k] || canvas.ink[k] != fresh.ink[k] {
                differ += 1
            }
            try expect(differ == 0, "layout \(trial): \(differ) cells kept from the last garden")
        }
    }
    check("relayoutRedrawsTheGarden", relayoutRedrawsTheGarden)

    func plantsStayOnTheirScreen() throws {
        // Review t5, finding 6: a meadow laid out on the upper screen draws nothing on the screen directly below it.
        let upper = Terrain.single(width: 2560, height: 1440)
        let land = Meadowland(random: WebRandom(seed: 5))
        land.layout(terrain: upper, cell: meadowCell)
        let breeze = calmBreeze(CGRect(x: 0, y: 0, width: 2560, height: 2880))
        let size = CGSize(width: 2560, height: 1440)
        let grid = GridSpec.make(viewportSize: size, cell: meadowCell)
        let c = CellCanvas(cols: grid.cols, rows: grid.rows)
        c.clear()
        MeadowPainter().paint(land: land, butterflies: [], breeze: breeze, time: 0, viewport: CGRect(x: 0, y: 1440, width: 2560, height: 1440),
                              grid: grid, theme: meadowTheme(), into: c)
        var drawnCells = 0
        for i in 0..<(c.cols * c.rows) where drawn(c, i) || c.overGlyph[i] != CellCanvas.noGlyph { drawnCells += 1 }
        try expect(drawnCells == 0, "the lower screen holds \(drawnCells) plant cells")
    }
    check("plantsStayOnTheirScreen", plantsStayOnTheirScreen)
}

/// The painter as a habitat, for drawing through the renderer before the meadow world exists (t3 wraps it for real).
private final class MeadowScene: CellPainter {
    let land: Meadowland
    let flies: [Butterfly]
    let breeze: Breeze
    let painter = MeadowPainter()
    /// The canvas last painted, as the renderer handed it over.
    private(set) var canvas: CellCanvas?

    init(land: Meadowland, flies: [Butterfly], breeze: Breeze) {
        self.land = land
        self.flies = flies
        self.breeze = breeze
    }

    var kind: HabitatKind { .web }
    var time: Double { 0 }
    var stepCount: Int { 0 }
    func layout(terrain: Terrain, cell: CGSize, settings: Settings) {}
    func step(_ dt: Double) {}
    func pointerMoved(_ x: Double, _ y: Double) {}
    func pointerLeft() {}
    func pointerDown(_ x: Double, _ y: Double) {}
    func update(settings: Settings) {}
    func settle() {}

    func paint(viewport: CGRect, grid: GridSpec, theme: ThemeParams, into canvas: CellCanvas) {
        painter.paint(land: land, butterflies: flies, breeze: breeze, time: 0, viewport: viewport, grid: grid, theme: theme,
                      into: canvas)
        self.canvas = canvas
    }
}

func meadowRenderChecks() {
    guard let device = MTLCreateSystemDefaultDevice() else { return }

    func meadowComposeDraws() throws {
        // A fixed scene through `encode(habitat:)`: the monarch's body cell shows its block colour, and a flower head
        // cell has pixels in the head's ink.
        let size = CGSize(width: 400, height: 300)
        let scale: CGFloat = 2
        let w = Int(size.width * scale), h = Int(size.height * scale)
        let scene = meadowScene(size, seed: 4)
        let monarch = posed(.monarch, x: 201.5, y: 66.5)
        let sim = MeadowScene(land: scene.land, flies: [monarch], breeze: scene.breeze)
        let r = try OceanRenderer(device: device)
        let vp = try r.makeViewport(pointSize: size, scale: scale, cell: meadowCell)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OceanRenderer.outputFormat, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .managed
        guard let target = r.device.makeTexture(descriptor: d), let cb = r.queue.makeCommandBuffer() else {
            throw CheckFailure(detail: "no frame target")
        }
        vp.encode(habitat: sim, theme: meadowTheme(), target: target, commandBuffer: cb)
        let blit = cb.makeBlitCommandEncoder()!
        blit.synchronize(resource: target)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        target.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        guard let canvas = sim.canvas else { throw CheckFailure(detail: "the scene was never painted") }

        let cw = Int(meadowCell.width * scale), ch = Int(meadowCell.height * scale)
        // Pixels of cell (col, row) within 2/255 of a packed colour (BGRA bytes).
        func pixels(_ col: Int, _ row: Int, near v: UInt32) -> Int {
            let want: SIMD4<Double> = unpack(v)
            var n = 0
            for y in (row * ch)..<((row + 1) * ch) {
                for x in (col * cw)..<((col + 1) * cw) {
                    let i = (y * w + x) * 4
                    let dr: Double = abs(Double(bytes[i + 2]) - want.x)
                    let dg: Double = abs(Double(bytes[i + 1]) - want.y)
                    let db: Double = abs(Double(bytes[i]) - want.z)
                    if dr <= 2 && dg <= 2 && db <= 2 { n += 1 }
                }
            }
            return n
        }
        let bc = Int(floor(monarch.x / Double(meadowCell.width))), br = Int(floor(monarch.y / Double(meadowCell.height)))
        let body = canvas.block[br * canvas.cols + bc]
        try expect(body >> 24 != 0, "no block on the body cell (\(bc), \(br))")
        let onBlock = pixels(bc, br, near: body)
        try expect(onBlock * 5 > cw * ch, "body cell: \(onBlock) of \(cw * ch) pixels in the block colour \(String(body, radix: 16))")

        let heads: [FlowerKind] = [.clover, .dandelion, .mustard, .coneflower, .milkweed, .fennel]
        guard let fi = scene.land.flowers.indices.first(where: { heads.contains(scene.land.flowers[$0].kind) }) else {
            throw CheckFailure(detail: "no flower with a plain head")
        }
        let head: SIMD2<Double> = scene.land.head(fi)
        let hc = Int(floor(head.x / Double(meadowCell.width))), hr = Int(floor(head.y / Double(meadowCell.height)))
        let hi = hr * canvas.cols + hc
        try expect(canvas.glyph[hi] != CellCanvas.noGlyph, "\(scene.land.flowers[fi].kind) head cell (\(hc), \(hr)) is empty")
        let inked = pixels(hc, hr, near: canvas.ink[hi] | 0xff00_0000)
        try expect(inked > 4, "head cell: \(inked) pixels in the ink \(String(canvas.ink[hi], radix: 16))")
    }
    check("meadowComposeDraws", meadowComposeDraws)
}

// ── t5 restart: closed wings, the drawn size in flight, the ground cache's key, adding butterflies ──

/// What one posed butterfly draws: block cells, glyph-only cells off the body's column, the columns its blocks reach
/// on either side of the body, and the mean colour of its blocks.
private struct Drawing {
    var blocks = 0, bare = 0, left = 0, right = 0
    var mean = SIMD3<Double>(0, 0, 0)
}

private func drawing(_ kind: ButterflyKind, stroke: Double, bank: Double = 0, light: Bool = false) -> Drawing {
    let size = CGSize(width: 640, height: 400)
    let land = Meadowland(random: WebRandom(seed: 2))
    let b = posed(kind, x: 318.5, y: 199.5)
    b.stroke = stroke
    b.bank = bank
    let c = paintMeadow(MeadowPainter(), land: land, flies: [b], breeze: calmBreeze(CGRect(origin: .zero, size: size)),
                        size: size, theme: meadowTheme(light: light))
    let body = Int(floor(b.x / Double(meadowCell.width)))
    var d = Drawing()
    var sum = SIMD3<Double>(0, 0, 0)
    for i in 0..<(c.cols * c.rows) where drawn(c, i) {
        let col = i % c.cols
        if c.block[i] >> 24 != 0 {
            d.blocks += 1
            let v: SIMD4<Double> = unpack(c.block[i])
            sum += SIMD3<Double>(v.x, v.y, v.z)
            if col < body { d.left = max(d.left, body - col) }
            if col > body { d.right = max(d.right, col - body) }
        } else if col != body {
            d.bare += 1
        }
    }
    if d.blocks > 0 { d.mean = sum / Double(d.blocks) }
    return d
}

func meadowRestartChecks() {
    let deg: Double = Double.pi / 180

    func closedWingsShowTheUnderside() throws {
        // The restart's change 1: seen closed (stroke 90°, at rest) and near the clap (78°), a butterfly shows the
        // underside of its folded wings as a solid shape, never a stick or loose outlines: blocks, not bare glyphs;
        // at least a third of the open pose's blocks, reaching at least 40 % of the open reach; in the underside's
        // colours (a different mean block colour from the open pose; the morpho's brown, not its blue). And through
        // every stroke from level to closed it never shrinks below a third of the open pose's blocks.
        for light in [false, true] {
            for kind in ButterflyKind.allCases {
                let open = drawing(kind, stroke: 0, light: light)
                let openReach: Int = max(open.left, open.right)
                let shut: [(String, Double)] = [("clap", 78 * deg), ("closed", 90 * deg)]
                for (name, stroke) in shut {
                    let d = drawing(kind, stroke: stroke, light: light)
                    let tag = "\(kind) \(name) \(light ? "paper" : "dark")"
                    try expect(3 * d.blocks >= open.blocks, "\(tag): \(d.blocks) blocks, open \(open.blocks)")
                    try expect(2 * d.bare <= d.blocks, "\(tag): \(d.bare) bare glyphs beside \(d.blocks) blocks")
                    try expect(10 * max(d.left, d.right) >= 4 * openReach,
                               "\(tag): reaches \(d.left) / \(d.right) columns, open \(openReach)")
                    try expect(simd_length(d.mean - open.mean) > 20,
                               "\(tag): mean block \(d.mean) is the open pose's \(open.mean)")
                    if kind == .morpho {
                        try expect(d.mean.x > d.mean.z, "\(tag): the morpho's underside is not brown: \(d.mean)")
                    }
                }
                for step in 0...45 {
                    let d = drawing(kind, stroke: Double(step) * 2 * deg, light: light)
                    try expect(3 * d.blocks >= open.blocks,
                               "\(kind) \(light ? "paper" : "dark") at stroke \(2 * step)°: \(d.blocks) blocks, open \(open.blocks)")
                }
            }
        }
    }
    check("closedWingsShowTheUnderside", closedWingsShowTheUnderside)

    func oneButterflyFitsThePreview() throws {
        // The Settings preview, 340 × 150 pt at its 8-pt cell: one butterfly of each species at its biggest, open,
        // at the bottom of the downstroke, banked or closed, draws no more columns and rows than the preview has
        // (measured on a taller canvas, so nothing is clipped while measuring).
        let preview = GridSpec.make(viewportSize: CGSize(width: 340, height: 150), cell: GridSpec.cell(forWidth: 340))
        let size = CGSize(width: 340, height: 450)
        let cell = GridSpec.cell(forWidth: 340)
        let grid = GridSpec.make(viewportSize: size, cell: cell)
        let land = Meadowland(random: WebRandom(seed: 2))
        for kind in ButterflyKind.allCases {
            let poses: [(Double, Double)] = [(0, 0), (-35 * deg, 0), (25 * deg, 40 * deg), (78 * deg, 0), (90 * deg, 0)]
            for (stroke, bank) in poses {
                let b = posed(kind, x: 170, y: 225)
                b.scale = Double(cell.width) / 13
                b.size = 1 + b.species.sizeSpread
                b.stroke = stroke
                b.bank = bank
                let c = CellCanvas(cols: grid.cols, rows: grid.rows)
                c.clear()
                MeadowPainter().paint(land: land, butterflies: [b], breeze: calmBreeze(CGRect(origin: .zero, size: size)),
                                      time: 0, viewport: CGRect(origin: .zero, size: size), grid: grid,
                                      theme: meadowTheme(), into: c)
                var c0 = Int.max, c1 = Int.min, r0 = Int.max, r1 = Int.min, cells = 0
                for i in 0..<(c.cols * c.rows) where drawn(c, i) || c.overGlyph[i] != CellCanvas.noGlyph {
                    cells += 1
                    c0 = min(c0, i % c.cols); c1 = max(c1, i % c.cols)
                    r0 = min(r0, i / c.cols); r1 = max(r1, i / c.cols)
                }
                try expect(cells > 20, "\(kind): drew \(cells) cells")
                try expect(c0 > 0 && r0 > 0 && c1 < c.cols - 1 && r1 < c.rows - 1, "\(kind): clipped while measuring")
                try expect(c1 - c0 + 1 <= preview.cols && r1 - r0 + 1 <= preview.rows,
                           "\(kind) stroke \(stroke) bank \(bank): \(c1 - c0 + 1) × \(r1 - r0 + 1) cells, the preview \(preview.cols) × \(preview.rows)")
            }
        }
    }
    check("oneButterflyFitsThePreview", oneButterflyFitsThePreview)

    func subPixelRelayoutRedraws() throws {
        // Review t5, finding 7 (re-check): the same garden laid out half a point lower changes stems' base rows; the
        // painter that drew it before redraws what a fresh painter draws.
        let size = CGSize(width: 2560, height: 1440)
        let grid = GridSpec.make(viewportSize: size, cell: meadowCell)
        let breeze = calmBreeze(CGRect(origin: .zero, size: size))
        for seed in [UInt64(2), 5, 7] {
            let painter = MeadowPainter()
            let canvas = CellCanvas(cols: grid.cols, rows: grid.rows)
            for (k, y) in [0.0, 0.5, 0.0, 0.25].enumerated() {
                let land = Meadowland(random: WebRandom(seed: seed))
                land.layout(terrain: Terrain(rects: [CGRect(x: 0, y: y, width: 2560, height: 1368)]), cell: meadowCell)
                _ = paintMeadow(painter, land: land, flies: [], breeze: breeze, size: size, theme: meadowTheme(), into: canvas)
                let fresh = paintMeadow(MeadowPainter(), land: land, flies: [], breeze: breeze, size: size, theme: meadowTheme())
                var differ = 0
                for i in 0..<(grid.cols * grid.rows)
                where canvas.glyph[i] != fresh.glyph[i] || canvas.ink[i] != fresh.ink[i] || canvas.block[i] != fresh.block[i] {
                    differ += 1
                }
                try expect(differ == 0, "seed \(seed), layout \(k) at y \(y): \(differ) cells kept from the last garden")
            }
        }
    }
    check("subPixelRelayoutRedraws", subPixelRelayoutRedraws)
}

// ── t5 restart, fix round 1: low flowers keep their reach; the clap reads as a butterfly ──
// (Its `nothingDrawnLeavesTheScreen`, with `drawingStaysOnScreen` above, was retired in restart 2: the director let
// butterflies flutter partly off screen, 2026-11-20.)

/// The flight's peak stroke (the clap): the stroke's mid plus its amplitude.
private func peakStroke(_ kind: ButterflyKind) -> Double {
    let sp = ButterflySpecies.of(kind)
    return sp.strokeMid + sp.strokeAmp
}

/// One posed butterfly's blocks, each with its column offset from the body and its colour.
private func blockCells(_ kind: ButterflyKind, stroke: Double, bank: Double = 0, light: Bool = false)
    -> [(dc: Int, rgb: SIMD3<Double>, cell: Int)] {
    let size = CGSize(width: 640, height: 400)
    let land = Meadowland(random: WebRandom(seed: 2))
    let b = posed(kind, x: 318.5, y: 199.5)
    b.stroke = stroke
    b.bank = bank
    let c = paintMeadow(MeadowPainter(), land: land, flies: [b], breeze: calmBreeze(CGRect(origin: .zero, size: size)),
                        size: size, theme: meadowTheme(light: light))
    let body = Int(floor(b.x / Double(meadowCell.width)))
    var out: [(dc: Int, rgb: SIMD3<Double>, cell: Int)] = []
    for i in 0..<(c.cols * c.rows) where c.block[i] >> 24 != 0 {
        let v: SIMD4<Double> = unpack(c.block[i])
        out.append((dc: i % c.cols - body, rgb: SIMD3<Double>(v.x, v.y, v.z), cell: i))
    }
    return out
}

private func meanColour(_ cells: [(dc: Int, rgb: SIMD3<Double>, cell: Int)]) -> SIMD3<Double> {
    var sum = SIMD3<Double>(0, 0, 0)
    for c in cells { sum += c.rgb }
    return cells.isEmpty ? sum : sum / Double(cells.count)
}

func meadowRestartFixChecks() {
    let deg: Double = Double.pi / 180

    func lowFlowersKeepTheirReach() throws {
        // At a one-row flower the flight still brings the butterfly to the head (the flight's point, within half a
        // cell, as `flowerSeekersReachLowHeads` holds it), on a big monitor and a laptop at their own cells.
        for size in [CGSize(width: 2560, height: 1440), CGSize(width: 1440, height: 900)] {
            let cell: CGSize = GridSpec.cell(forWidth: Double(size.width))
            let w: Double = Double(size.width), h: Double = Double(size.height)
            let head = SIMD2<Double>(w / 2, h - Double(cell.height))
            let field = Terrain.single(width: w, height: h)
            for kind in ButterflyKind.allCases {
                let random = WebRandom(seed: 41)
                let b = Butterfly(kind: kind, x: w / 2 - 200, y: h / 2, random: random)
                b.scale = Double(cell.width) / 13
                b.state = .approach
                let log = flyLog(b, seconds: 20, terrain: field, random: random) { _ in head }
                var closest: Double = .infinity
                for k in 0..<log.count { closest = min(closest, simd_length(SIMD2<Double>(log.x[k], log.y[k]) - head)) }
                try expect(closest <= 0.5 * Double(cell.width), "\(kind) on \(Int(w))×\(Int(h)): closest \(closest) pt to the head")
            }
        }
    }
    check("lowFlowersKeepTheirReach", lowFlowersKeepTheirReach)

    func clapReadsAsAButterfly() throws {
        // Fix round 1, item 2 (review t5 restart, finding 5): at the strokes flight reaches (75° to each species'
        // peak), the clap is the folded side profile: the wing pair on the side it faces, solid, in the underside's
        // colours, the far pair tucked behind it (at most a sixth of the blocks off the body on the far side).
        // The face change from upper side to underside spreads over several degrees: in 1° steps no step turns
        // more than a third of the blocks, and at least three steps show both faces.
        for light in [false, true] {
            for kind in ButterflyKind.allCases {
                let open = blockCells(kind, stroke: 0, light: light)
                let under = meanColour(blockCells(kind, stroke: 90 * deg, light: light))
                let upper = meanColour(open)
                let tag = "\(kind) \(light ? "paper" : "dark")"
                let peak: Double = peakStroke(kind)
                for stroke in [75 * deg, peak] {
                    let cells = blockCells(kind, stroke: stroke, light: light)
                    let near: Int = cells.filter { $0.dc > 0 }.count, far: Int = cells.filter { $0.dc < 0 }.count
                    try expect(near >= 5 * far && near > 0,
                               "\(tag) at \(Int((stroke / deg).rounded()))°: \(near) blocks on the near side, \(far) on the far")
                    try expect(3 * cells.count >= open.count, "\(tag) at \(stroke / deg)°: \(cells.count) blocks, open \(open.count)")
                    let m: SIMD3<Double> = meanColour(cells)
                    try expect(simd_length(m - under) < simd_length(m - upper),
                               "\(tag) at \(stroke / deg)°: mean block \(m) is nearer the upper side \(upper) than the underside \(under)")
                }
                // Share of blocks nearer the underside's colour than the upper side's, 50° to the peak in 1° steps.
                var shares: [Double] = []
                var s: Double = 50 * deg
                while s <= peak + 1e-9 {
                    let cells = blockCells(kind, stroke: s, light: light)
                    let u: Int = cells.filter { simd_length($0.rgb - under) < simd_length($0.rgb - upper) }.count
                    shares.append(cells.isEmpty ? 0 : Double(u) / Double(cells.count))
                    s += deg
                }
                var mixed = 0, jump: Double = 0
                for k in shares.indices {
                    if shares[k] > 0.15 && shares[k] < 0.85 { mixed += 1 }
                    if k > 0 { jump = max(jump, abs(shares[k] - shares[k - 1])) }
                }
                try expect(jump <= 1.0 / 3.0, "\(tag): the face changes \(jump) of the blocks in one degree (shares \(shares))")
                try expect(mixed >= 3, "\(tag): only \(mixed) one-degree steps show both faces (shares \(shares))")
            }
        }
        // The morpho's flash stays: blue open, brown at its clap.
        let blue = meanColour(blockCells(.morpho, stroke: 0)), brown = meanColour(blockCells(.morpho, stroke: peakStroke(.morpho)))
        try expect(blue.z > blue.x && brown.x > brown.z, "the morpho's flash: open \(blue), clap \(brown)")
    }
    check("clapReadsAsAButterfly", clapReadsAsAButterfly)
}

// ── t5 restart 2, simplified: the body is drawn where it flies; the clap turns over at every bank ──

/// Blocks of a posed butterfly by canvas cell, with their colours (see `blockCells`).
private func blockMap(_ kind: ButterflyKind, stroke: Double, bank: Double, heading: Double, light: Bool)
    -> [Int: SIMD3<Double>] {
    let size = CGSize(width: 640, height: 400)
    let land = Meadowland(random: WebRandom(seed: 2))
    let b = posed(kind, x: 318.5, y: 199.5)
    b.stroke = stroke
    b.bank = bank
    b.heading = heading
    let c = paintMeadow(MeadowPainter(), land: land, flies: [b], breeze: calmBreeze(CGRect(origin: .zero, size: size)),
                        size: size, theme: meadowTheme(light: light))
    var out: [Int: SIMD3<Double>] = [:]
    for i in 0..<(c.cols * c.rows) where c.block[i] >> 24 != 0 {
        let v: SIMD4<Double> = unpack(c.block[i])
        out[i] = SIMD3<Double>(v.x, v.y, v.z)
    }
    return out
}

/// The share of block cells (of those in either) that change in one tiny step of a pose: present in one and not the
/// other, or turned to a clearly different colour (more than 40 of 255 apart).
private func flipShare(_ a: [Int: SIMD3<Double>], _ b: [Int: SIMD3<Double>]) -> Double {
    var changed = 0
    for (i, ca) in a {
        if let cb = b[i] {
            if simd_length(ca - cb) > 40 { changed += 1 }
        } else {
            changed += 1
        }
    }
    var union: Int = a.count
    for i in b.keys where a[i] == nil {
        changed += 1
        union += 1
    }
    let total: Int = max(1, union)
    return Double(changed) / Double(total)
}

func meadowRestart2Checks() {
    let deg: Double = Double.pi / 180
    let eight: UInt8 = GlyphAtlas.index("8")!

    /// Whether the thorax (the body's `8`) is drawn within a cell of (x, y) on `c` (grid at the origin, `cell` pt).
    func thoraxAt(_ c: CellCanvas, _ x: Double, _ y: Double, cell: CGSize) -> Bool {
        let bc: Int = Int(floor(x / Double(cell.width))), br: Int = Int(floor(y / Double(cell.height)))
        for r in (br - 1)...(br + 1) where r >= 0 && r < c.rows {
            for col in (bc - 1)...(bc + 1) where col >= 0 && col < c.cols {
                if c.glyph[r * c.cols + col] == eight { return true }
            }
        }
        return false
    }

    func clapTurnsOverAtEveryBank() throws {
        // Restart 2, item 3 (re-check finding 5): at banks of 0°, 15° and 30° either way, from 50° to each species'
        // peak stroke, no hundredth of a degree turns more than a tenth of the blocks over (the colour change from
        // upper side to underside is a blend, not a switch where the signed width crosses zero), and the face changes
        // over several degrees: at least four half-degree samples show both faces.
        for light in [false, true] {
            for kind in ButterflyKind.allCases {
                let upper = meanColour(blockCells(kind, stroke: 0, light: light))
                let under = meanColour(blockCells(kind, stroke: 90 * deg, light: light))
                let peak: Double = peakStroke(kind)
                let banks: [Double] = [0, 15 * deg, 30 * deg, -15 * deg, -30 * deg]
                for bank in banks {
                    let tag = "\(kind) \(light ? "paper" : "dark") bank \(Int((bank / deg).rounded()))°"
                    var mixed = 0
                    var s: Double = 50 * deg
                    while s <= peak + 1e-9 {
                        let a = blockMap(kind, stroke: s, bank: bank, heading: 1.5 * Double.pi, light: light)
                        let b = blockMap(kind, stroke: s + 0.01 * deg, bank: bank, heading: 1.5 * Double.pi, light: light)
                        let flip: Double = flipShare(a, b)
                        try expect(flip <= 0.1, "\(tag): \(flip) of the blocks turn over between \(s / deg)° and \(s / deg + 0.01)°")
                        let u: Int = a.values.filter { simd_length($0 - under) < simd_length($0 - upper) }.count
                        let share: Double = a.isEmpty ? 0 : Double(u) / Double(a.count)
                        if share > 0.15 && share < 0.85 { mixed += 1 }
                        s += 0.5 * deg
                    }
                    try expect(mixed >= 4, "\(tag): only \(mixed) half-degree samples show both faces")
                }
                // Where the signed width crosses zero at a bank (the re-check's 59.99° → 60.01° at 30°).
                let crossings: [Double] = [15 * deg, 30 * deg, -30 * deg]
                for bank in crossings {
                    let c: Double = 90 * deg - abs(bank)
                    let a = blockMap(kind, stroke: c - 0.01 * deg, bank: bank, heading: 1.5 * Double.pi, light: light)
                    let b = blockMap(kind, stroke: c + 0.01 * deg, bank: bank, heading: 1.5 * Double.pi, light: light)
                    let flip: Double = flipShare(a, b)
                    try expect(flip <= 0.1, "\(kind) \(light ? "paper" : "dark") bank \(bank / deg)°: \(flip) of the blocks turn over where the signed width crosses zero")
                }
            }
        }
    }
    check("clapTurnsOverAtEveryBank", clapTurnsOverAtEveryBank)

    func foldedSideNeverFlips() throws {
        // Restart 2, item 3: at the clap the folded pair moves from one side of the body to the other as the bank
        // changes over several degrees, never in one step: from −10° to 10° of bank in steps of a twentieth of a
        // degree, no step changes more than a third of the blocks (as `clapReadsAsAButterfly` holds the face; one
        // column of a narrow clap is a sixth of its blocks, a jump to the other side all of them), facing up, up-left
        // and up-right.
        for kind in ButterflyKind.allCases {
            let stroke: Double = peakStroke(kind) - 1 * deg
            let headings: [Double] = [1.5 * Double.pi, 1.25 * Double.pi, 1.75 * Double.pi]
            for heading in headings {
                var bank: Double = -10 * deg
                var last = blockMap(kind, stroke: stroke, bank: bank, heading: heading, light: false)
                while bank < 10 * deg {
                    bank += 0.05 * deg
                    let next = blockMap(kind, stroke: stroke, bank: bank, heading: heading, light: false)
                    let flip: Double = flipShare(last, next)
                    try expect(flip <= 1.0 / 3.0, "\(kind) heading \(Int((heading / deg).rounded()))°: \(flip) of the blocks change in the step to bank \(bank / deg)°")
                    last = next
                }
            }
        }
    }
    check("foldedSideNeverFlips", foldedSideNeverFlips)

    func bodyDrawnWhereItFlies() throws {
        // Restart 2: the body is drawn at the flight's point, on every screen. (a) The 340 × 150 preview, one
        // butterfly of each species flying freely in weather; (b) pursuits of a one-row flower's head on a big
        // monitor and a laptop. Every 5th step the thorax is drawn within a cell of (x, y).
        let preview = CGSize(width: 340, height: 150)
        var runs: [(CGSize, SIMD2<Double>?)] = [(preview, nil)]
        for size in [CGSize(width: 2560, height: 1440), CGSize(width: 1440, height: 900)] {
            let cell: CGSize = GridSpec.cell(forWidth: Double(size.width))
            runs.append((size, SIMD2<Double>(Double(size.width) / 2, Double(size.height) - Double(cell.height))))
        }
        for (size, head) in runs {
            let cell: CGSize = GridSpec.cell(forWidth: Double(size.width))
            let w: Double = Double(size.width), h: Double = Double(size.height)
            let field = Terrain.single(width: w, height: h)
            let grid = GridSpec.make(viewportSize: size, cell: cell)
            let canvas = CellCanvas(cols: grid.cols, rows: grid.rows)
            let painter = MeadowPainter()
            let land = Meadowland(random: WebRandom(seed: 3))
            for (i, kind) in ButterflyKind.allCases.enumerated() {
                for seed in [UInt64(7), 1] {
                    let random = WebRandom(seed: seed * 23 + UInt64(i))
                    let b = Butterfly(kind: kind, x: w / 2, y: h / 2, random: random)
                    b.scale = Double(cell.width) / 13
                    if seed == 1 { b.size = 1 + b.species.sizeSpread }
                    b.fitDrawing(to: size)
                    let air = Breeze(bounds: field.bounds, cell: cell)
                    air.ambient = head == nil
                    for step in 0..<(30 * 60) {
                        air.step(flightDt, random: random)
                        if head != nil { b.state = .approach }
                        b.fly(flightDt, target: head, breeze: air, terrain: field, random: random)
                        guard step % 5 == 0 else { continue }
                        canvas.clear()
                        painter.paint(land: land, butterflies: [b], breeze: air, time: Double(step) * flightDt,
                                      viewport: CGRect(origin: .zero, size: size), grid: grid, theme: meadowTheme(), into: canvas)
                        try expect(thoraxAt(canvas, b.x, b.y, cell: cell),
                                   "\(kind) seed \(seed) on \(Int(w))×\(Int(h))\(head == nil ? "" : " after a one-row head"), step \(step): no thorax drawn within a cell of the body at (\(b.x), \(b.y))")
                    }
                }
            }
        }
    }
    check("bodyDrawnWhereItFlies", bodyDrawnWhereItFlies)

    func previewSizeFitsEveryLean() throws {
        // Restart 2, item 2: a screen too small for full-size butterflies gets a smaller size, chosen at layout, so
        // one whole butterfly fits it at any lean the painter draws: on the 340 × 150 preview, each species at its
        // biggest, fitted, painted leaning either way (heading and pitch) in the open, downstroke, banked, clap and
        // closed poses, spans no more whole columns and rows than the preview has. Desktop screens keep full size.
        let preview = CGSize(width: 340, height: 150)
        let cell = GridSpec.cell(forWidth: 340)
        let cols: Int = Int(floor(340 / Double(cell.width))), rows: Int = Int(floor(150 / Double(cell.height)))
        let size = CGSize(width: 480, height: 450)
        let grid = GridSpec.make(viewportSize: size, cell: cell)
        let land = Meadowland(random: WebRandom(seed: 2))
        for kind in ButterflyKind.allCases {
            let desktops: [CGSize] = [CGSize(width: 2560, height: 1440), CGSize(width: 1440, height: 900),
                                      CGSize(width: 1800, height: 1169)]
            for screen in desktops {
                let big = Butterfly(kind: kind, x: 0, y: 0, random: WebRandom(seed: 1))
                big.scale = GridSpec.cell(forWidth: Double(screen.width)).width / 13
                big.size = 1 + big.species.sizeSpread
                big.fitDrawing(to: screen)
                try expectClose(big.fit, 1, tol: 1e-12, "\(kind) on \(Int(screen.width))×\(Int(screen.height)) is drawn at \(big.fit) of its size")
            }
            let poses: [(Double, Double)] = [(0, 0), (-35 * deg, 0), (25 * deg, 40 * deg), (78 * deg, 0), (78 * deg, 20 * deg),
                                             (90 * deg, 0)]
            for (stroke, bank) in poses {
                let leans: [(Double, Double)] = [(0, 0), (Double.pi, 0), (0, 0.6), (0, -0.6), (Double.pi, 0.6), (Double.pi, -0.6)]
                for (heading, pitch) in leans {
                    let b = posed(kind, x: 240, y: 225)
                    b.scale = Double(cell.width) / 13
                    b.size = 1 + b.species.sizeSpread
                    b.fitDrawing(to: preview)
                    b.stroke = stroke
                    b.bank = bank
                    b.heading = heading
                    b.pitch = pitch
                    let c = CellCanvas(cols: grid.cols, rows: grid.rows)
                    c.clear()
                    MeadowPainter().paint(land: land, butterflies: [b], breeze: calmBreeze(CGRect(origin: .zero, size: size)),
                                          time: 0, viewport: CGRect(origin: .zero, size: size), grid: grid,
                                          theme: meadowTheme(), into: c)
                    var c0 = Int.max, c1 = Int.min, r0 = Int.max, r1 = Int.min, cells = 0
                    for i in 0..<(c.cols * c.rows) where drawn(c, i) || c.overGlyph[i] != CellCanvas.noGlyph {
                        cells += 1
                        c0 = min(c0, i % c.cols); c1 = max(c1, i % c.cols)
                        r0 = min(r0, i / c.cols); r1 = max(r1, i / c.cols)
                    }
                    let tag = "\(kind) stroke \(Int((stroke / deg).rounded()))° bank \(Int((bank / deg).rounded()))° heading \(Int((heading / deg).rounded()))° pitch \(pitch)"
                    try expect(cells > 20, "\(tag): drew \(cells) cells")
                    try expect(c0 > 0 && r0 > 0 && c1 < c.cols - 1 && r1 < c.rows - 1, "\(tag): clipped while measuring")
                    try expect(c1 - c0 + 1 <= cols && r1 - r0 + 1 <= rows,
                               "\(tag) at \(b.fit) of its size: \(c1 - c0 + 1) × \(r1 - r0 + 1) cells, the preview \(cols) × \(rows)")
                }
            }
        }
    }
    check("previewSizeFitsEveryLean", previewSizeFitsEveryLean)
}
