import CoreGraphics
import Foundation
import OceanKit
import simd

// The Meadow's world and painter (task mp): only what can hurt. Fidelity to the sketch is judged by eye on films
// next to it; these hold the safety rules: finite and sane, nothing allocated per frame, most in the air at the
// director's settings, several screens, the tiny viewport, the same meadow for a seed, the pointer, and the CPU budget
// against Web.

private let tick: Double = 1.0 / 60.0
private let cell13 = CGSize(width: 13, height: 19)
/// The owner's desk: a 2560 x 1440 monitor above the 1800 x 1169 laptop, offset 375 pt (as `bench --desk`).
private let desk = Terrain(rects: [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1800, height: 1169)])
/// Two screens side by side with a gap between them (the gap a butterfly must never enter).
private let gapped = Terrain(rects: [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1600, y: 100, width: 1440, height: 900)])

func meadowWorldChecks() {
    check("meadowLongRunStaysSane", meadowLongRunStaysSane)
    check("meadowWorldFiniteOnBadInput", meadowWorldFiniteOnBadInput)
    check("meadowFrameAllocatesNothing", meadowFrameAllocatesNothing)
    check("meadowMostlyInTheAir", meadowMostlyInTheAir)
    check("meadowNothingInAGap", meadowNothingInAGap)
    check("meadowRelayoutKeepsEveryoneOnAScreen", meadowRelayoutKeepsEveryoneOnAScreen)
    check("meadowTinyViewport", meadowTinyViewport)
    check("meadowSameSeedSameFrames", meadowSameSeedSameFrames)
    check("meadowStillPointerIsLandedOn", meadowStillPointerIsLandedOn)
    check("meadowClicksCallOneAtATime", meadowClicksCallOneAtATime)
    check("meadowWithinWebsCPU", meadowWithinWebsCPU)
}

/// The span the flight's distances use (the sketch's `spanRef`).
private func spanRef(_ w: MeadowWorld, _ b: Butterfly) -> Double { b.sp.span * 13 * w.breeze.unit * b.size * 0.6 }

private func finite(_ w: MeadowWorld) -> Bool {
    for b in w.flies {
        for v in [b.x, b.y, b.z, b.heading, b.stroke, b.vx, b.vy, b.bank, b.phase] where !v.isFinite { return false }
        if b.z < 0 || b.z > 1 { return false }
    }
    for f in w.flowers.all where !(f.ox.isFinite && f.oy.isFinite) { return false }
    for d in w.dust where !(d.x.isFinite && d.y.isFinite) { return false }
    return true
}

/// In a gap: off every screen, with a screen on each side of it, level with it.
private func inGap(_ t: Terrain, _ p: SIMD2<Double>) -> Bool {
    if t.contains(p) { return false }
    var l = false, r = false, a = false, b = false
    for s in t.rects {
        if p.y >= Double(s.minY) && p.y <= Double(s.maxY) {
            if Double(s.maxX) <= p.x { l = true }
            if Double(s.minX) >= p.x { r = true }
        }
        if p.x >= Double(s.minX) && p.x <= Double(s.maxX) {
            if Double(s.maxY) <= p.y { a = true }
            if Double(s.minY) >= p.y { b = true }
        }
    }
    return (l && r) || (a && b)
}

private func paintAll(_ painter: MeadowPainter, _ w: MeadowWorld, _ views: [(CGRect, GridSpec, CellCanvas)], _ theme: ThemeParams) {
    for (rect, grid, canvas) in views {
        canvas.clear()
        painter.paint(w, viewport: rect, grid: grid, theme: theme, into: canvas)
    }
}

private func views(_ t: Terrain, _ cell: CGSize) -> [(CGRect, GridSpec, CellCanvas)] {
    t.rects.map { r in
        let g = GridSpec.make(viewportSize: r.size, cell: cell)
        return (r, g, CellCanvas(cols: g.cols, rows: g.rows))
    }
}

private let dark: ThemeParams = ThemeParams.make(Settings.defaults, systemIsDark: true, accent: .zero)
private let paperCalm: ThemeParams = {
    var s = Settings.defaults
    s.appearance = .light
    s.calm = true
    return ThemeParams.make(s, systemIsDark: true, accent: .zero)
}()

/// 30 minutes on the desk: everyone finite, height in 0…1, the count kept, nobody lost far off the screens, painted
/// now and then in dark and on paper.
private func meadowLongRunStaysSane() throws {
    let w = MeadowWorld(terrain: desk, cell: cell13, seed: 9)
    let painter = MeadowPainter()
    let vs = views(desk, cell13)
    var worstOff = 0.0
    for s in 1...(30 * 60 * 60) {
        w.step(tick)
        if s % 600 == 0 {
            try expect(finite(w), "not finite at \(Double(s) / 60) s")
            try expect(w.flies.count == 7, "count \(w.flies.count) at \(Double(s) / 60) s")
            paintAll(painter, w, vs, s % 1200 == 0 ? dark : paperCalm)
        }
        if s % 10 == 0 {
            for b in w.flies where b.wait <= 0 && !b.leaving {
                worstOff = max(worstOff, desk.signedOutside(SIMD2(b.x, b.y)) / spanRef(w, b))
            }
        }
    }
    // The sketch steers back a quarter span past a real edge; at full speed the turn carries it further, most of all
    // after a take-off with the escape boost into the pocket right of the laptop and below the monitor. Fix round 1:
    // the bound was 2, which only seed 9 met (at 3134721, seeds 1-10 reach up to 3.70 spans; after the fixes, 2.92).
    try expect(worstOff < 4, "a butterfly went \(worstOff) spans off the screens")
}

/// NaN and huge numbers into every entry point, broken screens and cells: nothing breaks and everything stays finite.
private func meadowWorldFiniteOnBadInput() throws {
    let bad: [Double] = [.nan, .infinity, -.infinity, 1e300, -1e300]
    let w = MeadowWorld(terrain: .single(width: 1440, height: 900), cell: cell13, seed: 3)
    for v in bad {
        w.pointerMoved(x: v, y: 400)
        w.pointerMoved(x: 400, y: v)
        w.pointerDown(x: v, y: v)
        w.step(tick)
        w.pointerLeft()
        w.step(Double.nan)
        w.step(1)
    }
    for _ in 0..<600 { w.step(tick) }
    try expect(finite(w), "not finite after bad pointer input")
    let painter = MeadowPainter()
    for (t, c) in [(Terrain(rects: []), cell13), (.single(width: 0, height: 0), cell13), (.single(width: 1, height: 5000), cell13),
                   (.single(width: 1440, height: 900), CGSize(width: 0, height: 0)),
                   (.single(width: 1440, height: 900), CGSize(width: Double.nan, height: 19))] {
        w.layout(terrain: t, cell: c)
        for _ in 0..<120 { w.step(tick) }
        try expect(finite(w), "not finite on \(t.rects) cell \(c)")
        if let r = t.rects.first, r.width >= 1, r.height >= 1, c.width.isFinite, c.width > 0 {
            let g = GridSpec.make(viewportSize: r.size, cell: c)
            let canvas = CellCanvas(cols: g.cols, rows: g.rows)
            painter.paint(w, viewport: r, grid: g, theme: dark, into: canvas)
        }
    }
    let fresh = MeadowWorld(terrain: Terrain(rects: []), cell: cell13, seed: 1)
    for _ in 0..<60 { fresh.step(tick) }
    try expect(fresh.flies.isEmpty && finite(fresh), "an empty terrain made butterflies")
}

/// Once warm, a frame (four steps and both screens painted, the pointer moving) allocates nothing, in dark and on
/// paper with Calm.
private func meadowFrameAllocatesNothing() throws {
    let w = MeadowWorld(terrain: desk, cell: cell13, seed: 5)
    let painter = MeadowPainter()
    let vs = views(desk, cell13)
    func frame(_ f: Int, _ theme: ThemeParams) {
        for k in 0..<4 {
            let t = Double(f * 4 + k) * tick
            w.pointerMoved(x: 1200 + 300 * cos(t), y: 700 + 200 * sin(t))
            w.step(tick)
        }
        paintAll(painter, w, vs, theme)
    }
    // Warm in each theme, then measure in it (a theme change rebuilds a screen's caches once, as a new screen does).
    for theme in [dark, paperCalm] {
        for f in 0..<600 { frame(f, theme) }
        guard let n = allocations({ for f in 600..<900 { frame(f, theme) } }) else {
            print("  (allocator not watchable here: skipped)")
            return
        }
        try expect(n == 0, "\(n) allocations over 300 warm frames (\(theme.light ? "paper, Calm" : "dark"))")
    }
}

/// At the director's settings most butterflies are in the air (the sketch measures about 75 %).
private func meadowMostlyInTheAir() throws {
    var air = 0, all = 0
    for seed: Int32 in [1, 2, 3, 4] {
        let w = MeadowWorld(terrain: .single(width: 1728, height: 1117), cell: cell13, seed: seed)
        for s in 1...(10 * 60 * 60) {
            w.step(tick)
            if s % 30 == 0 { for b in w.flies { all += 1; if !b.landed { air += 1 } } }
        }
    }
    let share = Double(air) / Double(max(1, all))
    print(String(format: "  in the air %.1f %% of the time", share * 100))
    try expect(share >= 0.65, String(format: "only %.1f %% in the air", share * 100))
}

/// Two screens with a gap between them, ten minutes: no butterfly is ever in the gap, nor goes through it between
/// two steps (the way sampled every 0.5 pt; fix round 1: the end of a step alone was not enough), the flowers stand
/// on the screens, and both screens keep butterflies. (Real crossings between touching screens:
/// `meadowWaysAndStepsNeverCrossAGap`.)
private func meadowNothingInAGap() throws {
    let w = MeadowWorld(terrain: gapped, cell: cell13, seed: 11)
    var last: [Int: SIMD2<Double>] = [:]
    var onRight = 0, onLeft = 0
    for s in 1...(10 * 60 * 60) {
        w.step(tick)
        for b in w.flies {
            let p = SIMD2(b.x, b.y)
            try expect(!inGap(gapped, p), "butterfly \(b.id) in the gap at (\(b.x), \(b.y)), \(Double(s) / 60) s")
            if let q = last[b.id] {
                let n = max(1, Int((simd_length(p - q) / 0.5).rounded(.up)))
                for i in 1..<n {
                    let m = q + (p - q) * (Double(i) / Double(n))
                    try expect(!inGap(gapped, m), "butterfly \(b.id) went through the gap at (\(m.x), \(m.y)), \(Double(s) / 60) s")
                }
            }
            last[b.id] = p
            if s % 600 == 0 { if b.x > 1600 { onRight += 1 } else if b.x < 1440 { onLeft += 1 } }
        }
    }
    for f in w.flowers.all { try expect(!inGap(gapped, SIMD2(f.x, f.y)), "flower \(f.id) in the gap") }
    try expect(onRight > 0 && onLeft > 0, "a screen stayed empty: \(onLeft) on the left, \(onRight) on the right")
}

/// Screens come and go: two to one and back, at many moments; right after each relayout everyone is on a screen (or
/// within a quarter span of one), nobody landed is off them, and the count is kept.
private func meadowRelayoutKeepsEveryoneOnAScreen() throws {
    let one = Terrain(rects: [CGRect(x: 0, y: 0, width: 2560, height: 1440)])
    let w = MeadowWorld(terrain: desk, cell: cell13, seed: 21)
    for round in 0..<40 {
        for _ in 0..<(97 + round * 13) { w.step(tick) }
        let t = round % 2 == 0 ? one : desk
        w.layout(terrain: t, cell: cell13)
        for b in w.flies where b.wait <= 0 && !b.leaving {
            let out = t.signedOutside(SIMD2(b.x, b.y))
            try expect(out <= 0.25 * spanRef(w, b) + 1e-6, "round \(round): butterfly \(b.id) \(out) pt off the screens")
            if b.landed { try expect(t.contains(SIMD2(b.x, b.y)) || b.state == .cursor, "round \(round): landed off the screens") }
        }
        try expect(w.flies.count == 7 && finite(w), "round \(round): count \(w.flies.count)")
    }
}

/// The 340 x 150 viewport (the Settings preview): the meadow lives and paints there, everyone stays near it.
private func meadowTinyViewport() throws {
    let t = Terrain.single(width: 340, height: 150)
    let cell = GridSpec.cell(forWidth: 340)
    let w = MeadowWorld(terrain: t, cell: cell, seed: 4)
    let painter = MeadowPainter()
    let vs = views(t, cell)
    for s in 1...(5 * 60 * 60) {
        w.step(tick)
        if s % 30 == 0 { paintAll(painter, w, vs, s % 60 == 0 ? dark : paperCalm) }
    }
    try expect(finite(w) && w.flies.count == 7, "count \(w.flies.count)")
    var drawn = 0
    for c in vs.map({ $0.2 }) { for g in c.glyph where g != CellCanvas.noGlyph { drawn += 1 } }
    try expect(drawn > 0, "nothing drawn on the tiny viewport")
    for b in w.flies { try expect(t.signedOutside(SIMD2(b.x, b.y)) < 3 * spanRef(w, b), "butterfly \(b.id) lost at (\(b.x), \(b.y))") }
}

/// FNV-1a over a canvas.
private func digest(_ c: CellCanvas, _ h: inout UInt64) {
    func add<T>(_ a: [T]) { a.withUnsafeBytes { for x in $0 { h = (h ^ UInt64(x)) &* 0x100_0000_01b3 } } }
    add(c.block); add(c.ink); add(c.glyph); add(c.ground)
}

/// The same seed gives the same meadow, frame for frame (world and canvases), with the same pointer.
private func meadowSameSeedSameFrames() throws {
    func run(_ seed: Int32) -> UInt64 {
        let w = MeadowWorld(terrain: desk, cell: cell13, seed: seed)
        let painter = MeadowPainter()
        let vs = views(desk, cell13)
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for f in 0..<300 {
            if f == 100 { w.pointerDown(x: 900, y: 600) }
            if f > 120 && f < 160 { w.pointerMoved(x: 600 + Double(f) * 8, y: 900) }
            if f == 160 { w.pointerLeft() }
            for _ in 0..<2 { w.step(tick) }
            if f % 10 == 0 {
                paintAll(painter, w, vs, f % 20 == 0 ? dark : paperCalm)
                for v in vs { digest(v.2, &h) }
                for b in w.flies { h = (h ^ b.x.bitPattern ^ b.z.bitPattern) &* 0x100_0000_01b3 }
            }
        }
        return h
    }
    let a = run(77), b = run(77), c = run(78)
    try expect(a == b, "same seed, different frames")
    try expect(a != c, "different seeds, same frames")
}

/// Hold the pointer still and one comes and sits on it, its whole body on the screen even at a corner; a move
/// sends it off.
private func meadowStillPointerIsLandedOn() throws {
    for (px, py) in [(720.0, 450.0), (6.0, 4.0), (1436.0, 897.0)] {
        let t = Terrain.single(width: 1440, height: 900)
        let w = MeadowWorld(terrain: t, cell: cell13, seed: 8)
        for _ in 0..<120 { w.step(tick) }
        w.pointerMoved(x: px, y: py)
        var sitter: Butterfly? = nil
        for _ in 0..<(40 * 60) {
            w.step(tick)
            if let b = w.flies.first(where: { $0.state == .cursor }) { sitter = b; break }
        }
        guard let b = sitter else { throw CheckFailure(detail: "nobody landed on the pointer at (\(px), \(py)) in 40 s") }
        for _ in 0..<60 { w.step(tick) }
        // The body runs 0.78 half-heights behind its centre and 0.4 ahead: all on the screen.
        let hh = b.sp.span * 13 * w.breeze.unit * b.size * w.depthScale(b.z) * b.sp.aspect / 2
        for a in stride(from: -0.78 * hh, through: 0.4 * hh, by: hh / 8) {
            let p = SIMD2(b.x + cos(b.heading) * a, b.y + sin(b.heading) * a)
            try expect(t.contains(p), "the sitter's body leaves the screen at (\(p.x), \(p.y)) for a pointer at (\(px), \(py))")
        }
        try expect(b.state == .cursor, "the sitter left a still pointer")
        w.pointerMoved(x: px + 30, y: py)
        w.step(tick)
        try expect(b.state != .cursor, "a move did not send the sitter off")
    }
}

/// Clicks on open ground bloom flowers; a fresh bloom calls at most one butterfly at a time, never two on their way.
private func meadowClicksCallOneAtATime() throws {
    let w = MeadowWorld(terrain: .single(width: 1728, height: 1117), cell: cell13, seed: 42)
    for _ in 0..<60 { w.step(tick) }
    let before = w.flowers.all.count
    var maxCalled = 0
    for k in 0..<60 {
        w.pointerDown(x: 100 + Double(k % 12) * 130, y: 120 + Double(k / 12) * 200)
        for _ in 0..<12 {
            w.step(tick)
            // A called one is on its way with `called` set; the world never has two.
            var called = 0
            for b in w.flies where b.called && b.state == .approach { called += 1 }
            maxCalled = max(maxCalled, called)
        }
    }
    try expect(w.flowers.all.count > before, "no click bloomed a flower")
    try expect(w.flowers.clickedOpen <= w.tuning.clickLimit, "\(w.flowers.clickedOpen) clicked flowers open, limit \(w.tuning.clickLimit)")
    try expect(finite(w), "not finite after clicks")
    try expect(maxCalled <= 1, "\(maxCalled) butterflies called at once")
}

/// The CPU budget: on the owner's desk the Meadow (steps and painting both screens) costs no more than Web at 30 and
/// 15 fps. Measured on this thread's CPU time, painting only (no GPU), so it holds on machines without one. To stay
/// steady on a busy machine or one with fast and slow cores, the two are measured as pairs, back to back (the order
/// swapped every pair), at the user-interactive QoS that keeps the thread on the fast cores where it can; the check
/// compares like with like: the median of the pairs' Meadow ÷ Web ratios must be at most 1.
private func meadowWithinWebsCPU() throws {
    let cell = GridSpec.cell(forWidth: 2560)
    let pairs = 9
    let qos = qos_class_self()
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
    defer { pthread_set_qos_class_self_np(qos, 0) }
    func cpu() -> UInt64 { clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) }
    func cost(_ kind: HabitatKind, fps: Int, seed: Int) -> Double {
        var s = Settings.defaults
        s.habitat = kind
        let sim = Habitats.make(s, seed: UInt64(seed)) as! CellPainter
        sim.layout(terrain: desk, cell: cell, settings: s)
        let vs = views(desk, cell)
        for i in 0..<600 {
            sim.step(tick)
            if i % 2 == 1 { for (r, g, c) in vs { c.clear(); sim.paint(viewport: r, grid: g, theme: dark, into: c) } }
        }
        let frames = 4 * fps
        let t0 = cpu()
        for _ in 0..<frames {
            for _ in 0..<(60 / fps) { sim.step(tick) }
            for (r, g, c) in vs { c.clear(); sim.paint(viewport: r, grid: g, theme: dark, into: c) }
        }
        return Double(cpu() - t0) / 1e6 / 4
    }
    func median(_ v: [Double]) -> Double { let s = v.sorted(); return s[s.count / 2] }
    for fps in [30, 15] {
        var ratios: [Double] = []
        var meadows: [Double] = []
        var webs: [Double] = []
        for p in 0..<pairs {
            let seed: Int = 1 + p % 3
            var web = 0.0, meadow = 0.0
            if p % 2 == 0 {
                web = cost(.web, fps: fps, seed: seed)
                meadow = cost(.meadow, fps: fps, seed: seed)
            } else {
                meadow = cost(.meadow, fps: fps, seed: seed)
                web = cost(.web, fps: fps, seed: seed)
            }
            ratios.append(meadow / max(web, 1e-9))
            meadows.append(meadow)
            webs.append(web)
        }
        let ratio: Double = median(ratios)
        let low: Double = ratios.min() ?? 0, high: Double = ratios.max() ?? 0
        print(String(format: "  %d fps: meadow %.2f ms/s, web %.2f ms/s (medians); Meadow ÷ Web median %.2f over %d pairs (%.2f–%.2f)",
                     fps, median(meadows), median(webs), ratio, pairs, low, high))
        try expect(ratio <= 1, String(format: "at %d fps the Meadow costs %.2f× Web (median of %d pairs)", fps, ratio, pairs))
    }
}
