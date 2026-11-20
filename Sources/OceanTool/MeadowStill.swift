import CoreGraphics
import Foundation
import Metal
import OceanKit
import simd

/// `OceanTool meadow-still`: a first picture of the Meadow before its world exists (t3). The land is laid out on
/// one screen with the natural breeze blowing, a few of each species fly toward random flowers (or roam) for a
/// while, then one frame is painted through the renderer, as the app would draw it, and written as a PNG.
enum MeadowStill {
    /// Butterflies of each species.
    static let perSpecies = 2

    /// The painter as a habitat, so the renderer draws it (t3 wraps it in the real meadow world).
    final class Scene: CellPainter {
        let land: Meadowland
        let flies: [Butterfly]
        let breeze: Breeze
        let painter = MeadowPainter()
        var clock: Double = 0

        init(land: Meadowland, flies: [Butterfly], breeze: Breeze) {
            self.land = land
            self.flies = flies
            self.breeze = breeze
        }

        var kind: HabitatKind { .web }
        var time: Double { clock }
        var stepCount: Int { 0 }
        func layout(terrain: Terrain, cell: CGSize, settings: Settings) {}
        func step(_ dt: Double) {}
        func pointerMoved(_ x: Double, _ y: Double) {}
        func pointerLeft() {}
        func pointerDown(_ x: Double, _ y: Double) {}
        func update(settings: Settings) {}
        func settle() {}

        func paint(viewport: CGRect, grid: GridSpec, theme: ThemeParams, into canvas: CellCanvas) {
            painter.paint(land: land, butterflies: flies, breeze: breeze, time: clock, viewport: viewport, grid: grid,
                          theme: theme, into: canvas)
        }
    }

    /// A flower this species feeds on, drawn by its weights; nil when the meadow has none.
    static func flower(for b: Butterfly, _ land: Meadowland, _ random: WebRandom) -> Int? {
        var total: Double = 0
        for f in land.flowers { total += b.species.flowerWeights[f.kind] ?? 0 }
        guard total > 0 else { return nil }
        var u: Double = random.unit() * total
        for (i, f) in land.flowers.enumerated() {
            u -= b.species.flowerWeights[f.kind] ?? 0
            if u < 0 { return i }
        }
        return nil
    }

    /// A pose sheet: each species (a row) in the poses the brief asks to read at a glance, left to right: open
    /// (wings level), the bottom of the downstroke, the upstroke (s ≈ 0.5), banked one way and the other, near
    /// the clap, and closed (at rest, the underside edge-on), facing up the screen.
    static func poseSheet(size: CGSize, cell: CGSize, random: WebRandom) -> [Butterfly] {
        let deg: Double = Double.pi / 180
        let poses: [(stroke: Double, bank: Double)] = [(0, 0), (-35 * deg, 0), (60 * deg, 0), (25 * deg, 40 * deg),
                                                       (25 * deg, -55 * deg), (78 * deg, 0), (90 * deg, 0)]
        var out: [Butterfly] = []
        let w: Double = Double(size.width), h: Double = Double(size.height)
        for (row, kind) in ButterflyKind.allCases.enumerated() {
            for (col, pose) in poses.enumerated() {
                let x: Double = w * (Double(col) + 0.5) / Double(poses.count)
                let y: Double = h * (0.13 + 0.17 * Double(row))
                let b = Butterfly(kind: kind, x: x, y: y, random: random)
                b.scale = Double(cell.width) / 13
                b.size = 1
                b.fitDrawing(to: size)
                b.heading = -Double.pi / 2
                b.pitch = 0
                b.stroke = pose.stroke
                b.bank = pose.bank
                b.state = .fly
                out.append(b)
            }
        }
        return out
    }

    static func run(out: URL, size: CGSize, scale: CGFloat, light: Bool, calm: Bool, seconds: Double, seed: UInt64,
                    poses: Bool = false) throws {
        let cell = GridSpec.cell(forWidth: Double(size.width))
        let terrain = Terrain.single(width: Double(size.width), height: Double(size.height))
        let random = WebRandom(seed: seed)
        let land = Meadowland(random: random)
        land.layout(terrain: terrain, cell: cell)
        let breeze = Breeze(bounds: terrain.bounds, cell: cell)
        var flies: [Butterfly] = []
        for kind in ButterflyKind.allCases {
            for _ in 0..<perSpecies {
                let x: Double = random.range(0.1, 0.9) * Double(size.width)
                let y: Double = random.range(0.2, 0.75) * Double(size.height)
                let b = Butterfly(kind: kind, x: x, y: y, random: random)
                b.scale = Double(cell.width) / 13
                // A screen too small for one whole butterfly (the Settings preview) draws them smaller.
                b.fitDrawing(to: size)
                flies.append(b)
            }
        }
        // Each flies toward a flower for a few seconds, or roams; then chooses again.
        var targets = [Int?](repeating: nil, count: flies.count)
        var left = [Double](repeating: 0, count: flies.count)
        let dt: Double = 1.0 / 60.0
        let steps = max(1, Int(seconds * 60))
        for _ in 0..<steps {
            breeze.step(dt, random: random)
            land.step(dt, breeze: breeze)
            for (k, b) in flies.enumerated() {
                left[k] -= dt
                if left[k] <= 0 {
                    targets[k] = random.unit() < 0.7 ? flower(for: b, land, random) : nil
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
        if poses { flies = poseSheet(size: size, cell: cell, random: random) }
        let scene = Scene(land: land, flies: flies, breeze: breeze)
        scene.clock = Double(steps) * dt

        var s = Settings.defaults
        s.appearance = light ? .light : .dark
        s.calm = calm
        let theme = ThemeParams.make(s, systemIsDark: true, accent: SIMD3<Float>(0.2, 0.5, 1))
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError(description: "no Metal device") }
        let r = try OceanRenderer(device: device)
        let vp = try r.makeViewport(pointSize: size, scale: scale, cell: cell)
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OceanRenderer.outputFormat, width: w, height: h, mipmapped: false)
        d.usage = .renderTarget
        d.storageMode = .managed
        guard let target = r.device.makeTexture(descriptor: d), let cb = r.queue.makeCommandBuffer() else {
            throw RenderError(description: "no frame target")
        }
        vp.encode(habitat: scene, theme: theme, target: target, commandBuffer: cb)
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
        try StillRenderer.writePNG(image, to: out)
        print("wrote \(out.path) \(w)x\(h): \(land.flowers.count) plants, \(flies.count) butterflies, \(String(format: "%.0f", seconds)) s")
    }
}
