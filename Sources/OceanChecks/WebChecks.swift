import CoreGraphics
import Foundation
import OceanKit

/// A web like world.ts strings one: radius 200, a 12x17 cell.
private func makeWeb(seed: UInt64 = 1, stab: Bool = false) -> OrbWeb {
    OrbWeb(cx: 400, cy: 300, radius: 200, depth: 1, cw: 12, ch: 17, stab: stab, random: WebRandom(seed: seed))
}

/// Ten seconds of 60 Hz steps, plucked at the hub every second (as the pointer would).
private func ring(_ w: OrbWeb, seconds: Int) {
    for s in 0..<(seconds * 60) {
        if s % 60 == 0 { _ = w.pluck(Double(w.x[w.hub]), Double(w.y[w.hub]), 3, -2, w.cw * 1.15) }
        w.step(Double(s) / 60)
    }
}

/// The numbers web-ref.mjs prints for one web: the original web.ts run on the same random stream.
private struct WebSummary {
    var seed: Double, N: Int, T: Int, n: Int, m: Int, route: Int, spiralStart: Int
    var laid: Int, broken: Int, radialsLaid: Int, on: Int, dew: Int
    var rin: Double, spacing: Double, outer: Double, sumX: Double, sumY: Double, sumRest: Double
    var hubX: Double, hubY: Double
}

private func summarise(_ w: OrbWeb) -> WebSummary {
    var sx = 0.0, sy = 0.0, sr = 0.0, on = 0, dew = 0
    for i in 0..<w.n { sx += Double(w.x[i]); sy += Double(w.y[i]); on += Int(w.on[i]) }
    for l in 0..<w.m { sr += Double(w.rest[l]); if w.dew[l] >= 0 { dew += 1 } }
    return WebSummary(seed: w.seed, N: w.N, T: w.T, n: w.n, m: w.m, route: w.route.count, spiralStart: w.spiralStart,
                      laid: w.laid, broken: w.broken, radialsLaid: w.radialsLaid, on: on, dew: dew,
                      rin: w.rin, spacing: w.spacing, outer: w.outer, sumX: sx, sumY: sy, sumRest: sr,
                      hubX: Double(w.x[w.hub]), hubY: Double(w.y[w.hub]))
}

private func expectSummary(_ label: String, _ w: OrbWeb, _ want: WebSummary, tol: Double) throws {
    let got = summarise(w)
    let counts = [(got.N, want.N), (got.T, want.T), (got.n, want.n), (got.m, want.m), (got.route, want.route),
                  (got.spiralStart, want.spiralStart), (got.laid, want.laid), (got.broken, want.broken),
                  (got.radialsLaid, want.radialsLaid), (got.on, want.on), (got.dew, want.dew)]
    try expect(got.seed == want.seed && counts.allSatisfy { $0.0 == $0.1 }, "\(label): counts \(got) want \(want)")
    try expectClose(got.rin, want.rin, tol: 1e-9, "\(label) rin")
    try expectClose(got.spacing, want.spacing, tol: 1e-9, "\(label) spacing")
    try expectClose(got.outer, want.outer, tol: 1e-6, "\(label) outer")
    try expectClose(got.sumRest, want.sumRest, tol: 1e-4, "\(label) sumRest")
    try expectClose(got.sumX, want.sumX, tol: tol, "\(label) sumX")
    try expectClose(got.sumY, want.sumY, tol: tol, "\(label) sumY")
    try expectClose(got.hubX, want.hubX, tol: tol, "\(label) hubX")
    try expectClose(got.hubY, want.hubY, tol: tol, "\(label) hubY")
}

func webChecks() {
    // Values printed by running the original math.ts under node (Tools/web-reference/math-ref.mjs).
    check("webMathMatchesOriginal") {
        try expect(hash3(1, 2, 3) == 0.63940130639821291, "hash3(1,2,3) \(hash3(1, 2, 3))")
        try expect(hash3(-7, 123456, 91) == 0.98001145850867033, "hash3(-7,123456,91) \(hash3(-7, 123456, 91))")
        try expect(hash3(3.9, -2.5, 5e9) == 0.57291761506348848, "hash3(3.9,-2.5,5e9) \(hash3(3.9, -2.5, 5e9))")
        try expectClose(noise1(0.5), -0.63907853560522199, tol: 1e-15, "noise1(0.5)")
        try expectClose(noise1(12.34, 7), -0.51029782220220565, tol: 1e-15, "noise1(12.34,7)")
        try expectClose(noise1(-3.3, 123.7), -0.19136028190329663, tol: 1e-15, "noise1(-3.3,123.7)")
        try expectClose(angleDiff(3, -3), 0.28318530717958623, tol: 1e-15, "angleDiff(3,-3)")
        try expectClose(angleDiff(-3, 3), -0.28318530717958623, tol: 1e-15, "angleDiff(-3,3)")
        try expectClose(angleDiff(0.5, 20), 0.65044407846124130, tol: 1e-15, "angleDiff(0.5,20)")
        try expectClose(closestT(5, 5, 0, 0, 10, 0), 0.5, tol: 1e-15, "closestT level")
        try expectClose(closestT(3, 7, 1, 2, 9, 4), 0.38235294117647056, tol: 1e-15, "closestT")
        try expectClose(closestT(-4, 1, 1, 2, 9, 4), 0, tol: 0, "closestT clamped")
        try expectClose(crossAlong(0, 0, 10, 10, 0, 10, 10, 0), 0.5, tol: 1e-15, "crossAlong X")
        try expectClose(crossAlong(1, 2, 7, 9, 0, 8, 12, 1), 0.34126984126984128, tol: 1e-15, "crossAlong")
        try expectClose(crossAlong(0, 0, 1, 0, 0, 1, 1, 1), -1, tol: 0, "crossAlong parallel")
        try expectClose(smoothstep(0.2, 0.8, 0.35), 0.15624999999999989, tol: 1e-15, "smoothstep")
        try expectClose(ease(0.3), 0.216, tol: 1e-15, "ease")
        try expectClose(easeOut(0.3), 0.51000000000000001, tol: 1e-15, "easeOut")
        try expectClose(lerp(2, 9, 0.25), 3.75, tol: 0, "lerp")
        try expectClose(clamp(5, 0, 3), 3, tol: 0, "clamp")
        let r = WebRandom(seed: 9)
        for _ in 0..<2000 {
            let k = r.int(3, 4), u = r.range(-0.5, 0.5)
            try expect((3...4).contains(k) && u >= -0.5 && u < 0.5, "randInt/rand out of range: \(k) \(u)")
        }
    }
    check("orbWebRouteComplete") {
        let w = makeWeb()
        for st in w.route where st.lay { w.lay(st.link) }
        let unlaid = (0..<w.m).filter { w.state[$0] != 1 }
        try expect(unlaid.isEmpty, "\(unlaid.count) of \(w.m) links unlaid after the route: \(unlaid.prefix(8))")
        try expect(w.laid == w.m && w.radialsLaid == w.N, "laid \(w.laid)/\(w.m), radials \(w.radialsLaid)/\(w.N)")
    }
    check("orbWebStaysFinite") {
        let w = makeWeb()
        w.buildInstant()
        ring(w, seconds: 60)
        let hx = Double(w.x[w.hub]), hy = Double(w.y[w.hub])
        for i in 0..<w.n {
            let x = Double(w.x[i]), y = Double(w.y[i])
            try expect(x.isFinite && y.isFinite, "node \(i) not finite")
            // Twigs (pinned anchors and mooring ends) sit outside the capture area by design.
            if w.pin[i] == 0 {
                try expect(hypot(x - hx, y - hy) <= w.radius * 1.5, "node \(i) \(hypot(x - hx, y - hy)) from the hub")
            }
        }
        try expect(w.broken == 0, "plucking at the hub snapped \(w.broken) threads")
    }
    // A leg can still hold a link index from before a rebuild (spider.ts, weaver.ts): past the new web's
    // links it must read as "not laid" and lay/cut/jolt/load must do nothing, as in JS.
    check("orbWebStaleLinks") {
        let w = OrbWeb(cx: 900, cy: 600, radius: 480, depth: 1, cw: 12, ch: 17, stab: true, random: WebRandom(seed: 3))
        w.buildInstant()
        let stale = w.m - 1
        let oldX = w.x                       // a buffer held across the rebuild, as `const { x } = web` would be
        let before = oldX[0]
        w.cx = 400; w.cy = 300; w.radius = 200
        w.generate(Vec(x: 400, y: 300))
        try expect(w.m <= stale, "rebuild didn't shrink the web (m \(w.m))")
        try expect(oldX[0] == before && oldX.count > w.n, "old buffer changed or freed")
        let xs = (0..<w.n).map { w.x[$0] }, ys = (0..<w.n).map { w.y[$0] }
        let laid = w.laid, broken = w.broken, radials = w.radialsLaid
        for l in [stale, w.m, w.m + 1000, -1] {
            try expect(!w.isLaid(l), "isLaid(\(l))")
            w.jolt(l, 0.5, 3); w.load(l, 0.5, 2); w.cut(l, true); w.cut(l); w.lay(l)
            let p = w.pos(l, 0.5)
            try expect(l >= 0 && l < w.m || (p.x.isNaN && p.y.isNaN), "pos(\(l)) \(p)")
        }
        try expect(w.laid == laid && w.broken == broken && w.radialsLaid == radials, "counts changed")
        for i in 0..<w.n { try expect(w.x[i] == xs[i] && w.y[i] == ys[i], "node \(i) moved") }
        try expect(w.isLaid(w.route.first { $0.lay }!.link) == false, "a fresh web's route link reads laid")
    }
    check("orbWebDeterministic") {
        let a = makeWeb(seed: 5, stab: true), b = makeWeb(seed: 5, stab: true)
        a.buildInstant(); b.buildInstant()
        ring(a, seconds: 10); ring(b, seconds: 10)
        try expect(a.n == b.n, "node counts differ")
        for i in 0..<a.n {
            try expect(a.x[i] == b.x[i] && a.y[i] == b.y[i], "node \(i) differs")
        }
    }
    // The original web.ts on the same random stream (Tools/web-reference/web-ref.mjs): generated, built,
    // ten seconds plucked at the hub, then one jolt and a step. It agrees to the 12 digits node prints;
    // floats get a small tolerance for libm vs V8 sin/cos/hypot.
    check("orbWebMatchesOriginal") {
        let cases: [(String, () -> OrbWeb, [WebSummary])] = [
            ("A", { OrbWeb(cx: 400, cy: 300, radius: 200, depth: 1, cw: 12, ch: 17, random: WebRandom(seed: 1)) }, [
                WebSummary(seed: 566562, N: 10, T: 2, n: 59, m: 107, route: 156, spiralStart: 134, laid: 4, broken: 0, radialsLaid: 0, on: 8, dew: 1,
                           rin: 54, spacing: 55.2149795885, outer: 225.176475658, sumX: 23687.3755798, sumY: 17895.5529003, sumRest: 5156.36353970, hubX: 400, hubY: 300),
                WebSummary(seed: 566562, N: 10, T: 2, n: 59, m: 107, route: 156, spiralStart: 134, laid: 107, broken: 0, radialsLaid: 10, on: 59, dew: 1,
                           rin: 54, spacing: 55.2149795885, outer: 225.176475658, sumX: 23681.3868256, sumY: 17930.6587429, sumRest: 5156.36353970, hubX: 399.572265625, hubY: 301.341156006),
                WebSummary(seed: 566562, N: 10, T: 2, n: 59, m: 107, route: 156, spiralStart: 134, laid: 107, broken: 0, radialsLaid: 10, on: 59, dew: 1,
                           rin: 54, spacing: 55.2149795885, outer: 225.176475658, sumX: 23685.7845001, sumY: 17928.6556377, sumRest: 5156.36353970, hubX: 399.670288086, hubY: 301.262634277),
                WebSummary(seed: 566562, N: 10, T: 2, n: 59, m: 107, route: 156, spiralStart: 134, laid: 107, broken: 0, radialsLaid: 10, on: 59, dew: 1,
                           rin: 54, spacing: 55.2149795885, outer: 225.176475658, sumX: 23680.2983093, sumY: 17925.8987865, sumRest: 5156.36353970, hubX: 399.697570801, hubY: 301.243103027),
            ]),
            ("B", { OrbWeb(cx: 640, cy: 420, radius: 260, depth: 0.5, cw: 9, ch: 18, stab: true, random: WebRandom(seed: 42)) }, [
                WebSummary(seed: 741565, N: 18, T: 2, n: 99, m: 193, route: 296, spiralStart: 238, laid: 4, broken: 0, radialsLaid: 0, on: 8, dew: 2,
                           rin: 70.2, spacing: 61.1091744107, outer: 324.261687289, sumX: 64049.4086609, sumY: 41266.5382786, sumRest: 9223.68077707, hubX: 640, hubY: 420),
                WebSummary(seed: 741565, N: 18, T: 2, n: 99, m: 193, route: 296, spiralStart: 238, laid: 193, broken: 0, radialsLaid: 18, on: 99, dew: 2,
                           rin: 70.2, spacing: 61.1091744107, outer: 324.261687289, sumX: 64228.0121155, sumY: 41275.1558628, sumRest: 9223.68077707, hubX: 642.296508789, hubY: 420.562347412),
                WebSummary(seed: 741565, N: 18, T: 2, n: 99, m: 193, route: 296, spiralStart: 238, laid: 193, broken: 0, radialsLaid: 18, on: 99, dew: 2,
                           rin: 70.2, spacing: 61.1091744107, outer: 324.261687289, sumX: 64242.9541321, sumY: 41265.1073856, sumRest: 9223.68077707, hubX: 642.422119141, hubY: 420.497924805),
                WebSummary(seed: 741565, N: 18, T: 2, n: 99, m: 193, route: 296, spiralStart: 238, laid: 193, broken: 0, radialsLaid: 18, on: 99, dew: 2,
                           rin: 70.2, spacing: 61.1091744107, outer: 324.261687289, sumX: 64245.3590393, sumY: 41268.2874546, sumRest: 9223.68077707, hubX: 642.432678223, hubY: 420.508422852),
            ]),
            ("C", {
                OrbWeb(cx: 500, cy: 400, radius: 180, depth: 0.7, cw: 12, ch: 17, frame: [
                    FramePoint(x: 330, y: 220, mx: 300, my: 150), FramePoint(x: 690, y: 240, mx: 760, my: 180),
                    FramePoint(x: 700, y: 610, mx: 760, my: 680), FramePoint(x: 310, y: 600, mx: 250, my: 660),
                ], random: WebRandom(seed: 7))
            }, [
                WebSummary(seed: 389830, N: 9, T: 2, n: 54, m: 97, route: 141, spiralStart: 121, laid: 4, broken: 0, radialsLaid: 0, on: 8, dew: 0,
                           rin: 52.86, spacing: 57.4372368493, outer: 235.461353535, sumX: 27108.7104797, sumY: 21796.5152893, sumRest: 5299.04349375, hubX: 500, hubY: 400),
                WebSummary(seed: 389830, N: 9, T: 2, n: 54, m: 97, route: 141, spiralStart: 121, laid: 97, broken: 0, radialsLaid: 9, on: 54, dew: 0,
                           rin: 52.86, spacing: 57.4372368493, outer: 235.461353535, sumX: 27135.2939148, sumY: 21818.9399719, sumRest: 5299.04349375, hubX: 500.974212646, hubY: 400.428527832),
                WebSummary(seed: 389830, N: 9, T: 2, n: 54, m: 97, route: 141, spiralStart: 121, laid: 97, broken: 0, radialsLaid: 9, on: 54, dew: 0,
                           rin: 52.86, spacing: 57.4372368493, outer: 235.461353535, sumX: 27133.3263855, sumY: 21818.3656006, sumRest: 5299.04349375, hubX: 500.928405762, hubY: 400.406799316),
                WebSummary(seed: 389830, N: 9, T: 2, n: 54, m: 97, route: 141, spiralStart: 121, laid: 97, broken: 0, radialsLaid: 9, on: 54, dew: 0,
                           rin: 52.86, spacing: 57.4372368493, outer: 235.461353535, sumX: 27130.3445129, sumY: 21813.9998474, sumRest: 5299.04349375, hubX: 500.903656006, hubY: 400.396514893),
            ]),
            ("D", { OrbWeb(cx: 900, cy: 600, radius: 480, depth: 1, cw: 12, ch: 17, stab: true, random: WebRandom(seed: 3)) }, [
                WebSummary(seed: 113451, N: 20, T: 6, n: 191, m: 383, route: 583, spiralStart: 425, laid: 5, broken: 0, radialsLaid: 0, on: 10, dew: 7,
                           rin: 129.6, spacing: 54.6407144041, outer: 651.115797167, sumX: 170124.342117, sumY: 118371.309422, sumRest: 28084.6339831, hubX: 900, hubY: 600),
                WebSummary(seed: 113451, N: 20, T: 6, n: 191, m: 383, route: 583, spiralStart: 425, laid: 383, broken: 0, radialsLaid: 20, on: 191, dew: 7,
                           rin: 129.6, spacing: 54.6407144041, outer: 651.115797167, sumX: 169803.063583, sumY: 119436.547947, sumRest: 28084.6339831, hubX: 898.626770020, hubY: 607.451721191),
                WebSummary(seed: 113451, N: 20, T: 6, n: 191, m: 383, route: 583, spiralStart: 425, laid: 383, broken: 0, radialsLaid: 20, on: 191, dew: 7,
                           rin: 129.6, spacing: 54.6407144041, outer: 651.115797167, sumX: 169820.008774, sumY: 119443.701649, sumRest: 28084.6339831, hubX: 898.717712402, hubY: 607.489196777),
                WebSummary(seed: 113451, N: 20, T: 6, n: 191, m: 383, route: 583, spiralStart: 425, laid: 383, broken: 0, radialsLaid: 20, on: 191, dew: 7,
                           rin: 129.6, spacing: 54.6407144041, outer: 651.115797167, sumX: 169814.842606, sumY: 119442.046299, sumRest: 28084.6339831, hubX: 898.713867188, hubY: 607.494140625),
            ]),
        ]
        for (label, make, want) in cases {
            let w = make()
            try expectSummary("\(label) generated", w, want[0], tol: 1e-6)
            w.buildInstant()
            try expectSummary("\(label) built", w, want[1], tol: 1e-4)
            ring(w, seconds: 10)
            try expectSummary("\(label) plucked", w, want[2], tol: 1e-4)
            if let st = w.route.indices.contains(w.spiralStart) ? w.route[w.spiralStart] : nil { w.jolt(st.link, 0.5, 3) }
            w.step(10)
            try expectSummary("\(label) jolted", w, want[3], tol: 1e-4)
        }
    }
    webWorldChecks()
    webPainterChecks()
}

// ── Task 9: spiders, weavers, the jumper, flies and the wall ──

/// The demo page's wall at the built-in display's size, 13 × 19 cells.
private func makeWorld(seed: UInt64, spiders: [SpiderKind] = SpiderKind.defaultCast, flies: Bool = true, jumper: Bool = true,
                       rects: [CGRect] = [CGRect(x: 0, y: 0, width: 1800, height: 1169)], settled: Bool = false) -> WebWorld {
    let w = WebWorld(spiders: spiders, flies: flies, jumper: jumper, random: WebRandom(seed: seed))
    w.layout(terrain: Terrain(rects: rects), cell: CGSize(width: 13, height: 19), settled: settled)
    return w
}

private let weaverStates: [WeaverState] = [.build, .idle, .hunt, .wrap, .carry, .return, .eat, .move]
private let jumperStates: [JumperState] = [.pause, .burst, .crouch, .jump]
private let flyModes: [FlyMode] = [.fly, .rest, .stuck, .wrapped, .held, .gone]

/// The same numbers world-ref.mjs prints, in the same order.
func webWorldFeatures(_ w: WebWorld) -> [(String, Double)] {
    var f: [(String, Double)] = [("time", w.time)]
    for (i, web) in w.webs.enumerated() {
        var sx = 0.0, sy = 0.0
        for n in 0..<web.n { sx += Double(web.x[n]); sy += Double(web.y[n]) }
        f += [("web\(i).laid", Double(web.laid)), ("web\(i).broken", Double(web.broken)), ("web\(i).gen", Double(web.gen)),
              ("web\(i).seed", web.seed), ("web\(i).n", Double(web.n)), ("web\(i).held", Double(web.held)),
              ("web\(i).hubX", Double(web.x[web.hub])), ("web\(i).hubY", Double(web.y[web.hub])),
              ("web\(i).sumX", sx), ("web\(i).sumY", sy), ("web\(i).prey", Double(web.prey.count))]
    }
    for (i, v) in w.weavers.enumerated() {
        let sp = v.spider
        var fx = 0.0, fy = 0.0, planted = 0.0, links = 0.0
        for l in sp.legs { fx += l.fx; fy += l.fy; planted += l.planted ? 1 : 0; links += Double(l.link) }
        f += [("weaver\(i).state", Double(weaverStates.firstIndex(of: v.state)!)), ("weaver\(i).step", Double(v.step)),
              ("weaver\(i).wp", Double(v.wp)), ("weaver\(i).catches", Double(v.catches)), ("weaver\(i).age", v.age),
              ("weaver\(i).alert", v.alert), ("weaver\(i).x", sp.x), ("weaver\(i).y", sp.y), ("weaver\(i).h", sp.h),
              ("weaver\(i).hv", sp.hv), ("weaver\(i).dx", sp.dx), ("weaver\(i).dy", sp.dy), ("weaver\(i).still", sp.still),
              ("weaver\(i).feetX", fx), ("weaver\(i).feetY", fy), ("weaver\(i).planted", planted), ("weaver\(i).links", links)]
    }
    if let j = w.jumper {
        let sp = j.spider
        var fx = 0.0, fy = 0.0
        for l in sp.legs { fx += l.fx; fy += l.fy }
        f += [("jumper.state", Double(jumperStates.firstIndex(of: j.state)!)), ("jumper.x", sp.x), ("jumper.y", sp.y),
              ("jumper.h", sp.h), ("jumper.scale", sp.scale), ("jumper.drag", j.drag?.life ?? -1),
              ("jumper.feetX", fx), ("jumper.feetY", fy)]
    }
    f.append(("flies", Double(w.swarm.flies.count)))
    for (i, fl) in w.swarm.flies.enumerated() {
        f += [("fly\(i).mode", Double(flyModes.firstIndex(of: fl.mode)!)), ("fly\(i).x", fl.x), ("fly\(i).y", fl.y),
              ("fly\(i).h", fl.h), ("fly\(i).v", fl.v)]
    }
    f.append(("heat", Double(w.heat.count)))
    return f
}

/// world-ref.mjs's script: a pass through the near web, a fly dropped on its spiral and one into the air, then the
/// pointer held still 300 px from the jumper,
/// then from 40 s the first hunted fly torn free. Calls `each(step)` after every step.
func runWebScript(_ w: WebWorld, steps: Int, _ each: (Int) -> Void) {
    let W = w.width
    var aim = Vec(x: 0, y: 0)
    var cut = false
    let near = { w.weavers[w.weavers.count - 1] }
    for s in 1...steps {
        if s >= 60 && s < 120 && !w.weavers.isEmpty {
            let web = near().web
            let k = Double(s - 60) / 60
            w.pointerMoved(x: Double(web.x[web.hub]) + web.outer * (0.6 - 1.2 * k), y: Double(web.y[web.hub]) + 7)
        }
        if s == 120 { w.pointerLeft() }
        if s == 180 && !w.weavers.isEmpty {
            let web = near().web
            for l in 0..<web.m where web.isLaid(l) && web.kind[l] == SPIRAL {
                let p = web.pos(l, 0.5)
                w.release(x: p.x, y: p.y)
                break
            }
        }
        if s == 200 { w.release(x: W * 0.5, y: 12) }
        if s >= 300 && s < 1500 && w.jumper != nil {
            if s == 300, let sp = w.jumper?.spider {
                aim = Vec(x: min(W - 20, max(20, sp.x + (sp.x < W / 2 ? 300 : -300))), y: sp.y)
            }
            w.pointerMoved(x: aim.x, y: aim.y)
        }
        if s == 1500 { w.pointerLeft() }
        if s >= 2400 && !cut, let v = w.weavers.first(where: { $0.state == .hunt && $0.prey != nil }) {
            // The first fly hunted from then on tears free (its thread cut), so its spider turns back: "return".
            v.web.cut(v.prey!.link, true)
            cut = true
        }
        w.step(1.0 / 60)
        each(s)
    }
}

/// Every web's hub on a screen, and every frame corner (a pinned end of a frame thread) on the hub's screen.
private func framesFit(_ w: WebWorld, _ rects: [CGRect]) throws {
    let t = Terrain(rects: rects)
    for web in w.webs {
        let r = rects[t.rectIndex(near: SIMD2(web.cx, web.cy))]
        try expect(r.contains(CGPoint(x: web.cx, y: web.cy)), "hub \(web.cx), \(web.cy) on no screen")
        for l in 0..<web.m where web.kind[l] == FRAME {
            for n in [web.la[l], web.lb[l]] where web.pin[n] != 0 {
                let p = CGPoint(x: Double(web.x[n]), y: Double(web.y[n]))
                try expect(r.insetBy(dx: -1, dy: -1).contains(p), "frame corner \(p) off its screen \(r)")
            }
        }
    }
}

private func step(_ w: WebWorld, _ seconds: Double, until done: () -> Bool = { false }) {
    for _ in 0..<Int(seconds * 60) {
        w.step(1.0 / 60)
        if done() { return }
    }
}

/// The capture-spiral thread nearest the hub: where a dropped fly sticks closest to the spider.
private func innerSpiral(_ web: OrbWeb) -> Int? {
    let hx = Double(web.x[web.hub]), hy = Double(web.y[web.hub])
    return (0..<web.m).filter { web.isLaid($0) && web.kind[$0] == SPIRAL }
        .min { let a = web.pos($0, 0.5), b = web.pos($1, 0.5); return hypot(a.x - hx, a.y - hy) < hypot(b.x - hx, b.y - hy) }
}

func webWorldChecks() {
    // The brief says "release a fly at the hub", but release only sticks a fly to capture spiral within 0.9 of a
    // cell (flies.ts), and the hub is ringed by hub and radial silk: there it just flies off. So it is dropped on
    // the spiral thread nearest the hub.
    check("weaverLifeCycle") {
        let w = makeWorld(seed: 3, spiders: [.araneus], flies: false, jumper: false)
        let v = w.weavers[0]
        try expect(v.state == .idle, "starts \(v.state)")
        guard let l = innerSpiral(v.web) else { throw CheckFailure(detail: "no capture spiral") }
        let p = v.web.pos(l, 0.5)
        let fly = w.release(x: p.x, y: p.y)
        try expect(fly.mode == .stuck && fly.web === v.web, "the fly didn't stick to the web: \(fly.mode)")
        var seen = Set<WeaverState>()
        let eaten: Set<FlyMode> = [.wrapped, .held, .gone]
        step(w, 30) {
            seen.insert(v.state)
            return eaten.contains(fly.mode) && seen.isSuperset(of: [.hunt, .wrap, .carry])
        }
        try expect(seen.isSuperset(of: [.hunt, .wrap, .carry]), "states seen \(seen)")
        try expect(eaten.contains(fly.mode), "fly ended \(fly.mode)")
    }
    check("weaverFeelsAPluck") {
        let w = makeWorld(seed: 3, spiders: [.araneus], flies: false, jumper: false)
        let v = w.weavers[0], web = v.web
        step(w, 1)
        let hx = Double(web.x[web.hub]), hy = Double(web.y[web.hub])
        let h0 = v.spider.h
        try expect(v.state == .idle && abs(angleDiff(h0, .pi / 2)) < 0.05, "not hanging head-down: \(v.state) \(h0)")
        // The pointer sweeps down through the silk to the right of the hub, for half a second.
        for s in 0..<30 {
            w.pointerMoved(x: hx + web.outer * 0.5, y: hy - web.outer * 0.4 + web.outer * 0.8 * Double(s) / 29)
            w.step(1.0 / 60)
        }
        try expect(v.alert > 0.3 && abs(v.alertDir) < 0.8, "alert \(v.alert) from \(v.alertDir)")
        // Head-down is +pi/2; a tug from the right (angle ~0) swings it toward 0.
        try expect(v.spider.h < h0 - 0.1, "heading \(h0) -> \(v.spider.h)")
        try expect(v.spider.reach != nil, "no foreleg raised toward the tug")
    }
    check("jumperPounces") {
        let w = makeWorld(seed: 3, flies: false)
        guard let j = w.jumper else { throw CheckFailure(detail: "no jumper") }
        let sp = j.spider
        let p = Vec(x: sp.x + (sp.x < w.width / 2 ? 300 : -300), y: sp.y)
        var jumped = false
        for _ in 0..<600 {
            w.pointerMoved(x: p.x, y: p.y)
            w.step(1.0 / 60)
            if j.state == .jump { jumped = true; break }
        }
        try expect(jumped, "no pounce in 10 s; ended \(j.state) at \(hypot(sp.x - p.x, sp.y - p.y)) px")
        step(w, 2) { j.state != .jump }
        try expect(hypot(sp.x - p.x, sp.y - p.y) < sp.B * 0.5, "landed \(hypot(sp.x - p.x, sp.y - p.y)) px from the pointer")
    }
    check("legsStayOnSilk") {
        for kind in SpiderKind.allCases {
            let w = makeWorld(seed: 3, spiders: [kind], flies: false, jumper: false)
            let v = w.weavers[0]
            let cell = max(w.cw, w.ch)
            var planted = 0
            for _ in 0..<(20 * 60) {
                w.step(1.0 / 60)
                try expect(v.state == .idle, "\(kind) left idle: \(v.state)")
                for (i, leg) in v.spider.legs.enumerated() where leg.planted {
                    planted += 1
                    try expect(v.web.snap(leg.fx, leg.fy, cell) != nil, "\(kind) foot \(i) off the silk at t=\(w.time)")
                }
            }
            try expect(planted > 20 * 60 * 6, "\(kind): feet mostly in the air (\(planted))")
        }
    }
    check("flyFromEmptyClick") {
        let w = makeWorld(seed: 3, flies: false)
        try expect(w.swarm.flies.isEmpty, "flies off, yet \(w.swarm.flies.count)")
        var spot: Vec? = nil
        search: for gy in stride(from: 40.0, to: w.height - 40, by: 40) {
            for gx in stride(from: 40.0, to: w.width - 40, by: 40) where w.webs.allSatisfy({ $0.snap(gx, gy, 80) == nil }) {
                spot = Vec(x: gx, y: gy)
                break search
            }
        }
        guard let spot else { throw CheckFailure(detail: "no empty spot") }
        try expect(w.pointerDown(x: -5, y: spot.y) == nil, "a click off the terrain dropped a fly")
        guard let f = w.pointerDown(x: spot.x, y: spot.y) else { throw CheckFailure(detail: "no fly") }
        try expect(w.swarm.flies.count == 1 && f.mode == .fly && f.x == spot.x && f.y == spot.y, "\(f.mode) at \(f.x), \(f.y)")
        w.step(1.0 / 60)
        try expect(f.mode == .fly && hypot(f.x - spot.x, f.y - spot.y) < w.cw, "\(f.mode), \(hypot(f.x - spot.x, f.y - spot.y)) px away")
    }
    check("webWorldDeterministic") {
        let a = makeWorld(seed: 5), b = makeWorld(seed: 5)
        runWebScript(a, steps: 1800) { _ in }
        runWebScript(b, steps: 1800) { _ in }
        let fa = webWorldFeatures(a), fb = webWorldFeatures(b)
        try expect(fa.count == fb.count, "feature counts differ")
        for (x, y) in zip(fa, fb) { try expect(x.0 == y.0 && x.1 == y.1, "\(x.0): \(x.1) vs \(y.1)") }
        try expect(a.random.unit() == b.random.unit(), "random streams differ")
    }
    // The original world.ts run on the same random stream (Tools/web-reference/world-ref.mjs, values in
    // WebWorldReference.swift), with the scripted pointer, two clicks and a torn-free fly: the demo page's wall at
    // 1800 x 1169 for ten simulated minutes (every weaver, jumper and fly state), and a small screen with a roster
    // longer than it has room for, laid out settled. Every number agrees to ~1e-13 and the stream ends at the same
    // draw. (The original is patched as the port is: no nav-bar gap, and the move glide's hang fixed.)
    check("webWorldMatchesOriginal") {
        for run in webWorldReference {
            let w = WebWorld(spiders: run.spiders ?? SpiderKind.defaultCast, flies: true, jumper: true, random: WebRandom(seed: run.seed))
            w.layout(terrain: .single(width: run.width, height: run.height), cell: CGSize(width: run.cw, height: run.ch), settled: run.settled)
            var weavers = Set<WeaverState>(), jumpers = Set<JumperState>(), flies = Set<FlyMode>()
            var got: [Int: [(String, Double)]] = [:]
            let wanted = Set(run.checkpoints.map(\.step))
            runWebScript(w, steps: run.checkpoints.map(\.step).max()!) { s in
                for v in w.weavers { weavers.insert(v.state) }
                if let j = w.jumper { jumpers.insert(j.state) }
                for f in w.swarm.flies { flies.insert(f.mode) }
                if wanted.contains(s) { got[s] = webWorldFeatures(w) }
            }
            for ref in run.checkpoints {
                let f = got[ref.step]!
                try expect(f.map(\.0) == ref.labels, "\(run.name) step \(ref.step): \(f.count) features, original \(ref.labels.count)")
                for (i, (label, v)) in f.enumerated() {
                    let want = ref.values[i]
                    try expect(abs(v - want) <= 1e-9 * max(1, abs(want)), "\(run.name) step \(ref.step) \(label): \(v), original \(want)")
                }
            }
            try expect(w.random.unit() == run.next, "\(run.name): the random stream drifted from the original's")
            if run.name == "demo" {
                try expect(weavers.count == 8 && jumpers.count == 4 && flies.count == 6,
                           "not every state was exercised: \(weavers) \(jumpers) \(flies)")
            }
        }
    }
    // Two screens, the monitor-above-laptop desk: webs drawn on one screen with the whole frame on it, the jumper and
    // the flies kept to the screens (flies up to 20 px off, as the original lets them off the page), and a relayout
    // onto one screen.
    check("webWorldOnSeveralScreens") {
        let rects = [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1800, height: 1169)]
        let w = makeWorld(seed: 9, rects: rects)
        let t = Terrain(rects: rects)
        try expect(w.webs.count >= 3 && !w.weavers.isEmpty, "\(w.webs.count) webs")
        try framesFit(w, rects)
        var lost: String? = nil
        runWebScript(w, steps: 3600) { s in
            if let sp = w.jumper?.spider, !t.contains(SIMD2(sp.x, sp.y)) { lost = lost ?? "jumper off the screens at \(sp.x), \(sp.y), step \(s)" }
            for f in w.swarm.flies where f.mode == .fly && !rects.contains(where: { $0.insetBy(dx: -20.5, dy: -20.5).contains(CGPoint(x: f.x, y: f.y)) }) {
                lost = lost ?? "fly lost at \(f.x), \(f.y), step \(s)"
            }
        }
        try expect(lost == nil, lost ?? "")
        try framesFit(w, rects)
        for v in w.weavers { try expect(v.spider.x.isFinite && v.spider.y.isFinite, "weaver not finite") }
        w.layout(terrain: .single(width: 1800, height: 1169), cell: CGSize(width: 13, height: 19), settled: false)
        step(w, 5)
        try expect(w.webs.count >= 3 && w.weavers.allSatisfy { $0.spider.x.isFinite }, "relayout onto one screen")
    }
    // Several screens: a weaver past its life eats its web, moves house and builds again; the new web is still
    // on its screen with its whole frame (Weaver.relocate's several-screens path).
    check("webWorldRelocatesOnSeveralScreens") {
        let rects = [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1800, height: 1169)]
        let t = Terrain(rects: rects)
        let w = makeWorld(seed: 9, flies: false, jumper: false, rects: rects)
        // How far a web's hub is inside the band where its whole frame (1.5 R) fits on its screen.
        func slack(_ web: OrbWeb) -> Double {
            let r = rects[t.rectIndex(near: SIMD2(web.home.x, web.home.y))]
            return min(web.cx - Double(r.minX), Double(r.maxX) - web.cx, web.cy - Double(r.minY), Double(r.maxY) - web.cy) - web.radius * 1.5
        }
        // The idle weaver whose web sits tightest against that band, so a move could take it off the screen.
        guard let v = w.weavers.filter({ $0.state == .idle }).min(by: { slack($0.web) < slack($1.web) }) else {
            throw CheckFailure(detail: "no idle weaver")
        }
        try expect(slack(v.web) < 1, "no web against its margin (\(slack(v.web)))")
        let gen = v.web.gen, home = v.web.home
        v.life = 0
        var seen = Set<WeaverState>()
        step(w, 600) {
            seen.insert(v.state)
            return seen.contains(.move) && v.state == .build
        }
        try expect(seen.isSuperset(of: [.eat, .move]) && v.state == .build, "states \(seen), now \(v.state)")
        try expect(v.web.gen == gen + 1, "web generation \(v.web.gen), was \(gen)")
        let r = rects[t.rectIndex(near: SIMD2(home.x, home.y))]
        try expect(r.contains(CGPoint(x: v.web.cx, y: v.web.cy)), "moved off its screen to \(v.web.cx), \(v.web.cy)")
        try expect(slack(v.web) >= -1e-9, "moved \(-slack(v.web)) px past where its frame fits")
        try framesFit(w, rects)
        step(w, 5)
        try framesFit(w, rects)
    }

}

// ── Task 10: the painter (renderer.ts) and the habitat ──

private let darkTheme = ThemeParams.make(.defaults, systemIsDark: true, accent: SIMD3(0.2, 0.5, 1))

/// A WebSim laid out over `rects` with the grid of the widest screen.
private func makeSim(seed: UInt64, rects: [CGRect], spiders: [SpiderKind] = SpiderKind.defaultCast,
                     flies: Bool = true, jumper: Bool = true) -> WebSim {
    var s = Settings.defaults
    s.habitat = .web
    s.webSpiders = spiders
    s.webFlies = flies
    s.webJumper = jumper
    let sim = WebSim(settings: s, seed: seed)
    sim.layout(terrain: Terrain(rects: rects), cell: GridSpec.cell(forWidth: Double(rects.map(\.width).max() ?? 0)), settings: s)
    return sim
}

/// Paints `viewport` of `sim` into a fresh canvas.
private func paint(_ sim: CellPainter, _ viewport: CGRect, cell: CGSize, theme: ThemeParams = darkTheme) -> CellCanvas {
    let grid = GridSpec.make(viewportSize: viewport.size, cell: cell)
    let c = CellCanvas(cols: grid.cols, rows: grid.rows)
    sim.paint(viewport: viewport, grid: grid, theme: theme, into: c)
    return c
}

private func glyphs(_ s: String) -> Set<UInt8> { Set(s.map { GlyphAtlas.index($0)! }) }

/// Every web's frame points (both ends of every frame thread) inside its own screen or off every screen, never on
/// another screen (the ruling on Review Focus 2: one screen is the original, whose frames run off the page).
private func framesOwnScreen(_ w: WebWorld, _ rects: [CGRect]) throws {
    for (n, web) in w.webs.enumerated() {
        guard let own = rects.firstIndex(where: { $0.contains(CGPoint(x: web.cx, y: web.cy)) }) else {
            throw CheckFailure(detail: "web \(n) hub \(web.cx), \(web.cy) on no screen")
        }
        for l in 0..<web.m where web.kind[l] == FRAME {
            for i in [web.la[l], web.lb[l]] {
                let p = CGPoint(x: Double(web.x[i]), y: Double(web.y[i]))
                for (k, r) in rects.enumerated() where k != own && r.contains(p) {
                    throw CheckFailure(detail: "web \(n) on screen \(own) has a frame point \(p) on screen \(k)")
                }
            }
        }
    }
}

func webPainterChecks() {
    check("webPainterLevelThread") {
        // renderer.ts Strokes: a level thread takes one cell per column, - _ or ¯ by where in the cell it runs.
        let s = WebStrokes()
        s.resize(cols: 30, rows: 6)
        for (frac, want) in [(0.5, "-"), (0.1, "¯"), (0.9, "_")] {
            s.begin()
            s.add(2.5 * 12, (3 + frac) * 17, 22.5 * 12, (3 + frac) * 17, 12, 17, 0.5)
            let cells = (0..<s.length).map { Int(s.cells[$0]) }
            try expect(Set(cells) == Set((2...21).map { 3 * 30 + $0 }), "\(want): cells \(cells.sorted())")
            for i in cells {
                try expect(glyphs("-_¯").contains(s.glyph(i)), "cell \(i) is \(GlyphAtlas.glyphs[Int(s.glyph(i))])")
                try expect(s.glyph(i) == GlyphAtlas.index(Character(want))!, "at \(frac) of the cell: \(GlyphAtlas.glyphs[Int(s.glyph(i))]), want \(want)")
            }
        }
        // Off the grid's left and right: only the 30 columns on it are plotted.
        s.begin()
        s.add(-40, 2.5 * 17, 50 * 12, 2.5 * 17, 12, 17, 0.5)
        try expect(s.length == 30, "clipped to the grid: \(s.length) cells")
    }
    check("webPainterHubKnot") {
        // Empty webs (no roster) are finished at once: every hub, where the radials meet, is a * knot.
        let w = WebWorld(spiders: [], flies: false, jumper: false, random: WebRandom(seed: 2))
        let cell = CGSize(width: 13, height: 19)
        w.layout(terrain: .single(width: 1800, height: 1169), cell: cell, settled: true)
        try expect(w.webs.count >= 5 && w.weavers.isEmpty, "\(w.webs.count) webs, \(w.weavers.count) weavers")
        let painter = WebPainter()
        let grid = GridSpec.make(viewportSize: CGSize(width: 1800, height: 1169), cell: cell)
        let c = CellCanvas(cols: grid.cols, rows: grid.rows)
        painter.paint(w, viewport: CGRect(x: 0, y: 0, width: 1800, height: 1169), grid: grid, theme: darkTheme, into: c)
        for web in w.webs {
            let col = Int(floor(Double(web.x[web.hub]) / 13)), row = Int(floor(Double(web.y[web.hub]) / 19))
            guard col >= 0, col < c.cols, row >= 0, row < c.rows else { continue }
            let g = c.glyph[row * c.cols + col]
            try expect(g == GlyphAtlas.index("*")!, "hub cell (\(col),\(row)) holds \(g == CellCanvas.noGlyph ? "nothing" : GlyphAtlas.glyphs[Int(g)])")
        }
        // Silk is all line glyphs and knots; dew sits over it as · or +.
        let silk = glyphs("-_¯/\\|*")
        try expect(c.glyph.allSatisfy { $0 == CellCanvas.noGlyph || silk.contains($0) }, "a silk cell holds something else")
        let dew = (0..<c.glyph.count).filter { c.overGlyph[$0] != CellCanvas.noGlyph }
        try expect(dew.count > 20 && dew.allSatisfy { glyphs("·+").contains(c.overGlyph[$0]) }, "\(dew.count) dew beads")
        try expect(dew.filter { c.glyph[$0] != CellCanvas.noGlyph }.count * 2 > dew.count, "dew mostly not over silk")
        try expect(c.block.allSatisfy { $0 == 0 }, "blocks on a wall with no spiders")
    }
    check("webPainterSpidersAndFlies") {
        // The demo wall: bodies are blocks with carved glyphs, legs are line glyphs on blocks, flies one glyph each.
        let sim = makeSim(seed: 3, rects: [CGRect(x: 0, y: 0, width: 1800, height: 1169)])
        for _ in 0..<120 { sim.step(OceanClock.step) }
        let c = paint(sim, CGRect(x: 0, y: 0, width: 1800, height: 1169), cell: CGSize(width: 13, height: 19))
        let blocks = c.block.filter { $0 >> 24 != 0 }.count
        try expect(blocks > 60, "\(blocks) block cells for \(sim.world.weavers.count) spiders and a jumper")
        try expect(c.glyph.contains(GlyphAtlas.index("O")!), "no jumper eyes")
        let skin = glyphs(":;t%SX8#@")
        try expect((0..<c.glyph.count).contains { c.block[$0] >> 24 != 0 && skin.contains(c.glyph[$0]) }, "no skin glyphs on blocks")
        for f in sim.world.swarm.flies where f.mode == .fly {
            let i = Int(floor(f.y / 19)) * c.cols + Int(floor(f.x / 13))
            guard f.x >= 0, f.y >= 0, f.x < 1800, f.y < 1169 else { continue }
            try expect(glyphs("x+").contains(c.glyph[i]) || c.block[i] >> 24 != 0, "fly at \(f.x), \(f.y) not drawn")
        }
    }
    check("webPalettes") {
        let sim = makeSim(seed: 3, rects: [CGRect(x: 0, y: 0, width: 900, height: 600)])
        for _ in 0..<60 { sim.step(OceanClock.step) }
        let vp = CGRect(x: 0, y: 0, width: 900, height: 600), cell = GridSpec.cell(forWidth: 900)
        var s = Settings.defaults
        let dark = paint(sim, vp, cell: cell)
        try expect(dark.background == .zero, "dark background \(dark.background)")
        try expect(dark.gridColor == SIMD4(1, 1, 1, 0.055), "dark grid \(dark.gridColor)")
        s.appearance = .light
        let lightTheme = ThemeParams.make(s, systemIsDark: true, accent: .zero)
        let light = paint(sim, vp, cell: cell, theme: lightTheme)
        try expect(light.background == SIMD3(247, 246, 243) / 255, "paper \(light.background)")
        try expect(light.gridColor == SIMD4(SIMD3(35, 35, 35) / 255, 0.08), "light grid \(light.gridColor)")
        s.grid = false
        try expect(paint(sim, vp, cell: cell, theme: ThemeParams.make(s, systemIsDark: true, accent: .zero)).gridColor.w == 0, "grid off")
        // Calm: dark multiplies ink and block by the brightness; light mixes them toward the paper.
        func rgba(_ v: UInt32) -> SIMD4<Float> { SIMD4(Float(v & 0xff), Float((v >> 8) & 0xff), Float((v >> 16) & 0xff), Float(v >> 24)) }
        // (Accents at the full rate here, so the same cells take the same colours; Calm's rate is checked below.)
        func calmTheme(_ light: Bool) -> ThemeParams {
            var t = Settings.defaults
            t.calm = true
            t.appearance = light ? .light : .dark
            var p = ThemeParams.make(t, systemIsDark: true, accent: .zero)
            p.accentRate = 1
            return p
        }
        for (normal, theme, isLight) in [(dark, calmTheme(false), false), (light, calmTheme(true), true)] {
            let calm = paint(sim, vp, cell: cell, theme: theme)
            try expect(calm.glyph == normal.glyph, "calm changed the glyphs")
            var compared = 0
            for i in 0..<normal.ink.count where normal.glyph[i] != CellCanvas.noGlyph {
                for (a, b) in [(rgba(normal.ink[i]), rgba(calm.ink[i])), (rgba(normal.block[i]), rgba(calm.block[i]))] where a.w > 0 {
                    let paper = SIMD3<Float>(247, 246, 243)
                    let want = isLight ? SIMD3(a.x, a.y, a.z) + (paper - SIMD3(a.x, a.y, a.z)) * (1 - theme.brightness)
                                       : SIMD3(a.x, a.y, a.z) * theme.brightness
                    let d = SIMD3(b.x, b.y, b.z) - want
                    try expect(max(abs(d.x), abs(d.y), abs(d.z)) <= 1.01 && a.w == b.w, "calm \(isLight ? "light" : "dark") cell \(i): \(a) -> \(b), want \(want)")
                    compared += 1
                }
            }
            try expect(compared > 100, "compared \(compared) colours")
        }
        // Accents (dark only) at the original's 6 % of skin cells, scaled by the theme's rate.
        let accents = Set([(224, 137, 44), (224, 58, 50), (180, 74, 224), (51, 200, 204), (60, 181, 74), (49, 80, 232), (217, 193, 74)]
            .map { UInt32($0.0) | UInt32($0.1) << 8 | UInt32($0.2) << 16 | 255 << 24 })
        let skin = glyphs(":;t%SX8#@")
        func accented(_ c: CellCanvas) -> Int { (0..<c.ink.count).filter { skin.contains(c.glyph[$0]) && accents.contains(c.ink[$0]) }.count }
        var none = ThemeParams.make(.defaults, systemIsDark: true, accent: .zero)
        none.accentRate = 0
        try expect(accented(dark) > 0 && accented(paint(sim, vp, cell: cell, theme: none)) == 0, "accents \(accented(dark)) at rate 1")
    }
    check("webLayoutRespectsTerrain") {
        // Ruling on Review Focus 2: on several screens every web's frame points lie on its own screen or off every
        // screen; on one screen the layout is the original's (frames may run off the page) and nothing crashes.
        let desk = [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1800, height: 1169)]
        let laptop = [CGRect(x: 0, y: 0, width: 1800, height: 1169)]
        let cell = GridSpec.cell(forWidth: 2560)
        for seed: UInt64 in [1, 2, 9, 21] {
            let sim = makeSim(seed: seed, rects: desk)
            try framesOwnScreen(sim.world, desk)
            for _ in 0..<120 { sim.step(OceanClock.step) }
            for r in desk { _ = paint(sim, r, cell: cell) }
            // Unplug the monitor: one screen, then plug it back.
            sim.layout(terrain: Terrain(rects: laptop), cell: GridSpec.cell(forWidth: 1800), settings: .defaults)
            for _ in 0..<120 { sim.step(OceanClock.step) }
            try framesOwnScreen(sim.world, laptop)
            _ = paint(sim, laptop[0], cell: GridSpec.cell(forWidth: 1800))
            sim.layout(terrain: Terrain(rects: desk), cell: cell, settings: .defaults)
            try framesOwnScreen(sim.world, desk)
            for _ in 0..<120 { sim.step(OceanClock.step) }
            for r in desk { _ = paint(sim, r, cell: cell) }
            try expect(sim.world.weavers.allSatisfy { $0.spider.x.isFinite && $0.spider.y.isFinite }, "seed \(seed): not finite")
        }
        // One screen: WebSim lays out exactly as the original's world (WebWorld, checked against it).
        let sim = makeSim(seed: 4, rects: laptop)
        let ref = WebWorld(spiders: SpiderKind.defaultCast, flies: true, jumper: true, random: WebRandom(seed: 4))
        ref.layout(terrain: Terrain(rects: laptop), cell: GridSpec.cell(forWidth: 1800), settled: false)
        for _ in 0..<60 { sim.step(OceanClock.step); ref.step(OceanClock.step) }
        let a = webWorldFeatures(sim.world), b = webWorldFeatures(ref)
        try expect(a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }, "WebSim's wall differs from WebWorld's")
        try expect(sim.world.webs.contains { web in (0..<web.n).contains { web.x[$0] < 0 || web.y[$0] < 0 || web.x[$0] > 1800 || web.y[$0] > 1169 } },
                   "no frame runs off the page (the original's frames do)")
    }
    check("webTinyViewport") {
        let r = CGRect(x: 0, y: 0, width: 340, height: 150)
        let sim = makeSim(seed: 5, rects: [r])
        try expect(sim.world.webs.count >= 1, "\(sim.world.webs.count) webs")
        for s in 0..<300 {
            sim.step(OceanClock.step)
            if s % 30 == 0 { _ = paint(sim, r, cell: GridSpec.cell(forWidth: 340)) }
        }
        for web in sim.world.webs { for i in 0..<web.n { try expect(web.x[i].isFinite && web.y[i].isFinite, "node not finite") } }
        for v in sim.world.weavers { try expect(v.spider.x.isFinite && v.spider.y.isFinite, "weaver not finite") }
        if let j = sim.world.jumper { try expect(j.spider.x.isFinite && j.spider.y.isFinite, "jumper not finite") }
        for f in sim.world.swarm.flies { try expect(f.x.isFinite && f.y.isFinite, "fly not finite") }
        let c = paint(sim, r, cell: GridSpec.cell(forWidth: 340))
        try expect(c.glyph.contains { $0 != CellCanvas.noGlyph }, "nothing drawn")
    }
    check("webSimFromSettings") {
        var s = Settings.defaults
        try expect(Habitats.make(s, seed: 1) is OceanSim, "ocean")
        s.habitat = .web
        s.webSpiders = [.nephila]
        s.webFlies = false
        s.webJumper = true
        let sim = Habitats.make(s, seed: 4)
        guard let web = sim as? WebSim else { throw CheckFailure(detail: "\(type(of: sim)) for .web") }
        try expect(sim.kind == .web, "kind \(sim.kind)")
        sim.layout(terrain: .single(width: 1800, height: 1169), cell: GridSpec.cell(forWidth: 1800), settings: s)
        try expect(web.world.weavers.count == 1 && web.world.weavers[0].spider.kind == .nephila, "weavers \(web.world.weavers.map(\.spider.kind))")
        try expect(web.world.swarm.flies.isEmpty && web.world.jumper != nil, "flies \(web.world.swarm.flies.count), jumper \(web.world.jumper != nil)")
        s.webFlies = true
        s.webJumper = false
        let other = Habitats.make(s, seed: 4) as! WebSim
        other.layout(terrain: .single(width: 1800, height: 1169), cell: GridSpec.cell(forWidth: 1800), settings: s)
        try expect(!other.world.swarm.flies.isEmpty && other.world.jumper == nil, "flies \(other.world.swarm.flies.count), jumper \(other.world.jumper != nil)")
        // Steps, the pointer, a click.
        let before = other.world.swarm.flies.count
        other.step(OceanClock.step)
        other.pointerMoved(100, 100)
        other.step(OceanClock.step)
        other.pointerDown(900, 20)
        other.pointerLeft()
        try expect(other.stepCount == 2 && other.world.swarm.flies.count == before + 1 && !other.world.pointer.active,
                   "steps \(other.stepCount), flies \(other.world.swarm.flies.count)")
    }
    check("webGlyphsMatchChrome") {
        // The canvas atlas draws each glyph where Chrome's canvas draws it, as heavy: ink boxes (coverage > 0.25)
        // within a pixel and total ink within 12 % of Chrome 158's own (600 13px Geist Mono, textBaseline middle at
        // ch/2 + 1, a 12 x 17 cell). The numbers are sheet-boxes.py's on sheet.mjs's glyph sheet, both in
        // Tools/web-reference/parity (README there, "Parity with the original"); docs/reference/web-port-notes.md.
        let chrome: [Int: [(Character, Int, Int, Int, Int, Double)]] = [
            1: [("|", 3, 14, 5, 6, 21.7), ("-", 8, 9, 3, 8, 8.9), ("_", 13, 14, 3, 8, 11.2), ("¯", 3, 4, 4, 7, 6.1), ("/", 3, 14, 3, 8, 22.5),
                ("*", 3, 9, 3, 8, 23.1), ("x", 6, 12, 2, 8, 28.2), ("@", 3, 14, 2, 9, 53.6), ("O", 3, 12, 2, 9, 44.3)],
            2: [("|", 6, 28, 10, 13, 82.9), ("-", 16, 19, 7, 16, 33.9), ("_", 25, 28, 6, 17, 41.7), ("¯", 7, 9, 8, 15, 22.6), ("/", 6, 28, 6, 17, 82.6),
                ("*", 7, 18, 6, 17, 85.3), ("x", 11, 25, 5, 18, 108.1), ("@", 7, 28, 4, 19, 196.4), ("O", 7, 26, 5, 18, 167.8)],
        ]
        for (scale, refs) in chrome {
            let a = try GlyphAtlas.makeBytes(cell: CGSize(width: 12, height: 17), scale: CGFloat(scale), middle: .canvas)
            for (g, y0, y1, x0, x1, ink) in refs {
                let slot = Int(GlyphAtlas.index(g)!)
                var box = (Int.max, Int.min, Int.max, Int.min), sum = 0.0
                for y in 0..<a.height { for x in 0..<a.slotWidth {
                    let v = Double(a.bytes[y * a.width + slot * a.slotWidth + x]) / 255
                    sum += v
                    if v > 0.25 { box = (min(box.0, y), max(box.1, y), min(box.2, x), max(box.3, x)) }
                } }
                let off = [box.0 - y0, box.1 - y1, box.2 - x0, box.3 - x1].map(abs).max()!
                try expect(off <= 1, "\(scale)x \(g): box rows \(box.0)-\(box.1) cols \(box.2)-\(box.3), Chrome \(y0)-\(y1), \(x0)-\(x1)")
                try expect(abs(sum / ink - 1) < 0.12, "\(scale)x \(g): ink \(sum), Chrome \(ink)")
            }
        }
    }
    check("webSettleIsTheOriginalStill") {
        // settle(): a fresh wall is laid out settled (every web finished, flies resting) and stepped 120 times, as
        // engine.ts does for ?still=1; settling again, or once the wall has lived, changes nothing.
        let r = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let sim = makeSim(seed: 6, rects: [r])
        sim.settle()
        // The original's still page: one layout, settled, from the seed's first draw.
        let ref = WebWorld(spiders: SpiderKind.defaultCast, flies: true, jumper: true, random: WebRandom(seed: 6))
        ref.layout(terrain: .single(width: 1800, height: 1169), cell: GridSpec.cell(forWidth: 1800), settled: true)
        for _ in 0..<120 { ref.step(1.0 / 60) }
        let a = webWorldFeatures(sim.world), b = webWorldFeatures(ref)
        try expect(a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }, "settled wall differs")
        try expect(sim.world.webs.allSatisfy { $0.laid == $0.m }, "an unfinished web in the still")
        let modes = sim.world.swarm.flies.map(\.mode)
        try expect(modes.filter { $0 == .rest }.count >= modes.count - 1 && !modes.contains(.fly), "flies in the still: \(modes)")
        sim.settle()
        try expect(webWorldFeatures(sim.world).map(\.1) == a.map(\.1), "settling twice changed the wall")
        let live = makeSim(seed: 6, rects: [r])
        for _ in 0..<600 { live.step(OceanClock.step) }
        let f = webWorldFeatures(live.world)
        live.settle()
        try expect(webWorldFeatures(live.world).map(\.1) == f.map(\.1), "settling a living wall changed it")
    }
}

func webRenderChecks() {
    check("webStillRenders") {
        var s = Settings.defaults
        s.habitat = .web
        for light in [false, true] {
            s.appearance = light ? .light : .dark
            let img = try StillRenderer.render(settings: s, size: CGSize(width: 480, height: 300), scale: 1, warmup: 1,
                                               systemIsDark: true, accent: SIMD3(0.2, 0.5, 1), seed: 3)
            let w = img.width, h = img.height
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            let bg: [Int] = light ? [247, 246, 243] : [0, 0, 0]
            var plain = 0, other = 0
            for i in stride(from: 0, to: bytes.count, by: 4) {
                if abs(Int(bytes[i]) - bg[0]) <= 1 && abs(Int(bytes[i + 1]) - bg[1]) <= 1 && abs(Int(bytes[i + 2]) - bg[2]) <= 1 { plain += 1 } else { other += 1 }
            }
            try expect(plain > w * h / 3, "\(light ? "light" : "dark"): background pixels \(plain) of \(w * h)")
            try expect(other > w * h / 50, "\(light ? "light" : "dark"): drawn pixels \(other) of \(w * h)")
        }
        // A Web still is the original's still frame: no warm-up steps after settling, whatever the warm-up asked.
        s.appearance = .dark
        let short = try StillRenderer.render(settings: s, size: CGSize(width: 480, height: 300), scale: 1, warmup: 1,
                                             systemIsDark: true, accent: SIMD3(0.2, 0.5, 1), seed: 3)
        let long = try StillRenderer.render(settings: s, size: CGSize(width: 480, height: 300), scale: 1, warmup: 6,
                                            systemIsDark: true, accent: SIMD3(0.2, 0.5, 1), seed: 3)
        try expect(rgbBytes(short) == rgbBytes(long), "the warm-up changed the Web still")
    }
    check("webLightHasNoAccents") {
        // Review Focus 4: Light is graphite on paper. The still's background is paper, and the only colour in it is
        // the species' tint on their bodies (the original's light palette tints bodies and legs too: argiope's
        // bands reach saturation 0.36 in the original's own light still). No accent hue anywhere: not on silk,
        // dew, flies or ringing silk, and the cells that take an accent, the cyan ring, the fang or the heat on
        // black are graphite or paper on paper.
        var s = Settings.defaults
        s.habitat = .web
        s.appearance = .light
        let size = CGSize(width: 900, height: 600)
        let img = try StillRenderer.render(settings: s, size: size, scale: 1, warmup: 1, systemIsDark: true,
                                           accent: SIMD3(0.2, 0.5, 1), seed: 5)
        let px = rgbBytes(img)
        // The same wall on the CPU (the still is settle(), deterministic): which cells hold a spider.
        let cell = GridSpec.cell(forWidth: size.width)
        let sim = makeSim(seed: 5, rects: [CGRect(origin: .zero, size: size)])
        sim.settle()
        let lightTheme = ThemeParams.make(s, systemIsDark: true, accent: .zero)
        let canvas = paint(sim, CGRect(origin: .zero, size: size), cell: cell, theme: lightTheme)
        let cols = canvas.cols, rows = canvas.rows
        var body = [Bool](repeating: false, count: cols * rows)
        for r in 0..<rows { for c in 0..<cols where canvas.block[r * cols + c] >> 24 > 0 {
            // A body or leg block, and the edge glyphs around it.
            for rr in max(0, r - 1)...min(rows - 1, r + 1) { for cc in max(0, c - 1)...min(cols - 1, c + 1) { body[rr * cols + cc] = true } }
        } }
        try expect(body.contains(true), "no spider in the still")
        var paper = 0, saturated = 0, stray = 0
        for y in 0..<img.height { for x in 0..<img.width {
            let i = (y * img.width + x) * 4
            let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
            if abs(r - 247) <= 1 && abs(g - 246) <= 1 && abs(b - 243) <= 1 { paper += 1 }
            let mx = max(r, g, b), sat = mx > 0 ? (mx - min(r, g, b)) / mx : 0
            guard sat > 0.15 else { continue }
            saturated += 1
            let c = min(cols - 1, Int(Double(x) / cell.width)), rr = min(rows - 1, Int(Double(y) / cell.height))
            if !body[rr * cols + c] { stray += 1 }
        } }
        try expect(paper > img.width * img.height / 3, "paper pixels \(paper) of \(img.width * img.height)")
        try expect(stray == 0, "\(stray) saturated pixels off the spiders (of \(saturated) saturated)")

        // A live wall with every kind of accent: the pointer drawn through the near web (cyan rings on black),
        // accents at the full rate, the jumper's cyan fang. Light paints those cells graphite or paper.
        let live = makeSim(seed: 5, rects: [CGRect(origin: .zero, size: size)])
        for _ in 0..<300 { live.step(OceanClock.step) }
        let web = live.world.weavers.last!.web
        for k in 0..<40 {
            live.pointerMoved(Double(web.x[web.hub]) + web.outer * (0.7 - 1.4 * Double(k) / 40), Double(web.y[web.hub]) + 7)
            live.step(OceanClock.step)
        }
        var dt = darkTheme, lt = lightTheme
        dt.accentRate = 1
        lt.accentRate = 1
        let dark = paint(live, CGRect(origin: .zero, size: size), cell: cell, theme: dt)
        let light = paint(live, CGRect(origin: .zero, size: size), cell: cell, theme: lt)
        let chroma = Set(([(224, 137, 44), (224, 58, 50), (180, 74, 224), (51, 200, 204), (60, 181, 74), (49, 80, 232), (217, 193, 74),
                           (110, 230, 255), (255, 120, 60)] as [(UInt32, UInt32, UInt32)]).map { $0.0 | $0.1 << 8 | $0.2 << 16 })
        func saturation(_ v: UInt32) -> Double {
            let r = Double(v & 0xff), g = Double((v >> 8) & 0xff), b = Double((v >> 16) & 0xff), mx = max(r, g, b)
            return mx > 0 ? (mx - min(r, g, b)) / mx : 0
        }
        var accentCells = 0, ringCells = 0
        for i in 0..<dark.ink.count where dark.glyph[i] != CellCanvas.noGlyph && chroma.contains(dark.ink[i] & 0xffffff) {
            accentCells += 1
            if dark.ink[i] & 0xffffff == 110 | 230 << 8 | 255 << 16 { ringCells += 1 }
            try expect(saturation(light.ink[i]) <= 0.15, "light cell \(i) ink \(String(light.ink[i], radix: 16)) where dark has an accent")
        }
        try expect(accentCells > 10 && ringCells > 3, "accent cells on black \(accentCells), ringing \(ringCells)")
        for i in 0..<light.ink.count where light.glyph[i] != CellCanvas.noGlyph && light.block[i] >> 24 == 0 {
            // Off the bodies' blocks (silk, dew, flies, edges): graphite or a body's tinted tone, never an accent hue.
            try expect(!chroma.contains(light.ink[i] & 0xffffff), "light cell \(i) in an accent colour")
        }
        for i in 0..<light.overInk.count where light.overGlyph[i] != CellCanvas.noGlyph {
            try expect(saturation(light.overInk[i]) <= 0.15, "light dew \(i) \(String(light.overInk[i], radix: 16))")
        }
    }
    check("webCalmIsDimmer") {
        // Calm on black: the ink is dimmer (its pixels' mean luminance lower), the background and grid stay.
        var s = Settings.defaults
        s.habitat = .web
        func still(_ calm: Bool) throws -> [UInt8] {
            s.calm = calm
            return rgbBytes(try StillRenderer.render(settings: s, size: CGSize(width: 900, height: 600), scale: 1, warmup: 1,
                                                     systemIsDark: true, accent: SIMD3(0.2, 0.5, 1), seed: 5))
        }
        let normal = try still(false), calm = try still(true)
        func lum(_ p: [UInt8], _ i: Int) -> Double { 0.2126 * Double(p[i]) + 0.7152 * Double(p[i + 1]) + 0.0722 * Double(p[i + 2]) }
        var inkN = 0.0, inkC = 0.0, n = 0
        for i in stride(from: 0, to: normal.count, by: 4) where lum(normal, i) > 24 {
            inkN += lum(normal, i)
            inkC += lum(calm, i)
            n += 1
        }
        try expect(n > 2000, "ink pixels \(n)")
        try expect(inkC / Double(n) < inkN / Double(n) * 0.8, "calm ink \(inkC / Double(n)) vs \(inkN / Double(n))")
    }
}

/// A still's pixels as RGBA bytes, top row first.
private func rgbBytes(_ img: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: img.width * img.height * 4)
    let ctx = CGContext(data: &bytes, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    return bytes
}
