import CoreGraphics
import Foundation

/// The air at one point, in pt/s (ocean space, y down): the sketch's three sums (html:711–712).
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

/// The meadow's air, ported from the sketch's breeze (html:705–756, 1607–1615, 1969–1978): a slowly turning wind with
/// gust bands that roll downwind, plus two fields on a coarse grid, the air the pointer stirs and the wings'
/// downwash, both decaying with a half-life of about 0.43 s.
///
/// Stepped at the family's fixed 1/60 s (`OceanClock`), never at a frame's time. The pointer is read once a step, as
/// Web does: `pointerMoved` only records where the pointer was and when; `step` stirs along the way it went since the
/// last step (see `MeadowTuning.Stir.pathLag`). Nothing allocates per step once laid out.
public final class Breeze {
    /// The director's settings (the breeze and downwash sliders are read).
    public var tuning: MeadowTuning
    /// Seconds of simulation stepped (the sketch's `simT`).
    public private(set) var time = 0.0
    /// The wind's direction (unit) and base speed this step (`wind.cx/cy`, `wind.base`).
    public private(set) var directionX = 1.0
    public private(set) var directionY = 0.0
    public private(set) var base = 0.0
    /// `S`: sketch points per point (cell width / 13).
    public private(set) var unit = 1.0
    /// The pointer's own time: seconds stepped at the pointer's pace (`dt / speed` a step). `pointerMoved(at:)`
    /// takes its times on this clock.
    public private(set) var inputClock = 0.0
    /// How far behind the pointer the stir point plays its path back, s (the port's rule, `Stir.pathLag`). The
    /// replay of the sketch's fixture sets 0: the sketch's own per-step difference.
    public private(set) var pathLag = MeadowTuning.Stir.pathLag

    // The grid: `PG`, its origin (the terrain's top-left) and size; the two fields, stored as Float as the sketch's
    // Float32Arrays are, so a replay rounds the same way.
    public private(set) var spacing = 48.0
    private var originX = 0.0, originY = 0.0
    public private(set) var columns = 0
    public private(set) var rows = 0
    private var pfx: [Float] = [], pfy: [Float] = []
    private var dwx: [Float] = [], dwy: [Float] = []

    // The pointer: its path as reported (a ring of timed samples, oldest first from `pathStart`), whether it is
    // over the meadow (or still playing out the way it went before it left), and the stir point after the last step
    // (the sketch's `ptr.sx/sy`).
    private static let pathCapacity = 256
    private var pathT = [Double](repeating: 0, count: Breeze.pathCapacity)
    private var pathX = [Double](repeating: 0, count: Breeze.pathCapacity)
    private var pathY = [Double](repeating: 0, count: Breeze.pathCapacity)
    private var pathStart = 0, pathCount = 0
    /// The pointer is over the meadow.
    public private(set) var pointerActive = false
    private var playing = false              // the stir point is following a path (also just after the pointer left)
    private var headX = 0.0, headY = 0.0

    public init(terrain: Terrain, cell: CGSize, tuning: MeadowTuning = .director) {
        self.tuning = tuning.sanitized()
        layout(terrain: terrain, cell: cell)
    }

    /// The grid laid over the terrain's bounds at this cell size (the sketch's `pfInit`, on every resize): both
    /// fields start still. A broken size gives a one-sample grid; a huge one widens the spacing (never more than
    /// `Stir.maxSamples` samples).
    public func layout(terrain: Terrain, cell: CGSize) {
        let cw = Double(cell.width)
        unit = cw.isFinite && cw > 0 ? min(cw, 1000) / MeadowTuning.Unit.referenceCell : 1
        let b = terrain.bounds
        let bx = Double(b.minX), by = Double(b.minY), bw = Double(b.width), bh = Double(b.height)
        originX = bx.isFinite ? bx : 0
        originY = by.isFinite ? by : 0
        let W = bw.isFinite ? max(0, bw) : 0
        let H = bh.isFinite ? max(0, bh) : 0
        var pg: Double = MeadowTuning.Stir.grid * unit
        // pgc = ceil(W / PG) + 1, pgr = ceil(H / PG) + 1 (html:715), widened past the cap.
        func cells(_ pg: Double) -> (Int, Int) {
            let c: Double = min(1e9, ceil(W / pg) + 1)
            let r: Double = min(1e9, ceil(H / pg) + 1)
            return (Int(c), Int(r))
        }
        var (c, r) = cells(pg)
        while c * r > MeadowTuning.Stir.maxSamples {
            pg *= 2
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
    }

    /// How far behind the pointer the stir point follows, s (0…1; 0 is the sketch's own rule).
    public func setPathLag(_ seconds: Double) {
        pathLag = seconds.isFinite ? min(1, max(0, seconds)) : MeadowTuning.Stir.pathLag
    }

    // ── the pointer ──

    /// The pointer is at (x, y) over the meadow; it was there at `at`, on `inputClock` (nil: now, when it arrives).
    /// Only recorded: the steps stir along the way it went. A host that knows when each event happened passes it, so
    /// moves that arrive late or together are still played back at their own pace. Times never run backwards or
    /// ahead of now; a non-finite point is ignored.
    public func pointerMoved(x: Double, y: Double, at: Double? = nil) {
        guard x.isFinite && y.isFinite else { return }
        var t = inputClock
        if let a = at, a.isFinite { t = min(inputClock, a) }
        if !pointerActive {
            // Coming onto the meadow: its way starts here (the sketch's `ptr.sx = x` on entry, html:2672).
            pathStart = 0
            pathCount = 0
            headX = x
            headY = y
            pointerActive = true
        }
        playing = true
        if pathCount > 0 { t = max(t, pathT[(pathStart + pathCount - 1) % Breeze.pathCapacity]) }
        if pathCount == Breeze.pathCapacity {
            pathStart = (pathStart + 1) % Breeze.pathCapacity
            pathCount -= 1
        }
        let i = (pathStart + pathCount) % Breeze.pathCapacity
        pathT[i] = t
        pathX[i] = x
        pathY[i] = y
        pathCount += 1
    }

    /// The pointer left the meadow: the way it went before it left still plays out, then it stirs nothing until it
    /// comes back, and its way back starts where it enters.
    public func pointerLeft() {
        pointerActive = false
        // With no lag, the sketch's rule: a pointer gone stirs nothing more (`if (!ptr.has) return`, html:1970).
        if pathLag == 0 { playing = false }
    }

    /// Where the pointer's path was at time `t`: between the samples either side, else the nearest end. Drops the
    /// samples the stir point has passed.
    private func pathPoint(_ t: Double) -> (Double, Double) {
        let cap = Breeze.pathCapacity
        while pathCount > 1 && pathT[(pathStart + 1) % cap] <= t {
            pathStart = (pathStart + 1) % cap
            pathCount -= 1
        }
        let a = pathStart
        if pathCount == 1 || t <= pathT[a] { return (pathX[a], pathY[a]) }
        let b = (a + 1) % cap
        let span: Double = pathT[b] - pathT[a]
        let f: Double = span > 0 ? (t - pathT[a]) / span : 1
        return (pathX[a] + (pathX[b] - pathX[a]) * f, pathY[a] + (pathY[b] - pathY[a]) * f)
    }

    // ── stepping ──

    /// One fixed step: the wind turns and the fields decay (`updateWind`), then the pointer stirs along its way
    /// (`stirStep`). `speed` is the app's speed setting (the sketch's time scale): a step is `dt / speed` of the
    /// pointer's own time.
    public func step(_ dt: Double, speed: Double = 1) {
        guard dt.isFinite && dt > 0 else { return }
        time += dt
        let pace: Double = speed.isFinite && speed > 0 ? speed : 1
        inputClock += dt / pace
        updateWind(dt)
        stirStep(dt, speed: pace)
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
        for i in 0..<pfx.count {
            pfx[i] = Float(Double(pfx[i]) * k)
            pfy[i] = Float(Double(pfy[i]) * k)
            dwx[i] = Float(Double(dwx[i]) * k)
            dwy[i] = Float(Double(dwy[i]) * k)
        }
    }

    /// The sketch's `stirStep` (html:1969–1978), fed by the port's played-back stir point: the stir point moves from
    /// where it was after the last step to where the pointer's path was `pathLag` ago, and the air is stirred along
    /// that way at the speed the pointer went, one stir per grid spacing of the way. With no lag it is the sketch's
    /// rule exactly: from where the pointer was at the last step to where it is now.
    private func stirStep(_ dt: Double, speed: Double) {
        guard playing && pathCount > 0 else { return }
        let (sx, sy) = pathPoint(inputClock - pathLag)
        // Past the last sample after the pointer left: the way is played out.
        if !pointerActive && pathCount == 1 && inputClock - pathLag >= pathT[pathStart] { playing = false }
        let dx: Double = sx - headX
        let dy: Double = sy - headY
        headX = sx
        headY = sy
        if dx == 0 && dy == 0 { return }
        typealias St = MeadowTuning.Stir
        let real: Double = dt / speed
        let k: Double = St.impulseRate * dt
        let vx: Double = clamp(dx / real, -St.speedLimit, St.speedLimit) * k
        let vy: Double = clamp(dy / real, -St.speedLimit, St.speedLimit) * k
        let way: Double = (dx * dx + dy * dy).squareRoot() / spacing
        let n = Int(max(1, min(100_000, ceil(way))))
        let nd = Double(n)
        for i in 1...n {
            let back: Double = Double(n - i) / nd
            stir(sx - dx * back, sy - dy * back, vx / nd, vy / nd)
        }
    }

    /// A grid index held to −1…count (the loops skip the samples outside), safe for any finite value.
    @inline(__always) private static func index(_ v: Double, _ count: Int) -> Int {
        Int(min(Double(count), max(-1, v)))
    }

    /// `stir(x, y, vx, vy)` (html:747–756): adds the pointer's push within 3 grid cells, weight `(1 − d)² · 0.16`,
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

    /// `wash(x, y, v, rad)` (html:1607–1615): pushes the air out from (x, y), `v` at the centre falling to 0 at
    /// `rad` pt, each sample clamped to ±200 pt/s.
    public func wash(_ x: Double, _ y: Double, _ v: Double, _ radius: Double) {
        guard x.isFinite && y.isFinite && v.isFinite && radius.isFinite && radius > 0, !dwx.isEmpty else { return }
        let lim = MeadowTuning.Stir.washLimit
        let cx: Double = (x - originX) / spacing
        let cy: Double = (y - originY) / spacing
        let rr: Double = min(radius / spacing, 1e4)
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

    /// A flying butterfly's downstroke (html:1752): at height z under 0.35, while the stroke's `sinθ` is positive,
    /// it washes `520 · S · downwash · (1 − z / 0.35) · sinθ · dt` out within 1.2 of its span (`spanRef`, pt).
    /// Nothing at z ≥ 0.35 or on the upstroke.
    public func downstroke(x: Double, y: Double, z: Double, sinStroke s: Double, span: Double, dt: Double) {
        typealias St = MeadowTuning.Stir
        guard z.isFinite && s.isFinite && s > 0 && z < St.washBelow && tuning.downwash > 0 else { return }
        let v: Double = St.washFlight * unit * tuning.downwash * (1 - max(0, z) / St.washBelow) * s * dt
        wash(x, y, v, St.washFlightRadius * span)
    }

    /// A swallowtail fluttering on a flower (html:1882): `300 · S · downwash · sinθ · dt` within one span.
    public func flutter(x: Double, y: Double, sinStroke s: Double, span: Double, dt: Double) {
        typealias St = MeadowTuning.Stir
        guard s.isFinite && s > 0 && tuning.downwash > 0 else { return }
        wash(x, y, St.washFlutter * unit * tuning.downwash * s * dt, St.washFlutterRadius * span)
    }

    // ── sampling ──

    /// `gustAt(x, y, t)` (html:724–729): the gust at a point now, 0…1.
    public func gust(_ x: Double, _ y: Double) -> Double {
        typealias W = MeadowTuning.Wind
        let along: Double = (x * directionX + y * directionY) / (W.bandAlong * unit)
        let a: Double = along - time * W.bandRoll
        let b: Double = (-x * directionY + y * directionX) / (W.bandAcross * unit)
        let o1: Double = W.octave1 * MeadowMath.vnoise(a, b, W.octave1Noise)
        let o2: Double = W.octave2 * MeadowMath.vnoise(a * W.octave2Along + W.octave2Shift, b * W.octave2Across, W.octave2Noise)
        return MeadowMath.smooth(W.gustFrom, W.gustTo, o1 + o2)
    }

    /// `windAt(x, y, t)` (html:731–745): the air at a point now. Still air at a non-finite point.
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
