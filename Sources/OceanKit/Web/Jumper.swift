import Foundation

// Port of jumper.ts from ascii-spiders by @stackedlol (MIT), commit 89a7721.
// See docs/reference/web-port-notes.md for what differs and why.

/**
 * A jumping spider loose on the wall. It moves the way salticids do: short bursts that swell and die away,
 * still pauses, quick sprung swivels to face whatever moves. It watches the cursor, edging closer, and if
 * it holds still, crouches and pounces, landing low and springing back up. It stalks resting flies the
 * same way. Every jump pays out a dragline from where it took off.
 */

public enum JumperState: Sendable { case pause, burst, crouch, jump }

/// What has its attention, and how far off it is.
struct Interest {
    var x: Double
    var y: Double
    var d: Double
    var fly: Fly?
}

struct Leap {
    var x0: Double
    var y0: Double
    var x1: Double
    var y1: Double
    var t: Double
    var dur: Double
    var fly: Fly?
}

/// The dragline paid out from the last take-off, fading once it lands.
public struct Dragline {
    public var x: Double
    public var y: Double
    public var life: Double
}

public final class Jumper {
    public let spider: Spider
    public var state: JumperState = .pause
    private var timer: Double
    private var goal: Vec? = nil
    /// How long the target has held still in front of it.
    private var watch = 0.0
    private var cool = 0.0
    private var hunger = 0.6
    /// The dragline paid out from the last take-off, fading once it lands.
    public var drag: Dragline? = nil
    private var mark = Vec(x: 0, y: 0)
    private var bt = 0.0
    private var bdur = 0.0
    private var bv = 0.0
    private var crouch: Interest? = nil
    private var jump: Leap? = nil
    unowned let world: WebWorld
    /// `Math.random()`: the world's shared stream.
    let random: WebRandom

    init(_ world: WebWorld, _ B: Double) {
        self.world = world
        random = world.random
        timer = random.range(0.4, 1.2)
        spider = Spider(.jumper, B, random: random)
    }

    public func place(_ x: Double, _ y: Double) {
        spider.place(x, y, random.range(0, Double.pi * 2))
    }

    /// What has its attention: the cursor, else a resting fly when hungry.
    private func interest() -> Interest? {
        let pointer = world.pointer
        let swarm = world.swarm
        let sp = spider
        if pointer.active {
            let d = hypot(pointer.x - sp.x, pointer.y - sp.y)
            if d < 440 { return Interest(x: pointer.x, y: pointer.y, d: d, fly: nil) }
        }
        if hunger < 0.35 { return nil }
        var best: Interest? = nil
        for f in swarm.flies {
            if f.mode != .rest { continue }
            let d = hypot(f.x - sp.x, f.y - sp.y)
            if d < 480 && (best == nil || d < best!.d) { best = Interest(x: f.x, y: f.y, d: d, fly: f) }
        }
        return best
    }

    public func update(_ dt: Double) {
        let sp = spider
        let W = world.width, H = world.height
        let px = sp.x
        let py = sp.y
        let s = sp.B / 60
        hunger = min(1, hunger + dt * 0.02)
        cool = max(0, cool - dt)
        if drag != nil {
            drag!.life -= dt * (state == .jump ? 0 : 0.35)
            if drag!.life <= 0 { drag = nil }
        }
        var scaleTo = 1.0

        if state == .jump, var j = jump {
            j.t = min(1, j.t + dt / j.dur)
            jump = j
            let e = 1 - pow(1 - j.t, 2.4)
            sp.x = j.x0 + (j.x1 - j.x0) * e
            sp.y = j.y0 + (j.y1 - j.y0) * e
            sp.scale = 1 + 0.3 * sin(Double.pi * j.t)
            scaleTo = sp.scale
            if j.t >= 1 {
                sp.airborne = false
                sp.scale = 0.9 // lands low, and springs back up
                sp.place(sp.x, sp.y, sp.h)
                state = .pause
                timer = random.range(0.6, 1.2)
                if let f = j.fly, f.mode == .rest && hypot(f.x - sp.x, f.y - sp.y) < sp.B * 0.7 {
                    f.mode = .gone
                    f.respawn = random.range(3, 7)
                    world.burst(f.x, f.y)
                    hunger = 0
                    timer = 1.8
                }
            }
        } else if state == .crouch, let crouch {
            // Settle low on the legs for a beat, then go.
            timer -= dt
            scaleTo = 0.88
            sp.steer(atan2(crouch.y - sp.y, crouch.x - sp.x), dt, 160)
            if timer <= 0 { leap(crouch) }
        } else {
            let it = interest()
            let goal: Vec
            var near = sp.B * 1.2
            if let it {
                let still = it.fly != nil ? true : hypot(it.x - mark.x, it.y - mark.y) < 10
                if !still { mark.x = it.x; mark.y = it.y; watch = 0 }
                goal = Vec(x: it.x, y: it.y)
                near = sp.B * 4.2
            } else {
                watch = 0
                if self.goal == nil || hypot(self.goal!.x - sp.x, self.goal!.y - sp.y) < sp.B * 1.2 {
                    let m = sp.B * 1.6
                    self.goal = world.single ? Vec(x: random.range(m, W - m), y: random.range(m, H - m)) : world.wanderGoal(from: sp.x, sp.y, margin: m)
                }
                goal = self.goal!
            }
            let face = atan2(goal.y - sp.y, goal.x - sp.x)
            let d = hypot(goal.x - sp.x, goal.y - sp.y)
            // Swivel to face it: quick, sprung, as salticids do.
            sp.steer(face, dt, it != nil ? 110 : 45)
            let aligned = abs(angleDiff(sp.h, face)) < 0.22
            if state == .burst {
                // A burst: speed swells and dies away along a sine, then a still pause.
                bt += dt
                let k = bt / bdur
                let v = bv * pow(sin(Double.pi * min(1, k)), 1.4)
                sp.x += cos(sp.h) * v * dt
                sp.y += sin(sp.h) * v * dt
                if k >= 1 || d < near * 0.85 {
                    state = .pause
                    timer = it != nil ? random.range(0.35, 0.9) : random.range(0.7, 2.6)
                }
            } else {
                timer -= dt
                if let it, d <= near && aligned {
                    watch += dt
                    if watch > (it.fly != nil ? 0.45 : 0.9) && cool <= 0 && d > sp.B * 0.9 {
                        state = .crouch
                        timer = 0.26
                        crouch = it
                    }
                } else if timer <= 0 && d > near && aligned {
                    state = .burst
                    bt = 0
                    bdur = it != nil ? random.range(0.45, 0.8) : random.range(0.7, 1.4)
                    bv = (it != nil ? 55 : 62) * s * random.range(0.85, 1.15)
                }
            }
        }
        if state != .jump { sp.scale += (scaleTo - sp.scale) * (1 - exp(-dt * 14)) }

        let m = sp.B * 0.8
        if world.single {
            sp.x = clamp(sp.x, m, W - m)
            sp.y = clamp(sp.y, m, H - m)
        } else {
            let p = world.inside(sp.x, sp.y, from: px, py, margin: m)
            sp.x = p.x
            sp.y = p.y
        }
        sp.vx = (sp.x - px) / max(dt, 1e-4)
        sp.vy = (sp.y - py) / max(dt, 1e-4)
        sp.updateLegs(dt)
    }

    private func leap(_ it: Interest) {
        let sp = spider
        // Land just short of a fly; right on the cursor.
        let short = it.fly != nil ? sp.B * 0.35 : sp.B * 0.2
        let a = atan2(it.y - sp.y, it.x - sp.x)
        let d = max(0, hypot(it.x - sp.x, it.y - sp.y) - short)
        jump = Leap(x0: sp.x, y0: sp.y, x1: sp.x + cos(a) * d, y1: sp.y + sin(a) * d, t: 0, dur: 0.32 + d / 700, fly: it.fly)
        drag = Dragline(x: sp.x, y: sp.y, life: 1)
        sp.airborne = true
        state = .jump
        watch = 0
        cool = it.fly != nil ? 0.5 : 2.6
    }
}
