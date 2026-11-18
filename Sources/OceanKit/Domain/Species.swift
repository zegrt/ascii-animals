// Fish species and shark line-ups. Port of ascii-sharks species.ts (MIT).

struct FishSpecies {
    let cruise, maxSpeed, minSpeed, weight: Double
    let schoolMin, schoolMax: Int
    let spacingX, spacingY, align, cohesion, jitter, mill, verticalDrag: Double
}

let fishSpecies: [FishSpecies] = [
    // sardine
    FishSpecies(cruise: 36, maxSpeed: 64, minSpeed: 18, weight: 3, schoolMin: 18, schoolMax: 28, spacingX: 1.8, spacingY: 1.1,
                align: 1.6, cohesion: 1.6, jitter: 40, mill: 70, verticalDrag: 0.5),
    // anchovy
    FishSpecies(cruise: 46, maxSpeed: 78, minSpeed: 22, weight: 3, schoolMin: 20, schoolMax: 32, spacingX: 1.5, spacingY: 1,
                align: 3.2, cohesion: 0.45, jitter: 30, mill: 0, verticalDrag: 1.4),
    // silverside
    FishSpecies(cruise: 40, maxSpeed: 70, minSpeed: 20, weight: 3, schoolMin: 12, schoolMax: 20, spacingX: 2, spacingY: 1.1,
                align: 2.4, cohesion: 1.1, jitter: 35, mill: 0, verticalDrag: 1.6),
    // mackerel
    FishSpecies(cruise: 32, maxSpeed: 60, minSpeed: 16, weight: 2, schoolMin: 5, schoolMax: 9, spacingX: 2.6, spacingY: 1.3,
                align: 2, cohesion: 0.9, jitter: 25, mill: 0, verticalDrag: 2),
    // goby
    FishSpecies(cruise: 26, maxSpeed: 56, minSpeed: 10, weight: 1, schoolMin: 8, schoolMax: 12, spacingX: 1.4, spacingY: 1.1,
                align: 0.35, cohesion: 1.4, jitter: 110, mill: 0, verticalDrag: 0.3),
]

let fishTotalWeight = fishSpecies.reduce(0) { $0 + $1.weight }

public struct SharkSpec: Equatable, Sendable {
    public var kind: SharkKind
    public var size: Double

    /// First is biggest, each next one 0.1 smaller. Empty: the landing page's four classics.
    public static func lineUp(_ kinds: [SharkKind]) -> [SharkSpec] {
        if kinds.isEmpty {
            return [1, 0.7, 0.84, 0.77].map { SharkSpec(kind: .classic, size: $0) }
        }
        return kinds.enumerated().map { SharkSpec(kind: $1, size: 1 - Double($0) * 0.1) }
    }
}
