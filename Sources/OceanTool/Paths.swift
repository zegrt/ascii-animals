import CoreGraphics
import CoreText
import Foundation
import OceanKit
import simd

/// `OceanTool paths`: each species flown freely for a while over a laptop-sized field (1800 × 1169 pt) in calm
/// air with one gust, its track drawn in the species' colour with a tick at every wingbeat. One panel per
/// species, so the four signatures can be compared: the monarch's long glides, the white's restless zig-zag, the
/// morpho's bounds, the swallowtail's floating glides.
enum FlightPaths {
    static let field = CGSize(width: 1800, height: 1169)
    static let cell = CGSize(width: 13, height: 19)
    static let dt: Double = 1.0 / 60.0
    /// The gust: a sin² bump peaking at 100 pt/s from the left, lifting a little.
    static let gustStart: Double = 30, gustLength: Double = 4, gustPeak: Double = 100

    struct Track {
        var kind: ButterflyKind
        var points: [SIMD2<Double>] = []
        var velocity: [SIMD2<Double>] = []
        var gliding: [Bool] = []
        var gust: [Bool] = []
        var claps: [Int] = []          // indices into points
        var flyNanos: UInt64 = 0
    }

    static func names(_ k: ButterflyKind) -> String {
        switch k {
        case .monarch: return "Monarch"
        case .morpho: return "Blue morpho"
        case .swallowtail: return "Swallowtail (P. machaon)"
        case .cabbageWhite: return "Cabbage white"
        }
    }

    /// Research §5.4, dark theme glyph colours.
    static func colour(_ k: ButterflyKind) -> CGColor {
        switch k {
        case .monarch: return rgb(196, 120, 52)
        case .morpho: return rgb(84, 132, 190)
        case .swallowtail: return rgb(212, 190, 96)
        case .cabbageWhite: return rgb(222, 220, 206)
        }
    }

    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    static func fly(_ kind: ButterflyKind, seconds: Double, seed: UInt64) -> Track {
        let terrain = Terrain.single(width: Double(field.width), height: Double(field.height))
        let breeze = Breeze(bounds: terrain.bounds, cell: cell)
        breeze.ambient = false
        let random = WebRandom(seed: seed)
        let b = Butterfly(kind: kind, x: 450, y: 520, random: random)
        var track = Track(kind: kind)
        let sx: Double = 4 * Double(cell.width), sy: Double = 3 * Double(cell.height)
        for step in 0..<Int(seconds * 60) {
            let t: Double = Double(step) * dt
            let tau: Double = t - gustStart
            let inGust = tau > 0 && tau < gustLength
            if inGust {
                let s: Double = sin(Double.pi * tau / gustLength)
                let w: Double = gustPeak * s * s / 0.6   // the breeze stores writes × 0.6
                var y: Double = 0
                while y <= Double(field.height) + sy {
                    var x: Double = 0
                    while x <= Double(field.width) + sx {
                        breeze.write(x, y, vx: w, vy: -0.15 * w)
                        x += sx
                    }
                    y += sy
                }
            }
            breeze.step(dt, random: random)
            let before = b.claps
            let t0 = DispatchTime.now().uptimeNanoseconds
            b.fly(dt, target: nil, breeze: breeze, terrain: terrain, random: random)
            track.flyNanos += DispatchTime.now().uptimeNanoseconds - t0
            track.points.append(SIMD2<Double>(b.x, b.y))
            track.velocity.append(SIMD2<Double>(b.vx, b.vy))
            track.gliding.append(b.gliding)
            track.gust.append(inGust)
            if b.claps > before { track.claps.append(track.points.count - 1) }
        }
        return track
    }

    struct Stats { var beat: Double, glide: Double, speed: Double }

    static func stats(_ t: Track) -> Stats {
        let flapping = Double(t.gliding.filter { !$0 }.count) * dt
        let speed = t.velocity.map { simd_length($0) }.reduce(0, +) / Double(max(1, t.velocity.count))
        return Stats(beat: Double(t.claps.count) / max(flapping, 1e-9),
                     glide: Double(t.gliding.filter { $0 }.count) / Double(max(1, t.gliding.count)), speed: speed)
    }

    static func run(out: URL, seconds: Double, seed: UInt64) throws {
        let kinds: [ButterflyKind] = [.monarch, .cabbageWhite, .morpho, .swallowtail]
        let tracks = kinds.enumerated().map { i, k in fly(k, seconds: seconds, seed: seed &+ UInt64(i)) }

        // Layout, in points (drawn at 2 px per point, so a panel shows the field 1 px : 1 pt).
        let panelScale: CGFloat = 0.5
        let pw = field.width * panelScale, ph = field.height * panelScale
        let margin: CGFloat = 40, gap: CGFloat = 34, header: CGFloat = 150, caption: CGFloat = 40
        let width = margin * 2 + pw * 2 + gap
        let height = header + (caption + ph) * 2 + gap + margin
        let px: CGFloat = 2
        let ctx = CGContext(data: nil, width: Int(width * px), height: Int(height * px), bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Top-down points, like ocean space.
        ctx.scaleBy(x: px, y: px)
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(rgb(12, 13, 16))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let ink = rgb(205, 207, 212), dim = rgb(130, 134, 142)
        text(ctx, "Butterfly flight paths", at: CGPoint(x: margin, y: 52), size: 30, colour: ink, bold: true)
        text(ctx, String(format: "%.0f s each, free flight over an 1800 × 1169 pt field (a laptop screen), calm air with one gust. "
                         + "Per-beat forces; wingbeats slowed to 0.28× real, ±10 %% per individual, +20 %% in the gust.", seconds),
             at: CGPoint(x: margin, y: 84), size: 15, colour: dim)
        // Legend.
        var lx = margin
        let ly: CGFloat = 122
        for k in kinds {
            ctx.setStrokeColor(colour(k))
            ctx.setLineWidth(3)
            ctx.strokeLineSegments(between: [CGPoint(x: lx, y: ly - 5), CGPoint(x: lx + 26, y: ly - 5)])
            lx += 34
            lx += text(ctx, names(k), at: CGPoint(x: lx, y: ly), size: 15, colour: ink) + 26
        }
        drawTick(ctx, at: CGPoint(x: lx + 6, y: ly - 5), dir: CGVector(dx: 1, dy: 0), colour: ink)
        lx += 18
        lx += text(ctx, "one wingbeat (clap); stretches without ticks are glides", at: CGPoint(x: lx, y: ly), size: 15, colour: ink) + 26
        ctx.setStrokeColor(rgb(255, 255, 255, 0.22))
        ctx.setLineWidth(9)
        ctx.strokeLineSegments(between: [CGPoint(x: lx, y: ly - 5), CGPoint(x: lx + 26, y: ly - 5)])
        lx += 34
        text(ctx, String(format: "during the gust (%.0f pt/s from the left, t = %.0f–%.0f s)", gustPeak, gustStart, gustStart + gustLength),
             at: CGPoint(x: lx, y: ly), size: 15, colour: ink)

        for (i, track) in tracks.enumerated() {
            let ox = margin + CGFloat(i % 2) * (pw + gap)
            let oy = header + CGFloat(i / 2) * (caption + ph + gap)
            let s = stats(track)
            text(ctx, names(track.kind), at: CGPoint(x: ox, y: oy + 26), size: 19, colour: colour(track.kind), bold: true)
            let w = text(ctx, "", at: .zero, size: 19, colour: ink, bold: true, measureOnly: names(track.kind))
            text(ctx, String(format: "   wingbeat %.2f Hz (species %.1f) · glides %.0f %% of the time · mean %.0f pt/s",
                             s.beat, ButterflySpecies.of(track.kind).beat, s.glide * 100, s.speed),
                 at: CGPoint(x: ox + w, y: oy + 26), size: 15, colour: dim)
            let frame = CGRect(x: ox, y: oy + caption, width: pw, height: ph)
            ctx.setFillColor(rgb(20, 22, 28))
            ctx.fill(frame)
            ctx.setStrokeColor(rgb(58, 61, 70))
            ctx.setLineWidth(1)
            ctx.stroke(frame.insetBy(dx: -0.5, dy: -0.5))
            ctx.saveGState()
            ctx.clip(to: frame)
            ctx.translateBy(x: frame.minX, y: frame.minY)
            ctx.scaleBy(x: panelScale, y: panelScale)
            drawTrack(ctx, track)
            ctx.restoreGState()
        }
        try StillRenderer.writePNG(ctx.makeImage()!, to: out)
        for t in tracks {
            let s = stats(t)
            print(String(format: "%@: %.3f Hz, glides %.1f %%, mean speed %.0f pt/s, %.2f µs per fly step",
                         names(t.kind), s.beat, s.glide * 100, s.speed, Double(t.flyNanos) / Double(max(1, t.points.count)) / 1000))
        }
        print("wrote \(out.path) \(Int(width * px))x\(Int(height * px))")
    }

    /// The track in field points (the context is scaled to the panel).
    static func drawTrack(_ ctx: CGContext, _ t: Track) {
        let c = colour(t.kind)
        let pts = t.points.map { CGPoint(x: $0.x, y: $0.y) }
        guard pts.count > 1 else { return }
        // Gust halo.
        ctx.setStrokeColor(rgb(255, 255, 255, 0.16))
        ctx.setLineWidth(18)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        var k = 1
        while k < pts.count {
            guard t.gust[k] else { k += 1; continue }
            ctx.beginPath()
            ctx.move(to: pts[k - 1])
            while k < pts.count && t.gust[k] { ctx.addLine(to: pts[k]); k += 1 }
            ctx.strokePath()
        }
        // The track.
        ctx.setStrokeColor(c)
        ctx.setLineWidth(2.6)
        ctx.beginPath()
        ctx.addLines(between: pts)
        ctx.strokePath()
        // A tick at every clap, square to the ground track.
        for i in t.claps {
            let v = t.velocity[i]
            let n = max(simd_length(v), 1e-9)
            drawTick(ctx, at: pts[i], dir: CGVector(dx: v.x / n, dy: v.y / n), colour: c, length: 18, width: 2.4)
        }
        // Start (dot) and end (ring).
        ctx.setFillColor(c)
        ctx.fillEllipse(in: CGRect(x: pts[0].x - 9, y: pts[0].y - 9, width: 18, height: 18))
        let e = pts[pts.count - 1]
        ctx.setLineWidth(3.5)
        ctx.strokeEllipse(in: CGRect(x: e.x - 12, y: e.y - 12, width: 24, height: 24))
        text(ctx, "start", at: CGPoint(x: pts[0].x + 16, y: pts[0].y + 34), size: 26, colour: rgb(150, 154, 162))
        text(ctx, "end", at: CGPoint(x: e.x + 18, y: e.y + 34), size: 26, colour: rgb(150, 154, 162))
    }

    static func drawTick(_ ctx: CGContext, at p: CGPoint, dir: CGVector, colour: CGColor, length: CGFloat = 12, width: CGFloat = 1.6) {
        let h = length / 2
        ctx.setStrokeColor(colour)
        ctx.setLineWidth(width)
        ctx.strokeLineSegments(between: [CGPoint(x: p.x - dir.dy * h, y: p.y + dir.dx * h),
                                         CGPoint(x: p.x + dir.dy * h, y: p.y - dir.dx * h)])
    }

    /// Draws one line of text with its baseline at `p` (top-down context) and returns its width.
    @discardableResult
    static func text(_ ctx: CGContext, _ s: String, at p: CGPoint, size: CGFloat, colour: CGColor, bold: Bool = false,
                     measureOnly: String? = nil) -> CGFloat {
        let base = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
        let attr = NSAttributedString(string: measureOnly ?? s, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: base,
            kCTForegroundColorAttributeName as NSAttributedString.Key: colour,
        ])
        let line = CTLineCreateWithAttributedString(attr)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if measureOnly == nil {
            ctx.saveGState()
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = p
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        return width
    }
}
