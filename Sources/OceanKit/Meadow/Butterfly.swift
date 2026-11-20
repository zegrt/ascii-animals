import CoreGraphics
import Foundation
import simd

/// What a butterfly is doing. `fly` and `court` cruise, `approach` and `cursor` slow to foraging speed, `flush`
/// is the escape burst; `nectar`, `bask` and `rest` are landed (the world stops calling `fly` for those).
public enum ButterflyState: Equatable, Sendable { case fly, approach, nectar, bask, rest, flush, cursor, court }

/// One butterfly in flight, flown by per-beat forces (research §1.4), in ocean space (y down).
///
/// Two time scales: the beat is slowed to ~0.28× real (≤ 3 Hz) and the advance per beat to ~0.4–0.7 wingspan,
/// so it reads as a slowed-down close-up. Every beat:
/// - **Downstroke** (sin θ > 0): lift `L·sin θ` upward. It averages to gravity over the beat, so the body rises on
///   the downstroke and sinks on the upstroke: the bob falls out of the forces.
/// - **Clap** (θ wraps past 2π, wings up): a forward lurch `T` along the heading, and the chance of a jink, a kick
///   to the target heading (the hindwings' zig-zag). The morpho's bounds also change at claps.
/// - **Always:** gravity, and air drag pulling the airspeed toward the wanted one.
/// - **Glides:** after a bout of beats, the wings stop in the glide pose as they pass it on the downstroke; no lift
///   and no claps, the airspeed settles onto the species' glide slope until the glide ends.
/// - **Heading** follows its target on a spring (k, ζ), so turns swing and settle. Bank follows the turn rate.
/// - **Ground velocity** = breeze + airspeed. Walls (`Terrain.wallPush`) steer it back and push.
public final class Butterfly {
    public let kind: ButterflyKind
    public let species: ButterflySpecies
    /// Position (body centre) and ground velocity, pt and pt/s.
    public var x, y, vx, vy: Double
    /// Flight direction, radians in [0, 2π), y down. `phase` is θ in [0, 2π): 0 is the clap (wings up), the
    /// downstroke is 0 … π. `bank` rolls the stroke plane toward the viewer, + when turning clockwise on screen.
    /// `pitch` is the body's nose-up angle about the path: nose down on the downstroke.
    public var heading: Double, phase: Double, bank: Double, pitch: Double
    /// φ, radians: the wings' elevation, φ_mid + A·cos θ.
    public var stroke: Double
    public var gliding: Bool
    public var state: ButterflyState
    /// Per individual: size ±12 %, boldness ×0.6–1.6, beat ±10 %, jink ±30 %.
    public var size: Double
    public var boldness: Double
    public var beatFactor: Double
    public var jinkFactor: Double
    /// `cell.width / 13`: speeds, accelerations and sizes are given for 13 × 19 pt cells.
    public var scale: Double = 1
    /// Claps so far: one per wingbeat.
    public private(set) var claps: Int = 0

    // Airspeed (ground velocity less the wind).
    private var ux: Double, uy: Double
    private var turnRate: Double = 0
    /// Offset on the target heading from jinks; it relaxes back over `jinkRelax`.
    private var jink: Double = 0
    // Flap bouts and glides.
    private var beatsLeft: Int
    private var armed = false
    private var glideLeft: Double = 0
    private var glideSense: Double = 1
    private var held = false
    // Free flight (no target): it roams toward a waypoint anywhere in the terrain, chosen along a preferred
    // direction that drifts over the species' persistence time.
    private var waypoint = SIMD2<Double>(0, 0)
    private var hasWaypoint = false
    private var waypointLeft: Double = 0
    private var prefer: Double
    private var preferAt: Double = 0
    private var wasPushing = false
    private var wander: Double
    private var time: Double = 0
    /// This beat's wanted speed as a share of the species' (`ButterflySpecies.surge`), redrawn at every clap.
    private var pace: Double = 1
    // The morpho's bounds: +1 climbing, -1 dropping.
    private var bound: Double = 0
    private var boundLeft: Int = 0
    /// The flight state after the last step that left everything finite: a step that doesn't is undone to it.
    private struct Snapshot {
        var x, y, vx, vy, ux, uy, heading, turnRate, jink, phase, bank, pitch, stroke, prefer: Double
    }
    private var good: Snapshot

    /// Jink offsets on the target heading relax back with this time constant, s.
    static let jinkRelax = 1.5
    /// Turn rate (rad/s) that gives about three-quarters of the species' max bank.
    static let bankRate = 1.5
    /// How fast the bank follows its target, 1/s.
    static let bankFollow = 6.0
    /// The heading spring's turn-rate limit, rad/s.
    static let maxTurn = 6.0
    /// Climb angle toward a higher waypoint: the top of the measured 13–22° (Le Roy 2021).
    static let climb = 22 * Double.pi / 180
    /// Steepest descent toward a lower waypoint.
    static let descend = 30 * Double.pi / 180
    /// The free-flight heading's slow vertical wander: ±20° of value noise at ~0.15 Hz.
    static let wobble = 0.35
    /// The steepest heading toward a waypoint close above or below.
    static let steepUp = 50 * Double.pi / 180, steepDown = 60 * Double.pi / 180
    /// Share of waypoints in the bottom 40 % of a screen, where the flowers are.
    static let lowWaypoints = 0.65

    public init(kind: ButterflyKind, x: Double, y: Double, random: WebRandom) {
        let sp = ButterflySpecies.of(kind)
        self.kind = kind
        species = sp
        self.x = x
        self.y = y
        size = 1 + random.range(-sp.sizeSpread, sp.sizeSpread)
        boldness = random.range(0.6, 1.6)
        beatFactor = 1 + random.range(-0.1, 0.1)
        jinkFactor = 1 + random.range(-0.3, 0.3)
        let sense: Double = random.unit() < 0.5 ? -1 : 1
        heading = sense > 0 ? 0 : Double.pi
        prefer = sense > 0 ? 0 : Double.pi
        phase = random.range(0, TAU)
        bank = 0
        pitch = 0
        stroke = sp.strokeMid + sp.strokeAmp * cos(phase)
        gliding = false
        state = .fly
        ux = sense * sp.cruise
        uy = 0
        vx = ux
        vy = 0
        beatsLeft = random.int(sp.boutBeats.lowerBound, sp.boutBeats.upperBound)
        wander = floor(random.range(0, 10_000))
        if sp.boundAngle > 0 {
            bound = random.unit() < 0.5 ? -1 : 1
            boundLeft = random.int(sp.boundBeats.lowerBound, sp.boundBeats.upperBound)
        }
        good = Snapshot(x: x, y: y, vx: ux, vy: 0, ux: ux, uy: 0, heading: heading, turnRate: 0, jink: 0,
                        phase: phase, bank: 0, pitch: 0, stroke: stroke, prefer: prefer)
    }

    private var snapshot: Snapshot {
        Snapshot(x: x, y: y, vx: vx, vy: vy, ux: ux, uy: uy, heading: heading, turnRate: turnRate, jink: jink,
                 phase: phase, bank: bank, pitch: pitch, stroke: stroke, prefer: prefer)
    }

    private var isFinite: Bool {
        let a: Bool = x.isFinite && y.isFinite && vx.isFinite && vy.isFinite && ux.isFinite && uy.isFinite
        let b: Bool = heading.isFinite && turnRate.isFinite && jink.isFinite && phase.isFinite
        let c: Bool = bank.isFinite && pitch.isFinite && stroke.isFinite && prefer.isFinite
        return a && b && c
    }

    /// Back to the last finite state, with a fresh waypoint to come (the old one may be what went wrong).
    private func restore() {
        let g = good
        x = g.x; y = g.y; vx = g.vx; vy = g.vy; ux = g.ux; uy = g.uy
        heading = g.heading; turnRate = g.turnRate; jink = g.jink; phase = g.phase
        bank = g.bank; pitch = g.pitch; stroke = g.stroke; prefer = g.prefer
        hasWaypoint = false
    }

    /// The wing elevation held in a glide: cos φ = the pose's projected width.
    private var glideStroke: Double { acos(clamp(species.glideWidth, -1, 1)) }

    /// θ on the downstroke where the stroke passes the glide pose.
    private var glidePhase: Double {
        acos(clamp((glideStroke - species.strokeMid) / species.strokeAmp, -1, 1))
    }

    /// Wingspan in pt.
    public var wingspan: Double { species.span * 13 * scale * size }

    /// Half the span as drawn (`ButterflySpecies.drawnSpan` cells of 13 pt at this scale), pt: how far the drawing
    /// reaches from the body sideways.
    public var drawnHalfSpan: Double { species.drawnSpan * 13 * scale * size / 2 }

    /// How far the drawing reaches above the body, pt, at 19-pt rows at this scale: the head and the antennae
    /// (`MeadowPainter` draws their clubs 0.42 half-heights and 3.3 rows above the body).
    public var drawnUp: Double {
        let row: Double = 19 * scale
        return 0.42 * species.drawnHeight * row * size / 2 + 3.3 * row
    }

    /// How far the drawing reaches below the body, pt: the hindwings (the swallowtail's tails 1.4 half-heights) and
    /// the tips' 0.4-row climb.
    public var drawnDown: Double {
        let row: Double = 19 * scale
        return (species.tailRow ? 1.4 : 1) * species.drawnHeight * row * size / 2 + 0.4 * row
    }

    /// Stop beating and glide for `seconds`, wings in the glide pose; it won't end early.
    public func glide(for seconds: Double) {
        startGlide(seconds)
        held = true
    }

    private func startGlide(_ seconds: Double) {
        gliding = true
        armed = false
        glideLeft = seconds
        glideSense = cos(heading) >= 0 ? 1 : -1
        phase = glidePhase
        stroke = glideStroke
    }

    /// Projected width of each wing, s = cos(ρ ± φ). Negative: the wing is past edge-on and shows its underside.
    public func wings() -> (left: Double, right: Double) {
        (cos(bank + stroke), cos(bank - stroke))
    }

    /// A standard normal draw (Box–Muller).
    @inline(__always) private func gauss(_ random: WebRandom) -> Double {
        let a: Double = max(random.unit(), 1e-12), b: Double = random.unit()
        return (-2 * log(a)).squareRoot() * cos(TAU * b)
    }

    /// Angle `a` tilted up (toward −y) by `e`, keeping its horizontal sense.
    @inline(__always) private func tilted(_ a: Double, _ e: Double) -> Double {
        let side: Double = cos(a) >= 0 ? 1 : -1
        let elevation: Double = atan2(-sin(a), abs(cos(a))) + e
        return atan2(-sin(elevation), side * cos(elevation))
    }

    /// A wall margin of `want`, but never more than a quarter of the screen's shorter side, so on a tiny screen
    /// (the Settings preview) the walls don't meet in the middle.
    @inline(__always) static func capped(_ want: Double, _ r: CGRect) -> Double {
        let short: Double = Double(min(r.width, r.height))
        return min(want, 0.25 * short)
    }

    /// How far a point inside the terrain is from its nearest wall (0 outside it).
    static func clearance(_ q: SIMD2<Double>, _ terrain: Terrain) -> Double {
        guard terrain.contains(q) else { return 0 }
        var best: Double = .infinity
        for e in terrain.edges {
            let d: SIMD2<Double> = e.b - e.a
            let along: Double = simd_dot(q - e.a, d) / max(simd_length_squared(d), 1e-12)
            let t: Double = min(1, max(0, along))
            let foot: SIMD2<Double> = e.a + d * t
            best = min(best, simd_length(q - foot))
        }
        return best
    }

    /// How far inside the walls the flight keeps (and free flight puts its waypoints): at the sides, the top and the
    /// bottom, the drawing's reach that way, so it stays on the screen, and a zone beyond it for the turn.
    struct Walls {
        var side: Double, top: Double, bottom: Double
        /// Halfway from `d` to these.
        func halfway(_ d: Walls) -> Walls {
            Walls(side: (side + d.side) / 2, top: (top + d.top) / 2, bottom: (bottom + d.bottom) / 2)
        }
        /// Each held to a quarter of the screen's shorter side, as `capped` does.
        func capped(_ r: CGRect) -> Walls {
            Walls(side: Butterfly.capped(side, r), top: Butterfly.capped(top, r), bottom: Butterfly.capped(bottom, r))
        }
    }
    /// The drawing's reach.
    var reach: Walls { Walls(side: drawnHalfSpan, top: drawnUp, bottom: drawnDown) }
    var margins: Walls {
        let zx: Double = Butterfly.turnZone.x * wingspan, zy: Double = Butterfly.turnZone.y * wingspan
        return Walls(side: drawnHalfSpan + zx, top: drawnUp + zy, bottom: drawnDown + zy)
    }
    /// The turn zones, wingspans: narrow at the sides (the drawing is wide, and free flight still roams the width);
    /// deeper at the top and bottom, where the climbs and glides run into them.
    static let turnZone = SIMD2<Double>(0.1, 0.2)

    /// The wall push with these margins: each edge of the terrain (they run along the axes) with its own.
    private func push(_ p: SIMD2<Double>, _ terrain: Terrain, _ m: Walls) -> SIMD2<Double> {
        let sides: Double = terrain.wallPush(p, margin: m.side).x
        let down: Double = terrain.wallPush(p, margin: m.top).y, up: Double = terrain.wallPush(p, margin: m.bottom).y
        return SIMD2<Double>(sides, max(0, down) + min(0, up))
    }

    /// A random point inside a screen, clear of its walls, in the bottom 40 % of it `lowWaypoints` of the time.
    private func randomPoint(_ terrain: Terrain, _ random: WebRandom, span: Double) -> SIMD2<Double> {
        guard !terrain.rects.isEmpty else { return SIMD2<Double>(x, y) }
        var u: Double = random.unit() * terrain.area
        var r = terrain.rects[terrain.rects.count - 1]
        for rect in terrain.rects {
            u -= Double(rect.width * rect.height)
            if u < 0 { r = rect; break }
        }
        // At the drawing's reach: as the original placed them half a wingspan into its one-wingspan margin, inside
        // the turn zone, so free flight roams right out to where the drawing still fits.
        let m: Walls = reach.capped(r)
        let minX: Double = Double(r.minX) + m.side, maxX: Double = Double(r.maxX) - m.side
        let minY: Double = Double(r.minY) + m.top, maxY: Double = Double(r.maxY) - m.bottom
        let px: Double = minX < maxX ? random.range(minX, maxX) : Double(r.midX)
        let lowTop: Double = max(minY, Double(r.maxY) - 0.4 * Double(r.height))
        let py: Double
        if minY >= maxY {
            py = Double(r.midY)
        } else if random.unit() < Butterfly.lowWaypoints && lowTop < maxY {
            py = random.range(lowTop, maxY)
        } else {
            py = random.range(minY, maxY)
        }
        return SIMD2<Double>(px, py)
    }

    /// The next free-flight waypoint: the best of four random points for heading along the preferred direction
    /// and going somewhere. The preferred direction drifts as a random walk that decorrelates over the species'
    /// persistence time; at a wall it is redrawn about the wall's normal (`away`).
    private func pickWaypoint(_ terrain: Terrain, _ random: WebRandom, from p: SIMD2<Double>, span: Double, away: Double?) {
        let sp = species
        let persist: Double = (sp.persistence.lowerBound + sp.persistence.upperBound) / 2
        if let a = away {
            prefer = a + 0.6 * gauss(random)
        } else {
            let since: Double = max(0, time - preferAt)
            let spread: Double = (2 * since / persist).squareRoot()
            prefer += gauss(random) * spread
        }
        preferAt = time
        let b = terrain.bounds
        let reach: Double = 0.5 * Double(max(b.width, b.height))
        var best = p, bestScore = -Double.infinity
        for _ in 0..<4 {
            let q = randomPoint(terrain, random, span: span)
            let d: SIMD2<Double> = q - p
            let along: Double = cos(atan2(d.y, d.x) - prefer)
            let distance: Double = min(1, simd_length(d) / max(reach, 1))
            // Going somewhere counts as much as going the preferred way, so the drawn size's wider margins still leave
            // the flight roaming the whole field.
            let score: Double = along + 1.0 * distance
            if score > bestScore { best = q; bestScore = score }
        }
        let bearing: Double = atan2(best.y - p.y, best.x - p.x)
        if cos(bearing - prefer) < 0 { prefer = bearing }
        waypoint = best
        hasWaypoint = true
        waypointLeft = random.range(3, sp.persistence.lowerBound)
    }

    /// One step of flight. A non-finite target is ignored (free flight); a step that would leave anything
    /// non-finite, or one taken from a state poisoned from outside, is undone to the last finite state.
    public func fly(_ dt: Double, target: SIMD2<Double>?, breeze: Breeze, terrain: Terrain, random: WebRandom) {
        guard dt > 0 && dt.isFinite else { return }
        if !isFinite { restore() }
        step(dt, target: target.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil },
             breeze: breeze, terrain: terrain, random: random)
        if isFinite { good = snapshot } else { restore() }
    }

    /// Where a butterfly flying at `t` aims: `t` moved in from its screen's sides and top until the drawing fits
    /// there with half the turn zone to spare (the ground gives way to a low target, as the walls below do).
    private func aimPoint(_ t: SIMD2<Double>, _ terrain: Terrain) -> SIMD2<Double> {
        guard !terrain.rects.isEmpty else { return t }
        let r: CGRect = terrain.rects[terrain.rectIndex(near: t)]
        let m: Walls = margins.halfway(reach)
        let inX: Double = Butterfly.capped(m.side, r)
        let inY: Double = Butterfly.capped(m.top, r)
        var q: SIMD2<Double> = t
        let lo: Double = Double(r.minX) + inX, hi: Double = Double(r.maxX) - inX
        q.x = lo <= hi ? min(max(q.x, lo), hi) : Double(r.midX)
        q.y = max(q.y, min(Double(r.minY) + inY, Double(r.midY)))
        return q
    }

    private func step(_ dt: Double, target aimed: SIMD2<Double>?, breeze: Breeze, terrain: Terrain, random: WebRandom) {
        time += dt
        let target: SIMD2<Double>? = aimed.map { aimPoint($0, terrain) }
        let sp = species
        let span: Double = wingspan
        let drag: Double = ButterflySpecies.drag

        // ── How fast, and how fast it beats ──
        let base: Double = state == .approach || state == .cursor ? sp.forage : sp.cruise
        var speed: Double = base * scale * pace
        var beatMul: Double = beatFactor
        var climb: Double = 0
        if state == .flush {
            speed *= sp.escapeSpeed
            beatMul *= sp.escapeBeat
            climb = (sp.escapeClimb.lowerBound + sp.escapeClimb.upperBound) / 2
        }
        let wind: SIMD2<Double> = breeze.sample(x, y)
        let windSpeed: Double = simd_length(wind)
        if windSpeed > 0.3 * speed { beatMul *= 1.2 }   // gusts: beat +20 %
        let f: Double = min(3, sp.beat * beatMul)

        // ── Where it wants to go ──
        let p = SIMD2<Double>(x, y)
        var want: Double
        var far = true
        if let t = target {
            let d: SIMD2<Double> = t - p
            want = atan2(d.y, d.x)
            far = simd_length(d) > 6 * span
        } else {
            // Free flight: roam toward a waypoint, climbing at up to 22° or dropping at up to 30° to its height,
            // the heading's height wandering on slow value noise.
            waypointLeft -= dt
            // Reached within half a wingspan, so a waypoint near a wall is flown out to.
            if !hasWaypoint || waypointLeft <= 0 || simd_length(waypoint - p) < 0.5 * span {
                pickWaypoint(terrain, random, from: p, span: span, away: nil)
            }
            let d: SIMD2<Double> = waypoint - p
            let rise: Double = -d.y / span   // wingspans above
            var elevation: Double = rise > 0 ? min(rise, 1) * Butterfly.climb : max(rise, -1) * Butterfly.descend
            // Close below or above it, head straight for it (steeply, slowly) rather than circling.
            let bearing: Double = atan2(-d.y, abs(d.x))
            if abs(bearing) > abs(elevation) { elevation = clamp(bearing, -Butterfly.steepDown, Butterfly.steepUp) }
            elevation += Butterfly.wobble * noise1(time * 0.15, wander)
            let side: Double = d.x >= 0 ? 1 : -1
            want = atan2(-sin(elevation), side * cos(elevation))
        }
        if climb > 0 { want = tilted(want, climb) }
        if bound != 0 { want = tilted(want, bound * sp.boundAngle) }
        // Walls: a soft steer within a margin of an edge (the drawing's reach and a zone for the turn), and a push;
        // behind it a hard stop at the drawing's reach (`stop`).
        // Free flight meeting a wall turns as a correlated random walk: a new preferred direction drawn about the
        // wall's normal, and a waypoint along it. Flying at a target (a flower, the cursor), the ground starts no
        // higher than the target itself, so it never pushes a flower seeker off a flower one row tall; at the sides
        // and the top the target itself is moved in (`aimPoint`).
        let here: CGRect = terrain.rects.isEmpty ? terrain.bounds : terrain.rects[terrain.rectIndex(near: p)]
        var m: Walls = margins.capped(here)
        // The ground: no farther in than the target.
        if let t = target { m.bottom = max(1e-9, min(m.bottom, Butterfly.clearance(t, terrain))) }
        let push: SIMD2<Double> = self.push(p, terrain, m)
        let my: Double = push.y < 0 ? m.bottom : m.top
        let w = SIMD2<Double>(push.x / (7 * m.side), push.y / (7 * my))
        let pushing = push.x != 0 || push.y != 0
        if pushing {
            let sy: Double = sin(want) + 2 * w.y, sx: Double = cos(want) + 2 * w.x
            want = atan2(sy, sx)
            if target == nil && !wasPushing {
                pickWaypoint(terrain, random, from: p, span: span, away: atan2(push.y, push.x))
            }
        }
        wasPushing = pushing

        // ── Heading on a spring ──
        let glideAngle: Double = atan2(sin(sp.glideAngle), glideSense * cos(sp.glideAngle))
        let aim: Double = gliding ? glideAngle : want + jink
        jink *= exp(-dt / Butterfly.jinkRelax)
        let k: Double = sp.headingK
        let spring: Double = k * angleDiff(heading, aim)
        let damping: Double = 2 * sp.headingZeta * k.squareRoot() * turnRate
        turnRate += (spring - damping) * dt
        turnRate = clamp(turnRate, -Butterfly.maxTurn, Butterfly.maxTurn)
        heading = fmod(fmod(heading + turnRate * dt, TAU) + TAU, TAU)
        var hx: Double = cos(heading), hy: Double = sin(heading)

        // ── Wings and forces ──
        // Too far below its waypoint to glide (monarchs flap again 1–3 m above the ground).
        let low: Bool = target == nil && y > waypoint.y + 2 * span
        if gliding {
            glideLeft -= dt
            let turnedBack: Bool = cos(want) * glideSense < 0
            let interrupted: Bool = turnedBack || pushing || low || state != .fly || !far
            let ending: Bool = glideLeft <= 0 || (!held && interrupted)
            if ending {
                gliding = false
                held = false
                beatsLeft = random.int(sp.boutBeats.lowerBound, sp.boutBeats.upperBound)
            } else {
                let gx: Double = speed * glideSense * cos(sp.glideAngle), gy: Double = speed * sin(sp.glideAngle)
                let a: Double = min(1, ButterflySpecies.glideDrag * dt)
                ux += (gx - ux) * a
                uy += (gy - uy) * a
                stroke = glideStroke
                pitch *= max(0, 1 - 6 * dt)
            }
        }
        if !gliding {
            let before: Double = phase
            phase += TAU * f * dt
            let lift: Double = sp.lift * scale * (1 + 0.25 * bound)
            let thrust: Double = sp.thrust * speed
            if phase >= TAU {
                phase -= TAU
                claps += 1
                ux += thrust * hx
                uy += thrust * hy
                beatsLeft -= 1
                if beatsLeft <= 0 { armed = true }
                if sp.surge > 0 { pace = clamp(1 + sp.surge * gauss(random), 0.4, 1.6) }
                let near: Double = target == nil || far ? 1 : 0.3
                if random.unit() < sp.jinkChance { jink += gauss(random) * sp.jinkSigma * jinkFactor * near }
                if sp.boundAngle > 0 {
                    boundLeft -= 1
                    if boundLeft <= 0 {
                        // An abrupt change of height: the clap kicks the flight up or down by the whole change
                        // of tilt at once, heading and airspeed together.
                        bound = -bound
                        boundLeft = random.int(sp.boundBeats.lowerBound, sp.boundBeats.upperBound)
                        let side: Double = hx >= 0 ? 1 : -1
                        let kick: Double = -side * 2 * sp.boundAngle * bound
                        let c: Double = cos(kick), sn: Double = sin(kick)
                        (ux, uy) = (ux * c - uy * sn, ux * sn + uy * c)
                        heading = fmod(fmod(heading + kick, TAU) + TAU, TAU)
                        hx = cos(heading)
                        hy = sin(heading)
                    }
                }
            }
            let g: Double = glidePhase
            // Free flight glides down toward its waypoint's height: flap up, glide down (Gibo).
            let high: Bool = target != nil || y <= waypoint.y + 0.5 * span
            let canGlide = state == .fly && far && high && !pushing
            if armed && canGlide && before < g && phase >= g {
                startGlide(random.range(sp.glideSeconds.lowerBound, sp.glideSeconds.upperBound))
            } else {
                // Lift on the downstroke only, square to the stroke plane: the body pitches nose-down as the
                // wings come down, tipping the lift forward. Gravity always. Drag toward the wanted airspeed,
                // less the mean lurch and forward lift so the average stays at `speed`.
                let s: Double = sin(phase)
                pitch = -sp.pitchSwing * s
                var ax: Double = 0, ay: Double = sp.gravity * scale
                if s > 0 {
                    let side: Double = hx >= 0 ? 1 : -1
                    ax = lift * s * sin(-pitch) * side
                    ay -= lift * s * cos(pitch)
                }
                let v: Double = speed - (thrust * f + lift * sp.pitchSwing / 4) / drag
                ux += (ax - drag * (ux - v * hx)) * dt
                uy += (ay - drag * (uy - v * hy)) * dt
                stroke = sp.strokeMid + sp.strokeAmp * cos(phase)
            }
        }
        if pushing {
            ux += push.x * dt
            uy += push.y * dt
        }

        // ── Bank: into the turn, and leaning to a crosswind ──
        var lean: Double = tanh(turnRate / Butterfly.bankRate)
        if windSpeed > 0.3 * speed {
            lean += 0.5 * clamp((wind.y * hx - wind.x * hy) / max(speed, 1), -1, 1)
        }
        let bankTarget: Double = sp.maxBank * clamp(lean, -1, 1)
        bank += (bankTarget - bank) * min(1, Butterfly.bankFollow * dt)

        // ── Ground velocity = breeze + airspeed ──
        vx = ux + wind.x
        vy = uy + wind.y
        x += vx * dt
        y += vy * dt
        stop(at: terrain, here: here, target: target)
    }

    /// The hard edge behind the soft margin: a body nearer a screen's outer edge than its drawing reaches is set
    /// back to that reach and stops moving into the edge, so the drawing never leaves the screen. On a tiny screen
    /// the reach is capped as the margins are; a target's ground gives way to it as the soft margin does.
    private func stop(at terrain: Terrain, here: CGRect, target: SIMD2<Double>?) {
        var p = SIMD2<Double>(x, y)
        guard terrain.contains(p) else { return }
        // Only where the drawing fits: on a tiny screen the capped soft margin is all there is.
        let m: Walls = margins, d: Walls = reach
        let fitsX: Bool = Butterfly.capped(m.side, here) >= m.side
        let fitsY: Bool = Butterfly.capped(max(m.top, m.bottom), here) >= max(m.top, m.bottom)
        let side: Double = fitsX ? d.side : 0, top: Double = fitsY ? d.top : 0
        var bottom: Double = fitsY ? d.bottom : 0
        if let t = target { bottom = min(bottom, Butterfly.clearance(t, terrain)) }
        for e in terrain.edges {
            let n: SIMD2<Double> = e.normal
            // An edge's normal points inside: a floor's up (−y), a ceiling's down.
            let limit: Double = abs(n.x) > 0.5 ? side : (n.y < 0 ? bottom : top)
            let s: Double = simd_dot(p - e.a, n)
            guard s >= 0 && s < limit else { continue }
            let along: Double = simd_dot(p - e.a, (e.b - e.a) / max(e.length, 1e-12))
            guard along >= 0 && along <= e.length else { continue }
            p += n * (limit - s)
            let into: Double = ux * n.x + uy * n.y
            if into < 0 { ux -= into * n.x; uy -= into * n.y }
        }
        guard terrain.contains(p) else { return }
        x = p.x
        y = p.y
    }
}
