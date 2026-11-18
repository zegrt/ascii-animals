import CoreGraphics
import Foundation
import OceanKit

/// The app icon: a crop of the ocean with a big shark in it, on a rounded square.
enum IconMaker {
    static func write(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var s = Settings.defaults
        s.sharks = [.greathammer]
        s.fishDensity = 1.4
        // The ocean keeps its middle clear, so instead of hoping the shark is
        // centred, find a moment it swims level and fully in frame, then crop
        // a square around it.
        let side = 420.0, seed: UInt64 = 11
        let probe = World(sharks: s.sharks, rng: Rng(seed: seed))
        probe.resize(width: side, height: side, cell: GridSpec.cell(forWidth: side), density: s.fishDensity)
        var best = (score: Double.infinity, time: 6.0, cx: side / 2, cy: side / 2, length: 170.0)
        for step in 1...(60 * 60) {
            probe.step(OceanClock.step)
            let t = Double(step) / 60
            guard t >= 4, let sh = probe.sharks.first else { continue }
            let n = sh.nodes, last = World.sharkNodes - 1
            let cx = (n[0] + n[last * 2]) / 2, cy = (n[1] + n[last * 2 + 1]) / 2
            let half = sh.length * 0.62
            guard cx - half > 0, cx + half < side, cy - half > 0, cy + half < side else { continue }
            // Level and swimming right reads best.
            let score = abs(sin(sh.heading)) + (cos(sh.heading) < 0 ? 0.5 : 0)
            if score < best.score { best = (score, t, cx, cy, sh.length) }
        }
        let scale = 4.0
        let ocean = try StillRenderer.render(settings: s, size: CGSize(width: side, height: side), scale: scale, warmup: best.time,
                                             systemIsDark: true, accent: SIMD3(0.2, 0.5, 1), seed: seed)
        let half = best.length * 0.62
        let crop = CGRect(x: (best.cx - half) * scale, y: (best.cy - half) * scale, width: half * 2 * scale, height: half * 2 * scale)
        guard let icon = ocean.cropping(to: crop.integral) else { throw CocoaError(.fileWriteUnknown) }
        let sizes: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, px) in sizes {
            let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            // macOS icon grid: 824/1024 rounded square, radius ~185/1024.
            let inset = CGFloat(px) * 100 / 1024
            let rect = CGRect(x: inset, y: inset, width: CGFloat(px) - inset * 2, height: CGFloat(px) - inset * 2)
            let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
            ctx.addPath(path)
            ctx.clip()
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(rect)
            ctx.draw(icon, in: rect)
            let img = ctx.makeImage()!
            try StillRenderer.writePNG(img, to: dir.appendingPathComponent(name + ".png"))
        }
        print("wrote \(dir.path)")
    }
}
