import Foundation

// Port of weaver.ts from ascii-spiders by @stackedlol (MIT), commit 89a7721.
// See docs/reference/web-port-notes.md for what differs and why.

/**
 * An orb weaver and its web, as one life:
 *
 *   build    walk the web's route, laying each thread as it goes
 *   idle     hang head-down at the hub; turn toward anything that tugs the silk
 *   hunt     run out along the nearest radial to a struggling fly
 *   wrap     circle it, swathing it in silk
 *   carry    take the bundle back to the hub and feed on it there
 *   eat      once the web is old, torn or has fed it enough, walk the route backwards, reeling it in
 *   move     shift a little and start again
 *
 * It glides rather than marches: speed eases in and out, brakes into sharp corners and for the end of a
 * run, and slows to touch each radial as the spiral goes down, so the build has a rhythm. Heading is
 * sprung, so the body swings into each turn. While it lays a thread it holds the loose end, so the new
 * silk doesn't swing about under it.
 */

private let DOWN = Double.pi / 2
// Laying speeds per kind of thread (px/s at a 300 px web); walking existing silk is faster. Unhurried:
// the easing, braking and sprung turns carry the smoothness, not the pace.
private let LAY_SPEED: [Double] = [0, 70, 66, 72, 42, 46, 38]
private let WALK = 80.0
private let HUNT = 85.0
private let CARRY = 60.0
private let WRAP = 3.6

public enum WeaverState: Sendable { case build, idle, hunt, wrap, carry, `return`, eat, move }

public final class Weaver: Silk {
    public let spider: Spider
    public var state: WeaverState = .build
    /// Where along the web's route it is.
    public var step = 0
    /// Current speed along the silk, eased.
    public var v = 0.0
    /// A short slowdown at each radial while the spiral goes down.
    public var tap = 0.0
    /// Node path out to prey and back, and how many of its waypoints are passed.
    public var path: [Int]? = nil
    public var wp = 0
    public var prey: Fly? = nil
    /// The meal hanging off the spinnerets at the hub.
    public var bundle: Fly? = nil
    public var catches = 0
    public var age = 0.0
    public var life: Double
    /// How strongly, and from where, something last tugged the silk.
    public var alert = 0.0
    public var alertDir = DOWN
    /// The node the thread being laid (or reeled in) runs from, or -1.
    public var partial = -1
    public var heading: Double? = nil
    public var goal = Vec(x: 0, y: 0)
    private var timer = 0.0
    private var spin = 0.0
    private var wrapFrom = Vec(x: 0, y: 0)
    unowned let world: WebWorld
    public let web: OrbWeb
    /// `Math.random()`: the world's shared stream.
    let random: WebRandom

    init(_ world: WebWorld, _ web: OrbWeb, _ kind: SpiderKind, _ size: Double? = nil) {
        let size = size ?? web.radius * 0.31
        self.world = world
        self.web = web
        random = world.random
        life = random.range(150, 260)
        spider = Spider(SpeciesKind(kind), size, random: random)
    }

    // `snap` and `land`: the original's two closures, as the Silk this weaver hands its spider.

    public func snap(_ x: Double, _ y: Double, _ r: Double) -> SilkHit? {
        guard let hit = web.snap(x, y, r) else { return nil }
        return SilkHit(web: web, link: hit.link, t: hit.t)
    }

    public func land(_ leg: Leg) { web.jolt(leg.link, leg.at, 0.1 * scale) }

    public var scale: Double { clamp(web.radius / 300, 0.5, 1.25) }

    /// Start partway through the route: 0 is a bare scaffold, route.length a finished web.
    public func startAt(_ step: Int) {
        let web = self.web
        let st: RouteStep? = step >= 0 && step < web.route.count ? web.route[step] : nil
        web.held = st.map { $0.lay ? $0.from : -1 } ?? -1
        web.buildInstant(step)
        if step >= web.route.count {
            state = .idle
            spider.place(Double(web.x[web.hub]), Double(web.y[web.hub]), DOWN, self)
            age = random.range(0, life * 0.4)
        } else {
            state = .build
            self.step = step
            let n = web.route[step].from
            let to = web.route[step].to
            spider.place(Double(web.x[n]), Double(web.y[n]),
                         atan2(Double(web.y[to]) - Double(web.y[n]), Double(web.x[to]) - Double(web.x[n])), self)
        }
    }

    /// Something tugged the silk at (x, y).
    public func feel(_ x: Double, _ y: Double, _ amount: Double) {
        if state != .idle { return }
        let web = self.web
        alert = min(1, alert + amount * 0.08)
        alertDir = atan2(y - Double(web.y[web.hub]), x - Double(web.x[web.hub]))
    }

    /// Walk the body toward (tx, ty). Returns the leftover distance once there, or -1 on the way.
    private func advance(_ tx: Double, _ ty: Double, _ dist: Double) -> Double {
        let sp = spider
        let dx = tx - sp.x
        let dy = ty - sp.y
        let d = hypot(dx, dy)
        if d > 1e-3 { heading = atan2(dy, dx) }
        if d <= dist {
            sp.x = tx
            sp.y = ty
            return dist - d
        }
        sp.x += (dx / d) * dist
        sp.y += (dy / d) * dist
        return -1
    }

    /**
     * The speed to aim for, heading to (tx, ty) and then on to (nx, ny): full speed on the straight, easing
     * down as a sharp corner (or the end of the run) comes up.
     */
    private func cruise(_ vmax: Double, _ tx: Double, _ ty: Double, _ nx: Double?, _ ny: Double?) -> Double {
        let sp = spider
        let d = hypot(tx - sp.x, ty - sp.y)
        var through = 0.0
        if let nx, let ny {
            let turn = abs(angleDiff(atan2(ty - sp.y, tx - sp.x), atan2(ny - ty, nx - tx)))
            through = 1 - min(1, turn / 2.2)
        }
        return vmax * lerp(0.2 + 0.8 * through, 1, clamp(d / (sp.B * 1.2), 0, 1))
    }

    /// Ease the current speed toward `vt`; the distance to cover this frame.
    private func pace(_ vt: Double, _ vmax: Double, _ dt: Double) -> Double {
        v += (vt - v) * (1 - exp(-dt * 4.5))
        return max(v, vmax * 0.06) * dt
    }

    /**
     * Glide through waypoints: pts(k) is the k-th one ahead ([x, y]), nil past the last. `self.wp` counts
     * the ones passed. Returns true at the end.
     */
    private func glide(_ dt: Double, _ vmax: Double, _ pts: (Int) -> (Double, Double)?) -> Bool {
        guard let a = pts(0) else { return true }
        let b = pts(1)
        var dist = pace(cruise(vmax, a.0, a.1, b?.0, b?.1), vmax, dt)
        while dist > 0 {
            guard let p = pts(0) else { return true }
            let left = advance(p.0, p.1, dist)
            if left < 0 { return false }
            dist = left
            wp += 1
        }
        return pts(0) == nil
    }

    public func update(_ dt: Double) {
        let sp = spider
        let web = self.web
        let px = sp.x
        let py = sp.y
        heading = nil
        partial = -1
        let s = scale

        switch state {
        case .build, .eat:
            let back = state == .eat
            let dir = back ? -1 : 1
            tap = max(0, tap - dt)
            let route = web.route
            if step >= 0 && step < route.count {
                let st = route[step]
                let to = back ? st.from : st.to
                let ns = step + dir
                let nn = ns >= 0 && ns < route.count ? (back ? route[ns].from : route[ns].to) : -1
                let vmax = (st.lay ? LAY_SPEED[web.kind[st.link]] : WALK) * s * (back ? 1.4 : 1) * (tap > 0 ? 0.35 : 1)
                var dist = pace(cruise(vmax, Double(web.x[to]), Double(web.y[to]),
                                       nn >= 0 ? Double(web.x[nn]) : nil, nn >= 0 ? Double(web.y[nn]) : nil), vmax, dt)
                while dist > 0 {
                    if step < 0 || step >= route.count { break }
                    let cur = route[step]
                    let target = back ? cur.from : cur.to
                    // Reeling in: the thread ahead is taken up as the spider walks it.
                    if back && cur.lay && web.isLaid(cur.link) { web.cut(cur.link) }
                    let left = advance(Double(web.x[target]), Double(web.y[target]), dist)
                    if left < 0 {
                        // The thread still to lay (or still to reel in) runs from the last node to the body.
                        if cur.lay { partial = cur.from }
                        break
                    }
                    dist = left
                    if !back && cur.lay {
                        web.lay(cur.link)
                        // A touch at each radial while the sticky spiral goes down.
                        if web.kind[cur.link] == SPIRAL { tap = 0.1 }
                    }
                    step += dir
                }
            }
            // Hold the loose end while laying, so the new thread doesn't swing about under the spider.
            web.held = !back && partial >= 0 && web.deg[partial] <= 1 ? partial : -1
            if !back && step >= route.count {
                state = .idle
                age = 0
                catches = 0
            } else if back && step < 0 {
                state = .move
                relocate()
            }

        case .move:
            wp = 0
            let goal = self.goal
            // The original's `k === 0` never lets the goal pass: arrived with distance to spare, glide's loop
            // walks to it forever and the page hangs. Counted from `wp`, as hunt, carry and return count.
            if glide(dt, WALK * 0.7 * s, { k in self.wp + k == 0 ? (goal.x, goal.y) : nil }) {
                state = .build
                step = 0
            }

        case .idle:
            age += dt
            let hx = Double(web.x[web.hub])
            let hy = Double(web.y[web.hub])
            // Lean a little toward a tug, then settle.
            alert = max(0, alert - dt * 0.7)
            let lean = sp.B * 0.14 * alert
            sp.x = hx + cos(alertDir) * lean
            sp.y = hy + sin(alertDir) * lean
            heading = DOWN + clamp(angleDiff(DOWN, alertDir), -1, 1) * alert
            sp.reach = alert > 0.3 ? Reach(dir: alertDir, amount: alert) : nil
            if let fly = web.prey.first(where: { $0.mode == .stuck && $0.web === web && $0.gen == web.gen }) {
                prey = fly
                fly.hunted = true
                path = web.pathToward(fly.x, fly.y)
                wp = 1
                state = .hunt
                sp.reach = nil
            } else if bundle == nil && !web.prey.contains(where: { $0.mode == .stuck }) &&
                (catches >= 3 || web.damage > 0.22 || age > life) {
                state = .eat
                step = web.route.count - 1
                sp.reach = nil
            }

        case .hunt, .carry:
            guard let fly = prey, !(state == .hunt && fly.mode != .stuck) else {
                // It got away.
                prey = nil
                path = Array((path ?? [web.hub]).prefix(max(1, wp)).reversed())
                wp = 0
                state = .return
                break
            }
            let hunting = state == .hunt
            let path = self.path ?? [web.hub]
            let done = glide(dt, (hunting ? HUNT : CARRY) * s) { k in
                let i = self.wp + k
                if i < path.count { return (Double(web.x[path[i]]), Double(web.y[path[i]])) }
                if i == path.count { return hunting ? (fly.x, fly.y) : (Double(web.x[web.hub]), Double(web.y[web.hub])) }
                return nil
            }
            if done {
                if hunting {
                    state = .wrap
                    timer = WRAP
                    spin = atan2(sp.y - fly.y, sp.x - fly.x)
                    wrapFrom = Vec(x: sp.x, y: sp.y)
                } else {
                    // A meal already on the go is finished off as the new one is hung up.
                    if let bundle { bundle.mode = .gone; bundle.respawn = random.range(2, 6) }
                    fly.mode = .held
                    bundle = fly
                    prey = nil
                    catches += 1
                    state = .idle
                }
            }
            if state == .carry { tow(prey, dt) }

        case .return:
            let path = self.path ?? [web.hub]
            if glide(dt, CARRY * s, { k in
                self.wp + k < path.count ? (Double(web.x[path[self.wp + k]]), Double(web.y[path[self.wp + k]])) : nil
            }) { state = .idle }

        case .wrap:
            guard let fly = prey else {
                state = .idle
                break
            }
            timer -= dt
            // Turn the parcel round under the legs, paying out silk: the circling eases in and out.
            let k = 1 - timer / WRAP
            spin += dt * 1.3 * pow(sin(Double.pi * clamp(k, 0, 1)), 0.6)
            let r = sp.B * 0.28 * clamp(k * 4, 0, 1)
            sp.x = lerp(wrapFrom.x, fly.x, clamp(k * 4, 0, 1)) + cos(spin) * r
            sp.y = lerp(wrapFrom.y, fly.y, clamp(k * 4, 0, 1)) + sin(spin) * r
            heading = atan2(fly.y - sp.y, fly.x - sp.x)
            fly.wrap = 1 - timer / WRAP
            if random.unit() < dt * 4 { web.jolt(fly.link, fly.at, 0.25 * s) }
            if timer <= 0 {
                if let i = web.prey.firstIndex(where: { $0 === fly }) { web.prey.remove(at: i) }
                fly.web = nil
                fly.mode = .wrapped
                path = (path ?? [web.hub]).reversed()
                wp = 0
                v = 0
                state = .carry
            }
        }

        // Feeding at the hub: the bundle hangs off the spinnerets and shrinks.
        if let bundle {
            tow(bundle, dt)
            bundle.digest += dt / 18
            if bundle.digest >= 1 {
                bundle.mode = .gone
                bundle.respawn = random.range(2, 6)
                self.bundle = nil
            }
        }

        sp.vx = (sp.x - px) / max(dt, 1e-4)
        sp.vy = (sp.y - py) / max(dt, 1e-4)
        if let heading { sp.steer(heading, dt, state == .idle ? 34 : 64) }
        sp.updateLegs(dt, self)
    }

    /// The parcel trails the spinnerets on a short line.
    private func tow(_ f: Fly?, _ dt: Double) {
        guard let f else { return }
        let sp = spider
        let tmp = sp.spinneret()
        let back = sp.B * 0.16
        let tx = tmp.x - cos(sp.h) * back
        let ty = tmp.y - sin(sp.h) * back
        let k = min(1, dt * 12)
        f.x += (tx - f.x) * k
        f.y += (ty - f.y) * k
    }

    /// After eating the web: a new site close by, and the route's first corner to walk to.
    private func relocate() {
        let web = self.web
        let R = web.radius
        let j = web.frame != nil ? 0.06 : 1
        let x = web.home.x + random.range(-0.18, 0.18) * R * j
        let y = web.home.y + random.range(-0.14, 0.14) * R * j
        if world.single {
            let W = world.width, H = world.height
            web.cx = clamp(x, R * 0.4, W - R * 0.4)
            web.cy = clamp(y, R * 0.4, H - R * 0.4)
        } else {
            // Several screens: the new site stays on the web's own screen, its frame inside it (as laid out).
            let r = world.screen(near: web.home.x, web.home.y)
            let m = max(R * 0.4, R * FRAME_REACH)
            web.cx = fitClamp(x, r.minX + m, r.maxX - m)
            web.cy = fitClamp(y, r.minY + m, r.maxY - m)
        }
        web.generate(Vec(x: spider.x, y: spider.y))
        web.gen += 1
        let n = web.route[0].from
        goal = Vec(x: Double(web.x[n]), y: Double(web.y[n]))
        life = random.range(150, 260)
    }

    /// The spider's weight, through every foot on silk.
    public func weigh() {
        let sp = spider
        let w = (sp.B / 90) * 0.05
        for leg in sp.legs where leg.planted {
            if let web = leg.web { web.load(leg.link, leg.at, w) }
        }
    }
}
