import Foundation

// Port of spider.ts from ascii-spiders by @stackedlol (MIT), commit 89a7721.
// See docs/reference/web-port-notes.md for what differs and why.

/**
 * A spider seen from above: prosoma and abdomen as ellipses, eight two-bone legs, and a tetrapod gait.
 *
 * Feet are planted in the world and only move when they step. A foot steps once its rest spot (where it
 * would sit relative to the body) drifts too far, and only while its neighbours stand, so the legs fall
 * into the alternating L1 R2 L3 R4 / R1 L2 R3 L4 rhythm without being told to. On a web, each step lands
 * on the nearest thread and the foot then rides that thread as the silk moves.
 *
 * What makes it move well: heading is sprung, so turns swing and settle; strides are long, eased in and
 * out, and arc outward as the foot lifts; never more than four legs are off the silk at once, and a long
 * stride takes longer, so the feet reach rather than flick; the body leans toward the feet it stands on,
 * so it sways in time with the gait; the abdomen breathes; at rest a foot now and then lets go and
 * re-grips; and a tug on the silk brings a foreleg up toward it.
 */

private let D = Double.pi / 180

/// The orb weavers.
public enum SpiderKind: String, Codable, CaseIterable, Sendable {
    case araneus, argiope, nephila

    /// The original ascii-spiders `DEFAULT_SPIDERS`, bottom-left first.
    public static let defaultCast: [SpiderKind] = [.araneus, .nephila, .argiope, .nephila, .araneus, .argiope]
}

/// Every body the renderer knows, the jumping spider included.
public enum SpeciesKind: String, Sendable {
    case araneus, argiope, nephila, jumper

    public init(_ kind: SpiderKind) {
        switch kind {
        case .araneus: self = .araneus
        case .argiope: self = .argiope
        case .nephila: self = .nephila
        }
    }
}

public enum SpeciesPattern: Sendable { case cross, bands, spots, jumper }

public struct Species: Sendable {
    /// Half-length and half-width, in body lengths.
    public let prosoma: [Double]
    public let abdomen: [Double]
    /// Leg lengths, front pair first, in body lengths.
    public let legLen: [Double]
    /// Degrees from the heading: where each hip sits round the prosoma, and where each foot rests.
    public let hip: [Double]
    public let rest: [Double]
    /// How far out each foot rests, as a fraction of its leg.
    public let reach: [Double]
    public let pattern: SpeciesPattern
    public let tint: [Double]
    /// Leg shade, and how much darker the banded half of each segment is.
    public let leg: Double
    public let band: Double
    /// A rounded-box prosoma, and the jumper's great front eyes.
    public let boxy: Bool
    public let eyes: Bool

    init(prosoma: [Double], abdomen: [Double], legLen: [Double], hip: [Double], rest: [Double], reach: [Double],
         pattern: SpeciesPattern, tint: [Double], leg: Double, band: Double, boxy: Bool = false, eyes: Bool = false) {
        self.prosoma = prosoma
        self.abdomen = abdomen
        self.legLen = legLen
        self.hip = hip
        self.rest = rest
        self.reach = reach
        self.pattern = pattern
        self.tint = tint
        self.leg = leg
        self.band = band
        self.boxy = boxy
        self.eyes = eyes
    }
}

/**
 * Proportions are fractions of the body length B. Angles are degrees from the heading: hips round the
 * prosoma, and where each foot rests. Leg lengths are in body lengths, front pair first.
 */
public let SPECIES: [SpeciesKind: Species] = [
    // European garden spider: a round abdomen marked with a pale cross, legs I and II long and forward.
    .araneus: Species(
        prosoma: [0.18, 0.15], abdomen: [0.32, 0.29],
        legLen: [1.5, 1.38, 0.95, 1.3], hip: [34, 68, 106, 142],
        rest: [26, 60, 108, 152], reach: [0.86, 0.82, 0.74, 0.84],
        pattern: .cross, tint: [1.1, 0.96, 0.8], leg: 176, band: 0.16),
    // Wasp spider: a long banded abdomen, legs held in pairs so the spider makes an X on its zigzag.
    .argiope: Species(
        prosoma: [0.16, 0.14], abdomen: [0.36, 0.22],
        legLen: [1.55, 1.45, 0.9, 1.35], hip: [32, 62, 112, 146],
        rest: [16, 28, 140, 158], reach: [0.9, 0.88, 0.78, 0.9],
        pattern: .bands, tint: [1.12, 1.02, 0.66], leg: 184, band: 0.45),
    // Golden orb weaver: a long slim abdomen and very long thin legs.
    .nephila: Species(
        prosoma: [0.15, 0.12], abdomen: [0.4, 0.15],
        legLen: [1.95, 1.7, 0.9, 1.6], hip: [34, 66, 108, 144],
        rest: [22, 52, 112, 158], reach: [0.88, 0.84, 0.76, 0.88],
        pattern: .spots, tint: [1.08, 1.0, 0.82], leg: 176, band: 0.3),
    // Jumping spider: a boxy prosoma with two huge front eyes, a short abdomen, short stout legs.
    .jumper: Species(
        prosoma: [0.26, 0.22], abdomen: [0.25, 0.2],
        legLen: [0.98, 0.8, 0.82, 0.96], hip: [30, 66, 110, 148],
        rest: [24, 70, 116, 160], reach: [0.8, 0.82, 0.82, 0.84],
        pattern: .jumper, tint: [0.94, 0.97, 1.06], leg: 160, band: 0.22, boxy: true, eyes: true),
]

/// Where a foot found silk: which web, which thread, how far along it.
public struct SilkHit {
    public var web: OrbWeb?
    public var link: Int
    public var t: Double
    public init(web: OrbWeb?, link: Int, t: Double) { self.web = web; self.link = link; self.t = t }
}

/// The original's `snap` and `land` callbacks (the weaver passes both), as one object, so a step builds
/// no closures. `snap` finds silk near (x, y) within r, nil off the web; `land` is told about each foot
/// that lands, so the web can feel it.
public protocol Silk: AnyObject {
    func snap(_ x: Double, _ y: Double, _ r: Double) -> SilkHit?
    func land(_ leg: Leg)
}

public struct Leg {
    /// -1 left, 1 right; 0 is the front pair.
    public let side: Double
    public let i: Int
    public let L: Double
    public let femur: Double
    public let tibia: Double
    public let hipA: Double
    public let restA: Double
    public let reach: Double
    /// The foot, where a step started, and where it is headed.
    public var fx = 0.0
    public var fy = 0.0
    public var sx = 0.0
    public var sy = 0.0
    public var tx = 0.0
    public var ty = 0.0
    public var t = 1.0
    public var dur = 0.12
    public var planted = true
    public var raised = false
    /// The thread the foot holds, and the one it is stepping to.
    public var web: OrbWeb? = nil
    public var link = -1
    public var at = 0.0
    public var toWeb: OrbWeb? = nil
    public var toLink = -1
    public var toAt = 0.0
    /// Hip and knee, solved for drawing.
    public var hx = 0.0
    public var hy = 0.0
    public var kx = 0.0
    public var ky = 0.0
    /// Neighbours this foot waits for before it steps: one bit per index into `legs`.
    public var wait: UInt8 = 0

    init(side: Double, i: Int, L: Double, femur: Double, tibia: Double, hipA: Double, restA: Double, reach: Double) {
        self.side = side
        self.i = i
        self.L = L
        self.femur = femur
        self.tibia = tibia
        self.hipA = hipA
        self.restA = restA
        self.reach = reach
    }
}

/// A foreleg raised toward a tug.
public struct Reach {
    public var dir: Double
    public var amount: Double
    public init(dir: Double, amount: Double) { self.dir = dir; self.amount = amount }
}

public final class Spider {
    public let kind: SpeciesKind
    public let sp: Species
    /// Body length in px.
    public let B: Double
    /// Where the body is carried (on the thread, or on the wall).
    public var x = 0.0
    public var y = 0.0
    public var h = Double.pi / 2
    /// Turning speed: heading is sprung, so it swings into turns and settles instead of snapping.
    public var hv = 0.0
    public var vx = 0.0
    public var vy = 0.0
    /// Weight shift: the body leans toward the feet it stands on, so it sways with the gait.
    public var dx = 0.0
    public var dy = 0.0
    /// Drawn scale: a jumper crouches, and grows a touch in the air, as if nearer.
    public var scale = 1.0
    /// The abdomen rises and falls.
    public var breath = 1.0
    /// Feet follow the body instead of stepping (mid-jump).
    public var airborne = false
    /// Raise a foreleg toward a tug.
    public var reach: Reach? = nil
    public var still = 0.0
    public var t: Double
    public let id: Int
    public private(set) var legs: [Leg] = []
    /// `Math.random()`: the world's shared stream.
    let random: WebRandom

    public init(_ kind: SpeciesKind, _ B: Double, random: WebRandom) {
        self.random = random
        t = random.unit() * 10
        id = Int(floor(random.unit() * 1e6))
        self.kind = kind
        self.sp = SPECIES[kind]!
        self.B = B
        let sp = self.sp
        for side in [-1.0, 1.0] {
            for i in 0..<4 {
                let L = sp.legLen[i] * B
                legs.append(Leg(side: side, i: i, L: L, femur: L * 0.46, tibia: L * 0.56,
                                hipA: sp.hip[i] * D, restA: sp.rest[i] * D, reach: sp.reach[i] * L))
            }
        }
        // Neighbours a foot waits for: same side front and back, and its opposite number.
        for (n, leg) in legs.enumerated() {
            var wait: UInt8 = 0
            for (k, o) in legs.enumerated() where k != n {
                if (o.side == leg.side && abs(o.i - leg.i) == 1) || (o.side != leg.side && o.i == leg.i) { wait |= 1 << UInt8(k) }
            }
            legs[n].wait = wait
        }
    }

    /// The drawn body position: the carried one plus the weight shift.
    public var rx: Double { x + dx }
    public var ry: Double { y + dy }

    public var prosomaU: Double { sp.prosoma[0] * B * 0.92 }
    public var abdomenU: Double { -sp.abdomen[0] * B * 0.95 }

    /// Body frame → world: u forward, v to the spider's right. `shifted` uses the drawn position.
    @inline(__always) public func toWorld(_ u: Double, _ v: Double, _ shifted: Bool = false) -> Vec {
        let c = cos(h)
        let s = sin(h)
        return Vec(x: (shifted ? rx : x) + u * c - v * s, y: (shifted ? ry : y) + u * s + v * c)
    }

    /// Spinnerets: the tip of the abdomen, where silk comes out.
    public func spinneret() -> Vec {
        toWorld((abdomenU - sp.abdomen[0] * B * 0.92) * scale, 0, true)
    }

    @inline(__always) public func hipLocal(_ leg: Int) -> (u: Double, v: Double) {
        let pa = sp.prosoma[0], pb = sp.prosoma[1]
        let l = legs[leg]
        return (u: prosomaU + cos(l.hipA) * pa * B * 0.72, v: l.side * sin(l.hipA) * pb * B * 0.86)
    }

    @inline(__always) public func restWorld(_ leg: Int, _ tuck: Double = 1) -> Vec {
        let hip = hipLocal(leg)
        let l = legs[leg]
        let r = l.reach * tuck
        return toWorld(hip.u + cos(l.restA) * r, hip.v + l.side * sin(l.restA) * r)
    }

    /// Put the spider down with every foot at rest (and on silk, given a snap).
    public func place(_ x: Double, _ y: Double, _ h: Double, _ snap: Silk? = nil) {
        self.x = x
        self.y = y
        self.h = h
        hv = 0
        vx = 0
        vy = 0
        for n in legs.indices {
            let w = restWorld(n)
            legs[n].fx = w.x
            legs[n].fy = w.y
            legs[n].planted = true
            legs[n].t = 1
            legs[n].web = nil
            legs[n].link = -1
            if let snap { grip(n, snap, w.x, w.y, legs[n].L * 0.5, true) }
        }
    }

    /// Find silk for a foot near (x, y). When `now`, the foot moves there at once.
    @discardableResult
    public func grip(_ leg: Int, _ snap: Silk, _ x: Double, _ y: Double, _ r: Double, _ now: Bool) -> Bool {
        let hit = snap.snap(x, y, r)
        guard let hit, let web = hit.web else {
            legs[leg].toLink = -1
            if now { legs[leg].web = nil; legs[leg].link = -1 }
            return false
        }
        legs[leg].toWeb = web
        legs[leg].toLink = hit.link
        legs[leg].toAt = hit.t
        if now {
            legs[leg].web = web
            legs[leg].link = hit.link
            legs[leg].at = hit.t
            let p = web.pos(hit.link, hit.t)
            legs[leg].fx = p.x
            legs[leg].fy = p.y
        }
        return true
    }

    /// Turn toward `target` on a spring: it swings into the turn and settles without snapping.
    public func steer(_ target: Double, _ dt: Double, _ k: Double = 70) {
        let c = 2 * k.squareRoot() * 0.92
        hv += (k * angleDiff(h, target) - c * hv) * dt
        hv = clamp(hv, -6, 6)
        h = fmod(fmod(h + hv * dt, TAU) + TAU, TAU)
    }

    /// Lift a foot and send it to (tx, ty), landing on silk if there is any.
    public func stepTo(_ leg: Int, _ tx: Double, _ ty: Double, _ dur: Double, _ snap: Silk?, _ grip: Bool = true) {
        legs[leg].sx = legs[leg].fx
        legs[leg].sy = legs[leg].fy
        legs[leg].tx = tx
        legs[leg].ty = ty
        legs[leg].toLink = -1
        if let snap, grip { self.grip(leg, snap, tx, ty, legs[leg].L * 0.42, false) }
        legs[leg].t = 0
        legs[leg].dur = dur
        legs[leg].planted = false
        legs[leg].web = nil
    }

    /**
     * Move the feet for this frame. `snap.snap(x, y, r)` finds silk (or nil off the web); `snap.land(leg)` is
     * told about each foot that lands, so the web can feel it.
     */
    public func updateLegs(_ dt: Double, _ snap: Silk? = nil) {
        t += dt
        breath = 1 + 0.035 * sin(t * 1.9 + Double(id % 7))
        let speed = hypot(vx, vy)
        still = speed < 4 ? still + dt : 0
        var stepping = 0
        for n in legs.indices where !legs[n].planted { stepping += 1 }
        // A foreleg raised toward a tug, on the side it came from.
        let reach = self.reach
        var raise = -1
        if let reach, reach.amount > 0.25 {
            let side = sin(reach.dir - h) >= 0 ? 1.0 : -1.0
            raise = legs.firstIndex { $0.i == 0 && $0.side == side } ?? -1
        }

        for n in legs.indices {
            if airborne {
                let w = restWorld(n, legs[n].i < 2 ? 0.85 : 0.6)
                legs[n].fx = w.x
                legs[n].fy = w.y
                legs[n].planted = true
                legs[n].t = 1
                legs[n].web = nil
                legs[n].link = -1
                continue
            }
            if legs[n].planted {
                if let web = legs[n].web {
                    if web.isLaid(legs[n].link) {
                        let p = web.pos(legs[n].link, legs[n].at)
                        legs[n].fx = p.x
                        legs[n].fy = p.y
                    } else { legs[n].web = nil }
                }
                if n == raise, let reach {
                    // Held up and out toward the tug, testing the silk.
                    let hip = hipLocal(n)
                    let w = toWorld(hip.u, hip.v)
                    let L = legs[n].L
                    let tx = w.x + cos(reach.dir) * L * 0.92
                    let ty = w.y + sin(reach.dir) * L * 0.92
                    if !legs[n].raised || hypot(legs[n].fx - tx, legs[n].fy - ty) > L * 0.2 { stepTo(n, tx, ty, 0.22, nil, false) }
                    legs[n].raised = true
                    continue
                }
                let w = restWorld(n)
                let L = legs[n].L
                let err = hypot(legs[n].fx - w.x, legs[n].fy - w.y)
                let moving = still == 0
                let threshold = legs[n].raised ? 0 : moving ? L * 0.34 : L * 0.15
                let wait = legs[n].wait
                var ready = true
                for k in legs.indices where wait & (1 << UInt8(k)) != 0 && !legs[k].planted { ready = false; break }
                let desperate = err > L * 0.85
                // At rest, tidy one foot at a time; on the move, any foot whose neighbours stand.
                // Never more than half the legs in the air, so the body always stands on four (a tetrapod gait).
                if err > threshold && stepping < 4 && (desperate || (ready && (moving || (stepping == 0 && still > 0.2)))) {
                    // Long, unhurried strides: the foot reaches well ahead of where the body is going.
                    var dur = clamp(L / (speed * 1.3 + L * 2.8), 0.14, 0.34)
                    var tx = w.x
                    var ty = w.y
                    if speed > 1 {
                        let lead = dur * 1.1 + (L * 0.26) / max(speed, 40)
                        tx += vx * lead
                        ty += vy * lead
                    }
                    // A long stride takes longer: the foot never whips across faster than about three leg lengths
                    // a second, so catching up after a turn reads as a reach, not a flick.
                    dur = clamp(max(dur, hypot(tx - legs[n].fx, ty - legs[n].fy) / (L * 3)), 0.14, 0.5)
                    legs[n].raised = false
                    stepTo(n, tx, ty, dur, snap)
                    stepping += 1
                }
            } else {
                legs[n].t = min(1, legs[n].t + dt / legs[n].dur)
                var tx = legs[n].tx
                var ty = legs[n].ty
                if legs[n].toLink >= 0, let toWeb = legs[n].toWeb {
                    if toWeb.isLaid(legs[n].toLink) {
                        let p = toWeb.pos(legs[n].toLink, legs[n].toAt)
                        tx = p.x
                        ty = p.y
                    } else { legs[n].toLink = -1 }
                }
                // Ease in and out, and arc outward as the foot lifts, so each step reads as a reach.
                let lt = legs[n].t
                let e = 0.5 - 0.5 * cos(Double.pi * lt)
                let lift = sin(Double.pi * lt)
                var fx = lerp(legs[n].sx, tx, e)
                var fy = lerp(legs[n].sy, ty, e)
                let ox = fx - x
                let oy = fy - y
                let ol = jsOr(hypot(ox, oy), 1)
                fx += (ox / ol) * lift * legs[n].L * 0.1
                fy += (oy / ol) * lift * legs[n].L * 0.1
                legs[n].fx = fx
                legs[n].fy = fy
                if lt >= 1 {
                    legs[n].planted = true
                    if legs[n].toLink >= 0, let toWeb = legs[n].toWeb {
                        legs[n].web = toWeb
                        legs[n].link = legs[n].toLink
                        legs[n].at = legs[n].toAt
                        snap?.land(legs[n])
                    }
                }
            }
        }
        if raise == -1 { for n in legs.indices where legs[n].raised && legs[n].planted { legs[n].raised = false } }

        // Now and then, at rest, one foot lets go and takes a fresh grip.
        if !airborne && still > 1.4 && stepping == 0 && random.unit() < dt * 0.35 {
            let n = Int(floor(random.unit() * 8))
            if !legs[n].raised {
                let w = restWorld(n)
                let a = random.unit() * TAU
                let L = legs[n].L
                stepTo(n, w.x + cos(a) * L * 0.07, w.y + sin(a) * L * 0.07, 0.2, snap)
            }
        }

        // Weight shift toward the feet on the ground: the body sways in time with the gait.
        var px = 0.0
        var py = 0.0
        var rx = 0.0
        var ry = 0.0
        var n = 0
        for k in legs.indices {
            if !legs[k].planted || legs[k].raised { continue }
            let w = restWorld(k)
            px += legs[k].fx
            py += legs[k].fy
            rx += w.x
            ry += w.y
            n += 1
        }
        var tx = 0.0
        var ty = 0.0
        if n != 0 && !airborne {
            tx = ((px - rx) / Double(n)) * 0.22
            ty = ((py - ry) / Double(n)) * 0.22
            let m = hypot(tx, ty)
            let cap = B * 0.07
            if m > cap { tx *= cap / m; ty *= cap / m }
        }
        let k = 1 - exp(-dt * 9)
        dx += (tx - dx) * k
        dy += (ty - dy) * k
    }

    /// Hips and knees for drawing: each knee bends away from the body's midline.
    public func solve() {
        let bx = rx
        let by = ry
        for n in legs.indices {
            let hip = hipLocal(n)
            let w = toWorld(hip.u * scale, hip.v * scale, true)
            legs[n].hx = w.x
            legs[n].hy = w.y
            let a = legs[n].femur * scale
            let b = legs[n].tibia * scale
            let dx = legs[n].fx - legs[n].hx
            let dy = legs[n].fy - legs[n].hy
            let d0 = jsOr(hypot(dx, dy), 1e-3)
            let d = clamp(d0, abs(a - b) + 1e-3, a + b - 1e-3)
            let base = atan2(dy, dx)
            let A = acos(clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1))
            // Of the two knees, take the one further out on the leg's own side.
            let rx = -sin(h)
            let ry = cos(h)
            let k1x = legs[n].hx + cos(base + A) * a
            let k1y = legs[n].hy + sin(base + A) * a
            let k2x = legs[n].hx + cos(base - A) * a
            let k2y = legs[n].hy + sin(base - A) * a
            let o1 = legs[n].side * ((k1x - bx) * rx + (k1y - by) * ry)
            let o2 = legs[n].side * ((k2x - bx) * rx + (k2y - by) * ry)
            legs[n].kx = o1 >= o2 ? k1x : k2x
            legs[n].ky = o1 >= o2 ? k1y : k2y
        }
    }

    /// Turn toward `target` heading (sprung; `rate` sets how firmly).
    public func turnToward(_ target: Double, _ rate: Double, _ dt: Double) {
        steer(target, dt, rate * rate * 1.2)
    }
}

/// JavaScript's `v || d` for a number: 0 and NaN are falsy.
@inline(__always) func jsOr(_ v: Double, _ d: Double) -> Double { v == 0 || v.isNaN ? d : v }
