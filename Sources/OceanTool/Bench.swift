import CoreGraphics
import Foundation
import Metal
import OceanKit

/// `OceanTool bench --desk`: the CPU a habitat costs on the owner's desk, measured the way the app spends it.
///
/// The desk (as CoreGraphics reports it): a 2560 x 1440 monitor at 1x above the built-in display, 1800 x 1169 pt
/// at 2x, offset 375 pt (`--laptop WxH` for another built-in size, e.g. 1512x982), one shared scene
/// (`--separate`: one scene per screen, as with "shared ocean" off). The habitat steps at 60 Hz; each frame
/// both viewports are drawn through `ViewportRenderer.encode` into offscreen targets of the screens' pixel
/// sizes, exactly as a display-link tick does (Ocean: pack + upload + GPU passes encoded; Web: paint on the CPU
/// + upload + compose encoded). Times are this thread's CPU time, so waits on the GPU don't count; "process"
/// adds Metal's own threads. Both are per second of habitat time, i.e. per wall-clock second live.
///
/// `--digest`: no timing; a fingerprint of every Web canvas painted over a scripted run on the desk (pointer
/// through a web, a click, the jumper stalking), to prove a change leaves the output bit-identical.
enum Bench {
    static func desk(laptop: CGSize) -> [ScreenInfo] {
        [ScreenInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), scale: 1),
         ScreenInfo(id: 2, frame: CGRect(origin: CGPoint(x: 375, y: 1440), size: laptop), scale: 2)]
    }

    @inline(__always) static func cpuNow() -> UInt64 { clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) }
    /// The whole process (Metal's own threads too).
    static func processNow() -> UInt64 { clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) }

    private struct Scene {
        let sim: HabitatSim
        let views: [(rect: CGRect, vp: ViewportRenderer, target: MTLTexture)]
    }

    private static func scenes(_ s: Settings, desk: [ScreenInfo], separate: Bool, renderer r: OceanRenderer) throws -> [Scene] {
        let scale = Dictionary(uniqueKeysWithValues: desk.map { ($0.id, $0.scale) })
        return try SceneLayout.plan(desk, shared: !separate).enumerated().map { n, plan in
            let sim = Habitats.make(s, seed: UInt64(1 + n))
            sim.layout(terrain: plan.terrain, cell: plan.cell, settings: s)
            let views = try plan.views.map { v -> (rect: CGRect, vp: ViewportRenderer, target: MTLTexture) in
                let sc = scale[v.screenID]!
                let vp = try r.makeViewport(pointSize: v.rect.size, scale: sc, cell: plan.cell)
                let d = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: OceanRenderer.outputFormat, width: Int(v.rect.width * sc), height: Int(v.rect.height * sc), mipmapped: false)
                d.usage = .renderTarget
                d.storageMode = .private
                guard let t = r.device.makeTexture(descriptor: d) else { throw RenderError(description: "no target") }
                return (v.rect, vp, t)
            }
            return Scene(sim: sim, views: views)
        }
    }

    static func run(_ s: Settings, laptop: CGSize, separate: Bool, seconds: Double) throws {
        let desk = Bench.desk(laptop: laptop)
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError(description: "no Metal device") }
        let r = try OceanRenderer(device: device)
        let theme = ThemeParams.make(s, systemIsDark: true, accent: .zero)
        let all = try scenes(s, desk: desk, separate: separate, renderer: r)
        var last: MTLCommandBuffer?
        func draw(_ sc: Scene, _ v: (rect: CGRect, vp: ViewportRenderer, target: MTLTexture)) {
            guard let cb = r.queue.makeCommandBuffer() else { return }
            v.vp.encode(habitat: sc.sim, viewport: v.rect, theme: theme, target: v.target, commandBuffer: cb)
            cb.commit()
            last = cb
        }
        // Warm up: ten seconds, drawn at 30 fps.
        for i in 0..<600 {
            for sc in all { sc.sim.step(OceanClock.step) }
            if i % 2 == 1 { for sc in all { for v in sc.views { draw(sc, v) } } }
        }
        last?.waitUntilCompleted()
        let label = separate ? "separate" : "shared"
        let viewNames = all.flatMap { $0.views.map { "\(Int($0.rect.width))x\(Int($0.rect.height))" } }.joined(separator: " + ")
        print("\(s.habitat.rawValue)\(s.habitat == .ocean ? String(format: " (fish density %.2f)", s.fishDensity) : "") on the desk (\(label): \(all.count) scene\(all.count == 1 ? "" : "s"), viewports \(viewNames))")
        for fps in [30, 15] {
            let frames = Int(seconds * Double(fps))
            let stepsPerFrame = 60 / fps
            var simNs: UInt64 = 0
            var drawNs = [UInt64](repeating: 0, count: all.reduce(0) { $0 + $1.views.count })
            let p0 = processNow()
            for _ in 0..<frames {
                var t0 = cpuNow()
                for _ in 0..<stepsPerFrame { for sc in all { sc.sim.step(OceanClock.step) } }
                simNs += cpuNow() - t0
                var k = 0
                for sc in all {
                    for v in sc.views {
                        t0 = cpuNow()
                        draw(sc, v)
                        drawNs[k] += cpuNow() - t0
                        k += 1
                    }
                }
            }
            last?.waitUntilCompleted()
            let processMsPerS = Double(processNow() - p0) / 1e6 / seconds
            let simMsPerS = Double(simNs) / 1e6 / seconds
            let perView = drawNs.map { Double($0) / 1e6 / Double(frames) }
            let drawPerFrame = perView.reduce(0, +)
            let total = simMsPerS + drawPerFrame * Double(fps)
            print(String(format: "  %2d fps  sim %6.2f ms/s   draw %6.3f ms/frame (%@)   total %6.2f ms/s = %5.2f%% of a core   (process %6.2f ms/s)",
                         fps, simMsPerS, drawPerFrame, perView.map { String(format: "%.3f", $0) }.joined(separator: " + "),
                         total, total / 10, processMsPerS))
        }
    }

    /// FNV-1a over everything a canvas hands the GPU.
    private struct Digest {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        mutating func add<T>(_ a: [T]) {
            a.withUnsafeBytes { b in for x in b { h = (h ^ UInt64(x)) &* 0x100_0000_01b3 } }
        }
        mutating func add(_ c: CellCanvas) {
            add(c.block); add(c.ink); add(c.glyph); add(c.overGlyph); add(c.overInk)
            add([c.background.x, c.background.y, c.background.z, c.gridColor.x, c.gridColor.y, c.gridColor.z, c.gridColor.w])
        }
    }

    static func digest(_ s: Settings, laptop: CGSize, separate: Bool, frames: Int) {
        let desk = Bench.desk(laptop: laptop)
        var dark = s, light = s
        dark.appearance = .dark
        light.appearance = .light
        light.calm = true
        let themes = [ThemeParams.make(dark, systemIsDark: true, accent: .zero), ThemeParams.make(light, systemIsDark: true, accent: .zero)]
        var total = Digest()
        for (n, plan) in SceneLayout.plan(desk, shared: !separate).enumerated() {
            let sim = WebSim(settings: s.sanitized(), seed: UInt64(1 + n))
            sim.layout(terrain: plan.terrain, cell: plan.cell, settings: s)
            let script = WebScript(world: sim.world)
            let canvases = plan.views.map { v -> (CGRect, GridSpec, CellCanvas) in
                let g = GridSpec.make(viewportSize: v.rect.size, cell: plan.cell)
                return (v.rect, g, CellCanvas(cols: g.cols, rows: g.rows))
            }
            var d = Digest()
            for f in 0..<frames {
                for _ in 0..<2 {
                    script.step()
                    sim.step(OceanClock.step)
                }
                for (rect, g, c) in canvases {
                    c.clear()
                    sim.paint(viewport: rect, grid: g, theme: themes[f % 7 == 3 ? 1 : 0], into: c)
                    d.add(c)
                }
            }
            print(String(format: "scene %d: %d webs, %d frames x %d viewports  digest %016llx", n, sim.world.webs.count, frames, canvases.count, d.h))
            total.h = (total.h ^ d.h) &* 0x100_0000_01b3
        }
        print(String(format: "digest %016llx", total.h))
    }
}
