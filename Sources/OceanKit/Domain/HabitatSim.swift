import CoreGraphics
import Foundation

/// What every habitat's simulation offers the host. Coordinates are in ocean
/// space: the terrain's bounds start at 0,0.
public protocol HabitatSim: AnyObject {
    var kind: HabitatKind { get }
    var time: Double { get }
    var stepCount: Int { get }
    func layout(terrain: Terrain, cell: CGSize, settings: Settings)
    /// Where this scene sits on the desk (`HabitatScene.arrange`): the desk's scenes and screens, and which one is this
    /// scene's. Called before `layout` for a new sim, and again whenever the desk changes, without a layout when this
    /// scene's own geometry is unchanged, so a habitat can share a desk-wide cap (the Meadow's 12); the others ignore it.
    func share(desk: SceneDesk, index: Int)
    func step(_ dt: Double)
    func pointerMoved(_ x: Double, _ y: Double)
    func pointerLeft()
    func pointerDown(_ x: Double, _ y: Double)
    /// In-place changes (Ocean: fish density).
    func update(settings: Settings)
    /// Advance to a representative state for a still.
    func settle()
}

public extension HabitatSim {
    func share(desk: SceneDesk, index: Int) {}
}

public enum Habitats {
    public static func make(_ s: Settings, seed: UInt64) -> HabitatSim {
        switch s.habitat {
        case .ocean: return OceanSim(settings: s, seed: seed)
        case .web: return WebSim(settings: s, seed: seed)
        case .meadow: return MeadowSim(settings: s, seed: seed)
        }
    }

    public static func needsRebuild(old: Settings, new: Settings) -> Bool {
        if old.habitat != new.habitat { return true }
        switch new.habitat {
        case .ocean: return old.sharks != new.sharks
        case .web: return old.webSpiders != new.webSpiders || old.webFlies != new.webFlies || old.webJumper != new.webJumper
        case .meadow: return false
        }
    }

    /// A view of the habitat shown again after a while (the About banner when reopened): rebuilt when
    /// `needsRebuild`, and also when the Meadow's line-up changed, which a live scene takes in place but a view coming
    /// back should simply show (its butterflies would otherwise be the old line-up, or still leaving).
    public static func needsFreshLook(old: Settings, new: Settings) -> Bool {
        if needsRebuild(old: old, new: new) { return true }
        guard new.habitat == .meadow else { return false }
        let a = old.sanitized(), b = new.sanitized()
        return a.meadowButterflies != b.meadowButterflies || a.meadowCount != b.meadowCount
    }
}
