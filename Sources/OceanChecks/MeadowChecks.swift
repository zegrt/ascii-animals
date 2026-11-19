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
        // flowers: the ground doesn't push it off. Within half a cell of the head, from anywhere above.
        let field = Terrain.single(width: 1800, height: 1169)
        var head: SIMD2<Double>? = nil
        for seed in UInt64(1)...UInt64(20) where head == nil {
            let land = Meadowland(random: WebRandom(seed: seed))
            land.layout(terrain: field, cell: meadowCell)
            if let i = land.flowers.indices.first(where: { land.flowers[$0].kind != .grass && land.flowers[$0].rows == 1 }) {
                head = land.head(i)
            }
        }
        guard let h = head else { throw CheckFailure(detail: "no one-row flower in 20 layouts") }
        try expectClose(h.y, 1169 - 19, tol: 1e-9, "a one-row head's height")
        for kind in ButterflyKind.allCases {
            for seed in UInt64(1)...UInt64(5) {
                let random = WebRandom(seed: 200 + seed)
                let x0: Double = random.range(100, 1700), y0: Double = random.range(100, 700)
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

