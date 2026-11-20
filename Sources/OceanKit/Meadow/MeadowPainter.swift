import CoreGraphics
import Foundation
import simd

/**
 * Draws the meadow as a grid of ASCII cells, in the hand of the Web's spiders (research §5.2):
 *
 *   flowers   heads per research §4.1, 2–3 rows and 3–7 columns (a daisy's petal ring round its gold eye, a
 *             coneflower's drooping petals round its cone, milkweed's ball, fennel's flat umbel, clover, a mustard
 *             spike, a dandelion), their centres on coloured blocks; stems pick `/ | \` by their local slope (the silk
 *             rule) with leaves beside them; grass `,'/|\` by its lean; a fresh bloom's pollen sparkles, and the
 *             breeze shows a little brighter on the stems it moves.
 *   wings     each wing a forewing over a hindwing, outlines per species (the swallowtail's tail part of its
 *             hindwing), in wing-local (u along the body, v outward) sampled at (u, v / s) five times a cell, where s
 *             is the model's signed projected width: a beat foreshortens them, under 0 the underside shows. Mostly
 *             solid blocks in the face colour; borders, veins, dots, spots and bands only where the species has them,
 *             measured in cells from the outline so they stay a cell deep at any size.
 *   edge-on   |s| < 0.18: the wing's outer contour as a line of `| / \` in the underside colour, never blocks.
 *   flicker   a cell's coverage class (empty, edge, full) changes only when its coverage moves 0.1 past the
 *             threshold, and it switches between empty and full at most twice in any beat (a third switch is held as a
 *             glyph without its block): kept per cell of each butterfly's box, frame to frame.
 *   bodies    a dark column (head `o`, thorax `8`, abdomen `|`) between the wings, antennae `\ /` standing clear
 *             above the head with `°` clubs, the proboscis when nectaring.
 *   dust      pollen-gold motes drifting off the flower a butterfly has just left, fading over 3–6 s.
 *
 * The ground band is cached and redrawn only in the columns of plants that changed.
 *
 * Colours come out final (research §5.4): species colours toned down on black; graphite on paper with species ink in
 * light, the cabbage white a pale graphite block; Calm dims toward black, or toward the paper in light, as the Web does.
 */

/// Atlas slots, looked up once.
private enum MG {
    static func i(_ c: Character) -> UInt8 { GlyphAtlas.index(c)! }
    static let pipe = i("|"), slash = i("/"), back = i("\\"), dash = i("-"), dot = i("·"), plus = i("+")
    static let at = i("@"), o = i("o"), ring = i("°"), colon = i(":"), comma = i(",")
    static let tick = i("'"), period = i("."), eight = i("8")
    static let MARK: [UInt8] = "#%@".map { (c: Character) -> UInt8 in i(c) }
    static let EDGE_HEAVY: [UInt8] = ":;".map { (c: Character) -> UInt8 in i(c) }
    static let EDGE_LIGHT: [UInt8] = ".',`".map { (c: Character) -> UInt8 in i(c) }
}

private typealias RGB = SIMD3<Double>
private let PAPER = RGB(247, 246, 243)
private let INK = RGB(35, 35, 35)
private let GOLD = RGB(217, 193, 74)
private let OCHRE = RGB(150, 124, 40)

/// A fixed-size buffer that only grows (zeroed when it does), so painting allocates nothing once warm.
private struct Grow<T> {
    private(set) var p: UnsafeMutablePointer<T>
    private(set) var capacity = 0
    private let zero: T
    init(_ zero: T) { self.zero = zero; p = .allocate(capacity: 1); p.initialize(to: zero); capacity = 1 }
    /// True when it had to grow.
    mutating func ensure(_ n: Int) -> Bool {
        guard n > capacity else { return false }
        p.deallocate()
        p = .allocate(capacity: n)
        p.initialize(repeating: zero, count: n)
        capacity = n
        return true
    }
    func free() { p.deallocate() }
}

// ── colour ──

/// The theme's tone: Calm multiplies by the brightness on black and mixes toward the paper by 1 − brightness in light.
private struct Tone {
    var light = false
    var brightness: Double = 1
    var accentRate: Double = 1

    @inline(__always) func pack(_ c: RGB, _ alpha: Double = 1) -> UInt32 {
        var v: RGB = c
        if brightness != 1 {
            if light { v = v + (PAPER - v) * (1 - brightness) } else { v = v * brightness }
        }
        let q: RGB = simd_clamp(v, RGB(0, 0, 0), RGB(255, 255, 255)).rounded(.toNearestOrAwayFromZero)
        let a: Double = (clamp(alpha, 0, 1) * 255).rounded()
        return UInt32(q.x) | UInt32(q.y) << 8 | UInt32(q.z) << 16 | UInt32(a) << 24
    }
}

/// A flower colour for the paper: the same hue darkened to graphite strength, its saturation held to 0.4.
private func onPaper(_ c: RGB) -> RGB {
    let lum: Double = max(1, 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z)
    var v: RGB = c * (92 / lum)
    let mx: Double = max(v.x, v.y, v.z), mn: Double = min(v.x, v.y, v.z)
    if mx > 0 && mx - mn > 0.4 * mx {
        let k: Double = 0.4 * mx / (mx - mn)
        v = RGB(repeating: mx) - (RGB(repeating: mx) - v) * k
    }
    return simd_clamp(v, RGB(0, 0, 0), RGB(255, 255, 255))
}

/// One species' wing and body colours for a theme (research §5.4). Wings are mostly solid blocks in the field
/// colour; marks, dots and spots sit where the species has them.
private struct WingInks {
    /// The field: its block, and the ink of the few texture glyphs on it.
    var block = RGB(0, 0, 0), glyph = RGB(0, 0, 0)
    /// Veins and borders: the mark's block and its glyph's ink.
    var markBlock = RGB(0, 0, 0), markInk = RGB(0, 0, 0)
    var dot = RGB(0, 0, 0)
    var underBlock = RGB(0, 0, 0), underGlyph = RGB(0, 0, 0)
    /// Eyespots: the ring's colour and the centre's block (morpho underside; the swallowtail's red-orange spot).
    var ring = RGB(0, 0, 0), centre = RGB(0, 0, 0)
    /// The swallowtail's blue row; the morpho's shine.
    var blue = RGB(0, 0, 0), shine = RGB(0, 0, 0)
    var bodyBlock = RGB(0, 0, 0), bodyGlyph = RGB(0, 0, 0)
    /// The antennae, drawn on the background.
    var feeler = RGB(0, 0, 0)

    static func make(_ k: ButterflyKind, light: Bool) -> WingInks {
        var w = WingInks()
        if !light {
            w.bodyBlock = RGB(24, 21, 19)
            w.bodyGlyph = RGB(196, 186, 170)
            w.feeler = w.bodyGlyph
            switch k {
            case .monarch:
                w.block = RGB(168, 88, 28); w.glyph = RGB(232, 156, 76)
                w.markBlock = RGB(36, 26, 20); w.markInk = RGB(110, 82, 62); w.dot = RGB(236, 230, 214)
                w.underBlock = RGB(170, 118, 58); w.underGlyph = RGB(234, 186, 116)
                w.ring = w.dot; w.centre = w.markBlock
            case .morpho:
                w.block = RGB(38, 88, 160); w.glyph = RGB(120, 170, 228); w.shine = RGB(84, 142, 212)
                w.markBlock = RGB(18, 22, 32); w.markInk = RGB(74, 86, 110); w.dot = RGB(222, 228, 238)
                w.underBlock = RGB(104, 78, 50); w.underGlyph = RGB(160, 128, 88)
                w.ring = RGB(200, 172, 100); w.centre = RGB(34, 26, 20)
            case .swallowtail:
                w.block = RGB(182, 158, 62); w.glyph = RGB(234, 214, 124)
                w.markBlock = RGB(32, 28, 22); w.markInk = RGB(104, 94, 68); w.dot = RGB(230, 210, 112)
                w.underBlock = RGB(178, 162, 96); w.underGlyph = RGB(230, 216, 154)
                w.ring = RGB(206, 98, 52); w.centre = RGB(32, 28, 22); w.blue = RGB(74, 110, 186)
            case .cabbageWhite:
                w.block = RGB(204, 202, 190); w.glyph = RGB(140, 140, 132)
                w.markBlock = RGB(42, 42, 42); w.markInk = RGB(116, 116, 112); w.dot = w.glyph
                w.underBlock = RGB(198, 204, 156); w.underGlyph = RGB(140, 146, 104)
                w.ring = w.glyph; w.centre = w.markBlock
            }
            return w
        }
        // Graphite on paper: species ink on paper-tinted blocks; veins, borders and bodies in graphite.
        func tinted(_ ink: RGB, _ k: Double) -> RGB { PAPER + (ink - PAPER) * k }
        w.markBlock = RGB(78, 74, 70)
        w.markInk = RGB(150, 146, 140)
        w.dot = RGB(236, 234, 228)
        w.bodyBlock = RGB(70, 67, 64)
        w.bodyGlyph = RGB(236, 234, 228)
        w.feeler = RGB(60, 58, 56)
        switch k {
        case .monarch:
            w.glyph = RGB(168, 96, 42); w.block = tinted(w.glyph, 0.78)
            w.underGlyph = RGB(176, 124, 72); w.underBlock = tinted(w.underGlyph, 0.5)
            w.ring = w.dot; w.centre = w.markBlock
        case .morpho:
            w.glyph = RGB(54, 92, 146); w.block = tinted(w.glyph, 0.6); w.shine = tinted(w.glyph, 0.4)
            w.underGlyph = RGB(110, 84, 58); w.underBlock = tinted(w.underGlyph, 0.55)
            w.ring = OCHRE; w.centre = INK
        case .swallowtail:
            w.glyph = OCHRE; w.block = tinted(w.glyph, 0.6)
            w.underGlyph = RGB(140, 124, 70); w.underBlock = tinted(w.underGlyph, 0.5)
            w.ring = RGB(170, 90, 52); w.centre = w.markBlock; w.blue = RGB(70, 92, 130)
            w.dot = tinted(OCHRE, 0.45)
        case .cabbageWhite:
            // White on paper vanishes: a pale graphite block with ink glyphs, tips in ink.
            w.block = RGB(214, 212, 204); w.glyph = RGB(96, 96, 90)
            w.underBlock = RGB(208, 212, 168); w.underGlyph = RGB(104, 106, 84)
            w.ring = w.glyph; w.centre = w.markBlock
            w.dot = w.glyph
        }
        return w
    }
}

/// The meadow's plant colours for a theme.
private struct PlantInks {
    var stem = RGB(0, 0, 0), leaf = RGB(0, 0, 0), grass = RGB(0, 0, 0)
    var milkweed = RGB(0, 0, 0), cone = RGB(0, 0, 0), petals = RGB(0, 0, 0), fennel = RGB(0, 0, 0)
    var mustard = RGB(0, 0, 0), clover = RGB(0, 0, 0), daisy = RGB(0, 0, 0), dandelion = RGB(0, 0, 0)
    /// The blocks under the heads' centres: the daisy's gold eye, the coneflower's cone, milkweed's, clover's and the
    /// dandelion's middles.
    var goldBlock = RGB(0, 0, 0), coneBlock = RGB(0, 0, 0), milkweedBlock = RGB(0, 0, 0), cloverBlock = RGB(0, 0, 0)
    var dandelionBlock = RGB(0, 0, 0)
    /// Pollen: the sparkle, the dust, the daisy's eye.
    var gold = RGB(0, 0, 0)
    /// What a stem moves toward when the breeze stirs it.
    var stirred = RGB(0, 0, 0)

    static func make(light: Bool) -> PlantInks {
        var p = PlantInks()
        p.stem = RGB(88, 118, 78); p.leaf = RGB(110, 130, 96); p.grass = RGB(110, 130, 96)
        // Research §4.1's colours, a little fuller so the heads carry the strip.
        p.milkweed = RGB(204, 126, 150); p.cone = RGB(176, 96, 50); p.petals = RGB(194, 122, 174)
        p.fennel = RGB(226, 212, 124); p.mustard = RGB(220, 190, 70); p.clover = RGB(196, 104, 136)
        p.daisy = RGB(232, 230, 220); p.dandelion = RGB(222, 192, 64); p.gold = GOLD
        p.goldBlock = RGB(118, 92, 24); p.coneBlock = RGB(88, 44, 24); p.milkweedBlock = RGB(112, 58, 78)
        p.cloverBlock = RGB(104, 48, 70); p.dandelionBlock = RGB(124, 100, 26)
        p.stirred = RGB(170, 206, 140)
        guard light else { return p }
        func block(_ c: RGB) -> RGB { PAPER + (onPaper(c) - PAPER) * 0.4 }
        p.goldBlock = block(p.gold); p.coneBlock = block(p.cone); p.milkweedBlock = block(p.milkweed)
        p.cloverBlock = block(p.clover); p.dandelionBlock = block(p.dandelion)
        p.stem = onPaper(p.stem); p.leaf = onPaper(p.leaf); p.grass = onPaper(p.grass)
        p.milkweed = onPaper(p.milkweed); p.cone = onPaper(p.cone); p.petals = onPaper(p.petals)
        p.fennel = onPaper(p.fennel); p.mustard = onPaper(p.mustard); p.clover = onPaper(p.clover)
        p.daisy = onPaper(p.daisy); p.dandelion = onPaper(p.dandelion); p.gold = OCHRE
        p.stirred = INK
        return p
    }
}

// ── flower heads ──

/// One cell of a flower head: its offset from the head point (columns; rows, up negative), glyph and colour role.
private struct Floret {
    let dc: Int, dr: Int
    let glyph: UInt8
    let role: UInt8
}

/// Petal ink; the centre's ink on its block; the centre's ink alone; leaf; stem.
private let PETAL: UInt8 = 0, EYE: UInt8 = 1, CONE: UInt8 = 2, LEAF: UInt8 = 3, STEM: UInt8 = 4

/// Every kind's open head (research §4.1), drawn row by row: the art, and under each glyph its role (`p` petal,
/// `C` centre on a block, `c` centre ink, `l` leaf, `s` stem). The row holding the head point is `above` rows down
/// (`FlowerKind.head`), and the middle column is the stem's.
private let HEADS: [[Floret]] = FlowerKind.allCases.map { (k: FlowerKind) -> [Floret] in
    let art: [String], roles: [String]
    switch k {
    case .daisy:
        art = [" \\|/ ", "-(@)-", " /|\\ "]; roles = [" ppp ", "ppCpp", " ppp "]
    case .coneflower:
        art = ["_(@)_", "//|\\\\"]; roles = ["pcCcp", "ppspp"]
    case .milkweed:
        art = [" o°o ", "°oOo°", " °o° "]; roles = [" ppp ", "ppCpp", " ppp "]
    case .fennel:
        art = ["·:·:·:·", " \\\\|// "]; roles = ["ppppppp", " sssss "]
    case .clover:
        art = ["(@)", "\\|/"]; roles = ["pCp", "lsl"]
    case .mustard:
        art = [" + ", "+|+"]; roles = [" p ", "psp"]
    case .dandelion:
        art = ["·*·", "*@*"]; roles = ["ppp", "pCp"]
    case .grass:
        return []
    }
    let above = k.head.above
    var out: [Floret] = []
    for (r, line) in art.enumerated() {
        let gs = Array(line), rs = Array(roles[r])
        let half = gs.count / 2
        for (c, ch) in gs.enumerated() where ch != " " {
            let role: UInt8
            switch rs[c] {
            case "C": role = EYE
            case "c": role = CONE
            case "l": role = LEAF
            case "s": role = STEM
            default: role = PETAL
            }
            out.append(Floret(dc: c - half, dr: r - above, glyph: GlyphAtlas.index(ch)!, role: role))
        }
    }
    return out
}

// ── wings ──

/// Which edge of a wing outline: along the body (no border drawn), the leading edge (costa), the outer margin, or
/// the inner (trailing) margin.
private let ROOT = 0, COSTA = 1, OUTER = 2, INNER = 3

/// A wing part's outline, a polygon in wing-local units: x outward in half-spans (0 at the body), y along the body in
/// half-heights (+ toward the head). `kind[i]` is the kind of the edge from `p[i]` to the next point.
private struct Outline {
    let p: [SIMD2<Double>]
    let kind: [Int]
    /// The points' bounds, for a quick miss.
    let lo: SIMD2<Double>, hi: SIMD2<Double>

    init(p: [SIMD2<Double>], kind: [Int]) {
        self.p = p
        self.kind = kind
        var lo = SIMD2<Double>(repeating: .infinity), hi = SIMD2<Double>(repeating: -.infinity)
        for q in p { lo = simd_min(lo, q); hi = simd_max(hi, q) }
        self.lo = lo
        self.hi = hi
    }
}

/// Each species' forewing and hindwing outlines (research §5.2): the forewing on top, its apex up and out, the
/// rounded hindwing below it with a notch between them on the outer edge, and the swallowtail's tail part of its
/// hindwing. Only the outlines differ by species; the drawing is the same machinery for all four.
private struct WingShape {
    let fore: Outline, hind: Outline
    /// Below this y the hindwing is the swallowtail's tail.
    let tailY: Double

    static func of(_ k: ButterflyKind) -> WingShape {
        switch k {
        case .monarch: return monarch
        case .morpho: return morpho
        case .swallowtail: return swallowtail
        case .cabbageWhite: return white
        }
    }

    // Forewings: root (along the body), costa up and out to the apex, the outer margin down to the tornus, the
    // inner margin back over the hindwing to the body.
    private static let foreKinds: [Int] = [COSTA, COSTA, COSTA, OUTER, OUTER, OUTER, INNER, INNER, ROOT]
    // Hindwings: costa (under the forewing) out to the shoulder, the outer margin round to the inner corner,
    // the inner margin up along the abdomen, the root.
    private static let hindKinds: [Int] = [COSTA, COSTA, OUTER, OUTER, OUTER, OUTER, INNER, INNER, ROOT]

    static let monarch = WingShape(
        fore: Outline(p: [SIMD2<Double>(0.03, 0.34), SIMD2<Double>(0.30, 0.62), SIMD2<Double>(0.62, 0.88),
                          SIMD2<Double>(0.92, 1.00), SIMD2<Double>(1.00, 0.80), SIMD2<Double>(0.92, 0.40),
                          SIMD2<Double>(0.74, 0.00), SIMD2<Double>(0.40, -0.12), SIMD2<Double>(0.03, -0.10)],
                      kind: foreKinds),
        hind: Outline(p: [SIMD2<Double>(0.03, 0.06), SIMD2<Double>(0.38, 0.06), SIMD2<Double>(0.58, -0.12),
                          SIMD2<Double>(0.68, -0.36), SIMD2<Double>(0.64, -0.62), SIMD2<Double>(0.50, -0.86),
                          SIMD2<Double>(0.28, -0.98), SIMD2<Double>(0.12, -0.88), SIMD2<Double>(0.04, -0.56)],
                      kind: hindKinds),
        tailY: -.infinity)

    static let morpho = WingShape(
        fore: Outline(p: [SIMD2<Double>(0.03, 0.34), SIMD2<Double>(0.34, 0.70), SIMD2<Double>(0.68, 0.94),
                          SIMD2<Double>(0.90, 0.98), SIMD2<Double>(1.00, 0.72), SIMD2<Double>(0.96, 0.34),
                          SIMD2<Double>(0.80, -0.02), SIMD2<Double>(0.40, -0.12), SIMD2<Double>(0.03, -0.10)],
                      kind: foreKinds),
        hind: Outline(p: [SIMD2<Double>(0.03, 0.06), SIMD2<Double>(0.44, 0.06), SIMD2<Double>(0.64, -0.12),
                          SIMD2<Double>(0.76, -0.36), SIMD2<Double>(0.72, -0.64), SIMD2<Double>(0.54, -0.88),
                          SIMD2<Double>(0.30, -1.00), SIMD2<Double>(0.10, -0.90), SIMD2<Double>(0.04, -0.54)],
                      kind: hindKinds),
        tailY: -.infinity)

    static let swallowtail = WingShape(
        fore: Outline(p: [SIMD2<Double>(0.03, 0.34), SIMD2<Double>(0.34, 0.66), SIMD2<Double>(0.68, 0.90),
                          SIMD2<Double>(0.96, 1.02), SIMD2<Double>(0.98, 0.78), SIMD2<Double>(0.86, 0.36),
                          SIMD2<Double>(0.72, -0.02), SIMD2<Double>(0.38, -0.12), SIMD2<Double>(0.03, -0.10)],
                      kind: foreKinds),
        // The tail hangs from the hindwing's lower outer edge, part of its outline.
        hind: Outline(p: [SIMD2<Double>(0.03, 0.06), SIMD2<Double>(0.40, 0.06), SIMD2<Double>(0.58, -0.12),
                          SIMD2<Double>(0.68, -0.36), SIMD2<Double>(0.62, -0.68), SIMD2<Double>(0.56, -1.40),
                          SIMD2<Double>(0.44, -1.40), SIMD2<Double>(0.40, -0.88), SIMD2<Double>(0.20, -0.94),
                          SIMD2<Double>(0.08, -0.84), SIMD2<Double>(0.04, -0.54)],
                      kind: [COSTA, COSTA, OUTER, OUTER, OUTER, OUTER, OUTER, OUTER, INNER, INNER, ROOT]),
        tailY: -0.92)

    static let white = WingShape(
        fore: Outline(p: [SIMD2<Double>(0.03, 0.34), SIMD2<Double>(0.34, 0.72), SIMD2<Double>(0.66, 0.96),
                          SIMD2<Double>(0.88, 0.96), SIMD2<Double>(1.00, 0.66), SIMD2<Double>(0.94, 0.28),
                          SIMD2<Double>(0.74, -0.02), SIMD2<Double>(0.38, -0.12), SIMD2<Double>(0.03, -0.10)],
                      kind: foreKinds),
        hind: Outline(p: [SIMD2<Double>(0.03, 0.06), SIMD2<Double>(0.40, 0.06), SIMD2<Double>(0.58, -0.12),
                          SIMD2<Double>(0.70, -0.38), SIMD2<Double>(0.64, -0.66), SIMD2<Double>(0.46, -0.90),
                          SIMD2<Double>(0.24, -0.98), SIMD2<Double>(0.08, -0.88), SIMD2<Double>(0.04, -0.54)],
                      kind: hindKinds),
        tailY: -.infinity)
}

/// What a wing sample shows.
private let FIELD = 0, MARK = 1, DOT = 2, RING = 3, CENTRE = 4, BLUE = 5, SHINE = 6, SEAM = 7
/// A dark line glyph (`WingHit.line`) on the face's block: an underside's veins and bars, so the folded wing stays one
/// solid shape with its marks drawn on it.
private let LINE = 8

/// Under this projected width a wing is seen edge-on: a line, never blocks (a single banked wing, below the clap).
private let EDGE_ON = 0.18
/// The clap and the closed pose (the restart's design, at the top of its report, carried into flight by fix round 1).
/// Each wing's drawn width is held from a stroke of `HOLD_FROM` at `CLAP_HOLD`, reached exactly where cos(stroke) falls to
/// it, so at zero bank a wing never narrows and widens again within a beat (the flicker rule's two switches); from
/// `TUCK_FROM` to `TUCK_FULL`, inside every species' flight peak (75–80°), the far pair tucks behind the near one, so the
/// clap in flight is the folded side profile: one solid wing pair on the side the butterfly faces. The face turns from
/// upper side to underside over `UNDER_FROM` … `UNDER_FULL`, sweeping in from the tips (the morpho's blue and brown flash
/// in turn). Past the flight's strokes, from `FOLD_FROM` to `FOLD_FULL` (at rest), the near pair opens to the full
/// underside wing beside the body, as a perched butterfly is seen from the side.
private let CLAP_HOLD = 0.72
private let HOLD_FROM = 42.5 * Double.pi / 180, HOLD_FULL = acos(CLAP_HOLD)
private let TUCK_FROM = 60 * Double.pi / 180, TUCK_FULL = 72 * Double.pi / 180
private let UNDER_FROM = 58 * Double.pi / 180, UNDER_FULL = 73 * Double.pi / 180
private let FOLD_FROM = 84 * Double.pi / 180, FOLD_FULL = 89 * Double.pi / 180
/// The width an edge-on wing's outline is traced at, so its forewing and hindwing still read as lines.
private let EDGE_LINE = 0.36

/// One butterfly as drawn this frame: everything the samples read, read once.
private struct Pose {
    let kind: ButterflyKind
    let shape: WingShape
    /// Body centre and axes (pt; `a` up the body toward the head, `r` to its right).
    let x: Double, y: Double
    let ax: Double, ay: Double, rx: Double, ry: Double
    /// The cell, pt; half the span in columns and half the height in rows.
    let cw: Double, ch: Double
    let hsC: Double, hhR: Double
    /// Each wing's projected width, the model's signed cos(stroke ± bank): under 0 the underside shows.
    let sL: Double, sR: Double
    /// Each wing as drawn: its width (≥ 0), and whether it is an edge-on line.
    let wL: Double, wR: Double
    /// How far the underside has swept in from the tips toward the clap, 0…1.
    let turn: Double
    let lineL: Bool, lineR: Bool
    /// How far the tips climb (pt, at the tip): −0.4 row · sin φ drops them on the downstroke.
    let climb: Double
    let id: Double
    let twoSpots: Bool

    init(_ b: Butterfly, cw: Double, ch: Double, id: Double) {
        kind = b.kind
        shape = WingShape.of(b.kind)
        x = b.x + b.drawnOffset.x
        y = b.y + b.drawnOffset.y
        let tilt: Double = b.drawnLean
        ax = sin(tilt)
        ay = -cos(tilt)
        rx = cos(tilt)
        ry = sin(tilt)
        self.cw = cw
        self.ch = ch
        let k: Double = b.scale * b.size * b.fit
        hsC = b.species.drawnSpan * 13 * k / 2 / cw
        hhR = b.species.drawnHeight * 19 * k / 2 / ch
        let s = b.wings()
        sL = s.left
        sR = s.right
        let hold: Double = CLAP_HOLD * smoothstep(HOLD_FROM, HOLD_FULL, b.stroke)
        let tuck: Double = smoothstep(TUCK_FROM, TUCK_FULL, b.stroke)
        let fold: Double = smoothstep(FOLD_FROM, FOLD_FULL, b.stroke)
        // The folded pair shows on the side the butterfly faces; the other tucks behind it.
        let nearRight: Bool = b.bank < -0.05 || (abs(b.bank) <= 0.05 && cos(b.heading) >= -1e-9)
        let heldL: Double = max(abs(sL), hold), heldR: Double = max(abs(sR), hold)
        wL = nearRight ? heldL * (1 - tuck) : heldL + (1 - heldL) * fold
        wR = nearRight ? heldR + (1 - heldR) * fold : heldR * (1 - tuck)
        turn = smoothstep(UNDER_FROM, UNDER_FULL, b.stroke)
        lineL = wL < EDGE_ON && tuck == 0
        lineR = wR < EDGE_ON && tuck == 0
        climb = 0.4 * ch * sin(b.stroke)
        self.id = id
        twoSpots = hash3(id, 7, 3) < 0.5
    }

    /// The drawn width of the wing on `v`'s side, and whether it shows its underside at `X` (half-spans out): past
    /// edge-on, or where the clap's sweep has reached.
    @inline(__always) func width(_ v: Double) -> Double { v < 0 ? wL : wR }
    @inline(__always) func under(_ v: Double, _ X: Double) -> Bool { (v < 0 ? sL : sR) < 0 || X >= 1.2 - 1.3 * turn }
}

/// A wing sample: how much of it is covered (0…1, soft at the edge) and, where covered, what it shows.
private struct WingHit {
    var cover: Double = 0
    var flag = FIELD
    /// 0 forewing, 1 hindwing, 2 the swallowtail's tail.
    var part = 0
    var under = false
    /// Depth inside the outline, cells on screen; the kind of the nearest edge and how far along the outline it is.
    var depth: Double = 0
    var edge = ROOT
    var along: Double = 0
    /// Wing-local position, half-spans and half-heights (unprojected), and on screen in cells from the root.
    var X: Double = 0, Y: Double = 0
    var qx: Double = 0, qy: Double = 0
    var side = 0
    /// The glyph a `LINE` sample draws.
    var line: UInt8 = 0
}

/// Signed distance (cells; < 0 inside) from `q` to an outline scaled by (sx, sy), with the nearest edge's kind and
/// how far along the outline that point is.
@inline(__always) private func outlineDistance(_ o: Outline, _ q: SIMD2<Double>, _ sx: Double, _ sy: Double)
    -> (sd: Double, kind: Int, along: Double) {
    let scale = SIMD2<Double>(sx, sy)
    // Well outside the bounds: the distance to them is near enough (nothing out there is covered or patterned).
    let out: SIMD2<Double> = simd_max(simd_max(o.lo * scale - q, q - o.hi * scale), SIMD2<Double>(0, 0))
    let gap: Double = simd_length(out)
    if gap > 0.5 { return (gap, ROOT, 0) }
    let n = o.p.count
    var inside = false
    var best: Double = .infinity, kind = ROOT, along: Double = 0, run: Double = 0
    var a: SIMD2<Double> = o.p[n - 1] * scale
    var ka = o.kind[n - 1]
    for i in 0..<n {
        let b: SIMD2<Double> = o.p[i] * scale
        if (a.y > q.y) != (b.y > q.y) {
            let xCross: Double = a.x + (b.x - a.x) * (q.y - a.y) / (b.y - a.y)
            if q.x < xCross { inside.toggle() }
        }
        let e: SIMD2<Double> = b - a
        let len2: Double = max(1e-12, simd_length_squared(e))
        let t: Double = clamp(simd_dot(q - a, e) / len2, 0, 1)
        let d: Double = simd_length(q - (a + e * t))
        let len: Double = len2.squareRoot()
        if d < best { best = d; kind = ka; along = run + t * len }
        run += len
        a = b
        ka = o.kind[i]
    }
    return (inside ? -best : best, kind, along)
}

/// How far out (cells) an outline scaled by (sx, sy) reaches at height `y` (cells), or −1 where it doesn't.
@inline(__always) private func outlineReach(_ o: Outline, _ y: Double, _ sx: Double, _ sy: Double) -> Double {
    let n = o.p.count
    var best: Double = -1
    var a = SIMD2<Double>(o.p[n - 1].x * sx, o.p[n - 1].y * sy)
    for i in 0..<n {
        let b = SIMD2<Double>(o.p[i].x * sx, o.p[i].y * sy)
        if (a.y > y) != (b.y > y) { best = max(best, a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)) }
        a = b
    }
    return best
}

/// Distance (cells) from `q` to the segment between two wing-local points scaled by (sx, sy).
@inline(__always) private func segment(_ q: SIMD2<Double>, _ a0: SIMD2<Double>, _ b0: SIMD2<Double>,
                                       _ sx: Double, _ sy: Double) -> Double {
    let scale = SIMD2<Double>(sx, sy)
    let a: SIMD2<Double> = a0 * scale, b: SIMD2<Double> = b0 * scale
    let e: SIMD2<Double> = b - a
    let t: Double = clamp(simd_dot(q - a, e) / max(1e-12, simd_length_squared(e)), 0, 1)
    return simd_length(q - (a + e * t))
}

/// Samples the wings at (px, py).
@inline(__always) private func sampleWing(_ p: Pose, _ px: Double, _ py: Double, _ hit: inout WingHit) {
    hit.cover = 0
    let dx: Double = px - p.x, dy: Double = py - p.y
    let u: Double = dx * p.ax + dy * p.ay
    let v: Double = dx * p.rx + dy * p.ry
    let w: Double = p.width(v)
    guard w >= EDGE_ON else { return }
    // On screen, cells: across from the body and along it, the tips climbing with the stroke.
    let qx: Double = abs(v) / p.cw
    let X: Double = qx / (w * p.hsC)
    guard X < 1.2 else { return }
    let qy: Double = (u - p.climb * min(X, 1.1)) / p.ch
    let Y: Double = qy / p.hhR
    guard Y > -1.6 && Y < 1.2 else { return }
    let q = SIMD2<Double>(qx, qy)
    let sx: Double = w * p.hsC, sy: Double = p.hhR
    let f = outlineDistance(p.shape.fore, q, sx, sy)
    // The forewing lies over the hindwing.
    var sd: Double = f.sd, edge = f.kind, along = f.along, part = 0
    if f.sd > 0 {
        let h = outlineDistance(p.shape.hind, q, sx, sy)
        if h.sd < f.sd { sd = h.sd; edge = h.kind; along = h.along; part = Y < p.shape.tailY ? 2 : 1 }
    }
    // Soft over half a cell at the edge.
    var cover: Double = clamp(0.5 - sd / 0.5, 0, 1)
    // The body's own line stays clear of wing.
    if qx < 0.3 { cover = 0 }
    hit.cover = cover
    guard cover > 0 else { return }
    hit.part = part
    hit.depth = max(0, -sd)
    hit.edge = edge
    hit.along = along
    hit.X = X
    hit.Y = Y
    hit.qx = qx
    hit.qy = qy
    hit.under = p.under(v, X)
    hit.side = v < 0 ? 0 : 1
    hit.flag = pattern(p, &hit, sx, sy)
}

/// The species' markings (research §5.2), each where the real species has it: borders a cell deep along the free
/// edges, veins as lines from the root, spots at fixed places on the wing.
private func pattern(_ p: Pose, _ h: inout WingHit, _ sx: Double, _ sy: Double) -> Int {
    let d: Double = h.depth, X: Double = h.X, Y: Double = h.Y
    let q = SIMD2<Double>(h.qx, h.qy)
    /// Every other cell along the edge.
    let alternate: Bool = Int(floor(h.along / 1.5)) % 2 == 0
    @inline(__always) func near(_ x: Double, _ y: Double, _ r: Double) -> Bool {
        let c = SIMD2<Double>(x * sx, y * sy)
        return simd_length(q - c) < r
    }
    @inline(__always) func vein(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
        segment(q, SIMD2<Double>(x0, y0), SIMD2<Double>(x1, y1), sx, sy) < 0.42
    }
    /// A vein drawn as a line glyph along it, on the face's block.
    func lineVein(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
        guard vein(x0, y0, x1, y1) else { return false }
        let out: Double = h.side == 0 ? -1 : 1
        h.line = lineGlyph(out * (x1 - x0) * sx, -(y1 - y0) * sy)
        return true
    }
    /// How wide this wing is drawn, as a share of open: spots shrink with it so a narrow wing isn't all spots.
    let open: Double = min(1, sx / max(1e-9, p.hsC) / 0.9)
    if h.under {
        // The underside (research §5.4 and the restart's change 1), seen near the clap and folded at rest.
        switch p.kind {
        case .monarch:
            // Pale orange with bold black veins and the white-dotted black border; the apex pale, not black.
            if h.edge == OUTER && d < 0.8 { return alternate && d > 0.15 ? DOT : MARK }
            if h.part == 0 && near(0.84, 0.8, 0.45) { return DOT }
            if h.part == 1 && lineVein(0.1, -0.14, 0.58, -0.5) { return LINE }
            if h.part == 1 && open > 0.7 && lineVein(0.1, -0.24, 0.34, -0.86) { return LINE }
            if h.part == 0 && open > 0.7 && lineVein(0.1, 0.06, 0.8, 0.3) { return LINE }
            return FIELD
        case .morpho:
            // Brown with a row of ringed eyespots along the outer margin, a dark edge.
            let ring: Double = 1.05 * open, eye: Double = 0.45 * open
            for (x, y) in [(0.62, 0.52), (0.7, 0.16), (0.5, -0.3), (0.44, -0.6)] where near(x, y, ring) {
                return near(x, y, eye) ? CENTRE : RING
            }
            if h.edge == OUTER && d < 0.6 { return MARK }
            return FIELD
        case .swallowtail:
            // Pale yellow crossed by dark bands: the veins, a dark outer band, on the hindwing a row of blue and an
            // orange-red spot at the inner corner; the tail dark.
            if h.part == 2 { return MARK }
            if h.part == 1 && near(0.18, -0.82, 0.55 * open + 0.1) { return RING }
            if h.edge == OUTER && d < 0.6 { return MARK }
            if h.part == 1 && h.edge == OUTER && d < 1.3 && alternate { return BLUE }
            if h.part == 0 && h.edge == COSTA && d < 0.7 && X > 0.3 && Int(floor(h.along / 2.4)) % 2 == 0 {
                h.line = MG.MARK[0]
                return LINE
            }
            if h.part == 0 && open > 0.7 && lineVein(0.12, 0.08, 0.76, 0.44) { return LINE }
            if h.part == 1 && open > 0.7 && lineVein(0.12, -0.14, 0.5, -0.56) { return LINE }
            return FIELD
        case .cabbageWhite:
            // Creamy green-yellow, one dark dot on the forewing.
            if h.part == 0 && near(0.55, 0.22, 0.5 * open + 0.1) { return MARK }
            return FIELD
        }
    }
    switch p.kind {
    case .monarch:
        // A black outer border with white dots, a black leading edge and apex with pale spots, a black vein or
        // two; the same below, paler. A darker seam where the forewing lies over the hindwing.
        if h.edge == OUTER && d < 0.8 { return alternate && d > 0.15 ? DOT : MARK }
        if h.part == 0 && X + 0.6 * Y > 1.42 { return near(0.8, 0.86, 0.5) || near(0.94, 0.64, 0.45) ? DOT : MARK }
        if h.part == 0 && h.edge == COSTA && X > 0.45 && d < 0.8 { return MARK }
        if h.part == 1 && (vein(0.1, -0.12, 0.58, -0.42) || vein(0.1, -0.18, 0.4, -0.78)) { return MARK }
        if h.part == 0 && h.edge == INNER && d < 0.8 { return SEAM }
        return FIELD
    case .morpho:
        // Blue with a broad black forewing margin holding white dots, a narrow black hindwing margin, a shine.
        if h.part == 0 && (h.edge == OUTER || h.edge == COSTA) && X > 0.45 && d < 1.3 {
            return near(0.84, 0.78, 0.5) || near(0.95, 0.5, 0.45) ? DOT : MARK
        }
        if h.part == 1 && h.edge == OUTER && d < 0.8 { return alternate && d > 0.15 ? DOT : MARK }
        let band: Double = X - 0.42 + 0.4 * Y
        if abs(band) < 0.06 && d > 0.8 { return SHINE }
        if h.part == 0 && h.edge == INNER && d < 0.8 { return SEAM }
        return FIELD
    case .swallowtail:
        if h.part == 2 { return MARK }
        // A black base; black bars along the forewing's leading edge; a black outer band with yellow lunules;
        // on the hindwing a blue row inside that band and a red-orange eyespot at the inner corner.
        if X < 0.11 { return MARK }
        if h.part == 1 && near(0.18, -0.82, 0.6) { return RING }
        if h.part == 0 && h.edge == COSTA && d < 0.8 && X > 0.2 && Int(floor(h.along / 2.4)) % 2 == 0 { return MARK }
        if h.part == 0 && h.edge == OUTER && d < 1.1 { return d < 0.6 && alternate ? DOT : MARK }
        if h.part == 0 && X + 0.6 * Y > 1.5 { return MARK }
        if h.part == 1 && h.edge == OUTER && d < 1.6 {
            if d < 0.7 { return alternate ? DOT : MARK }
            return Y < -0.2 ? BLUE : MARK
        }
        if h.part == 1 && h.edge == INNER && d < 0.6 { return MARK }
        if h.part == 0 && h.edge == INNER && d < 0.8 { return SEAM }
        return FIELD
    case .cabbageWhite:
        // A black forewing tip and one or two black spots.
        if h.part == 0 && h.edge != INNER && X + 0.5 * Y > 1.18 && d < 1.4 { return MARK }
        if h.part == 0 && near(0.55, 0.3, 0.55) { return MARK }
        if h.part == 0 && p.twoSpots && near(0.5, 0.02, 0.5) { return MARK }
        if h.part == 0 && h.edge == INNER && d < 0.8 { return SEAM }
        return FIELD
    }
}

// ── the painter ──

/// Where painting writes: the canvas, or the cached ground band (its first row is `top`).
private struct Layer {
    var glyph: UnsafeMutablePointer<UInt8>
    var ink: UnsafeMutablePointer<UInt32>
    var block: UnsafeMutablePointer<UInt32>
    var overGlyph: UnsafeMutablePointer<UInt8>
    var overInk: UnsafeMutablePointer<UInt32>
    let cols: Int, rows: Int
    /// The first row and column it holds.
    let top: Int
    var left = 0
    /// When set, only the columns it marks are written.
    var mask: UnsafeMutablePointer<UInt8>? = nil

    @inline(__always) func put(_ c: Int, _ r: Int, _ g: UInt8, _ ink: UInt32, _ block: UInt32 = 0) {
        guard c >= left, c < left + cols, r >= top, r < top + rows else { return }
        if let m = mask, m[c - left] == 0 { return }
        let i = (r - top) * cols + (c - left)
        self.glyph[i] = g
        self.ink[i] = ink
        self.block[i] = block
    }

    @inline(__always) func putOver(_ c: Int, _ r: Int, _ g: UInt8, _ ink: UInt32) {
        guard c >= left, c < left + cols, r >= top, r < top + rows else { return }
        if let m = mask, m[c - left] == 0 { return }
        let i = (r - top) * cols + (c - left)
        overGlyph[i] = g
        overInk[i] = ink
    }
}

/// A butterfly's box from the last frame: where it was, and whose.
private struct Slot {
    var owner: ObjectIdentifier? = nil
    var c0 = 0, r0 = 0, cols = 0, rows = 0
    var nectar = false
}

/// A mote of pollen dust.
private struct Mote {
    var x: Double = 0, y: Double = 0, vx: Double = 0, vy: Double = 0
    var born: Double = 0, life: Double = 0
}

/// What the painter remembers of one screen cell in a butterfly's box: its coverage class (0 empty, 1 edge,
/// 2 full), whether it was last empty (0) or full (1), and when it last switched between them and the time before.
private struct CellMemory {
    var cls: UInt8 = 0
    var solid: UInt8 = 0
    var t1: Double = -.infinity, t2: Double = -.infinity
}

/// One butterfly's box, drawn before it goes on the canvas.
private struct Sprite {
    var glyph = Grow<UInt8>(CellCanvas.noGlyph)
    var ink = Grow<UInt32>(0)
    var block = Grow<UInt32>(0)
    var overGlyph = Grow<UInt8>(CellCanvas.noGlyph)
    var overInk = Grow<UInt32>(0)

    var capacity: Int { glyph.capacity }

    mutating func ensure(_ n: Int) -> Bool {
        var grew = glyph.ensure(n)
        grew = ink.ensure(n) || grew
        grew = block.ensure(n) || grew
        grew = overGlyph.ensure(n) || grew
        grew = overInk.ensure(n) || grew
        return grew
    }

    func clear(_ n: Int) {
        glyph.p.update(repeating: CellCanvas.noGlyph, count: n)
        ink.p.update(repeating: 0, count: n)
        block.p.update(repeating: 0, count: n)
        overGlyph.p.update(repeating: CellCanvas.noGlyph, count: n)
        overInk.p.update(repeating: 0, count: n)
    }

    func layer(cols: Int, rows: Int, left: Int, top: Int) -> Layer {
        Layer(glyph: glyph.p, ink: ink.p, block: block.p, overGlyph: overGlyph.p, overInk: overInk.p, cols: cols,
              rows: rows, top: top, left: left)
    }

    func free() { glyph.free(); ink.free(); block.free(); overGlyph.free(); overInk.free() }
}

/// What the ground band remembers of a plant: what it was drawn with, and the cells it drew over.
private struct PlantMemo {
    var tip = SIMD2<Double>(0, 0)
    var bloom: Double = -1, grown: Double = -1, baseX: Double = 0, baseY: Double = 0
    var rows = -1, kind = -1, boost = 0
    var sparkle = false
    var c0 = 0, c1 = -1, r0 = 0, r1 = -1
    var visible = false
}

/// A plant kind's slot in `HEADS`.
@inline(__always) private func kindSlot(_ k: FlowerKind) -> Int {
    switch k {
    case .milkweed: return 0
    case .coneflower: return 1
    case .fennel: return 2
    case .mustard: return 3
    case .clover: return 4
    case .daisy: return 5
    case .dandelion: return 6
    case .grass: return 7
    }
}

/// `Int(floor(v))` held to ±100 000 cells (NaN gives −100 000): far off but never wrapped onto the canvas.
@inline(__always) private func rowOrCol(_ v: Double) -> Int {
    let f = floor(v)
    guard f >= -100_000 else { return -100_000 }
    return f > 100_000 ? 100_000 : Int(f)
}

/// A species' slot in the painter's tables (a switch: `allCases` would build an array every call).
@inline(__always) private func kindIndex(_ k: ButterflyKind) -> Int {
    switch k {
    case .monarch: return 0
    case .morpho: return 1
    case .swallowtail: return 2
    case .cabbageWhite: return 3
    }
}

/// `Int(floor(v))` held to [-1, `n`] (NaN gives -1), so a far-off but finite point can't trap.
@inline(__always) private func cellIndex(_ v: Double, _ n: Int) -> Int {
    let f = floor(v)
    guard f >= -1 else { return -1 }
    return f > Double(n) ? n : Int(f)
}

/// `Int(floor(v))` held to [lo − 1, hi] (NaN gives lo − 1).
@inline(__always) private func cellIndexIn(_ v: Double, _ lo: Int, _ hi: Int) -> Int {
    let f = floor(v)
    guard f >= Double(lo) else { return lo - 1 }
    return f >= Double(hi) ? hi : Int(f)
}

/// A wing's edge-on line glyph for a direction in cell units: `|` within 26° of upright, else `/` or `\`.
@inline(__always) private func edgeGlyph(_ dc: Double, _ dr: Double) -> UInt8 {
    let a: Double = atan2(abs(dr), abs(dc))
    if a > 1.12 { return MG.pipe }
    return (dc > 0) == (dr < 0) ? MG.slash : MG.back
}

/// The line glyph for a direction in cell units (the silk rule): `|` within 26° of upright, else `/` or `\`.
@inline(__always) private func lineGlyph(_ dc: Double, _ dr: Double) -> UInt8 {
    let a: Double = atan2(abs(dr), abs(dc))
    if a > 1.12 { return MG.pipe }
    if a < 0.32 { return MG.dash }
    return (dc > 0) == (dr < 0) ? MG.slash : MG.back
}

/// Draws a meadow (land, butterflies, breeze) into a `CellCanvas`. Colours come out final: the palette for the
/// theme, Calm applied. Keeps its buffers between frames and allocates nothing once warm.
public final class MeadowPainter {
    private var tone = Tone()
    private var theme: ThemeParams? = nil
    private var plants = PlantInks.make(light: false)
    private var wings: [WingInks] = [WingInks](repeating: WingInks(), count: 4)

    // Anti-flicker: each butterfly's box from the last frame and what is remembered of each cell of it (its
    // coverage class and its last switches), in two buffers swapped every frame; the box is drawn in `sprite` first.
    private var slots = Grow<Slot>(Slot())
    private var memPrev = Grow<CellMemory>(CellMemory())
    private var memNext = Grow<CellMemory>(CellMemory())
    private var sprite = Sprite()
    private var stride = 0

    // The ground band, cached: repainted only when a stem moved more than 0.05 cell (or a bloom, a sparkle, the
    // breeze on a stem, the viewport or the theme changed); otherwise copied.
    private var bandGlyph = Grow<UInt8>(CellCanvas.noGlyph)
    private var bandInk = Grow<UInt32>(0)
    private var bandBlock = Grow<UInt32>(0)
    private var bandOverGlyph = Grow<UInt8>(CellCanvas.noGlyph)
    private var bandOverInk = Grow<UInt32>(0)
    /// Per plant: what it was drawn with and over (`memo`), and what it is now (`fresh`); the dirty columns and
    /// their running count.
    private var memo = Grow<PlantMemo>(PlantMemo())
    private var fresh = Grow<PlantMemo>(PlantMemo())
    private var dirty = Grow<UInt8>(0)
    private var coverage = Grow<Int32>(0)
    private var bandValid = false
    private var bandKey = SIMD4<Double>(0, 0, 0, 0)
    private var bandTop = 0, bandCount = 0, bandCols = 0, bandRows = 0

    // Pollen dust off flowers just left.
    private var motes = Grow<Mote>(Mote())
    private var moteNext = 0
    private static let moteCount = 96

    public init() {
        _ = motes.ensure(MeadowPainter.moteCount)
        for kind in ButterflyKind.allCases { wings[kindIndex(kind)] = WingInks.make(kind, light: false) }
    }

    deinit {
        slots.free(); memPrev.free(); memNext.free(); sprite.free()
        bandGlyph.free(); bandInk.free(); bandBlock.free(); bandOverGlyph.free(); bandOverInk.free()
        memo.free(); fresh.free(); dirty.free(); coverage.free(); motes.free()
    }

    /// How many columns of the ground band the last frame redrew (for the checks: still air redraws none).
    public private(set) var groundColumnsRedrawn = 0

    /// The capacity of every buffer the painter keeps between frames (for the checks: painting a warm meadow
    /// never grows one).
    public var bufferCapacities: [Int] {
        [slots.capacity, memPrev.capacity, memNext.capacity, sprite.capacity, bandGlyph.capacity, bandInk.capacity,
         bandBlock.capacity, bandOverGlyph.capacity, bandOverInk.capacity, memo.capacity, fresh.capacity, dirty.capacity,
         coverage.capacity,
         motes.capacity]
    }

    private func setTheme(_ t: ThemeParams) {
        guard t != theme else { return }
        theme = t
        tone = Tone(light: t.light, brightness: Double(t.brightness), accentRate: Double(t.accentRate))
        plants = PlantInks.make(light: t.light)
        for kind in ButterflyKind.allCases { wings[kindIndex(kind)] = WingInks.make(kind, light: t.light) }
        bandValid = false
    }

    /// Paints the part of the meadow inside `viewport` (habitat space) on `grid` into `canvas`, which arrives
    /// cleared. Sets the canvas's background and grid colour (the Web's). `time` is the meadow's clock, for the
    /// sparkle and the dust.
    public func paint(land: Meadowland, butterflies: [Butterfly], breeze: Breeze, time: Double, viewport: CGRect,
                      grid: GridSpec, theme t: ThemeParams, into canvas: CellCanvas) {
        setTheme(t)
        let bg = WebPainter.background(t)
        canvas.background = bg.rgb
        canvas.gridColor = bg.grid
        let cols = canvas.cols, rows = canvas.rows
        guard cols > 0, rows > 0 else { return }
        let cw = Double(grid.cell.width), ch = Double(grid.cell.height)
        let ox = Double(viewport.minX), oy = Double(viewport.minY)
        guard cw > 0, ch > 0, ox.isFinite, oy.isFinite else { return }

        canvas.glyph.withUnsafeMutableBufferPointer { glyph in
            canvas.ink.withUnsafeMutableBufferPointer { ink in
                canvas.block.withUnsafeMutableBufferPointer { block in
                    canvas.overGlyph.withUnsafeMutableBufferPointer { og in
                        canvas.overInk.withUnsafeMutableBufferPointer { oi in
                            let layer = Layer(glyph: glyph.baseAddress!, ink: ink.baseAddress!, block: block.baseAddress!,
                                              overGlyph: og.baseAddress!, overInk: oi.baseAddress!, cols: cols, rows: rows, top: 0)
                            ground(land, breeze, time, ox, oy, cw, ch, layer)
                            butterflyPass(butterflies, land, breeze, time, ox, oy, cw, ch, layer)
                            dust(time, ox, oy, cw, ch, layer)
                        }
                    }
                }
            }
        }
    }

    // ── ground ──

    /// The cells plant `i` can draw on (its stem, leaves, head and sparkle), in canvas columns and rows, and whether
    /// any of them is in view. Rows are not held to the canvas, so a plant above the view draws nothing in it.
    @inline(__always) private func extent(_ land: Meadowland, _ i: Int, _ ox: Double, _ oy: Double, _ cw: Double,
                                          _ ch: Double, _ cols: Int, _ rows: Int) -> PlantMemo {
        let f = land.flowers[i]
        let h: SIMD2<Double> = land.head(i)
        let size = f.kind.head
        let half: Int = size.cols / 2 + 1
        let baseCol = rowOrCol((f.base.x - ox) / cw), headCol = rowOrCol((h.x - ox) / cw)
        var m = PlantMemo()
        m.c0 = min(baseCol, headCol) - half
        m.c1 = max(baseCol, headCol) + half
        m.r0 = rowOrCol((h.y - oy) / ch) - size.above - 1
        m.r1 = rowOrCol((f.base.y - 0.01 - oy) / ch)
        m.visible = m.c1 >= 0 && m.c0 < cols && m.r1 >= 0 && m.r0 < rows
        return m
    }

    private func ground(_ land: Meadowland, _ breeze: Breeze, _ time: Double, _ ox: Double, _ oy: Double,
                        _ cw: Double, _ ch: Double, _ out: Layer) {
        let flowers = land.flowers
        let n = flowers.count
        groundColumnsRedrawn = 0
        guard n > 0 else { bandValid = false; return }
        let cols = out.cols, rows = out.rows
        // Every buffer is sized once for the whole canvas (the band never outgrows it), and the plant memory with room
        // to spare, so a warm meadow allocates nothing as its heads rise and fall or a few flowers are clicked.
        var grew = false
        grew = bandGlyph.ensure(cols * rows) || grew
        grew = bandInk.ensure(cols * rows) || grew
        grew = bandBlock.ensure(cols * rows) || grew
        grew = bandOverGlyph.ensure(cols * rows) || grew
        grew = bandOverInk.ensure(cols * rows) || grew
        grew = dirty.ensure(cols + 1) || grew
        grew = coverage.ensure(cols + 1) || grew
        if n > memo.capacity { grew = memo.ensure(max(2 * n, 64)) || grew; _ = fresh.ensure(memo.capacity) }
        // The band: from the highest plant in view down to the bottom of the canvas. Plants are culled in both axes.
        var top = rows
        let k: Double = cw / 13
        for i in 0..<n {
            var m = extent(land, i, ox, oy, cw, ch, cols, rows)
            if m.visible {
                let h: SIMD2<Double> = land.head(i)
                // From the head at rest, with room for the sway, so the band's top holds still in a breeze.
                let rest: Int = rowOrCol((h.y - flowers[i].tip.y - oy) / ch) - flowers[i].kind.head.above - 3
                top = min(top, min(rest, m.r0))
                let wind: SIMD2<Double> = breeze.sample(h.x, h.y)
                m.boost = Int((clamp((simd_length(wind) - 45 * k) / (60 * k), 0, 1) * 6).rounded())
            }
            next(&m, flowers[i])
            fresh.p[i] = m
        }
        top = max(0, top)
        guard top < rows else { bandValid = false; return }
        let bandRowsNow = rows - top
        let cells = bandRowsNow * cols
        let key = SIMD4<Double>(ox, oy, cw, ch)
        let full: Bool = grew || !bandValid || key != bandKey || top != bandTop || n != bandCount || cols != bandCols
            || bandRowsNow != bandRows
        let mask = dirty.p
        if full {
            mask.update(repeating: 1, count: cols)
        } else {
            // A plant that moved more than 0.05 cell, opened, grew, sparkles, stirs differently or is another plant
            // (a new layout, a click) dirties the columns it drew over and the ones it draws over now. Every other
            // plant is drawn as it was last drawn (its remembered tip and stir), so redrawing it in a dirty column
            // gives back exactly the cells it had there: the band stays what one full paint would give.
            mask.update(repeating: 0, count: cols)
            for i in 0..<n {
                let was = memo.p[i], now = fresh.p[i]
                if changed(was, now, cw, ch) {
                    if was.visible { mark(was, cols) }
                    if now.visible { mark(now, cols) }
                } else {
                    fresh.p[i] = was
                }
            }
        }
        prefix(cols)
        let anyDirty: Bool = coverage.p[cols] > 0
        groundColumnsRedrawn = Int(coverage.p[cols])
        if anyDirty {
            if top != bandTop || full {
                bandGlyph.p.update(repeating: CellCanvas.noGlyph, count: cells)
                bandInk.p.update(repeating: 0, count: cells)
                bandBlock.p.update(repeating: 0, count: cells)
                bandOverGlyph.p.update(repeating: CellCanvas.noGlyph, count: cells)
                bandOverInk.p.update(repeating: 0, count: cells)
            } else {
                for row in 0..<bandRowsNow {
                    let at = row * cols
                    for c in 0..<cols where mask[c] != 0 {
                        bandGlyph.p[at + c] = CellCanvas.noGlyph
                        bandInk.p[at + c] = 0
                        bandBlock.p[at + c] = 0
                        bandOverGlyph.p[at + c] = CellCanvas.noGlyph
                        bandOverInk.p[at + c] = 0
                    }
                }
            }
            var band = Layer(glyph: bandGlyph.p, ink: bandInk.p, block: bandBlock.p, overGlyph: bandOverGlyph.p,
                             overInk: bandOverInk.p, cols: cols, rows: bandRowsNow, top: top)
            band.mask = mask
            // Leaves, then stems and grass over them, then heads over those, each only in the dirty columns.
            for pass in 0..<3 {
                for i in 0..<n where fresh.p[i].visible && hits(fresh.p[i], cols) {
                    if pass == 2 && flowers[i].kind == .grass { continue }
                    if pass == 2 {
                        head(land, i, fresh.p[i].tip, time, ox, oy, cw, ch, band)
                    } else {
                        stem(land, i, fresh.p[i].tip, fresh.p[i].boost, pass == 0, ox, oy, cw, ch, band)
                    }
                }
            }
        }
        // Remember what each plant is drawn as now.
        (memo.p).update(from: fresh.p, count: n)
        bandValid = true
        bandKey = key
        bandTop = top
        bandCount = n
        bandCols = cols
        bandRows = bandRowsNow
        let at = top * cols
        (out.glyph + at).update(from: bandGlyph.p, count: cells)
        (out.ink + at).update(from: bandInk.p, count: cells)
        (out.block + at).update(from: bandBlock.p, count: cells)
        (out.overGlyph + at).update(from: bandOverGlyph.p, count: cells)
        (out.overInk + at).update(from: bandOverInk.p, count: cells)
    }

    /// Fills in a plant's state as it is now.
    @inline(__always) private func next(_ m: inout PlantMemo, _ f: Flower) {
        m.tip = f.tip
        m.bloom = f.bloom
        m.grown = f.grown
        m.baseX = f.base.x
        m.baseY = f.base.y
        m.rows = f.rows
        m.kind = kindSlot(f.kind)
        m.sparkle = f.sparkle > 0
    }

    @inline(__always) private func changed(_ a: PlantMemo, _ b: PlantMemo, _ cw: Double, _ ch: Double) -> Bool {
        // Split into typed parts for CI's older compiler. The base and the rows drawn over are part of the key, so a
        // sub-pixel relayout that moves a stem's base row redraws (review t5, finding 7).
        let moved: Bool = abs(a.tip.x - b.tip.x) > 0.05 * cw || abs(a.tip.y - b.tip.y) > 0.05 * ch
        let grew: Bool = a.bloom != b.bloom || a.grown != b.grown || a.rows != b.rows || a.kind != b.kind
        let based: Bool = a.baseX != b.baseX || a.baseY != b.baseY
        let looks: Bool = a.visible != b.visible || a.boost != b.boost || a.sparkle || b.sparkle
        let box: Bool = a.c0 != b.c0 || a.c1 != b.c1 || a.r0 != b.r0 || a.r1 != b.r1
        return moved || grew || based || looks || box
    }

    @inline(__always) private func mark(_ m: PlantMemo, _ cols: Int) {
        let a = max(0, m.c0), b = min(cols - 1, m.c1)
        guard a <= b else { return }
        for c in a...b { dirty.p[c] = 1 }
    }

    /// Running count of dirty columns, for `hits`.
    @inline(__always) private func prefix(_ cols: Int) {
        coverage.p[0] = 0
        for c in 0..<cols { coverage.p[c + 1] = coverage.p[c] + Int32(dirty.p[c]) }
    }

    /// Whether any of the plant's columns is dirty.
    @inline(__always) private func hits(_ m: PlantMemo, _ cols: Int) -> Bool {
        let a = max(0, m.c0), b = min(cols - 1, m.c1)
        return a <= b && coverage.p[b + 1] - coverage.p[a] > 0
    }

    /// A stem's (or a grass tuft's) cells between the ground and the head: bent ∝ (height)², each cell's glyph by
    /// its local slope; or (`leaves`) the leaves beside it, opposite pairs on milkweed, alternating on the rest.
    private func stem(_ land: Meadowland, _ i: Int, _ tip: SIMD2<Double>, _ boost: Int, _ leaves: Bool, _ ox: Double,
                      _ oy: Double, _ cw: Double, _ ch: Double, _ out: Layer) {
        var f = land.flowers[i]
        f.tip = tip
        let grass = f.kind == .grass
        if leaves && grass { return }
        let h: SIMD2<Double> = land.head(i) - land.flowers[i].tip + tip
        let len: Double = max(1e-6, f.base.y - (h.y - f.tip.y))
        let stir: Double = Double(boost) / 6
        let base: RGB = grass ? plants.grass : plants.stem
        let color: UInt32 = tone.pack(base + (plants.stirred - base) * (0.45 * stir), grass ? 0.72 + 0.28 * stir : 0.9 + 0.1 * stir)
        let leafInk: UInt32 = tone.pack(plants.leaf + (plants.stirred - plants.leaf) * (0.3 * stir), 0.95)
        let headRow = rowOrCol((h.y - oy) / ch)
        let baseRow = rowOrCol((f.base.y - 0.01 - oy) / ch)
        let lowest = min(baseRow, out.top + out.rows - 1)
        // Below the head's lowest row (a flower) or from the tuft's tip (grass).
        let below: Int = grass ? 0 : f.kind.head.rows - f.kind.head.above
        let first = max(headRow + below, out.top)
        guard first <= lowest else { return }
        let lean: Double = f.tip.x / len
        for row in first...lowest {
            let yc: Double = oy + (Double(row) + 0.5) * ch
            let t: Double = clamp((f.base.y - yc) / len, 0, 1)
            let x: Double = f.base.x + f.tip.x * t * t
            let col = rowOrCol((x - ox) / cw)
            if leaves {
                // Every other row up the stem, never on the ground row.
                let up = baseRow - row
                guard up >= 1 && (up + i) % 2 == 1 && row > headRow + below else { continue }
                let opposite = f.kind == .milkweed
                let right: Bool = opposite || (up / 2 + i) % 2 == 0
                let left: Bool = opposite || !right
                if left { out.put(col - 1, row, MG.back, leafInk) }
                if right { out.put(col + 1, row, MG.slash, leafInk) }
                continue
            }
            var g: UInt8 = lineGlyph(2 * f.tip.x * t / cw, -len / ch)
            if grass && row == first {
                // A tuft's tip: a tick when it stands, a stroke when it leans.
                g = abs(lean) < 0.22 ? (row == lowest ? MG.comma : MG.tick) : (lean > 0 ? MG.slash : MG.back)
            }
            out.put(col, row, g, color)
        }
    }

    /// A flower's head (research §4.1), opening with its bloom, and its pollen sparkle.
    private func head(_ land: Meadowland, _ i: Int, _ tip: SIMD2<Double>, _ time: Double, _ ox: Double, _ oy: Double,
                      _ cw: Double, _ ch: Double, _ out: Layer) {
        let f = land.flowers[i]
        let h: SIMD2<Double> = land.head(i) - f.tip + tip
        let c = rowOrCol((h.x - ox) / cw)
        let r = rowOrCol((h.y - oy) / ch)
        let p = plants
        let open: Double = f.bloom
        // A bud swells, then the petals open and brighten: the middle first, the whole head from 0.6.
        if open < 0.25 {
            out.put(c, r, open < 0.12 ? MG.period : MG.o, tone.pack(p.leaf, 0.6 + open))
            return
        }
        let a: Double = 0.55 + 0.45 * clamp((open - 0.25) / 0.75, 0, 1)
        let full = open >= 0.6
        var petal = RGB(0, 0, 0), eye = RGB(0, 0, 0), eyeBlock = RGB(0, 0, 0), cone = RGB(0, 0, 0)
        switch f.kind {
        case .daisy: petal = p.daisy; eye = p.gold; eyeBlock = p.goldBlock; cone = p.gold
        case .coneflower: petal = p.petals; eye = p.cone; eyeBlock = p.coneBlock; cone = p.cone
        case .milkweed: petal = p.milkweed; eye = p.milkweed; eyeBlock = p.milkweedBlock; cone = p.milkweed
        case .fennel: petal = p.fennel; eye = p.fennel; eyeBlock = p.fennel; cone = p.fennel
        case .clover: petal = p.clover; eye = p.clover; eyeBlock = p.cloverBlock; cone = p.clover
        case .mustard: petal = p.mustard; eye = p.mustard; eyeBlock = p.mustard; cone = p.mustard
        case .dandelion: petal = p.dandelion; eye = p.dandelion; eyeBlock = p.dandelionBlock; cone = p.dandelion
        case .grass: return
        }
        let petalInk: UInt32 = tone.pack(petal, a), eyeInk: UInt32 = tone.pack(eye, a), coneInk: UInt32 = tone.pack(cone, a)
        let block: UInt32 = tone.pack(eyeBlock, a)
        let leaf: UInt32 = tone.pack(p.leaf, 0.95), stemInk: UInt32 = tone.pack(p.stem, 0.9)
        let florets: [Floret] = HEADS[kindSlot(f.kind)]
        for fl in florets {
            if !full && (fl.dr != 0 || abs(fl.dc) > 1) { continue }
            switch fl.role {
            case EYE: out.put(c + fl.dc, r + fl.dr, fl.glyph, eyeInk, block)
            case CONE: out.put(c + fl.dc, r + fl.dr, fl.glyph, coneInk)
            case LEAF: out.put(c + fl.dc, r + fl.dr, fl.glyph, leaf)
            case STEM: out.put(c + fl.dc, r + fl.dr, fl.glyph, stemInk)
            default: out.put(c + fl.dc, r + fl.dr, fl.glyph, petalInk)
            }
        }
        if f.sparkle > 0 {
            // Pollen twinkling over a fresh bloom, at the theme's accent rate.
            let tick: Double = floor(time * 2.4 * 2)
            let roll: Double = hash3(Double(i), tick, 11)
            if roll < 0.75 * tone.accentRate {
                let dc = Int(floor(hash3(Double(i), tick, 12) * 3)) - 1
                out.putOver(c + dc, r - f.kind.head.above - (roll < 0.3 ? 1 : 0), roll < 0.2 ? MG.plus : MG.dot,
                            tone.pack(p.gold, f.sparkle))
            }
        }
    }

    // ── butterflies ──

    private func butterflyPass(_ flies: [Butterfly], _ land: Meadowland, _ breeze: Breeze, _ time: Double,
                               _ ox: Double, _ oy: Double, _ cw: Double, _ ch: Double, _ out: Layer) {
        let n = flies.count
        // Every box is a square of reach R around the body; one stride fits the biggest. Sized up front for the
        // cap of butterflies on a screen, each the biggest a species grows to at this cell, so adding butterflies
        // allocates nothing (the restart's change 4); only more than the cap, or a bigger scale, grows them.
        @inline(__always) func box(_ r: Double) -> Int { (2 * Int(ceil(r / cw)) + 1) * (2 * Int(ceil(r / ch)) + 1) }
        var want = stride
        for sp in MeadowPainter.species { want = max(want, box(reach(sp, cw / 13 * (1 + sp.sizeSpread), cw))) }
        for b in flies { want = max(want, box(reach(b.species, b.scale * b.size, cw))) }
        var grew = false
        if want != stride { stride = want; grew = true }
        let room: Int = max(MeadowPainter.flockCap, n)
        grew = slots.ensure(room) || grew
        grew = memPrev.ensure(room * stride) || grew
        grew = memNext.ensure(room * stride) || grew
        _ = sprite.ensure(stride)
        if grew {
            for k in 0..<slots.capacity { slots.p[k] = Slot() }
            memPrev.p.update(repeating: CellMemory(), count: memPrev.capacity)
        }
        for k in 0..<n {
            let b = flies[k]
            var slot = slots.p[k]
            if slot.owner != ObjectIdentifier(b) { slot = Slot(); slot.owner = ObjectIdentifier(b); slot.nectar = b.state == .nectar }
            // Leaving a flower: pollen dust off its head.
            let nectar = b.state == .nectar
            if slot.nectar && !nectar { shed(b, land, breeze, time) }
            slot.nectar = nectar
            drawButterfly(b, k, &slot, time, ox, oy, cw, ch, out)
            slots.p[k] = slot
        }
        for k in n..<slots.capacity { slots.p[k].owner = nil }
        swap(&memPrev, &memNext)
    }

    /// Butterflies a screen holds at most (plan T3's cap), for sizing the per-butterfly buffers up front.
    static let flockCap = 16
    /// Every species, read once (`allCases` would build an array every frame).
    private static let species: [ButterflySpecies] = ButterflyKind.allCases.map { (k: ButterflyKind) -> ButterflySpecies in
        ButterflySpecies.of(k)
    }

    /// How far from its body a butterfly of `sp` at scale × size `k` can draw, pt: the wings (the swallowtail's
    /// tails reach 1.4 half-heights down) and the antennae.
    private func reach(_ sp: ButterflySpecies, _ k: Double, _ cw: Double) -> Double {
        let hs: Double = sp.drawnSpan * 13 * k / 2, hh: Double = sp.drawnHeight * 19 * k / 2
        let r: Double = max(hs * 1.1, hh * 1.5 + 0.6 * cw) + cw
        return r.isFinite ? min(r, 4000) : 0
    }

    private func drawButterfly(_ b: Butterfly, _ k: Int, _ slot: inout Slot, _ time: Double, _ ox: Double, _ oy: Double,
                               _ cw: Double, _ ch: Double, _ out: Layer) {
        let lx: Double = b.x + b.drawnOffset.x - ox, ly: Double = b.y + b.drawnOffset.y - oy
        guard lx.isFinite, ly.isFinite, b.stroke.isFinite, b.bank.isFinite, b.heading.isFinite, b.pitch.isFinite else {
            slot.owner = nil
            return
        }
        let r: Double = reach(b.species, b.scale * b.size, cw)
        let hc = Int(ceil(r / cw)), hr = Int(ceil(r / ch))
        let bw = 2 * hc + 1, bh = 2 * hr + 1
        let cc = cellIndex(lx / cw, out.cols), rc = cellIndex(ly / ch, out.rows)
        // Culled: nowhere near the viewport.
        guard bw * bh <= stride, cc + hc >= 0, cc - hc < out.cols, rc + hr >= 0, rc - hr < out.rows,
              lx > -r - cw, ly > -r - ch, lx < Double(out.cols) * cw + r + cw, ly < Double(out.rows) * ch + r + ch else {
            slot.owner = nil
            return
        }
        let c0 = cc - hc, r0 = rc - hr
        let prev = memPrev.p + k * stride, next = memNext.p + k * stride
        let kind = kindIndex(b.kind)
        let ink: WingInks = wings[kind]
        let pose = Pose(b, cw: cw, ch: ch, id: Double(k) * 17 + Double(kind))
        // The butterfly is drawn into its own box first, then each cell's switch is held to the beat, then copied.
        let cells = bw * bh
        sprite.clear(cells)
        let box = sprite.layer(cols: bw, rows: bh, left: c0, top: r0)
        var hit = WingHit()
        for row in 0..<bh {
            for col in 0..<bw {
                let c = c0 + col, rr = r0 + row
                // Last frame's memory of this screen cell, if it was in last frame's box.
                var mem = CellMemory()
                let pc = c - slot.c0, pr = rr - slot.r0
                if slot.cols > 0 && pc >= 0 && pc < slot.cols && pr >= 0 && pr < slot.rows { mem = prev[pr * slot.cols + pc] }
                let x: Double = ox + Double(c) * cw, y: Double = oy + Double(rr) * ch
                var sum: Double = 0
                var best = WingHit()
                for s in 0..<5 {
                    let fx: Double = s == 0 ? 0.5 : (s == 1 || s == 3 ? 0.25 : 0.75)
                    let fy: Double = s == 0 ? 0.5 : (s < 3 ? 0.3 : 0.72)
                    sampleWing(pose, x + fx * cw, y + fy * ch, &hit)
                    sum += hit.cover
                    if s == 0 ? hit.cover > 0 : hit.cover > best.cover + 0.25 { best = hit }
                }
                let cover: Double = sum / 5
                // Coverage class with hysteresis: 0 empty, 1 edge, 2 full.
                var now: UInt8
                switch mem.cls {
                case 2: now = cover >= 0.45 ? 2 : (cover >= 0.08 ? 1 : 0)
                case 1: now = cover >= 0.65 ? 2 : (cover >= 0.08 ? 1 : 0)
                default: now = cover >= 0.65 ? 2 : (cover >= 0.28 ? 1 : 0)
                }
                if best.cover == 0 { now = min(now, cover > 0 ? 1 : 0) }
                mem.cls = now
                next[row * bw + col] = mem
                guard now > 0 else { continue }
                paintWingCell(pose, ink, best, now, cover, c, rr, time, box)
            }
        }
        edgeOn(pose, ink, ox, oy, cw, ch, box)
        body(b, pose, ink, ox, oy, cw, ch, box)
        // At most two switches between empty and full in any beat (the wings open and close once): a cell that
        // would switch a third time within a beat of the switch before last is held as a line glyph without its
        // block. That is how the model's real projected width (which narrows again at the bottom of the downstroke)
        // is drawn without flicker: the narrowing shows as the tips' blocks giving way to glyphs.
        let period: Double = 1 / (b.species.beat * min(1, max(0.5, b.beatFactor)))
        let faint: UInt32 = tone.pack(ink.glyph, 0.5)
        for i in 0..<cells {
            var mem = next[i]
            let hasBlock: Bool = box.block[i] >> 24 != 0
            let hasGlyph: Bool = box.glyph[i] != CellCanvas.noGlyph
            let state: UInt8 = hasBlock ? 1 : (hasGlyph ? 2 : 0)
            if state != 2 && state != mem.solid {
                if time - mem.t2 >= period * 0.999 || time < mem.t1 {
                    mem.solid = state
                    mem.t2 = mem.t1
                    mem.t1 = time
                } else if hasBlock {
                    box.block[i] = 0
                    if !hasGlyph { box.glyph[i] = MG.colon; box.ink[i] = faint }
                } else {
                    box.glyph[i] = (i & 1) == 0 ? MG.period : MG.tick
                    box.ink[i] = faint
                }
            }
            next[i] = mem
            let c = c0 + i % bw, rr = r0 + i / bw
            guard c >= 0, c < out.cols, rr >= 0, rr < out.rows else { continue }
            if box.glyph[i] != CellCanvas.noGlyph || box.block[i] >> 24 != 0 { out.put(c, rr, box.glyph[i], box.ink[i], box.block[i]) }
            if box.overGlyph[i] != CellCanvas.noGlyph { out.putOver(c, rr, box.overGlyph[i], box.overInk[i]) }
        }
        slot.c0 = c0; slot.r0 = r0; slot.cols = bw; slot.rows = bh
    }

    private func paintWingCell(_ p: Pose, _ ink: WingInks, _ h: WingHit, _ cls: UInt8, _ cover: Double, _ c: Int, _ r: Int,
                               _ time: Double, _ out: Layer) {
        // Keyed by where the cell is on the wing, so glyphs ride with it.
        let key = UInt32(hash3((h.X * p.hsC).rounded(), (h.Y * p.hhR).rounded(), p.id * 8 + Double(h.part + 3 * h.side)) * 4_294_967_295)
        let faceBlock: RGB = h.under ? ink.underBlock : ink.block
        let faceGlyph: RGB = h.under ? ink.underGlyph : ink.glyph
        if cls == 1 {
            // An edge: a light glyph, no block.
            let set = cover >= 0.55 ? MG.EDGE_HEAVY : MG.EDGE_LIGHT
            let edgeInk: RGB = h.flag == MARK || h.flag == DOT ? ink.markInk : faceGlyph
            out.put(c, r, set[Int((key >> 8) % UInt32(set.count))], tone.pack(edgeInk, 0.55 + 0.45 * cover))
            return
        }
        // Lit from the top-left and a little darker toward the edges, as the spiders are; on paper it darkens
        // toward the ink, never toward the paper.
        let lit: Double = clamp(0.5 + 0.25 * min(h.depth, 2) + 0.12 * h.Y - 0.1 * h.X, 0, 1)
        let shaded: RGB = tone.light ? faceBlock + (INK - faceBlock) * (0.12 * (1 - lit)) : faceBlock * (0.88 + 0.16 * lit)
        switch h.flag {
        case MARK:
            let g: UInt8 = (key >> 6) % 3 == 0 ? MG.MARK[Int((key >> 8) % 2)] : CellCanvas.noGlyph
            out.put(c, r, g, tone.pack(ink.markInk), tone.pack(ink.markBlock))
        case DOT:
            out.put(c, r, (key >> 4) % 3 == 0 ? MG.dot : MG.ring, tone.pack(ink.dot), tone.pack(ink.markBlock))
        case RING:
            // On paper the ring's block is a tint of its ink, so the `o` shows on it.
            out.put(c, r, MG.o, tone.pack(ink.ring), tone.pack(tone.light ? PAPER + (ink.ring - PAPER) * 0.45 : ink.ring * 0.62))
        case CENTRE:
            out.put(c, r, MG.at, tone.pack(ink.ring), tone.pack(ink.centre))
        case BLUE:
            out.put(c, r, CellCanvas.noGlyph, 0, tone.pack(ink.blue))
        case SHINE:
            // The morpho's sheen: a paler band, glinting at the spiders' accent tick.
            let tick: Double = floor(time * 2.4)
            let glint: Bool = hash3(Double(key & 0xffff), tick, 5) < 0.35 * tone.accentRate
            out.put(c, r, glint ? MG.dot : CellCanvas.noGlyph, tone.pack(ink.glyph), tone.pack(ink.shine))
        case LINE:
            out.put(c, r, h.line, tone.pack(ink.markBlock), tone.pack(shaded))
        case SEAM:
            let k: Double = p.kind == .cabbageWhite ? 0.5 : 1
            out.put(c, r, CellCanvas.noGlyph, 0, tone.pack(tone.light ? shaded + (INK - shaded) * (0.1 * k) : shaded * (1 - 0.2 * k)))
        default:
            // Mostly a solid block; a few texture glyphs ride with the wing.
            let g: UInt8 = (key >> 4) % 7 == 0 ? MG.EDGE_HEAVY[Int((key >> 8) % 2)] : CellCanvas.noGlyph
            out.put(c, r, g, tone.pack(faceGlyph, 0.8), tone.pack(shaded))
        }
    }

    /// A wing seen edge-on (|s| < 0.18): its outer contour as one line of glyphs, row by row down the body (`|`
    /// beside it, `/` `\` where the forewing's apex slants out and the notch above the hindwing slants in), in the
    /// underside colour, never blocks.
    private func edgeOn(_ p: Pose, _ ink: WingInks, _ ox: Double, _ oy: Double, _ cw: Double, _ ch: Double, _ out: Layer) {
        let color: UInt32 = tone.pack(ink.underGlyph)
        let sx: Double = EDGE_LINE * p.hsC, sy: Double = p.hhR
        @inline(__always) func reach(_ y: Double) -> Double {
            max(outlineReach(p.shape.fore, y, sx, sy), outlineReach(p.shape.hind, y, sx, sy))
        }
        for side in 0..<2 {
            guard side == 0 ? p.lineL : p.lineR else { continue }
            let sign: Double = side == 0 ? -1 : 1
            var y: Double = sy * 1.05
            while y > -sy * 1.5 {
                let x: Double = reach(y)
                if x > 0 {
                    // The contour's direction over this row, on screen.
                    let up: Double = max(0.75, max(reach(y + 0.5), 0)), down: Double = max(0.75, max(reach(y - 0.5), 0))
                    let dc: Double = sign * (up - down), dr: Double = 1
                    let sdx: Double = p.rx * dc * cw + p.ax * dr * ch, sdy: Double = p.ry * dc * cw + p.ay * dr * ch
                    let across: Double = sign * max(0.75, x) * cw
                    let along: Double = y * ch + p.climb * min(x / max(1e-9, sx), 1.1)
                    let px: Double = p.x + p.rx * across + p.ax * along, py: Double = p.y + p.ry * across + p.ay * along
                    out.put(cellIndexIn((px - ox) / cw, out.left, out.left + out.cols),
                            cellIndexIn((py - oy) / ch, out.top, out.top + out.rows), edgeGlyph(sdx / cw, sdy / ch), color)
                }
                y -= 1
            }
        }
    }

    /// Head, thorax and abdomen as a dark column on blocks, so the two wings read either side of it; antennae
    /// standing clear above the head with clubs; the proboscis when nectaring.
    private func body(_ b: Butterfly, _ p: Pose, _ ink: WingInks, _ ox: Double, _ oy: Double, _ cw: Double, _ ch: Double,
                      _ out: Layer) {
        @inline(__always) func cell(_ along: Double, _ across: Double) -> (Int, Int) {
            let x: Double = p.x + p.ax * along * ch + p.rx * across * cw
            let y: Double = p.y + p.ay * along * ch + p.ry * across * cw
            return (cellIndexIn((x - ox) / cw, out.left, out.left + out.cols), cellIndexIn((y - oy) / ch, out.top, out.top + out.rows))
        }
        let block: UInt32 = tone.pack(ink.bodyBlock)
        let lit: UInt32 = tone.pack(ink.bodyGlyph)
        let head: Double = 0.42 * p.hhR + 0.3, tail: Double = -0.66 * p.hhR
        var along: Double = head, i = 0
        while along >= tail {
            let g: UInt8 = i == 0 ? MG.o : (i <= 2 ? MG.eight : (along - 1 < tail ? MG.colon : MG.pipe))
            let at = cell(along, 0)
            out.put(at.0, at.1, g, lit, block)
            along -= 1
            i += 1
        }
        // Antennae: two cells each, out and up from the head, clubbed, swaying a little with the bob.
        let sway: Double = 0.12 * sin(b.phase)
        let tilt: Double = atan2(p.ax, -p.ay)
        let lg: UInt8 = tilt > 0.45 ? MG.pipe : MG.back, rg: UInt8 = tilt < -0.45 ? MG.pipe : MG.slash
        let club: UInt32 = tone.pack(ink.feeler)
        for k in 1...2 {
            let l = cell(head + Double(k), -Double(k) + sway), r = cell(head + Double(k), Double(k) + sway)
            out.put(l.0, l.1, lg, club)
            out.put(r.0, r.1, rg, club)
        }
        let lc = cell(head + 3, -2.6 + sway), rc = cell(head + 3, 2.6 + sway)
        out.putOver(lc.0, lc.1, MG.ring, club)
        out.putOver(rc.0, rc.1, MG.ring, club)
        if b.state == .nectar {
            let tip = cell(head + 1, 0)
            out.put(tip.0, tip.1, MG.pipe, club)
        }
    }

    // ── dust ──

    /// A butterfly has just left a flower: pollen motes drift off the nearest head.
    private func shed(_ b: Butterfly, _ land: Meadowland, _ breeze: Breeze, _ time: Double) {
        let flowers = land.flowers
        var best = -1, bestD: Double = .infinity
        for i in 0..<flowers.count where flowers[i].kind != .grass {
            let h: SIMD2<Double> = land.head(i)
            let d: Double = (h.x - b.x) * (h.x - b.x) + (h.y - b.y) * (h.y - b.y)
            if d < bestD { bestD = d; best = i }
        }
        let from: SIMD2<Double> = best >= 0 && bestD < 4 * b.wingspan * b.wingspan ? land.head(best) : SIMD2<Double>(b.x, b.y)
        guard from.x.isFinite && from.y.isFinite else { return }
        let wind: SIMD2<Double> = breeze.sample(from.x, from.y)
        let k: Double = b.scale
        for m in 0..<5 {
            let h1: Double = hash3(time, Double(m), 21), h2: Double = hash3(time, Double(m), 22), h3: Double = hash3(time, Double(m), 23)
            var mote = Mote()
            mote.x = from.x + (h1 - 0.5) * 26 * k
            mote.y = from.y - h2 * 10 * k
            mote.vx = 0.25 * wind.x + (h2 - 0.5) * 14 * k
            mote.vy = 0.1 * wind.y - (4 + 6 * h3) * k
            mote.born = time
            mote.life = 3 + 3 * h1
            motes.p[moteNext] = mote
            moteNext = (moteNext + 1) % MeadowPainter.moteCount
        }
    }

    private func dust(_ time: Double, _ ox: Double, _ oy: Double, _ cw: Double, _ ch: Double, _ out: Layer) {
        for m in 0..<MeadowPainter.moteCount {
            let mote = motes.p[m]
            guard mote.life > 0 else { continue }
            let age: Double = time - mote.born
            if age < 0 || age > mote.life { motes.p[m].life = 0; continue }
            let x: Double = mote.x + mote.vx * age, y: Double = mote.y + mote.vy * age
            let c = cellIndex((x - ox) / cw, out.cols), r = cellIndex((y - oy) / ch, out.rows)
            let fade: Double = 1 - age / mote.life
            out.putOver(c, r, fade > 0.5 ? MG.dot : MG.period, tone.pack(plants.gold, 0.9 * fade))
        }
    }
}

// ── How far a drawing reaches (for the flight's hard walls) ──

extension Butterfly {
    /// The lean the painter draws the body at, radians (+ head to the right): toward where it flies, pitching with the
    /// stroke, never far from upright.
    var drawnLean: Double {
        let side: Double = cos(heading) >= 0 ? 1 : -1
        return leanRoom * clamp(0.3 * cos(heading) - 0.5 * pitch * side, -0.5, 0.5)
    }

    /// How far the painter's drawing of this butterfly reaches from where its body is drawn, pt, as (left, right, up,
    /// down), leaning by `lean`, its tips climbing `climb` pt, drawn at `fit` of its size, on cells of `cw` × `ch` pt.
    /// It holds every point the painter puts a glyph at (body, antennae and clubs, proboscis, edge-on lines) and every
    /// point a wing sample can cover: the outlines at any drawn width from 0 to open, softened by a quarter cell (a
    /// sample covers within a quarter cell of the outline). So each cell the painter draws holds a point inside it.
    func drawnExtent(lean: Double, climb: Double, fit: Double, cw: Double, ch: Double) -> SIMD4<Double> {
        let k: Double = scale * size * fit
        let hs: Double = species.drawnSpan * 13 * k / 2, hh: Double = species.drawnHeight * 19 * k / 2
        let rows: Double = hh / ch
        let c: Double = cos(lean), s: Double = sin(lean)
        var lo = SIMD2<Double>(0, 0), hi = SIMD2<Double>(0, 0)
        /// A point `v` pt across the body (+ right) and `u` pt along it (+ toward the head).
        @inline(__always) func add(_ v: Double, _ u: Double) {
            let q = SIMD2<Double>(c * v + s * u, s * v - c * u)
            lo = simd_min(lo, q)
            hi = simd_max(hi, q)
        }
        /// An outline's corners at no width and open, both sides, and where an edge-on line is put (0.75 column out).
        func outline(_ o: Outline) {
            for p in o.p {
                let u: Double = p.y * hh + climb * min(p.x, 1.1)
                add(0, u)
                add(p.x * hs, u)
                add(-p.x * hs, u)
                add(0.75 * cw, u)
                add(-0.75 * cw, u)
            }
        }
        let shape = WingShape.of(kind)
        outline(shape.fore)
        outline(shape.hind)
        // The body, from the head's `o` to the tail; the proboscis; the antennae and their clubs (with the sway).
        let head: Double = 0.42 * rows + 0.3, tail: Double = -0.66 * rows
        add(0, (head + 1) * ch)
        add(0, tail * ch)
        add(2.12 * cw, (head + 2) * ch)
        add(-2.12 * cw, (head + 2) * ch)
        add(2.72 * cw, (head + 3) * ch)
        add(-2.72 * cw, (head + 3) * ch)
        // The soft edge, a quarter cell across and along (and the tips' climb past the outline's widest point).
        let pv: Double = 0.25 * cw, pu: Double = 0.25 * ch + 0.2 * abs(climb)
        let px: Double = abs(c) * pv + abs(s) * pu, py: Double = abs(s) * pv + abs(c) * pu
        return SIMD4<Double>(px - lo.x, hi.x + px, py - lo.y, hi.y + py)
    }
}
