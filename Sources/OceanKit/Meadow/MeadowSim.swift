import CoreGraphics
import Foundation

/// The Meadow habitat: the sketch's meadow (`MeadowWorld`) and its painter (`MeadowPainter`) behind the
/// `HabitatSim` protocol, as Web's `WebSim`. Not offered in the app yet (`HabitatKind.offered`); OceanTool's still,
/// frames and bench run it.
public final class MeadowSim: CellPainter {
    public private(set) var world: MeadowWorld
    private let painter = MeadowPainter()
    private let seed: Int32
    private var tuning: MeadowTuning
    private var terrain = Terrain(rects: [])
    private var cell = CGSize(width: 13, height: 19)
    public private(set) var stepCount = 0
    private var laidOut = false

    public init(settings: Settings, seed: UInt64, tuning: MeadowTuning = .director) {
        self.seed = Int32(truncatingIfNeeded: seed)
        self.tuning = tuning
        world = MeadowWorld(terrain: Terrain(rects: []), cell: CGSize(width: 13, height: 19), tuning: tuning, seed: self.seed)
        world.speed = settings.speed
    }

    public var kind: HabitatKind { .meadow }
    public var time: Double { world.time }

    /// The sketch's `start` on the first layout (planting, the butterflies, the opening moment), its `resize` after.
    public func layout(terrain: Terrain, cell: CGSize, settings: Settings) {
        self.terrain = terrain
        self.cell = cell
        world.speed = settings.speed
        if !laidOut {
            world = MeadowWorld(terrain: terrain, cell: cell, tuning: tuning, seed: seed)
            world.speed = settings.speed
            laidOut = true
        } else {
            world.layout(terrain: terrain, cell: cell)
        }
    }

    public func step(_ dt: Double) {
        world.step(dt)
        stepCount += 1
    }

    public func pointerMoved(_ x: Double, _ y: Double) { world.pointerMoved(x: x, y: y) }
    public func pointerLeft() { world.pointerLeft() }
    public func pointerDown(_ x: Double, _ y: Double) { world.pointerDown(x: x, y: y) }

    /// The app's speed; the butterflies are rebuilt by the host when the habitat changes.
    public func update(settings: Settings) { world.speed = settings.speed }

    /// A still: the sketch's first frame, the opening moment as laid out (one butterfly nectaring, one basking, one
    /// coming in to land). Nothing to do once it has lived.
    public func settle() {}

    public func paint(viewport: CGRect, grid: GridSpec, theme: ThemeParams, into canvas: CellCanvas) {
        painter.paint(world, viewport: viewport, grid: grid, theme: theme, into: canvas)
    }
}
