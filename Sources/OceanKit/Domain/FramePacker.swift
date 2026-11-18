import CoreGraphics
import Foundation

/// The ASCII grid for one viewport.
public struct GridSpec: Equatable, Sendable {
    public var cell: CGSize
    public var cols: Int
    public var rows: Int

    /// renderer.ts: cells scale with the width, ~1.45:1 tall.
    public static func cell(forWidth w: Double) -> CGSize {
        let cw = min(13, max(8, (w / 124).rounded()))
        return CGSize(width: cw, height: (cw * 1.45).rounded())
    }

    public static func make(viewportSize: CGSize, cell: CGSize) -> GridSpec {
        GridSpec(cell: cell,
                 cols: max(1, Int(ceil(viewportSize.width / cell.width))),
                 rows: max(1, Int(ceil(viewportSize.height / cell.height))))
    }
}

/// Uniform buffer layout, in float4 slots. Mirrored in Shaders.swift.
///   hd0 (W, H, cols, rows)            hd1 (cw, ch, time, stepDt)
///   hd2 (outW px, outH px, scale, 0)   hd3 (sharkCount, eventCount, pointerActive, clearWake)
///   hd4 (pointerX, pointerY, 0, 0)     hd5 (light, brightness, accentRate, grid)
///   hd6 (wake r, g, b, 0)
/// Shark i at sharkBase + i * sharkStride:
///   0 (L, depth, kind, id)  1 (tipLeft, tipRight, speed, arcTotal)  2 pectoral  3 pelvic
///   4 (caudal, falcate, dorsal0, dorsal1)  5 (secondDorsal0, secondDorsal1, eye0, eye1)
///   6 (gills0, gills1, headSpan, headSweep)  7 (headDepth, headNotch, 0, 0)
///   8...27 spine nodes (x, y, arc, 0)  28 bounding box (minX, minY, maxX, maxY)
/// Event e at eventBase + e: (x, y, kind 0 eat / 1 splash, 0).
public enum FrameLayout {
    public static let headerCount = 7
    public static let maxSharks = 8
    public static let sharkStride = 29
    public static let maxEvents = 16
    public static let sharkBase = headerCount
    public static let eventBase = sharkBase + maxSharks * sharkStride
    public static let slots = eventBase + maxEvents
    public static let bytes = slots * 16
}

struct SharkShape {
    let pectoral: SIMD4<Float>
    let falcate: Bool
    let pelvic: SIMD4<Float>
    let caudal: Float
    let dorsal: SIMD2<Float>
    let secondDorsal: SIMD2<Float>
    let head: SIMD4<Float> // span, sweep, depth, notch; zero for no cephalofoil
    let eye: SIMD2<Float> // -1 for none
    let gills: SIMD2<Float>
}

/// renderer.ts SHAPES in SharkKind order.
let sharkShapes: [SharkShape] = [
    // classic
    SharkShape(pectoral: [0.15, 0.43, 0.55, 0.26], falcate: true, pelvic: [0.57, 0.65, 0.69, 0.085], caudal: 0.085,
               dorsal: [0.33, 0.47], secondDorsal: [0.71, 0.76], head: .zero, eye: [0.1, 0.14], gills: [0.19, 0.29]),
    // hammerhead
    SharkShape(pectoral: [0.17, 0.4, 0.5, 0.22], falcate: true, pelvic: [0.56, 0.63, 0.67, 0.075], caudal: 0.11,
               dorsal: [0.28, 0.44], secondDorsal: [0.7, 0.74], head: [0.17, 0.035, 0.09, 0], eye: [-1, -1], gills: [0.16, 0.26]),
    // tiger
    SharkShape(pectoral: [0.15, 0.42, 0.53, 0.25], falcate: true, pelvic: [0.57, 0.65, 0.69, 0.085], caudal: 0.095,
               dorsal: [0.33, 0.46], secondDorsal: [0.71, 0.75], head: .zero, eye: [0.08, 0.12], gills: [0.19, 0.28]),
    // zebra
    SharkShape(pectoral: [0.12, 0.3, 0.36, 0.19], falcate: false, pelvic: [0.42, 0.48, 0.51, 0.065], caudal: 0,
               dorsal: [0.36, 0.44], secondDorsal: [0.49, 0.53], head: .zero, eye: [0.06, 0.09], gills: [0.13, 0.2]),
    // greathammer
    SharkShape(pectoral: [0.16, 0.38, 0.49, 0.24], falcate: true, pelvic: [0.55, 0.62, 0.67, 0.085], caudal: 0.13,
               dorsal: [0.24, 0.45], secondDorsal: [0.68, 0.74], head: [0.21, 0.006, 0.085, 0.014], eye: [-1, -1], gills: [0.15, 0.25]),
    // mako
    SharkShape(pectoral: [0.18, 0.4, 0.5, 0.21], falcate: true, pelvic: [0.58, 0.64, 0.68, 0.06], caudal: 0.13,
               dorsal: [0.34, 0.45], secondDorsal: [0.76, 0.79], head: .zero, eye: [0.11, 0.15], gills: [0.2, 0.3]),
    // thresher
    SharkShape(pectoral: [0.12, 0.27, 0.36, 0.2], falcate: true, pelvic: [0.37, 0.41, 0.44, 0.045], caudal: 0,
               dorsal: [0.24, 0.32], secondDorsal: [0.45, 0.47], head: .zero, eye: [0.05, 0.1], gills: [0.11, 0.18]),
    // nurse
    SharkShape(pectoral: [0.16, 0.34, 0.4, 0.17], falcate: false, pelvic: [0.45, 0.52, 0.55, 0.075], caudal: 0,
               dorsal: [0.5, 0.58], secondDorsal: [0.63, 0.69], head: .zero, eye: [0.05, 0.075], gills: [0.14, 0.22]),
]

public enum FramePacker {
    /// Seconds after which shader time wraps, so float precision never decays.
    public static let timeWrap = 3600.0

    /// Writes the uniforms (`FrameLayout.bytes`) and the fish grid
    /// (`cols * rows` RGBA8 texels: present, brightness, wake deposit, near).
    /// Does not clear `world.events`; the caller does after the frame.
    public static func pack(world w: World, grid: GridSpec, pixelSize: CGSize, scale: Float, theme: ThemeParams,
                            clearWake: Bool, uniforms: UnsafeMutableRawPointer, fishGrid: UnsafeMutablePointer<UInt8>) {
        let u = uniforms.bindMemory(to: SIMD4<Float>.self, capacity: FrameLayout.slots)
        let sharkCount = min(w.sharks.count, FrameLayout.maxSharks)
        let eventCount = min(w.events.count, FrameLayout.maxEvents)
        let cw = Double(grid.cell.width), ch = Double(grid.cell.height)

        u[0] = SIMD4(Float(w.width), Float(w.height), Float(grid.cols), Float(grid.rows))
        u[1] = SIMD4(Float(cw), Float(ch), Float(w.time.truncatingRemainder(dividingBy: timeWrap)), Float(OceanClock.step))
        u[2] = SIMD4(Float(pixelSize.width), Float(pixelSize.height), scale, 0)
        u[3] = SIMD4(Float(sharkCount), Float(eventCount), w.pointer.active ? 1 : 0, clearWake ? 1 : 0)
        u[4] = SIMD4(Float(w.pointer.x), Float(w.pointer.y), 0, 0)
        u[5] = SIMD4(theme.light ? 1 : 0, theme.brightness, theme.accentRate, theme.grid ? 1 : 0)
        u[6] = SIMD4(theme.wake, 0)

        for i in 0..<sharkCount {
            packShark(w.sharks[i], into: u + FrameLayout.sharkBase + i * FrameLayout.sharkStride)
        }
        for e in 0..<eventCount {
            let ev = w.events[e]
            u[FrameLayout.eventBase + e] = SIMD4(Float(ev.x), Float(ev.y), ev.kind == .eat ? 0 : 1, 0)
        }
        packFish(w, grid: grid, cw: cw, ch: ch, into: fishGrid)
    }

    private static func packFish(_ w: World, grid: GridSpec, cw: Double, ch: Double, into g: UnsafeMutablePointer<UInt8>) {
        let cells = grid.cols * grid.rows
        g.update(repeating: 0, count: cells * 4)
        var deposit = [Double](repeating: 0, count: cells)
        for f in w.fish where f.alive && f.x >= 0 && f.y >= 0 {
            let c = Int(f.x / cw), r = Int(f.y / ch)
            guard c < grid.cols, r < grid.rows else { continue }
            let i = r * grid.cols + c
            deposit[i] += 0.012 + f.alarm * 0.03
            let near = f.depth > 0.78
            let o = i * 4
            // One fish per cell; a near fish claims a shared cell first.
            if g[o] == 0 || (near && g[o + 3] == 0) {
                let glint = min(1, max(0, abs(f.turn) / 3.5))
                let v = 0.3 + 0.4 * (f.depth - 0.55) / 0.45 + 0.3 * max(glint, f.alarm)
                g[o] = 255
                g[o + 1] = UInt8(min(255, max(0, (v * 255).rounded())))
                g[o + 3] = near ? 255 : 0
            }
        }
        // Deposit is encoded over 0...0.25.
        for i in 0..<cells where deposit[i] > 0 {
            g[i * 4 + 2] = UInt8(min(255, (deposit[i] / 0.25 * 255).rounded()))
        }
    }

    /// The render spine: the sim spine plus a travelling body wave, as in rasterizeSharks.
    private static func packShark(_ sh: Shark, into s: UnsafeMutablePointer<SIMD4<Float>>) {
        let nodes = World.sharkNodes
        let L = sh.length
        let n = sh.nodes
        let swim = min(1.4, max(0.4, sh.speed / 60))
        var spine = [Double](repeating: 0, count: nodes * 2)
        for k in 0..<nodes {
            let t = Double(k) / Double(nodes - 1)
            let a = max(0, k - 1), c = min(nodes - 1, k + 1)
            var tx = n[a * 2] - n[c * 2], ty = n[a * 2 + 1] - n[c * 2 + 1]
            var tl = (tx * tx + ty * ty).squareRoot()
            if tl == 0 { tl = 1 }
            tx /= tl; ty /= tl
            let amp = L * 0.05 * (0.1 + 0.9 * pow(t, 1.8)) * swim
            let off = amp * sin(sh.phase - t * 5.2)
            spine[k * 2] = n[k * 2] - ty * off
            spine[k * 2 + 1] = n[k * 2 + 1] + tx * off
        }
        var arc = [Double](repeating: 0, count: nodes)
        for k in 1..<nodes {
            let dx = spine[k * 2] - spine[(k - 1) * 2], dy = spine[k * 2 + 1] - spine[(k - 1) * 2 + 1]
            arc[k] = arc[k - 1] + (dx * dx + dy * dy).squareRoot()
        }

        let shape = sharkShapes[sh.kind.index]
        // Bank into turns: the inside fin foreshortens, the outside one spreads.
        let bank = min(0.35, max(-0.35, sh.turn * 0.45))
        let flex = 1 + 0.06 * sin(sh.phase * 0.5)
        let reach = Double(shape.pectoral.w)
        let tipRight = L * reach * flex * (1 - bank)
        let tipLeft = L * reach * flex * (1 + bank)

        s[0] = SIMD4(Float(L), Float(sh.depth), Float(sh.kind.index), Float(sh.id))
        s[1] = SIMD4(Float(tipLeft), Float(tipRight), Float(sh.speed), Float(arc[nodes - 1]))
        s[2] = shape.pectoral
        s[3] = shape.pelvic
        s[4] = SIMD4(shape.caudal, shape.falcate ? 1 : 0, shape.dorsal.x, shape.dorsal.y)
        s[5] = SIMD4(shape.secondDorsal.x, shape.secondDorsal.y, shape.eye.x, shape.eye.y)
        s[6] = SIMD4(shape.gills.x, shape.gills.y, shape.head.x, shape.head.y)
        s[7] = SIMD4(shape.head.z, shape.head.w, 0, 0)
        var lo = SIMD2<Double>(.infinity, .infinity), hi = SIMD2<Double>(-.infinity, -.infinity)
        for k in 0..<nodes {
            let p = SIMD2(spine[k * 2], spine[k * 2 + 1])
            lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p)
            s[8 + k] = SIMD4(Float(p.x), Float(p.y), Float(arc[k]), 0)
        }
        // Fins and the cephalofoil reach at most ~0.36 L from the spine.
        let pad = L * 0.36
        s[28] = SIMD4(Float(lo.x - pad), Float(lo.y - pad), Float(hi.x + pad), Float(hi.y + pad))
    }
}
