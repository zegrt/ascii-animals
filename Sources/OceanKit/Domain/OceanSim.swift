import CoreGraphics
import Foundation

/// Today's shark ocean behind the `HabitatSim` protocol.
public final class OceanSim: HabitatSim {
    public let world: World
    private var terrain = Terrain(rects: [])
    private var cell = CGSize(width: 13, height: 19)

    public init(settings: Settings, seed: UInt64) {
        world = World(sharks: settings.sharks, rng: Rng(seed: seed))
    }

    public var kind: HabitatKind { .ocean }
    public var time: Double { world.time }
    public var stepCount: Int { world.stepCount }

    public func layout(terrain: Terrain, cell: CGSize, settings: Settings) {
        self.terrain = terrain
        self.cell = cell
        world.resize(terrain: terrain, cell: cell, density: settings.fishDensity)
    }

    public func step(_ dt: Double) { world.step(dt) }
    public func pointerMoved(_ x: Double, _ y: Double) { world.pointer = (x, y, true) }
    public func pointerLeft() { world.pointer.active = false }
    public func pointerDown(_ x: Double, _ y: Double) { world.splash(x, y) }

    public func update(settings: Settings) {
        world.resize(terrain: terrain, cell: cell, density: settings.fishDensity)
    }

    public func settle() {
        if world.time < 4 { for _ in 0..<240 { world.step(OceanClock.step) } }
    }
}
