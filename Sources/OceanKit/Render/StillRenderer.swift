import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Renders a warmed-up ocean offscreen: for the system wallpaper, the app
/// icon and the checks.
public enum StillRenderer {
    public static func render(settings: Settings, size: CGSize, scale: CGFloat, warmup: Double,
                              systemIsDark: Bool, accent: SIMD3<Float>, seed: UInt64,
                              renderer: OceanRenderer? = nil) throws -> CGImage {
        guard let device = renderer?.device ?? MTLCreateSystemDefaultDevice() else {
            throw RenderError(description: "no Metal device")
        }
        let r = try renderer ?? OceanRenderer(device: device)
        let vp = try r.makeViewport(pointSize: size, scale: scale)
        let world = World(sharks: settings.sharks, rng: Rng(seed: seed))
        world.resize(width: size.width, height: size.height, cell: vp.grid.cell, density: settings.fishDensity)
        let theme = ThemeParams.make(settings, systemIsDark: systemIsDark, accent: accent)

        // Step the ocean; the wake only needs the last few seconds (it fades in ~2 s).
        let total = max(1, Int(warmup * 60))
        let wakeFrom = max(0, total - 180)
        var last: MTLCommandBuffer?
        for i in 0..<total {
            world.step(OceanClock.step)
            if i >= wakeFrom, let cb = r.queue.makeCommandBuffer() {
                vp.encode(world: world, theme: theme, steps: 1, target: nil, commandBuffer: cb)
                cb.commit()
                last = cb
            }
            world.events.removeAll()
        }
        last?.waitUntilCompleted()

        return try FrameRecorder.compose(vp, world: world, theme: theme, steps: 0, size: size, scale: scale, renderer: r)
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
    private let world: World
    private let theme: ThemeParams
    private let size: CGSize
    private let scale: CGFloat

    public init(settings: Settings, size: CGSize, scale: CGFloat, seed: UInt64, warmup: Double,
                systemIsDark: Bool = true, accent: SIMD3<Float> = SIMD3(0.2, 0.5, 1)) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError(description: "no Metal device") }
        renderer = try OceanRenderer(device: device)
        viewport = try renderer.makeViewport(pointSize: size, scale: scale)
        world = World(sharks: settings.sharks, rng: Rng(seed: seed))
        world.resize(width: size.width, height: size.height, cell: viewport.grid.cell, density: settings.fishDensity)
        theme = ThemeParams.make(settings, systemIsDark: systemIsDark, accent: accent)
        self.size = size
        self.scale = scale
        // Warm up with the wake running for the last few seconds.
        let total = max(1, Int(warmup * 60)), wakeFrom = max(0, total - 180)
        for i in 0..<total {
            world.step(OceanClock.step)
            if i >= wakeFrom, let cb = renderer.queue.makeCommandBuffer() {
                viewport.encode(world: world, theme: theme, steps: 1, target: nil, commandBuffer: cb)
                cb.commit()
            }
            world.events.removeAll()
        }
    }

    /// Advance `steps` simulation steps (1/60 s each) and render a frame.
    public func next(steps: Int) throws -> CGImage {
        for _ in 0..<steps { world.step(OceanClock.step) }
        let img = try FrameRecorder.compose(viewport, world: world, theme: theme, steps: steps, size: size, scale: scale, renderer: renderer)
        world.events.removeAll()
        return img
    }

    static func compose(_ vp: ViewportRenderer, world: World, theme: ThemeParams, steps: Int, size: CGSize, scale: CGFloat,
                        renderer r: OceanRenderer) throws -> CGImage {
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OceanRenderer.outputFormat, width: w, height: h, mipmapped: false)
        d.usage = .renderTarget
        d.storageMode = .managed
        guard let target = r.device.makeTexture(descriptor: d), let cb = r.queue.makeCommandBuffer() else {
            throw RenderError(description: "no frame target")
        }
        vp.encode(world: world, theme: theme, steps: steps, target: target, commandBuffer: cb)
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
