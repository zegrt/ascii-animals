import CoreGraphics
import Foundation
import Metal
import os

/// The renderer's rare failures, in the unified log (OceanKit has no app log of its own).
private let renderLog = Logger(subsystem: "local.ascii-animals.wallpaper", category: "render")

public struct RenderError: Error, CustomStringConvertible {
    public let description: String
    public init(description: String) { self.description = description }
}

/// Device-wide state: the compiled shaders and the pipelines (the Ocean's
/// three, and the generic canvas compose).
public final class OceanRenderer {
    public let device: MTLDevice
    public let queue: MTLCommandQueue
    let wakePipe: MTLRenderPipelineState
    let cellsPipe: MTLRenderPipelineState
    let composePipe: MTLRenderPipelineState
    let canvasPipe: MTLRenderPipelineState
    public static let outputFormat = MTLPixelFormat.bgra8Unorm

    public init(device: MTLDevice) throws {
        self.device = device
        guard let q = device.makeCommandQueue() else { throw RenderError(description: "no command queue") }
        queue = q
        let lib: MTLLibrary
        do {
            lib = try device.makeLibrary(source: Shaders.source, options: nil)
        } catch {
            throw RenderError(description: "shader compile failed: \(error)")
        }
        func pipe(_ fragment: String, _ format: MTLPixelFormat) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "vs_main")
            d.fragmentFunction = lib.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = format
            d.label = fragment
            return try device.makeRenderPipelineState(descriptor: d)
        }
        wakePipe = try pipe("wake_main", .rg16Float)
        cellsPipe = try pipe("cells_main", .rgba8Unorm)
        composePipe = try pipe("compose_main", OceanRenderer.outputFormat)
        canvasPipe = try pipe("canvas_main", OceanRenderer.outputFormat)
    }

    public func makeViewport(pointSize: CGSize, scale: CGFloat, cell: CGSize? = nil) throws -> ViewportRenderer {
        try ViewportRenderer(renderer: self, pointSize: pointSize, scale: scale,
                             cell: cell ?? GridSpec.cell(forWidth: pointSize.width))
    }
}

/// Mirrors `CanvasUniforms` in Shaders.swift. `canvas_main`'s inputs:
/// buffer 0 these uniforms; textures, all `cols x rows`, one texel per cell:
/// 0 block (rgba8), 1 ink (rgba8), 2 glyph (r8 uint), 3 the glyph atlas,
/// 4 overlay ink (rgba8), 5 overlay glyph (r8 uint), 6 ground (rgba8, a == 0:
/// plain background), read only when misc.y is 1. A canvas that never wrote a
/// ground has no ground texture: misc.y is 0 and the block texture stands in
/// at index 6, unread.
struct CanvasUniforms {
    var grid: SIMD4<Float>       // cols, rows, cell w, cell h (points)
    var background: SIMD4<Float> // rgb, scale
    var gridColor: SIMD4<Float>
    var misc: SIMD4<Float>       // reveal, ground (1: read texture 6, 0: none), 0, 0
}

/// Per-screen GPU state: wake ping-pong, cell classification, glyph atlas,
/// and a ring of uniform buffers / fish grids so the CPU never writes what
/// the GPU is still reading. A `CellPainter` habitat gets a `CellCanvas` and
/// a ring of cell textures instead, made the first time one draws here.
public final class ViewportRenderer {
    public private(set) var grid: GridSpec
    public private(set) var pointSize: CGSize
    public private(set) var scale: CGFloat

    private let r: OceanRenderer
    private static let inFlight = 3
    private let semaphore = DispatchSemaphore(value: ViewportRenderer.inFlight)
    private var ring = 0
    private var uniforms: [MTLBuffer] = []
    private var fishGrids: [MTLTexture] = []
    private var fishBytes: UnsafeMutablePointer<UInt8>?
    private var wake: [MTLTexture] = []
    private var wakeCurrent = 0
    private var cells: MTLTexture!
    private var atlas: MTLTexture!
    /// The canvas habitats' atlas (a browser canvas's middle baseline), made on first use. If making it fails, that
    /// is logged once and the Ocean's atlas stands in until the next resize.
    private var canvasAtlas: MTLTexture?
    private var canvasAtlasFailed = false
    private var needsClear = true
    /// Canvas habitats: the CPU grid and, per ring slot, its upload (block, ink, glyph, overlay ink and glyph).
    private var canvas: CellCanvas?
    private var canvasTextures: [(block: MTLTexture, ink: MTLTexture, glyph: MTLTexture, overInk: MTLTexture, overGlyph: MTLTexture)] = []
    /// Per ring slot, the canvas's ground; made the first time a canvas here has one (grow-only: kept until the grid
    /// changes), so a habitat without a ground allocates and uploads nothing more.
    private var groundTextures: [MTLTexture] = []
    /// What this viewport has already drawn of its world: steps run through
    /// the wake, and events stamped. A world shared by several screens is
    /// drawn by each at its own pace.
    private var lastWorld: ObjectIdentifier?
    private var lastStepCount = 0
    private var lastEventSeq = 0

    init(renderer: OceanRenderer, pointSize: CGSize, scale: CGFloat, cell: CGSize) throws {
        r = renderer
        self.pointSize = pointSize
        self.scale = scale
        grid = GridSpec.make(viewportSize: pointSize, cell: cell)
        for _ in 0..<ViewportRenderer.inFlight {
            guard let b = r.device.makeBuffer(length: FrameLayout.bytes, options: .storageModeShared) else {
                throw RenderError(description: "no uniform buffer")
            }
            uniforms.append(b)
        }
        try allocate()
    }

    deinit { fishBytes?.deallocate() }

    public func resize(pointSize: CGSize, scale: CGFloat, cell: CGSize? = nil) throws {
        let cell = cell ?? GridSpec.cell(forWidth: pointSize.width)
        guard pointSize != self.pointSize || scale != self.scale || cell != grid.cell else { return }
        // Let in-flight frames finish before their textures go away.
        for _ in 0..<ViewportRenderer.inFlight { semaphore.wait() }
        defer { for _ in 0..<ViewportRenderer.inFlight { semaphore.signal() } }
        self.pointSize = pointSize
        self.scale = scale
        grid = GridSpec.make(viewportSize: pointSize, cell: cell)
        try allocate()
    }

    private func texture(_ format: MTLPixelFormat, _ w: Int, _ h: Int, _ usage: MTLTextureUsage, _ label: String) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
        d.usage = usage
        guard let t = r.device.makeTexture(descriptor: d) else { throw RenderError(description: "no texture \(label)") }
        t.label = label
        return t
    }

    private func allocate() throws {
        let c = grid.cols, rows = grid.rows
        wake = try (0..<2).map { try texture(.rg16Float, c, rows, [.renderTarget, .shaderRead], "wake \($0)") }
        cells = try texture(.rgba8Unorm, c, rows, [.renderTarget, .shaderRead], "cells")
        fishGrids = try (0..<ViewportRenderer.inFlight).map { try texture(.rgba8Unorm, c, rows, .shaderRead, "fish \($0)") }
        fishBytes?.deallocate()
        fishBytes = .allocate(capacity: c * rows * 4)
        atlas = try GlyphAtlas.make(device: r.device, cell: grid.cell, scale: scale)
        canvasAtlas = nil
        canvasAtlasFailed = false
        needsClear = true
        canvas = nil
        canvasTextures = []
        groundTextures = []
    }

    private func pass(_ cb: MTLCommandBuffer, _ target: MTLTexture, _ pipe: MTLRenderPipelineState, _ label: String,
                      _ body: (MTLRenderCommandEncoder) -> Void) {
        let d = MTLRenderPassDescriptor()
        d.colorAttachments[0].texture = target
        d.colorAttachments[0].loadAction = .dontCare
        d.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: d) else { return }
        enc.label = label
        enc.setRenderPipelineState(pipe)
        body(enc)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Draws `habitat` the way its kind draws: the part inside `viewport`
    /// (ocean space; nil = all of it), into `target` when given (nil only
    /// advances per-step state such as the Ocean's wake). `reveal` dissolves
    /// the picture in: cells whose revealHash is at or above it draw bare
    /// background; 1 shows everything. The caller commits `commandBuffer`.
    public func encode(habitat: HabitatSim, viewport: CGRect? = nil, theme: ThemeParams, reveal: Float = 1,
                       target: MTLTexture?, commandBuffer cb: MTLCommandBuffer) {
        if let ocean = habitat as? OceanSim {
            encode(world: ocean.world, viewport: viewport, theme: theme, reveal: reveal, target: target, commandBuffer: cb)
        } else if let target {
            if let painter = habitat as? CellPainter {
                encode(painter: painter, viewport: viewport, theme: theme, reveal: reveal, target: target, commandBuffer: cb)
            } else {
                clear(target, cb)
            }
        }
    }

    /// Paints `painter`'s part inside `viewport` (nil: this viewport's size at
    /// the origin) into this viewport's canvas, uploads it, and composes it
    /// into `target` with canvas_main.
    private func encode(painter: CellPainter, viewport: CGRect?, theme: ThemeParams, reveal: Float,
                        target: MTLTexture, commandBuffer cb: MTLCommandBuffer) {
        let area = viewport ?? CGRect(origin: .zero, size: pointSize)
        let c: CellCanvas
        if let existing = canvas {
            c = existing
            c.clear()
        } else {
            c = CellCanvas(cols: grid.cols, rows: grid.rows)
            canvas = c
        }
        painter.paint(viewport: area, grid: grid, theme: theme, into: c)

        semaphore.wait()
        let sem = semaphore
        cb.addCompletedHandler { _ in sem.signal() }
        ring = (ring + 1) % ViewportRenderer.inFlight
        if canvasTextures.isEmpty {
            do {
                canvasTextures = try (0..<ViewportRenderer.inFlight).map { i in
                    (try texture(.rgba8Unorm, grid.cols, grid.rows, .shaderRead, "canvas block \(i)"),
                     try texture(.rgba8Unorm, grid.cols, grid.rows, .shaderRead, "canvas ink \(i)"),
                     try texture(.r8Uint, grid.cols, grid.rows, .shaderRead, "canvas glyph \(i)"),
                     try texture(.rgba8Unorm, grid.cols, grid.rows, .shaderRead, "canvas over ink \(i)"),
                     try texture(.r8Uint, grid.cols, grid.rows, .shaderRead, "canvas over glyph \(i)"))
                }
            } catch {
                clear(target, cb)
                return
            }
        }
        let t = canvasTextures[ring]
        let region = MTLRegionMake2D(0, 0, grid.cols, grid.rows)
        c.block.withUnsafeBytes { t.block.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: grid.cols * 4) }
        c.ink.withUnsafeBytes { t.ink.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: grid.cols * 4) }
        c.glyph.withUnsafeBytes { t.glyph.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: grid.cols) }
        c.overInk.withUnsafeBytes { t.overInk.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: grid.cols * 4) }
        c.overGlyph.withUnsafeBytes { t.overGlyph.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: grid.cols) }
        var groundTexture: MTLTexture? = nil
        if !c.ground.isEmpty {
            if groundTextures.isEmpty {
                groundTextures = (0..<ViewportRenderer.inFlight).compactMap { i in
                    try? texture(.rgba8Unorm, grid.cols, grid.rows, .shaderRead, "canvas ground \(i)")
                }
                if groundTextures.count != ViewportRenderer.inFlight { groundTextures = [] }
            }
            if !groundTextures.isEmpty {
                let g = groundTextures[ring]
                c.ground.withUnsafeBytes { g.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: grid.cols * 4) }
                groundTexture = g
            }
        }

        let hasGround: Float = groundTexture == nil ? 0 : 1
        var u = CanvasUniforms(
            grid: SIMD4<Float>(Float(grid.cols), Float(grid.rows), Float(grid.cell.width), Float(grid.cell.height)),
            background: SIMD4<Float>(c.background, Float(scale)),
            gridColor: c.gridColor,
            misc: SIMD4<Float>(reveal, hasGround, 0, 0))
        if canvasAtlas == nil && !canvasAtlasFailed {
            do {
                canvasAtlas = try GlyphAtlas.make(device: r.device, cell: grid.cell, scale: scale, middle: .canvas)
            } catch {
                canvasAtlasFailed = true
                renderLog.error("canvas glyph atlas failed (\(String(describing: error), privacy: .public)); drawing with the Ocean's")
            }
        }
        let atlas = canvasAtlas ?? self.atlas
        pass(cb, target, r.canvasPipe, "canvas compose") { enc in
            enc.setFragmentBytes(&u, length: MemoryLayout<CanvasUniforms>.stride, index: 0)
            enc.setFragmentTexture(t.block, index: 0)
            enc.setFragmentTexture(t.ink, index: 1)
            enc.setFragmentTexture(t.glyph, index: 2)
            enc.setFragmentTexture(atlas, index: 3)
            enc.setFragmentTexture(t.overInk, index: 4)
            enc.setFragmentTexture(t.overGlyph, index: 5)
            enc.setFragmentTexture(groundTexture ?? t.block, index: 6)
        }
    }

    /// Black: a habitat with nothing to draw still presents a defined frame.
    private func clear(_ target: MTLTexture, _ cb: MTLCommandBuffer) {
        let d = MTLRenderPassDescriptor()
        d.colorAttachments[0].texture = target
        d.colorAttachments[0].loadAction = .clear
        d.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        d.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: d) else { return }
        enc.label = "clear"
        enc.endEncoding()
    }

    /// Packs the part of `world` inside `viewport` (ocean space; nil = all of
    /// it) and encodes one wake pass per simulation step since this viewport
    /// last drew (at most 4), the cell pass, and (when `target` is given) the
    /// compose pass into `target`. The caller commits `commandBuffer`.
    func encode(world: World, viewport: CGRect? = nil, theme: ThemeParams, reveal: Float = 1, target: MTLTexture?,
                commandBuffer cb: MTLCommandBuffer) {
        let id = ObjectIdentifier(world)
        if lastWorld != id {
            lastWorld = id
            lastStepCount = world.stepCount
            lastEventSeq = world.eventSeq
            needsClear = true
        }
        let steps = min(OceanClock.maxSteps, max(0, world.stepCount - lastStepCount))
        lastStepCount = world.stepCount
        let area = viewport ?? CGRect(x: 0, y: 0, width: world.width, height: world.height)

        semaphore.wait()
        let sem = semaphore
        cb.addCompletedHandler { _ in sem.signal() }
        ring = (ring + 1) % ViewportRenderer.inFlight
        let ubo = uniforms[ring]
        let fishTex = fishGrids[ring]
        let clear = needsClear
        needsClear = false

        lastEventSeq = FramePacker.pack(world: world, viewport: area, afterEventSeq: lastEventSeq, grid: grid,
                                        pixelSize: CGSize(width: pointSize.width * scale, height: pointSize.height * scale),
                                        scale: Float(scale), theme: theme, reveal: reveal, clearWake: clear, uniforms: ubo.contents(), fishGrid: fishBytes!)
        fishTex.replace(region: MTLRegionMake2D(0, 0, grid.cols, grid.rows), mipmapLevel: 0,
                        withBytes: fishBytes!, bytesPerRow: grid.cols * 4)

        let sharkOffset = FrameLayout.sharkBase * 16
        let eventOffset = FrameLayout.eventBase * 16
        let passes = clear ? max(1, steps) : steps
        for i in 0..<passes {
            let src = wake[wakeCurrent], dst = wake[1 - wakeCurrent]
            var withEvents: Int32 = i == 0 ? 1 : 0
            pass(cb, dst, r.wakePipe, "ocean wake") { enc in
                enc.setFragmentBuffer(ubo, offset: 0, index: 0)
                enc.setFragmentBuffer(ubo, offset: sharkOffset, index: 1)
                enc.setFragmentBuffer(ubo, offset: eventOffset, index: 2)
                enc.setFragmentBytes(&withEvents, length: 4, index: 3)
                enc.setFragmentTexture(src, index: 0)
                enc.setFragmentTexture(fishTex, index: 1)
            }
            wakeCurrent = 1 - wakeCurrent
        }

        guard let target else { return }
        pass(cb, cells, r.cellsPipe, "ocean cells") { enc in
            enc.setFragmentBuffer(ubo, offset: 0, index: 0)
            enc.setFragmentBuffer(ubo, offset: sharkOffset, index: 1)
            enc.setFragmentTexture(fishTex, index: 1)
        }
        let wakeNow = wake[wakeCurrent]
        pass(cb, target, r.composePipe, "ocean compose") { enc in
            enc.setFragmentBuffer(ubo, offset: 0, index: 0)
            enc.setFragmentTexture(cells, index: 0)
            enc.setFragmentTexture(wakeNow, index: 1)
            enc.setFragmentTexture(atlas, index: 2)
        }
    }
}
