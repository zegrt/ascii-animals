import Foundation

// The Meadow's butterflies as the sketch defines them (`SHAPES`, `SPECIES`, `wingInks`, `PAPER_WINGS`, `VEINS`;
// html:374–531, 2137–2144). `html:N` is a line of `Tools/meadow-sketch/meadow.html` on `meadow-sketch` at 4e1b869.

/// The four species, in the sketch's `SPECIES_LIST` order (html:188–193).
public enum ButterflyKind: Int, CaseIterable, Sendable {
    case monarch, morpho, swallowtail, white

    public var name: String { String(describing: self) }
    public var species: ButterflySpecies { ButterflySpecies.all[rawValue] }
}

/// A wing outline (`outline`, html:377–381): x outward in half-spans (0 at the body), y along the body in
/// half-heights (+ toward the head), with each edge's kind (the edge from point i to point i + 1).
public struct WingOutline: Sendable {
    public enum Edge: Int8, Sendable { case root = 0, costa = 1, outer = 2, inner = 3 }
    public let points: [SIMD2<Double>]
    public let kinds: [Edge]
    public let minY: Double, maxY: Double, maxX: Double

    init(_ pts: [(Double, Double)], _ kinds: [Edge]) {
        points = pts.map { SIMD2($0.0, $0.1) }
        self.kinds = kinds
        minY = pts.map { $0.1 }.min() ?? 0
        maxY = pts.map { $0.1 }.max() ?? 0
        maxX = max(0, pts.map { $0.0 }.max() ?? 0)
    }

    /// `inside(o, x, y)` (html:2047–2055): even-odd point in polygon.
    @inline(__always) public func contains(_ x: Double, _ y: Double) -> Bool {
        if y < minY || y > maxY || x > maxX { return false }
        var c = false
        var j = points.count - 1
        for i in 0..<points.count {
            let a = points[i], b = points[j]
            if (a.y > y) != (b.y > y) {
                let xc: Double = a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x)
                if x < xc { c.toggle() }
            }
            j = i
        }
        return c
    }
}

public typealias MeadowRGB = SIMD3<Double>

/// One species' dark inks (`wingInks`, html:459–477).
public struct WingInks: Sendable {
    public let ramp: [MeadowRGB]
    public let marks: [MeadowRGB]
    public let markInk: MeadowRGB
    public let dot: MeadowRGB, spot: MeadowRGB, under: MeadowRGB, ring: MeadowRGB, centre: MeadowRGB, blue: MeadowRGB
    public let shine: MeadowRGB?
    public let body = MeadowRGB(22, 19, 17), bodyInk = MeadowRGB(200, 190, 172), feeler = MeadowRGB(178, 168, 150)
}

/// One species on paper (`PAPER_WINGS`, html:518–531).
public struct PaperWings: Sendable {
    public let pig: MeadowRGB, deep: Double, lit: Double, ink: MeadowRGB, edge: MeadowRGB, under: MeadowRGB
    public let mark: MeadowRGB, markA: [Double], markInk: MeadowRGB, spot: MeadowRGB, spotA: Double
    public let ring: MeadowRGB, ringA: Double, blue: MeadowRGB, blueA: Double
}

/// A vein (`VEINS`, html:2137–2144): part (0 fore, 1 hind), from (x0, y0) to (x1, y1) in half-span units, drawn
/// always (0), on a wing over 10 cells (1) or over 14 (2).
public struct Vein: Sendable {
    public let part: Int, x0: Double, y0: Double, x1: Double, y1: Double, from: Int
}

/// A species (`SPECIES`, html:400–427). Sizes in cells at 13 × 19 pt; speeds in pt/s at that cell; angles stored in
/// radians (the sketch's degrees × DEG).
public struct ButterflySpecies: Sendable {
    public let kind: ButterflyKind
    public let span: Double, aspect: Double, realBeat: Double
    public let top: Double, bottom: Double
    public let cruise: Double, forage: Double, surge: Double, thrust: Double
    public let bout: (Int, Int), glideS: (Double, Double), glideWidth: Double
    public let jinkChance: Double, jinkSigma: Double, slip: Double, headingK: Double, zeta: Double
    public let bob: Double, maxBank: Double, bound: Bool
    public let nectar: (Double, Double), bask: (Double, Double)
    public enum BaskPose: Sendable { case open, closed, vee }
    public let baskPose: BaskPose
    public let flutterOnFlower: Bool
    /// Flower weights by `FlowerKind` raw value; 0 where the sketch lists none (its `|| 0.5` then applies).
    public let flowers: [Double]
    public let fore: WingOutline, hind: WingOutline
    /// Below this y a hindwing hit is the tail (-9: none).
    public let tailY: Double
    public let inks: WingInks
    public let paper: PaperWings
    public let veins: [Vein]
    /// The weight when one comes to a still pointer (`stepPointer`, html:1912).
    public let cursorWeight: Double

    /// Derived (html:420–427).
    public var mid: Double { (top + bottom) / 2 }
    public var amp: Double { (top - bottom) / 2 }
    public var glideStroke: Double { acos(clamp(glideWidth, -1, 1)) }
    public var glidePhase: Double { acos(clamp((glideStroke - mid) / amp, -1, 1)) }

    /// A flower kind's weight for this species: `sp.flowers[f.kind] || 0.5` (html:1482).
    @inline(__always) public func weight(_ k: FlowerKind) -> Double {
        let w = flowers[k.rawValue]
        return w != 0 ? w : 0.5
    }

    public static let beatCap = 7.5

    static let DEG = Double.pi / 180

    private static let FK: [WingOutline.Edge] = [.costa, .costa, .costa, .outer, .outer, .outer, .inner, .inner, .root]
    private static let HK: [WingOutline.Edge] = [.costa, .costa, .outer, .outer, .outer, .outer, .inner, .inner, .root]

    private static func weights(_ d: [FlowerKind: Double]) -> [Double] {
        FlowerKind.allCases.map { d[$0] ?? 0 }
    }

    public static let all: [ButterflySpecies] = [monarch, morpho, swallowtail, white]

    static let monarch = ButterflySpecies(
        kind: .monarch, span: 22, aspect: 0.6, realBeat: 9.5, top: 80 * DEG, bottom: -16 * DEG,
        cruise: 170, forage: 80, surge: 0, thrust: 0.9, bout: (3, 8), glideS: (1.5, 5), glideWidth: 0.95,
        jinkChance: 0.12, jinkSigma: 12, slip: 0.35, headingK: 30, zeta: 0.9, bob: 0.25, maxBank: 35 * DEG, bound: false,
        nectar: (10, 40), bask: (10, 40), baskPose: .open, flutterOnFlower: false,
        flowers: weights([.milkweed: 3, .coneflower: 2, .clover: 1, .daisy: 1]),
        fore: WingOutline([(0.03, 0.34), (0.30, 0.62), (0.62, 0.88), (0.92, 1.00), (1.00, 0.80), (0.92, 0.40), (0.74, 0.00), (0.40, -0.12), (0.03, -0.10)], FK),
        hind: WingOutline([(0.03, 0.06), (0.38, 0.06), (0.58, -0.12), (0.68, -0.36), (0.64, -0.62), (0.50, -0.86), (0.28, -0.98), (0.12, -0.88), (0.04, -0.56)], HK),
        tailY: -9,
        inks: WingInks(ramp: [MeadowRGB(96, 38, 10), MeadowRGB(150, 64, 16), MeadowRGB(204, 104, 28), MeadowRGB(240, 152, 62)],
                       marks: [MeadowRGB(12, 9, 8), MeadowRGB(30, 22, 17), MeadowRGB(54, 40, 30)], markInk: MeadowRGB(118, 88, 64),
                       dot: MeadowRGB(240, 234, 218), spot: MeadowRGB(232, 172, 92), under: MeadowRGB(176, 122, 60), ring: MeadowRGB(240, 234, 218),
                       centre: MeadowRGB(30, 22, 18), blue: MeadowRGB(0, 0, 0), shine: nil),
        paper: PaperWings(pig: MeadowRGB(226, 128, 60), deep: 0.8, lit: 0.3, ink: MeadowRGB(84, 38, 10), edge: MeadowRGB(196, 94, 24), under: MeadowRGB(214, 150, 84),
                          mark: MeadowRGB(66, 58, 54), markA: [0.48, 0.38, 0.3], markInk: MeadowRGB(30, 25, 22), spot: MeadowRGB(236, 146, 56), spotA: 0.55,
                          ring: MeadowRGB(220, 200, 150), ringA: 0.4, blue: MeadowRGB(0, 0, 0), blueA: 0),
        veins: [Vein(part: 0, x0: 0.08, y0: 0.12, x1: 0.92, y1: 0.62, from: 0), Vein(part: 0, x0: 0.08, y0: 0.06, x1: 0.88, y1: 0.32, from: 1),
                Vein(part: 0, x0: 0.1, y0: 0.0, x1: 0.76, y1: 0.02, from: 2), Vein(part: 1, x0: 0.06, y0: -0.14, x1: 0.44, y1: -0.82, from: 0),
                Vein(part: 1, x0: 0.06, y0: -0.08, x1: 0.62, y1: -0.32, from: 1), Vein(part: 1, x0: 0.06, y0: -0.1, x1: 0.66, y1: -0.56, from: 2)],
        cursorWeight: 1)

    static let morpho = ButterflySpecies(
        kind: .morpho, span: 26, aspect: 0.5, realBeat: 6, top: 82 * DEG, bottom: -18 * DEG,
        cruise: 150, forage: 70, surge: 0, thrust: 0.9, bout: (4, 10), glideS: (0.6, 2), glideWidth: 1,
        jinkChance: 0.30, jinkSigma: 30, slip: 0.7, headingK: 35, zeta: 0.85, bob: 0.35, maxBank: 50 * DEG, bound: true,
        nectar: (20, 60), bask: (20, 90), baskPose: .closed, flutterOnFlower: false,
        flowers: weights([:]),
        fore: WingOutline([(0.03, 0.34), (0.34, 0.70), (0.68, 0.94), (0.90, 0.98), (1.00, 0.72), (0.96, 0.34), (0.80, -0.02), (0.40, -0.12), (0.03, -0.10)], FK),
        hind: WingOutline([(0.03, 0.06), (0.44, 0.06), (0.64, -0.12), (0.76, -0.36), (0.72, -0.64), (0.54, -0.88), (0.30, -1.00), (0.10, -0.90), (0.04, -0.54)], HK),
        tailY: -9,
        inks: WingInks(ramp: [MeadowRGB(12, 30, 86), MeadowRGB(24, 62, 150), MeadowRGB(42, 104, 200), MeadowRGB(86, 152, 232)],
                       marks: [MeadowRGB(7, 9, 16), MeadowRGB(16, 20, 34), MeadowRGB(32, 38, 60)], markInk: MeadowRGB(76, 90, 122),
                       dot: MeadowRGB(222, 230, 242), spot: MeadowRGB(222, 230, 242), under: MeadowRGB(112, 84, 54), ring: MeadowRGB(204, 176, 102),
                       centre: MeadowRGB(34, 26, 20), blue: MeadowRGB(0, 0, 0), shine: MeadowRGB(178, 226, 255)),
        paper: PaperWings(pig: MeadowRGB(60, 112, 212), deep: 0.6, lit: 0.2, ink: MeadowRGB(18, 32, 82), edge: MeadowRGB(44, 96, 196), under: MeadowRGB(150, 108, 66),
                          mark: MeadowRGB(52, 58, 76), markA: [0.48, 0.38, 0.3], markInk: MeadowRGB(20, 23, 34), spot: MeadowRGB(150, 176, 226), spotA: 0.3,
                          ring: MeadowRGB(208, 168, 76), ringA: 0.6, blue: MeadowRGB(0, 0, 0), blueA: 0),
        veins: [Vein(part: 0, x0: 0.1, y0: 0.08, x1: 0.86, y1: 0.5, from: 2), Vein(part: 1, x0: 0.08, y0: -0.1, x1: 0.6, y1: -0.5, from: 2)],
        cursorWeight: 0.5)

    static let swallowtail = ButterflySpecies(
        kind: .swallowtail, span: 22, aspect: 0.62, realBeat: 7, top: 78 * DEG, bottom: -14 * DEG,
        cruise: 170, forage: 80, surge: 0, thrust: 0.9, bout: (3, 6), glideS: (1, 3), glideWidth: 1,
        jinkChance: 0.25, jinkSigma: 25, slip: 0.55, headingK: 45, zeta: 0.9, bob: 0.25, maxBank: 40 * DEG, bound: false,
        nectar: (6, 25), bask: (10, 30), baskPose: .open, flutterOnFlower: true,
        flowers: weights([.coneflower: 2, .fennel: 2, .milkweed: 1, .daisy: 1]),
        fore: WingOutline([(0.03, 0.34), (0.34, 0.66), (0.68, 0.90), (0.96, 1.02), (0.98, 0.78), (0.86, 0.36), (0.72, -0.02), (0.38, -0.12), (0.03, -0.10)], FK),
        hind: WingOutline([(0.03, 0.06), (0.40, 0.06), (0.58, -0.12), (0.68, -0.36), (0.62, -0.68), (0.56, -1.40), (0.44, -1.40), (0.40, -0.88), (0.20, -0.94), (0.08, -0.84), (0.04, -0.54)],
                          [.costa, .costa, .outer, .outer, .outer, .outer, .outer, .outer, .inner, .inner, .root]),
        tailY: -0.92,
        inks: WingInks(ramp: [MeadowRGB(110, 90, 28), MeadowRGB(164, 140, 50), MeadowRGB(212, 188, 82), MeadowRGB(244, 226, 134)],
                       marks: [MeadowRGB(11, 10, 8), MeadowRGB(28, 25, 20), MeadowRGB(50, 45, 35)], markInk: MeadowRGB(112, 100, 72),
                       dot: MeadowRGB(236, 216, 120), spot: MeadowRGB(236, 216, 120), under: MeadowRGB(180, 164, 98), ring: MeadowRGB(218, 98, 46),
                       centre: MeadowRGB(26, 23, 18), blue: MeadowRGB(72, 114, 200), shine: nil),
        paper: PaperWings(pig: MeadowRGB(236, 206, 84), deep: 0.85, lit: 0.36, ink: MeadowRGB(82, 66, 10), edge: MeadowRGB(172, 140, 18), under: MeadowRGB(234, 216, 132),
                          mark: MeadowRGB(62, 58, 50), markA: [0.48, 0.38, 0.3], markInk: MeadowRGB(26, 24, 19), spot: MeadowRGB(242, 210, 70), spotA: 0.6,
                          ring: MeadowRGB(232, 104, 34), ringA: 0.6, blue: MeadowRGB(64, 104, 214), blueA: 0.48),
        veins: [Vein(part: 0, x0: 0.12, y0: 0.08, x1: 0.76, y1: 0.44, from: 0), Vein(part: 0, x0: 0.12, y0: 0.02, x1: 0.7, y1: 0.02, from: 2),
                Vein(part: 1, x0: 0.12, y0: -0.14, x1: 0.5, y1: -0.56, from: 1)],
        cursorWeight: 2)

    static let white = ButterflySpecies(
        kind: .white, span: 15, aspect: 0.68, realBeat: 11.8, top: 80 * DEG, bottom: -12 * DEG,
        cruise: 140, forage: 70, surge: 0.45, thrust: 1.1, bout: (30, 90), glideS: (0.15, 0.4), glideWidth: 1,
        jinkChance: 0.40, jinkSigma: 40, slip: 1, headingK: 60, zeta: 0.8, bob: 0.2, maxBank: 45 * DEG, bound: false,
        nectar: (6, 20), bask: (8, 25), baskPose: .vee, flutterOnFlower: false,
        flowers: weights([.mustard: 3, .clover: 2, .daisy: 2, .dandelion: 2]),
        fore: WingOutline([(0.03, 0.34), (0.34, 0.72), (0.66, 0.96), (0.88, 0.96), (1.00, 0.66), (0.94, 0.28), (0.74, -0.02), (0.38, -0.12), (0.03, -0.10)], FK),
        hind: WingOutline([(0.03, 0.06), (0.40, 0.06), (0.58, -0.12), (0.70, -0.38), (0.64, -0.66), (0.46, -0.90), (0.24, -0.98), (0.08, -0.88), (0.04, -0.54)], HK),
        tailY: -9,
        inks: WingInks(ramp: [MeadowRGB(132, 132, 122), MeadowRGB(178, 178, 166), MeadowRGB(214, 212, 198), MeadowRGB(238, 236, 224)],
                       marks: [MeadowRGB(26, 26, 28), MeadowRGB(40, 40, 42), MeadowRGB(58, 58, 60)], markInk: MeadowRGB(120, 120, 116),
                       dot: MeadowRGB(140, 140, 132), spot: MeadowRGB(140, 140, 132), under: MeadowRGB(198, 204, 156), ring: MeadowRGB(140, 140, 132),
                       centre: MeadowRGB(36, 36, 38), blue: MeadowRGB(0, 0, 0), shine: nil),
        paper: PaperWings(pig: MeadowRGB(226, 220, 186), deep: 0.9, lit: 0.25, ink: MeadowRGB(74, 76, 70), edge: MeadowRGB(112, 116, 104), under: MeadowRGB(212, 224, 150),
                          mark: MeadowRGB(76, 76, 84), markA: [0.44, 0.36, 0.28], markInk: MeadowRGB(30, 30, 34), spot: MeadowRGB(150, 150, 150), spotA: 0.4,
                          ring: MeadowRGB(150, 150, 150), ringA: 0.4, blue: MeadowRGB(0, 0, 0), blueA: 0),
        veins: [],
        cursorWeight: 2)

    /// `beatHz` (html:419): the drawn beat at a wingbeat setting, capped at 7.5 Hz.
    public func beatHz(_ wingbeat: Double) -> Double { min(ButterflySpecies.beatCap, realBeat * wingbeat) }
}
