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
    /// A second glyph drawn over the first (source-over, as a 2D canvas
    /// draws one glyph on another): `GlyphAtlas` index, or `noGlyph`.
    public var overGlyph: [UInt8]
    /// RGBA8 packed like `ink`, for `overGlyph`.
    public var overInk: [UInt32]
    /// The ground under each cell, RGBA8 packed like `block`: shown wherever the
    /// cell would show `background` (the strip around its inset block, an empty
    /// cell, under the grid line and the glyphs), mixed over `background` by a;
    /// a == 0 (`noGround`): plain `background`. Grow-only: empty until the first
    /// `putGround` or `growGround()`, then `cols * rows` for this canvas's life,
    /// so a habitat that never writes it (Ocean, Web) costs nothing.
    public private(set) var ground: [UInt32] = []
    public static let noGround: UInt32 = 0
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
        overGlyph = [UInt8](repeating: CellCanvas.noGlyph, count: n)
        overInk = [UInt32](repeating: 0, count: n)
    }

    /// Empties every cell, its ground included (keeps `background` and
    /// `gridColor`), in place.
    public func clear() {
        if !ground.isEmpty { ground.withUnsafeMutableBufferPointer { $0.update(repeating: CellCanvas.noGround) } }
        block.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        ink.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        glyph.withUnsafeMutableBufferPointer { $0.update(repeating: CellCanvas.noGlyph) }
        overGlyph.withUnsafeMutableBufferPointer { $0.update(repeating: CellCanvas.noGlyph) }
        overInk.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
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

    /// Sets one cell's ground: `color` mixed over `background` by its a (1:
    /// the ground alone; 0: no ground). Cells outside the grid are ignored.
    public func putGround(_ col: Int, _ row: Int, ground color: SIMD4<Float>) {
        guard col >= 0, col < cols, row >= 0, row < rows else { return }
        growGround()
        ground[row * cols + col] = CellCanvas.pack(color)
    }

    /// Makes `ground` `cols * rows` long (all `noGround`) if it is still empty,
    /// for a painter that fills it in bulk with `withGround`. Allocates once.
    public func growGround() {
        if ground.isEmpty { ground = [UInt32](repeating: CellCanvas.noGround, count: cols * rows) }
    }

    /// Grows `ground` if needed and hands it over for writing in place.
    public func withGround<R>(_ body: (inout UnsafeMutableBufferPointer<UInt32>) throws -> R) rethrows -> R {
        growGround()
        return try ground.withUnsafeMutableBufferPointer(body)
    }

    /// Sets one cell's overlay: `glyph` in `ink` drawn over whatever the
    /// cell holds. Cells outside the grid are ignored.
    public func putOver(_ col: Int, _ row: Int, glyph g: Character, ink color: SIMD4<Float>) {
        guard col >= 0, col < cols, row >= 0, row < rows else { return }
        let i = row * cols + col
        overGlyph[i] = GlyphAtlas.index(g) ?? CellCanvas.noGlyph
        overInk[i] = CellCanvas.pack(color)
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
