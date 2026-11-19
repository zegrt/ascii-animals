import CoreGraphics
import simd

/// Where the ocean lives: the union of the screen rectangles, in ocean space
/// (points, top-left origin, bounding box starting at 0,0).
///
/// Everything the simulation used to ask of its single W x H box — soft
/// walls, "has the snout left the frame", where schools enter — it now asks
/// the Terrain. With one rect every answer equals the old box formula.
public struct Terrain: Equatable, Sendable {
    /// A piece of the outline that is not shared with another rect: a real wall.
    public struct Edge: Equatable, Sendable {
        public var a: SIMD2<Double>
        public var b: SIMD2<Double>
        /// Points into the ocean.
        public var normal: SIMD2<Double>
        public var rect: Int
        public var length: Double { simd_length(b - a) }
    }

    public let rects: [CGRect]
    public let bounds: CGRect
    public let area: Double
    public let edges: [Edge]
    public let neighbours: [[Int]]
    private let doorways: [Int: SIMD2<Double>]

    static let touch = 0.5   // points: edges this close are considered touching
    static let minDoor = 1.0 // shared edges shorter than this don't count

    public static func single(width: Double, height: Double) -> Terrain {
        Terrain(rects: [CGRect(x: 0, y: 0, width: width, height: height)])
    }

    public init(rects: [CGRect]) {
        self.rects = rects
        bounds = rects.dropFirst().reduce(rects.first ?? .zero) { $0.union($1) }
        area = rects.reduce(0) { $0 + Double($1.width * $1.height) }

        var edges: [Edge] = []
        var neighbours = [[Int]](repeating: [], count: rects.count)
        var doorways: [Int: SIMD2<Double>] = [:]
        for (i, r) in rects.enumerated() {
            let minX = Double(r.minX), maxX = Double(r.maxX), minY = Double(r.minY), maxY = Double(r.maxY)
            // (fixed coordinate, span start, span end, horizontal?, inward normal, which side of others touches)
            let sides: [(Double, Double, Double, Bool, SIMD2<Double>)] = [
                (minY, minX, maxX, true, SIMD2(0, 1)),   // top
                (maxY, minX, maxX, true, SIMD2(0, -1)),  // bottom
                (minX, minY, maxY, false, SIMD2(1, 0)),  // left
                (maxX, minY, maxY, false, SIMD2(-1, 0)), // right
            ]
            for (fixed, lo, hi, horizontal, normal) in sides {
                var pieces = [(lo, hi)]
                for (j, o) in rects.enumerated() where j != i {
                    // The other rect's opposite side must lie on this line.
                    let opposite: Double
                    let oLo: Double, oHi: Double
                    if horizontal {
                        opposite = normal.y > 0 ? Double(o.maxY) : Double(o.minY)
                        oLo = Double(o.minX); oHi = Double(o.maxX)
                    } else {
                        opposite = normal.x > 0 ? Double(o.maxX) : Double(o.minX)
                        oLo = Double(o.minY); oHi = Double(o.maxY)
                    }
                    guard abs(opposite - fixed) < Terrain.touch else { continue }
                    let s = max(lo, oLo), e = min(hi, oHi)
                    guard e - s > Terrain.minDoor else { continue }
                    pieces = Terrain.subtract(pieces, s, e)
                    if !neighbours[i].contains(j) { neighbours[i].append(j) }
                    let mid = (s + e) / 2
                    doorways[Terrain.key(i, j)] = horizontal ? SIMD2(mid, fixed) : SIMD2(fixed, mid)
                }
                for (s, e) in pieces where e - s > 1e-9 {
                    let a = horizontal ? SIMD2(s, fixed) : SIMD2(fixed, s)
                    let b = horizontal ? SIMD2(e, fixed) : SIMD2(fixed, e)
                    edges.append(Edge(a: a, b: b, normal: normal, rect: i))
                }
            }
        }
        self.edges = edges
        self.neighbours = neighbours.map { $0.sorted() }
        self.doorways = doorways
    }

    private static func key(_ i: Int, _ j: Int) -> Int { min(i, j) * 1024 + max(i, j) }

    private static func subtract(_ pieces: [(Double, Double)], _ s: Double, _ e: Double) -> [(Double, Double)] {
        pieces.flatMap { (lo, hi) -> [(Double, Double)] in
            if e <= lo || s >= hi { return [(lo, hi)] }
            var out: [(Double, Double)] = []
            if s > lo { out.append((lo, s)) }
            if e < hi { out.append((e, hi)) }
            return out
        }
    }

    /// Midpoint of the edge two touching rects share.
    public func doorway(_ i: Int, _ j: Int) -> SIMD2<Double>? { doorways[Terrain.key(i, j)] }

    public func contains(_ p: SIMD2<Double>) -> Bool {
        rects.contains { Double($0.minX) <= p.x && p.x <= Double($0.maxX) && Double($0.minY) <= p.y && p.y <= Double($0.maxY) }
    }

    private func clamp(_ p: SIMD2<Double>, to r: CGRect) -> SIMD2<Double> {
        SIMD2(min(Double(r.maxX), max(Double(r.minX), p.x)), min(Double(r.maxY), max(Double(r.minY), p.y)))
    }

    /// The rect containing `p`, else the nearest one.
    public func rectIndex(near p: SIMD2<Double>) -> Int {
        var best = 0, bestD = Double.infinity
        for (i, r) in rects.enumerated() {
            let d = simd_length_squared(p - clamp(p, to: r))
            if d < bestD { bestD = d; best = i }
            if d == 0 { return i }
        }
        return best
    }

    public func nearestInside(_ p: SIMD2<Double>) -> SIMD2<Double> {
        guard !rects.isEmpty else { return p }
        return clamp(p, to: rects[rectIndex(near: p)])
    }

    private func distance(_ p: SIMD2<Double>, to e: Edge) -> Double {
        let d = e.b - e.a
        let t = min(1, max(0, simd_dot(p - e.a, d) / max(simd_length_squared(d), 1e-12)))
        return simd_length(p - (e.a + d * t))
    }

    /// Positive outside (distance to the ocean), zero or negative inside
    /// (minus the distance to the nearest real wall). For one rect this is
    /// world.ts's `max(-x, x - W, -y, y - H)`.
    public func signedOutside(_ p: SIMD2<Double>) -> Double {
        if contains(p) {
            return -(edges.map { distance(p, to: $0) }.min() ?? 0)
        }
        return simd_length(p - nearestInside(p))
    }

    /// world.ts's soft wall, per exposed edge: `(margin - s) * 7` along the
    /// edge's inward normal when the signed distance `s` is under `margin`.
    /// Inside the ocean only walls in front of the point count; outside,
    /// walls within `margin` of their ends count too, and anything stranded
    /// beyond every wall is pulled to the nearest ocean.
    public func wallPush(_ p: SIMD2<Double>, margin m: Double) -> SIMD2<Double> {
        let inside = contains(p)
        var push = SIMD2<Double>(0, 0)
        var applied = false
        for e in edges {
            let s = simd_dot(p - e.a, e.normal)
            guard s < m else { continue }
            if inside && s < 0 { continue }
            let dir = (e.b - e.a) / max(e.length, 1e-12)
            let t = simd_dot(p - e.a, dir)
            let slack = inside ? 0 : m
            guard t >= -slack && t <= e.length + slack else { continue }
            push += e.normal * ((m - s) * 7)
            applied = true
        }
        if !inside && !applied {
            let q = nearestInside(p)
            let d = simd_length(q - p)
            if d > 1e-9 { push += (q - p) / d * ((d + m) * 7) }
        }
        return push
    }
}
