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

/// One display: its window, Metal layer, display link and GPU state, looking
/// into a scene's habitat through `oceanRect`.
final class OceanScreen: NSObject {
    let displayID: CGDirectDisplayID
    let window: OceanWindow
    let view: OceanView
    private(set) var viewport: ViewportRenderer
    private(set) var scene: HabitatScene
    /// This screen's area in the scene's ocean space.
    private(set) var oceanRect: CGRect
    private(set) var link: CADisplayLink?
    /// From the window's occlusion state; ignored until the first frame shows.
    private(set) var visible = true
    private(set) var presented = false
    /// `.still`: draw one settled frame, then stop.
    var stillPending = false
    let onTick: (OceanScreen, CADisplayLink) -> Void
    let onVisibility: () -> Void

    init(screen: NSScreen, renderer: OceanRenderer, scene: HabitatScene, rect: CGRect,
         onTick: @escaping (OceanScreen, CADisplayLink) -> Void, onVisibility: @escaping () -> Void) throws {
        displayID = screen.displayID
        self.scene = scene
        oceanRect = rect
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

        viewport = try renderer.makeViewport(pointSize: frame.size, scale: screen.backingScaleFactor, cell: scene.plan.cell)
        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
        window.orderFrontRegardless()
        let l = view.displayLink(target: self, selector: #selector(tick(_:)))
        l.isPaused = true
        l.add(to: .main, forMode: .common)
        link = l
    }

    /// Same display, maybe a new frame, scale or scene.
    func fit(to screen: NSScreen, scene: HabitatScene, rect: CGRect) throws {
        self.scene = scene
        oceanRect = rect
        let frame = screen.frame
        window.setFrame(frame, display: true)
        view.metalLayer.contentsScale = screen.backingScaleFactor
        view.metalLayer.drawableSize = CGSize(width: frame.width * screen.backingScaleFactor, height: frame.height * screen.backingScaleFactor)
        try viewport.resize(pointSize: frame.size, scale: screen.backingScaleFactor, cell: scene.plan.cell)
    }

    func setFrameRate(_ fps: Int) {
        let f = Float(fps)
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: f, maximum: f, preferred: f)
    }

    /// Runs the link only when there is something to draw.
    func setRunning(_ running: Bool) {
        let run = running && (visible || !presented)
        if link?.isPaused == run { link?.isPaused = !run }
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
