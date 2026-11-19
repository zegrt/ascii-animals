import CoreGraphics
import Foundation

// Port of renderer.ts from ascii-spiders by @stackedlol (MIT), commit 89a7721, onto the shared cell canvas.
// See docs/reference/web-port-notes.md for what differs and why.

/**
 * Draws the World as a grid of ASCII cells, in the ascii-sharks hand (same grid, same font, same
 * paper and black):
 *
 *   silk    every thread is sampled through the cells it crosses. Each cell keeps the thread's direction,
 *           how much thread it holds, and where in the cell it runs, then picks one glyph: - _ ¯ for level
 *           threads, / \ | for the rest; where threads cross the strongest runs on through, and only the
 *           hub gets a * knot. Silk is faint, and brightens (cyan on black) where it is ringing.
 *   dew     a few beads on the capture spiral that twinkle.
 *   flies   one glyph each: x/+ on the wing, a stuck one thrashing, a wrapped one as @ shrinking to ·.
 *   spiders legs as stroke glyphs; bodies supersampled into blocks with carved glyphs, shaded from the
 *           top-left like the sharks, with each species' markings.
 */

private let LEVELS = 24

/// Atlas slots, looked up once.
private enum G {
    static func i(_ c: Character) -> UInt8 { GlyphAtlas.index(c)! }
    static let over = i("¯"), under = i("_"), dash = i("-"), pipe = i("|"), back = i("\\"), slash = i("/")
    static let star = i("*"), dot = i("·"), plus = i("+"), x = i("x"), pct = i("%"), at = i("@"), zero = i("0"), o = i("o")
    static let eyeDark = i("O"), v = i("v")
    static let SKIN_RAMP = ":;t%SX8#@".map(i)
    static let MARK_GLYPHS = "#%@".map(i)
    static let SPOT_GLYPHS = "o°o".map(i)
    static let EDGE_HEAVY = ":;".map(i)
    static let EDGE_LIGHT = ".',`".map(i)
}

// Body cells.
private let BODY = 1
private let MARK = 3
private let SPOT = 4
private let EYE = 5
private let FANG = 6
private let CROSS = 7
private let BAND = 8
private let SUBSAMPLES: [Double] = [0.25, 0.3, 0.75, 0.3, 0.25, 0.72, 0.75, 0.72]

private typealias RGB = (Double, Double, Double)
private let PAPER: RGB = (247, 246, 243)
private let INK: RGB = (35, 35, 35)
private let ACCENTS: [RGB] = [(224, 137, 44), (224, 58, 50), (180, 74, 224), (51, 200, 204), (60, 181, 74), (49, 80, 232), (217, 193, 74)]

/// `PALETTES` from renderer.ts. The light `accents` list is empty.
private struct Palette {
    let light: Bool
    let silk: RGB, ring: RGB, dew: RGB, fly: RGB, heat: RGB
    let silkGain: Double
    let glyphLit: RGB, glyphShadow: RGB, eye: RGB, fleck: RGB, spot: RGB, fang: RGB
    let accents: [RGB]

    static let dark = Palette(
        light: false, silk: (214, 222, 238), ring: (110, 230, 255), dew: (240, 246, 255), fly: (226, 234, 250),
        heat: (255, 120, 60), silkGain: 1, glyphLit: (14, 15, 19), glyphShadow: (27, 29, 36), eye: (215, 222, 236),
        fleck: (255, 255, 255), spot: (242, 246, 255), fang: (51, 200, 204), accents: ACCENTS)
    // Graphite on paper, as in ascii-sharks: lit surfaces fade toward the paper, shadow sinks toward the ink.
    static let light = Palette(
        light: true, silk: INK, ring: INK, dew: INK, fly: INK, heat: INK, silkGain: 0.85,
        glyphLit: (35, 35, 35), glyphShadow: (22, 22, 22), eye: PAPER, fleck: PAPER, spot: PAPER, fang: PAPER, accents: [])

    /// Legs stand out from the silk as filled cells: a bright glyph on a dim block on black, and a dark glyph on
    /// a pale graphite block on paper.
    @inline(__always) func legLevel(_ l: Double) -> Double { light ? 250 - l * 1.25 : l * 1.12 }
    @inline(__always) func legBlock(_ l: Double) -> Double { light ? 250 - l * 0.5 : l * 0.34 }

    @inline(__always) func tone(_ level: Double, _ tr: Double, _ tg: Double, _ tb: Double) -> RGB {
        if !light {
            return (min(255, mathRound(level * tr)), min(255, mathRound(level * tg)), min(255, mathRound(level * tb + 4)))
        }
        let k = clamp(level / 255, 0, 1)
        @inline(__always) func ch(_ ink: Double, _ paper: Double, _ t: Double) -> Double {
            max(0, min(paper, mathRound((ink + (paper - ink) * k) * (1 + (t - 1) * 0.5))))
        }
        return (ch(INK.0, PAPER.0, tr), ch(INK.1, PAPER.1, tg), ch(INK.2, PAPER.2, tb))
    }
}

/// `Number.prototype.toFixed(n)` for the small positive alphas the original formats.
@inline(__always) private func toFixed(_ x: Double, _ n: Double) -> Double { mathRound(x * n) / n }

/// The glyph for a direction (as cos 2φ, sin 2φ) and where in the cell it runs (0 top → 1 bottom).
@inline(__always) private func lineGlyph(_ nc: Double, _ ns: Double, _ m: Double) -> UInt8 {
    let phi = 0.5 * atan2(ns, nc)
    let a = abs(phi)
    if a < 0.5 { return m < 0.3 ? G.over : m > 0.7 ? G.under : G.dash }
    if a > 1.12 { return G.pipe }
    return phi > 0 ? G.back : G.slash
}

/**
 * The glyph for a cell of thread, from its accumulated direction moments. Only the hub, where the radials
 * all meet, gets a knot; where two or three threads cross, the strongest runs on through (radials over
 * the finer spiral), so the web reads as clean lines instead of a field of + and x.
 */
@inline(__always) private func strokeGlyph(_ cov: Double, _ c2: Double, _ s2: Double, _ v: Double, _ count: Int,
                                           _ dc: Double, _ ds: Double, _ dv: Double) -> UInt8 {
    let nc = c2 / cov
    let ns = s2 / cov
    if count >= 4 && hypot(nc, ns) < 0.6 { return G.star }
    if count >= 2 { return lineGlyph(dc, ds, dv) }
    return lineGlyph(nc, ns, v / cov)
}


// ── speed ──
//
// The hot loops below run on values (`StrokeAcc`, `Pass`, `Body`) holding raw buffers, never on class
// properties: Swift checks exclusive access to a class's stored property at run time, on every read and
// write, and here that cost more than the drawing itself. Each class hands its state to a value once per
// call and takes it back after, so the arithmetic, and its order, is unchanged.

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

/// The thread accumulated in one cell: renderer.ts `Strokes`' typed arrays, kept side by side so a plot
/// touches one record instead of a dozen arrays.
struct StrokeCell {
    var cov: Float = 0, c2: Float = 0, s2: Float = 0, v: Float = 0
    /// The strongest thread's direction and place in the cell: it runs on through a crossing.
    var dc: Float = 0, ds: Float = 0, dv: Float = 0
    /// Brightness, and how hard the silk there is ringing.
    var a: Float = 0, e: Float = 0
    var last: Int32 = 0
    var seen: UInt32 = 0
    var count: UInt16 = 0
}

/// `WebStrokes`' state as a value (its memory belongs to the `WebStrokes`).
struct StrokeAcc {
    fileprivate var cell: UnsafeMutablePointer<StrokeCell>
    fileprivate var list: UnsafeMutablePointer<Int32>
    fileprivate var capacity = 1
    fileprivate(set) var cols = 0
    fileprivate(set) var rows = 0
    fileprivate(set) var length = 0
    fileprivate var frame: UInt32 = 0
    fileprivate var line: Int32 = 0
    /// Webs come far to near; a clearly nearer thread hides a farther one.
    var layered = false

    fileprivate init(cell: UnsafeMutablePointer<StrokeCell>, list: UnsafeMutablePointer<Int32>) {
        self.cell = cell
        self.list = list
    }

    mutating func begin() {
        frame &+= 1
        if frame == 0 {
            // Wrapped: stale stamps could match again.
            for i in 0..<capacity { cell[i].seen = 0 }
            frame = 1
        }
        length = 0
    }

    /// See `WebStrokes.add`.
    mutating func add(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ cw: Double, _ ch: Double, _ a: Double, _ e: Double = 0) {
        let gx0 = x0 / cw
        let gy0 = y0 / ch
        let dx = x1 / cw - gx0
        let dy = y1 / ch - gy0
        let len = hypot(dx, dy)
        // (NaN: the original would push a NaN cell and throw; nothing is drawn instead.)
        guard len.isFinite, len >= 1e-4 else { return }
        line = line == Int32.max ? 1 : line + 1
        let id = line
        // Entirely off the grid: nothing to plot, not even the stub.
        let C = Double(cols), R = Double(rows)
        if max(gx0, gx0 + dx) < -1 || min(gx0, gx0 + dx) > C + 1 || max(gy0, gy0 + dy) < -1 || min(gy0, gy0 + dy) > R + 1 { return }
        let phi = atan2(dy, dx)
        let pc2 = cos(2 * phi)
        let ps2 = sin(2 * phi)
        var any = false
        if abs(dx) >= abs(dy) {
            let lo = min(gx0, gx0 + dx)
            let hi = max(gx0, gx0 + dx)
            let c0 = (lo - 0.5).rounded(.up)
            if c0 + 0.5 < hi {
                any = true
                var c = max(c0, 0)
                while c + 0.5 < hi && c < C {
                    let gy = gy0 + (dy * (c + 0.5 - gx0)) / dx
                    let fy = floor(gy)
                    plot(c, fy, gy - fy, a, e, id, pc2, ps2)
                    c += 1
                }
            }
        } else {
            let lo = min(gy0, gy0 + dy)
            let hi = max(gy0, gy0 + dy)
            let r0 = (lo - 0.5).rounded(.up)
            if r0 + 0.5 < hi {
                any = true
                var r = max(r0, 0)
                while r + 0.5 < hi && r < R {
                    let gx = gx0 + (dx * (r + 0.5 - gy0)) / dy
                    plot(floor(gx), r, 0.5, a, e, id, pc2, ps2)
                    r += 1
                }
            }
        }
        // A stub shorter than a cell still shows, at its middle.
        if !any {
            let gy = gy0 + dy / 2
            plot(floor(gx0 + dx / 2), floor(gy), gy - floor(gy), a * min(1, len * 1.5), e, id, pc2, ps2)
        }
    }

    @inline(__always) private mutating func plot(_ cd: Double, _ rd: Double, _ v: Double, _ a: Double, _ e: Double,
                                                 _ id: Int32, _ pc2: Double, _ ps2: Double) {
        guard cd >= 0, rd >= 0, cd < Double(cols), rd < Double(rows) else { return }
        let i = Int(rd) * cols + Int(cd)
        let s = cell + i
        if s.pointee.seen != frame {
            s.pointee.seen = frame
            list[length] = Int32(i)
            length += 1
            StrokeAcc.clear(s)
        } else if layered {
            // Webs come far to near: a clearly nearer thread hides a farther one rather than crossing it,
            // and a clearly farther one is hidden behind.
            if a > Double(s.pointee.a) * 1.35 { StrokeAcc.clear(s) } else if a * 1.35 < Double(s.pointee.a) { return }
        }
        s.pointee.cov += 1
        s.pointee.c2 = Float(Double(s.pointee.c2) + pc2)
        s.pointee.s2 = Float(Double(s.pointee.s2) + ps2)
        s.pointee.v = Float(Double(s.pointee.v) + v)
        if s.pointee.last != id { s.pointee.last = id; s.pointee.count &+= 1 }
        if a > Double(s.pointee.a) { s.pointee.a = Float(a); s.pointee.dc = Float(pc2); s.pointee.ds = Float(ps2); s.pointee.dv = Float(v) }
        if e > Double(s.pointee.e) { s.pointee.e = Float(e) }
    }

    @inline(__always) private static func clear(_ s: UnsafeMutablePointer<StrokeCell>) {
        s.pointee.cov = 0; s.pointee.c2 = 0; s.pointee.s2 = 0; s.pointee.v = 0; s.pointee.a = 0; s.pointee.e = 0
        s.pointee.count = 0
        s.pointee.last = 0
    }

    @inline(__always) func at(_ i: Int) -> StrokeCell { cell[i] }

    /// The cell's glyph (a `GlyphAtlas` index).
    @inline(__always) func glyph(_ i: Int) -> UInt8 {
        let s = cell[i]
        return strokeGlyph(Double(s.cov), Double(s.c2), Double(s.s2), Double(s.v), Int(s.count),
                           Double(s.dc), Double(s.ds), Double(s.dv))
    }
}

/// Thread accumulated per cell; reset lazily by frame stamp (renderer.ts `Strokes`, its typed arrays as
/// grow-only buffers).
public final class WebStrokes {
    private var store = Grow<StrokeCell>(StrokeCell())
    private var listStore = Grow<Int32>(0)
    fileprivate var acc: StrokeAcc

    public init() { acc = StrokeAcc(cell: store.p, list: listStore.p) }

    deinit { store.free(); listStore.free() }

    public var cols: Int { acc.cols }
    public var rows: Int { acc.rows }
    public var length: Int { acc.length }
    /// Webs come far to near; a clearly nearer thread hides a farther one.
    public var layered: Bool {
        get { acc.layered }
        set { acc.layered = newValue }
    }

    /// The grid to accumulate over. Buffers only grow: a smaller grid (another screen) reuses them.
    public func resize(cols: Int, rows: Int) {
        acc.cols = max(0, cols)
        acc.rows = max(0, rows)
        let n = max(1, acc.cols * acc.rows)
        var grew = false
        grew = store.ensure(n) || grew
        grew = listStore.ensure(n) || grew
        acc.cell = store.p
        acc.list = listStore.p
        acc.capacity = store.capacity
        if grew { acc.frame = 0; acc.line = 0 }
        acc.length = 0
    }

    public func begin() { acc.begin() }

    /// The cells touched this frame, in order.
    public var cells: UnsafePointer<Int32> { UnsafePointer(acc.list) }

    /**
     * One glyph per step along the line's major axis, as a hand-drawn ASCII line is: one cell per column
     * for a level thread, one per row for a steep one. Cell centres are claimed half-open, so threads that
     * meet end to end never double up, while two different threads through one cell make a crossing.
     *
     * (Coordinates are relative to the grid's top-left. Columns or rows off the grid are skipped without
     * visiting them, which plots exactly what the original plots.)
     */
    public func add(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ cw: Double, _ ch: Double, _ a: Double, _ e: Double = 0) {
        acc.add(x0, y0, x1, y1, cw, ch, a, e)
    }

    /// The cell's glyph (a `GlyphAtlas` index).
    public func glyph(_ i: Int) -> UInt8 { acc.glyph(i) }
}

/// The theme's packed inks (renderer.ts silkStyles, ringStyles, flyStyles, dewStyles, and heat), Calm applied.
private struct Inks {
    var palette = Palette.dark
    var brightness = 1.0
    var accentRate = 1.0
    var silkStyles = [UInt32](repeating: 0, count: LEVELS + 1)
    var ringStyles = [UInt32](repeating: 0, count: LEVELS + 1)
    var flyStyles = [UInt32](repeating: 0, count: LEVELS + 1)
    var dewStyles = [UInt32](repeating: 0, count: LEVELS + 1)
    var heatStyles = [UInt32](repeating: 0, count: LEVELS + 1)
    var accentInks = [UInt32](repeating: 0, count: ACCENTS.count)
    var glyphLit: UInt32 = 0, glyphShadow: UInt32 = 0, eye: UInt32 = 0, fleck: UInt32 = 0, spot: UInt32 = 0, fang: UInt32 = 0

    init() {}

    init(_ t: ThemeParams) {
        let p = t.light ? Palette.light : Palette.dark
        palette = p
        brightness = Double(t.brightness)
        accentRate = Double(t.accentRate)
        for l in 0...LEVELS {
            let a = toFixed(Double(l) / Double(LEVELS), 1000)
            silkStyles[l] = pack(p.silk, a)
            ringStyles[l] = pack(p.ring, a)
            flyStyles[l] = pack(p.fly, a)
            dewStyles[l] = pack(p.dew, a)
            heatStyles[l] = pack(p.heat, toFixed(Double(l) / Double(LEVELS), 100))
        }
        for (k, c) in ACCENTS.enumerated() { accentInks[k] = pack(c) }
        glyphLit = pack(p.glyphLit)
        glyphShadow = pack(p.glyphShadow)
        eye = pack(p.eye)
        fleck = pack(p.fleck)
        spot = pack(p.spot)
        fang = pack(p.fang)
    }

    /// A final RGBA8: Calm dims dark ink toward black and light ink toward the paper.
    @inline(__always) func pack(_ c: RGB, _ alpha: Double = 1) -> UInt32 {
        var r = c.0, g = c.1, b = c.2
        if brightness != 1 {
            if palette.light {
                let k = 1 - brightness
                r += (PAPER.0 - r) * k; g += (PAPER.1 - g) * k; b += (PAPER.2 - b) * k
            } else {
                r *= brightness; g *= brightness; b *= brightness
            }
        }
        @inline(__always) func u8(_ x: Double) -> UInt32 { UInt32(max(0, min(255, x)).rounded()) }
        return u8(r) | u8(g) << 8 | u8(b) << 16 | u8(alpha * 255) << 24
    }
}

/// The top layer: flies and spiders, which hide the silk under them. Later puts win.
private struct Top {
    var seen: UnsafeMutablePointer<UInt32>
    var cells: UnsafeMutablePointer<Int32>
    var glyph: UnsafeMutablePointer<UInt8>
    var ink: UnsafeMutablePointer<UInt32>
    var block: UnsafeMutablePointer<UInt32>
    var n = 0
}

/// A spider's body as drawn this frame: everything `sample` reads, read once.
private struct Body {
    let rx: Double, ry: Double, s: Double, B: Double
    let c: Double, sn: Double
    let pa: Double, pb: Double, pu: Double
    let aa: Double, ab: Double, au: Double
    /// The cell in body units.
    let cw: Double, ch: Double
    let id: Double
    let boxy: Bool, eyes: Bool
    let pattern: SpeciesPattern

    init(_ sp: Spider, cw: Double, ch: Double) {
        let spec = sp.sp
        s = sp.scale
        B = sp.B
        c = cos(sp.h)
        sn = sin(sp.h)
        rx = sp.rx
        ry = sp.ry
        pa = spec.prosoma[0] * B
        pb = spec.prosoma[1] * B
        pu = sp.prosomaU
        aa = spec.abdomen[0] * B * sp.breath
        ab = spec.abdomen[1] * B * (2 - sp.breath)
        au = sp.abdomenU
        self.cw = cw / s
        self.ch = ch / s
        id = Double(sp.id)
        boxy = spec.boxy
        eyes = spec.eyes
        pattern = spec.pattern
    }

    /// Whether (px, py) falls on the body: `sample`'s answer, without the shading it also works out.
    @inline(__always) func covers(_ px: Double, _ py: Double) -> Bool {
        let dx = (px - rx) / s
        let dy = (py - ry) / s
        let u = dx * c + dy * sn
        let v = -dx * sn + dy * c
        let eu = (u - pu) / pa
        let ev = v / pb
        if prosoma(eu, ev, boxy) < 1 { return true }
        let eu2 = (u - au) / aa
        let ev2 = v / ab
        // (As `sample` decides: only e >= 1 misses, so a NaN counts as a hit.)
        return !(eu2 * eu2 + ev2 * ev2 >= 1)
    }
}

/**
 * Where (eu, ev) sits against the prosoma, in its own radii: under 1 inside. An ellipse, or for the jumper a
 * rounded box, (|eu|³ + |ev|³)^(2/3). Callers only ask whether it is under 1 unless it is, so a box sample
 * clearly outside (|eu| or |ev| at least 1.01, where the powers come to 1.02 or more however pow rounds) is
 * answered without taking them.
 */
@inline(__always) private func prosoma(_ eu: Double, _ ev: Double, _ boxy: Bool) -> Double {
    guard boxy else { return eu * eu + ev * ev }
    if abs(eu) >= 1.01 || abs(ev) >= 1.01 { return .infinity }
    return pow(pow(abs(eu), 3) + pow(abs(ev), 3), 2.0 / 3)
}

/// What a body sample hit.
private struct Hit {
    var flag = 0
    var shade = 0.0
    var key: UInt32 = 0
}

/// One `paint`: the painter's per-frame state as a value.
private struct Pass {
    let ink: Inks
    let cw: Double, ch: Double
    let cols: Int, rows: Int
    /// The viewport's top-left in habitat space: the grid starts there.
    let ox: Double, oy: Double
    let frame: UInt32
    var top: Top
    var silk: StrokeAcc
    var legs: StrokeAcc

    // ── grid ──

    @inline(__always) func cell(_ x: Double, _ y: Double) -> Int {
        let c = floor((x - ox) / cw)
        let r = floor((y - oy) / ch)
        guard c >= 0, r >= 0, c < Double(cols), r < Double(rows) else { return -1 }
        return Int(r) * cols + Int(c)
    }

    /// The top layer: flies and spiders, which hide the silk under them. Later puts win.
    @inline(__always) mutating func put(_ i: Int, _ glyph: UInt8, _ color: UInt32, _ block: UInt32 = 0) {
        if i < 0 { return }
        if top.seen[i] != frame {
            top.seen[i] = frame
            top.cells[top.n] = Int32(i)
            top.n += 1
        }
        top.glyph[i] = glyph
        top.ink[i] = color
        top.block[i] = block
    }

    mutating func run(_ world: WebWorld, _ canvas: CellCanvas) {
        let time = world.time

        drawFlies(world)
        for b in world.heat {
            let i = cell(b.x, b.y)
            let a = Int(mathRound(clamp(b.life, 0, 1) * Double(LEVELS)))
            put(i, b.life > 0.5 ? G.star : G.dot, ink.heatStyles[a])
        }
        // Far webs' spiders first, so nearer ones draw over them; the jumper is nearest of all.
        for w in world.weavers { drawSpider(w.spider, 0.72 + 0.28 * w.web.depth, time) }
        if let j = world.jumper { drawSpider(j.spider, 1, time) }

        // ── silk ──
        silk.begin()
        silk.layered = true
        for web in world.webs { addWeb(web) }
        for w in world.weavers { addThreads(w) }
        if let j = world.jumper, let jd = j.drag {
            let tmp = j.spider.spinneret()
            silk.add(jd.x - ox, jd.y - oy, tmp.x - ox, tmp.y - oy, cw, ch, 0.5 * jd.life * ink.palette.silkGain)
        }

        let S = silk
        let topSeen = top.seen, frame = self.frame
        ink.ringStyles.withUnsafeBufferPointer { ringStyles in
            ink.silkStyles.withUnsafeBufferPointer { silkStyles in
                canvas.glyph.withUnsafeMutableBufferPointer { glyph in
                    canvas.ink.withUnsafeMutableBufferPointer { ink in
                        for k in 0..<S.length {
                            let i = Int(S.list[k])
                            if topSeen[i] == frame { continue }
                            let s = S.at(i)
                            if s.cov < 0.1 { continue }
                            let e = Double(s.e)
                            let a = Double(s.a) * (s.count >= 4 ? 1.25 : 1) + clamp((e - 0.12) * 0.4, 0, 0.5)
                            let level = Int(clamp(mathRound(a * Double(LEVELS)), 1, Double(LEVELS)))
                            ink[i] = e > 0.45 ? ringStyles[level] : silkStyles[level]
                            glyph[i] = S.glyph(i)
                        }
                    }
                }
            }
        }

        drawDew(world, time, canvas)

        // ── top layer ──
        let top = self.top
        canvas.glyph.withUnsafeMutableBufferPointer { glyph in
            canvas.ink.withUnsafeMutableBufferPointer { ink in
                canvas.block.withUnsafeMutableBufferPointer { block in
                    for k in 0..<top.n {
                        let i = Int(top.cells[k])
                        block[i] = top.block[i]
                        glyph[i] = top.glyph[i]
                        ink[i] = top.ink[i]
                    }
                }
            }
        }
    }

    /// Near webs read clearly; far ones are a whisper.
    @inline(__always) func silkAlpha(_ web: OrbWeb) -> Double {
        (0.04 + 0.36 * pow(web.depth, 1.6)) * ink.palette.silkGain
    }

    mutating func addWeb(_ web: OrbWeb) {
        let base = silkAlpha(web)
        let x = web.x.p, y = web.y.p, la = web.la.p, lb = web.lb.p, state = web.state.p, kind = web.kind.p, speed = web.speed.p
        let ox = self.ox, oy = self.oy, cw = self.cw, ch = self.ch
        if Pass.offGrid(x, y, web.n, ox, oy, cw, ch, cols, rows) { return }
        SILK_ALPHA.withUnsafeBufferPointer { SILK_ALPHA in
            for l in 0..<web.m {
                // (The "full" stage draws every kind, up to STAB.)
                if state[l] != 1 || kind[l] > STAB { continue }
                let a = la[l]
                let b = lb[l]
                let e = Double(max(speed[a], speed[b]))
                silk.add(Double(x[a]) - ox, Double(y[a]) - oy, Double(x[b]) - ox, Double(y[b]) - oy, cw, ch,
                         base * SILK_ALPHA[kind[l]], kind[l] == MOOR ? 0 : e)
            }
        }
    }

    /// `Int(floor(v))` held to [-1, `n`] (NaN gives -1): for a cell range clamped to 0..<n after, the same
    /// answer as converting first, but a huge or infinite `v` can't trap.
    @inline(__always) static func cell(_ v: Double, _ n: Int) -> Int {
        let f = floor(v)
        guard f >= -1 else { return -1 }
        return f > Double(n) ? n : Int(f)
    }

    /**
     * Whether every node of a web lies more than two cells off the grid on one side, so that `StrokeAcc.add`
     * would drop each of its threads before plotting (it drops a thread wholly beyond -1 or C + 1 cells).
     * Only for sane coordinates (within ±1e7 px, where rounding is far below the cell of margin); a NaN node
     * is passed over, as its threads draw nothing either. Skipping a web changes no output: a dropped
     * thread only spends a line number, and line numbers only tell threads apart within a frame.
     */
    static func offGrid(_ x: UnsafeMutableBufferPointer<Float>, _ y: UnsafeMutableBufferPointer<Float>, _ n: Int,
                        _ ox: Double, _ oy: Double, _ cw: Double, _ ch: Double, _ cols: Int, _ rows: Int) -> Bool {
        guard n > 0, cw > 0, ch > 0 else { return false }
        var x0 = Float.infinity, x1 = -Float.infinity, y0 = Float.infinity, y1 = -Float.infinity
        for i in 0..<n {
            x0 = min(x0, x[i]); x1 = max(x1, x[i])
            y0 = min(y0, y[i]); y1 = max(y1, y[i])
        }
        let lim: Float = 1e7
        guard x0 >= -lim, x1 <= lim, y0 >= -lim, y1 <= lim else { return false }
        return (Double(x1) - ox) / cw < -2 || (Double(x0) - ox) / cw > Double(cols) + 2
            || (Double(y1) - oy) / ch < -2 || (Double(y0) - oy) / ch > Double(rows) + 2
    }

    /// A weaver's loose silk: the thread it is laying (or reeling in), and the lines to its parcels.
    mutating func addThreads(_ w: Weaver) {
        let web = w.web
        let base = silkAlpha(web)
        let sp = w.spider
        if w.partial >= 0 && w.partial < web.n {
            silk.add(Double(web.x[w.partial]) - ox, Double(web.y[w.partial]) - oy, sp.rx - ox, sp.ry - oy, cw, ch, min(1, base * 2.4))
        }
        // (The original loops over [carried prey, bundle]; two calls build no array.)
        @inline(__always) func line(_ parcel: Fly?, _ pass: inout Pass) {
            guard let parcel else { return }
            let tmp = sp.spinneret()
            pass.silk.add(tmp.x - pass.ox, tmp.y - pass.oy, parcel.x - pass.ox, parcel.y - pass.oy, pass.cw, pass.ch, min(1, base * 2))
        }
        line(w.state == .carry ? w.prey : nil, &self)
        line(w.bundle, &self)
    }

    /// Dew is drawn over the silk glyph in its cell (the canvas overlay), as the original draws a second glyph there.
    func drawDew(_ world: WebWorld, _ t: Double, _ canvas: CellCanvas) {
        let silkGain = ink.palette.silkGain
        ink.dewStyles.withUnsafeBufferPointer { dewStyles in
            canvas.overGlyph.withUnsafeMutableBufferPointer { og in
                canvas.overInk.withUnsafeMutableBufferPointer { oi in
                    for web in world.webs {
                        let dew = web.dew.p, state = web.state.p
                        let seed = web.seed, depth = web.depth
                        for l in 0..<web.m {
                            if dew[l] < 0 || state[l] != 1 { continue }
                            let p = web.pos(l, Double(dew[l]))
                            let i = cell(p.x, p.y)
                            if i < 0 || top.seen[i] == frame { continue }
                            let tw = 0.5 + 0.5 * sin(t * (0.8 + hash3(Double(l), seed, 9) * 1.4) + Double(l) * 1.37)
                            let a = (0.3 + 0.6 * tw) * (0.45 + 0.55 * depth) * silkGain
                            let level = Int(clamp(mathRound(a * Double(LEVELS)), 1, Double(LEVELS)))
                            let g = tw > 0.94 ? G.plus : G.dot
                            var ink = dewStyles[level]
                            if og[i] != CellCanvas.noGlyph {
                                // A second bead in the cell: the same glyph drawn twice, 1 - (1 - a)(1 - b); a different
                                // one keeps the last drawn at that opacity.
                                let prev = Double(oi[i] >> 24) / 255, now = Double(ink >> 24) / 255
                                let both = 1 - (1 - prev) * (1 - now)
                                ink = (ink & 0x00ff_ffff) | UInt32((both * 255).rounded()) << 24
                            }
                            og[i] = g
                            oi[i] = ink
                        }
                    }
                }
            }
        }
    }

    mutating func drawFlies(_ world: WebWorld) {
        for f in world.swarm.flies {
            if f.mode == .gone { continue }
            let i = cell(f.x, f.y)
            if i < 0 { continue }
            let g: UInt8
            var a = 0.5 + 0.45 * f.depth
            switch f.mode {
            case .fly:
                g = fmod(floor(f.phase * 12 + f.seed), 2) != 0 ? G.x : G.plus
            case .rest:
                g = G.x
            case .stuck:
                g = f.wrap > 0 ? (f.wrap < 0.5 ? G.pct : G.at) : fmod(floor(f.phase * 15), 3) != 0 ? G.star : G.x
                a = 1
            case .wrapped:
                g = G.at
                a = 0.9
            default: // held: shrinks as it is eaten
                g = f.digest < 0.35 ? G.at : f.digest < 0.65 ? G.zero : f.digest < 0.88 ? G.o : G.dot
                a = 0.85
            }
            put(i, g, ink.flyStyles[Int(clamp(mathRound(a * Double(LEVELS)), 1, Double(LEVELS)))])
        }
    }

    // ── spiders ──

    mutating func drawSpider(_ sp: Spider, _ dim: Double, _ t: Double) {
        let p = ink.palette
        let spec = sp.sp
        let tr = spec.tint[0], tg = spec.tint[1], tb = spec.tint[2]
        sp.solve()

        // Legs: stroke glyphs, each segment its own shade; banded species alternate light and dark.
        legs.begin()
        let spLegs = sp.legs
        for k in 0..<spLegs.count {
            let lv = spec.leg * (spLegs[k].i == 0 && spec.eyes ? 0.9 : 1)
            let band = spec.band
            segment(spLegs[k].hx, spLegs[k].hy, spLegs[k].kx, spLegs[k].ky, lv, lv * (1 - band))
            segment(spLegs[k].kx, spLegs[k].ky, spLegs[k].fx, spLegs[k].fy, lv * 0.92, lv * (1 - band) * 0.92)
        }
        for k in 0..<legs.length {
            let i = Int(legs.list[k])
            let s = legs.at(i)
            if s.cov < 0.12 { continue }
            let lv = Double(s.a) * dim
            put(i, legs.glyph(i), ink.pack(p.tone(p.legLevel(lv), tr, tg, tb)), ink.pack(p.tone(p.legBlock(lv), tr, tg, tb)))
        }

        // Body: supersample each cell of the bounding box against the two ellipses.
        let s = sp.scale
        let B = sp.B * s
        let reach = (spec.prosoma[0] + spec.abdomen[0]) * 2.1 * B
        let lx = sp.rx - ox, ly = sp.ry - oy
        guard lx.isFinite, ly.isFinite, reach.isFinite else { return }
        // Held to [-1, cols] / [-1, rows] before converting: a finite but far-off spider would trap in Int().
        let c0 = max(0, Pass.cell((lx - reach) / cw, cols))
        let c1 = min(cols - 1, Pass.cell((lx + reach) / cw, cols))
        let r0 = max(0, Pass.cell((ly - reach) / ch, rows))
        let r1 = min(rows - 1, Pass.cell((ly + reach) / ch, rows))
        guard c0 <= c1, r0 <= r1 else { return }
        let body = Body(sp, cw: cw, ch: ch)
        let tick = floor(t * 2.4)
        let dark = spec.eyes
        for r in r0...r1 {
            for c in c0...c1 {
                let x = Double(c) * cw + ox
                let y = Double(r) * ch + oy
                var hit = Hit()
                let center = Pass.sample(body, &hit, x + cw / 2, y + ch / 2)
                let flag = hit.flag
                let shade = hit.shade
                let key = hit.key
                // The four corner samples, in SUBSAMPLES' order.
                var hits = center ? 1 : 0
                if body.covers(x + 0.25 * cw, y + 0.3 * ch) { hits += 1 }
                if body.covers(x + 0.75 * cw, y + 0.3 * ch) { hits += 1 }
                if body.covers(x + 0.25 * cw, y + 0.72 * ch) { hits += 1 }
                if body.covers(x + 0.75 * cw, y + 0.72 * ch) { hits += 1 }
                if hits == 0 { continue }
                let i = r * cols + c
                let cover = Double(hits) / 5
                if !center || cover < 0.6 {
                    let set = cover >= 0.5 ? G.EDGE_HEAVY : G.EDGE_LIGHT
                    put(i, set[Int((key >> 8) % UInt32(set.count))], ink.pack(p.tone((70 + cover * 80) * dim, tr, tg, tb)))
                    continue
                }
                let roll = hash3(Double(key), Double(toInt32(tick + Double(key % 97) / 41)), 7)
                var level: Double
                var glyph: UInt8
                var color: UInt32
                var ttr = tr
                var ttg = tg
                var ttb = tb
                switch flag {
                case EYE:
                    level = 8
                    glyph = dark ? G.eyeDark : G.o
                    color = ink.eye
                case FANG:
                    level = 26
                    glyph = G.v
                    color = ink.fang
                case MARK:
                    level = 22 + shade * 26
                    glyph = G.MARK_GLYPHS[Int((key >> 8) % 3)]
                    color = ink.pack(p.tone(70, tr, tg, tb))
                case SPOT:
                    level = 120 + shade * 80
                    glyph = G.SPOT_GLYPHS[Int((key >> 8) % 3)]
                    color = ink.spot
                case CROSS:
                    level = 110 + shade * 70
                    glyph = G.plus
                    color = ink.spot
                case BAND:
                    // Argiope's bright bands: warm yellow on black, a paler graphite on paper.
                    level = 120 + shade * 110
                    ttr = 1.18
                    ttg = 1.06
                    ttb = 0.42
                    glyph = G.SKIN_RAMP[Int(clamp(floor((1 - shade) * 6), 0, 8))]
                    color = shade > 0.5 ? ink.glyphLit : ink.glyphShadow
                default:
                    level = dark ? 30 + shade * 96 : 48 + shade * 150
                    let jitter = Int((key >> 4) % 3) - 1
                    glyph = G.SKIN_RAMP[Int(clamp(floor((1 - shade) * 8.99) + Double(jitter), 0, Double(G.SKIN_RAMP.count - 1)))]
                    // Accents and flecks at the original's rates, scaled by the theme's (Calm: fewer).
                    if !p.accents.isEmpty && roll < 0.06 * ink.accentRate { color = ink.accentInks[Int(key % UInt32(p.accents.count))] }
                    else if roll < 0.1 * ink.accentRate { color = ink.fleck }
                    else { color = shade > 0.55 ? ink.glyphLit : ink.glyphShadow }
                }
                put(i, glyph, color, ink.pack(p.tone(level * dim, ttr, ttg, ttb)))
            }
        }
    }

    /// A leg segment in two halves, so banded legs alternate shade along their length.
    @inline(__always) mutating func segment(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ l0: Double, _ l1: Double) {
        let mx = (x0 + x1) / 2
        let my = (y0 + y1) / 2
        legs.add(x0 - ox, y0 - oy, mx - ox, my - oy, cw, ch, l0)
        legs.add(mx - ox, my - oy, x1 - ox, y1 - oy, cw, ch, l1)
    }

    /**
     * Classify a point against a spider's body. Body frame: u forward from the pedicel, v to the right.
     * Writes the hit's flag, shade and key (a body-anchored hash, so glyphs ride along with the body).
     */
    static func sample(_ sp: Body, _ hit: inout Hit, _ px: Double, _ py: Double) -> Bool {
        let s = sp.s
        let c = sp.c
        let sn = sp.sn
        let dx = (px - sp.rx) / s
        let dy = (py - sp.ry) / s
        let u = dx * c + dy * sn
        let v = -dx * sn + dy * c
        let pa = sp.pa
        let pb = sp.pb
        let pu = sp.pu
        let cw = sp.cw
        hit.key = UInt32(hash3(mathRound(u / (cw * 0.9)), mathRound(v / (cw * 0.9)), sp.id) * 4_294_967_295)

        // Prosoma: an ellipse, or a rounded box for the jumper.
        var eu = (u - pu) / pa
        var ev = v / pb
        var e = prosoma(eu, ev, sp.boxy)
        if e < 1 {
            hit.shade = lit(eu / pa, ev / pb, e.squareRoot(), c, sn) * 0.92
            hit.flag = BODY
            if sp.eyes {
                // Two great forward eyes, at least a cell each, and the iridescent fangs between them.
                let er = max(pb * 0.38, cw * 0.62)
                let ex = u - (pu + pa * 0.5)
                for side in 0..<2 {
                    let ey = v - (side == 0 ? -1 : 1) * max(pb * 0.46, cw * 0.7)
                    if ex * ex + ey * ey < er * er { hit.flag = EYE }
                }
                if hit.flag == BODY && eu > 0.78 && abs(ev) < 0.42 { hit.flag = FANG }
            }
            return true
        }

        // Abdomen. The abdomen breathes.
        let aa = sp.aa
        let ab = sp.ab
        eu = (u - sp.au) / aa
        ev = v / ab
        e = eu * eu + ev * ev
        if e >= 1 { return false }
        let across = e.squareRoot()
        hit.shade = lit(eu / aa, ev / ab, across, c, sn)
        hit.flag = BODY
        let ch = sp.ch
        let au = u - sp.au
        switch sp.pattern {
        case .cross:
            // The garden spider's cross on a dark scalloped folium.
            let mid = abs(v) < max(ab * 0.16, cw * 0.55)
            let bar = abs(au - aa * 0.28) < max(aa * 0.12, ch * 0.5) && abs(v) < ab * 0.5
            if (mid && eu > -0.45 && eu < 0.78) || bar { hit.flag = CROSS }
            else if abs(ev) < 0.62 + 0.12 * sin(eu * 9) && eu < 0.6 { hit.flag = MARK }
        case .bands:
            let n = max(2, mathRound((aa * 2) / (ch * 1.7)))
            if sin((eu * 0.5 + 0.5) * Double.pi * n * 2 + 0.6) > 0.15 { hit.flag = MARK } else { hit.flag = BAND }
        case .spots:
            let lane = abs(abs(v) - ab * 0.5) < max(ab * 0.22, cw * 0.45)
            if lane && sin(eu * 9) > 0.3 { hit.flag = SPOT }
        case .jumper:
            // Phidippus: a pale triangle and two spots on black, a pale band across the front.
            if eu > 0.72 { hit.flag = SPOT }
            else if eu > -0.05 && eu < 0.45 && abs(v) < max(ab * 0.32 * (1 - (0.45 - eu)), cw * 0.5) { hit.flag = SPOT }
            else if abs(eu + 0.45) < 0.16 && abs(abs(v) - ab * 0.5) < max(ab * 0.16, cw * 0.4) { hit.flag = SPOT }
        }
        return true
    }

    /// Rounded body lit from the top-left, as the sharks are.
    @inline(__always) static func lit(_ nu: Double, _ nv: Double, _ across: Double, _ c: Double, _ sn: Double) -> Double {
        let h = hypot(nu, nv)
        let l = h == 0 || h.isNaN ? 1 : h
        let nx = (nu * c - nv * sn) / l
        let ny = (nu * sn + nv * c) / l
        let facing = (nx * -0.6 + ny * -0.8) * across
        return clamp(0.58 - across * across * 0.42 + facing * 0.26, 0, 1)
    }
}

/// renderer.ts `AsciiRenderer`, drawing into a `CellCanvas` (always the "full" stage). Colours come out final:
/// the palette for the theme, Calm applied, accents at the theme's rate.
public final class WebPainter {
    private let silk = WebStrokes()
    private let legStrokes = WebStrokes()
    private var frame: UInt32 = 0
    private var theme: ThemeParams? = nil
    private var ink = Inks()
    // The top layer: flies and spiders, which hide the silk under them.
    private var topSeen = Grow<UInt32>(0)
    private var topCells = Grow<Int32>(0)
    private var topGlyph = Grow<UInt8>(0)
    private var topInk = Grow<UInt32>(0)
    private var topBlock = Grow<UInt32>(0)

    public init() {}

    deinit { topSeen.free(); topCells.free(); topGlyph.free(); topInk.free(); topBlock.free() }

    private func setTheme(_ t: ThemeParams) {
        guard t != theme else { return }
        theme = t
        ink = Inks(t)
    }

    /// The background and grid for a theme (renderer.ts `paintBackground`).
    public static func background(_ t: ThemeParams) -> (rgb: SIMD3<Float>, grid: SIMD4<Float>) {
        if t.light {
            return (SIMD3(247, 246, 243) / 255, SIMD4(SIMD3(35, 35, 35) / 255, t.grid ? 0.08 : 0))
        }
        return (.zero, SIMD4(1, 1, 1, t.grid ? 0.055 : 0))
    }

    /// Paints the part of `world` inside `viewport` (habitat space) on `grid` into `canvas`, which arrives
    /// cleared. Sets the canvas's background and grid colour.
    public func paint(_ world: WebWorld, viewport: CGRect, grid: GridSpec, theme t: ThemeParams, into canvas: CellCanvas) {
        setTheme(t)
        let bg = WebPainter.background(t)
        canvas.background = bg.rgb
        canvas.gridColor = bg.grid
        let cols = canvas.cols
        let rows = canvas.rows
        guard cols > 0, rows > 0 else { return }
        let n = cols * rows
        if topSeen.ensure(n) { frame = 0 }
        _ = topCells.ensure(n); _ = topGlyph.ensure(n); _ = topInk.ensure(n); _ = topBlock.ensure(n)
        silk.resize(cols: cols, rows: rows)
        legStrokes.resize(cols: cols, rows: rows)

        frame &+= 1
        if frame == 0 { topSeen.p.update(repeating: 0, count: topSeen.capacity); frame = 1 }

        var pass = Pass(ink: ink, cw: Double(grid.cell.width), ch: Double(grid.cell.height), cols: cols, rows: rows,
                        ox: Double(viewport.minX), oy: Double(viewport.minY), frame: frame,
                        top: Top(seen: topSeen.p, cells: topCells.p, glyph: topGlyph.p, ink: topInk.p, block: topBlock.p),
                        silk: silk.acc, legs: legStrokes.acc)
        pass.run(world, canvas)
        silk.acc = pass.silk
        legStrokes.acc = pass.legs
    }
}
