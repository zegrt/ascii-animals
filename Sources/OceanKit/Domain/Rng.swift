/// SplitMix64: small, fast, seedable. All simulation randomness goes through
/// one of these so checks are reproducible.
public struct Rng {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    public mutating func unit() -> Double { Double(next() >> 11) * 0x1.0p-53 }

    public mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }

    public mutating func chance(_ p: Double) -> Bool { unit() < p }

    public mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) }
}
