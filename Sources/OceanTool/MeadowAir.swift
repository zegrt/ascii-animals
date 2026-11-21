import CoreGraphics
import CoreText
import Foundation
import ImageIO
import OceanKit

/// `OceanTool meadow-air`: one seed's planted meadow and its air, drawn plainly for checking the port against the
/// sketch (task m1). Two panels side by side:
/// - left: the sketch's own render at the same seed and size (`--under`, a PNG), with every flower the Swift port
///   planted outlined on top (its bloom radius, a dot at its head, its id);
/// - right: the Swift air after `--seconds` of steps: speed as shade (black still, green 50 pt/s, gold 100 pt/s),
///   an arrow per stir-grid sample, the pointer's stir ringed in white, and the flowers as discs by kind with their
///   leaves.
/// With `--stir`, a pointer sweeps across the middle during the last second.
enum MeadowAir {
    static let kindColours: [FlowerKind: (CGFloat, CGFloat, CGFloat)] = [
        .daisy: (0.95, 0.95, 0.92), .coneflower: (0.78, 0.36, 0.55), .milkweed: (0.72, 0.52, 0.66), .fennel: (0.86, 0.78, 0.28),
        .clover: (0.85, 0.62, 0.78), .mustard: (0.95, 0.85, 0.2), .dandelion: (0.98, 0.82, 0.12),
    ]

    static func run(out: URL, size: CGSize, seed: Int32, seconds: Double, under: URL?, stir: Bool) throws {
        let W = Double(size.width), H = Double(size.height)
        let terrain = Terrain.single(width: W, height: H)
        let cell = GridSpec.cell(forWidth: W)
        let breeze = Breeze(terrain: terrain, cell: cell)
        let flowers = Flowers(terrain: terrain, cell: cell, breeze: breeze)
        let streams = MeadowRandom.pair(seed: seed)
        flowers.plant(rng: streams.sim)
        let steps = max(0, Int((seconds * 60).rounded()))
        for k in 0..<steps {
            if stir && k >= steps - 60 {
                let u: Double = Double(k - (steps - 60)) / 60
                breeze.pointerMoved(x: W * (0.15 + 0.7 * u), y: H * (0.5 + 0.2 * sin(6 * u)))
            }
            breeze.step(OceanClock.step)
            flowers.step(OceanClock.step)
        }

        let w = Int(size.width), h = Int(size.height)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w * 2 + 16, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w * 2 + 16, height: h))
        // y down, as ocean space.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        // ── left: the sketch, with the port's flowers outlined ──
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if let under, let src = CGImageSourceCreateWithURL(under as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            ctx.restoreGState()
        }
        // Planted positions: the left panel shows the meadow as planted (no sway), as the sketch's first frame.
        let fresh = Flowers(terrain: terrain, cell: cell, breeze: Breeze(terrain: terrain, cell: cell))
        fresh.plant(rng: MeadowRandom.pair(seed: seed).sim)
        ctx.setLineWidth(1.5)
        for f in fresh.all {
            ctx.setStrokeColor(CGColor(red: 0.2, green: 0.95, blue: 1, alpha: 0.9))
            ctx.strokeEllipse(in: CGRect(x: f.x - f.radius, y: f.y - f.radius, width: 2 * f.radius, height: 2 * f.radius))
            ctx.setFillColor(CGColor(red: 0.2, green: 0.95, blue: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: f.x - 3, y: f.y - 3, width: 6, height: 6))
            label("\(f.id) \(f.kind.name)", at: CGPoint(x: f.x + 5, y: f.y + 4), ctx: ctx, height: h)
        }

        // ── right: the port's air and flowers ──
        let ox = CGFloat(w + 16)
        ctx.saveGState()
        ctx.translateBy(x: ox, y: 0)
        let tile = 8.0
        var y = 0.0
        while y < H {
            var x = 0.0
            while x < W {
                let a = breeze.sample(x + tile / 2, y + tile / 2)
                let s = CGFloat(min(1, a.speed / 100))
                let r: CGFloat = s > 0.5 ? (s - 0.5) * 2 * 0.85 : 0
                let g: CGFloat = s * 0.55 + (s > 0.5 ? 0.1 : 0)
                ctx.setFillColor(CGColor(red: r * 0.9, green: g, blue: 0.05 * s, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: tile, height: tile))
                x += tile
            }
            y += tile
        }
        for f in flowers.all {
            let c = kindColours[f.kind] ?? (1, 1, 1)
            ctx.setStrokeColor(CGColor(red: 0.25, green: 0.55, blue: 0.3, alpha: 0.9))
            ctx.setLineWidth(2)
            for l in f.leaves {
                ctx.move(to: CGPoint(x: f.x, y: f.y))
                ctx.addLine(to: CGPoint(x: f.x + cos(l.angle) * l.length, y: f.y + sin(l.angle) * l.length))
            }
            ctx.strokePath()
            let hx = f.x + f.ox, hy = f.y + f.oy
            ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 0.55))
            ctx.fillEllipse(in: CGRect(x: hx - f.radius, y: hy - f.radius, width: 2 * f.radius, height: 2 * f.radius))
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: f.x, y: f.y))
            ctx.addLine(to: CGPoint(x: hx, y: hy))
            ctx.strokePath()
        }
        let pg = breeze.spacing
        for r in 0..<breeze.rows {
            for c in 0..<breeze.columns {
                let px = Double(c) * pg, py = Double(r) * pg
                guard px <= W && py <= H else { continue }
                let a = breeze.sample(px, py)
                let k = 0.45
                ctx.setStrokeColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.8))
                ctx.setLineWidth(1)
                arrow(ctx, px, py, a.x * k, a.y * k)
                let p: Double = (a.pointerX * a.pointerX + a.pointerY * a.pointerY).squareRoot()
                if p > 2 {
                    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: CGFloat(min(1, p / 80))))
                    ctx.strokeEllipse(in: CGRect(x: px - 6, y: py - 6, width: 12, height: 12))
                }
            }
        }
        label(String(format: "Swift port: seed %d, %.1f s, wind %.0f pt/s base, dir %.0f°", Int(seed), breeze.time, breeze.base,
                     atan2(breeze.directionY, breeze.directionX) * 180 / .pi), at: CGPoint(x: 10, y: H - 12), ctx: ctx, height: h)
        ctx.restoreGState()
        label("sketch (under) + Swift planting (cyan)", at: CGPoint(x: 10, y: H - 12), ctx: ctx, height: h)

        guard let img = ctx.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        try StillRenderer.writePNG(img, to: out)
        print("wrote \(out.path) \(img.width)x\(img.height): \(flowers.all.count) flowers, \(flowers.patches) patches")
        for f in fresh.all {
            print(String(format: "  %3d %-10@ (%7.1f, %7.1f) R %5.1f", f.id, f.kind.name as NSString, f.x, f.y, f.radius))
        }
    }

    private static func arrow(_ ctx: CGContext, _ x: Double, _ y: Double, _ dx: Double, _ dy: Double) {
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0.5 else { return }
        ctx.move(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x + dx, y: y + dy))
        let a = atan2(dy, dx), head = min(6, len * 0.4)
        ctx.move(to: CGPoint(x: x + dx, y: y + dy))
        ctx.addLine(to: CGPoint(x: x + dx - head * cos(a - 0.5), y: y + dy - head * sin(a - 0.5)))
        ctx.move(to: CGPoint(x: x + dx, y: y + dy))
        ctx.addLine(to: CGPoint(x: x + dx - head * cos(a + 0.5), y: y + dy - head * sin(a + 0.5)))
        ctx.strokePath()
    }

    /// A small label; the context is flipped (y down), so the text is drawn flipped back.
    private static func label(_ text: String, at p: CGPoint, ctx: CGContext, height: Int) {
        let font = CTFontCreateWithName("Menlo" as CFString, 11, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = p
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
