import Foundation
import OceanKit

/// One world, its clock, and the plan of which screens look into it.
/// Separate oceans: one scene per screen. Shared ocean: one scene for all.
final class OceanScene {
    private(set) var plan: ScenePlan
    private(set) var world: World
    private var clock = OceanClock()

    init(plan: ScenePlan, settings: Settings) {
        self.plan = plan
        world = OceanScene.makeWorld(plan, settings)
    }

    var screenIDs: Set<Int> { Set(plan.views.map(\.screenID)) }

    func rect(for screenID: Int) -> CGRect? { plan.views.first { $0.screenID == screenID }?.rect }

    private static func makeWorld(_ plan: ScenePlan, _ s: Settings) -> World {
        let w = World(sharks: s.sharks, rng: Rng(seed: UInt64.random(in: 1...UInt64.max)))
        w.resize(habitat: plan.habitat, cell: plan.cell, density: s.fishDensity)
        return w
    }

    func rebuildWorld(_ s: Settings) {
        world = OceanScene.makeWorld(plan, s)
        clock.reset()
    }

    func setDensity(_ s: Settings) {
        world.resize(habitat: plan.habitat, cell: plan.cell, density: s.fishDensity)
    }

    /// Same screens, new geometry: resize in place so the ocean keeps swimming.
    func update(_ newPlan: ScenePlan, settings: Settings) {
        guard newPlan != plan else { return }
        plan = newPlan
        world.resize(habitat: plan.habitat, cell: plan.cell, density: settings.fishDensity)
    }

    /// Called by every screen's display link; the clock ignores timestamps it
    /// has already counted, so the world steps once however many screens draw it.
    func advance(to timestamp: Double, speed: Double) {
        let steps = clock.advance(to: timestamp, speed: speed)
        for _ in 0..<steps { world.step(OceanClock.step) }
    }
}
