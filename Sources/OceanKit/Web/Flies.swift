import Foundation

// Port of flies.ts from ascii-spiders by @stackedlol (MIT), commit 89a7721.
// See docs/reference/web-port-notes.md for what differs and why.

/**
 * Flies: the prey. Each wanders on smooth noise with the odd dart, shies from the cursor, now and then lands
 * to rest, and blunders into webs. Crossing a thread of capture spiral may stick it there; a stuck fly
 * struggles, shaking the silk so the spider feels where it is, and tears free if left long enough.
 *
 * mode: fly · rest · stuck · wrapped (carried) · held (being eaten at the hub) · gone (waiting to respawn)
 */

private let STICK = 0.07

public enum FlyMode: Sendable { case fly, rest, stuck, wrapped, held, gone }

public final class Fly {
    public var x: Double
    public var y: Double
    /// Where it was last frame, so a web can tell whether it crossed a thread.
    public var ox: Double
    public var oy: Double
    public var h: Double
    public var v: Double
    public let seed: Double
    public var phase: Double
    public let depth: Double
    public var mode: FlyMode = .fly
    public var timer = 0.0
    /// The opening catch: a point on a web it flies straight for, and the web that takes it.
    public var aim: Vec? = nil
    public weak var aimWeb: OrbWeb? = nil
    /// Stuck: which web, which of its builds, which thread, how far along.
    public weak var web: OrbWeb? = nil
    public var gen = 0
    public var link = -1
    public var at = 0.0
    /// How far the spider has wrapped it, and how far it has been eaten.
    public var wrap = 0.0
    public var digest = 0.0
    public var hunted = false
    public var respawn = 0.0
    /// Seconds left before a stuck fly tears free.
    public var escape = 0.0
    /// `Math.random()`: the world's shared stream.
    let random: WebRandom

    public init(_ x: Double, _ y: Double, random: WebRandom) {
        self.random = random
        h = random.range(0, TAU)
        v = random.range(60, 120)
        seed = Double(random.int(1, 100_000))
        phase = random.range(0, TAU)
        depth = random.range(0.55, 1)
        self.x = x
        self.ox = x
        self.y = y
        self.oy = y
    }

    public func free(_ speed: Double = 220) {
        if let web {
            if let i = web.prey.firstIndex(where: { $0 === self }) { web.prey.remove(at: i) }
        }
        mode = .fly
        web = nil
        hunted = false
        wrap = 0
        v = speed
        h = random.range(0, TAU)
    }

    public func stick(_ web: OrbWeb, _ link: Int, _ at: Double) {
        mode = .stuck
        self.web = web
        gen = web.gen
        self.link = link
        self.at = at
        aim = nil
        hunted = false
        wrap = 0
        digest = 0
        timer = 0
        escape = random.range(16, 26)
        web.prey.append(self)
        web.jolt(link, at, 3)
    }
}

public final class Swarm {
    public private(set) var flies: [Fly] = []
    unowned let world: WebWorld

    init(_ world: WebWorld) { self.world = world }

    public func populate(_ n: Int) {
        let W = world.width, H = world.height
        let random = world.random
        flies = []
        for _ in 0..<max(0, n) {
            if world.single {
                // Arguments are evaluated left to right, as in `new Fly(rand(…) * W, rand(…) * H)`.
                let x = random.range(0.05, 0.95) * W
                let y = random.range(0.1, 0.9) * H
                flies.append(Fly(x, y, random: random))
            } else {
                let r = world.screenByArea()
                let x = r.minX + random.range(0.05, 0.95) * r.w
                let y = r.minY + random.range(0.1, 0.9) * r.h
                flies.append(Fly(x, y, random: random))
            }
        }
    }

    /// A fly let loose at the pointer; dropped onto silk, it is caught there.
    @discardableResult
    public func release(_ x: Double, _ y: Double) -> Fly {
        let random = world.random
        var f = flies.first { $0.mode == .gone }
        if f == nil {
            if flies.count >= 26 { f = flies.first { $0.mode == .fly || $0.mode == .rest } }
            if f == nil {
                let n = Fly(x, y, random: random)
                flies.append(n)
                f = n
            }
        }
        let fly = f!
        if fly.web != nil { fly.free() }
        fly.x = x
        fly.ox = x
        fly.y = y
        fly.oy = y
        fly.mode = .fly
        fly.v = random.range(140, 200)
        fly.h = random.range(0, TAU)
        let w = world
        for web in w.webs.reversed() {
            if let hit = web.snap(x, y, w.cw * 0.9), web.kind[hit.link] == SPIRAL {
                fly.stick(web, hit.link, hit.t)
                return fly
            }
        }
        return fly
    }

    public func update(_ dt: Double) {
        let w = world
        let W = w.width, H = w.height, t = w.time, pointer = w.pointer
        let random = w.random
        for f in flies {
            f.phase += dt
            switch f.mode {
            case .fly:
                fly(f, dt, W, H, t, pointer)
            case .rest:
                f.timer -= dt
                if f.timer <= 0 || (pointer.active && hypot(pointer.x - f.x, pointer.y - f.y) < 90) { f.free(200) }
            case .stuck:
                guard let web = f.web, web.gen == f.gen, web.isLaid(f.link) else {
                    f.free()
                    break
                }
                let p = web.pos(f.link, f.at)
                f.x = p.x
                f.y = p.y
                if f.wrap > 0 { break }
                f.timer -= dt
                if f.timer <= 0 {
                    web.jolt(f.link, f.at, random.range(1, 2.6) * (web.radius / 300))
                    f.timer = random.range(0.06, 0.45)
                }
                if !f.hunted { f.escape -= dt }
                if f.escape <= 0 {
                    web.cut(f.link, true)
                    f.free(260)
                }
            case .gone:
                f.respawn -= dt
                if f.respawn <= 0 { enter(f, W, H) }
            case .wrapped, .held:
                break
            }
        }
    }

    private func fly(_ f: Fly, _ dt: Double, _ W: Double, _ H: Double, _ t: Double, _ pointer: WebPointer) {
        let random = world.random
        f.ox = f.x
        f.oy = f.y
        // Wander on smooth noise, with the odd dart.
        f.h += noise1(t * 0.9 + f.seed, f.seed) * 3.4 * dt + (random.unit() - 0.5) * 5 * dt
        var vt = 80 + 55 * noise1(t * 0.6 + f.seed * 0.37, f.seed + 1)
        if random.unit() < dt * 0.5 {
            f.h += random.range(-2.2, 2.2)
            f.v = random.range(180, 250)
        }
        var want: Double? = nil
        var rate = 0.0
        if pointer.active {
            let d = hypot(f.x - pointer.x, f.y - pointer.y)
            if d < 120 { want = atan2(f.y - pointer.y, f.x - pointer.x); rate = 9; vt = 230 }
        }
        if want == nil, let aim = f.aim { want = atan2(aim.y - f.y, aim.x - f.x); rate = 6; vt = 130 }
        let m = 36.0
        if want == nil {
            if world.single {
                if f.x < m || f.x > W - m || f.y < m || f.y > H - m { want = atan2(H / 2 - f.y, W / 2 - f.x); rate = 4 }
            } else if !world.clear(f.x, f.y, m) {
                // Several screens: a wall is any edge of the terrain; head for the middle of this screen.
                let r = world.screen(near: f.x, f.y)
                want = atan2(r.midY - f.y, r.midX - f.x)
                rate = 4
            }
        }
        if let want { f.h += clamp(angleDiff(f.h, want), -rate * dt, rate * dt) }
        f.v += (vt - f.v) * min(1, dt * 2.2)
        if world.single {
            f.x = clamp(f.x + cos(f.h) * f.v * dt, -20, W + 20)
            f.y = clamp(f.y + sin(f.h) * f.v * dt, -20, H + 20)
        } else {
            let p = world.loose(f.x + cos(f.h) * f.v * dt, f.y + sin(f.h) * f.v * dt, from: f.x, f.y, slack: 20)
            f.x = p.x
            f.y = p.y
        }

        for web in world.webs {
            let hit = web.catches(f.ox, f.oy, f.x, f.y)
            // Only the aimed web takes the opening fly; otherwise any web may.
            if let hit, f.aim != nil ? f.aimWeb === web : random.unit() < STICK * (0.4 + 0.6 * web.depth) {
                f.stick(web, hit.link, hit.t)
                return
            }
        }
        // Settle for a rest now and then, away from the edges.
        let away = world.single ? f.x > m && f.x < W - m && f.y > m && f.y < H - m : world.clear(f.x, f.y, m)
        if f.aim == nil && away && random.unit() < dt * 0.045 {
            f.mode = .rest
            f.timer = random.range(2.5, 7)
        }
    }

    /// A new fly drifts in from an edge.
    private func enter(_ f: Fly, _ W: Double, _ H: Double) {
        let random = world.random
        if world.single {
            let side = random.int(0, 3)
            let along = random.range(0.15, 0.85)
            f.x = side == 0 ? -10 : side == 1 ? W + 10 : along * W
            f.ox = f.x
            f.y = side == 2 ? -10 : side == 3 ? H + 10 : along * H
            f.oy = f.y
            f.web = nil
            f.mode = .fly
            f.h = atan2(H / 2 - f.y, W / 2 - f.x) + random.range(-0.6, 0.6)
        } else {
            // Several screens: in over a real edge (one not shared with another screen), toward its screen's middle.
            let e = world.wallByLength()
            let along = random.range(0.15, 0.85)
            f.x = e.a.x + (e.b.x - e.a.x) * along - e.normal.x * 10
            f.ox = f.x
            f.y = e.a.y + (e.b.y - e.a.y) * along - e.normal.y * 10
            f.oy = f.y
            f.web = nil
            f.mode = .fly
            let r = world.screens[e.rect]
            f.h = atan2(r.midY - f.y, r.midX - f.x) + random.range(-0.6, 0.6)
        }
        f.v = 120
        f.wrap = 0
        f.digest = 0
        f.hunted = false
    }
}
