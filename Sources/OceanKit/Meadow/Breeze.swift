import CoreGraphics
import Foundation

/// The air at one point, in pt/s (ocean space, y down): the sketch's three sums (html:719–720).
public struct MeadowAir: Equatable, Sendable {
    /// All the air: what grass, flowers, pollen and a flying butterfly's drift feel (`wind.x/y`).
    public var x = 0.0
    public var y = 0.0
    /// The air a landed butterfly feels: the breeze and the pointer's stir, not other wings' downwash
    /// (`wind.ax/ay`).
    public var landedX = 0.0
    public var landedY = 0.0
    /// The pointer's stir alone (`wind.px/py`).
    public var pointerX = 0.0
    public var pointerY = 0.0
    /// The gust at the point, 0…1 (`wind.g`).
    public var gust = 0.0
    /// The speed of all the air, |(x, y)| (`wind.m`).
    public var speed = 0.0

    public init() {}
}

/// The meadow's air, ported from the sketch's breeze (html:713–764, 1625–1633, 1987–1996): a slowly
/// turning wind with gust bands that roll downwind, plus two fields on a coarse grid, the air the pointer stirs and
/// the wings' downwash, both decaying with a half-life of about 0.43 s.
///
/// Stepped at the family's fixed tick only (`OceanClock.step`, 1/60 s); any other step length is refused. Nothing
/// allocates per step once laid out.
///
/// **The pointer**, as Web's world takes it: the host calls `pointerMoved(x:y:)` with the pointer's position (ocean
/// space) as it moves over the meadow, and `pointerLeft()` when it leaves. Only the latest position counts. Each step
/// stirs along the segment from where the pointer was at the last step to where it is now (the sketch's `stirStep`,
/// html:1987–1996). A move that arrives while the pointer is off the meadow starts a new way there, so nothing is
/// stirred along the jump. The sketch's paused moves stir nothing (html:2691); the host gets the same by calling
/// `pointerLeft()` when it pauses.
///
/// One rule is the port's own: the way the pointer went between the last step and leaving is still stirred, by the
/// next step (the sketch drops it: its `stirStep` returns once the pointer has gone).
public final class Breeze {
    /// The director's settings (the breeze and downwash sliders are read). Put right on every write (finite and
    /// inside each slider's range).
    public var tuning: MeadowTuning {
        didSet { tuning = tuning.sanitized() }
    }
    /// Seconds of simulation stepped (the sketch's `simT`).
    public private(set) var time = 0.0
    /// Steps taken.
    public private(set) var steps = 0
    /// The wind's direction (unit) and base speed this step (`wind.cx/cy`, `wind.base`).
    public private(set) var directionX = 1.0
    public private(set) var directionY = 0.0
    public private(set) var base = 0.0
    /// `S`: sketch points per point (cell width / 13, the width held to `MeadowTuning.Unit.cellRange`).
    public private(set) var unit = 1.0

    // The grid: `PG`, its origin (the terrain's top-left) and size; the two fields, stored as Float as the sketch's
    // Float32Arrays are, so a replay rounds the same way.
    public private(set) var spacing = 48.0
    private var originX = 0.0, originY = 0.0
    /// Where grid sample (0, 0) lies (the terrain's top-left), pt: for the painter, which reads the fields per sample.
    public var origin: SIMD2<Double> { SIMD2(originX, originY) }
    public private(set) var columns = 0
    public private(set) var rows = 0
    private var pfx: [Float] = [], pfy: [Float] = []
    private var dwx: [Float] = [], dwy: [Float] = []

    // The pointer (the sketch's `ptr`, as the air sees it): `has`, `x/y` (the latest position) and `sx/sy` (where
    // the air was last stirred to).
    /// The pointer is over the meadow.
    public private(set) var pointerActive = false
    private var pointerX = 0.0, pointerY = 0.0
    private var stirredX = 0.0, stirredY = 0.0
    // The way from the last step's position to where the pointer left, if it moved in between: stirred by the next
    // step. `lastReal` is the last step's real length, for the one case a way is stirred outside a step.
    private var leftWay = false
    private var leftFromX = 0.0, leftFromY = 0.0, leftToX = 0.0, leftToY = 0.0
    private var lastReal = OceanClock.step

    public init(terrain: Terrain, cell: CGSize, tuning: MeadowTuning = .director) {
        self.tuning = tuning.sanitized()
        layout(terrain: terrain, cell: cell)
    }

    /// The grid laid over the terrain's bounds at this cell size (the sketch's `pfInit`, on every resize): both
    /// fields start still. A broken size gives a one-sample grid; a huge one widens the spacing (never more than
    /// `Stir.maxSamples` samples). The cell width is held to `Unit.cellRange` (13 when it isn't a number).
    public func layout(terrain: Terrain, cell: CGSize) {
        unit = MeadowTuning.Unit.cellWidth(Double(cell.width)) / MeadowTuning.Unit.referenceCell
        let b = terrain.bounds
        let bx = Double(b.minX), by = Double(b.minY), bw = Double(b.width), bh = Double(b.height)
        originX = bx.isFinite ? bx : 0
        originY = by.isFinite ? by : 0
        let W = bw.isFinite ? max(0, bw) : 0
        let H = bh.isFinite ? max(0, bh) : 0
        var pg: Double = MeadowTuning.Stir.grid * unit
        // pgc = ceil(W / PG) + 1, pgr = ceil(H / PG) + 1 (html:723), widened past the cap.
        func cells(_ pg: Double) -> (Int, Int) {
            let c: Double = min(1e9, ceil(W / pg) + 1)
            let r: Double = min(1e9, ceil(H / pg) + 1)
            return (Int(c), Int(r))
        }
        var (c, r) = cells(pg)
        while c * r > MeadowTuning.Stir.maxSamples {
            pg = pg > 0 && pg.isFinite ? pg * 2 : 1   // never stuck: a spacing of 0 (a unit gone to 0) starts at 1
            (c, r) = cells(pg)
        }
        spacing = pg
        columns = c
        rows = r
        let n = c * r
        pfx = [Float](repeating: 0, count: n)
        pfy = pfx
        dwx = pfx
        dwy = pfx
        leftWay = false
    }

    // ── the pointer ──

    /// The pointer is at (x, y) over the meadow (the sketch's `pointermove`, html:2685–2691, as the air sees it). Only
    /// recorded: the next step stirs the way from where it was at the last step. Coming onto the meadow (the first
    /// move, or the first after `pointerLeft`) starts the way there. A point that isn't finite is ignored; a huge one
    /// is held to ±`Unit.coordinateLimit`.
    public func pointerMoved(x: Double, y: Double) {
        guard x.isFinite && y.isFinite else { return }
        let lim = MeadowTuning.Unit.coordinateLimit
        let px: Double = clamp(x, -lim, lim)
        let py: Double = clamp(y, -lim, lim)
        if !pointerActive {
            stirredX = px
            stirredY = py
        }
        pointerX = px
        pointerY = py
        pointerActive = true
    }

    /// The pointer left the meadow (the sketch's `pointerGone`, html:1939): it stirs nothing until it comes back. The
    /// way it went since the last step is stirred by the next step. If an earlier such way is still waiting (it left,
    /// came back and left again within one step), that one is stirred now, as the last step would have.
    public func pointerLeft() {
        guard pointerActive else { return }
        pointerActive = false
        guard pointerX != stirredX || pointerY != stirredY else { return }
        if leftWay {
            stirWay(fromX: leftFromX, fromY: leftFromY, toX: leftToX, toY: leftToY, dt: OceanClock.step, real: lastReal)
        }
        leftWay = true
        leftFromX = stirredX
        leftFromY = stirredY
        leftToX = pointerX
        leftToY = pointerY
        stirredX = pointerX
        stirredY = pointerY
    }

    // ── stepping ──

    /// One step of exactly `OceanClock.step` (any other length is refused): the wind turns and the fields decay
    /// (`updateWind`), then the pointer stirs along its way (`stirStep`). `speed` is the app's speed setting (the
    /// sketch's Slow motion, held to `Unit.paceRange`): a step is `OceanClock.step / speed` of the pointer's real time.
    public func step(_ dt: Double = OceanClock.step, speed: Double = 1) {
        guard dt == OceanClock.step else { return }
        let pace: Double = MeadowTuning.Unit.pace(speed)
        time += dt
        steps += 1
        updateWind(dt)
        stirStep(dt, real: dt / pace)
    }

    private func updateWind(_ dt: Double) {
        typealias W = MeadowTuning.Wind
        let t = time
        let dir: Double = W.directionMean + W.directionSwing * MeadowMath.n1(t * W.directionRate, W.directionNoise)
        directionX = cos(dir)
        directionY = sin(dir)
        let swing: Double = W.baseMean + W.baseSwing * MeadowMath.n1(t * W.baseRate, W.baseNoise)
        base = W.baseSpeed * unit * tuning.breeze * swing
        let k: Double = exp(-MeadowTuning.Stir.decay * dt)
        // The same decay, element by element, through buffer pointers (one access per field per step, not per sample).
        Breeze.decay(&pfx, k)
        Breeze.decay(&pfy, k)
        Breeze.decay(&dwx, k)
        Breeze.decay(&dwy, k)
    }

    private static func decay(_ a: inout [Float], _ k: Double) {
        a.withUnsafeMutableBufferPointer { p in
            for i in 0..<p.count { p[i] = Float(Double(p[i]) * k) }
        }
    }

    /// The sketch's `stirStep` (html:1987–1996): the way from where the pointer was at the last step to where it is
    /// now, after the way it went before it left, if that is waiting.
    private func stirStep(_ dt: Double, real: Double) {
        lastReal = real
        if leftWay {
            leftWay = false
            stirWay(fromX: leftFromX, fromY: leftFromY, toX: leftToX, toY: leftToY, dt: dt, real: real)
        }
        guard pointerActive else { return }
        stirWay(fromX: stirredX, fromY: stirredY, toX: pointerX, toY: pointerY, dt: dt, real: real)
        stirredX = pointerX
        stirredY = pointerY
    }

    /// The sketch's stroke along one way (html:1989–1995): at the speed the pointer went (each axis held to ±1500
    /// pt/s), an impulse of 60 · dt × that speed, split into one stir per grid spacing of the way (at most
    /// `Stir.maxStirs`), ending at the way's end.
    private func stirWay(fromX: Double, fromY: Double, toX: Double, toY: Double, dt: Double, real: Double) {
        let dx: Double = toX - fromX
        let dy: Double = toY - fromY
        if dx == 0 && dy == 0 { return }
        typealias St = MeadowTuning.Stir
        let k: Double = St.impulseRate * dt
        let vx: Double = clamp(dx / real, -St.speedLimit, St.speedLimit) * k
        let vy: Double = clamp(dy / real, -St.speedLimit, St.speedLimit) * k
        let way: Double = (dx * dx + dy * dy).squareRoot() / spacing
        let n = Int(max(1, min(St.maxStirs, ceil(way))))
        let nd = Double(n)
        for i in 1...n {
            let back: Double = Double(n - i) / nd
            stir(toX - dx * back, toY - dy * back, vx / nd, vy / nd)
        }
    }

    /// A grid index held to −1…count (the loops skip the samples outside), safe for any finite value.
    @inline(__always) private static func index(_ v: Double, _ count: Int) -> Int {
        Int(min(Double(count), max(-1, v)))
    }

    /// `stir(x, y, vx, vy)` (html:755–764): adds the pointer's push within 3 grid cells, weight `(1 − d)² · 0.16`,
    /// each sample clamped to ±260 pt/s.
    public func stir(_ x: Double, _ y: Double, _ vx: Double, _ vy: Double) {
        guard x.isFinite && y.isFinite && vx.isFinite && vy.isFinite, !pfx.isEmpty else { return }
        typealias St = MeadowTuning.Stir
        let rad = St.radius
        let cx: Double = (x - originX) / spacing
        let cy: Double = (y - originY) / spacing
        let r0 = Breeze.index(floor(cy - rad), rows), r1 = Breeze.index(ceil(cy + rad), rows)
        let c0 = Breeze.index(floor(cx - rad), columns), c1 = Breeze.index(ceil(cx + rad), columns)
        guard r0 <= r1 && c0 <= c1 else { return }
        for r in r0...r1 {
            for c in c0...c1 {
                if c < 0 || r < 0 || c >= columns || r >= rows { continue }
                let ox: Double = Double(c) - cx
                let oy: Double = Double(r) - cy
                let d: Double = (ox * ox + oy * oy).squareRoot() / rad
                if d >= 1 { continue }
                let w: Double = (1 - d) * (1 - d) * St.gain
                let i = r * columns + c
                pfx[i] = Float(clamp(Double(pfx[i]) + vx * w, -St.limit, St.limit))
                pfy[i] = Float(clamp(Double(pfy[i]) + vy * w, -St.limit, St.limit))
            }
        }
    }

    /// `wash(x, y, v, rad)` (html:1625–1633): pushes the air out from (x, y), `v` at the centre falling to 0 at
    /// `rad` pt, each sample clamped to ±200 pt/s.
    public func wash(_ x: Double, _ y: Double, _ v: Double, _ radius: Double) {
        guard x.isFinite && y.isFinite && v.isFinite && radius.isFinite && radius > 0, !dwx.isEmpty else { return }
        let lim = MeadowTuning.Stir.washLimit
        let cx: Double = (x - originX) / spacing
        let cy: Double = (y - originY) / spacing
        let rr: Double = min(radius / spacing, MeadowTuning.Stir.washReach)
        let r0 = Breeze.index(floor(cy - rr), rows), r1 = Breeze.index(ceil(cy + rr), rows)
        let c0 = Breeze.index(floor(cx - rr), columns), c1 = Breeze.index(ceil(cx + rr), columns)
        guard r0 <= r1 && c0 <= c1 else { return }
        for r in r0...r1 {
            for c in c0...c1 {
                if c < 0 || r < 0 || c >= columns || r >= rows { continue }
                let ox: Double = Double(c) - cx
                let oy: Double = Double(r) - cy
                let d: Double = (ox * ox + oy * oy).squareRoot()
                if d >= rr || d < 1e-3 { continue }
                let w: Double = 1 - d / rr
                let i = r * columns + c
                dwx[i] = Float(clamp(Double(dwx[i]) + ox / d * v * w, -lim, lim))
                dwy[i] = Float(clamp(Double(dwy[i]) + oy / d * v * w, -lim, lim))
            }
        }
    }

    /// A flying butterfly's downstroke (html:1770): at height z under 0.35, while the stroke's `sinθ` is positive,
    /// it washes `520 · S · downwash · (1 − z / 0.35) · sinθ · dt` out within 1.2 of its span (`spanRef`, pt).
    /// Nothing at z ≥ 0.35 or on the upstroke. `dt` is the tick (`OceanClock.step`); any other is refused.
    public func downstroke(x: Double, y: Double, z: Double, sinStroke s: Double, span: Double,
                           dt: Double = OceanClock.step) {
        typealias St = MeadowTuning.Stir
        guard dt == OceanClock.step, z.isFinite && s.isFinite && s > 0 && z < St.washBelow && tuning.downwash > 0
        else { return }
        let v: Double = St.washFlight * unit * tuning.downwash * (1 - max(0, z) / St.washBelow) * s * dt
        wash(x, y, v, St.washFlightRadius * span)
    }

    /// A swallowtail fluttering on a flower (html:1900): `300 · S · downwash · sinθ · dt` within one span. `dt` is
    /// the tick; any other is refused.
    public func flutter(x: Double, y: Double, sinStroke s: Double, span: Double, dt: Double = OceanClock.step) {
        typealias St = MeadowTuning.Stir
        guard dt == OceanClock.step, s.isFinite && s > 0 && tuning.downwash > 0 else { return }
        wash(x, y, St.washFlutter * unit * tuning.downwash * s * dt, St.washFlutterRadius * span)
    }

    // ── sampling ──

    /// `gustAt(x, y, t)` (html:732–737): the gust at a point now, 0…1. Coordinates are held to
    /// ±`Unit.coordinateLimit` so the band arithmetic can't overflow; 0 if it still isn't a number.
    public func gust(_ x: Double, _ y: Double) -> Double {
        guard x.isFinite && y.isFinite else { return 0 }
        typealias W = MeadowTuning.Wind
        let lim = MeadowTuning.Unit.coordinateLimit
        let px: Double = clamp(x, -lim, lim)
        let py: Double = clamp(y, -lim, lim)
        let along: Double = (px * directionX + py * directionY) / (W.bandAlong * unit)
        let a: Double = along - time * W.bandRoll
        let b: Double = (-px * directionY + py * directionX) / (W.bandAcross * unit)
        let o1: Double = W.octave1 * MeadowMath.vnoise(a, b, W.octave1Noise)
        let o2: Double = W.octave2 * MeadowMath.vnoise(a * W.octave2Along + W.octave2Shift, b * W.octave2Across, W.octave2Noise)
        let g: Double = MeadowMath.smooth(W.gustFrom, W.gustTo, o1 + o2)
        return g.isFinite ? g : 0
    }

    /// `windAt(x, y, t)` (html:739–753): the air at a point now. Still air at a non-finite point, and wherever the
    /// sum isn't a number.
    public func sample(_ x: Double, _ y: Double) -> MeadowAir {
        var out = MeadowAir()
        guard x.isFinite && y.isFinite else { return out }
        typealias W = MeadowTuning.Wind
        let g = gust(x, y)
        let m: Double = base * (W.lull + W.gustGain * g)
        var px = 0.0, py = 0.0, dx = 0.0, dy = 0.0
        if !pfx.isEmpty {
            let gx: Double = clamp((x - originX) / spacing, 0, max(0, Double(columns) - 1.001))
            let gy: Double = clamp((y - originY) / spacing, 0, max(0, Double(rows) - 1.001))
            let ix = Int(gx), iy = Int(gy)
            let fx: Double = gx - Double(ix)
            let fy: Double = gy - Double(iy)
            let i = iy * columns + ix
            let i1 = ix + 1 < columns ? i + 1 : i
            let i2 = iy + 1 < rows ? i + columns : i
            let i3 = ix + 1 < columns ? i2 + 1 : i2
            let a: Double = (1 - fx) * (1 - fy)
            let b: Double = fx * (1 - fy)
            let c: Double = (1 - fx) * fy
            let d: Double = fx * fy
            px = Double(pfx[i]) * a + Double(pfx[i1]) * b + Double(pfx[i2]) * c + Double(pfx[i3]) * d
            py = Double(pfy[i]) * a + Double(pfy[i1]) * b + Double(pfy[i2]) * c + Double(pfy[i3]) * d
            dx = Double(dwx[i]) * a + Double(dwx[i1]) * b + Double(dwx[i2]) * c + Double(dwx[i3]) * d
            dy = Double(dwy[i]) * a + Double(dwy[i1]) * b + Double(dwy[i2]) * c + Double(dwy[i3]) * d
        }
        out.pointerX = px
        out.pointerY = py
        out.landedX = directionX * m + px
        out.landedY = directionY * m + py
        out.x = out.landedX + dx
        out.y = out.landedY + dy
        out.gust = g
        out.speed = (out.x * out.x + out.y * out.y).squareRoot()
        guard out.x.isFinite && out.y.isFinite && out.speed.isFinite else { return MeadowAir() }
        return out
    }

    // ── for checks and pictures ──

    /// The pointer-stir field at grid sample (c, r), pt/s.
    public func stirSample(_ c: Int, _ r: Int) -> SIMD2<Double> {
        guard c >= 0 && r >= 0 && c < columns && r < rows else { return SIMD2(0, 0) }
        let i = r * columns + c
        return SIMD2(Double(pfx[i]), Double(pfy[i]))
    }

    /// The downwash field at grid sample (c, r), pt/s.
    public func washSample(_ c: Int, _ r: Int) -> SIMD2<Double> {
        guard c >= 0 && r >= 0 && c < columns && r < rows else { return SIMD2(0, 0) }
        let i = r * columns + c
        return SIMD2(Double(dwx[i]), Double(dwy[i]))
    }
}
