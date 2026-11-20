import CoreGraphics
import Foundation
import Metal
import OceanKit

private func rgba(_ v: UInt32) -> (UInt8, UInt8, UInt8, UInt8) {
    (UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24))
}

func canvasChecks() {
    check("atlasKeepsOceanIndices") {
        let ocean = [":", ";", "t", "%", "S", "X", "8", "#", "@", ".", "'", ",", "`", "o", "-", "*", "·"]
        try expect(Array(GlyphAtlas.glyphs.prefix(17)) == ocean, "first 17 glyphs moved: \(GlyphAtlas.glyphs.prefix(17))")
        for g in ["¯", "_", "/", "\\", "|", "+", "x", "O", "°", "v", "0"] {
            guard let i = GlyphAtlas.index(Character(g)) else { throw CheckFailure(detail: "no index for \(g)") }
            try expect(Int(i) >= 17 && GlyphAtlas.glyphs[Int(i)] == g, "\(g) at \(i)")
        }
        try expect(GlyphAtlas.index(":") == 0 && GlyphAtlas.index("·") == 16, "Ocean glyph indices")
        try expect(GlyphAtlas.index(" ") == nil && GlyphAtlas.index("Q") == nil, "unknown glyphs have no index")
        try expect(GlyphAtlas.glyphs.count < Int(CellCanvas.noGlyph), "atlas reaches noGlyph")
    }
    check("canvasPut") {
        let c = CellCanvas(cols: 4, rows: 3)
        try expect(c.block.count == 12 && c.ink.count == 12 && c.glyph.count == 12, "array sizes")
        try expect(c.glyph.allSatisfy { $0 == CellCanvas.noGlyph } && c.block.allSatisfy { $0 == 0 }, "starts empty")
        c.put(2, 1, glyph: "x", ink: SIMD4(1, 0.5, 0, 0.8), block: SIMD3(0.2, 0.4, 0.6))
        let i = 1 * 4 + 2
        try expect(c.glyph[i] == GlyphAtlas.index("x")!, "glyph \(c.glyph[i])")
        let ink = rgba(c.ink[i]), block = rgba(c.block[i])
        try expect(ink == (255, 128, 0, 204), "ink \(ink)")
        try expect(block == (51, 102, 153, 255), "block \(block)")
        try expect(c.ink[i] == 255 | 128 << 8 | 0 << 16 | 204 << 24, "ink packing r|g<<8|b<<16|a<<24")
        // Out of range: ignored. No block: a == 0. Unknown glyph: noGlyph.
        c.put(4, 0, glyph: "x", ink: SIMD4(1, 1, 1, 1))
        c.put(0, 3, glyph: "x", ink: SIMD4(1, 1, 1, 1))
        c.put(0, 0, glyph: "Q", ink: SIMD4(1, 1, 1, 1))
        try expect(c.glyph[0] == CellCanvas.noGlyph && c.block[0] >> 24 == 0, "cell 0 \(c.glyph[0]) \(c.block[0])")
        try expect(c.glyph.filter { $0 != CellCanvas.noGlyph }.count == 1, "out-of-range put wrote a cell")
        // The overlay: a second glyph over the first, its own ink; starts empty.
        try expect(c.overGlyph.count == 12 && c.overInk.count == 12 && c.overGlyph.allSatisfy { $0 == CellCanvas.noGlyph },
                   "overlay starts empty")
        c.putOver(2, 1, glyph: "·", ink: SIMD4(0, 1, 0, 0.5))
        c.putOver(9, 1, glyph: "·", ink: SIMD4(0, 1, 0, 0.5))
        try expect(c.overGlyph[i] == GlyphAtlas.index("·")! && rgba(c.overInk[i]) == (0, 255, 0, 128), "overlay \(c.overGlyph[i])")
        try expect(c.glyph[i] == GlyphAtlas.index("x")!, "overlay replaced the base glyph")
        try expect(c.overGlyph.filter { $0 != CellCanvas.noGlyph }.count == 1, "out-of-range putOver wrote a cell")
        c.clear()
        try expect(c.glyph.allSatisfy { $0 == CellCanvas.noGlyph } && c.block.allSatisfy { $0 == 0 } && c.ink.allSatisfy { $0 == 0 },
                   "clear")
        try expect(c.overGlyph.allSatisfy { $0 == CellCanvas.noGlyph } && c.overInk.allSatisfy { $0 == 0 }, "clear overlay")
    }
    check("canvasGroundPut") {
        let c = CellCanvas(cols: 4, rows: 3)
        try expect(c.ground.isEmpty, "a new canvas has no ground (grow-only, so Ocean and Web never pay for it)")
        c.clear()
        try expect(c.ground.isEmpty, "clear grew the ground")
        c.putGround(9, 0, ground: SIMD4<Float>(1, 1, 1, 1))
        c.putGround(0, -1, ground: SIMD4<Float>(1, 1, 1, 1))
        try expect(c.ground.allSatisfy { $0 == CellCanvas.noGround }, "out-of-range putGround wrote a cell")
        c.putGround(1, 2, ground: SIMD4<Float>(0.2, 0.4, 0.6, 0.5))
        let i = 2 * 4 + 1
        try expect(c.ground.count == 12, "ground size \(c.ground.count)")
        try expect(rgba(c.ground[i]) == (51, 102, 153, 128), "ground \(rgba(c.ground[i]))")
        try expect(c.ground.filter { $0 != CellCanvas.noGround }.count == 1, "putGround wrote other cells")
        // put leaves the ground alone; bulk writes reach the same array.
        c.put(1, 2, glyph: "x", ink: SIMD4<Float>(1, 1, 1, 1), block: SIMD3<Float>(1, 0, 0))
        try expect(rgba(c.ground[i]) == (51, 102, 153, 128), "put changed the ground")
        c.withGround { g in g[0] = CellCanvas.pack(SIMD4<Float>(0, 1, 0, 1)) }
        try expect(rgba(c.ground[0]) == (0, 255, 0, 255), "withGround")
        c.clear()
        try expect(c.ground.count == 12 && c.ground.allSatisfy { $0 == CellCanvas.noGround }, "clear left a ground")
    }
    check("dissolveTiming") {
        let a = Dissolve.reveal(elapsed: 0)
        try expect(a.reveal == 1 && !a.swapNow && !a.done, "start \(a)")
        let b = Dissolve.reveal(elapsed: 0.35)
        try expect(b.reveal == 0 && b.swapNow && !b.done, "swap \(b)")
        let c = Dissolve.reveal(elapsed: 0.8)
        try expect(c.reveal == 1 && c.done, "end \(c)")
        let mid = Dissolve.reveal(elapsed: 0.2), back = Dissolve.reveal(elapsed: 0.6)
        try expect(mid.reveal > 0 && mid.reveal < 1 && !mid.swapNow, "fading out \(mid)")
        try expect(back.reveal > 0 && back.reveal < 1 && back.swapNow && !back.done, "fading in \(back)")
    }
    check("dissolveOnlyWhenLive") {
        try expect(Dissolve.shouldAnimate(.live(fps: 30)), "live animates")
        try expect(!Dissolve.shouldAnimate(.still), "still must swap at once")
        try expect(!Dissolve.shouldAnimate(.paused), "paused must swap at once")
    }
    check("dissolveRunSwapsOnce") {
        var run = DissolveRun(start: 10)
        var swaps = 0, last: (reveal: Float, swap: Bool, done: Bool) = (1, false, false)
        for f in 0...60 {
            last = run.frame(at: 10 + Double(f) / 60)
            if last.swap { swaps += 1 }
        }
        try expect(swaps == 1 && last.done && last.reveal == 1, "swaps \(swaps) last \(last)")
        // A frame that skips past the swap point still swaps.
        var late = DissolveRun(start: 0)
        try expect(late.frame(at: 0.7).swap && !late.frame(at: 0.75).swap, "late swap")
    }
    check("dissolveRestartFadesOutFromHere") {
        // Before the swap a second switch changes nothing: the swap builds whatever is chosen then.
        var a = DissolveRun(start: 0)
        _ = a.frame(at: 0.1)
        a.restart(at: 0.1)
        try expect(abs(a.frame(at: 0.2).reveal - Dissolve.reveal(elapsed: 0.2).reveal) < 1e-6, "restart before swap moved the run")
        // After it, fade out again from the current level, then swap again.
        var b = DissolveRun(start: 0)
        _ = b.frame(at: 0.5)
        let level = Dissolve.reveal(elapsed: 0.6).reveal
        b.restart(at: 0.6)
        let f = b.frame(at: 0.6)
        try expect(abs(f.reveal - level) < 1e-4 && !f.swap, "restart jumped: \(f.reveal) vs \(level)")
        var swapped = false
        for t in stride(from: 0.6, through: 2, by: 1.0 / 60) where b.frame(at: t).swap { swapped = true }
        try expect(swapped, "restarted run never swapped")
    }
    check("switchDrawsStillWhenNotLive") {
        // Review Focus 1: a habitat switch in a Low Power still or a user pause draws the new still at once;
        // a covered desktop just rebuilds (its next visible frame shows the change); live dissolves instead.
        try expect(Dissolve.drawsStillNow(.still, userPaused: false), "still")
        try expect(Dissolve.drawsStillNow(.paused, userPaused: true), "user paused")
        try expect(!Dissolve.drawsStillNow(.paused, userPaused: false), "covered")
        try expect(!Dissolve.drawsStillNow(.live(fps: 30), userPaused: false), "live")
    }
}

/// A 4 x 3 habitat that paints a fixed picture: block at (0,0), "x" at (1,0), the rest empty.
private final class TestPainter: CellPainter {
    static let background = SIMD3<Float>(10, 20, 30) / 255
    static let grid = SIMD4<Float>(1, 1, 1, 0.2)
    static let block = SIMD3<Float>(200, 100, 50) / 255
    static let ink = SIMD3<Float>(40, 220, 90) / 255
    var painted = 0

    var kind: HabitatKind { .web }
    var time: Double { 0 }
    var stepCount: Int { 0 }
    func layout(terrain: Terrain, cell: CGSize, settings: Settings) {}
    func step(_ dt: Double) {}
    func pointerMoved(_ x: Double, _ y: Double) {}
    func pointerLeft() {}
    func pointerDown(_ x: Double, _ y: Double) {}
    func update(settings: Settings) {}
    func settle() {}

    func paint(viewport: CGRect, grid: GridSpec, theme: ThemeParams, into canvas: CellCanvas) {
        painted += 1
        canvas.background = TestPainter.background
        canvas.gridColor = TestPainter.grid
        canvas.put(0, 0, glyph: " ", ink: .zero, block: TestPainter.block)
        canvas.put(1, 0, glyph: "x", ink: SIMD4(TestPainter.ink, 1))
    }
}

/// A habitat that is neither the Ocean nor a painter: drawn as plain black.
private final class BlankSim: HabitatSim {
    var kind: HabitatKind { .web }
    var time: Double { 0 }
    var stepCount: Int { 0 }
    func layout(terrain: Terrain, cell: CGSize, settings: Settings) {}
    func step(_ dt: Double) {}
    func pointerMoved(_ x: Double, _ y: Double) {}
    func pointerLeft() {}
    func pointerDown(_ x: Double, _ y: Double) {}
    func update(settings: Settings) {}
    func settle() {}
}

func canvasRenderChecks() {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let scale: CGFloat = 2
    let cell = CGSize(width: 13, height: 19)
    let size = CGSize(width: 52, height: 57)
    let w = Int(size.width * scale), h = Int(size.height * scale)
    let theme = ThemeParams.make(.defaults, systemIsDark: true, accent: SIMD3(0.2, 0.5, 1))

    func frame(_ r: OceanRenderer, _ vp: ViewportRenderer, _ sim: HabitatSim, reveal: Float = 1, fill: UInt8? = nil) throws -> [UInt8] {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OceanRenderer.outputFormat, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .managed
        let target = r.device.makeTexture(descriptor: d)!
        if let fill {
            let junk = [UInt8](repeating: fill, count: w * h * 4)
            target.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: junk, bytesPerRow: w * 4)
        }
        let cb = r.queue.makeCommandBuffer()!
        vp.encode(habitat: sim, theme: theme, reveal: reveal, target: target, commandBuffer: cb)
        let blit = cb.makeBlitCommandEncoder()!
        blit.synchronize(resource: target)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        target.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes
    }
    // BGRA bytes -> rgb in 0...255.
    func px(_ p: [UInt8], _ x: Int, _ y: Int) -> SIMD3<Float> {
        let i = (y * w + x) * 4
        return SIMD3(Float(p[i + 2]), Float(p[i + 1]), Float(p[i]))
    }
    func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ tol: Float = 1.01) -> Bool {
        let d = a - b * 255
        return abs(d.x) <= tol && abs(d.y) <= tol && abs(d.z) <= tol
    }

    check("canvasComposeDraws") {
        let r = try OceanRenderer(device: device)
        let vp = try r.makeViewport(pointSize: size, scale: scale, cell: cell)
        try expect(vp.grid.cols == 4 && vp.grid.rows == 3, "grid \(vp.grid)")
        let painter = TestPainter()
        let p = try frame(r, vp, painter)
        try expect(painter.painted == 1, "painted \(painter.painted) times")
        let cw = Int(cell.width * scale), ch = Int(cell.height * scale)
        let bg = TestPainter.background
        func centre(_ c: Int, _ row: Int) -> SIMD3<Float> { px(p, c * cw + cw / 2, row * ch + ch / 2) }
        try expect(near(centre(0, 0), TestPainter.block), "block centre \(centre(0, 0))")
        // Inset one point from the top-left: the block's first two device pixels show the grid line / background.
        let gridOverBg = bg + (SIMD3(TestPainter.grid.x, TestPainter.grid.y, TestPainter.grid.z) - bg) * TestPainter.grid.w
        try expect(near(px(p, 1, ch / 2), bg), "block inset column \(px(p, 1, ch / 2))")
        var inked = 0
        for y in 0..<ch { for x in cw..<(2 * cw) where near(px(p, x, y), TestPainter.ink, 2) { inked += 1 } }
        try expect(inked > 4, "ink-coloured pixels in the glyph cell: \(inked)")
        for (c, row) in [(2, 0), (3, 0), (0, 1), (1, 2), (3, 2)] {
            try expect(near(centre(c, row), bg), "empty cell (\(c),\(row)) centre \(centre(c, row))")
        }
        // Grid: the cell's left column and top row of device pixels.
        try expect(near(px(p, 2 * cw, ch + ch / 2), gridOverBg), "grid column \(px(p, 2 * cw, ch + ch / 2)) vs \(gridOverBg * 255)")
        try expect(near(px(p, 2 * cw + cw / 2, ch), gridOverBg), "grid row \(px(p, 2 * cw + cw / 2, ch))")
        try expect(near(px(p, 2 * cw + 1, ch + ch / 2), bg), "next to the grid column \(px(p, 2 * cw + 1, ch + ch / 2))")

        let hidden = try frame(r, vp, painter, reveal: 0)
        for y in 0..<h { for x in 0..<w where !near(px(hidden, x, y), bg) {
            throw CheckFailure(detail: "reveal 0: pixel (\(x),\(y)) is \(px(hidden, x, y)), not background")
        } }
    }
    check("canvasGroundDraws") {
        // A ground under a block (0,0), under a glyph (1,0), alone and half mixed (2,1); the rest plain background.
        final class Ground: CellPainter {
            static let under = SIMD3<Float>(20, 90, 40) / 255
            static let half = SIMD3<Float>(120, 200, 60) / 255
            var withGround = true
            var kind: HabitatKind { .web }
            var time: Double { 0 }
            var stepCount: Int { 0 }
            func layout(terrain: Terrain, cell: CGSize, settings: Settings) {}
            func step(_ dt: Double) {}
            func pointerMoved(_ x: Double, _ y: Double) {}
            func pointerLeft() {}
            func pointerDown(_ x: Double, _ y: Double) {}
            func update(settings: Settings) {}
            func settle() {}
            func paint(viewport: CGRect, grid: GridSpec, theme: ThemeParams, into canvas: CellCanvas) {
                canvas.background = TestPainter.background
                canvas.gridColor = TestPainter.grid
                canvas.put(0, 0, glyph: " ", ink: .zero, block: TestPainter.block)
                canvas.put(1, 0, glyph: "x", ink: SIMD4<Float>(TestPainter.ink, 1))
                guard withGround else { return }
                canvas.putGround(0, 0, ground: SIMD4<Float>(Ground.under, 1))
                canvas.putGround(1, 0, ground: SIMD4<Float>(Ground.under, 1))
                canvas.putGround(2, 1, ground: SIMD4<Float>(Ground.half, 0.5))
            }
        }
        let r = try OceanRenderer(device: device)
        let vp = try r.makeViewport(pointSize: size, scale: scale, cell: cell)
        let painter = Ground()
        let p = try frame(r, vp, painter)
        let cw = Int(cell.width * scale), ch = Int(cell.height * scale)
        let bg: SIMD3<Float> = TestPainter.background
        let gridRGB = SIMD3<Float>(TestPainter.grid.x, TestPainter.grid.y, TestPainter.grid.z)
        let gridA: Float = TestPainter.grid.w
        func over(_ base: SIMD3<Float>, _ top: SIMD3<Float>, _ a: Float) -> SIMD3<Float> { base + (top - base) * a }
        // The half ground as packed: a = 128/255.
        let halfA: Float = 128 / 255
        let halfGround: SIMD3<Float> = over(bg, Ground.half, halfA)
        func centre(_ c: Int, _ row: Int) -> SIMD3<Float> { px(p, c * cw + cw / 2, row * ch + ch / 2) }

        // Under the block: the block itself, the ground in its inset strip, the grid line over the ground.
        try expect(near(centre(0, 0), TestPainter.block), "block centre \(centre(0, 0))")
        try expect(near(px(p, 1, ch / 2), Ground.under), "inset strip \(px(p, 1, ch / 2)) vs \(Ground.under * 255)")
        try expect(near(px(p, cw / 2, 1), Ground.under), "inset top strip \(px(p, cw / 2, 1))")
        let gridOverUnder: SIMD3<Float> = over(Ground.under, gridRGB, gridA)
        try expect(near(px(p, 0, ch / 2), gridOverUnder), "grid over ground \(px(p, 0, ch / 2)) vs \(gridOverUnder * 255)")
        // Under the glyph: ink pixels, and the ground (never the background) around them.
        var inked = 0, grounded = 0
        for y in 1..<ch { for x in (cw + 1)..<(2 * cw) {
            let v = px(p, x, y)
            if near(v, TestPainter.ink, 2) { inked += 1 }
            if near(v, Ground.under) { grounded += 1 }
            if near(v, bg) { throw CheckFailure(detail: "glyph cell shows the background at (\(x),\(y))") }
        } }
        try expect(inked > 4 && grounded > cw * ch / 2, "glyph cell: \(inked) ink, \(grounded) ground pixels")
        // Alone, half mixed: the whole empty cell, the grid line drawn over it.
        try expect(near(centre(2, 1), halfGround, 1.6), "half ground \(centre(2, 1)) vs \(halfGround * 255)")
        try expect(near(px(p, 2 * cw + 1, ch + 1), halfGround, 1.6), "half ground corner \(px(p, 2 * cw + 1, ch + 1))")
        let gridOverHalf: SIMD3<Float> = over(halfGround, gridRGB, gridA)
        try expect(near(px(p, 2 * cw, ch + ch / 2), gridOverHalf, 1.6), "grid over half ground \(px(p, 2 * cw, ch + ch / 2))")
        // Everywhere else: the plain background.
        for (c, row) in [(2, 0), (3, 0), (0, 1), (1, 1), (3, 1), (0, 2), (1, 2), (2, 2), (3, 2)] {
            try expect(near(centre(c, row), bg), "cell (\(c),\(row)) without ground \(centre(c, row))")
        }
        // The dissolve hides the ground with the rest of the cell: bare background.
        let hidden = try frame(r, vp, painter, reveal: 0)
        for y in 0..<h { for x in 0..<w where !near(px(hidden, x, y), bg) {
            throw CheckFailure(detail: "reveal 0: pixel (\(x),\(y)) is \(px(hidden, x, y)), not background")
        } }
        // Cleared each frame: once the painter stops writing a ground, none shows.
        painter.withGround = false
        let gone = try frame(r, vp, painter)
        let goneHalf = px(gone, 2 * cw + cw / 2, ch + ch / 2)
        try expect(near(px(gone, 1, ch / 2), bg) && near(px(gone, cw + 2, ch - 2), bg) && near(goneHalf, bg),
                   "ground left over: \(px(gone, 1, ch / 2)) \(goneHalf)")
    }
    check("canvasOverlayGlyph") {
        // A "-" overlay over a "|" base (as dew over silk): both show, the overlay on top where they cross; an
        // overlay alone draws too.
        final class Overlay: CellPainter {
            static let base = SIMD3<Float>(240, 40, 40) / 255
            static let over = SIMD3<Float>(40, 240, 240) / 255
            var kind: HabitatKind { .web }
            var time: Double { 0 }
            var stepCount: Int { 0 }
            func layout(terrain: Terrain, cell: CGSize, settings: Settings) {}
            func step(_ dt: Double) {}
            func pointerMoved(_ x: Double, _ y: Double) {}
            func pointerLeft() {}
            func pointerDown(_ x: Double, _ y: Double) {}
            func update(settings: Settings) {}
            func settle() {}
            func paint(viewport: CGRect, grid: GridSpec, theme: ThemeParams, into canvas: CellCanvas) {
                canvas.background = TestPainter.background
                canvas.gridColor = SIMD4(1, 1, 1, 0)
                canvas.put(1, 1, glyph: "|", ink: SIMD4(Overlay.base, 1))
                canvas.putOver(1, 1, glyph: "-", ink: SIMD4(Overlay.over, 1))
                canvas.putOver(3, 2, glyph: "-", ink: SIMD4(Overlay.over, 1))
            }
        }
        let r = try OceanRenderer(device: device)
        let vp = try r.makeViewport(pointSize: size, scale: scale, cell: cell)
        let p = try frame(r, vp, Overlay())
        let cw = Int(cell.width * scale), ch = Int(cell.height * scale)
        func count(_ c: Int, _ row: Int, _ colour: SIMD3<Float>) -> (n: Int, xs: Set<Int>, ys: Set<Int>) {
            var n = 0, xs = Set<Int>(), ys = Set<Int>()
            for y in (row * ch)..<((row + 1) * ch) { for x in (c * cw)..<((c + 1) * cw) where near(px(p, x, y), colour, 2) {
                n += 1; xs.insert(x); ys.insert(y)
            } }
            return (n, xs, ys)
        }
        let base = count(1, 1, Overlay.base), over = count(1, 1, Overlay.over)
        try expect(base.n > 4, "base glyph pixels \(base.n)")
        try expect(over.n > 4, "overlay glyph pixels \(over.n)")
        // Where the dash crosses the bar the overlay wins: overlay pixels in the bar's columns.
        try expect(!over.xs.isDisjoint(with: base.xs), "overlay not drawn over the base where they cross")
        try expect(base.ys.count > over.ys.count, "bar rows \(base.ys.count) vs dash rows \(over.ys.count)")
        try expect(count(3, 2, Overlay.over).n > 4, "overlay alone not drawn")
        try expect(count(3, 2, Overlay.base).n == 0 && count(2, 1, Overlay.over).n == 0, "overlay leaked")
    }
    check("canvasGridOff") {
        let r = try OceanRenderer(device: device)
        let vp = try r.makeViewport(pointSize: size, scale: scale, cell: cell)
        final class NoGrid: CellPainter {
            var kind: HabitatKind { .web }
            var time: Double { 0 }
            var stepCount: Int { 0 }
            func layout(terrain: Terrain, cell: CGSize, settings: Settings) {}
            func step(_ dt: Double) {}
            func pointerMoved(_ x: Double, _ y: Double) {}
            func pointerLeft() {}
            func pointerDown(_ x: Double, _ y: Double) {}
            func update(settings: Settings) {}
            func settle() {}
            func paint(viewport: CGRect, grid: GridSpec, theme: ThemeParams, into canvas: CellCanvas) {
                canvas.background = TestPainter.background
                canvas.gridColor = SIMD4(1, 1, 1, 0)
            }
        }
        let p = try frame(r, vp, NoGrid())
        for y in 0..<h { for x in 0..<w where !near(px(p, x, y), TestPainter.background) {
            throw CheckFailure(detail: "pixel (\(x),\(y)) is \(px(p, x, y)) with no grid and no cells")
        } }
    }
    check("canvasThenOceanStillDraws") {
        // One viewport can switch between habitats: canvas, then the Ocean, then canvas again.
        let r = try OceanRenderer(device: device)
        let vp = try r.makeViewport(pointSize: CGSize(width: 400, height: 250), scale: 1)
        let s = Settings.defaults
        let ocean = Habitats.make(s, seed: 7)
        ocean.layout(terrain: .single(width: 400, height: 250), cell: vp.grid.cell, settings: s)
        for _ in 0..<240 { ocean.step(OceanClock.step) }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: OceanRenderer.outputFormat, width: 400, height: 250, mipmapped: false)
        d.usage = .renderTarget
        d.storageMode = .managed
        for sim in [TestPainter() as HabitatSim, ocean, TestPainter()] {
            let target = r.device.makeTexture(descriptor: d)!, cb = r.queue.makeCommandBuffer()!
            vp.encode(habitat: sim, theme: theme, target: target, commandBuffer: cb)
            cb.commit()
            cb.waitUntilCompleted()
            try expect(cb.status == .completed, "\(sim.kind) frame status \(cb.status.rawValue)")
        }
    }
    check("unknownHabitatClearsToBlack") {
        // Neither the Ocean nor a painter: black, never an undefined drawable.
        let r = try OceanRenderer(device: device)
        let vp = try r.makeViewport(pointSize: size, scale: scale, cell: cell)
        let p = try frame(r, vp, BlankSim(), fill: 0x7f)
        try expect(stride(from: 0, to: p.count, by: 4).allSatisfy { p[$0] == 0 && p[$0 + 1] == 0 && p[$0 + 2] == 0 },
                   "not black: first pixel \(px(p, 0, 0))")
    }
}
