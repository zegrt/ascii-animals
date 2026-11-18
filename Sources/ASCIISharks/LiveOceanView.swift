import AppKit
import Metal
import OceanKit
import QuartzCore

/// A small, self-contained live ocean for UI surfaces (the welcome, About):
/// its own world and viewport, drawn with the app's renderer by its own
/// display link. Not the desktop: it never touches the director's scenes.
final class LiveOceanView: NSView {
    let metalLayer = CAMetalLayer()
    private let renderer: OceanRenderer
    private(set) var world: World
    private var viewport: ViewportRenderer?
    private var clock = OceanClock()
    private var link: CADisplayLink?
    private var sharks: [SharkKind]
    private let density: Double
    private let seed: UInt64
    /// World points per view point. 1 draws at desktop size; 1.8 is "seen from a step back".
    let zoom: CGFloat
    var theme: ThemeParams
    var speed = 1.0
    /// Fish flee the pointer and clicks splash, from this view's own mouse events.
    var handlesMouse = true
    private var tracking: NSTrackingArea?

    init(renderer: OceanRenderer, settings: OceanKit.Settings, theme: ThemeParams, zoom: CGFloat = 1, seed: UInt64 = .random(in: 1...UInt64.max)) {
        self.renderer = renderer
        self.theme = theme
        self.zoom = zoom
        self.seed = seed
        sharks = settings.sharks
        density = settings.fishDensity
        world = World(sharks: settings.sharks, rng: Rng(seed: seed))
        super.init(frame: .zero)
        wantsLayer = true
        metalLayer.device = renderer.device
        metalLayer.pixelFormat = OceanRenderer.outputFormat
        metalLayer.framebufferOnly = true
        metalLayer.maximumDrawableCount = 2
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = CGColor(gray: theme.light ? 0.96 : 0.02, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer { metalLayer }
    override var isFlipped: Bool { false }

    // MARK: Geometry

    private var worldSize: CGSize { CGSize(width: bounds.width * zoom, height: bounds.height * zoom) }
    private var backing: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutOcean()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layoutOcean()
    }

    private func layoutOcean() {
        guard bounds.width >= 1, bounds.height >= 1 else { return }
        let size = worldSize
        let scale = backing / zoom
        metalLayer.contentsScale = backing
        metalLayer.drawableSize = CGSize(width: (bounds.width * backing).rounded(), height: (bounds.height * backing).rounded())
        do {
            if let vp = viewport {
                try vp.resize(pointSize: size, scale: scale)
            } else {
                viewport = try renderer.makeViewport(pointSize: size, scale: scale)
            }
        } catch {
            NSLog("ASCII Sharks: UI ocean viewport failed: %@", "\(error)")
            return
        }
        let first = world.width == 0
        world.resize(width: size.width, height: size.height, cell: viewport!.grid.cell, density: density)
        if first { warm(seconds: 5) }
    }

    /// Step a fresh world until it looks lived-in, with a few frames of wake.
    private func warm(seconds: Double) {
        guard let vp = viewport else { return }
        let total = Int(seconds * 60)
        for i in 0..<total {
            world.step(OceanClock.step)
            if i >= total - 60, let cb = renderer.queue.makeCommandBuffer() {
                vp.encode(world: world, theme: theme, target: nil, commandBuffer: cb)
                cb.commit()
            }
        }
        clock.reset()
    }

    /// A new line-up: a new world, warmed, with a soft fade so the swap doesn't pop.
    func rebuild(sharks newSharks: [SharkKind]) {
        guard newSharks != sharks else { return }
        sharks = newSharks
        world = World(sharks: newSharks, rng: Rng(seed: seed &+ 1))
        guard let vp = viewport else { return }
        world.resize(width: worldSize.width, height: worldSize.height, cell: vp.grid.cell, density: density)
        warm(seconds: 4)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.35
        fade.toValue = 1
        fade.duration = 0.6
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        metalLayer.add(fade, forKey: "rebuild")
    }

    func setTheme(_ t: ThemeParams) {
        theme = t
        metalLayer.backgroundColor = CGColor(gray: t.light ? 0.96 : 0.02, alpha: 1)
    }

    // MARK: Running

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    func start() {
        guard link == nil, window != nil else { return }
        let l = displayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
        clock.reset()
    }

    @objc private func tick(_ l: CADisplayLink) {
        guard let vp = viewport else { return }
        let steps = clock.advance(to: l.targetTimestamp, speed: speed)
        for _ in 0..<steps { world.step(OceanClock.step) }
        guard let drawable = metalLayer.nextDrawable(), let cb = renderer.queue.makeCommandBuffer() else { return }
        vp.encode(world: world, theme: theme, target: drawable.texture, commandBuffer: cb)
        cb.present(drawable)
        cb.commit()
    }

    // MARK: Pointer

    /// A point in this view's coordinates, in world space (top-left origin).
    func worldPoint(_ p: NSPoint) -> (Double, Double) {
        (Double(p.x * zoom), Double((bounds.height - p.y) * zoom))
    }

    func pointer(at p: NSPoint?) {
        guard let p, bounds.contains(p) else { world.pointer.active = false; return }
        let (x, y) = worldPoint(p)
        world.pointer = (x, y, true)
    }

    func splash(at p: NSPoint) {
        let (x, y) = worldPoint(p)
        world.splash(x, y)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        guard handlesMouse else { return }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseMoved(with e: NSEvent) { if handlesMouse { pointer(at: convert(e.locationInWindow, from: nil)) } }
    override func mouseDragged(with e: NSEvent) { if handlesMouse { pointer(at: convert(e.locationInWindow, from: nil)) } }
    override func mouseExited(with e: NSEvent) { if handlesMouse { pointer(at: nil) } }
    override func mouseDown(with e: NSEvent) {
        guard handlesMouse else { return super.mouseDown(with: e) }
        splash(at: convert(e.locationInWindow, from: nil))
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Offscreen

    /// One frame of `world` as an image, for snapshots (no window needed).
    static func image(of world: World, viewport vp: ViewportRenderer, theme: ThemeParams, renderer r: OceanRenderer) -> CGImage? {
        let w = Int((vp.pointSize.width * vp.scale).rounded()), h = Int((vp.pointSize.height * vp.scale).rounded())
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OceanRenderer.outputFormat, width: w, height: h, mipmapped: false)
        d.usage = .renderTarget
        d.storageMode = .managed
        guard let target = r.device.makeTexture(descriptor: d), let cb = r.queue.makeCommandBuffer() else { return nil }
        vp.encode(world: world, theme: theme, target: target, commandBuffer: cb)
        if let blit = cb.makeBlitCommandEncoder() {
            blit.synchronize(resource: target)
            blit.endEncoding()
        }
        cb.commit()
        cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        target.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: info),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
