import Foundation

// Probes for OceanChecks only (`@_spi(Checks) import OceanKit`): they put a butterfly into a chosen state, as the
// review's probes did, so a check can hold the exact case that went wrong. Nothing in the app or the tool uses them.

@_spi(Checks) extension MeadowWorld {
    /// The world's own signed distance to the terrain (what the edge steer and the entry test read every step).
    public func probeSignedOutside(x: Double, y: Double) -> Double { signedOutside(x, y) }

    /// Puts `b` at (x, y) flying at (vx, vy) pt/s, heading that way, with its waypoint ahead.
    public func probeFly(_ b: Butterfly, x: Double, y: Double, vx: Double, vy: Double) {
        if b.landed { takeOff(b) }
        releaseFlower(b)
        b.state = .fly
        b.goal = .none
        b.spiral = nil
        b.circleT = 0
        b.wait = 0
        b.entering = false
        b.leaving = false
        b.x = x
        b.y = y
        b.ux = vx
        b.uy = vy
        b.heading = atan2(vy, vx)
        b.turn = 0
        b.jink = 0
        b.boost = 0
        b.wx = x + vx * 10
        b.wy = y + vy * 10
        b.wpLeft = 10
    }

    /// Lands `b` at (x, y) on flower `id` (feeding).
    public func probeLand(_ b: Butterfly, x: Double, y: Double, onFlower id: Int) {
        probeFly(b, x: x, y: y, vx: 0, vy: 0)
        b.goal = .nectar
        b.flower = id
        flowers.setBusy(id: id, by: b.id)
        land(b)
    }

    /// Puts `b` at (x, y) on its way down to flower `id`, close enough to settle.
    public func probeApproach(_ b: Butterfly, x: Double, y: Double, flower id: Int) {
        probeFly(b, x: x, y: y, vx: 0, vy: 0)
        guard let i = flowers.index(of: id) else { return }
        goToFlower(b, i)
        b.tag = 1
        b.zs = 0.05
        b.z = 0.05
    }

    /// Sends `b` away through an exit (the sketch's `sendAway`).
    public func probeSendAway(_ b: Butterfly) { sendAway(b) }

    /// One flight step of `b` alone.
    public func probeStep(_ b: Butterfly) { stepFly(b, OceanClock.step) }

    /// Whether (x, y) is in a gap between screens, as the world judges it.
    public func probeInGap(_ x: Double, _ y: Double) -> Bool { inGap(x, y) }
}

@_spi(Checks) extension MeadowPainter {
    /// Per screen painted: slots made, recordings held, and how many of those are of flowers no longer in `world`.
    public func probeFlowerCaches(_ world: MeadowWorld) -> [(slots: Int, cached: Int, stale: Int)] {
        views.map { v in
            var stale = 0
            for (id, _) in v.flowers where world.flowers.index(of: id) == nil { stale += 1 }
            return (v.slots.count, v.flowers.count, stale)
        }
    }
}
