import CoreGraphics
import Foundation
import simd

/// The meadow's plants (research §4.1). Grass carries the breeze along the ground line.
public enum FlowerKind: String, CaseIterable, Sendable {
    case milkweed, coneflower, fennel, mustard, clover, daisy, dandelion, grass

    /// Coneflower, fennel and milkweed stand 4–7 rows and sway slowly; the rest are short and quick.
    public var isTall: Bool { self == .milkweed || self == .coneflower || self == .fennel }

    /// Stem height in rows when laid out along the bottom.
    var rows: ClosedRange<Int> {
        switch self {
        case .milkweed, .fennel: return 5...7
        case .coneflower: return 4...6
        case .mustard: return 2...4
        case .daisy, .dandelion: return 1...3
        case .clover, .grass: return 1...2
        }
    }

    /// How much the meadow's four butterflies want it: each species' flower weights summed (Recommended
    /// parameters; morphos weigh every flower 0.5). A meadow grows what its butterflies feed on.
    var weight: Double {
        switch self {
        case .milkweed: return 3 + 0.5 + 1          // monarch, morpho, swallowtail
        case .coneflower: return 2 + 0.5 + 2        // monarch, morpho, swallowtail
        case .fennel: return 0.5 + 2                // morpho, swallowtail
        case .mustard: return 0.5 + 3               // morpho, white
        case .clover: return 1 + 0.5 + 2            // monarch, morpho, white
        case .daisy: return 1 + 0.5 + 1 + 2         // all four
        case .dandelion: return 0.5 + 2             // morpho, white
        case .grass: return 0
        }
    }

    /// The stem's natural frequency band, Hz, over its row band (f₀ ∝ 1/height inside it).
    var band: (fLo: Double, fHi: Double, rLo: Double, rHi: Double) {
        isTall ? (0.7, 1.2, 4, 7) : (1.5, 2.5, 1, 4)
    }

    static let blooming: [FlowerKind] = allCases.filter { $0 != .grass }
    static let tall: [FlowerKind] = allCases.filter { $0.isTall }
}

/// One plant: a stem rooted on a screen's bottom edge whose tip is a single damped spring.
public struct Flower: Equatable, Sendable {
    public var kind: FlowerKind
    /// Ground point, ocean space: always on the bottom edge of `rect`.
    public var base: SIMD2<Double>
    /// Stem height in rows (when fully grown).
    public var rows: Int
    /// Tip offset from rest (spring state), pt. y down: a landing dips it positive.
    public var tip: SIMD2<Double>
    public var tipV: SIMD2<Double>
    public var f0: Double, zeta: Double
    /// 0 bud … 1 open; < 1 only while blooming. A bud swells over 0 … 0.25, the petals open over 0.25 … 1.
    public var bloom: Double
    /// Sim time a click bloomed it, or −1.
    public var bornAt: Double
    /// Terrain rect it grows in.
    public var rect: Int
    /// Per-stem phase of the forcing, so neighbours never sway in lockstep.
    public var phase: Double
    /// How much of the stem has grown, 0 … 1 (ease-out); 1 unless it was just clicked.
    public var grown: Double
    /// The pollen sparkle after a bloom opens, 1 → 0; 0 the rest of the time.
    public var sparkle: Double
    /// A click bloom's stage lengths, s: stem growth, bud, petals, sparkle.
    public var stages: SIMD4<Double>
}

/// The flowers along the bottom of every screen rect, swaying in the breeze (research §4).
public final class Meadowland {
    public private(set) var flowers: [Flower] = []
    /// Sim time, s: the land's own clock, advanced only by `step`.
    public private(set) var time: Double = 0
    public private(set) var cell = CGSize(width: 13, height: 19)

    private let random: WebRandom

    /// Lean: the breeze's drag ∝ |v|·v sets a steady tip offset of `drag / (1 + drag)` stem lengths, where
    /// drag = |v|·v × leanGain / leanSpeed². 60 pt/s leans a stem ~0.45 of its length; a 120 pt/s gust ~0.77.
    static let leanGain = 0.82
    static let leanSpeed = 60.0
    /// Stems are stiff along their length: air blowing down moves the tip a quarter as much.
    static let verticalLean = 0.25
    /// The per-stem flutter on the forcing: ±30 % at 0.4 × the stem's own frequency.
    static let flutter = 0.3
    /// Clicked flowers kept per rect; past this a new click replaces the oldest.
    static let clickedPerRect = 40

    public init(random: WebRandom) {
        self.random = random
    }

    /// Lay the meadow out along the bottom of every rect: a plant every 3–5 columns, grass tufts in the bottom
    /// 1–2 rows, and 6–14 scattered taller stems up to 40 % of the rect's height (fewer on screens narrower than
    /// 1440 pt). Replaces any flowers there were, clicked ones included.
    public func layout(terrain: Terrain, cell: CGSize) {
        self.cell = CGSize(width: max(1, cell.width), height: max(1, cell.height))
        flowers.removeAll(keepingCapacity: true)
        let cw = Double(self.cell.width), ch = Double(self.cell.height)
        for (ri, r) in terrain.rects.enumerated() {
            let minX = Double(r.minX), maxX = Double(r.maxX), ground = Double(r.maxY)
            let maxRows = Int(0.4 * Double(r.height) / ch)
            guard maxRows >= 1 && maxX - minX >= cw else { continue }
            // Grass: a tuft every 1–2 columns.
            var x: Double = minX + cw * random.range(0.2, 1)
            while x < maxX - cw * 0.2 {
                add(.grass, x: x, ground: ground, rows: min(maxRows, random.int(1, 2)), rect: ri)
                x += cw * Double(random.int(1, 2))
            }
            // Plants: one every 3–5 columns.
            x = minX + cw * random.range(0.5, 2.5)
            while x < maxX - cw * 0.5 {
                let kind = pick(FlowerKind.blooming)
                add(kind, x: x, ground: ground, rows: min(maxRows, random.int(kind.rows.lowerBound, kind.rows.upperBound)), rect: ri)
                x += cw * Double(random.int(3, 5))
            }
            // Scattered taller stems, more of them short than very tall.
            let lo = min(8, maxRows), hi = max(lo, maxRows)
            let scale: Double = min(1, (maxX - minX) / 1440)
            let count = max(1, Int((Double(random.int(6, 14)) * scale).rounded()))
            for _ in 0..<count {
                let u: Double = random.unit()
                let rows = lo + Int((Double(hi - lo) * u * u).rounded())
                add(pick(FlowerKind.tall), x: random.range(minX + cw, maxX - cw), ground: ground, rows: rows, rect: ri)
            }
        }
    }

    private func add(_ kind: FlowerKind, x: Double, ground: Double, rows: Int, rect: Int) {
        flowers.append(make(kind, x: x, ground: ground, rows: rows, rect: rect))
    }

    private func make(_ kind: FlowerKind, x: Double, ground: Double, rows: Int, rect: Int) -> Flower {
        let b = kind.band
        let r: Double = clamp(Double(rows), b.rLo, b.rHi)
        let t: Double = (1 / r - 1 / b.rHi) / (1 / b.rLo - 1 / b.rHi)
        let f0: Double = clamp((b.fLo + (b.fHi - b.fLo) * t) * random.range(0.95, 1.05), b.fLo, b.fHi)
        return Flower(kind: kind, base: SIMD2<Double>(x, ground), rows: max(1, rows),
                      tip: SIMD2<Double>(0, 0), tipV: SIMD2<Double>(0, 0),
                      f0: f0, zeta: random.range(0.08, 0.15), bloom: 1, bornAt: -1, rect: rect,
                      phase: random.range(0, TAU), grown: 1, sparkle: 0, stages: SIMD4<Double>(0, 0, 0, 0))
    }

    /// A kind drawn by meadow weight, each weight multiplied by `boost` (when given).
    private func pick(_ kinds: [FlowerKind], boost: ((FlowerKind) -> Double)? = nil) -> FlowerKind {
        var total: Double = 0
        for k in kinds { total += k.weight * (boost?(k) ?? 1) }
        var u: Double = random.unit() * total
        for k in kinds {
            u -= k.weight * (boost?(k) ?? 1)
            if u < 0 { return k }
        }
        return kinds[kinds.count - 1]
    }

    /// Stem length in pt as grown so far (at least half a row, so a fresh sprout still has a head).
    @inline(__always) private func length(_ f: Flower) -> Double {
        max(0.5, Double(f.rows) * f.grown) * Double(cell.height)
    }

    /// Where the flower's head is now: the top of the stem plus the tip's sway.
    public func head(_ i: Int) -> SIMD2<Double> {
        let f = flowers[i]
        return f.base + SIMD2<Double>(0, -length(f)) + f.tip
    }

    public func step(_ dt: Double, breeze: Breeze) {
        guard dt > 0 else { return }
        time += dt
        for i in 0..<flowers.count {
            if flowers[i].bornAt >= 0 { grow(i) }
            sway(i, dt, breeze)
        }
    }

    /// A clicked flower's timeline: the stem grows (ease-out), the bud swells, the petals open, the pollen sparkles.
    private func grow(_ i: Int) {
        let f = flowers[i], s = f.stages
        let age: Double = time - f.bornAt
        if f.grown == 1 && f.bloom == 1 && f.sparkle == 0 && age > s.x + s.y + s.z + s.w { return }
        flowers[i].grown = age >= s.x ? 1 : easeOut(max(0, age) / s.x)
        let bud: Double = age - s.x, petals: Double = bud - s.y, after: Double = petals - s.z
        var b: Double = 0.25 * clamp(bud / s.y, 0, 1)
        if petals > 0 { b = petals >= s.z ? 1 : 0.25 + 0.75 * ease(petals / s.z) }
        flowers[i].bloom = max(flowers[i].bloom, b)
        flowers[i].sparkle = after >= 0 && after < s.w ? 1 - after / s.w : 0
    }

    /// The tip as a damped spring (f₀, ζ) driven towards the breeze's lean at the head.
    private func sway(_ i: Int, _ dt: Double, _ breeze: Breeze) {
        var f = flowers[i]
        let len: Double = length(f)
        let head: SIMD2<Double> = f.base + SIMD2<Double>(0, -len) + f.tip
        let v: SIMD2<Double> = breeze.sample(head.x, head.y)
        let speed: Double = simd_length(v)
        var target = SIMD2<Double>(0, 0)
        if speed > 1e-9 {
            let drag: SIMD2<Double> = v * (speed * Meadowland.leanGain / (Meadowland.leanSpeed * Meadowland.leanSpeed))
            let mag: Double = simd_length(drag)
            let flutter: Double = 1 + Meadowland.flutter * sin(TAU * 0.4 * f.f0 * time + f.phase)
            let lean: SIMD2<Double> = drag * (len * flutter / (1 + mag))
            // The head rides an arc as the stem bends (it can't rise past its length), plus a little push from
            // air blowing down on it. Updrafts don't stretch a stem.
            let x: Double = clamp(lean.x, -len, len)
            target = SIMD2<Double>(x, len - (len * len - x * x).squareRoot() + max(0, lean.y) * Meadowland.verticalLean)
        }
        let w: Double = TAU * f.f0
        let acc: SIMD2<Double> = (target - f.tip) * (w * w) - f.tipV * (2 * f.zeta * w)
        f.tipV += acc * dt
        f.tip += f.tipV * dt
        // A stem can't bend past its own length.
        let reach: Double = simd_length(f.tip)
        if reach > len { f.tip *= len / reach; f.tipV *= 0.5 }
        if !(f.tip.x.isFinite && f.tip.y.isFinite && f.tipV.x.isFinite && f.tipV.y.isFinite) {
            f.tip = SIMD2<Double>(0, 0); f.tipV = SIMD2<Double>(0, 0)
        }
        flowers[i] = f
    }

    /// A click: a flower grows from the ground band of the rect under it, in that column. Its kind leans
    /// towards what already grows nearby. Nil when the click is outside every rect. `time` is only the new
    /// flower's `bornAt`; the land keeps its own clock.
    public func bloom(atX x: Double, y: Double, terrain: Terrain, time: Double) -> Int? {
        let p = SIMD2<Double>(x, y)
        guard x.isFinite && y.isFinite && !terrain.rects.isEmpty && terrain.contains(p) else { return nil }
        let ri = terrain.rectIndex(near: p)
        let r = terrain.rects[ri]
        let cw = Double(cell.width)
        let bx: Double = Double(r.width) > cw ? clamp(x, Double(r.minX) + cw / 2, Double(r.maxX) - cw / 2) : Double(r.midX)
        // Kinds within ±8 columns count double each, so patches form.
        var near: [FlowerKind: Double] = [:]
        for f in flowers where f.rect == ri && f.kind != .grass && abs(f.base.x - bx) < 8 * cw {
            near[f.kind, default: 0] += 1
        }
        let kind = pick(FlowerKind.blooming) { 1 + (near[$0] ?? 0) }
        let maxRows = max(1, Int(0.4 * Double(r.height) / Double(cell.height)))
        var f = make(kind, x: bx, ground: Double(r.maxY), rows: min(maxRows, random.int(1, 3)), rect: ri)
        f.bloom = 0
        f.grown = 0
        f.bornAt = time
        f.stages = SIMD4<Double>(random.range(0.6, 0.9), 0.5, random.range(1.5, 2.5), random.range(1, 2))
        // Past the cap, the oldest clicked flower on this screen gives its place.
        var clicked = 0, oldest = -1
        for (k, g) in flowers.enumerated() where g.rect == ri && g.bornAt >= 0 {
            clicked += 1
            if oldest < 0 || g.bornAt < flowers[oldest].bornAt { oldest = k }
        }
        if clicked >= Meadowland.clickedPerRect && oldest >= 0 {
            flowers[oldest] = f
            return oldest
        }
        flowers.append(f)
        return flowers.count - 1
    }

    /// A butterfly lands (or leaves): kick the tip.
    public func dip(_ i: Int, impulse: SIMD2<Double>) {
        guard flowers.indices.contains(i), impulse.x.isFinite, impulse.y.isFinite else { return }
        flowers[i].tipV += impulse
    }
}
