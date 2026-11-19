import CoreGraphics
import Foundation
import OceanKit
import simd

/// The user's arrangement in ocean space: a 2560x1440 monitor directly above
/// an 1800x1169 laptop whose left edge is 375 pt in from the monitor's.
let userMonitor = CGRect(x: 0, y: 0, width: 2560, height: 1440)
let userLaptop = CGRect(x: 375, y: 1440, width: 1800, height: 1169)

/// world.ts's soft wall for a W x H box, per axis.
private func boxPush(_ x: Double, _ y: Double, _ W: Double, _ H: Double, _ m: Double) -> SIMD2<Double> {
    var ax = 0.0, ay = 0.0
    if x < m { ax += (m - x) * 7 } else if x > W - m { ax -= (x - (W - m)) * 7 }
    if y < m { ay += (m - y) * 7 } else if y > H - m { ay -= (y - (H - m)) * 7 }
    return SIMD2(ax, ay)
}

func terrainChecks() {
    check("terrainSingleMatchesBox") {
        let h = Terrain.single(width: 800, height: 500)
        for (x, y) in [(400.0, 250.0), (10, 250), (790, 250), (400, 5), (400, 495), (5, 5), (795, 495), (-30, 250), (400, 540)] {
            let got = h.wallPush(SIMD2(x, y), margin: 36), want = boxPush(x, y, 800, 500, 36)
            try expect(abs(got.x - want.x) < 1e-9 && abs(got.y - want.y) < 1e-9, "at (\(x),\(y)) got \(got) want \(want)")
        }
    }
    check("terrainStackedAdjacent") {
        let h = Terrain(rects: [userMonitor, userLaptop])
        try expect(h.neighbours[0] == [1] && h.neighbours[1] == [0], "neighbours \(h.neighbours)")
        try expect(h.doorway(0, 1) == SIMD2(1275, 1440), "doorway \(String(describing: h.doorway(0, 1)))")
    }
    check("terrainSharedEdgeNoWall") {
        let h = Terrain(rects: [userMonitor, userLaptop])
        let p = h.wallPush(SIMD2(1275, 1435), margin: 36)
        try expect(p == .zero, "push at doorway \(p)")
        try expect(h.wallPush(SIMD2(1275, 1445), margin: 36) == .zero, "push just below doorway")
    }
    check("terrainStripIsWall") {
        let h = Terrain(rects: [userMonitor, userLaptop])
        let p = SIMD2(200.0, 1600)
        try expect(!h.contains(p), "strip beside the laptop counted as ocean")
        let push = h.wallPush(p, margin: 36)
        try expect(push.x > 0 || push.y < 0, "strip not pushed back into the ocean: \(push)")
        try expect(h.signedOutside(p) > 0, "strip not outside")
    }
    check("terrainGapNotAdjacent") {
        let h = Terrain(rects: [CGRect(x: 0, y: 0, width: 500, height: 400), CGRect(x: 550, y: 0, width: 500, height: 400)])
        try expect(h.neighbours[0].isEmpty && h.neighbours[1].isEmpty, "gap counted as adjacent")
        try expect(!h.contains(SIMD2(525, 200)), "gap counted as ocean")
    }
    check("terrainSignedOutside") {
        let h = Terrain.single(width: 800, height: 500)
        try expectClose(h.signedOutside(SIMD2(10, 250)), -10, tol: 1e-9, "inside")
        try expectClose(h.signedOutside(SIMD2(-20, 250)), 20, tol: 1e-9, "outside")
        let s = Terrain(rects: [userMonitor, userLaptop])
        // Near the doorway the nearest wall is far away, not the shared edge.
        try expect(s.signedOutside(SIMD2(1275, 1440)) < -300, "shared edge treated as a wall: \(s.signedOutside(SIMD2(1275, 1440)))")
    }
    check("terrainEdgesExposedOnly") {
        let h = Terrain(rects: [userMonitor, userLaptop])
        let perimeter = 2 * (2560 + 1440) + 2 * (1800 + 1169.0)
        let total = h.edges.reduce(0) { $0 + $1.length }
        try expectClose(total, perimeter - 2 * 1800, tol: 1e-6, "exposed length")
    }
    check("terrainNearestInside") {
        let h = Terrain(rects: [userMonitor, userLaptop])
        let q = h.nearestInside(SIMD2(200, 1600))
        try expect(h.contains(q) || h.signedOutside(q) < 1e-6, "nearestInside not inside: \(q)")
        try expectClose(simd_length(q - SIMD2(200, 1600)), 160, tol: 1e-6, "nearest distance") // up to the monitor's bottom edge
    }
    check("terrainRectIndex") {
        let h = Terrain(rects: [userMonitor, userLaptop])
        try expect(h.rectIndex(near: SIMD2(1000, 2000)) == 1 && h.rectIndex(near: SIMD2(100, 100)) == 0, "rect index")
        try expect(h.rectIndex(near: SIMD2(100, 2500)) == 1, "nearest rect for a point in the strip")
    }
}
