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
    /// The desk this scene sits on in the app (`HabitatScene.arrange`); nil alone (OceanTool, the previews).
    private weak var desk: SceneDesk?
    private var deskIndex = 0

    public init(settings: Settings, seed: UInt64, tuning: MeadowTuning = .director) {
        self.seed = Int32(truncatingIfNeeded: seed)
        let t = MeadowSim.tuning(tuning, settings)
        self.tuning = t
        world = MeadowWorld(terrain: Terrain(rects: []), cell: CGSize(width: 13, height: 19), tuning: t, seed: self.seed)
        world.speed = settings.speed
        world.room = { [weak self] in self?.room ?? MeadowTuning.areaCountLimit }
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
            world = MeadowWorld(terrain: terrain, cell: cell, tuning: tuning, seed: seed, countLimit: countLimit,
                                room: { [weak self] in self?.room ?? MeadowTuning.areaCountLimit })
            world.speed = settings.speed
            laidOut = true
        } else {
            world.layout(terrain: terrain, cell: cell)
        }
    }

    /// This scene's place on the desk. Where each screen is its own scene, the scene holds its share of the 12
    /// (`MeadowTuning.areaCountShares`), so the desk settles where one scene across it would. A new share takes effect
    /// the sketch's way (spares leave, newcomers fly in) without a layout; newcomers wait while the desk's other
    /// scenes still draw butterflies on their way out (`room`).
    public func share(desk: SceneDesk, index: Int) {
        self.desk = desk
        deskIndex = index
        applyCountLimit()
    }

    /// The most this scene holds: 12, or its screen's share of the desk's 12.
    var countLimit: Int {
        guard let screens = desk?.screens, screens.count > 1, screens.indices.contains(deskIndex) else {
            return MeadowTuning.areaCountLimit
        }
        return MeadowTuning.areaCountShares(tuning.count, screens: screens)[deskIndex]
    }

    /// The desk's other Meadow scenes (none alone).
    private var others: [MeadowSim] {
        guard let desk else { return [] }
        return desk.sims.compactMap { (s: HabitatSim) -> MeadowSim? in s === self ? nil : s as? MeadowSim }
    }

    /// The most butterflies this scene may draw now, its own leaving ones included: the desk's 12 less every butterfly
    /// the desk's other scenes draw, theirs on the way out included (the director's "never more than 12 across all
    /// screens", during changes too). Alone, 12.
    var room: Int {
        var drawn = 0
        for m in others { drawn += m.world.flies.count }
        return max(0, MeadowTuning.areaCountLimit - drawn)
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

    /// A held frame (a pause, Low Power, Reduce Motion): a change still on its way is finished at once across the
    /// desk, as the same change made before a fresh start would look: the ones leaving are gone and the newcomers are
    /// on the screens, so a paused line-up change shows the new line-up and never more than 12. Otherwise nothing:
    /// a fresh scene's still is the sketch's first frame, the opening moment as laid out.
    public func settle() {
        let all: [MeadowSim] = [self] + others
        var any = false
        for m in all where m.world.dropInTransit() { any = true }
        if !any && !all.contains(where: { $0.world.shortOfCount }) { return }
        for m in all { m.world.fillAtOnce() }
    }

    public func paint(viewport: CGRect, grid: GridSpec, theme: ThemeParams, into canvas: CellCanvas) {
        painter.paint(world, viewport: viewport, grid: grid, theme: theme, into: canvas)
    }
}
