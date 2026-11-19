import CoreGraphics
import Foundation
import simd

/// A habitat drawn on the CPU as a grid of cells, composed on the GPU by
/// `canvas_main`. Row-major, `cols * rows` entries per array. Colours are
/// final: no light-theme inversion is applied after the painter.
public final class CellCanvas {
    public static let noGlyph: UInt8 = 255
    public let cols: Int, rows: Int
    /// RGBA8 packed `r | g<<8 | b<<16 | a<<24`; a == 0: no block. Drawn
    /// inset one point from the cell's top-left, mixed by a.
    public var block: [UInt32]
    /// RGBA8 packed like `block`; a = glyph opacity.
    public var ink: [UInt32]
    /// `GlyphAtlas` index, or `noGlyph`.
    public var glyph: [UInt8]
    public var background = SIMD3<Float>(0, 0, 0)
    /// The one-device-pixel line at each cell's top and left edge; a == 0: no grid.
    public var gridColor = SIMD4<Float>(0, 0, 0, 0)

    public init(cols: Int, rows: Int) {
        self.cols = max(0, cols)
        self.rows = max(0, rows)
        let n = self.cols * self.rows
        block = [UInt32](repeating: 0, count: n)
        ink = [UInt32](repeating: 0, count: n)
        glyph = [UInt8](repeating: CellCanvas.noGlyph, count: n)
    }

    /// Empties every cell (keeps `background` and `gridColor`), in place.
    public func clear() {
        block.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        ink.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        glyph.withUnsafeMutableBufferPointer { $0.update(repeating: CellCanvas.noGlyph) }
    }

    /// Sets one cell: `glyph` in `ink` (a = opacity) over `block` (nil: no
    /// block). A glyph the atlas lacks (e.g. " ") draws none. Cells outside
    /// the grid are ignored.
    public func put(_ col: Int, _ row: Int, glyph g: Character, ink color: SIMD4<Float>, block fill: SIMD3<Float>? = nil) {
        guard col >= 0, col < cols, row >= 0, row < rows else { return }
        let i = row * cols + col
        glyph[i] = GlyphAtlas.index(g) ?? CellCanvas.noGlyph
        ink[i] = CellCanvas.pack(color)
        block[i] = fill.map { CellCanvas.pack(SIMD4($0, 1)) } ?? 0
    }

    /// RGBA in 0...1 to `r | g<<8 | b<<16 | a<<24`.
    @inline(__always)
    public static func pack(_ c: SIMD4<Float>) -> UInt32 {
        let v = (simd_clamp(c, .zero, .one) * 255).rounded(.toNearestOrAwayFromZero)
        return UInt32(v.x) | UInt32(v.y) << 8 | UInt32(v.z) << 16 | UInt32(v.w) << 24
    }
}

/// A habitat that draws by painting a `CellCanvas`. The renderer hands it
/// the canvas for `viewport` (habitat space) already cleared, every frame.
public protocol CellPainter: HabitatSim {
    func paint(viewport: CGRect, grid: GridSpec, theme: ThemeParams, into canvas: CellCanvas)
}
