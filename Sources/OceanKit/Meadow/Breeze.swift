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

/// How the pointer's path becomes stir.
public enum PointerPlayback: Equatable, Sendable {
    /// The sketch's `stirStep` exactly (html:1987–1996): each step stirs from where the pointer was at the last step
    /// to where it is now, whatever the events' times. Only the replays of the sketch run it.
    case sketch
    /// The port's rule (`MeadowTuning.Stir`): the path is played back from the events' own times and places, `lag`
    /// seconds behind them; a step whose place on the path isn't known yet waits, and is stirred when its samples
    /// arrive, as it would have been (see `Breeze.pointerMoved(x:y:at:)`).
    case played(lag: Double)
}

/// The meadow's air, ported from the sketch's breeze (html:713–764, 1625–1633, 1987–1996): a slowly
/// turning wind with gust bands that roll downwind, plus two fields on a coarse grid, the air the pointer stirs and
/// the wings' downwash, both decaying with a half-life of about 0.43 s.
///
/// Stepped at the family's fixed tick only (`OceanClock.step`, 1/60 s); any other step length is refused. The
/// pointer is read once a step: `pointerMoved` only records where the pointer was and when; `step` stirs along the
/// way it went (see `PointerPlayback`). Nothing allocates per step once laid out.
///
/// **The host's input contract (m7).** For every pointer event over the meadow, in the order they happened, the host
/// calls `pointerMoved(x:y:hostTime:)` with the event's own position (ocean space) and its own timestamp
/// (`NSEvent.timestamp`, seconds on the system's uptime clock, the clock `CACurrentMediaTime` and the display link
/// use), never the time it was delivered; `pointerLeft()` when the pointer leaves the meadow. Once a frame, after the
/// frame's steps, it calls `syncInputClock(hostTime:speed:)` with the frame's timestamp and speed (the ones
/// `OceanClock.advance` got), so the breeze can place those timestamps on its own input clock across frame batches,
/// stalls and speed changes. The steps are `step(_:speed:)` at that same speed.
/// Events may arrive late, in pairs or in bursts (a frame's worth together): each is played back at its own time.
/// A host that keeps its own input clock may call `pointerMoved(x:y:at:)` instead.
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
    /// The pointer's own time: real seconds, as stepped (`OceanClock.step / pace` a step). `pointerMoved(at:)`
    /// takes its times on this clock.
    public private(set) var inputClock = 0.0
    /// How the pointer's path is stirred (the port's rule unless a replay of the sketch asks for the sketch's).
    public private(set) var playback: PointerPlayback = .played(lag: MeadowTuning.Stir.pathLag)

    // The grid: `PG`, its origin (the terrain's top-left) and size; the two fields, stored as Float as the sketch's
    // Float32Arrays are, so a replay rounds the same way.
    public private(set) var spacing = 48.0
    private var originX = 0.0, originY = 0.0
    public private(set) var columns = 0
    public private(set) var rows = 0
    private var pfx: [Float] = [], pfy: [Float] = []
    private var dwx: [Float] = [], dwy: [Float] = []

    // The pointer's path as reported: a ring of samples (time on the input clock, place, and whether the pointer
    // came onto the meadow there, so nothing is stirred along the way into it), oldest first from `pathStart`. The
    // first sample is the one the stir point is on or past.
    private static let pathCapacity = 256
    private var pathT = [Double](repeating: 0, count: Breeze.pathCapacity)
    private var pathX = [Double](repeating: 0, count: Breeze.pathCapacity)
    private var pathY = [Double](repeating: 0, count: Breeze.pathCapacity)
    private var pathEntry = [Bool](repeating: false, count: Breeze.pathCapacity)
    private var pathStart = 0, pathCount = 0
    // The steps whose place on the path isn't known yet (no sample at or after it has arrived): the path time each
    // is to reach, its real length, and which step it was. Played, oldest first, once their samples arrive.
    private static let pendingCapacity = Int(MeadowTuning.Stir.waitSteps)
    private var pendT = [Double](repeating: 0, count: Breeze.pendingCapacity)
    private var pendReal = [Double](repeating: 0, count: Breeze.pendingCapacity)
    private var pendStep = [Int](repeating: 0, count: Breeze.pendingCapacity)
    private var pendStart = 0, pendCount = 0
    /// The pointer is over the meadow.
    public private(set) var pointerActive = false
    private var playing = false              // the stir point is following a path (also just after the pointer left)
    private var headX = 0.0, headY = 0.0     // the stir point (the sketch's `ptr.sx/sy`)
    private var headT = 0.0                  // the path time it has reached
    // The host's clock: the last frame's host time, the family clock's simulation time accumulated but not yet stepped
    // then (mirrored), the speed it ran at, and the steps taken by then.
    private var hostLast: Double? = nil
    private var hostAcc = 0.0
    private var hostPace = 1.0
    private var hostSteps = 0
    // The last frames' anchors: each frame's host time and its moment on the input clock, newest at `anchorEnd − 1`.
    private static let anchorCapacity = 32
    private var anchorHost = [Double](repeating: 0, count: Breeze.anchorCapacity)
    private var anchorInput = [Double](repeating: 0, count: Breeze.anchorCapacity)
    private var anchorEnd = 0, anchorCount = 0

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
    }

    /// How the pointer's path is stirred. A `played` lag is held to 0…`Stir.lagLimit` (the default when it isn't a
    /// number). Changing it forgets the path played so far.
    public func setPlayback(_ p: PointerPlayback) {
        switch p {
        case .sketch:
            playback = .sketch
        case .played(let lag):
            let l: Double = lag.isFinite ? min(MeadowTuning.Stir.lagLimit, max(0, lag)) : MeadowTuning.Stir.pathLag
            playback = .played(lag: l)
        }
        pathStart = 0
        pathCount = 0
        pendStart = 0
        pendCount = 0
        playing = false
        pointerActive = false
    }

    private var lag: Double {
        if case .played(let l) = playback { return l }
        return 0
    }

    // ── the pointer ──

    /// The pointer was at (x, y) over the meadow at `at`, a time on `inputClock` (nil: now, as it arrives). Only
    /// recorded: the steps stir along the way it went, from these times. Times never run backwards (a sample older
    /// than the last is taken as at the last's time) and never more than `Stir.aheadLimit` ahead of now; a
    /// non-finite point is ignored. Coming onto the meadow (the first move, or the first after `pointerLeft`) starts
    /// a new way there: nothing is stirred along the jump from where it left.
    public func pointerMoved(x: Double, y: Double, at: Double? = nil) {
        guard x.isFinite && y.isFinite else { return }
        let px: Double = clamp(x, -MeadowTuning.Unit.coordinateLimit, MeadowTuning.Unit.coordinateLimit)
        let py: Double = clamp(y, -MeadowTuning.Unit.coordinateLimit, MeadowTuning.Unit.coordinateLimit)
        var t = inputClock
        if let a = at, a.isFinite { t = min(inputClock + MeadowTuning.Stir.aheadLimit, a) }
        let entering = !pointerActive
        pointerActive = true
        if case .sketch = playback {
            // The sketch: `ptr.x/y` is the latest move; on entry the stir point starts there (html:2690).
            if entering { headX = px; headY = py }
            pathStart = 0
            pathCount = 1
            pathT[0] = t
            pathX[0] = px
            pathY[0] = py
            playing = true
            return
        }
        if entering && !playing {
            // A fresh way: the stir point starts on its first sample. The recent steps due after it (its samples
            // may arrive later than the lag) wait to be played; those due before it are dropped.
            pathStart = 0
            pathCount = 0
            while pendCount > 0 && pendT[pendStart] < t {
                pendStart = (pendStart + 1) % Breeze.pendingCapacity
                pendCount -= 1
            }
            headX = px
            headY = py
            headT = t
        }
        playing = true
        if pathCount > 0 { t = max(t, pathT[(pathStart + pathCount - 1) % Breeze.pathCapacity]) }
        if pathCount == Breeze.pathCapacity {
            // Full (a flood of events more than `pathCapacity` ahead of the stir point): the oldest unplayed sample
            // is dropped.
            pathStart = (pathStart + 1) % Breeze.pathCapacity
            pathCount -= 1
        }
        let i = (pathStart + pathCount) % Breeze.pathCapacity
        pathT[i] = t
        pathX[i] = px
        pathY[i] = py
        pathEntry[i] = entering && pathCount > 0
        pathCount += 1
    }

    /// `pointerMoved` with the event's own timestamp on the host's clock (`NSEvent.timestamp`), placed on the input
    /// clock by the last `syncInputClock(hostTime:speed:)`. Before the first sync it is taken as now.
    public func pointerMoved(x: Double, y: Double, hostTime: Double) {
        guard hostTime.isFinite, anchorCount > 0 else { pointerMoved(x: x, y: y); return }
        // Placed through the frame it happened in (the latest at or before it), so an event delivered a frame or a
        // speed change later lands where it happened.
        let cap = Breeze.anchorCapacity
        var k = (anchorEnd - 1 + cap) % cap
        for _ in 1..<anchorCount {
            if anchorHost[k] <= hostTime { break }
            k = (k - 1 + cap) % cap
        }
        pointerMoved(x: x, y: y, at: anchorInput[k] + (hostTime - anchorHost[k]))
    }

    /// Ties the input clock to the host's: once a frame, after that frame's steps, with the frame's timestamp and the
    /// speed `OceanClock.advance` got. The frame's moment on the input clock is the input clock plus what the family
    /// clock has accumulated but not yet stepped (`acc / speed`, under a step); the breeze keeps that remainder as
    /// `OceanClock` does (each frame adds its real time, held to `Stir.frameLimit`, times the speed; each step takes
    /// `OceanClock.step`; a frame at the step cap drops the rest), held to 0…one step. An event's host time then lands
    /// on the input clock where it happened between the steps, at any frame rate, steady or uneven.
    public func syncInputClock(hostTime: Double, speed: Double = 1) {
        guard hostTime.isFinite else { return }
        let n = steps - hostSteps
        hostSteps = steps
        hostPace = MeadowTuning.Unit.pace(speed)
        if let last = hostLast {
            if hostTime > last {
                hostAcc += min(MeadowTuning.Stir.frameLimit, hostTime - last) * hostPace
                hostLast = hostTime
            }
            hostAcc -= Double(n) * OceanClock.step
            if n >= OceanClock.maxSteps { hostAcc = 0 }
        } else {
            hostLast = hostTime
            hostAcc = 0
        }
        hostAcc = min(OceanClock.step, max(0, hostAcc))
        guard let last = hostLast else { return }
        let cap = Breeze.anchorCapacity
        let newest = (anchorEnd - 1 + cap) % cap
        let moment: Double = inputClock + hostAcc / hostPace
        if anchorCount > 0 && anchorHost[newest] == last {
            anchorInput[newest] = moment
        } else {
            anchorHost[anchorEnd] = last
            anchorInput[anchorEnd] = moment
            anchorEnd = (anchorEnd + 1) % cap
            anchorCount = min(cap, anchorCount + 1)
        }
    }

    /// The pointer left the meadow: the way it went before it left still plays out, then it stirs nothing until it
    /// comes back, and its way back starts where it enters (nothing is stirred along the jump).
    public func pointerLeft() {
        pointerActive = false
        // The sketch: a pointer gone stirs nothing more (`if (!ptr.has) return`, html:1988).
        if case .sketch = playback { playing = false }
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
        inputClock += dt / pace
        updateWind(dt)
        switch playback {
        case .sketch: sketchStir(dt, real: dt / pace)
        case .played(let l): playStir(dt, real: dt / pace, lag: l)
        }
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

    /// The sketch's `stirStep` (html:1987–1996): from where the pointer was at the last step to where it is now.
    private func sketchStir(_ dt: Double, real: Double) {
        guard playing && pathCount > 0 else { return }
        let x = pathX[pathStart], y = pathY[pathStart]
        stirWay(fromX: headX, fromY: headY, toX: x, toY: y, dt: dt, real: real, weight: 1)
        headX = x
        headY = y
    }

    /// The sketch's stroke along one way (html:1990–1995): at the speed the pointer went (each axis held to ±1500
    /// pt/s), an impulse of 60 · dt × that speed, split into one stir per grid spacing of the way. `weight` scales the
    /// impulse (a late step's decay since it was due).
    private func stirWay(fromX: Double, fromY: Double, toX: Double, toY: Double, dt: Double, real: Double,
                         weight: Double) {
        let dx: Double = toX - fromX
        let dy: Double = toY - fromY
        if dx == 0 && dy == 0 { return }
        typealias St = MeadowTuning.Stir
        let k: Double = St.impulseRate * dt * weight
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

    /// The port's playback: this step is due at path time `inputClock − lag`. Each step waiting (this one and any
    /// before it whose samples hadn't arrived) is played as soon as its place on the path is known, oldest first,
    /// stirring the way from the stir point to it as that step would have, its impulse decayed by the steps since it
    /// was due. Its place is known once a sample at or after its time has arrived, or once the pointer has left (the
    /// way ended at the last sample). A step that waits longer than `Stir.waitSteps` is played as if the pointer had
    /// stopped at the last sample.
    private func playStir(_ dt: Double, real: Double, lag: Double) {
        // Every step is remembered (the last `waitSteps`), playing or not, so a way whose first samples arrive later
        // than the lag still plays the steps due after its start.
        let cap = Breeze.pendingCapacity
        let live = playing && pathCount > 0
        if pendCount == cap {
            if live {
                playPending(dt, force: true)
            } else {
                pendStart = (pendStart + 1) % cap
                pendCount -= 1
            }
        }
        let j = (pendStart + pendCount) % cap
        pendT[j] = inputClock - lag
        pendReal[j] = real
        pendStep[j] = steps
        pendCount += 1
        guard live else { return }
        while pendCount > 0 && playPending(dt, force: !pointerActive) {}
        // Past the last sample after the pointer left: the way is played out (and the queue empty).
        if !pointerActive && pendCount == 0 && pathCount == 1 && headT >= pathT[pathStart] { playing = false }
    }

    /// Plays the oldest waiting step if its place is known (or `force`); false if it must wait.
    @discardableResult
    private func playPending(_ dt: Double, force: Bool) -> Bool {
        let cap = Breeze.pendingCapacity
        let tau = pendT[pendStart]
        let newest: Double = pathT[(pathStart + pathCount - 1) % Breeze.pathCapacity]
        if !force && tau > newest { return false }
        let real = pendReal[pendStart]
        let late = Double(steps - pendStep[pendStart])
        let weight: Double = late > 0 ? exp(-MeadowTuning.Stir.decay * dt * late) : 1
        pendStart = (pendStart + 1) % cap
        pendCount -= 1
        advanceHead(to: max(tau, headT), dt: dt, real: real, weight: weight)
        return true
    }

    /// Moves the stir point along the path to time `tau`, stirring the way it goes (straight, as the sketch's one
    /// stroke a step), except across a re-entry, where it jumps without stirring. Drops the samples it has passed.
    private func advanceHead(to tau: Double, dt: Double, real: Double, weight: Double) {
        let cap = Breeze.pathCapacity
        var fromX = headX, fromY = headY
        // Past each sample the time reaches: a re-entry ends the stroke there and starts the next at the entry.
        while pathCount > 1 && pathT[(pathStart + 1) % cap] <= tau {
            let b = (pathStart + 1) % cap
            if pathEntry[b] {
                let a = pathStart
                stirWay(fromX: fromX, fromY: fromY, toX: pathX[a], toY: pathY[a], dt: dt, real: real, weight: weight)
                fromX = pathX[b]
                fromY = pathY[b]
            }
            pathStart = b
            pathCount -= 1
        }
        let (x, y) = pathPoint(tau)
        stirWay(fromX: fromX, fromY: fromY, toX: x, toY: y, dt: dt, real: real, weight: weight)
        headX = x
        headY = y
        headT = tau
    }

    /// Where the path was at time `t`, on the segment from the first sample: between it and the next; at the first
    /// before it is reached, and at the last past the end. Into a re-entry the pointer stays where it left until
    /// the entry's time; a gap longer than `Stir.longestMove` is taken as the pointer resting, then moving over the
    /// last `longestMove` of it.
    private func pathPoint(_ t: Double) -> (Double, Double) {
        let cap = Breeze.pathCapacity
        let a = pathStart
        if pathCount == 1 || t <= pathT[a] { return (pathX[a], pathY[a]) }
        let b = (a + 1) % cap
        if pathEntry[b] { return (pathX[a], pathY[a]) }
        let start: Double = max(pathT[a], pathT[b] - MeadowTuning.Stir.longestMove)
        if t <= start { return (pathX[a], pathY[a]) }
        let span: Double = pathT[b] - start
        let f: Double = span > 0 ? min(1, (t - start) / span) : 1
        return (pathX[a] + (pathX[b] - pathX[a]) * f, pathY[a] + (pathY[b] - pathY[a]) * f)
    }

    /// Steps waiting for their samples (for checks).
    public var waitingSteps: Int { pendCount }

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
