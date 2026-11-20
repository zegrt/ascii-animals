import Foundation

// The Meadow sketch's own numbers, ported exactly so a seed gives the same draws, hashes and noise as the sketch
// (Tools/meadow-sketch/meadow.html on meadow-sketch, "Basics", html:140–177). `html:N` below is a line of that file
// at f20b833.
//
// These differ from Web's on purpose: Web's `hash3` and `WebRandom` are ports of a different original and give other
// numbers (port inventory §4 item 6). Only `clamp`, `lerp` and `smoothstep` are shared, being the same functions.

/// The sketch's seeded generator, Mulberry32 (html:148–151): one 32-bit state, the same sequence as the sketch's
/// `mulberry32(a)` in every engine.
public struct Mulberry32: Sendable {
    public private(set) var state: UInt32

    /// `mulberry32(a)` with `a` as the sketch holds it, a 32-bit integer (`seed | 0`).
    public init(_ a: Int32) { state = UInt32(bitPattern: a) }

    /// The next draw in [0, 1).
    @inline(__always) public mutating func next() -> Double {
        state = state &+ 0x6D2B_79F5
        let a = state
        var t: UInt32 = (a ^ (a >> 15)) &* (1 | a)
        let u: UInt32 = (t ^ (t >> 7)) &* (61 | t)
        t = (t &+ u) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

/// One of the sketch's random streams with its helpers (`R`, `RI`, `gauss`, `shuffle`, html:158–162).
///
/// The sketch keeps two streams from the one seed (html:152–157): the meadow's own (planting, flight, the opening)
/// and the input's (clicks, resizing, pointer moves), so a click never shifts the meadow's draws. `MeadowRandom.pair`
/// makes both. A class, so every part of the meadow that draws from one stream shares it, as the sketch's `rnd` is
/// shared.
public final class MeadowRandom {
    private var gen: Mulberry32
    private let start: Int32

    public init(_ a: Int32) {
        gen = Mulberry32(a)
        start = a
    }

    /// The sketch's two streams for a seed: `simRnd = mulberry32(seed)`, `uiRnd = mulberry32(seed ^ 0x5bd1e995)`.
    public static func pair(seed: Int32) -> (sim: MeadowRandom, input: MeadowRandom) {
        let mix = Int32(bitPattern: 0x5BD1_E995)
        return (MeadowRandom(seed), MeadowRandom(seed ^ mix))
    }

    /// The sketch's seed from a number, as `+v | 0` reads it (JavaScript's ToInt32).
    public static func seed(_ v: Double) -> Int32 { toInt32(v) }

    /// Back to the start of the stream.
    public func restart() { gen = Mulberry32(start) }

    /// `rnd()`: uniform in [0, 1).
    @inline(__always) public func unit() -> Double { gen.next() }

    /// `R(a, b)`.
    @inline(__always) public func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }

    /// `RI(a, b)`: a…b inclusive.
    @inline(__always) public func int(_ a: Int, _ b: Int) -> Int {
        let lo = Double(a)
        let span: Double = Double(b) - lo + 1
        return Int(floor(lo + span * unit()))
    }

    /// `gauss()`: a standard normal draw (two draws, Box–Muller).
    public func gauss() -> Double {
        let a = max(unit(), 1e-12)
        let b = unit()
        return sqrt(-2 * log(a)) * cos(TAU * b)
    }

    /// `shuffle(a)`: the sketch's seeded Fisher–Yates, in place (html:162).
    public func shuffle<T>(_ a: inout [T]) {
        var i = a.count - 1
        while i > 0 {
            let j = Int(floor(unit() * Double(i + 1)))
            a.swapAt(i, j)
            i -= 1
        }
    }
}

/// The sketch's hashes and noise (html:164–177).
public enum MeadowMath {
    /// `hash3(x, y, z)`: a stable hash of three integers (each read as `| 0`) to [0, 1).
    public static func hash3(_ x: Double, _ y: Double, _ z: Double) -> Double {
        let hx: UInt32 = UInt32(bitPattern: toInt32(x)) &* 0x27D4_EB2D
        let hy: UInt32 = UInt32(bitPattern: toInt32(y)) &* 0x1656_67B1
        let hz: UInt32 = UInt32(bitPattern: toInt32(z)) &* 0x9E37_79B1
        var h: UInt32 = hx ^ hy ^ hz
        h = (h ^ (h >> 15)) &* 0x85EB_CA6B
        h = (h ^ (h >> 13)) &* 0xC2B2_AE35
        h ^= h >> 16
        return Double(h) / 4_294_967_296
    }

    /// `keyOf(x, y, s)`: the hash as a 32-bit key (html:603).
    public static func key(_ x: Double, _ y: Double, _ s: Double) -> UInt32 {
        UInt32(hash3(x, y, s) * 4_294_967_296)
    }

    /// `vnoise(x, y, s)`: smooth value noise in [0, 1].
    public static func vnoise(_ x: Double, _ y: Double, _ s: Double) -> Double {
        let xi = floor(x), yi = floor(y)
        var xf: Double = x - xi
        var yf: Double = y - yi
        xf = xf * xf * (3 - 2 * xf)
        yf = yf * yf * (3 - 2 * yf)
        let a = hash3(xi, yi, s)
        let b = hash3(xi + 1, yi, s)
        let c = hash3(xi, yi + 1, s)
        let d = hash3(xi + 1, yi + 1, s)
        let ab: Double = (b - a) * xf
        let ac: Double = (c - a) * yf
        let abcd: Double = (a - b - c + d) * xf * yf
        return a + ab + ac + abcd
    }

    /// `n1(t, s)`: one-dimensional noise in [-1, 1].
    @inline(__always) public static func n1(_ t: Double, _ s: Double) -> Double { vnoise(t, 0.5, s) * 2 - 1 }

    /// `smooth(a, b, x)`: the sketch's smoothstep (the family's `smoothstep`, html:143).
    @inline(__always) public static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        smoothstep(a, b, x)
    }

    /// `easeOutBack(t)` with the sketch's overshoot c1 = 1.4 (html:1274): a bloom's growth.
    public static func easeOutBack(_ t: Double) -> Double {
        let c1 = MeadowTuning.Flowers.growOvershoot
        let c3: Double = c1 + 1
        let u: Double = t - 1
        return 1 + c3 * u * u * u + c1 * u * u
    }

    /// JavaScript's `Math.round` (halves up), for the sketch's `Math.round`.
    @inline(__always) public static func round(_ x: Double) -> Double { mathRound(x) }
}
