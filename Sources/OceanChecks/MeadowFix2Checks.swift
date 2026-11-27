import CoreGraphics
import Foundation
@_spi(Checks) import OceanKit
import simd

// mp's fix round 2: the re-check's five narrow cases, each held by a check that fails without its fix. A zero-length
// gap at an exact screen corner; a relayout that leaves a departing flyer off the screens or an approach whose way now
// crosses a gap; a pointer that leaves the terrain by less than the 2.5 pt move rule; allocations while newcomers
// arrive after a count change; and a display left empty at the start because area seeding missed it.

private let tick: Double = 1.0 / 60.0
private let cell13 = CGSize(width: 13, height: 19)

private let oneScreen = Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900)])
private let twoTouching = Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1440, height: 900)])
/// Two 1440 x 900 screens 40 pt apart.
private let wideGap = Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1480, y: 0, width: 1440, height: 900)])
/// Two 1440 x 900 screens one point apart, the right one 2 pt lower (the re-check's empty-display layout).
private let hairline = Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1441, y: 2, width: 1440, height: 900)])
/// The right screen starts 40 pt right of the left one and exactly at its bottom: the gap between them is the single
/// line y = 900, 1440 < x < 1480 (the re-check's corner case).
private let cornerPair = Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1480, y: 900, width: 1440, height: 900)])
/// Three screens in a row, 40 pt apart.
private let threeApart = Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1480, y: 0, width: 1440, height: 900),
                                         CGRect(x: 2960, y: 0, width: 1440, height: 900)])
private let deskPair = Terrain(rects: [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1800, height: 1169)])

func meadowFix2Checks() {
    check("meadowCornerGapIsAGap", meadowCornerGapIsAGap)
    check("meadowRelayoutHoldsDeparturesAndRoutes", meadowRelayoutHoldsDeparturesAndRoutes)
    check("meadowPointerOffTheTerrainEndsTheLanding", meadowPointerOffTheTerrainEndsTheLanding)
    check("meadowArrivalsAllocateNothing", meadowArrivalsAllocateNothing)
    check("meadowNoDisplayStartsEmpty", meadowNoDisplayStartsEmpty)
}

private func onScreens(_ t: Terrain, _ x: Double, _ y: Double) -> Bool {
    for r in t.rects where x >= Double(r.minX) && x <= Double(r.maxX) && y >= Double(r.minY) && y <= Double(r.maxY) { return true }
    return false
}

/// The check's own exact test for the corner pair: the step from p to q meets the line y = 900 strictly between the
/// two screens (1440 < x < 1480), where no screen is.
private func crossesCornerGap(_ px: Double, _ py: Double, _ qx: Double, _ qy: Double) -> Bool {
    let ay: Double = py - 900, by: Double = qy - 900
    if ay * by > 0 || py == qy { return false }
    let k: Double = (900 - py) / (qy - py)
    let x: Double = px + (qx - px) * k
    return x > 1440 && x < 1480
}

/// Re-check, finding 2: the gap at an exact corner has zero height, so a segment through it clips to zero length. It
/// still counts as entering the gap, and flight steps from just above the corner line never go through it.
private func meadowCornerGapIsAGap() throws {
    let w = MeadowWorld(terrain: cornerPair, cell: cell13, seed: 3)
    try expect(w.probeInGap(1460, 900), "the corner point (1460, 900) is not judged in the gap")
    try expect(w.segmentEntersGap(1460, 899, 1459.999, 901.773), "the re-check's step through the corner gap is not seen")
    try expect(w.segmentEntersGap(1450, 890, 1470, 910), "a diagonal through the corner gap is not seen")
    try expect(!w.segmentEntersGap(1400, 890, 1430, 899), "a step on the left screen counts as entering the gap")
    try expect(!w.segmentEntersGap(1500, 1000, 1500, 901), "a step on the right screen counts as entering the gap")
    guard let b = w.flies.first else { throw CheckFailure(detail: "no butterflies") }
    let starts: [(Double, Double, Double, Double)] = [(1460, 899, -0.06, 166.38), (1460, 899, 0, 120), (1450, 898.5, 60, 200),
                                                     (1470, 899.5, -90, 300), (1445, 899, 0, 600)]
    for (x, y, vx, vy) in starts {
        w.probeFly(b, x: x, y: y, vx: vx, vy: vy)
        for s in 0..<20 {
            let px = b.x, py = b.y
            w.probeStep(b)
            try expect(!crossesCornerGap(px, py, b.x, b.y),
                       "from (\(x), \(y)) at (\(vx), \(vy)): step \(s) went from (\(px), \(py)) through the corner gap to (\(b.x), \(b.y))")
        }
    }
}

/// Re-check, finding 4: a departing flyer on the screen that is unplugged is put on a surviving screen, as any other
/// flyer is; and an approach whose way to its (still valid) bloom crosses a gap after the relayout is given up.
private func meadowRelayoutHoldsDeparturesAndRoutes() throws {
    for seed: Int32 in [2, 3, 4] {
        let w = MeadowWorld(terrain: oneScreen, cell: cell13, seed: seed)
        w.layout(terrain: twoTouching, cell: cell13)
        guard let b = w.flies.first else { throw CheckFailure(detail: "no butterflies") }
        w.probeFly(b, x: 1441, y: 450, vx: 100, vy: 0)
        w.probeSendAway(b)
        try expect(b.leaving, "the probe did not send it away")
        w.layout(terrain: oneScreen, cell: cell13)
        try expect(onScreens(oneScreen, b.x, b.y), "seed \(seed): after the unplug the departing flyer is at (\(b.x), \(b.y)), off the remaining screen")
    }

    for seed: Int32 in [2, 3, 4] {
        let w = MeadowWorld(terrain: twoTouching, cell: cell13, seed: seed)
        guard let b = w.flies.first else { throw CheckFailure(detail: "no butterflies") }
        let f = w.flowers.make(.daisy, x: 1500, y: 450, grown: true, rng: MeadowRandom(7))
        w.flowers.showOnly([f])
        w.probeApproach(b, x: 1300, y: 450, flower: f.id)
        try expect(b.state == .approach && b.flower == f.id, "the probe did not start the approach")
        // A 40 pt gap opens between the screens; the bloom stays on the right one, the flyer on the left.
        w.layout(terrain: wideGap, cell: cell13)
        try expect(w.flowers.index(of: f.id) != nil, "seed \(seed): the bloom did not survive the relayout (the case needs it)")
        try expect(onScreens(wideGap, b.x, b.y) && b.x < 1440, "seed \(seed): the flyer moved: (\(b.x), \(b.y))")
        let still: Bool = b.state == .approach && b.flower == f.id
        try expect(!still, "seed \(seed): the flyer still approaches the bloom across the gap after the relayout")
    }
}

/// Steps `w` until `done` holds (at most `seconds`); whether it did.
private func stepUntil(_ w: MeadowWorld, seconds: Double, _ done: () -> Bool) -> Bool {
    for _ in 0..<Int(seconds * 60) {
        w.step(tick)
        if done() { return true }
    }
    return false
}

private func answering(_ w: MeadowWorld) -> Bool { w.flies.contains { $0.goal == .cursor || $0.state == .cursor } }
private func perched(_ w: MeadowWorld) -> Bool { w.flies.contains { $0.state == .cursor } }

/// Re-check, finding 8: a pointer held still on a screen draws a butterfly; a move of under 2.5 pt that takes the
/// pointer off the terrain (into a gap, or past a real edge) ends its approach at once, and sends off one perched.
private func meadowPointerOffTheTerrainEndsTheLanding() throws {
    let cases: [(Terrain, Double, Double, Double, String)] = [(wideGap, 1439.6, 430, 1441.5, "into the gap"),
                                                              (oneScreen, 1439.1, 450, 1441.0, "past the real edge")]
    for (t, x0, y0, x1, where_) in cases {
        var approaches = 0, perches = 0
        for seed: Int32 in [5, 6, 7] {
            let a = MeadowWorld(terrain: t, cell: cell13, seed: seed)
            a.pointerMoved(x: x0, y: y0)
            if stepUntil(a, seconds: 40, { answering(a) && !perched(a) }) {
                approaches += 1
                a.pointerMoved(x: x1, y: y0)
                try expect(!answering(a), "seed \(seed): a move of \(x1 - x0) pt \(where_) leaves the approach on")
                let came: Bool = stepUntil(a, seconds: 10, { perched(a) })
                try expect(!came, "seed \(seed): a butterfly perched for a pointer \(where_)")
            }
            let p = MeadowWorld(terrain: t, cell: cell13, seed: seed)
            p.pointerMoved(x: x0, y: y0)
            if stepUntil(p, seconds: 60, { perched(p) }) {
                perches += 1
                p.pointerMoved(x: x1, y: y0)
                try expect(!perched(p), "seed \(seed): a move of \(x1 - x0) pt \(where_) leaves the sitter on")
            }
        }
        try expect(approaches >= 2 && perches >= 2, "\(where_): only \(approaches) approaches and \(perches) perches to test")
    }
}

/// Re-check, what is missing: once warm, the steps after a count change allocate nothing while the newcomers wait,
/// fly in from the edges and settle (the entering test reads the distance to the nearest real edge).
private func meadowArrivalsAllocateNothing() throws {
    let w = MeadowWorld(terrain: deskPair, cell: cell13, seed: 14)
    for _ in 0..<600 { w.step(tick) }
    w.tuning.count = 12
    w.syncFlies()
    var arrived = false
    guard let n = allocations({
        for _ in 0..<(20 * 60) { w.step(tick) }
    }) else {
        print("  (allocator not watchable here: skipped)")
        return
    }
    arrived = w.flies.filter { !$0.leaving }.count == 12 && !w.flies.contains { $0.entering || $0.wait > 0 }
    try expect(arrived, "the newcomers did not all arrive in 20 s")
    try expect(n == 0, "\(n) allocations in the 20 s after the count went from 7 to 12")
    // And back down: the leavers go without allocating either.
    w.tuning.count = 7
    w.syncFlies()
    let m = allocations({ for _ in 0..<(20 * 60) { w.step(tick) } }) ?? 0
    try expect(m == 0, "\(m) allocations in the 20 s after the count went from 12 to 7")
}

/// How many butterflies sit on each screen of `t`.
private func perScreen(_ w: MeadowWorld, _ t: Terrain) -> [Int] {
    var n = [Int](repeating: 0, count: t.rects.count)
    for b in w.flies {
        for (i, r) in t.rects.enumerated() where b.x >= Double(r.minX) && b.x <= Double(r.maxX) && b.y >= Double(r.minY) && b.y <= Double(r.maxY) {
            n[i] += 1
            break
        }
    }
    return n
}

/// Re-check, flight judgement: on screens no butterfly can fly between (a real gap), every screen starts with
/// butterflies when the count allows (area seeding left one empty for 4 of 400 seeds on the hairline pair; seed 38
/// stayed empty for ten minutes); with fewer butterflies than such screens, no screen gets two while one is empty.
private func meadowNoDisplayStartsEmpty() throws {
    let layouts: [(Terrain, Int32, String)] = [(hairline, 400, "hairline pair"), (wideGap, 100, "40 pt pair"), (threeApart, 100, "three apart")]
    for (t, seeds, name) in layouts {
        for seed: Int32 in 0..<seeds {
            let w = MeadowWorld(terrain: t, cell: cell13, seed: seed)
            let n = perScreen(w, t)
            try expect(!n.contains(0) && n.reduce(0, +) == w.flies.count, "\(name), seed \(seed): butterflies per screen \(n) of \(w.flies.count)")
        }
    }
    var few = MeadowTuning.director
    few.count = 2
    for seed: Int32 in 0..<50 {
        let w = MeadowWorld(terrain: threeApart, cell: cell13, tuning: few, seed: seed)
        let n = perScreen(w, threeApart)
        try expect(n.max() == 1 && n.reduce(0, +) == 2, "three apart, count 2, seed \(seed): butterflies per screen \(n)")
    }
}
