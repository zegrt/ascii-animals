import CoreGraphics
import Foundation

// The Meadow's painter, ported from the sketch's drawing (`Tools/meadow-sketch/meadow.html` on `meadow-sketch` at
// 4e1b869; `html:N` is a line of it): the cell writers and the palettes (html:430–713), the flowers (html:980–1281),
// the ground, grass and motes (html:2518–2592), the shadows, butterflies and rim (ButterflyPainter.swift), pollen,
// and the blit with Calm (html:2610–2675), onto the family's `CellCanvas` with m3's ground per cell.
//
// The sketch draws every cell every frame. The port draws the same cells but only touches the ones something is
// drawn on: the ground and its grass are cached per screen; each flower's cells are recorded and replayed until its
// head moves a quarter cell (or it grows, fades or its visit dim changes); the air is read on its grid once a frame.
// Nothing allocates per frame once warm.

/// The glyphs the sketch uses (`GL`, html:617), as `GlyphAtlas` indices.
enum MG {
    static let none: UInt8 = 255
    static let colon: UInt8 = 0, semi: UInt8 = 1, t: UInt8 = 2, pct: UInt8 = 3, S: UInt8 = 4, X: UInt8 = 5, eight: UInt8 = 6
    static let hash: UInt8 = 7, at: UInt8 = 8, dot: UInt8 = 9, quote: UInt8 = 10, comma: UInt8 = 11, tick: UInt8 = 12
    static let o: UInt8 = 13, dash: UInt8 = 14, star: UInt8 = 15, mid: UInt8 = 16, over: UInt8 = 17, under: UInt8 = 18
    static let slash: UInt8 = 19, back: UInt8 = 20, bar: UInt8 = 21, plus: UInt8 = 22, x: UInt8 = 23, O: UInt8 = 24
    static let deg: UInt8 = 25, v: UInt8 = 26, zero: UInt8 = 27
    static let heavy: [UInt8] = [colon, semi]
    static let lightEdge: [UInt8] = [dot, quote, comma, tick]
    static let skin: [UInt8] = [colon, semi, t, pct, S, X, eight, hash, at]
    static let tufts: [UInt8] = [comma, quote, tick, dot, comma, quote, mid]
    static let marks: [UInt8] = [hash, pct, at, eight, hash, pct, X]

    /// `DIM_STEP` (html:987): a visited disc's glyph drops a step.
    @inline(__always) static func dimStep(_ g: UInt8) -> UInt8 {
        switch g {
        case o: return deg
        case deg: return mid
        case mid: return dot
        case star: return x
        case x: return plus
        case plus: return mid
        default: return g
        }
    }
}

/// `lineGlyph` (html:624–631): Web's line glyph for a direction (pt, y down) and where the line runs in its cell.
@inline(__always) func meadowLine(_ dx: Double, _ dy: Double, _ m: Double = -1) -> UInt8 {
    var phi = atan2(dy, dx)
    if phi > .pi / 2 { phi -= .pi } else if phi <= -.pi / 2 { phi += .pi }
    let a = abs(phi)
    if a < 0.5 {
        if m < 0 { return MG.dash }
        return m < 0.3 ? MG.over : m > 0.7 ? MG.under : MG.dash
    }
    if a > 1.12 { return MG.bar }
    return phi > 0 ? MG.back : MG.slash
}

/// `hash3` and `keyOf` of the sketch.
@inline(__always) func mhash(_ x: Double, _ y: Double, _ z: Double) -> Double { MeadowMath.hash3(x, y, z) }
@inline(__always) func keyOf(_ x: Double, _ y: Double, _ s: Double) -> UInt32 { MeadowMath.key(x, y, s) }
@inline(__always) func lum(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

/// The meadow's plant colours (`plantInks`, html:480–494) and the paper ones (html:499, 537–549).
enum PlantInk {
    static let leaf = MeadowRGB(12, 32, 15), leafLit = MeadowRGB(24, 54, 26), rib = MeadowRGB(66, 108, 58), leafEdge = MeadowRGB(40, 78, 42)
    static let grass = MeadowRGB(50, 82, 44), stirred = MeadowRGB(132, 172, 106), ground = MeadowRGB(8, 20, 10)
    static let daisy = MeadowRGB(236, 234, 224), daisyEye = MeadowRGB(196, 150, 30), daisyEyeInk = MeadowRGB(248, 214, 96)
    static let cone = MeadowRGB(198, 112, 170), coneEye = MeadowRGB(110, 50, 22), coneEyeInk = MeadowRGB(226, 132, 52)
    static let milkweed = MeadowRGB(214, 136, 160), milkweedBody = MeadowRGB(92, 40, 60), milkweedInk = MeadowRGB(246, 190, 206)
    static let fennel = MeadowRGB(240, 224, 128), fennelRay = MeadowRGB(118, 142, 66)
    static let clover = MeadowRGB(200, 106, 142), cloverTip = MeadowRGB(236, 196, 212), cloverBody = MeadowRGB(96, 40, 66)
    static let mustard = MeadowRGB(232, 200, 70), mustardBud = MeadowRGB(150, 160, 64)
    static let dandelion = MeadowRGB(236, 196, 52), dandelionEye = MeadowRGB(196, 128, 26)
    static let gold = MeadowRGB(232, 200, 90)
    static let paper = MeadowRGB(247, 246, 243), ink = MeadowRGB(35, 35, 35)
    static let groundPaper = MeadowRGB(236, 240, 229), goldPaper = MeadowRGB(150, 124, 40)
    static let paperGrass = MeadowRGB(126, 144, 112), paperGrassStirred = MeadowRGB(98, 124, 80)
    static let accents: [MeadowRGB] = [MeadowRGB(224, 137, 44), MeadowRGB(224, 58, 50), MeadowRGB(180, 74, 224), MeadowRGB(51, 200, 204),
                                       MeadowRGB(60, 181, 74), MeadowRGB(49, 80, 232), MeadowRGB(217, 193, 74)]
}

/// A flower part's paper colours (`PAPER_PLANTS`, html:537–548): pigment, amount, glyph ink, glyph alpha.
struct PaperPart {
    let pig: MeadowRGB, amount: Double, ink: MeadowRGB, alpha: Double
    init(_ p: MeadowRGB, _ a: Double, _ i: MeadowRGB, _ al: Double) { pig = p; amount = a; ink = i; alpha = al }
}

/// The parts a flower's sample can hit (the sketch's `FH.part`).
enum FlowerPart: Int { case disc, petal, floret, tip, cluster, umbel, ray, bud, mflower, mpetal, leaf, thread }

/// What a flower sample hit (the sketch's `FH`, html:983).
struct FlowerHit {
    var hit = 0
    var r = 0.0, g = 0.0, b = 0.0
    var gi: UInt8 = MG.none
    var ir = 0.0, ig = 0.0, ib = 0.0, ia = 1.0
    var solid = true, disc = false, lit = false
    var part = FlowerPart.leaf
    var k = 1.0
    @inline(__always) mutating func set(_ layer: Int, _ r: Double, _ g: Double, _ b: Double, _ gi: UInt8, _ ir: Double, _ ig: Double, _ ib: Double,
                                        _ ia: Double, _ solid: Bool) {
        hit = layer; self.r = r; self.g = g; self.b = b; self.gi = gi; self.ir = ir; self.ig = ig; self.ib = ib; self.ia = ia
        self.solid = solid; disc = false; lit = false
    }
}

/// One recorded cell write of a flower, replayed every frame until the flower is drawn again.
struct FlowerOp {
    enum Kind: UInt8 { case block, glyph, shimmerGlyph, clearGlyph, shade }
    var kind: Kind
    var gi: UInt8
    var cell: Int32
    var r: Float, g: Float, b: Float, a: Float
    var key: UInt32
    /// The shimmer's last roll and the tick it was rolled on (it re-rolls 2.4 times a second, html:599).
    var tick: Int32 = Int32.min
    var roll: Float = 1
    /// The colour pushed back with the meadow (`far` of r, g, b), for the push its cache's `farKey` names.
    var fr = 0.0, fg = 0.0, fb = 0.0
}

/// A flower's recorded cells on one screen, with what they were drawn at: a slot, reused for another flower once
/// this one has gone (its storage kept).
final class FlowerCache {
    var ops: [FlowerOp] = []
    var hx = Double.nan, hy = Double.nan
    var grow = -1.0, leafGrow = -1.0, fk = -1.0, vd = -1.0, radius = -1.0
    var used = 0
    /// The push (`FAR`, `FAR_DIM`, `FAR_SAT`, paper) the ops' `fr`, `fg`, `fb` were made for; NaN when none.
    var farKey = SIMD4<Double>(.nan, .nan, .nan, .nan)
    /// Ready for another flower: nothing recorded, drawn next time.
    func reset() {
        ops.removeAll(keepingCapacity: true)
        farKey = SIMD4(.nan, .nan, .nan, .nan)
        hx = .nan; hy = .nan
        grow = -1; leafGrow = -1; fk = -1; vd = -1; radius = -1
    }
}

/// Grow-only raw storage: the painter's buffers are read and written through plain pointers in the frame's loops,
/// so the hot paths carry no runtime exclusivity or uniqueness checks (as Web's painter does).
struct MBuf<T> {
    private(set) var p: UnsafeMutablePointer<T>
    private(set) var capacity = 0
    private let zero: T
    init(_ zero: T) { self.zero = zero; p = .allocate(capacity: 1); p.initialize(to: zero); capacity = 1 }
    /// True when it had to grow.
    @discardableResult mutating func ensure(_ n: Int) -> Bool {
        guard n > capacity else { return false }
        p.deallocate()
        p = .allocate(capacity: n)
        p.initialize(repeating: zero, count: n)
        capacity = n
        return true
    }
    func free() { p.deallocate() }
}

/// One screen's cached ground (`buildGround`, html:2523–2543) and its flowers' recordings.
final class ViewportCache {
    var rect = CGRect.null
    var cols = 0, rows = 0
    var cw = 0.0, ch = 0.0
    var light = false
    var bright = 1.0
    var green = -1.0, grass = -1.0, unit = -1.0
    var gR = MBuf<Float>(0), gG = MBuf<Float>(0), gB = MBuf<Float>(0)
    var packed = MBuf<UInt32>(0)
    var built = false
    var tuftCells: [Int32] = []
    var tuftGlyph: [UInt8] = []
    var tuftK: [Float] = []
    var tuftM: [Float] = []
    /// Each tuft's `hash3(c, r, 13)` (whether it lies over in a gust), fixed per cell.
    var tuftH: [Float] = []
    /// Each tuft's four air samples (`j`, `j1`, `j2`, `j3`) and its weights between them on the breeze's grid laid
    /// as `airKey` says (the grid's origin, spacing, columns and rows); made again when the tufts or the grid change.
    var tuftAir: [SIMD4<Int32>] = []
    var tuftW: [SIMD2<Float>] = []
    var airKey = SIMD4<Double>(.nan, .nan, .nan, .nan)
    var airRows = -1
    /// The flowers' recordings by flower id, in slots that are reused: `slots` holds every slot made, `free` the
    /// ones not in use. Sized by the world's flower bound (`Flowers.most`) before drawing, so a new flower (a click)
    /// takes a slot without allocating; slots of flowers not drawn are handed back every `sweepEvery` of this
    /// screen's own paints, so each screen's recordings stay bounded however the screens' paints interleave.
    var flowers: [Int: FlowerCache] = [:]
    var slots: [FlowerCache] = []
    var free: [FlowerCache] = []
    var sweepIds: [Int] = []
    /// What a slot's recording is sized for (ops).
    var opsRoom = 0
    /// This screen's own paints.
    var paints = 0
    var used = 0
    static let sweepEvery = 60

    /// Every slot back to free (a rebuild or a new screen).
    func releaseFlowers() {
        for (_, c) in flowers { c.reset(); free.append(c) }
        flowers.removeAll(keepingCapacity: true)
    }

    /// Enough slots for `count` flowers, each with room for `ops` (allocates only when the bound grows).
    func ensureSlots(_ count: Int, ops: Int) {
        if ops > opsRoom {
            opsRoom = ops
            for c in slots where c.ops.capacity < ops { c.ops.reserveCapacity(ops) }
        }
        guard slots.count < count else { return }
        flowers.reserveCapacity(count)
        free.reserveCapacity(count)
        sweepIds.reserveCapacity(count)
        slots.reserveCapacity(count)
        while slots.count < count {
            let c = FlowerCache()
            c.ops.reserveCapacity(opsRoom)
            slots.append(c)
            free.append(c)
        }
    }

    /// A slot for flower `id` (its own if it has one).
    func slot(_ id: Int, paint: Int) -> FlowerCache {
        if let c = flowers[id] { return c }
        if free.isEmpty { sweep(paint, keepLast: true) }
        if free.isEmpty { sweep(paint, keepLast: false) }
        let c: FlowerCache
        if let f = free.popLast() { c = f } else { c = FlowerCache(); c.ops.reserveCapacity(opsRoom); slots.append(c) }
        flowers[id] = c
        return c
    }

    /// Hands back the slots of flowers not drawn this paint (or, with `keepLast`, not drawn this paint or the last).
    func sweep(_ paint: Int, keepLast: Bool) {
        let oldest = keepLast ? paint - 1 : paint
        for (id, c) in flowers where c.used < oldest { sweepIds.append(id) }
        for id in sweepIds {
            if let c = flowers.removeValue(forKey: id) { c.reset(); free.append(c) }
        }
        sweepIds.removeAll(keepingCapacity: true)
    }

    deinit { gR.free(); gG.free(); gB.free(); packed.free() }
}

/// The Meadow's painter: owns the buffers and caches; each frame is drawn by a `MeadowFrame` over them.
public final class MeadowPainter {
    var n = 0
    var BR = MBuf<Float>(0), BG = MBuf<Float>(0), BB = MBuf<Float>(0)
    var HB = MBuf<UInt8>(0), GI = MBuf<UInt8>(MG.none)
    var IR = MBuf<Float>(0), IG = MBuf<Float>(0), IB = MBuf<Float>(0), IA = MBuf<Float>(0)
    var stamp = MBuf<UInt32>(0), touched = MBuf<Int32>(0)
    var recMark = MBuf<UInt32>(0), recList = MBuf<Int32>(0), rimMark = MBuf<UInt32>(0), rimW = MBuf<Float>(0), rimList = MBuf<Int32>(0)
    var wingStamp = MBuf<UInt32>(0)
    var frame: UInt32 = 0, recStamp: UInt32 = 0, rimStamp: UInt32 = 0, wingStampN: UInt32 = 0
    var views: [ViewportCache] = []
    var paintCount = 0
    var airX = MBuf<Float>(0), airY = MBuf<Float>(0)
    var airTime = -1.0, airSteps = -1, airCount = -1
    /// The gust noise's corner hashes over this frame's grid, one table per octave (`GustReader`).
    var lattice1 = MBuf<Double>(0), lattice2 = MBuf<Double>(0)
    var order = MBuf<Int>(0)
    let spans = WingSpans.make()
    var veins = MBuf<VeinSeg>(VeinSeg())
    var edges = MBuf<EdgeSeg>(EdgeSeg()), edgeN = MBuf<Int>(0)
    /// The grass ink by how hard the air moves it, 65 steps, made each frame.
    var grassInk = MBuf<SIMD3<Float>>(.zero)

    public init() { veins.ensure(16); grassInk.ensure(65); edges.ensure(4 * WingSpans.maxPoints); edgeN.ensure(4) }

    deinit {
        BR.free(); BG.free(); BB.free(); HB.free(); GI.free(); IR.free(); IG.free(); IB.free(); IA.free()
        stamp.free(); touched.free(); recMark.free(); recList.free(); rimMark.free(); rimW.free(); rimList.free()
        wingStamp.free(); airX.free(); airY.free(); lattice1.free(); lattice2.free(); order.free(); veins.free(); spans.free(); grassInk.free(); edges.free(); edgeN.free()
    }

    private func ensure(_ count: Int) {
        guard count > n else { return }
        n = count
        BR.ensure(n); BG.ensure(n); BB.ensure(n); HB.ensure(n); GI.ensure(n)
        IR.ensure(n); IG.ensure(n); IB.ensure(n); IA.ensure(n)
        stamp.ensure(n); touched.ensure(n); recMark.ensure(n); recList.ensure(n); rimMark.ensure(n); rimW.ensure(n); rimList.ensure(n)
        wingStamp.ensure(n)
        frame = 0; recStamp = 0; rimStamp = 0; wingStampN = 0
    }

    private func view(for rect: CGRect) -> ViewportCache {
        for v in views where v.rect == rect { return v }
        if views.count < 8 {
            let v = ViewportCache()
            v.rect = rect
            views.append(v)
            return v
        }
        var oldest = views[0]
        for v in views where v.used < oldest.used { oldest = v }
        oldest.rect = rect
        oldest.built = false
        oldest.releaseFlowers()
        return oldest
    }

    /// Paints the part of `world` inside `viewport` (habitat space) on `grid` into `canvas`, which arrives cleared
    /// (`render` and `blit`, html:2610–2675).
    public func paint(_ world: MeadowWorld, viewport: CGRect, grid: GridSpec, theme t: ThemeParams, into canvas: CellCanvas) {
        let bg = WebPainter.background(t)
        canvas.background = bg.rgb
        canvas.gridColor = bg.grid
        let cols = canvas.cols, rows = canvas.rows
        guard cols > 0, rows > 0 else { return }
        ensure(cols * rows)
        frame &+= 1
        if frame == 0 { stamp.p.update(repeating: 0, count: n); frame = 1 }
        paintCount += 1
        let v = view(for: viewport)
        v.used = paintCount
        v.paints += 1
        var f = MeadowFrame(painter: self, world: world, view: v, cols: cols, rows: rows, viewport: viewport, grid: grid, theme: t)
        f.buildGround()
        f.readAir()
        f.drawGround()
        f.drawFlowers()
        f.drawButterflies()
        f.drawDust()
        f.blit(canvas)
        recStamp = f.recStamp
        rimStamp = f.rimStamp
        wingStampN = f.wingStampN
    }
}

/// One frame of one screen: the sketch's cell writers and drawing over the painter's buffers.
struct MeadowFrame {
    unowned let painter: MeadowPainter
    unowned let world: MeadowWorld
    unowned let v: ViewportCache
    let n: Int
    // This frame's cells (html:642). HB: 1 the cell has a block; 2 no block but its ground was shaded; 0 neither.
    let BR: UnsafeMutablePointer<Float>, BG: UnsafeMutablePointer<Float>, BB: UnsafeMutablePointer<Float>
    let HB: UnsafeMutablePointer<UInt8>, GI: UnsafeMutablePointer<UInt8>
    let IR: UnsafeMutablePointer<Float>, IG: UnsafeMutablePointer<Float>, IB: UnsafeMutablePointer<Float>, IA: UnsafeMutablePointer<Float>
    let stamp: UnsafeMutablePointer<UInt32>, touched: UnsafeMutablePointer<Int32>
    let recMark: UnsafeMutablePointer<UInt32>, recList: UnsafeMutablePointer<Int32>
    let rimMark: UnsafeMutablePointer<UInt32>, rimW: UnsafeMutablePointer<Float>, rimList: UnsafeMutablePointer<Int32>
    let wingStamp: UnsafeMutablePointer<UInt32>
    var gR: UnsafeMutablePointer<Float>, gG: UnsafeMutablePointer<Float>, gB: UnsafeMutablePointer<Float>
    let spans: WingSpans
    let veins: UnsafeMutablePointer<VeinSeg>
    let edges: UnsafeMutablePointer<EdgeSeg>, edgeN: UnsafeMutablePointer<Int>
    let frame: UInt32
    var touchedN = 0
    var recStamp: UInt32, rimStamp: UInt32, wingStampN: UInt32
    var REC = false
    var recN = 0
    // This frame's view.
    let cols: Int, rows: Int
    let cw: Double, ch: Double, S: Double
    let ox: Double, oy: Double
    /// The cell offset of this screen in the meadow's own cells, so hashes keyed by cell match the sketch's on one
    /// screen and stay put across screens.
    let gc0: Double, gr0: Double
    let LIGHT: Bool
    let calm: Bool
    let bright: Double
    let tuning: MeadowTuning
    let simT: Double
    let sparkleRate: Double
    let paintCount: Int
    /// This screen's own paints.
    let viewPaints: Int
    // Depth (`farPush`, html:675–690) and a fading flower's ink (`INK_K`, html:670).
    var FAR = 0.0, FAR_DIM = 1.0, FAR_SAT = 1.0, FAR_FLAT = 0.0, FAR_FAINT = 1.0
    var INK_K = 1.0
    var fh = FlowerHit()
    /// Recording a flower.
    var recording: FlowerCache? = nil

    init(painter p: MeadowPainter, world: MeadowWorld, view v: ViewportCache, cols: Int, rows: Int, viewport: CGRect, grid: GridSpec,
         theme t: ThemeParams) {
        painter = p
        self.world = world
        self.v = v
        n = p.n
        BR = p.BR.p; BG = p.BG.p; BB = p.BB.p; HB = p.HB.p; GI = p.GI.p
        IR = p.IR.p; IG = p.IG.p; IB = p.IB.p; IA = p.IA.p
        stamp = p.stamp.p; touched = p.touched.p
        recMark = p.recMark.p; recList = p.recList.p; rimMark = p.rimMark.p; rimW = p.rimW.p; rimList = p.rimList.p
        wingStamp = p.wingStamp.p
        gR = v.gR.p; gG = v.gG.p; gB = v.gB.p
        spans = p.spans
        veins = p.veins.p
        edges = p.edges.p; edgeN = p.edgeN.p
        frame = p.frame
        recStamp = p.recStamp; rimStamp = p.rimStamp; wingStampN = p.wingStampN
        self.cols = cols
        self.rows = rows
        cw = Double(grid.cell.width)
        ch = Double(grid.cell.height)
        S = world.breeze.unit
        ox = Double(viewport.minX)
        oy = Double(viewport.minY)
        gc0 = (ox / cw).rounded()
        gr0 = (oy / ch).rounded()
        LIGHT = t.light
        bright = Double(t.brightness)
        calm = bright < 1
        tuning = world.tuning
        sparkleRate = tuning.sparkle * (calm ? 0.35 : 1)
        simT = world.time
        paintCount = p.paintCount
        viewPaints = v.paints
    }

    // ── the cell writers (html:694–713) ──

    @inline(__always) mutating func touch(_ i: Int) {
        if stamp[i] != frame {
            stamp[i] = frame
            touched[touchedN] = Int32(i)
            touchedN += 1
            BR[i] = gR[i]; BG[i] = gG[i]; BB[i] = gB[i]
            HB[i] = 0
            GI[i] = MG.none
            IA[i] = 0
        }
    }

    /// `far` (html:684–690).
    @inline(__always) mutating func far(_ r: inout Double, _ g: inout Double, _ b: inout Double) {
        let l = lum(r, g, b)
        r = l + (r - l) * FAR_SAT; g = l + (g - l) * FAR_SAT; b = l + (b - l) * FAR_SAT
        if LIGHT {
            r = 247 + (r - 247) * FAR_DIM; g = 246 + (g - 246) * FAR_DIM; b = 243 + (b - 243) * FAR_DIM
        } else {
            r *= FAR_DIM; g *= FAR_DIM; b *= FAR_DIM
        }
    }

    /// `farPush` (html:678–682).
    mutating func farPush(_ p: Double) {
        FAR = p > 0 ? p : 0
        let q: Double = FAR * (LIGHT ? 0.8 : 1) * (calm ? 0.75 : 1)
        FAR_DIM = max(0.3, 1 - 0.3 * q)
        FAR_SAT = max(0.55, 1 - 0.18 * q)
        FAR_FLAT = min(0.5, 0.3 * q)
        FAR_FAINT = max(0.5, 1 - 0.15 * q)
    }


    /// `blockAt` (html:694–700).
    @inline(__always) mutating func blockAt(_ i: Int, _ r0: Double, _ g0: Double, _ b0: Double, _ a0: Double) {
        if let rc = recording { rc.ops.append(FlowerOp(kind: .block, gi: 0, cell: Int32(i), r: Float(r0), g: Float(g0), b: Float(b0), a: Float(a0), key: 0)); return }
        put(i, r0, g0, b0, a0)
    }

    @inline(__always) mutating func put(_ i: Int, _ r0: Double, _ g0: Double, _ b0: Double, _ a0: Double) {
        var r = r0, g = g0, b = b0
        if FAR != 0 { far(&r, &g, &b) }
        putFarred(i, r, g, b, a0)
    }

    /// `put` of a colour already pushed back (`far`) when `FAR` is set.
    @inline(__always) mutating func putFarred(_ i: Int, _ r: Double, _ g: Double, _ b: Double, _ a0: Double) {
        touch(i)
        if REC { rec(i) }
        let a = a0 * INK_K
        if a >= 1 {
            BR[i] = Float(r); BG[i] = Float(g); BB[i] = Float(b); HB[i] = 1
        } else if a > 0 {
            let fa = Float(a)
            BR[i] += (Float(r) - BR[i]) * fa; BG[i] += (Float(g) - BG[i]) * fa; BB[i] += (Float(b) - BB[i]) * fa; HB[i] = 1
        }
    }

    /// `glyphAt` (html:701–706).
    @inline(__always) mutating func glyphAt(_ i: Int, _ gi: UInt8, _ r0: Double, _ g0: Double, _ b0: Double, _ a0: Double) {
        if let rc = recording { rc.ops.append(FlowerOp(kind: .glyph, gi: gi, cell: Int32(i), r: Float(r0), g: Float(g0), b: Float(b0), a: Float(a0), key: 0)); return }
        putGlyph(i, gi, r0, g0, b0, a0)
    }

    @inline(__always) mutating func putGlyph(_ i: Int, _ gi: UInt8, _ r0: Double, _ g0: Double, _ b0: Double, _ a0: Double) {
        var r = r0, g = g0, b = b0
        if FAR != 0 { far(&r, &g, &b) }
        putGlyphFarred(i, gi, r, g, b, a0)
    }

    /// `putGlyph` of a colour already pushed back (`far`) when `FAR` is set.
    @inline(__always) mutating func putGlyphFarred(_ i: Int, _ gi: UInt8, _ r0: Double, _ g0: Double, _ b0: Double, _ a0: Double) {
        touch(i)
        var r = r0, g = g0, b = b0, a = a0
        if FAR != 0 {
            if HB[i] == 1 {
                let fl = FAR_FLAT
                r += (Double(BR[i]) - r) * fl; g += (Double(BG[i]) - g) * fl; b += (Double(BB[i]) - b) * fl
            } else {
                a *= FAR_FAINT
            }
        }
        GI[i] = gi
        IR[i] = Float(r); IG[i] = Float(g); IB[i] = Float(b); IA[i] = Float(a * INK_K)
    }

    @inline(__always) mutating func clearGlyph(_ i: Int) {
        if let rc = recording { rc.ops.append(FlowerOp(kind: .clearGlyph, gi: 0, cell: Int32(i), r: 0, g: 0, b: 0, a: 0, key: 0)); return }
        touch(i)
        GI[i] = MG.none
    }

    /// `shade` (html:708–713): a shadow, darker block, fainter glyph.
    @inline(__always) mutating func shade(_ i: Int, _ k: Double) {
        if k <= 0 { return }
        if let rc = recording { rc.ops.append(FlowerOp(kind: .shade, gi: 0, cell: Int32(i), r: 0, g: 0, b: 0, a: Float(k), key: 0)); return }
        touch(i)
        if HB[i] == 0 { HB[i] = 2 }
        if LIGHT {
            BR[i] *= Float(1 - 0.24 * k); BG[i] *= Float(1 - 0.21 * k); BB[i] *= Float(1 - 0.15 * k); IA[i] *= Float(1 - 0.5 * k)
        } else {
            let m = Float(1 - k)
            BR[i] *= m; BG[i] *= m; BB[i] *= m; IA[i] *= Float(1 - 0.9 * k)
        }
    }

    @inline(__always) mutating func rec(_ i: Int) {
        if recMark[i] != recStamp { recMark[i] = recStamp; recList[recN] = Int32(i); recN += 1 }
    }

    // ── the palette (html:438–455, 509–512, 566–611) ──

    /// `toneP` (html:441–448): Web's tone on paper.
    @inline(__always) mutating func toneP(_ r: Double, _ g: Double, _ b: Double, _ lv: Double = -1, _ hs: Double = 0.5) -> (Double, Double, Double) {
        let l = max(1, lum(r, g, b))
        let k: Double = clamp((lv < 0 ? l : lv) / 255, 0, 1)
        let o0: Double = clamp((35 + (247 - 35) * k) * (1 + (r / l - 1) * hs), 0, 247)
        let o1: Double = clamp((35 + (246 - 35) * k) * (1 + (g / l - 1) * hs), 0, 246)
        let o2: Double = clamp((35 + (243 - 35) * k) * (1 + (b / l - 1) * hs), 0, 243)
        return (o0, o1, o2)
    }

    /// `atLevel` (html:450–455).
    @inline(__always) mutating func atLevel(_ c: MeadowRGB, _ level: Double) -> (Double, Double, Double) {
        let l = max(1, lum(c.x, c.y, c.z))
        if LIGHT { return toneP(c.x, c.y, c.z, level) }
        return (min(255, c.x * level / l), min(255, c.y * level / l), min(255, c.z * level / l + 4))
    }

    /// `paperWash` (html:509–512).
    @inline(__always) mutating func paperWash(_ p: MeadowRGB, _ a: Double) -> (Double, Double, Double) {
        (247 * pow(p.x / 255, a), 246 * pow(p.y / 255, a), 243 * pow(p.z / 255, a))
    }

    /// `wBlock`, `wGlyph`, `sBlock`, `sGlyph`, `lGlyph`, `carved`, `edgeGlyph` (html:567–588).
    @inline(__always) mutating func wBlock(_ i: Int, _ r: Double, _ g: Double, _ b: Double, _ a: Double) {
        if LIGHT { let c = toneP(r, g, b); blockAt(i, c.0, c.1, c.2, a) } else { blockAt(i, r, g, b, a) }
    }
    @inline(__always) mutating func wGlyph(_ i: Int, _ gi: UInt8, _ r: Double, _ g: Double, _ b: Double, _ a: Double) {
        if LIGHT { let c = toneP(r, g, b); glyphAt(i, gi, c.0, c.1, c.2, a) } else { glyphAt(i, gi, r, g, b, a) }
    }
    @inline(__always) mutating func sBlock(_ i: Int, _ r: Double, _ g: Double, _ b: Double, _ a: Double, _ hs: Double = 0.3) {
        if LIGHT {
            let lv: Double = 250 - 0.5 * min(255, lum(r, g, b) / 0.34)
            let c = toneP(r, g, b, lv, hs)
            blockAt(i, c.0, c.1, c.2, a)
        } else { blockAt(i, r, g, b, a) }
    }
    @inline(__always) mutating func sGlyph(_ i: Int, _ gi: UInt8, _ r: Double, _ g: Double, _ b: Double, _ a: Double) {
        if LIGHT {
            let c = toneP(r, g, b, 250 - 1.25 * lum(r, g, b) / 1.12)
            glyphAt(i, gi, c.0, c.1, c.2, a)
        } else { glyphAt(i, gi, r, g, b, a) }
    }
    @inline(__always) mutating func lGlyph(_ i: Int, _ gi: UInt8, _ r: Double, _ g: Double, _ b: Double, _ a: Double) {
        if LIGHT { let c = toneP(r, g, b, 0); glyphAt(i, gi, c.0, c.1, c.2, a * 0.85) } else { glyphAt(i, gi, r, g, b, a) }
    }
    @inline(__always) mutating func carved(_ i: Int, _ gi: UInt8, _ shade: Double) {
        if LIGHT {
            if shade > 0.55 { glyphAt(i, gi, 35, 35, 35, 1) } else { glyphAt(i, gi, 22, 22, 22, 1) }
        } else if shade > 0.55 { glyphAt(i, gi, 14, 15, 19, 1) } else { glyphAt(i, gi, 27, 29, 36, 1) }
    }
    @inline(__always) mutating func edgeGlyph(_ i: Int, _ gi: UInt8, _ c: MeadowRGB, _ level: Double) {
        let o = atLevel(c, level)
        glyphAt(i, gi, o.0, o.1, o.2, 1)
    }

    /// `shimmer` (html:597–602): 1 an accent, 2 a fleck, 0 neither, re-rolled 2.4 times a second on each cell's phase.
    @inline(__always) mutating func shimmer(_ key: UInt32, _ acc: Double, _ fleck: Double) -> Int {
        let k = sparkleRate
        if k <= 0 { return 0 }
        let kd = Double(key)
        let roll = mhash(kd, floor(simT * 2.4 + Double(key % 997) / 97), 7)
        if !LIGHT && roll < acc * k { return 1 }
        return roll < fleck * k ? 2 : 0
    }

    /// `shimmerGlyph` (html:605–610).
    @inline(__always) mutating func shimmerGlyph(_ i: Int, _ gi: UInt8, _ kind: Int, _ key: UInt32, _ darkFleck: Bool) {
        if kind == 1 { let c = PlantInk.accents[Int(key % 7)]; putGlyph(i, gi, c.x, c.y, c.z, 1) }
        else if LIGHT { putGlyph(i, gi, 247, 246, 243, 1) }
        else if darkFleck { putGlyph(i, gi, 6, 6, 8, 1) }
        else { putGlyph(i, gi, 255, 255, 255, 1) }
    }

    // ── the ground (html:2522–2592) ──

    /// `buildGround` (html:2523–2543), cached per screen; rebuilt when the screen, cell, theme, Calm or the green
    /// and grass settings change.
    mutating func buildGround() {
        let green = tuning.green, grassAmt = tuning.grass
        if v.built && v.cols == cols && v.rows == rows && v.cw == cw && v.ch == ch && v.light == LIGHT && v.bright == bright
            && v.green == green && v.grass == grassAmt && v.unit == S { return }
        v.built = true
        v.cols = cols; v.rows = rows; v.cw = cw; v.ch = ch; v.light = LIGHT; v.bright = bright; v.green = green; v.grass = grassAmt
        v.unit = S
        let count = cols * rows
        v.gR.ensure(count); v.gG.ensure(count); v.gB.ensure(count); v.packed.ensure(count)
        gR = v.gR.p; gG = v.gG.p; gB = v.gB.p
        let packed = v.packed.p
        v.tuftCells.removeAll(keepingCapacity: true)
        v.tuftGlyph.removeAll(keepingCapacity: true)
        v.tuftK.removeAll(keepingCapacity: true)
        v.tuftM.removeAll(keepingCapacity: true)
        v.tuftH.removeAll(keepingCapacity: true)
        v.airRows = -1
        v.releaseFlowers()
        let bgc: MeadowRGB = LIGHT ? PlantInk.paper : MeadowRGB(0, 0, 0)
        let gc: MeadowRGB = LIGHT ? PlantInk.groundPaper : PlantInk.ground
        let pr: MeadowRGB = LIGHT ? PlantInk.paper : MeadowRGB(0, 0, 0)
        for r in 0..<rows {
            for c in 0..<cols {
                let i = r * cols + c
                let gcx = Double(c) + gc0, gry = Double(r) + gr0
                let x: Double = (ox + Double(c) * cw) / S, y: Double = (oy + Double(r) * ch) / S
                let n1: Double = 0.6 * MeadowMath.vnoise(x / 260, y / 230, 21)
                let n2: Double = 0.4 * MeadowMath.vnoise(x / 90, y / 80, 22)
                let patch = MeadowMath.smooth(0.42, 0.82, n1 + n2)
                let k: Double = clamp(patch * green * 1.15, 0, 2)
                let gr: Double = clamp(bgc.x + (gc.x - bgc.x) * k, 0, 255)
                let gg: Double = clamp(bgc.y + (gc.y - bgc.y) * k, 0, 255)
                let gb: Double = clamp(bgc.z + (gc.z - bgc.z) * k, 0, 255)
                gR[i] = Float(gr); gG[i] = Float(gg); gB[i] = Float(gb)
                packed[i] = packRound(gr, gg, gb, pr)
                let dens: Double = (0.09 + 0.22 * patch + 0.08 * MeadowMath.vnoise(x / 40, y / 40, 23)) * grassAmt
                let h = mhash(gcx, gry, 11)
                if h < dens {
                    let gi = MG.tufts[Int(mhash(gcx, gry, 5) * Double(MG.tufts.count))]
                    v.tuftCells.append(Int32(i))
                    v.tuftGlyph.append(gi)
                    v.tuftK.append(Float((0.45 + 0.55 * mhash(gcx, gry, 7)) * (0.55 + 0.45 * patch)))
                    v.tuftM.append(Float(mhash(gcx, gry, 17)))
                    v.tuftH.append(Float(mhash(gcx, gry, 13)))
                }
            }
        }
    }

    /// The air on the breeze's grid, once a frame for every screen (the sketch calls `windAt` for every grass cell).
    func readAir() {
        let b = world.breeze
        let count = b.columns * b.rows
        let p = painter
        guard p.airSteps != b.steps || p.airTime != b.time || p.airCount != count else { return }
        p.airSteps = b.steps
        p.airTime = b.time
        p.airCount = count
        p.airX.ensure(count)
        p.airY.ensure(count)
        let ax = p.airX.p, ay = p.airY.p
        let o = b.origin
        let dx = b.directionX, dy = b.directionY, base = b.base
        let gust = GustReader(b, columns: b.columns, rows: b.rows, painter: p)
        for r in 0..<b.rows {
            for c in 0..<b.columns {
                let x: Double = o.x + Double(c) * b.spacing, y: Double = o.y + Double(r) * b.spacing
                let g = gust.at(x, y)
                let m: Double = base * (MeadowTuning.Wind.lull + MeadowTuning.Wind.gustGain * g)
                let ps = b.stirSample(c, r), w = b.washSample(c, r)
                let i = r * b.columns + c
                ax[i] = Float(dx * m + ps.x + w.x)
                ay[i] = Float(dy * m + ps.y + w.y)
            }
        }
    }

    /// `drawGround` (html:2545–2571): the grass marks that ripple and lie over in the gusts, then the motes.
    mutating func drawGround() {
        let b = world.breeze
        let grassAmt = min(1.4, tuning.grass)
        farPush(tuning.depth)
        let ref: Double = max(1, 26 * S * max(0.3, tuning.breeze))
        let gr = PlantInk.grass, st = PlantInk.stirred
        let pg = PlantInk.paperGrass, pz = PlantInk.paperGrassStirred
        let cells = v.tuftCells, glyphs = v.tuftGlyph, ks = v.tuftK, ms = v.tuftM, hs = v.tuftH
        let airN = painter.airCount
        let airX = painter.airX.p, airY = painter.airY.p
        let o = b.origin, spacing = b.spacing, bc = b.columns, brows = b.rows
        let gxMax: Double = max(0, Double(bc) - 1.001), gyMax: Double = max(0, Double(brows) - 1.001)
        // The ink at each of 65 steps of the air's pull `s` (html:2559–2567): the stirred colour by `0.85 s`, pushed
        // back with the meadow (`far`); a glyph with no block under it is fainter (`FAR_FAINT`), and on black the
        // silk's alpha (lGlyph) is its own, on paper 0.75 of it.
        let ink = painter.grassInk.p
        for q in 0...64 {
            let kk: Double = Double(q) / 64 * 0.85
            var r: Double, g: Double, bl: Double
            if LIGHT {
                r = pg.x + (pz.x - pg.x) * kk; g = pg.y + (pz.y - pg.y) * kk; bl = pg.z + (pz.z - pg.z) * kk
            } else {
                r = gr.x + (st.x - gr.x) * kk; g = gr.y + (st.y - gr.y) * kk; bl = gr.z + (st.z - gr.z) * kk
            }
            if FAR != 0 { far(&r, &g, &bl) }
            ink[q] = SIMD3(Float(r), Float(g), Float(bl))
        }
        let alphaK: Double = (LIGHT ? 0.75 : 1) * grassAmt * (FAR != 0 ? FAR_FAINT : 1) * INK_K
        // Where each tuft reads the air (fixed while the tufts and the grid stay).
        let key = SIMD4<Double>(o.x, o.y, spacing, Double(bc))
        if airN > 0 && (v.airRows != brows || v.airKey != key) {
            v.airKey = key
            v.airRows = brows
            v.tuftAir.removeAll(keepingCapacity: true)
            v.tuftW.removeAll(keepingCapacity: true)
            for k in 0..<cells.count {
                let i = Int(cells[k])
                let c = i % cols, r = i / cols
                let x: Double = ox + (Double(c) + 0.5) * cw, y: Double = oy + (Double(r) + 0.5) * ch
                let gx: Double = clamp((x - o.x) / spacing, 0, gxMax)
                let gy: Double = clamp((y - o.y) / spacing, 0, gyMax)
                let ix = Int(gx), iy = Int(gy)
                let fx = Float(gx - Double(ix)), fy = Float(gy - Double(iy))
                let j = iy * bc + ix
                let j1 = ix + 1 < bc ? j + 1 : j
                let j2 = iy + 1 < brows ? j + bc : j
                let j3 = ix + 1 < bc ? j2 + 1 : j2
                v.tuftAir.append(SIMD4(Int32(j), Int32(j1), Int32(j2), Int32(j3)))
                v.tuftW.append(SIMD2(fx, fy))
            }
        }
        let tuftAir = v.tuftAir, tuftW = v.tuftW
        for k in 0..<cells.count {
            let i = Int(cells[k])
            var wx = 0.0, wy = 0.0
            if airN > 0 {
                let js = tuftAir[k], w = tuftW[k]
                let fx = w.x, fy = w.y
                let j = Int(js.x), j1 = Int(js.y), j2 = Int(js.z), j3 = Int(js.w)
                let axv: Float = (airX[j] * (1 - fx) + airX[j1] * fx) * (1 - fy) + (airX[j2] * (1 - fx) + airX[j3] * fx) * fy
                let ayv: Float = (airY[j] * (1 - fx) + airY[j1] * fx) * (1 - fy) + (airY[j2] * (1 - fx) + airY[j3] * fx) * fy
                wx = Double(axv); wy = Double(ayv)
            }
            let m = (wx * wx + wy * wy).squareRoot()
            let s: Double = clamp((m / ref - 0.35) / 1.3, 0, 1)
            var g = glyphs[k]
            if s > 0.45 && Double(hs[k]) < 0.25 + 0.6 * s { g = meadowLine(wx, wy, Double(ms[k])) }
            // lGlyph (or the paper's glyph) with the meadow pushed back: the ink from this frame's table.
            let col = ink[Int(s * 64 + 0.5)]
            touch(i)
            GI[i] = g
            IR[i] = col.x; IG[i] = col.y; IB[i] = col.z
            IA[i] = Float(Double(ks[k]) * (0.42 + 0.58 * s) * alphaK)
        }
        farPush(0)
        drawMotes()
    }

    /// `drawMotes` (html:2576–2592): gold motes where the pointer stirs the air over 60 pt/s.
    mutating func drawMotes() {
        let b = world.breeze
        var any = false
        let lim2: Double = 3600
        outer: for r in 0..<b.rows {
            for c in 0..<b.columns {
                let p = b.stirSample(c, r)
                if p.x * p.x + p.y * p.y > lim2 { any = true; break outer }
            }
        }
        if !any { return }
        let g = LIGHT ? PlantInk.goldPaper : PlantInk.gold
        let tick = floor(simT * 2.4)
        let accent: Double = calm ? 0.35 : 1
        let o = b.origin
        for r in 0..<rows {
            for c in 0..<cols {
                let i = r * cols + c
                if stamp[i] == frame && GI[i] != MG.none { continue }
                let x: Double = ox + (Double(c) + 0.5) * cw, y: Double = oy + (Double(r) + 0.5) * ch
                let gx: Double = clamp((x - o.x) / b.spacing, 0, max(0, Double(b.columns) - 1.001))
                let gy: Double = clamp((y - o.y) / b.spacing, 0, max(0, Double(b.rows) - 1.001))
                let ix = Int(gx), iy = Int(gy)
                let fx: Double = gx - Double(ix), fy: Double = gy - Double(iy)
                let p00 = b.stirSample(ix, iy), p10 = b.stirSample(min(ix + 1, b.columns - 1), iy)
                let p01 = b.stirSample(ix, min(iy + 1, b.rows - 1)), p11 = b.stirSample(min(ix + 1, b.columns - 1), min(iy + 1, b.rows - 1))
                let top = p00 * (1 - fx) + p10 * fx
                let bot = p01 * (1 - fx) + p11 * fx
                let p = top * (1 - fy) + bot * fy
                let m = (p.x * p.x + p.y * p.y).squareRoot()
                if m < 60 * S { continue }
                let k = MeadowMath.smooth(60 * S, 180 * S, m)
                let gcx = Double(c) + gc0, gry = Double(r) + gr0
                let phase = floor(mhash(gcx, gry, 3) * 3)
                if mhash(gcx, gry, tick + phase) > 0.12 + 0.2 * k { continue }
                putGlyph(i, MG.mid, g.x, g.y, g.z, (0.2 + 0.15 * k) * accent)
            }
        }
    }

    /// `drawDust` (html:2508–2516).
    mutating func drawDust() {
        let g = LIGHT ? PlantInk.goldPaper : PlantInk.gold
        let accent: Double = calm ? 0.35 : 1
        let tick = floor(simT * 6)
        for d in world.dust {
            let c = Int(floor((d.x - ox) / cw)), r = Int(floor((d.y - oy) / ch))
            if c < 0 || r < 0 || c >= cols || r >= rows { continue }
            let a: Double = clamp(d.life / d.max, 0, 1)
            let tw: UInt8 = d.spark ? (mhash(Double(c) + gc0, Double(r) + gr0, tick) < 0.5 ? MG.plus : MG.mid) : (a > 0.5 ? MG.mid : MG.dot)
            putGlyph(r * cols + c, tw, g.x, g.y, g.z, (d.spark ? 1 : 0.8) * a * accent)
        }
    }

    // ── the blit (html:2620–2675) ──

    @inline(__always) private func packRound(_ r: Double, _ g: Double, _ b: Double, _ pr: MeadowRGB) -> UInt32 {
        var r = r, g = g, b = b
        if bright != 1 { r = pr.x + (r - pr.x) * bright; g = pr.y + (g - pr.y) * bright; b = pr.z + (b - pr.z) * bright }
        @inline(__always) func u8(_ v: Double) -> UInt32 { UInt32(max(0, min(255, v)).rounded()) }
        return u8(r) | u8(g) << 8 | u8(b) << 16 | 255 << 24
    }

    @inline(__always) private func packTrunc(_ r: Float, _ g: Float, _ b: Float, _ a: Float, _ pr: SIMD3<Float>, _ br: Float) -> UInt32 {
        var r = r, g = g, b = b
        if br != 1 { r = pr.x + (r - pr.x) * br; g = pr.y + (g - pr.y) * br; b = pr.z + (b - pr.z) * br }
        @inline(__always) func u8(_ v: Float) -> UInt32 { UInt32(max(0, min(255, v))) }
        let al = UInt32(max(0, min(1, a)) * 255 + 0.5)
        return u8(r) | u8(g) << 8 | u8(b) << 16 | al << 24
    }

    func blit(_ canvas: CellCanvas) {
        let count = cols * rows
        let pr: SIMD3<Float> = LIGHT ? SIMD3(247, 246, 243) : .zero
        let br = Float(bright)
        canvas.withGround { ground in
            ground.baseAddress!.update(from: v.packed.p, count: count)
            canvas.block.withUnsafeMutableBufferPointer { block in
                canvas.ink.withUnsafeMutableBufferPointer { ink in
                    canvas.glyph.withUnsafeMutableBufferPointer { glyph in
                        for k in 0..<touchedN {
                            let i = Int(touched[k])
                            let hb = HB[i]
                            if hb == 1 {
                                block[i] = packTrunc(BR[i], BG[i], BB[i], 1, pr, br)
                            } else if hb == 2 {
                                // The ground here was shaded (or rimmed): its own colour; elsewhere the cached one.
                                ground[i] = packTrunc(BR[i], BG[i], BB[i], 1, pr, br)
                            }
                            let gi = GI[i]
                            if gi != MG.none && IA[i] > 0.02 {
                                glyph[i] = gi
                                ink[i] = packTrunc(IR[i], IG[i], IB[i], IA[i], pr, br)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// `Breeze.gust` over the breeze's grid, the same numbers with fewer hashes: `vnoise` hashes the four whole-number
/// corners round each point, and the grid's points share a few hundred corners a frame (the gust bands are 300 and 520
/// pt, the grid 48), so each octave's corners are hashed once into a table and read from it. Every sum is the one
/// `gust` and `vnoise` make, in the same order; a corner outside the table is hashed as `vnoise` hashes it.
struct GustReader {
    /// One octave's table: `hash3(x0 + i, y0 + j, s)` at `p[j * w + i]`; `w == 0` when there is none.
    struct Lattice {
        var p: UnsafeMutablePointer<Double>
        var x0 = 0, y0 = 0, w = 0, h = 0
        let s: Double

        /// The corners `noise` can meet for a, b in lo…hi (one corner of slack each way, for rounding).
        init(_ buf: inout MBuf<Double>, s: Double, loA: Double, hiA: Double, loB: Double, hiB: Double) {
            self.s = s
            p = buf.p
            let most: Double = 65536
            guard loA.isFinite && hiA.isFinite && loB.isFinite && hiB.isFinite, abs(loA) < 1e9 && abs(hiA) < 1e9 && abs(loB) < 1e9 && abs(hiB) < 1e9
            else { return }
            let fa: Double = floor(loA) - 1, ta: Double = floor(hiA) + 2
            let fb: Double = floor(loB) - 1, tb: Double = floor(hiB) + 2
            let cw: Double = ta - fa + 1, chh: Double = tb - fb + 1
            guard cw * chh <= most else { return }
            x0 = Int(fa); y0 = Int(fb); w = Int(cw); h = Int(chh)
            buf.ensure(w * h)
            p = buf.p
            for j in 0..<h {
                for i in 0..<w { p[j * w + i] = MeadowMath.hash3(Double(x0 + i), Double(y0 + j), s) }
            }
        }

        /// `MeadowMath.vnoise(x, y, s)`.
        @inline(__always) func noise(_ x: Double, _ y: Double) -> Double {
            let xi = floor(x), yi = floor(y)
            var xf: Double = x - xi
            var yf: Double = y - yi
            xf = xf * xf * (3 - 2 * xf)
            yf = yf * yf * (3 - 2 * yf)
            let a: Double, b: Double, c: Double, d: Double
            if xi >= Double(x0) && xi < Double(x0 + w - 1) && yi >= Double(y0) && yi < Double(y0 + h - 1) {
                let k = (Int(yi) - y0) * w + (Int(xi) - x0)
                a = p[k]; b = p[k + 1]; c = p[k + w]; d = p[k + w + 1]
            } else {
                a = MeadowMath.hash3(xi, yi, s)
                b = MeadowMath.hash3(xi + 1, yi, s)
                c = MeadowMath.hash3(xi, yi + 1, s)
                d = MeadowMath.hash3(xi + 1, yi + 1, s)
            }
            let ab: Double = (b - a) * xf
            let ac: Double = (c - a) * yf
            let abcd: Double = (a - b - c + d) * xf * yf
            return a + ab + ac + abcd
        }
    }

    let dirX: Double, dirY: Double, unit: Double, time: Double
    let one: Lattice, two: Lattice

    /// For the grid of `breeze` (`columns` x `rows` samples from its origin at its spacing), this step.
    init(_ breeze: Breeze, columns: Int, rows: Int, painter: MeadowPainter) {
        typealias W = MeadowTuning.Wind
        dirX = breeze.directionX
        dirY = breeze.directionY
        unit = breeze.unit
        time = breeze.time
        // a and b are linear in the point, so the grid's corners bound them.
        var loA = Double.infinity, hiA = -Double.infinity, loB = Double.infinity, hiB = -Double.infinity
        let o = breeze.origin
        let lim = MeadowTuning.Unit.coordinateLimit
        let lastC = max(0, columns - 1), lastR = max(0, rows - 1)
        for k in 0..<4 {
            let c = k & 1 == 0 ? 0 : lastC, r = k < 2 ? 0 : lastR
            let x: Double = o.x + Double(c) * breeze.spacing, y: Double = o.y + Double(r) * breeze.spacing
            let px: Double = clamp(x, -lim, lim), py: Double = clamp(y, -lim, lim)
            let along: Double = (px * dirX + py * dirY) / (W.bandAlong * unit)
            let a: Double = along - time * W.bandRoll
            let b: Double = (-px * dirY + py * dirX) / (W.bandAcross * unit)
            loA = min(loA, a); hiA = max(hiA, a); loB = min(loB, b); hiB = max(hiB, b)
        }
        one = Lattice(&painter.lattice1, s: W.octave1Noise, loA: loA, hiA: hiA, loB: loB, hiB: hiB)
        let loA2: Double = loA * W.octave2Along + W.octave2Shift, hiA2: Double = hiA * W.octave2Along + W.octave2Shift
        let loB2: Double = min(loB * W.octave2Across, hiB * W.octave2Across), hiB2: Double = max(loB * W.octave2Across, hiB * W.octave2Across)
        two = Lattice(&painter.lattice2, s: W.octave2Noise, loA: loA2, hiA: hiA2, loB: loB2, hiB: hiB2)
    }

    /// `Breeze.gust(x, y)`.
    @inline(__always) func at(_ x: Double, _ y: Double) -> Double {
        guard x.isFinite && y.isFinite else { return 0 }
        typealias W = MeadowTuning.Wind
        let lim = MeadowTuning.Unit.coordinateLimit
        let px: Double = clamp(x, -lim, lim)
        let py: Double = clamp(y, -lim, lim)
        let along: Double = (px * dirX + py * dirY) / (W.bandAlong * unit)
        let a: Double = along - time * W.bandRoll
        let b: Double = (-px * dirY + py * dirX) / (W.bandAcross * unit)
        let o1: Double = W.octave1 * one.noise(a, b)
        let o2: Double = W.octave2 * two.noise(a * W.octave2Along + W.octave2Shift, b * W.octave2Across)
        let g: Double = MeadowMath.smooth(W.gustFrom, W.gustTo, o1 + o2)
        return g.isFinite ? g : 0
    }
}
