import CoreGraphics
import Foundation
import Metal
import OceanKit
import simd

/// `OceanTool meadow-frames`: the `meadow-still` scene (MeadowStill.swift) as a film, so the director can watch the
/// butterflies move before behaviours (t3) exist. The land is laid out on one screen, the natural breeze blows, two
/// of each species fly toward random flowers (or roam), all stepped at the fixed 60 Hz from the first step, and
/// every frame is painted through the renderer, as the app draws it, and written as `f%05d.png`.
///
/// Slow motion (`slow` K > 1) shows 1/K of the time per frame. The world still steps only at 60 Hz, so a state is
/// shown on as many frames as it lasts (at 30 fps and K = 4, each step on two frames): nothing in between is made
/// up, and a change that happens in one step shows as one jump.
enum MeadowFrames {
    static func run(dir: URL, size: CGSize, scale: CGFloat, light: Bool, seconds: Double, fps: Int, slow: Int,
                    seed: UInt64) throws {
        let cell = GridSpec.cell(forWidth: Double(size.width))
        let terrain = Terrain.single(width: Double(size.width), height: Double(size.height))
        let random = WebRandom(seed: seed)
        let land = Meadowland(random: random)
        land.layout(terrain: terrain, cell: cell)
        let breeze = Breeze(bounds: terrain.bounds, cell: cell)
        // The still's butterflies, made in the same order from the same random numbers.
        var flies: [Butterfly] = []
        for kind in ButterflyKind.allCases {
            for _ in 0..<MeadowStill.perSpecies {
                let x: Double = random.range(0.1, 0.9) * Double(size.width)
                let y: Double = random.range(0.2, 0.75) * Double(size.height)
                let b = Butterfly(kind: kind, x: x, y: y, random: random)
                b.scale = Double(cell.width) / 13
                b.fitDrawing(to: size)
                flies.append(b)
            }
        }
        let scene = MeadowStill.Scene(land: land, flies: flies, breeze: breeze)

        // One step of the still's loop: each flies toward a flower for a few seconds, or roams; then chooses again.
        var targets = [Int?](repeating: nil, count: flies.count)
        var left = [Double](repeating: 0, count: flies.count)
        let dt: Double = OceanClock.step
        func step() {
            breeze.step(dt, random: random)
            land.step(dt, breeze: breeze)
            for (k, b) in flies.enumerated() {
                left[k] -= dt
                if left[k] <= 0 {
                    targets[k] = random.unit() < 0.7 ? MeadowStill.flower(for: b, land, random) : nil
                    left[k] = random.range(3, 8)
                }
                var target: SIMD2<Double>? = nil
                if let i = targets[k] {
                    let h: SIMD2<Double> = land.head(i)
                    let d: Double = simd_length(h - SIMD2<Double>(b.x, b.y))
                    b.state = d < 6 * b.wingspan ? .approach : .fly
                    target = h
                } else {
                    b.state = .fly
                }
                b.fly(dt, target: target, breeze: breeze, terrain: terrain, random: random)
            }
        }

        var s = Settings.defaults
        s.appearance = light ? .light : .dark
        let theme = ThemeParams.make(s, systemIsDark: true, accent: SIMD3<Float>(0.2, 0.5, 1))
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError(description: "no Metal device") }
        let r = try OceanRenderer(device: device)
        let vp = try r.makeViewport(pointSize: size, scale: scale, cell: cell)
        let w: Int = Int((size.width * scale).rounded()), h: Int = Int((size.height * scale).rounded())
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OceanRenderer.outputFormat, width: w, height: h,
                                                         mipmapped: false)
        d.usage = .renderTarget
        d.storageMode = .managed
        guard let target = r.device.makeTexture(descriptor: d) else { throw RenderError(description: "no frame target") }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let info: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw RenderError(description: "no sRGB") }

        /// Paints the scene as it stands and returns the image.
        func paint() throws -> CGImage {
            guard let cb = r.queue.makeCommandBuffer() else { throw RenderError(description: "no command buffer") }
            vp.encode(habitat: scene, theme: theme, target: target, commandBuffer: cb)
            if let blit = cb.makeBlitCommandEncoder() {
                blit.synchronize(resource: target)
                blit.endEncoding()
            }
            cb.commit()
            cb.waitUntilCompleted()
            target.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                                      decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            else { throw RenderError(description: "could not make image") }
            return image
        }

        // Frame i shows the world after floor(i · 60 / (fps · slow)) steps: at real speed 60/fps steps a frame, in
        // slow motion a state held for several frames. A state is painted once (as the app paints each state once)
        // and its file copied for the frames that repeat it.
        let count: Int = max(1, Int((seconds * Double(fps)).rounded()))
        let perSecond: Int = fps * slow
        var stepped: Int = 0
        var last: URL? = nil
        for i in 0..<count {
            let want: Int = i * 60 / perSecond
            let file: URL = dir.appendingPathComponent(String(format: "f%05d.png", i))
            if want == stepped, i > 0, let last {
                try? FileManager.default.removeItem(at: file)
                try FileManager.default.copyItem(at: last, to: file)
                continue
            }
            while stepped < want {
                step()
                stepped += 1
            }
            scene.clock = Double(stepped) * dt
            try StillRenderer.writePNG(try paint(), to: file)
            last = file
        }
        let shown: Double = Double(count) / Double(perSecond)
        print("wrote \(count) frames to \(dir.path) \(w)x\(h): \(land.flowers.count) plants, \(flies.count) butterflies, "
            + String(format: "%.2f s of meadow time, %d steps, %d fps, 1/%d speed", shown, stepped, fps, slow))
    }
}
