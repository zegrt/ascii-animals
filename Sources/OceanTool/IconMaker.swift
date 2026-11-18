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
        // A small ocean so the one shark fills the frame.
        let ocean = try StillRenderer.render(settings: s, size: CGSize(width: 420, height: 420), scale: 4, warmup: 9,
                                             systemIsDark: true, accent: SIMD3(0.2, 0.5, 1), seed: 11)
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
            ctx.draw(ocean, in: rect)
            let img = ctx.makeImage()!
            try StillRenderer.writePNG(img, to: dir.appendingPathComponent(name + ".png"))
        }
        print("wrote \(dir.path)")
    }
}
