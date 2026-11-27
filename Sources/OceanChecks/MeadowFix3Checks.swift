import CoreGraphics
import Foundation
@_spi(Checks) import OceanKit
import simd

// mp's fix round 3: the world's signed distance to the terrain (read every step by the edge steer and the entry test)
// works from the world's own copies of the screens and walls, so it touches no terrain copy, closure or generic call;
// it must still give the terrain's numbers exactly, and allocate nothing.

private let cell13 = CGSize(width: 13, height: 19)

func meadowFix3Checks() {
    check("meadowSignedOutsideMatchesTheTerrain", meadowSignedOutsideMatchesTheTerrain)
}

/// On the desk pair, two screens side by side, a pair with a gap and a single screen: at points on, near and far off
/// the screens (corners and edges included), the world's number is the terrain's, bit for bit; and a sweep of calls
/// allocates nothing.
private func meadowSignedOutsideMatchesTheTerrain() throws {
    let terrains: [(String, Terrain)] = [
        ("desk pair", Terrain(rects: [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1800, height: 1169)])),
        ("side by side", Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1440, height: 900)])),
        ("with a gap", Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1480, y: 0, width: 1440, height: 900)])),
        ("one screen", Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900)])),
    ]
    for (name, t) in terrains {
        let w = MeadowWorld(terrain: t, cell: cell13, seed: 5)
        let b = t.bounds
        let x0: Double = Double(b.minX) - 300, y0: Double = Double(b.minY) - 300
        let dx: Double = (Double(b.width) + 600) / 173, dy: Double = (Double(b.height) + 600) / 131
        func one(_ x: Double, _ y: Double) throws {
            let mine: Double = w.probeSignedOutside(x: x, y: y)
            let theirs: Double = t.signedOutside(SIMD2(x, y))
            try expect(mine.bitPattern == theirs.bitPattern, "\(name) at (\(x), \(y)): world \(mine), terrain \(theirs)")
        }
        for i in 0...173 { for j in 0...131 { try one(x0 + Double(i) * dx, y0 + Double(j) * dy) } }
        for r in t.rects {
            let xs: [Double] = [Double(r.minX), Double(r.midX), Double(r.maxX)]
            let ys: [Double] = [Double(r.minY), Double(r.midY), Double(r.maxY)]
            for x in xs { for y in ys { for e in [-1.0, -1e-9, 0, 1e-9, 1] { try one(x + e, y); try one(x, y + e) } } }
        }
        var sink = 0.0
        let n = allocations({
            for i in 0...173 { for j in 0...131 { sink += w.probeSignedOutside(x: x0 + Double(i) * dx, y: y0 + Double(j) * dy) } }
        })
        if let n { try expect(n == 0, "\(name): \(n) allocations in \(174 * 132) calls") }
        try expect(sink.isFinite, "\(name): a distance not finite")
    }
}
