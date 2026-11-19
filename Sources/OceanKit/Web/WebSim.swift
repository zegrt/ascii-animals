import CoreGraphics
import Foundation

/// The Web habitat: ascii-spiders' wall (`WebWorld`) and its renderer (`WebPainter`) behind the `HabitatSim`
/// protocol, with the host parts of the original engine.ts (the fixed step and the settled still).
public final class WebSim: CellPainter {
    public let world: WebWorld
    private let painter = WebPainter()
    private var terrain = Terrain(rects: [])
    private var cell = CGSize(width: 13, height: 19)
    public private(set) var stepCount = 0
    /// No step since the last layout: a still lays the wall out settled.
    private var fresh = true

    public init(settings: Settings, seed: UInt64) {
        world = WebWorld(spiders: settings.webSpiders, flies: settings.webFlies, jumper: settings.webJumper,
                         random: WebRandom(seed: seed))
    }

    public var kind: HabitatKind { .web }
    public var time: Double { world.time }

    /// engine.ts `resize`: the wall is laid out again for the new terrain (screens plugged in or out).
    public func layout(terrain: Terrain, cell: CGSize, settings: Settings) {
        self.terrain = terrain
        self.cell = cell
        world.layout(terrain: terrain, cell: cell, settled: false)
        fresh = true
    }

    public func step(_ dt: Double) {
        world.step(dt)
        stepCount += 1
        fresh = false
    }

    public func pointerMoved(_ x: Double, _ y: Double) { world.pointerMoved(x: x, y: y) }
    public func pointerLeft() { world.pointerLeft() }
    /// A click drops a fly (`world.release`), over the terrain. Clicks only arrive while live: the host stops
    /// the pointer for a still, as engine.ts ignores clicks on one.
    public func pointerDown(_ x: Double, _ y: Double) { world.pointerDown(x: x, y: y) }

    /// Spiders, flies and the jumper are rebuilt by the host (`Habitats.needsRebuild`); nothing changes in place.
    public func update(settings: Settings) {}

    /// engine.ts for `?still=1`: a fresh wall is laid out settled (every web finished, flies resting) and stepped
    /// 120 times. A wall that has already lived is held as it is, and settling again changes nothing.
    public func settle() {
        guard fresh else { return }
        world.layout(terrain: terrain, cell: cell, settled: true)
        for _ in 0..<120 { world.step(1.0 / 60) }
        stepCount += 120
        fresh = false
    }

    public func paint(viewport: CGRect, grid: GridSpec, theme: ThemeParams, into canvas: CellCanvas) {
        painter.paint(world, viewport: viewport, grid: grid, theme: theme, into: canvas)
    }
}
