import CoreGraphics
import Foundation

/// What every habitat's simulation offers the host. Coordinates are in ocean
/// space: the terrain's bounds start at 0,0.
public protocol HabitatSim: AnyObject {
    var kind: HabitatKind { get }
    var time: Double { get }
    var stepCount: Int { get }
    func layout(terrain: Terrain, cell: CGSize, settings: Settings)
    func step(_ dt: Double)
    func pointerMoved(_ x: Double, _ y: Double)
    func pointerLeft()
    func pointerDown(_ x: Double, _ y: Double)
    /// In-place changes (Ocean: fish density).
    func update(settings: Settings)
    /// Advance to a representative state for a still.
    func settle()
}

public enum Habitats {
    public static func make(_ s: Settings, seed: UInt64) -> HabitatSim {
        switch s.habitat {
        case .ocean: return OceanSim(settings: s, seed: seed)
        case .web: return WebSim(settings: s, seed: seed)
        }
    }

    public static func needsRebuild(old: Settings, new: Settings) -> Bool {
        if old.habitat != new.habitat { return true }
        switch new.habitat {
        case .ocean: return old.sharks != new.sharks
        case .web: return old.webSpiders != new.webSpiders || old.webFlies != new.webFlies || old.webJumper != new.webJumper
        }
    }
}
