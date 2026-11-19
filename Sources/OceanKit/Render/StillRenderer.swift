import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Renders a warmed-up habitat offscreen: for the system wallpaper, the app
/// icon, the previews and the checks.
public enum StillRenderer {
    /// `settle`: the habitat's still (`settle()`: the Web's settled wall, as the original's ?still=1) before the
    /// warm-up steps. nil: every habitat but the Ocean (whose stills stay as they were).
    public static func render(settings: Settings, size: CGSize, scale: CGFloat, warmup: Double,
                              systemIsDark: Bool, accent: SIMD3<Float>, seed: UInt64,
                              renderer: OceanRenderer? = nil, settle: Bool? = nil) throws -> CGImage {
        guard let device = renderer?.device ?? MTLCreateSystemDefaultDevice() else {
            throw RenderError(description: "no Metal device")
        }
        let r = try renderer ?? OceanRenderer(device: device)
        let vp = try r.makeViewport(pointSize: size, scale: scale)
        let sim = Habitats.make(settings, seed: seed)
        sim.layout(terrain: .single(width: size.width, height: size.height), cell: vp.grid.cell, settings: settings)
        let theme = ThemeParams.make(settings, systemIsDark: systemIsDark, accent: accent)
        if settle ?? (settings.habitat != .ocean) { sim.settle() }

        // Step the habitat; the wake only needs the last few seconds (it fades in ~2 s).
        let total = max(1, Int(warmup * 60))
        let wakeFrom = max(0, total - 180)
        var last: MTLCommandBuffer?
        for i in 0..<total {
            sim.step(OceanClock.step)
            if i >= wakeFrom, let cb = r.queue.makeCommandBuffer() {
                vp.encode(habitat: sim, theme: theme, target: nil, commandBuffer: cb)
                cb.commit()
                last = cb
            }
        }
        last?.waitUntilCompleted()

        return try FrameRecorder.compose(size: size, scale: scale, renderer: r) { target, cb in
            vp.encode(habitat: sim, theme: theme, target: target, commandBuffer: cb)
        }
    }

    /// One viewport of an existing world, as it looks right now (no wake history).
    public static func snapshot(_ world: World, viewport: CGRect, cell: CGSize, theme: ThemeParams, scale: CGFloat,
                                renderer r: OceanRenderer) throws -> CGImage {
        let vp = try r.makeViewport(pointSize: viewport.size, scale: scale, cell: cell)
        return try FrameRecorder.compose(size: viewport.size, scale: scale, renderer: r) { target, cb in
            vp.encode(world: world, viewport: viewport, theme: theme, target: target, commandBuffer: cb)
        }
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RenderError(description: "cannot write \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) { throw RenderError(description: "cannot write \(url.path)") }
    }
}

/// Renders a continuous run frame by frame (README animations, previews).
public final class FrameRecorder {
    private let renderer: OceanRenderer
    private let viewport: ViewportRenderer
    private let sim: HabitatSim
    private let theme: ThemeParams
    private let size: CGSize
    private let scale: CGFloat

    public init(settings: Settings, size: CGSize, scale: CGFloat, seed: UInt64, warmup: Double,
                systemIsDark: Bool = true, accent: SIMD3<Float> = SIMD3(0.2, 0.5, 1)) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError(description: "no Metal device") }
        renderer = try OceanRenderer(device: device)
        viewport = try renderer.makeViewport(pointSize: size, scale: scale)
        sim = Habitats.make(settings, seed: seed)
        sim.layout(terrain: .single(width: size.width, height: size.height), cell: viewport.grid.cell, settings: settings)
        theme = ThemeParams.make(settings, systemIsDark: systemIsDark, accent: accent)
        self.size = size
        self.scale = scale
        // Warm up with the wake running for the last few seconds.
        let total = max(1, Int(warmup * 60)), wakeFrom = max(0, total - 180)
        for i in 0..<total {
            sim.step(OceanClock.step)
            if i >= wakeFrom, let cb = renderer.queue.makeCommandBuffer() {
                viewport.encode(habitat: sim, theme: theme, target: nil, commandBuffer: cb)
                cb.commit()
            }
        }
    }

    /// Advance `steps` simulation steps (1/60 s each) and render a frame.
    public func next(steps: Int) throws -> CGImage {
        for _ in 0..<steps { sim.step(OceanClock.step) }
        return try FrameRecorder.compose(size: size, scale: scale, renderer: renderer) { [viewport, sim, theme] target, cb in
            viewport.encode(habitat: sim, theme: theme, target: target, commandBuffer: cb)
        }
    }

    /// A `size` x `scale` frame: `draw` encodes into the target, then the
    /// pixels are read back.
    static func compose(size: CGSize, scale: CGFloat, renderer r: OceanRenderer,
                        draw: (MTLTexture, MTLCommandBuffer) -> Void) throws -> CGImage {
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OceanRenderer.outputFormat, width: w, height: h, mipmapped: false)
        d.usage = .renderTarget
        d.storageMode = .managed
        guard let target = r.device.makeTexture(descriptor: d), let cb = r.queue.makeCommandBuffer() else {
            throw RenderError(description: "no frame target")
        }
        draw(target, cb)
        if let blit = cb.makeBlitCommandEncoder() {
            blit.synchronize(resource: target)
            blit.endEncoding()
        }
        cb.commit()
        cb.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        target.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: info),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw RenderError(description: "could not make image") }
        return image
    }
}

/// Several viewports of one habitat, captured together (shared-ocean previews).
/// The caller steps the habitat; each capture runs the wake for the steps since
/// the last one.
public final class SceneRecorder {
    private let renderer: OceanRenderer
    private let sim: HabitatSim
    private let views: [(rect: CGRect, vp: ViewportRenderer)]
    private let theme: ThemeParams
    private let scale: CGFloat

    public init(habitat: HabitatSim, viewports: [CGRect], cell: CGSize, scale: CGFloat, theme: ThemeParams) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError(description: "no Metal device") }
        let r = try OceanRenderer(device: device)
        renderer = r
        sim = habitat
        self.theme = theme
        self.scale = scale
        views = try viewports.map { ($0, try r.makeViewport(pointSize: $0.size, scale: scale, cell: cell)) }
    }

    /// Advance the wake only (cheap; for warm-up).
    public func advanceWake() {
        for v in views {
            guard let cb = renderer.queue.makeCommandBuffer() else { continue }
            v.vp.encode(habitat: sim, viewport: v.rect, theme: theme, target: nil, commandBuffer: cb)
            cb.commit()
        }
    }

    /// One image per viewport, in the order given.
    public func capture() throws -> [CGImage] {
        try views.map { v in
            try FrameRecorder.compose(size: v.rect.size, scale: scale, renderer: renderer) { target, cb in
                v.vp.encode(habitat: sim, viewport: v.rect, theme: theme, target: target, commandBuffer: cb)
            }
        }
    }
}
