import Foundation
import OceanKit

/// One habitat's simulation, its clock, and the plan of which screens look
/// into it. Separate oceans: one scene per screen. Shared ocean: one scene for all.
final class HabitatScene {
    private(set) var plan: ScenePlan
    private(set) var sim: HabitatSim
    private var clock = OceanClock()

    init(plan: ScenePlan, settings: OceanKit.Settings) {
        self.plan = plan
        sim = HabitatScene.makeSim(plan, settings)
    }

    var screenIDs: Set<Int> { Set(plan.views.map(\.screenID)) }

    func rect(for screenID: Int) -> CGRect? { plan.views.first { $0.screenID == screenID }?.rect }

    private static func makeSim(_ plan: ScenePlan, _ s: OceanKit.Settings) -> HabitatSim {
        let sim = Habitats.make(s, seed: UInt64.random(in: 1...UInt64.max))
        sim.layout(terrain: plan.terrain, cell: plan.cell, settings: s)
        return sim
    }

    /// A fresh simulation, for changes `Habitats.needsRebuild` says can't be made in place.
    func rebuild(_ s: OceanKit.Settings) {
        sim = HabitatScene.makeSim(plan, s)
        clock.reset()
    }

    /// Same screens, new geometry: lay out in place so the habitat keeps going.
    func update(_ newPlan: ScenePlan, settings: OceanKit.Settings) {
        guard newPlan != plan else { return }
        plan = newPlan
        sim.layout(terrain: plan.terrain, cell: plan.cell, settings: settings)
    }

    /// Called by every screen's display link; the clock ignores timestamps it
    /// has already counted, so the sim steps once however many screens draw it.
    func advance(to timestamp: Double, speed: Double) {
        let steps = clock.advance(to: timestamp, speed: speed)
        for _ in 0..<steps { sim.step(OceanClock.step) }
    }
}
