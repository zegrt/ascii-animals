import CoreGraphics
import CryptoKit
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
        var wake = 0
        for i in stride(from: 0, to: p.count, by: 4) {
            let r = Int(p[i]), g = Int(p[i + 1]), b = Int(p[i + 2])
            if b > 60 && g > 50 && r * 2 < b { wake += 1 }
        }
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
    check("glyphsCentredAtFractionalScale") {
        // 13 pt cells at scale 1.25 are 16.25 px: the atlas slots are 16 px.
        let img = try StillRenderer.render(settings: .defaults, size: CGSize(width: 1800, height: 900), scale: 1.25, warmup: 6,
                                           systemIsDark: true, accent: SIMD3(0.2, 0.5, 1), seed: 5)
        let p = pixels(img), w = img.width, h = img.height
        let slotW = 13 * 1.25, slotH = 19 * 1.25
        let cols = Int(Double(w) / slotW), rows = Int(Double(h) / slotH)
        var lit = [Int](repeating: 0, count: cols * rows)
        var sumX = [Double](repeating: 0, count: cols * rows)
        for y in 0..<h {
            let r = Int(Double(y) / slotH); if r >= rows { continue }
            for x in 0..<w {
                let c = Int(Double(x) / slotW); if c >= cols { continue }
                let off = Double(x) - Double(c) * slotW
                if off < 1.5 { continue } // skip the grid line
                if luma(p, (y * w + x) * 4) > 0.2 {
                    lit[r * cols + c] += 1
                    sumX[r * cols + c] += off
                }
            }
        }
        // Sparse cells hold single glyphs (fish, edges); blocks fill their cells.
        var total = 0.0, n = 0.0
        for i in lit.indices where lit[i] > 2 && Double(lit[i]) < slotW * slotH * 0.15 {
            total += sumX[i]; n += Double(lit[i])
        }
        try expect(n > 200, "too few sparse-cell pixels: \(n)")
        let mean = total / n
        try expect(abs(mean - slotW / 2) < 1.5, "glyph ink centred at \(mean) px, cell centre \(slotW / 2)")
    }
    check("oceanStillUnchanged") {
        // The Ocean's fingerprint, captured before the host refactor (Task 6):
        // any change to how the Ocean draws shows up here.
        let img = try StillRenderer.render(settings: .defaults, size: CGSize(width: 800, height: 500), scale: 2, warmup: 6,
                                           systemIsDark: true, accent: SIMD3(0.2, 0.5, 1), seed: 7)
        let data = img.dataProvider!.data! as Data
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try expect(hash == "c08e379d5657f7750ffecdb18108081e4a23e50b60b4095cc79a5956f85ef08b", "ocean still hash \(hash)")
    }
    check("revealDissolves") {
        // reveal 0: bare background everywhere; 0.5: some cells shown, some not.
        let r = try OceanRenderer(device: device)
        let size = CGSize(width: 400, height: 250)
        let vp = try r.makeViewport(pointSize: size, scale: 1)
        let s = Settings.defaults
        let sim = Habitats.make(s, seed: 7)
        sim.layout(terrain: .single(width: size.width, height: size.height), cell: vp.grid.cell, settings: s)
        for _ in 0..<240 { sim.step(OceanClock.step) }
        let theme = ThemeParams.make(s, systemIsDark: true, accent: SIMD3(0.2, 0.5, 1))
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OceanRenderer.outputFormat, width: 400, height: 250, mipmapped: false)
        d.usage = .renderTarget
        d.storageMode = .managed
        func frame(_ reveal: Float) throws -> [UInt8] {
            let target = r.device.makeTexture(descriptor: d)!, cb = r.queue.makeCommandBuffer()!
            vp.encode(habitat: sim, theme: theme, reveal: reveal, target: target, commandBuffer: cb)
            let blit = cb.makeBlitCommandEncoder()!
            blit.synchronize(resource: target)
            blit.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            var bytes = [UInt8](repeating: 0, count: 400 * 250 * 4)
            target.getBytes(&bytes, bytesPerRow: 400 * 4, from: MTLRegionMake2D(0, 0, 400, 250), mipmapLevel: 0)
            return bytes
        }
        func lit(_ p: [UInt8]) -> Int { stride(from: 0, to: p.count, by: 4).filter { p[$0] > 0 || p[$0 + 1] > 0 || p[$0 + 2] > 0 }.count }
        let none = lit(try frame(0)), half = lit(try frame(0.5)), all = lit(try frame(1))
        try expect(none == 0, "reveal 0 lit \(none) pixels")
        try expect(all > 0 && half > all / 4 && half < all * 3 / 4, "reveal 0.5 lit \(half) of \(all)")
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
