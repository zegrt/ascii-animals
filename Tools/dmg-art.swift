// Composes the install window's background (Resources/dmg/background.png and
// background@2x.png) from a rendered ASCII ocean. CoreGraphics + CoreText only.
//
//   swift run -c release --scratch-path .build-ui OceanTool still /tmp/dmg-ocean.png 660x420 --scale 2 --seed 5
//   swift Tools/dmg-art.swift /tmp/dmg-ocean.png Resources/dmg
//
// The window is 660×420 pt. Finder puts the app icon at (170, 210) and the
// Applications folder at (490, 210) (centres, top-left origin, 128 pt icons,
// names underneath), so those spots stay calm and clear.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = CGSize(width: 660, height: 420)
let appSlot = CGPoint(x: 170, y: 210)
let appsSlot = CGPoint(x: 490, y: 210)
let iconHalf: CGFloat = 64

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift Tools/dmg-art.swift <ocean@2x.png> <out-dir>\n".utf8))
    exit(2)
}
let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

func fail(_ s: String) -> Never { FileHandle.standardError.write(Data("dmg-art: \(s)\n".utf8)); exit(1) }

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let ocean = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail("can't read \(args[1])") }
guard let fontData = try? Data(contentsOf: repo.appendingPathComponent("Resources/GeistMono.ttf")),
      let provider = CGDataProvider(data: fontData as CFData), let geist = CGFont(provider) else { fail("can't load Geist Mono") }

func mono(_ size: CGFloat, weight: CGFloat) -> CTFont {
    let desc = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: [0x7767_6874: weight]] as CFDictionary)
    return CTFontCreateWithGraphicsFont(geist, size, nil, desc)
}

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let ground = rgba(5, 6, 8)
let cyan = (r: CGFloat(110), g: CGFloat(230), b: CGFloat(255))
let ink = (r: CGFloat(236), g: CGFloat(240), b: CGFloat(244))

func render(scale: CGFloat) -> CGImage {
    let w = Int(size.width * scale), h = Int(size.height * scale)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("no context") }
    ctx.scaleBy(x: scale, y: scale)
    // Work in window points with a top-left origin, as Finder places icons.
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)
    let full = CGRect(origin: .zero, size: size)

    ctx.setFillColor(ground)
    ctx.fill(full)

    // The ocean, quietened so it reads as a backdrop.
    ctx.saveGState()
    ctx.interpolationQuality = .high
    ctx.setAlpha(0.86)
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(ocean, in: full)
    ctx.restoreGState()

    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func radial(_ c: CGPoint, _ r: CGFloat, _ inner: CGFloat, _ outer: CGFloat = 0, sx: CGFloat = 1) {
        let g = CGGradient(colorsSpace: space, colors: [rgba(5, 6, 8, inner), rgba(5, 6, 8, (inner + outer) / 2 * 0.6), rgba(5, 6, 8, outer)] as CFArray,
                           locations: [0, 0.6, 1])!
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: sx, y: 1)
        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: [])
        ctx.restoreGState()
    }
    // A calm channel across the middle, deeper pools under each icon and its name.
    radial(CGPoint(x: 330, y: 222), 150, 0.78, sx: 1.75)
    radial(CGPoint(x: appSlot.x, y: appSlot.y + 14), 108, 0.88)
    radial(CGPoint(x: appsSlot.x, y: appsSlot.y + 14), 108, 0.88)
    // A faint glow under the app, so its dark icon stands off the water: this is the thing to drag.
    let glow = CGGradient(colorsSpace: space, colors: [rgba(cyan.r, cyan.g, cyan.b, 0.16), rgba(cyan.r, cyan.g, cyan.b, 0.05), rgba(cyan.r, cyan.g, cyan.b, 0)] as CFArray,
                          locations: [0, 0.55, 1])!
    ctx.drawRadialGradient(glow, startCenter: appSlot, startRadius: 30, endCenter: appSlot, endRadius: 104, options: [])
    // Edges fall off into the dark, and the bottom stays quiet for the hint.
    let fall = CGGradient(colorsSpace: space, colors: [rgba(5, 6, 8, 0), rgba(5, 6, 8, 0.92)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(fall, start: CGPoint(x: 0, y: 340), end: CGPoint(x: 0, y: 420), options: [])

    func text(_ s: String, _ font: CTFont, _ color: CGColor, centerX: CGFloat, baseline: CGFloat, kern: CGFloat = 0) -> CGFloat {
        let attr = NSAttributedString(string: s, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTKernAttributeName as String): kern,
        ])
        let line = CTLineCreateWithAttributedString(attr)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: (centerX - width / 2).rounded(), y: baseline)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        return width
    }

    // The arrow: a wake of dots brightening toward a chevron, the way a fish crosses the water.
    let from = appSlot.x + iconHalf + 34, to = appsSlot.x - iconHalf - 34
    let y = appSlot.y - 4
    let dot = mono(15, weight: 600)
    let steps = 9
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps - 1)
        let x = from + (to - from - 16) * t
        let a = 0.16 + 0.7 * pow(t, 1.6)
        _ = text("·", dot, rgba(cyan.r, cyan.g, cyan.b, a), centerX: x, baseline: y + 5)
    }
    _ = text("›", mono(30, weight: 500), rgba(cyan.r, cyan.g, cyan.b, 1), centerX: to - 2, baseline: y + 10)

    _ = text("drag to Applications", mono(11.5, weight: 450), rgba(ink.r, ink.g, ink.b, 0.82), centerX: 330, baseline: y + 34)

    // The one thing a friend needs to know the first time, quiet but readable.
    _ = text("First open: System Settings › Privacy & Security › Open Anyway", mono(10.5, weight: 400),
             rgba(ink.r, ink.g, ink.b, 0.6), centerX: 330, baseline: 394)

    guard let image = ctx.makeImage() else { fail("no image") }
    return image
}

func write(_ image: CGImage, _ url: URL, dpi: Int) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fail("can't write \(url.path)") }
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fail("can't write \(url.path)") }
    print("wrote \(url.path) \(image.width)×\(image.height)")
}

let out = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
write(render(scale: 1), out.appendingPathComponent("background.png"), dpi: 72)
write(render(scale: 2), out.appendingPathComponent("background@2x.png"), dpi: 144)
