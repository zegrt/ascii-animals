import CoreGraphics
import Foundation

/// One habitat's simulation, its clock, and the plan of which screens look
/// into it. Separate oceans: one scene per screen. Shared ocean: one scene for all.
/// The app's host (`OceanDirector`) lays the desk out through `arrange`; OceanTool's bench and the checks use the same.
public final class HabitatScene {
    public private(set) var plan: ScenePlan
    public private(set) var sim: HabitatSim
    private var clock = OceanClock()
    private let desk: SceneDesk
    private var index: Int
    private let seeds: () -> UInt64

    init(plan: ScenePlan, index: Int, desk: SceneDesk, settings: Settings, seeds: @escaping () -> UInt64) {
        self.plan = plan
        self.index = index
        self.desk = desk
        self.seeds = seeds
        sim = HabitatScene.makeSim(plan, index, desk, settings, seeds())
    }

    public var screenIDs: Set<Int> { Set(plan.views.map(\.screenID)) }

    public func rect(for screenID: Int) -> CGRect? { plan.views.first { $0.screenID == screenID }?.rect }

    private static func makeSim(_ plan: ScenePlan, _ index: Int, _ desk: SceneDesk, _ s: Settings, _ seed: UInt64) -> HabitatSim {
        let sim = Habitats.make(s, seed: seed)
        desk.join(sim)
        sim.share(desk: desk, index: index)
        sim.layout(terrain: plan.terrain, cell: plan.cell, settings: s)
        return sim
    }

    /// A fresh simulation, for changes `Habitats.needsRebuild` says can't be made in place.
    public func rebuild(_ s: Settings) {
        desk.leave(sim)
        sim = HabitatScene.makeSim(plan, index, desk, s, seeds())
        clock.reset()
    }

    /// Same screens: lay out in place to new geometry so the habitat keeps going, and only then. The scene's place on
    /// the desk goes to the sim on its own path (`HabitatSim.share`), so a change elsewhere on the desk never lays out
    /// a scene whose own geometry is unchanged (the Ocean and the Web ignore it; the Meadow takes its share of the 12).
    func update(_ newPlan: ScenePlan, index: Int, settings: Settings) {
        self.index = index
        if newPlan != plan {
            plan = newPlan
            sim.share(desk: desk, index: index)
            sim.layout(terrain: plan.terrain, cell: plan.cell, settings: settings)
        } else {
            sim.share(desk: desk, index: index)
        }
    }

    /// Called by every screen's display link; the clock ignores timestamps it
    /// has already counted, so the sim steps once however many screens draw it.
    public func advance(to timestamp: Double, speed: Double) {
        let steps = clock.advance(to: timestamp, speed: speed)
        for _ in 0..<steps { sim.step(OceanClock.step) }
    }

    /// Lay the scenes out for `plans` (`SceneLayout.plan`): a scene whose screens are unchanged keeps its sim (laid
    /// out in place to any new geometry); `fresh` forces new sims, e.g. when switching between shared and separate
    /// oceans. Every scene sits on `desk`, which the caller keeps for as long as the scenes. `seeds` gives a new sim's
    /// seed (random in the app; fixed in the bench and the checks).
    public static func arrange(_ old: [HabitatScene], plans: [ScenePlan], settings: Settings, fresh: Bool,
                               desk: SceneDesk,
                               seeds: @escaping () -> UInt64 = { UInt64.random(in: 1...UInt64.max) }) -> [HabitatScene] {
        let kept: [HabitatScene?] = plans.map { (plan: ScenePlan) -> HabitatScene? in
            if fresh { return nil }
            let ids = Set(plan.views.map(\.screenID))
            return old.first { $0.screenIDs == ids }
        }
        // The desk holds exactly the scenes laid out now, the kept ones first, so a new scene sees what they draw.
        desk.seat(plans)
        for case let k? in kept { desk.join(k.sim) }
        var next: [HabitatScene] = []
        for (i, plan) in plans.enumerated() {
            if let keep = kept[i] {
                keep.update(plan, index: i, settings: settings)
                next.append(keep)
            } else {
                next.append(HabitatScene(plan: plan, index: i, desk: desk, settings: settings, seeds: seeds))
            }
        }
        return next
    }
}

/// The scenes on one desk, for a habitat that shares something across them (the Meadow's 12 in all, the director's
/// "never more than 12 across all screens"): each scene's screen when every screen is its own scene, and the scenes'
/// sims, so one can see what the others draw. Holds the sims weakly; `HabitatScene.arrange` keeps it current.
public final class SceneDesk {
    /// Each scene's screen size, in the scenes' order, when every screen is its own scene; empty when one scene
    /// spans the desk (or there is one screen).
    public private(set) var screens: [CGSize] = []
    private struct Member { weak var sim: AnyObject? }
    private var members: [Member] = []

    public init() {}

    /// A new layout of the desk for `plans`: their screens, and no scenes yet (they join as they are laid out).
    func seat(_ plans: [ScenePlan]) {
        screens = plans.count > 1 ? plans.map { (p: ScenePlan) -> CGSize in p.terrain.bounds.size } : []
        members = []
    }

    func join(_ sim: HabitatSim) {
        members.removeAll { $0.sim == nil || $0.sim === sim }
        members.append(Member(sim: sim))
    }

    func leave(_ sim: HabitatSim) { members.removeAll { $0.sim == nil || $0.sim === sim } }

    /// The sims on the desk now, in the order they joined.
    public var sims: [HabitatSim] { members.compactMap { $0.sim as? HabitatSim } }

    /// `body` for each sim on the desk now, in the order they joined, without allocating (`sims` builds an array;
    /// a scene asks this on every step).
    public func forEachSim(_ body: (HabitatSim) -> Void) {
        for m in members { if let s = m.sim as? HabitatSim { body(s) } }
    }
}
