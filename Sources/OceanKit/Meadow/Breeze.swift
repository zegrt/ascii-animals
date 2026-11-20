import CoreGraphics
import Foundation

/// The air over the meadow, in pt/s, ocean space (y down).
///
/// Two layers add up in `sample`:
/// - **Stirred air:** a coarse grid, one sample per 4 × 3 cells, that the pointer writes into. It decays with a
///   0.8 s half-life and spreads by a gentle 5-point diffusion (double-buffered, no allocation per step).
/// - **Weather** (`ambient`): a natural breeze of 10–40 pt/s from value noise at 0.03–0.12 Hz, travelling across
///   the meadow so neighbouring flowers sway a beat apart, plus a gust of 60–120 pt/s every 20–60 s that sweeps
///   across as a front. It varies only along x, so it is kept per grid column.
///
/// The weather's speeds (the wind, the gusts, and how fast their pattern and fronts travel) are given for 13-pt
/// cells and scale with `cell.width / 13`, like the butterflies'.
///
/// Research §4.2, §7 and the Recommended parameters (Breeze grid).
public final class Breeze {
    /// The natural breeze and its gusts. Checks turn it off to see only what the pointer wrote.
    public var ambient = true
    /// Seconds of breeze stepped so far.
    public private(set) var time: Double = 0

    // Grid geometry.
    private let ox: Double, oy: Double   // ocean-space position of sample (0, 0)
    private let sx: Double, sy: Double   // sample spacing, pt
    private let nx: Int, ny: Int
    private let scale: Double            // cell.width / 13
    // Stirred air, double-buffered for the diffusion.
    private var vx: [Double], vy: [Double]
    private var bx: [Double], by: [Double]
    private var stirred = false          // false while the grid is all zero, so a still pointer costs nothing
    // Weather, per grid column.
    private var ax: [Double], ay: [Double]
    private var weatherReady = false
    private var seed: Double = 0
    private var prevailing: Double = 1   // +1 blows right, -1 left
    private var gustAt: Double = 0       // when the next (or current) gust front starts
    private var gustPeak: Double = 0
    private var gustLength: Double = 4

    static let perSample = SIMD2<Double>(4, 3)   // cells per sample
    static let halfLife = 0.8                    // s
    static let pointerGain = 0.6                 // the pointer's velocity × 0.6
    static let radius = 2.5                      // samples: weight exp(-(d / radius)²)
    static let reach = 5                         // samples written around the pointer (weight there 0.018)
    static let diffusion = 0.1                   // samples² / s
    static let travel = 200.0                    // pt/s: how fast the natural breeze's pattern crosses the meadow
    static let gustFront = 450.0                 // pt/s: how fast a gust sweeps across

    public init(bounds: CGRect, cell: CGSize) {
        let cw = max(1, Double(cell.width)), ch = max(1, Double(cell.height))
        sx = Breeze.perSample.x * cw
        sy = Breeze.perSample.y * ch
        ox = Double(bounds.minX)
        oy = Double(bounds.minY)
        nx = max(2, Int(ceil(Double(bounds.width) / sx)) + 1)
        ny = max(2, Int(ceil(Double(bounds.height) / sy)) + 1)
        scale = cw / 13
        let n = nx * ny
        vx = [Double](repeating: 0, count: n)
        vy = vx
        bx = vx
        by = vx
        ax = [Double](repeating: 0, count: nx)
        ay = ax
    }

    /// Fractional grid coordinates of a point, clamped to the grid.
    @inline(__always) private func grid(_ x: Double, _ y: Double) -> (Double, Double) {
        (clamp((x - ox) / sx, 0, Double(nx - 1)), clamp((y - oy) / sy, 0, Double(ny - 1)))
    }

    /// The wind at a point, bilinear between samples. No wind at a non-finite point.
    public func sample(_ x: Double, _ y: Double) -> SIMD2<Double> {
        guard x.isFinite && y.isFinite else { return SIMD2<Double>(0, 0) }
        let (gx, gy) = grid(x, y)
        let i = min(Int(gx), nx - 2), j = min(Int(gy), ny - 2)
        let fx: Double = gx - Double(i), fy: Double = gy - Double(j)
        var out = SIMD2<Double>(0, 0)
        if stirred {
            let k = j * nx + i
            let w00: Double = (1 - fx) * (1 - fy), w10: Double = fx * (1 - fy)
            let w01: Double = (1 - fx) * fy, w11: Double = fx * fy
            out.x = vx[k] * w00 + vx[k + 1] * w10 + vx[k + nx] * w01 + vx[k + nx + 1] * w11
            out.y = vy[k] * w00 + vy[k + 1] * w10 + vy[k + nx] * w01 + vy[k + nx + 1] * w11
        }
        if ambient && weatherReady {
            out.x += ax[i] + (ax[i + 1] - ax[i]) * fx
            out.y += ay[i] + (ay[i + 1] - ay[i]) * fx
        }
        return out
    }

    /// The pointer moving at (vx, vy) pushes the air around it towards velocity × 0.6, with a Gaussian falloff
    /// of radius 2.5 samples. Blending (not adding) means a pointer held on one spot never winds the air up
    /// past its own speed.
    public func write(_ x: Double, _ y: Double, vx wx: Double, vy wy: Double) {
        guard x.isFinite && y.isFinite && wx.isFinite && wy.isFinite else { return }
        let tx: Double = wx * Breeze.pointerGain, ty: Double = wy * Breeze.pointerGain
        let gx: Double = (x - ox) / sx, gy: Double = (y - oy) / sy
        guard gx > -Double(Breeze.reach) && gx < Double(nx - 1 + Breeze.reach)
                && gy > -Double(Breeze.reach) && gy < Double(ny - 1 + Breeze.reach) else { return }
        let ci = Int(gx.rounded()), cj = Int(gy.rounded())
        let r2: Double = Breeze.radius * Breeze.radius
        let i0 = max(0, ci - Breeze.reach), i1 = min(nx - 1, ci + Breeze.reach)
        let j0 = max(0, cj - Breeze.reach), j1 = min(ny - 1, cj + Breeze.reach)
        guard i0 <= i1 && j0 <= j1 else { return }
        for j in j0...j1 {
            let dy: Double = Double(j) - gy
            for i in i0...i1 {
                let dx: Double = Double(i) - gx
                let w: Double = exp(-(dx * dx + dy * dy) / r2)
                let k = j * nx + i
                vx[k] += (tx - vx[k]) * w
                vy[k] += (ty - vy[k]) * w
            }
        }
        stirred = true
    }

    public func step(_ dt: Double, random: WebRandom) {
        guard dt > 0 else { return }
        time += dt
        if stirred { decayAndSpread(dt) }
        if ambient { weather(random) }
    }

    /// Decay (half-life 0.8 s) and a 5-point diffusion with closed borders, into the back buffers, then swap.
    private func decayAndSpread(_ dt: Double) {
        let keep: Double = pow(0.5, dt / Breeze.halfLife)
        let a: Double = min(0.2, Breeze.diffusion * dt)
        var peak: Double = 0
        for j in 0..<ny {
            let up = j > 0 ? -nx : 0, down = j < ny - 1 ? nx : 0
            for i in 0..<nx {
                let k = j * nx + i
                let left = i > 0 ? -1 : 0, right = i < nx - 1 ? 1 : 0
                let lx: Double = vx[k + left] + vx[k + right] + vx[k + up] + vx[k + down] - 4 * vx[k]
                let ly: Double = vy[k + left] + vy[k + right] + vy[k + up] + vy[k + down] - 4 * vy[k]
                let nxv: Double = (vx[k] + a * lx) * keep, nyv: Double = (vy[k] + a * ly) * keep
                bx[k] = nxv
                by[k] = nyv
                peak = max(peak, abs(nxv), abs(nyv))
            }
        }
        swap(&vx, &bx)
        swap(&vy, &by)
        if peak < 0.01 {
            for k in 0..<vx.count { vx[k] = 0; vy[k] = 0 }
            stirred = false
        }
    }

    private func planGust(at t: Double, _ random: WebRandom) {
        gustAt = t
        gustPeak = random.range(60, 120) * scale
        gustLength = random.range(3, 5)
    }

    /// The natural breeze and gusts for this instant, per grid column.
    private func weather(_ random: WebRandom) {
        if !weatherReady {
            seed = floor(random.range(0, 10_000))
            prevailing = random.unit() < 0.5 ? -1 : 1
            planGust(at: time + random.range(20, 60), random)
            weatherReady = true
        }
        let front: Double = Breeze.gustFront * scale, travel: Double = Breeze.travel * scale
        if time > gustAt + gustLength + Double(nx) * sx / front {
            // The gust has crossed the meadow: the next one starts 20–60 s after it did.
            planGust(at: max(time, gustAt + random.range(20, 60)), random)
        }
        let startX: Double = prevailing > 0 ? 0 : Double(nx - 1) * sx
        for i in 0..<nx {
            let x: Double = Double(i) * sx
            // Travelling value noise: two octaves at ~0.035 and ~0.1 Hz.
            let u: Double = time - prevailing * x / travel
            let n: Double = 0.65 * noise1(u * 0.035, seed) + 0.35 * noise1(u * 0.1, seed + 17)
            let speed: Double = (25 + 15 * clamp(n * 1.6, -1, 1)) * scale
            let angle: Double = 0.3 * noise1(u * 0.05, seed + 41)   // wanders ±17° off level
            var wx: Double = prevailing * speed * cos(angle)
            var wy: Double = speed * sin(angle)
            // A gust front, with the prevailing wind: a sin² bump that reaches this column later the farther it is from where it began.
            let tau: Double = time - gustAt - abs(x - startX) / front
            if tau > 0 && tau < gustLength {
                let s: Double = sin(Double.pi * tau / gustLength)
                wx += prevailing * gustPeak * s * s
                wy -= 0.15 * gustPeak * s * s   // gusts lift a little
            }
            ax[i] = wx
            ay[i] = wy
        }
    }
}
