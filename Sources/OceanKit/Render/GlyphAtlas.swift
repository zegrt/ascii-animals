import CoreGraphics
import CoreText
import Foundation
import Metal

/// The glyphs the compose shaders index, rendered once per cell size in
/// Geist Mono SemiBold into a strip of cell-sized slots (R8 coverage). The
/// first 17 are the Ocean's (compose_main indexes them by number); the rest
/// are for `CellCanvas` habitats. Append only: indices never move.
public enum GlyphAtlas {
    public static let glyphs = [":", ";", "t", "%", "S", "X", "8", "#", "@", ".", "'", ",", "`", "o", "-", "*", "·",
                                "¯", "_", "/", "\\", "|", "+", "x", "O", "°", "v", "0"]

    private static let indices: [Character: UInt8] = {
        var d: [Character: UInt8] = [:]
        for (i, g) in glyphs.enumerated() { d[Character(g)] = UInt8(i) }
        return d
    }()

    /// `g`'s slot in the atlas, or nil when the atlas lacks it.
    public static func index(_ g: Character) -> UInt8? { indices[g] }

    public struct Bytes {
        public let bytes: [UInt8]
        public let width: Int
        public let height: Int
        public let slotWidth: Int
    }

    struct FontError: Error {}

    private static let baseFont: CGFont? = {
        guard let data = Data(base64Encoded: GeistMonoData.base64),
              let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGFont(provider)
    }()

    static func font(size: CGFloat) throws -> CTFont {
        guard let cg = baseFont else { throw FontError() }
        // 'wght' axis of the variable font: SemiBold.
        let wght = 0x7767_6874
        let desc = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: [wght: 600]] as CFDictionary)
        return CTFontCreateWithGraphicsFont(cg, size, nil, desc)
    }

    /// Where the "middle" baseline sits.
    public enum Middle {
        /// The Ocean's atlas, as it has always been: half of CoreText's ascent minus descent above the middle.
        case ocean
        /// A browser canvas's `textBaseline = "middle"`, as Chrome on macOS draws it: the middle of the em box (the
        /// font's ascent and descent scaled to sum to one em), glyphs landing one device pixel higher than that,
        /// and font smoothing on (macOS's stem darkening, which Chrome's canvas text gets). Fitted against Chrome's
        /// own glyphs at 1x and 2x (docs/reference/web-port-notes.md). The Web habitat draws as the original page.
        case canvas
    }

    public static func makeBytes(cell: CGSize, scale: CGFloat, middle: Middle = .ocean) throws -> Bytes {
        let slotW = Int((cell.width * scale).rounded())
        let slotH = Int((cell.height * scale).rounded())
        let width = slotW * glyphs.count
        guard let ctx = CGContext(data: nil, width: width, height: slotH, bitsPerComponent: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { throw FontError() }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: slotH))
        ctx.setShouldAntialias(true)
        ctx.setAllowsFontSmoothing(middle == .canvas)
        ctx.setShouldSmoothFonts(middle == .canvas)

        // renderer.ts: ctx.font = 600 round(ch * 0.74)px, centred, baseline "middle" at ch/2 + 1.
        let size = (cell.height * 0.74).rounded() * scale
        let font = try font(size: size)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let aboveMiddle = middle == .ocean ? (ascent - descent) / 2 : size * (ascent - descent) / (2 * (ascent + descent)) - 1
        let white = CGColor(gray: 1, alpha: 1)
        for (i, g) in glyphs.enumerated() {
            let attr = NSAttributedString(string: g, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: white,
            ])
            let line = CTLineCreateWithAttributedString(attr)
            let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
            let cx = CGFloat(i * slotW) + CGFloat(slotW) / 2
            let middleY = CGFloat(slotH) / 2 + scale                // from the top
            let baselineFromTop = middleY + aboveMiddle
            ctx.textPosition = CGPoint(x: cx - advance / 2, y: CGFloat(slotH) - baselineFromTop)
            CTLineDraw(line, ctx)
        }
        guard let data = ctx.data else { throw FontError() }
        // Bitmap memory is top row first.
        let bytes = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * slotH))
        return Bytes(bytes: bytes, width: width, height: slotH, slotWidth: slotW)
    }

    static func make(device: MTLDevice, cell: CGSize, scale: CGFloat, middle: Middle = .ocean) throws -> MTLTexture {
        let a = try makeBytes(cell: cell, scale: scale, middle: middle)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: a.width, height: a.height, mipmapped: false)
        d.usage = .shaderRead
        guard let t = device.makeTexture(descriptor: d) else { throw FontError() }
        a.bytes.withUnsafeBytes {
            t.replace(region: MTLRegionMake2D(0, 0, a.width, a.height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: a.width)
        }
        t.label = "glyph atlas"
        return t
    }
}
