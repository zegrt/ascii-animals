import AppKit
import Metal
import OceanKit
import QuartzCore

/// Borderless, mouse-transparent window at the desktop level: above the
/// system wallpaper, below the icons and every app, on every Space.
final class OceanWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OceanView: NSView {
    let metalLayer = CAMetalLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer { metalLayer }
}

/// One display's ocean: its window, Metal layer, display link, world and GPU state.
final class OceanScreen: NSObject {
    let displayID: CGDirectDisplayID
    let window: OceanWindow
    let view: OceanView
    private(set) var viewport: ViewportRenderer
    private(set) var world: World
    var clock = OceanClock()
    private(set) var link: CADisplayLink?
    /// From the window's occlusion state; ignored until the first frame shows.
    private(set) var visible = true
    private(set) var presented = false
    /// `.still`: draw one settled frame, then stop.
    var stillPending = false
    let onTick: (OceanScreen, CADisplayLink) -> Void
    let onVisibility: () -> Void

    init(screen: NSScreen, renderer: OceanRenderer, settings: Settings,
         onTick: @escaping (OceanScreen, CADisplayLink) -> Void, onVisibility: @escaping () -> Void) throws {
        displayID = screen.displayID
        self.onTick = onTick
        self.onVisibility = onVisibility
        let frame = screen.frame
        window = OceanWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(frame, display: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        view = OceanView(frame: NSRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        let layer = view.metalLayer
        layer.device = renderer.device
        layer.pixelFormat = OceanRenderer.outputFormat
        layer.framebufferOnly = true
        layer.maximumDrawableCount = 2
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.contentsScale = screen.backingScaleFactor
        layer.drawableSize = CGSize(width: frame.width * screen.backingScaleFactor, height: frame.height * screen.backingScaleFactor)
        layer.isOpaque = true
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer.opacity = 0 // fades in after the first frame
        window.contentView = view

        viewport = try renderer.makeViewport(pointSize: frame.size, scale: screen.backingScaleFactor)
        world = OceanScreen.makeWorld(settings, size: frame.size, cell: viewport.grid.cell)
        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
        window.orderFrontRegardless()
        let l = view.displayLink(target: self, selector: #selector(tick(_:)))
        l.isPaused = true
        l.add(to: .main, forMode: .common)
        link = l
    }

    static func makeWorld(_ s: Settings, size: CGSize, cell: CGSize) -> World {
        let w = World(sharks: s.sharks, rng: Rng(seed: UInt64.random(in: 1...UInt64.max)))
        w.resize(width: size.width, height: size.height, cell: cell, density: s.fishDensity)
        return w
    }

    func rebuildWorld(_ s: Settings) {
        world = OceanScreen.makeWorld(s, size: viewport.pointSize, cell: viewport.grid.cell)
        clock.reset()
    }

    func setDensity(_ s: Settings) {
        world.resize(width: viewport.pointSize.width, height: viewport.pointSize.height, cell: viewport.grid.cell, density: s.fishDensity)
    }

    /// Same display, new frame or scale: resize in place so the ocean keeps swimming.
    func fit(to screen: NSScreen, settings: Settings) throws {
        let frame = screen.frame
        window.setFrame(frame, display: true)
        view.metalLayer.contentsScale = screen.backingScaleFactor
        view.metalLayer.drawableSize = CGSize(width: frame.width * screen.backingScaleFactor, height: frame.height * screen.backingScaleFactor)
        try viewport.resize(pointSize: frame.size, scale: screen.backingScaleFactor)
        world.resize(width: frame.width, height: frame.height, cell: viewport.grid.cell, density: settings.fishDensity)
    }

    func setFrameRate(_ fps: Int) {
        let f = Float(fps)
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: f, maximum: f, preferred: f)
    }

    /// Runs the link only when there is something to draw.
    func setRunning(_ running: Bool) {
        let run = running && (visible || !presented)
        if link?.isPaused == run {
            if run { clock.reset() }
            link?.isPaused = !run
        }
    }

    func markPresented() {
        guard !presented else { return }
        presented = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.8
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        view.metalLayer.opacity = 1
        view.metalLayer.add(fade, forKey: "fade")
    }

    @objc private func tick(_ link: CADisplayLink) { onTick(self, link) }

    @objc private func occlusionChanged() {
        visible = window.occlusionState.contains(.visible)
        onVisibility()
    }

    func close() {
        link?.invalidate()
        link = nil
        NotificationCenter.default.removeObserver(self)
        window.orderOut(nil)
    }

    /// Global rect, top-left origin, for pointer routing.
    var viewportRect: CGRect {
        guard let primary = NSScreen.screens.first else { return window.frame }
        return ScreenGeometry.flip(window.frame, primaryHeight: primary.frame.height)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
