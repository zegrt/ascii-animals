import CoreGraphics
import Foundation
import OceanKit

/// `OceanTool meadow-desk <dir>`: the Meadow on the owner's desk, one shared scene over a 2560 x 1440 monitor above
/// the 1800 x 1169 built-in display (offset 375 pt, as `bench --desk`), drawn as the app draws each screen and laid
/// out where the screens are, the space around them dark grey. Frames at `fps`, after `warmup` seconds.
enum MeadowDesk {
    /// The desk's bounds in points (the image at scale 1).
    static let size = CGSize(width: 2560, height: 2609)

    static func run(out dir: URL, seed: UInt64, seconds: Double, fps: Int, warmup: Double, scale: CGFloat, light: Bool) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var s = Settings.defaults
        s.habitat = .meadow
        if light { s.appearance = .light }
        let screens = [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1800, height: 1169)]
        let terrain = Terrain(rects: screens)
        let cell = GridSpec.cell(forWidth: 2560)
        let sim = MeadowSim(settings: s, seed: seed)
        sim.layout(terrain: terrain, cell: cell, settings: s)
        let theme = ThemeParams.make(s, systemIsDark: true, accent: SIMD3(0.2, 0.5, 1))
        let rec = try SceneRecorder(habitat: sim, viewports: screens, cell: cell, scale: scale, theme: theme)
        for _ in 0..<max(1, Int(warmup * 60)) { sim.step(OceanClock.step) }
        let b = terrain.bounds
        let W = Int((b.width * scale).rounded()), H = Int((b.height * scale).rounded())
        let frames = max(1, Int(seconds * Double(fps)))
        for f in 0..<frames {
            if f > 0 { for _ in 0..<(60 / fps) { sim.step(OceanClock.step) } }
            let images = try rec.capture()
            guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw RenderError(description: "no context") }
            ctx.setFillColor(CGColor(gray: 0.18, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            for (img, r) in zip(images, screens) {
                // CoreGraphics' origin is bottom-left.
                let x = (r.minX - b.minX) * scale, y = CGFloat(H) - (r.maxY - b.minY) * scale
                ctx.draw(img, in: CGRect(x: x, y: y, width: r.width * scale, height: r.height * scale))
            }
            guard let img = ctx.makeImage() else { throw RenderError(description: "no image") }
            try StillRenderer.writePNG(img, to: dir.appendingPathComponent(String(format: "f%04d.png", f)))
        }
        let w = sim.world
        let off = w.flies.filter { !terrain.contains(SIMD2($0.x, $0.y)) }.count
        print("wrote \(frames) frames to \(dir.path); \(w.flies.count) butterflies (\(off) off the screens now), \(w.flowers.all.count) flowers")
    }
}
