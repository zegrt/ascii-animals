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
}
