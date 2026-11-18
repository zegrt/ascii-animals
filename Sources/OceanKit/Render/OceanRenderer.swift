import CoreGraphics
import Foundation
import Metal

public struct RenderError: Error, CustomStringConvertible {
    public let description: String
    public init(description: String) { self.description = description }
}

/// Device-wide state: the compiled shaders and the three pipelines.
public final class OceanRenderer {
    public let device: MTLDevice
    public let queue: MTLCommandQueue
    let wakePipe: MTLRenderPipelineState
    let cellsPipe: MTLRenderPipelineState
    let composePipe: MTLRenderPipelineState
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
    }

    public func makeViewport(pointSize: CGSize, scale: CGFloat) throws -> ViewportRenderer {
        try ViewportRenderer(renderer: self, pointSize: pointSize, scale: scale)
    }
}

/// Per-screen GPU state: wake ping-pong, cell classification, glyph atlas,
/// and a ring of uniform buffers / fish grids so the CPU never writes what
/// the GPU is still reading.
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
    private var needsClear = true

    init(renderer: OceanRenderer, pointSize: CGSize, scale: CGFloat) throws {
        r = renderer
        self.pointSize = pointSize
        self.scale = scale
        grid = GridSpec.make(viewportSize: pointSize, cell: GridSpec.cell(forWidth: pointSize.width))
        for _ in 0..<ViewportRenderer.inFlight {
            guard let b = r.device.makeBuffer(length: FrameLayout.bytes, options: .storageModeShared) else {
                throw RenderError(description: "no uniform buffer")
            }
            uniforms.append(b)
        }
        try allocate()
    }

    deinit { fishBytes?.deallocate() }

    public func resize(pointSize: CGSize, scale: CGFloat) throws {
        guard pointSize != self.pointSize || scale != self.scale else { return }
        // Let in-flight frames finish before their textures go away.
        for _ in 0..<ViewportRenderer.inFlight { semaphore.wait() }
        defer { for _ in 0..<ViewportRenderer.inFlight { semaphore.signal() } }
        self.pointSize = pointSize
        self.scale = scale
        grid = GridSpec.make(viewportSize: pointSize, cell: GridSpec.cell(forWidth: pointSize.width))
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
        needsClear = true
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

    /// Packs `world` and encodes `steps` wake passes, the cell pass, and (when
    /// `target` is given) the compose pass into `target`. The caller commits
    /// `commandBuffer`, and clears `world.events` afterwards.
    public func encode(world: World, theme: ThemeParams, steps: Int, target: MTLTexture?, commandBuffer cb: MTLCommandBuffer) {
        semaphore.wait()
        let sem = semaphore
        cb.addCompletedHandler { _ in sem.signal() }
        ring = (ring + 1) % ViewportRenderer.inFlight
        let ubo = uniforms[ring]
        let fishTex = fishGrids[ring]
        let clear = needsClear
        needsClear = false

        FramePacker.pack(world: world, grid: grid,
                         pixelSize: CGSize(width: pointSize.width * scale, height: pointSize.height * scale),
                         scale: Float(scale), theme: theme, clearWake: clear, uniforms: ubo.contents(), fishGrid: fishBytes!)
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
