import Foundation

// Port of math.ts from ascii-spiders by @stackedlol (MIT), commit 89a7721.
// See docs/reference/web-port-notes.md for what differs and why.

public let TAU = Double.pi * 2

@inline(__always) public func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    v < lo ? lo : v > hi ? hi : v
}

@inline(__always) public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

// rand and randInt draw from Math.random(), so they live on WebRandom (`range` and `int`), passed explicitly.

@inline(__always) public func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }

@inline(__always) public func easeOut(_ t: Double) -> Double { 1 - (1 - t) * (1 - t) }

public func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = clamp((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)
}

/// Shortest signed angle from a to b, in (-PI, PI].
@inline(__always) public func angleDiff(_ a: Double, _ b: Double) -> Double {
    var d = fmod(b - a, TAU)
    if d > .pi { d -= TAU }
    if d < -.pi { d += TAU }
    return d
}

/// Cheap integer hash → [0, 1). Deterministic, so textures stay put.
public func hash3(_ x: Double, _ y: Double, _ z: Double) -> Double {
    var h = (UInt32(bitPattern: toInt32(x)) &* 374_761_393) ^ (UInt32(bitPattern: toInt32(y)) &* 668_265_263)
        ^ (UInt32(bitPattern: toInt32(z)) &* 1_442_695_041)
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Double(h) / 4_294_967_296
}

/// Smooth 1D value noise in [-1, 1].
public func noise1(_ x: Double, _ seed: Double = 0) -> Double {
    let i = floor(x)
    let f = x - i
    let a = hash3(i, seed, 91) * 2 - 1
    let b = hash3(i + 1, seed, 91) * 2 - 1
    return a + (b - a) * f * f * (3 - 2 * f)
}

/// Parameter of the point on segment a→b closest to p, in [0, 1].
@inline(__always)
public func closestT(_ px: Double, _ py: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
    let sx = bx - ax
    let sy = by - ay
    let l2 = sx * sx + sy * sy
    if l2 < 1e-9 { return 0 }
    return clamp(((px - ax) * sx + (py - ay) * sy) / l2, 0, 1)
}

/// Where segments p0→p1 and q0→q1 cross: the parameter along q, or -1.
@inline(__always)
public func crossAlong(
    _ p0x: Double, _ p0y: Double, _ p1x: Double, _ p1y: Double,
    _ q0x: Double, _ q0y: Double, _ q1x: Double, _ q1y: Double
) -> Double {
    let rx = p1x - p0x
    let ry = p1y - p0y
    let sx = q1x - q0x
    let sy = q1y - q0y
    let den = rx * sy - ry * sx
    if abs(den) < 1e-9 { return -1 }
    let qpx = q0x - p0x
    let qpy = q0y - p0y
    let t = (qpx * sy - qpy * sx) / den
    let u = (qpx * ry - qpy * rx) / den
    return t >= 0 && t <= 1 && u >= 0 && u <= 1 ? u : -1
}

/// A point. The original passes one in to be written into so hot loops don't allocate; a Swift struct
/// is returned by value instead, which doesn't allocate either.
public struct Vec: Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

// ── platform: JavaScript number semantics the port relies on ──

/// JavaScript's `Math.round`: halves round up (towards +∞), unlike Swift's `.rounded()`.
@inline(__always) public func mathRound(_ x: Double) -> Double {
    let r = floor(x)
    return x - r >= 0.5 ? r + 1 : r
}

/// JavaScript's ToInt32 (`x | 0`): truncate, then wrap modulo 2^32.
@inline(__always) func toInt32(_ x: Double) -> Int32 {
    if abs(x) < 9.0e18 { return Int32(truncatingIfNeeded: Int64(x)) }
    guard x.isFinite else { return 0 }
    return Int32(truncatingIfNeeded: Int64(fmod(x.rounded(.towardZero), 4_294_967_296)))
}

/// The original's `Math.random()`, `rand` and `randInt`, drawn from one seeded stream so a web (and later
/// the whole wall) replays exactly. Pass the same instance everywhere the original shares `Math.random`.
public final class WebRandom {
    private var rng: Rng

    public init(seed: UInt64) { rng = Rng(seed: seed) }

    /// `Math.random()`: uniform in [0, 1).
    @inline(__always) public func unit() -> Double { rng.unit() }

    /// `rand(lo, hi)`.
    @inline(__always) public func range(_ lo: Double, _ hi: Double) -> Double { lo + unit() * (hi - lo) }

    /// `randInt(lo, hi)`: lo...hi inclusive.
    @inline(__always) public func int(_ lo: Int, _ hi: Int) -> Int { Int(floor(range(Double(lo), Double(hi + 1)))) }
}
