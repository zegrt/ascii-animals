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
    // Values printed by running the original math.ts under node (scratchpad port/math-ref.mjs).
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
    // The original web.ts on the same random stream (scratchpad port/web-ref.mjs): generated, built,
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
}
