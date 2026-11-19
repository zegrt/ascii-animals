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

/// Thread accumulated per cell; reset lazily by frame stamp (renderer.ts `Strokes`, its typed arrays as
/// grow-only buffers).
public final class WebStrokes {
    public private(set) var cols = 0
    public private(set) var rows = 0
    private var cov = Grow<Float>(0), c2 = Grow<Float>(0), s2 = Grow<Float>(0), v = Grow<Float>(0)
    /// The strongest thread's direction and place in the cell: it runs on through a crossing.
    private var dc = Grow<Float>(0), ds = Grow<Float>(0), dv = Grow<Float>(0)
    /// Brightness, and how hard the silk there is ringing.
    fileprivate var a = Grow<Float>(0), e = Grow<Float>(0)
    fileprivate var count = Grow<UInt16>(0)
    private var last = Grow<Int32>(0)
    private var seen = Grow<UInt32>(0)
    private var cellBuf = Grow<Int32>(0)
    public private(set) var length = 0
    private var frame: UInt32 = 0
    private var line: Int32 = 0
    /// Webs come far to near; a clearly nearer thread hides a farther one.
    public var layered = false
    private var id: Int32 = 0
    private var pc2 = 0.0
    private var ps2 = 0.0

    public init() {}

    deinit {
        cov.free(); c2.free(); s2.free(); v.free(); dc.free(); ds.free(); dv.free(); a.free(); e.free()
        count.free(); last.free(); seen.free(); cellBuf.free()
    }

    /// The grid to accumulate over. Buffers only grow: a smaller grid (another screen) reuses them.
    public func resize(cols: Int, rows: Int) {
        self.cols = max(0, cols)
        self.rows = max(0, rows)
        let n = max(1, self.cols * self.rows)
        var grew = false
        grew = cov.ensure(n) || grew; grew = c2.ensure(n) || grew; grew = s2.ensure(n) || grew; grew = v.ensure(n) || grew
        grew = dc.ensure(n) || grew; grew = ds.ensure(n) || grew; grew = dv.ensure(n) || grew
        grew = a.ensure(n) || grew; grew = e.ensure(n) || grew; grew = count.ensure(n) || grew
        grew = last.ensure(n) || grew; grew = seen.ensure(n) || grew; grew = cellBuf.ensure(n) || grew
        if grew { frame = 0; line = 0 }
        length = 0
    }

    public func begin() {
        frame &+= 1
        if frame == 0 {
            // Wrapped: stale stamps could match again.
            seen.p.update(repeating: 0, count: seen.capacity)
            frame = 1
        }
        length = 0
    }

    /// The cells touched this frame, in order.
    public var cells: UnsafePointer<Int32> { UnsafePointer(cellBuf.p) }
    @inline(__always) func cov(_ i: Int) -> Float { cov.p[i] }

    /**
     * One glyph per step along the line's major axis, as a hand-drawn ASCII line is: one cell per column
     * for a level thread, one per row for a steep one. Cell centres are claimed half-open, so threads that
     * meet end to end never double up, while two different threads through one cell make a crossing.
     *
     * (Coordinates are relative to the grid's top-left. Columns or rows off the grid are skipped without
     * visiting them, which plots exactly what the original plots.)
     */
    public func add(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ cw: Double, _ ch: Double, _ a: Double, _ e: Double = 0) {
        let gx0 = x0 / cw
        let gy0 = y0 / ch
        let dx = x1 / cw - gx0
        let dy = y1 / ch - gy0
        let len = hypot(dx, dy)
        // (NaN: the original would push a NaN cell and throw; nothing is drawn instead.)
        guard len.isFinite, len >= 1e-4 else { return }
        line = line == Int32.max ? 1 : line + 1
        id = line
        // Entirely off the grid: nothing to plot, not even the stub.
        let C = Double(cols), R = Double(rows)
        if max(gx0, gx0 + dx) < -1 || min(gx0, gx0 + dx) > C + 1 || max(gy0, gy0 + dy) < -1 || min(gy0, gy0 + dy) > R + 1 { return }
        let phi = atan2(dy, dx)
        pc2 = cos(2 * phi)
        ps2 = sin(2 * phi)
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
                    plot(c, fy, gy - fy, a, e)
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
                    plot(floor(gx), r, 0.5, a, e)
                    r += 1
                }
            }
        }
        // A stub shorter than a cell still shows, at its middle.
        if !any {
            let gy = gy0 + dy / 2
            plot(floor(gx0 + dx / 2), floor(gy), gy - floor(gy), a * min(1, len * 1.5), e)
        }
    }

    @inline(__always) private func plot(_ cd: Double, _ rd: Double, _ v: Double, _ a: Double, _ e: Double) {
        guard cd >= 0, rd >= 0, cd < Double(cols), rd < Double(rows) else { return }
        let i = Int(rd) * cols + Int(cd)
        if seen.p[i] != frame {
            seen.p[i] = frame
            cellBuf.p[length] = Int32(i)
            length += 1
            clear(i)
        } else if layered {
            // Webs come far to near: a clearly nearer thread hides a farther one rather than crossing it,
            // and a clearly farther one is hidden behind.
            if a > Double(self.a.p[i]) * 1.35 { clear(i) } else if a * 1.35 < Double(self.a.p[i]) { return }
        }
        cov.p[i] += 1
        c2.p[i] = Float(Double(c2.p[i]) + pc2)
        s2.p[i] = Float(Double(s2.p[i]) + ps2)
        self.v.p[i] = Float(Double(self.v.p[i]) + v)
        if last.p[i] != id { last.p[i] = id; count.p[i] &+= 1 }
        if a > Double(self.a.p[i]) { self.a.p[i] = Float(a); dc.p[i] = Float(pc2); ds.p[i] = Float(ps2); dv.p[i] = Float(v) }
        if e > Double(self.e.p[i]) { self.e.p[i] = Float(e) }
    }

    @inline(__always) private func clear(_ i: Int) {
        cov.p[i] = 0; c2.p[i] = 0; s2.p[i] = 0; v.p[i] = 0; a.p[i] = 0; e.p[i] = 0
        count.p[i] = 0
        last.p[i] = 0
    }

    /// The cell's glyph (a `GlyphAtlas` index).
    public func glyph(_ i: Int) -> UInt8 {
        strokeGlyph(Double(cov.p[i]), Double(c2.p[i]), Double(s2.p[i]), Double(v.p[i]), Int(count.p[i]),
                    Double(dc.p[i]), Double(ds.p[i]), Double(dv.p[i]))
    }
}

/// renderer.ts `AsciiRenderer`, drawing into a `CellCanvas` (always the "full" stage). Colours come out final:
/// the palette for the theme, Calm applied, accents at the theme's rate.
public final class WebPainter {
    private let silk = WebStrokes()
    private let legStrokes = WebStrokes()
    private var cw = 12.0
    private var ch = 17.0
    private var cols = 0
    private var rows = 0
    /// The viewport's top-left in habitat space: the grid starts there.
    private var ox = 0.0
    private var oy = 0.0
    private var frame: UInt32 = 0
    private var palette = Palette.dark
    private var theme: ThemeParams? = nil
    // Packed inks per level, for the theme (renderer.ts silkStyles, ringStyles, flyStyles, dewStyles, and heat).
    private var silkStyles = [UInt32](repeating: 0, count: LEVELS + 1)
    private var ringStyles = [UInt32](repeating: 0, count: LEVELS + 1)
    private var flyStyles = [UInt32](repeating: 0, count: LEVELS + 1)
    private var dewStyles = [UInt32](repeating: 0, count: LEVELS + 1)
    private var heatStyles = [UInt32](repeating: 0, count: LEVELS + 1)
    private var accentInks = [UInt32](repeating: 0, count: ACCENTS.count)
    private var glyphLit: UInt32 = 0, glyphShadow: UInt32 = 0, eye: UInt32 = 0, fleck: UInt32 = 0, spot: UInt32 = 0, fang: UInt32 = 0
    private var brightness = 1.0
    private var accentRate = 1.0
    // The top layer: flies and spiders, which hide the silk under them.
    private var topSeen = Grow<UInt32>(0)
    private var topCells = Grow<Int32>(0)
    private var topGlyph = Grow<UInt8>(0)
    private var topInk = Grow<UInt32>(0)
    private var topBlock = Grow<UInt32>(0)
    private var topN = 0
    // What the last body sample hit.
    private var hitFlag = 0
    private var hitShade = 0.0
    private var hitKey: UInt32 = 0

    public init() {}

    deinit { topSeen.free(); topCells.free(); topGlyph.free(); topInk.free(); topBlock.free() }

    // ── colours ──

    /// A final RGBA8: Calm dims dark ink toward black and light ink toward the paper.
    @inline(__always) private func pack(_ c: RGB, _ alpha: Double = 1) -> UInt32 {
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

    private func setTheme(_ t: ThemeParams) {
        guard t != theme else { return }
        theme = t
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

    /// The background and grid for a theme (renderer.ts `paintBackground`).
    public static func background(_ t: ThemeParams) -> (rgb: SIMD3<Float>, grid: SIMD4<Float>) {
        if t.light {
            return (SIMD3(247, 246, 243) / 255, SIMD4(SIMD3(35, 35, 35) / 255, t.grid ? 0.08 : 0))
        }
        return (.zero, SIMD4(1, 1, 1, t.grid ? 0.055 : 0))
    }

    // ── grid ──

    @inline(__always) private func cell(_ x: Double, _ y: Double) -> Int {
        let c = floor((x - ox) / cw)
        let r = floor((y - oy) / ch)
        guard c >= 0, r >= 0, c < Double(cols), r < Double(rows) else { return -1 }
        return Int(r) * cols + Int(c)
    }

    /// The top layer: flies and spiders, which hide the silk under them. Later puts win.
    @inline(__always) private func put(_ i: Int, _ glyph: UInt8, _ color: UInt32, _ block: UInt32 = 0) {
        if i < 0 { return }
        if topSeen.p[i] != frame {
            topSeen.p[i] = frame
            topCells.p[topN] = Int32(i)
            topN += 1
        }
        topGlyph.p[i] = glyph
        topInk.p[i] = color
        topBlock.p[i] = block
    }

    /// Paints the part of `world` inside `viewport` (habitat space) on `grid` into `canvas`, which arrives
    /// cleared. Sets the canvas's background and grid colour.
    public func paint(_ world: WebWorld, viewport: CGRect, grid: GridSpec, theme t: ThemeParams, into canvas: CellCanvas) {
        setTheme(t)
        let bg = WebPainter.background(t)
        canvas.background = bg.rgb
        canvas.gridColor = bg.grid
        cols = canvas.cols
        rows = canvas.rows
        cw = Double(grid.cell.width)
        ch = Double(grid.cell.height)
        ox = Double(viewport.minX)
        oy = Double(viewport.minY)
        guard cols > 0, rows > 0 else { return }
        let n = cols * rows
        if topSeen.ensure(n) { frame = 0 }
        _ = topCells.ensure(n); _ = topGlyph.ensure(n); _ = topInk.ensure(n); _ = topBlock.ensure(n)
        silk.resize(cols: cols, rows: rows)
        legStrokes.resize(cols: cols, rows: rows)

        frame &+= 1
        if frame == 0 { topSeen.p.update(repeating: 0, count: topSeen.capacity); frame = 1 }
        topN = 0
        let time = world.time

        drawFlies(world)
        for b in world.heat {
            let i = cell(b.x, b.y)
            let a = Int(mathRound(clamp(b.life, 0, 1) * Double(LEVELS)))
            put(i, b.life > 0.5 ? G.star : G.dot, heatStyles[a])
        }
        // Far webs' spiders first, so nearer ones draw over them; the jumper is nearest of all.
        for w in world.weavers { drawSpider(w.spider, 0.72 + 0.28 * w.web.depth, time) }
        if let j = world.jumper { drawSpider(j.spider, 1, time) }

        // ── silk ──
        let S = silk
        S.begin()
        S.layered = true
        for web in world.webs { addWeb(web, S) }
        for w in world.weavers { addThreads(w, S) }
        if let j = world.jumper, let jd = j.drag {
            let tmp = j.spider.spinneret()
            S.add(jd.x - ox, jd.y - oy, tmp.x - ox, tmp.y - oy, cw, ch, 0.5 * jd.life * palette.silkGain)
        }

        canvas.glyph.withUnsafeMutableBufferPointer { glyph in
            canvas.ink.withUnsafeMutableBufferPointer { ink in
                for k in 0..<S.length {
                    let i = Int(S.cells[k])
                    if topSeen.p[i] == frame { continue }
                    let cov = S.cov(i)
                    if cov < 0.1 { continue }
                    let e = Double(S.e.p[i])
                    let a = Double(S.a.p[i]) * (S.count.p[i] >= 4 ? 1.25 : 1) + clamp((e - 0.12) * 0.4, 0, 0.5)
                    let level = Int(clamp(mathRound(a * Double(LEVELS)), 1, Double(LEVELS)))
                    ink[i] = e > 0.45 ? ringStyles[level] : silkStyles[level]
                    glyph[i] = S.glyph(i)
                }
            }
        }

        drawDew(world, time, canvas)

        // ── top layer ──
        canvas.glyph.withUnsafeMutableBufferPointer { glyph in
            canvas.ink.withUnsafeMutableBufferPointer { ink in
                canvas.block.withUnsafeMutableBufferPointer { block in
                    for k in 0..<topN {
                        let i = Int(topCells.p[k])
                        block[i] = topBlock.p[i]
                        glyph[i] = topGlyph.p[i]
                        ink[i] = topInk.p[i]
                    }
                }
            }
        }
    }

    /// Near webs read clearly; far ones are a whisper.
    @inline(__always) private func silkAlpha(_ web: OrbWeb) -> Double {
        (0.04 + 0.36 * pow(web.depth, 1.6)) * palette.silkGain
    }

    private func addWeb(_ web: OrbWeb, _ S: WebStrokes) {
        let base = silkAlpha(web)
        let x = web.x.p, y = web.y.p, la = web.la.p, lb = web.lb.p, state = web.state.p, kind = web.kind.p, speed = web.speed.p
        for l in 0..<web.m {
            // (The "full" stage draws every kind, up to STAB.)
            if state[l] != 1 || kind[l] > STAB { continue }
            let a = la[l]
            let b = lb[l]
            let e = Double(max(speed[a], speed[b]))
            S.add(Double(x[a]) - ox, Double(y[a]) - oy, Double(x[b]) - ox, Double(y[b]) - oy, cw, ch,
                  base * SILK_ALPHA[kind[l]], kind[l] == MOOR ? 0 : e)
        }
    }

    /// A weaver's loose silk: the thread it is laying (or reeling in), and the lines to its parcels.
    private func addThreads(_ w: Weaver, _ S: WebStrokes) {
        let web = w.web
        let base = silkAlpha(web)
        let sp = w.spider
        if w.partial >= 0 && w.partial < web.n {
            S.add(Double(web.x[w.partial]) - ox, Double(web.y[w.partial]) - oy, sp.rx - ox, sp.ry - oy, cw, ch, min(1, base * 2.4))
        }
        // (The original loops over [carried prey, bundle]; two calls build no array.)
        @inline(__always) func line(_ parcel: Fly?) {
            guard let parcel else { return }
            let tmp = sp.spinneret()
            S.add(tmp.x - ox, tmp.y - oy, parcel.x - ox, parcel.y - oy, cw, ch, min(1, base * 2))
        }
        line(w.state == .carry ? w.prey : nil)
        line(w.bundle)
    }

    /// Dew is drawn over the silk glyph in its cell (the canvas overlay), as the original draws a second glyph there.
    private func drawDew(_ world: WebWorld, _ t: Double, _ canvas: CellCanvas) {
        canvas.overGlyph.withUnsafeMutableBufferPointer { og in
            canvas.overInk.withUnsafeMutableBufferPointer { oi in
                for web in world.webs {
                    let dew = web.dew.p, state = web.state.p
                    for l in 0..<web.m {
                        if dew[l] < 0 || state[l] != 1 { continue }
                        let p = web.pos(l, Double(dew[l]))
                        let i = cell(p.x, p.y)
                        if i < 0 || topSeen.p[i] == frame { continue }
                        let tw = 0.5 + 0.5 * sin(t * (0.8 + hash3(Double(l), web.seed, 9) * 1.4) + Double(l) * 1.37)
                        let a = (0.3 + 0.6 * tw) * (0.45 + 0.55 * web.depth) * palette.silkGain
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

    private func drawFlies(_ world: WebWorld) {
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
            put(i, g, flyStyles[Int(clamp(mathRound(a * Double(LEVELS)), 1, Double(LEVELS)))])
        }
    }

    // ── spiders ──

    private func drawSpider(_ sp: Spider, _ dim: Double, _ t: Double) {
        let p = palette
        let spec = sp.sp
        let tr = spec.tint[0], tg = spec.tint[1], tb = spec.tint[2]
        sp.solve()

        // Legs: stroke glyphs, each segment its own shade; banded species alternate light and dark.
        let L = legStrokes
        L.begin()
        let nLegs = sp.legs.count
        for k in 0..<nLegs {
            let leg = sp.legs[k]
            let lv = spec.leg * (leg.i == 0 && spec.eyes ? 0.9 : 1)
            let band = spec.band
            segment(L, leg.hx, leg.hy, leg.kx, leg.ky, lv, lv * (1 - band))
            segment(L, leg.kx, leg.ky, leg.fx, leg.fy, lv * 0.92, lv * (1 - band) * 0.92)
        }
        for k in 0..<L.length {
            let i = Int(L.cells[k])
            if L.cov(i) < 0.12 { continue }
            let lv = Double(L.a.p[i]) * dim
            put(i, L.glyph(i), pack(p.tone(p.legLevel(lv), tr, tg, tb)), pack(p.tone(p.legBlock(lv), tr, tg, tb)))
        }

        // Body: supersample each cell of the bounding box against the two ellipses.
        let s = sp.scale
        let B = sp.B * s
        let reach = (spec.prosoma[0] + spec.abdomen[0]) * 2.1 * B
        let lx = sp.rx - ox, ly = sp.ry - oy
        guard lx.isFinite, ly.isFinite, reach.isFinite else { return }
        let c0 = max(0, Int(floor((lx - reach) / cw)))
        let c1 = min(cols - 1, Int(max(-1, floor((lx + reach) / cw))))
        let r0 = max(0, Int(floor((ly - reach) / ch)))
        let r1 = min(rows - 1, Int(max(-1, floor((ly + reach) / ch))))
        guard c0 <= c1, r0 <= r1 else { return }
        let tick = floor(t * 2.4)
        let dark = spec.eyes
        for r in r0...r1 {
            for c in c0...c1 {
                let x = Double(c) * cw + ox
                let y = Double(r) * ch + oy
                let center = sample(sp, x + cw / 2, y + ch / 2)
                let flag = hitFlag
                let shade = hitShade
                let key = hitKey
                var hits = center ? 1 : 0
                for k in stride(from: 0, to: SUBSAMPLES.count, by: 2) where sample(sp, x + SUBSAMPLES[k] * cw, y + SUBSAMPLES[k + 1] * ch) {
                    hits += 1
                }
                if hits == 0 { continue }
                let i = r * cols + c
                let cover = Double(hits) / 5
                if !center || cover < 0.6 {
                    let set = cover >= 0.5 ? G.EDGE_HEAVY : G.EDGE_LIGHT
                    put(i, set[Int((key >> 8) % UInt32(set.count))], pack(p.tone((70 + cover * 80) * dim, tr, tg, tb)))
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
                    color = eye
                case FANG:
                    level = 26
                    glyph = G.v
                    color = fang
                case MARK:
                    level = 22 + shade * 26
                    glyph = G.MARK_GLYPHS[Int((key >> 8) % 3)]
                    color = pack(p.tone(70, tr, tg, tb))
                case SPOT:
                    level = 120 + shade * 80
                    glyph = G.SPOT_GLYPHS[Int((key >> 8) % 3)]
                    color = spot
                case CROSS:
                    level = 110 + shade * 70
                    glyph = G.plus
                    color = spot
                case BAND:
                    // Argiope's bright bands: warm yellow on black, a paler graphite on paper.
                    level = 120 + shade * 110
                    ttr = 1.18
                    ttg = 1.06
                    ttb = 0.42
                    glyph = G.SKIN_RAMP[Int(clamp(floor((1 - shade) * 6), 0, 8))]
                    color = shade > 0.5 ? glyphLit : glyphShadow
                default:
                    level = dark ? 30 + shade * 96 : 48 + shade * 150
                    let jitter = Int((key >> 4) % 3) - 1
                    glyph = G.SKIN_RAMP[Int(clamp(floor((1 - shade) * 8.99) + Double(jitter), 0, Double(G.SKIN_RAMP.count - 1)))]
                    // Accents and flecks at the original's rates, scaled by the theme's (Calm: fewer).
                    if !p.accents.isEmpty && roll < 0.06 * accentRate { color = accentInks[Int(key % UInt32(p.accents.count))] }
                    else if roll < 0.1 * accentRate { color = fleck }
                    else { color = shade > 0.55 ? glyphLit : glyphShadow }
                }
                put(i, glyph, color, pack(p.tone(level * dim, ttr, ttg, ttb)))
            }
        }
    }

    /// A leg segment in two halves, so banded legs alternate shade along their length.
    @inline(__always) private func segment(_ L: WebStrokes, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ l0: Double, _ l1: Double) {
        let mx = (x0 + x1) / 2
        let my = (y0 + y1) / 2
        L.add(x0 - ox, y0 - oy, mx - ox, my - oy, cw, ch, l0)
        L.add(mx - ox, my - oy, x1 - ox, y1 - oy, cw, ch, l1)
    }

    /**
     * Classify a point against a spider's body. Body frame: u forward from the pedicel, v to the right.
     * Writes hitFlag, hitShade and hitKey (a body-anchored hash, so glyphs ride along with the body).
     */
    private func sample(_ sp: Spider, _ px: Double, _ py: Double) -> Bool {
        let spec = sp.sp
        let s = sp.scale
        let B = sp.B
        let c = cos(sp.h)
        let sn = sin(sp.h)
        let dx = (px - sp.rx) / s
        let dy = (py - sp.ry) / s
        let u = dx * c + dy * sn
        let v = -dx * sn + dy * c
        let pa = spec.prosoma[0] * B
        let pb = spec.prosoma[1] * B
        let pu = sp.prosomaU
        let cw = self.cw / s
        hitKey = UInt32(hash3(mathRound(u / (cw * 0.9)), mathRound(v / (cw * 0.9)), Double(sp.id)) * 4_294_967_295)

        // Prosoma: an ellipse, or a rounded box for the jumper.
        var eu = (u - pu) / pa
        var ev = v / pb
        var e = spec.boxy ? pow(pow(abs(eu), 3) + pow(abs(ev), 3), 2.0 / 3) : eu * eu + ev * ev
        if e < 1 {
            hitShade = lit(eu / pa, ev / pb, e.squareRoot(), c, sn) * 0.92
            hitFlag = BODY
            if spec.eyes {
                // Two great forward eyes, at least a cell each, and the iridescent fangs between them.
                let er = max(pb * 0.38, cw * 0.62)
                let ex = u - (pu + pa * 0.5)
                for side in 0..<2 {
                    let ey = v - (side == 0 ? -1 : 1) * max(pb * 0.46, cw * 0.7)
                    if ex * ex + ey * ey < er * er { hitFlag = EYE }
                }
                if hitFlag == BODY && eu > 0.78 && abs(ev) < 0.42 { hitFlag = FANG }
            }
            return true
        }

        // Abdomen. The abdomen breathes.
        let aa = spec.abdomen[0] * B * sp.breath
        let ab = spec.abdomen[1] * B * (2 - sp.breath)
        eu = (u - sp.abdomenU) / aa
        ev = v / ab
        e = eu * eu + ev * ev
        if e >= 1 { return false }
        let across = e.squareRoot()
        hitShade = lit(eu / aa, ev / ab, across, c, sn)
        hitFlag = BODY
        let ch = self.ch / s
        let au = u - sp.abdomenU
        switch spec.pattern {
        case .cross:
            // The garden spider's cross on a dark scalloped folium.
            let mid = abs(v) < max(ab * 0.16, cw * 0.55)
            let bar = abs(au - aa * 0.28) < max(aa * 0.12, ch * 0.5) && abs(v) < ab * 0.5
            if (mid && eu > -0.45 && eu < 0.78) || bar { hitFlag = CROSS }
            else if abs(ev) < 0.62 + 0.12 * sin(eu * 9) && eu < 0.6 { hitFlag = MARK }
        case .bands:
            let n = max(2, mathRound((aa * 2) / (ch * 1.7)))
            if sin((eu * 0.5 + 0.5) * Double.pi * n * 2 + 0.6) > 0.15 { hitFlag = MARK } else { hitFlag = BAND }
        case .spots:
            let lane = abs(abs(v) - ab * 0.5) < max(ab * 0.22, cw * 0.45)
            if lane && sin(eu * 9) > 0.3 { hitFlag = SPOT }
        case .jumper:
            // Phidippus: a pale triangle and two spots on black, a pale band across the front.
            if eu > 0.72 { hitFlag = SPOT }
            else if eu > -0.05 && eu < 0.45 && abs(v) < max(ab * 0.32 * (1 - (0.45 - eu)), cw * 0.5) { hitFlag = SPOT }
            else if abs(eu + 0.45) < 0.16 && abs(abs(v) - ab * 0.5) < max(ab * 0.16, cw * 0.4) { hitFlag = SPOT }
        }
        return true
    }

    /// Rounded body lit from the top-left, as the sharks are.
    @inline(__always) private func lit(_ nu: Double, _ nv: Double, _ across: Double, _ c: Double, _ sn: Double) -> Double {
        let h = hypot(nu, nv)
        let l = h == 0 || h.isNaN ? 1 : h
        let nx = (nu * c - nv * sn) / l
        let ny = (nu * sn + nv * c) / l
        let facing = (nx * -0.6 + ny * -0.8) * across
        return clamp(0.58 - across * across * 0.42 + facing * 0.26, 0, 1)
    }
}
