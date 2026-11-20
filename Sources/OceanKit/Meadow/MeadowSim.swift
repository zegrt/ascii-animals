import CoreGraphics
import Foundation

/// The Meadow habitat: the sketch's meadow (`MeadowWorld`) and its painter (`MeadowPainter`) behind the
/// `HabitatSim` protocol, as Web's `WebSim`. The app's settings choose the species, the count on a laptop screen
/// (scaled by area on bigger ones) and whether one lands on a still pointer; everything else is the director's tuning.
public final class MeadowSim: CellPainter {
    public private(set) var world: MeadowWorld
    private let painter = MeadowPainter()
    private let seed: Int32
    private var tuning: MeadowTuning
    private var terrain = Terrain(rects: [])
    private var cell = CGSize(width: 13, height: 19)
    public private(set) var stepCount = 0
    private var laidOut = false
    private var desk: [CGSize] = []
    private var deskIndex = 0

    public init(settings: Settings, seed: UInt64, tuning: MeadowTuning = .director) {
        self.seed = Int32(truncatingIfNeeded: seed)
        let t = MeadowSim.tuning(tuning, settings)
        self.tuning = t
        world = MeadowWorld(terrain: Terrain(rects: []), cell: CGSize(width: 13, height: 19), tuning: t, seed: self.seed)
        world.speed = settings.speed
    }

    /// `base` with the app's settings in it: the species on, the laptop count scaled by area, and landing on a still
    /// pointer only while the pointer plays (the app's "Play with the pointer").
    public static func tuning(_ base: MeadowTuning, _ s: Settings) -> MeadowTuning {
        var t = base
        let c = s.sanitized()
        t.species = ButterflyKind.allCases.map { c.meadowButterflies.contains($0) }
        t.count = c.meadowCount
        t.areaCount = true
        t.cursorLand = s.interaction
        return t
    }

    public var kind: HabitatKind { .meadow }
    public var time: Double { world.time }

    /// The sketch's `start` on the first layout (planting, the butterflies, the opening moment), its `resize` after.
    public func layout(terrain: Terrain, cell: CGSize, settings: Settings) {
        self.terrain = terrain
        self.cell = cell
        world.speed = settings.speed
        if !laidOut {
            world = MeadowWorld(terrain: terrain, cell: cell, tuning: tuning, seed: seed, countLimit: countLimit)
            world.speed = settings.speed
            laidOut = true
        } else {
            world.layout(terrain: terrain, cell: cell)
        }
    }

    /// This scene's screen on a desk where each screen is its own scene: the scene then holds its share of the 12
    /// (`MeadowTuning.areaCountShares`), so the desk never shows more than one scene across it would. A new share
    /// takes effect the sketch's way (spares leave, newcomers fly in).
    public func share(desk: [CGSize], index: Int) {
        self.desk = desk
        deskIndex = index
        applyCountLimit()
    }

    /// The most this scene holds: 12, or its screen's share of the desk's 12.
    var countLimit: Int {
        guard desk.count > 1, desk.indices.contains(deskIndex) else { return MeadowTuning.areaCountLimit }
        return MeadowTuning.areaCountShares(tuning.count, screens: desk)[deskIndex]
    }

    private func applyCountLimit() {
        let limit = countLimit
        guard world.countLimit != limit else { return }
        world.countLimit = limit
        if laidOut { world.syncFlies() }
    }

    public func step(_ dt: Double) {
        world.step(dt)
        stepCount += 1
    }

    public func pointerMoved(_ x: Double, _ y: Double) { world.pointerMoved(x: x, y: y) }
    public func pointerLeft() { world.pointerLeft() }
    public func pointerDown(_ x: Double, _ y: Double) { world.pointerDown(x: x, y: y) }

    /// The app's settings, in place: the speed, and a new line-up the sketch's way (spares leave through the nearest
    /// edge, newcomers fly in; nobody pops). The host rebuilds the sim only when the habitat changes.
    public func update(settings: Settings) {
        world.speed = settings.speed
        let t = MeadowSim.tuning(tuning, settings)
        guard t != tuning else { return }
        tuning = t
        world.tuning = t
        world.countLimit = countLimit
        if laidOut { world.syncFlies() }
    }

    /// A still: the sketch's first frame, the opening moment as laid out (one butterfly nectaring, one basking, one
    /// coming in to land). Nothing to do once it has lived.
    public func settle() {}

    public func paint(viewport: CGRect, grid: GridSpec, theme: ThemeParams, into canvas: CellCanvas) {
        painter.paint(world, viewport: viewport, grid: grid, theme: theme, into: canvas)
    }
}
