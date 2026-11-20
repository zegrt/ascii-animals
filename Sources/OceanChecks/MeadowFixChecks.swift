import CoreGraphics
import Foundation
@_spi(Checks) import OceanKit
import simd

// mp's fix round 1: the review's probes, kept as checks so each finding would have been caught. Several screens
// (narrow and wide gaps, offset pairs, a count change, an unplug at the old seam, a pointer held between screens),
// allocations after clicks through the fade and cache eviction, each screen's recordings when paints alternate, a
// burst of clicks with no step between, bad terrain and the tool's numbers.

private let tick: Double = 1.0 / 60.0
private let cell13 = CGSize(width: 13, height: 19)
private let darkTheme: ThemeParams = ThemeParams.make(Settings.defaults, systemIsDark: true, accent: .zero)

/// Two 1440 x 900 screens one point apart, the right one 2 pt lower (the review's finding 2).
private let hairline = Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1441, y: 2, width: 1440, height: 900)])
/// Two 1440 x 900 screens 40 pt apart (findings 3 and 8).
private let wideGap = Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1480, y: 0, width: 1440, height: 900)])
/// Two 1440 x 900 screens 320 pt apart, the right one 2 pt lower (finding 3's newcomer).
private let farGap = Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1760, y: 2, width: 1440, height: 900)])
private let oneScreen = Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900)])
private let twoTouching = Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1440, height: 900)])
private let deskPair = Terrain(rects: [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1800, height: 1169)])

func meadowFixChecks() {
    check("meadowWaysAndStepsNeverCrossAGap", meadowWaysAndStepsNeverCrossAGap)
    check("meadowEntriesAndExitsAvoidGaps", meadowEntriesAndExitsAvoidGaps)
    check("meadowRelayoutPutsTheDisplacedOnAScreen", meadowRelayoutPutsTheDisplacedOnAScreen)
    check("meadowBadTerrainHoldsStill", meadowBadTerrainHoldsStill)
    check("meadowPointerInAGapIsNotLandedOn", meadowPointerInAGapIsNotLandedOn)
    check("meadowFlowersOutliveTheirWorld", meadowFlowersOutliveTheirWorld)
    check("meadowFadingFlowersBounded", meadowFadingFlowersBounded)
    check("meadowRecordingsBoundedOnEveryScreen", meadowRecordingsBoundedOnEveryScreen)
    check("meadowClicksAllocateNothingLater", meadowClicksAllocateNothingLater)
    check("meadowToolRefusesBadNumbers", meadowToolRefusesBadNumbers)
}

// ── the check's own geometry (independent of the world's) ──

private func onScreens(_ t: Terrain, _ x: Double, _ y: Double) -> Bool {
    for r in t.rects where x >= Double(r.minX) && x <= Double(r.maxX) && y >= Double(r.minY) && y <= Double(r.maxY) { return true }
    return false
}

/// Off every screen, with a screen on each side of it, level with it.
private func inGap(_ t: Terrain, _ x: Double, _ y: Double) -> Bool {
    if onScreens(t, x, y) { return false }
    var l = false, r = false, a = false, b = false
    for s in t.rects {
        if y >= Double(s.minY) && y <= Double(s.maxY) {
            if Double(s.maxX) <= x { l = true }
            if Double(s.minX) >= x { r = true }
        }
        if x >= Double(s.minX) && x <= Double(s.maxX) {
            if Double(s.maxY) <= y { a = true }
            if Double(s.minY) >= y { b = true }
        }
    }
    return (l && r) || (a && b)
}

/// Whether the segment passes through a gap: sampled every 0.05 pt (the gaps here are 1 pt or wider).
private func crossesGap(_ t: Terrain, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Bool {
    let len: Double = hypot(bx - ax, by - ay)
    let n = max(2, Int((len / 0.05).rounded(.up)))
    for i in 0...n {
        let k: Double = Double(i) / Double(n)
        if inGap(t, ax + (bx - ax) * k, ay + (by - ay) * k) { return true }
    }
    return false
}

private func spanOf(_ w: MeadowWorld, _ b: Butterfly) -> Double { b.sp.span * 13 * w.breeze.unit * b.size * 0.6 }

private func allFinite(_ w: MeadowWorld) -> Bool {
    for b in w.flies where !(b.x.isFinite && b.y.isFinite && b.z.isFinite && b.heading.isFinite) { return false }
    for f in w.flowers.all where !(f.x.isFinite && f.y.isFinite && f.ox.isFinite && f.oy.isFinite) { return false }
    return true
}

/// Steps `w` for `seconds`; every step, every butterfly's way from where it was must cross no gap.
private func runWatchingGaps(_ w: MeadowWorld, _ t: Terrain, seconds: Double, _ what: String) throws {
    var last: [Int: (Double, Double)] = [:]
    for b in w.flies { last[b.id] = (b.x, b.y) }
    for s in 0..<Int(seconds * 60) {
        w.step(tick)
        for b in w.flies {
            if inGap(t, b.x, b.y) { throw CheckFailure(detail: "\(what): butterfly \(b.id) in a gap at (\(b.x), \(b.y)), step \(s)") }
            if let (px, py) = last[b.id], crossesGap(t, px, py, b.x, b.y) {
                throw CheckFailure(detail: "\(what): butterfly \(b.id) went through a gap from (\(px), \(py)) to (\(b.x), \(b.y)), step \(s)")
            }
            last[b.id] = (b.x, b.y)
        }
    }
}

/// Finding 2: a straight way across a one-point gap is not open; a flight step, a landed pull and an approach toward
/// the other screen don't go through it; ten minutes on the hairline pair never go through the gap, step by step;
/// and on the owner's desk (touching, offset) butterflies really cross between the screens (not just start there).
private func meadowWaysAndStepsNeverCrossAGap() throws {
    let w = MeadowWorld(terrain: hairline, cell: cell13, seed: 3)
    try expect(!w.wayOpen(840, 400, 2040, 400), "the way across the one-point gap counts as open")
    try expect(w.segmentEntersGap(1439.5, 400, 1444.63, 400), "the step across the gap is not seen")
    try expect(w.wayOpen(840, 400, 1400, 600) && !w.segmentEntersGap(840, 400, 1400, 600), "a way on one screen is refused")

    // A controlled flight step from the left screen's edge straight at the right screen.
    guard let b = w.flies.first else { throw CheckFailure(detail: "no butterflies") }
    for vx in [300.0, 600.0, 1200.0] {
        w.probeFly(b, x: 1439.5, y: 400, vx: vx, vy: 0)
        for _ in 0..<30 {
            let px = b.x, py = b.y
            w.probeStep(b)
            try expect(!crossesGap(hairline, px, py, b.x, b.y), "a flight step went from (\(px), \(py)) through the gap to (\(b.x), \(b.y))")
        }
    }
    // A landed pull: on a bloom just across the gap, sitting on this side.
    let f = w.flowers.make(.daisy, x: 1442.5, y: 400, grown: true, rng: MeadowRandom(7))
    w.flowers.showOnly([f])
    w.probeLand(b, x: 1439.0, y: 400, onFlower: f.id)
    for _ in 0..<120 {
        let px = b.x, py = b.y
        w.probeStep(b)
        try expect(!crossesGap(hairline, px, py, b.x, b.y), "a landed pull went from (\(px), \(py)) through the gap to (\(b.x), \(b.y))")
    }
    // An approach and its settling pull toward the same bloom from this side.
    w.probeApproach(b, x: 1439.0, y: 401, flower: f.id)
    for _ in 0..<120 {
        let px = b.x, py = b.y
        w.probeStep(b)
        try expect(!crossesGap(hairline, px, py, b.x, b.y), "a step went from (\(px), \(py)) through the gap to (\(b.x), \(b.y))")
    }

    // Ten minutes on the hairline pair: everyone's every step.
    try runWatchingGaps(MeadowWorld(terrain: hairline, cell: cell13, seed: 3), hairline, seconds: 600, "hairline pair")

    // Five minutes on the desk: count the times a butterfly goes from one screen to the other.
    let desk = MeadowWorld(terrain: deskPair, cell: cell13, seed: 3)
    var side: [Int: Int] = [:]
    var crossings = 0
    for _ in 0..<(5 * 60 * 60) {
        desk.step(tick)
        for b in desk.flies {
            let k: Int = b.y < 1440 && onScreens(deskPair, b.x, b.y) ? 0 : b.y > 1440 && onScreens(deskPair, b.x, b.y) ? 1 : -1
            if k >= 0 {
                if let was = side[b.id], was != k { crossings += 1 }
                side[b.id] = k
            }
        }
    }
    print("  desk: \(crossings) crossings between the screens in 5 minutes")
    try expect(crossings >= 3, "only \(crossings) crossings between the desk's screens in five minutes")
}

/// Finding 3: twelve where there were seven on a wide-gap pair: no newcomer waits or comes in through the gap; a
/// departure beside a 40 pt gap leaves the desk (is gone within two minutes) without entering it.
private func meadowEntriesAndExitsAvoidGaps() throws {
    let w = MeadowWorld(terrain: farGap, cell: cell13, seed: 1)
    w.tuning.count = 12
    w.syncFlies()
    for b in w.flies {
        try expect(!inGap(farGap, b.x, b.y), "newcomer \(b.id) put in the gap at (\(b.x), \(b.y))")
        if b.wait > 0 || b.entering { try expect(!onScreens(farGap, b.x, b.y), "newcomer \(b.id) appears on a screen") }
    }
    try runWatchingGaps(w, farGap, seconds: 60, "count 7 → 12")
    try expect(w.flies.count == 12, "count \(w.flies.count)")

    for seed: Int32 in [1, 2, 3] {
        let d = MeadowWorld(terrain: wideGap, cell: cell13, seed: seed)
        guard let b = d.flies.first else { throw CheckFailure(detail: "no butterflies") }
        d.probeFly(b, x: 1439, y: 450, vx: 1, vy: 0)
        d.probeSendAway(b)
        var gone = false
        var last = (b.x, b.y)
        for s in 0..<(120 * 60) {
            d.step(tick)
            if !d.flies.contains(where: { $0 === b }) { gone = true; break }
            try expect(!crossesGap(wideGap, last.0, last.1, b.x, b.y), "seed \(seed): the departure went through the gap at step \(s)")
            last = (b.x, b.y)
        }
        try expect(gone, "seed \(seed): the departure is still on the desk after two minutes, at (\(b.x), \(b.y)) aiming off the desk")
    }
}

/// Finding 4: one screen to two and back (an unplug at the old seam), offsets, gaps and a count change; right after
/// each layout, everyone who was on a screen is on one, nobody is in a gap, those waiting to come in wait just past a
/// real edge of the new screens, and the count is kept.
private func meadowRelayoutPutsTheDisplacedOnAScreen() throws {
    // The review's case: a flyer one point onto the right screen when it is unplugged.
    let w = MeadowWorld(terrain: oneScreen, cell: cell13, seed: 2)
    w.layout(terrain: twoTouching, cell: cell13)
    guard let b = w.flies.first else { throw CheckFailure(detail: "no butterflies") }
    w.probeFly(b, x: 1441, y: 450, vx: 100, vy: 0)
    w.layout(terrain: oneScreen, cell: cell13)
    try expect(onScreens(oneScreen, b.x, b.y), "after the unplug the flyer is at (\(b.x), \(b.y)), off the remaining screen")

    // Many layouts in a row, with a count change in the middle: strict after every one.
    let layouts: [Terrain] = [deskPair, oneScreen, wideGap, hairline, twoTouching, farGap, deskPair, oneScreen]
    let m = MeadowWorld(terrain: deskPair, cell: cell13, seed: 21)
    var now = deskPair
    for round in 0..<48 {
        for _ in 0..<(37 + round * 11) { m.step(tick) }
        if round == 20 { m.tuning.count = 12; m.syncFlies() }
        if round == 34 { m.tuning.count = 5; m.syncFlies() }
        let next = layouts[round % layouts.count]
        var was: [Int: Bool] = [:]
        for b in m.flies { was[b.id] = onScreens(now, b.x, b.y) }
        m.layout(terrain: next, cell: cell13)
        now = next
        let want = round >= 34 ? 5 : round >= 20 ? 12 : 7
        try expect(allFinite(m), "round \(round): not finite")
        for b in m.flies {
            try expect(!inGap(next, b.x, b.y), "round \(round): butterfly \(b.id) in a gap at (\(b.x), \(b.y))")
            if b.leaving { continue }
            if b.wait > 0 || b.entering {
                if !onScreens(next, b.x, b.y) {
                    let reach: Double = b.sp.span * 13 * m.breeze.unit * b.size * m.depthScale(b.z) * 0.575 + 2 * 13 + 20 * m.breeze.unit
                    try expect(next.signedOutside(SIMD2(b.x, b.y)) <= reach + 1e-6,
                               "round \(round): newcomer \(b.id) waits \(next.signedOutside(SIMD2(b.x, b.y))) pt off the screens")
                }
                continue
            }
            if was[b.id] == true || b.landed {
                try expect(onScreens(next, b.x, b.y) || b.state == .cursor,
                           "round \(round): butterfly \(b.id) was on a screen and is now at (\(b.x), \(b.y)), off them")
            } else {
                try expect(next.signedOutside(SIMD2(b.x, b.y)) <= 0.25 * spanOf(m, b) + 1e-6,
                           "round \(round): butterfly \(b.id) \(next.signedOutside(SIMD2(b.x, b.y))) pt off the screens")
            }
        }
        // The count: leavers go, newcomers come, settling within a minute.
        if round % 8 == 7 {
            try runWatchingGaps(m, next, seconds: 60, "round \(round)")
            let active = m.flies.filter { !$0.leaving }.count
            try expect(active == want, "round \(round): \(active) butterflies staying, want \(want)")
        }
    }
}

/// Finding 7: two 1e-10 pt screens (no usable edges) with the count raised, and a screen whose far edge overflows:
/// nothing traps, nothing goes non-finite, and the butterflies hold still until a usable layout comes.
private func meadowBadTerrainHoldsStill() throws {
    let tiny = Terrain(rects: [CGRect(x: 0, y: 0, width: 1e-10, height: 1e-10), CGRect(x: 10, y: 10, width: 1e-10, height: 1e-10)])
    let a = MeadowWorld(terrain: tiny, cell: cell13, seed: 1)
    a.tuning.count = 12
    a.syncFlies()
    for _ in 0..<60 { a.step(tick) }
    try expect(allFinite(a), "not finite on 1e-10 pt screens")
    let huge = Terrain(rects: [CGRect(x: 1.5e308, y: 0, width: 1e308, height: 900)])
    let b = MeadowWorld(terrain: huge, cell: cell13, seed: 1)
    for _ in 0..<60 { b.step(tick) }
    try expect(allFinite(b), "not finite on a screen whose far edge overflows")
    // From a good layout into each bad one and back.
    let c = MeadowWorld(terrain: oneScreen, cell: cell13, seed: 1)
    for t in [tiny, huge, Terrain(rects: [CGRect(x: -2e7, y: 0, width: 1440, height: 900)]), oneScreen] {
        c.layout(terrain: t, cell: cell13)
        c.tuning.count = 9
        c.syncFlies()
        for _ in 0..<120 { c.step(tick) }
        try expect(allFinite(c), "not finite after a layout to \(t.rects)")
    }
    try expect(c.flies.count == 9 && c.flowers.all.count > 0, "the meadow did not come back on a usable screen: \(c.flies.count) butterflies")
}

/// Finding 8: a pointer held still off the screens, in the gap between two or just past a real edge, is never landed
/// on (the review's case first: seed 5, the pointer in the 40 pt gap from the start).
private func meadowPointerInAGapIsNotLandedOn() throws {
    let cases: [(Terrain, Double, Double, String)] = [(wideGap, 1442, 430, "in the gap"), (wideGap, 720, -6, "above the left screen"),
                                                     (wideGap, 2930, 450, "right of the right screen"), (oneScreen, -6, 450, "left of one screen")]
    for (t, px, py, where_) in cases {
        for seed: Int32 in [5, 6, 7] {
            let w = MeadowWorld(terrain: t, cell: cell13, seed: seed)
            w.pointerMoved(x: px, y: py)
            for s in 0..<(30 * 60) {
                w.step(tick)
                for b in w.flies where b.goal == .cursor || b.state == .cursor {
                    throw CheckFailure(detail: "seed \(seed): butterfly \(b.id) answers a pointer \(where_) after \(Double(s) / 60) s")
                }
            }
        }
    }
}

/// Finding 9: `Flowers` kept past its world: a replant, a touch and closes over the click limit don't crash.
private func meadowFlowersOutliveTheirWorld() throws {
    func orphan() -> Flowers { MeadowWorld(terrain: oneScreen, cell: cell13, seed: 4).flowers }
    let f = orphan()
    let rng = MeadowRandom(1)
    f.replant(fresh: false, rng: rng)
    if let first = f.all.first { _ = f.click(x: first.x, y: first.y, rng: rng) }
    for k in 0..<40 { _ = f.click(x: 30 + Double(k % 8) * 170, y: 40 + Double(k / 8) * 170, rng: rng) }
    f.relayout(terrain: twoTouching, cell: cell13, rng: rng)
    f.step()
    try expect(!f.all.isEmpty, "the orphaned flowers are gone")
}

/// Open spots: points at least `room` from every flower, on a grid over the screen.
private func openSpots(_ w: MeadowWorld, _ t: Terrain, room: Double) -> [(Double, Double)] {
    var out: [(Double, Double)] = []
    for r in t.rects {
        for gx in stride(from: Double(r.minX) + 60, to: Double(r.maxX) - 60, by: 37) {
            for gy in stride(from: Double(r.minY) + 60, to: Double(r.maxY) - 60, by: 41) {
                var ok = true
                for f in w.flowers.all where hypot(f.x - gx, f.y - gy) < room { ok = false; break }
                for o in out where hypot(o.0 - gx, o.1 - gy) < room { ok = false; break }
                if ok { out.append((gx, gy)) }
            }
        }
    }
    return out
}

/// Finding 10: with the click limit at one, 2,000 clicks alternating between two open spots before the next step
/// keep at most `Clicks.fadingMost` fading (the review's probe kept 2,000), and the flowers never pass `most`.
private func meadowFadingFlowersBounded() throws {
    let w = MeadowWorld(terrain: oneScreen, cell: cell13, seed: 12)
    w.tuning.clickLimit = 1
    for _ in 0..<60 { w.step(tick) }
    // Two open spots: the planted flowers cleared, the spots far apart.
    w.flowers.showOnly([])
    let spots = [(300.0, 450.0), (1100.0, 450.0)]
    let most = w.flowers.most
    var bloomed = 0
    for k in 0..<2000 {
        let (x, y) = spots[k % 2]
        if case .bloomed = w.flowers.click(x: x, y: y, rng: MeadowRandom(Int32(k))) { bloomed += 1 }
        try expect(w.flowers.fadingCount <= MeadowTuning.Clicks.fadingMost, "\(w.flowers.fadingCount) fading after \(k + 1) clicks")
        try expect(w.flowers.all.count <= most, "\(w.flowers.all.count) flowers after \(k + 1) clicks, bound \(most)")
    }
    try expect(bloomed == 2000, "only \(bloomed) of the clicks bloomed")
    for _ in 0..<150 { w.step(tick) }
    try expect(w.flowers.fadingCount == 0 && w.flowers.clickedOpen == 1, "after the fade: \(w.flowers.fadingCount) fading")
}

/// Finding 1: two screens painted in turn while clicks bloom and fade on both: each screen's recordings stay within
/// the flower bound throughout, and once the clicks stop, neither keeps recordings of flowers that have gone.
private func meadowRecordingsBoundedOnEveryScreen() throws {
    let t = twoTouching
    let w = MeadowWorld(terrain: t, cell: cell13, seed: 30)
    let painter = MeadowPainter()
    let vs = t.rects.map { r -> (CGRect, GridSpec, CellCanvas) in
        let g = GridSpec.make(viewportSize: r.size, cell: cell13)
        return (r, g, CellCanvas(cols: g.cols, rows: g.rows))
    }
    let spots = openSpots(w, t, room: 90)
    guard spots.count >= 8 else { throw CheckFailure(detail: "too few open spots") }
    var worst = 0
    for f in 0..<4000 {
        if f < 3000 && f % 3 == 0 {
            let (x, y) = spots[(f / 3 * 7) % spots.count]
            w.pointerDown(x: x, y: y)
        }
        w.step(tick)
        for (r, g, c) in vs { c.clear(); painter.paint(w, viewport: r, grid: g, theme: darkTheme, into: c) }
        for (k, p) in painter.probeFlowerCaches(w).enumerated() {
            worst = max(worst, p.cached)
            try expect(p.slots <= w.flowers.most && p.cached <= p.slots,
                       "frame \(f), screen \(k): \(p.slots) slots, \(p.cached) recordings, bound \(w.flowers.most)")
        }
    }
    for (k, p) in painter.probeFlowerCaches(w).enumerated() {
        try expect(p.stale == 0, "screen \(k) still holds \(p.stale) recordings of flowers that have gone (of \(p.cached))")
    }
    print("  most recordings on one screen: \(worst), bound \(w.flowers.most)")
}

/// Finding 5: once warm, frames after clicks allocate nothing: the bloom, its growth, the fade and the eviction of
/// its recording, on both screens; and the clicks themselves allocate nothing either.
private func meadowClicksAllocateNothingLater() throws {
    let t = deskPair
    let w = MeadowWorld(terrain: t, cell: cell13, seed: 31)
    let painter = MeadowPainter()
    let vs = t.rects.map { r -> (CGRect, GridSpec, CellCanvas) in
        let g = GridSpec.make(viewportSize: r.size, cell: cell13)
        return (r, g, CellCanvas(cols: g.cols, rows: g.rows))
    }
    let spots = openSpots(w, t, room: 90)
    guard spots.count >= 8 else { throw CheckFailure(detail: "too few open spots") }
    var clicks = 0
    func click(_ f: Int) {
        let (x, y) = spots[(f * 7) % spots.count]
        w.pointerDown(x: x, y: y)
        clicks += 1
    }
    func frame() {
        for _ in 0..<2 { w.step(tick) }
        for (r, g, c) in vs { c.clear(); painter.paint(w, viewport: r, grid: g, theme: darkTheme, into: c) }
    }
    // Warm: clicks every 20 frames for 1,500 frames (blooms, fades, evictions, the slots filled).
    for f in 0..<1500 { if f % 20 == 0 { click(f) }; frame() }
    var framesAfter = 0, inClicks = 0
    _ = allocationSites()
    for round in 0..<12 {
        guard let n = allocations({ click(1500 + round) }) else {
            print("  (allocator not watchable here: skipped)")
            return
        }
        inClicks += n
        // The 150 frames after it: the bloom grows, the one it closed fades and goes, its recording is handed back.
        framesAfter += allocations({ for _ in 0..<150 { frame() } }) ?? 0
    }
    print("  12 clicks: \(inClicks) allocations in the clicks, \(framesAfter) in the 1,800 frames after them")
    if framesAfter + inClicks > 0 { print("  where: \(allocationSites())") }
    try expect(framesAfter == 0, "\(framesAfter) allocations in the frames after clicks")
    try expect(inClicks == 0, "\(inClicks) allocations in the clicks themselves")
}

/// Finding 6: the tool's numbers: each value the review found trapping is refused, the usual ones pass.
private func meadowToolRefusesBadNumbers() throws {
    let size = CGSize(width: 340, height: 150)
    let desk = CGSize(width: 2560, height: 2609)
    let badSizes: [String] = ["nanx150", "340xinf", "0x150", "1e300x150", "340", "x"]
    for t in badSizes { try expect(ToolInput.size(t) == nil, "size \(t) passes") }
    let goodSize: CGSize? = ToolInput.size("340x150")
    try expect(goodSize == size && ToolInput.size("7680x4320") != nil, "a good size is refused")
    let badScales: [String] = ["nan", "inf", "0", "-1", "1e300", "1e-300", "x"]
    for t in badScales { try expect(ToolInput.scale(t, for: size) == nil, "--scale \(t) passes") }
    let two: CGFloat? = ToolInput.scale("2", for: size)
    let half: CGFloat? = ToolInput.scale("0.5", for: desk)
    try expect(two == 2 && half == 0.5, "a good scale is refused")
    let badSeconds: [String] = ["nan", "inf", "-1", "1e300", "x"]
    for t in badSeconds { try expect(ToolInput.seconds(t) == nil, "--seconds \(t) passes") }
    try expect(ToolInput.seconds("30") == 30 && ToolInput.seconds("0") == 0, "good seconds refused")
    let badFps: [String] = ["0", "-15", "7", "1e3", "x"]
    for t in badFps { try expect(ToolInput.fps(t) == nil, "--fps \(t) passes") }
    let goodFps: [Int] = [1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60]
    for f in goodFps { try expect(ToolInput.fps(String(f)) == f, "--fps \(f) refused") }
    try expect(ToolInput.unit("nan") == nil && ToolInput.unit("1.5") == nil, "a bad --z passes")
    try expect(ToolInput.unit("0.5") == 0.5, "--z 0.5 refused")
    try expect(ToolInput.count("0") == nil && ToolInput.count("900") == 900, "--frames")
}
