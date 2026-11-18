import CoreGraphics
import Foundation
import ImageIO
import Metal
import OceanKit

private func pixels(_ img: CGImage) -> [UInt8] {
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buf
}

private func luma(_ p: [UInt8], _ i: Int) -> Double {
    (0.2126 * Double(p[i]) + 0.7152 * Double(p[i + 1]) + 0.0722 * Double(p[i + 2])) / 255
}

private func still(_ s: Settings = .defaults, warmup: Double = 4, seed: UInt64 = 1, dark: Bool = true) throws -> CGImage {
    try StillRenderer.render(settings: s, size: CGSize(width: 800, height: 500), scale: 2, warmup: warmup,
                             systemIsDark: dark, accent: SIMD3(0.2, 0.5, 1), seed: seed)
}

func renderChecks() {
    guard let device = MTLCreateSystemDefaultDevice() else {
        check("metalDevice") { try expect(false, "no Metal device") }
        return
    }
    check("shadersCompile") { _ = try OceanRenderer(device: device) }
    check("atlasHasInk") {
        let a = try GlyphAtlas.makeBytes(cell: CGSize(width: 8, height: 12), scale: 2)
        for g in 0..<GlyphAtlas.glyphs.count {
            var ink = 0
            for y in 0..<a.height { for x in 0..<a.slotWidth where a.bytes[y * a.width + g * a.slotWidth + x] > 128 { ink += 1 } }
            try expect(ink > 0, "glyph \(GlyphAtlas.glyphs[g]) has no ink")
        }
    }
    check("atlasUpright") {
        let a = try GlyphAtlas.makeBytes(cell: CGSize(width: 8, height: 12), scale: 2)
        func inkRows(_ ch: String) -> (top: Int, bottom: Int) {
            let g = GlyphAtlas.glyphs.firstIndex(of: ch)!
            var top = 0, bottom = 0
            for y in 0..<a.height { for x in 0..<a.slotWidth where a.bytes[y * a.width + g * a.slotWidth + x] > 128 {
                if y < a.height / 2 { top += 1 } else { bottom += 1 }
            } }
            return (top, bottom)
        }
        let dot = inkRows("."), tick = inkRows("`")
        try expect(dot.bottom > 0 && dot.top == 0, "'.' ink top \(dot.top) bottom \(dot.bottom)")
        try expect(tick.top > 0 && tick.bottom == 0, "'`' ink top \(tick.top) bottom \(tick.bottom)")
    }
    check("stillNotBlank") {
        let p = pixels(try still())
        let lit = stride(from: 0, to: p.count, by: 4).filter { luma(p, $0) > 0.15 }.count
        try expect(Double(lit) / Double(p.count / 4) > 0.01, "lit fraction \(Double(lit) / Double(p.count / 4))")
    }
    check("stillAnimates") {
        let a = pixels(try still(warmup: 4)), b = pixels(try still(warmup: 4.5))
        var diff = 0
        for i in stride(from: 0, to: a.count, by: 4) where a[i] != b[i] || a[i + 1] != b[i + 1] { diff += 1 }
        try expect(Double(diff) / Double(a.count / 4) > 0.005, "only \(diff) pixels changed")
    }
    check("stillHasWake") {
        let p = pixels(try still())
        // Wake dots are the cyan theme colour blended over black: blue-green high, red low.
        let wake = stride(from: 0, to: p.count, by: 4).filter { p[$0 + 2] > 60 && p[$0 + 1] > 50 && Int(p[$0]) * 2 < Int(p[$0 + 2]) }.count
        try expect(wake > 50, "wake pixels \(wake)")
    }
    check("stillLightBackground") {
        var s = Settings.defaults; s.appearance = .light
        let p = pixels(try still(s))
        // Pixel (3,3): inside the first cell, away from the grid line.
        let i = (3 * 1600 + 3) * 4
        try expect(luma(p, i) > 0.8, "corner luma \(luma(p, i))")
    }
    check("stillCalmDimmer") {
        var s = Settings.defaults; s.calm = true
        func mean(_ p: [UInt8]) -> Double { stride(from: 0, to: p.count, by: 4).reduce(0) { $0 + luma(p, $1) } / Double(p.count / 4) }
        let d = mean(pixels(try still())), c = mean(pixels(try still(s)))
        try expect(c < d * 0.75, "calm \(c) vs default \(d)")
    }
    check("stillPNGSize") {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ocean-check-\(getpid()).png")
        try StillRenderer.writePNG(try still(warmup: 1), to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        try expect(img.width == 1600 && img.height == 1000, "png \(img.width)x\(img.height)")
    }
}
