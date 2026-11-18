import CoreGraphics
import Foundation
import OceanKit
import Metal
import simd

private func packShared(_ w: World, viewport: CGRect, after: Int = 0) -> (u: UnsafeMutableRawPointer, fish: UnsafeMutablePointer<UInt8>, grid: GridSpec, last: Int) {
    let grid = GridSpec.make(viewportSize: viewport.size, cell: CGSize(width: 13, height: 19))
    let u = UnsafeMutableRawPointer.allocate(byteCount: FrameLayout.bytes, alignment: 16)
    let f = UnsafeMutablePointer<UInt8>.allocate(capacity: grid.cols * grid.rows * 4)
    let last = FramePacker.pack(world: w, viewport: viewport, afterEventSeq: after, grid: grid,
                                pixelSize: viewport.size, scale: 1, theme: ThemeParams.make(.defaults, systemIsDark: true, accent: .zero),
                                clearWake: false, uniforms: u, fishGrid: f)
    return (u, f, grid, last)
}

private func hd(_ u: UnsafeMutableRawPointer, _ i: Int) -> SIMD4<Float> { u.load(fromByteOffset: i * 16, as: SIMD4<Float>.self) }

func sceneChecks() {
    check("clockIgnoresOlder") {
        var c = OceanClock(); _ = c.advance(to: 10, speed: 1)
        try expect(c.advance(to: 9.5, speed: 1) == 0, "older timestamp stepped")
        try expect(c.advance(to: 10 + 1.0 / 60, speed: 1) == 1, "did not resume from the newest timestamp")
    }
    check("clockTwoLinks") {
        var c = OceanClock(); _ = c.advance(to: 0, speed: 1)
        var stamps = (1...120).map { Double($0) / 120 } + (1...100).map { Double($0) / 100 + 0.0003 }
        stamps.sort()
        // Interleave as two links would fire, slightly out of order sometimes.
        var steps = 0
        for (i, t) in stamps.enumerated() { steps += c.advance(to: i % 7 == 3 ? t - 0.004 : t, speed: 1) }
        try expect(abs(steps - 60) <= 1, "two links gave \(steps) steps in 1 s")
    }

    let world = World(sharks: [.greathammer, .classic, .mako, .tiger], rng: Rng(seed: 5))
    world.resize(habitat: Habitat(rects: [userMonitor, userLaptop]), cell: CGSize(width: 13, height: 19), density: 1)

    check("packerViewportOffset") {
        let p = packShared(world, viewport: userLaptop)
        try expect(hd(p.u, 0).x == 1800 && hd(p.u, 0).y == 1169, "viewport size \(hd(p.u, 0))")
        let n = Int(hd(p.u, 3).x)
        for i in 0..<n {
            let bb = hd(p.u, FrameLayout.sharkBase + i * FrameLayout.sharkStride + 28)
            try expect(bb.z > 0 && bb.w > 0 && bb.x < 1800 && bb.y < 1169, "packed shark \(i) not in the laptop's local space: \(bb)")
        }
    }
    check("packerCullsToEight") {
        let w = World(sharks: Array(repeating: .classic, count: 8), rng: Rng(seed: 2))
        let r = { (y: Double) in CGRect(x: 0, y: y, width: 900, height: 600) }
        w.resize(habitat: Habitat(rects: [r(0), r(600)]), cell: CGSize(width: 8, height: 12), density: 1)
        // A viewport over both rects sees all 16 sharks; only 8 may be packed.
        let p = packShared(w, viewport: CGRect(x: 0, y: 0, width: 900, height: 1200))
        try expect(w.sharks.count == 16 && Int(hd(p.u, 3).x) == 8, "packed \(hd(p.u, 3).x) of \(w.sharks.count)")
    }
    check("packerEventsAfterSeq") {
        let w = World(sharks: [], rng: Rng(seed: 3))
        w.resize(habitat: Habitat(rects: [userMonitor, userLaptop]), cell: CGSize(width: 13, height: 19), density: 1)
        w.splash(1000, 2000) // laptop
        w.splash(100, 100)   // monitor
        let laptop = packShared(w, viewport: userLaptop)
        try expect(Int(hd(laptop.u, 3).y) == 1, "laptop events \(hd(laptop.u, 3).y)")
        let e = hd(laptop.u, FrameLayout.eventBase)
        try expect(e.x == 625 && e.y == 560, "event not in laptop space: \(e)")
        try expect(laptop.last == w.eventSeq, "returned seq \(laptop.last)")
        let again = packShared(w, viewport: userLaptop, after: laptop.last)
        try expect(Int(hd(again.u, 3).y) == 0, "old events packed again")
    }
    check("packerFishOutsideViewportAbsent") {
        let p = packShared(world, viewport: userLaptop)
        let inLaptop = world.fish.filter { $0.alive && userLaptop.contains(CGPoint(x: $0.x, y: $0.y)) }.count
        var present = 0
        for i in 0..<(p.grid.cols * p.grid.rows) where p.fish[i * 4] == 255 { present += 1 }
        try expect(present > 0 && present <= inLaptop, "present \(present), fish in laptop \(inLaptop)")
    }

    let laptopGlobal = ScreenInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), scale: 2)
    let monitorGlobal = ScreenInfo(id: 3, frame: CGRect(x: -375, y: -1440, width: 2560, height: 1440), scale: 1)
    check("userArrangementLayout") {
        let plans = SceneLayout.plan([laptopGlobal, monitorGlobal], shared: true)
        try expect(plans.count == 1, "plans \(plans.count)")
        let p = plans[0]
        try expect(p.originInGlobal == CGPoint(x: -375, y: -1440), "origin \(p.originInGlobal)")
        let byID = Dictionary(uniqueKeysWithValues: p.viewports.map { ($0.screenID, $0.rect) })
        try expect(byID[3] == userMonitor && byID[1] == userLaptop, "viewports \(byID)")
        try expect(p.habitat.neighbours.allSatisfy { !$0.isEmpty }, "screens not adjacent")
        try expect(p.cell == GridSpec.cell(forWidth: 2560), "cell \(p.cell)")
    }
    check("separateLayoutTwoPlans") {
        let plans = SceneLayout.plan([laptopGlobal, monitorGlobal], shared: false)
        try expect(plans.count == 2, "plans \(plans.count)")
        try expect(plans.allSatisfy { $0.viewports.count == 1 && $0.viewports[0].rect.origin == .zero && $0.habitat.rects.count == 1 }, "\(plans)")
        try expect(plans[0].cell == GridSpec.cell(forWidth: 1800), "laptop keeps its own cell size")
    }
    check("singleScreenLayoutSameInBothModes") {
        try expect(SceneLayout.plan([laptopGlobal], shared: true) == SceneLayout.plan([laptopGlobal], shared: false), "modes differ for one screen")
    }
}

func sharedRenderChecks() {
    check("sharedRenderSharkAcrossSeam") {
        guard let device = MTLCreateSystemDefaultDevice() else { throw CheckFailure(detail: "no Metal") }
        let renderer = try OceanRenderer(device: device)
        let cell = GridSpec.cell(forWidth: 2560)
        let w = World(sharks: [.greathammer, .classic, .mako, .tiger], rng: Rng(seed: 5))
        w.resize(habitat: Habitat(rects: [userMonitor, userLaptop]), cell: cell, density: 1)
        // Swim until some shark's body straddles the seam (y = 1440) over the laptop's span.
        var straddler: Shark?
        for _ in 0..<(240 * 60) {
            w.step(1.0 / 60)
            straddler = w.sharks.first { sh in
                let ys = stride(from: 0, to: World.sharkNodes, by: 1).map { sh.nodes[$0 * 2 + 1] }
                let xs = stride(from: 0, to: World.sharkNodes, by: 1).map { sh.nodes[$0 * 2] }
                return ys.min()! < 1400 && ys.max()! > 1480 && xs.allSatisfy { $0 > 450 && $0 < 2100 }
            }
            if straddler != nil { break }
        }
        guard let sh = straddler else { throw CheckFailure(detail: "no shark crossed the seam in 240 s") }
        let theme = ThemeParams.make(.defaults, systemIsDark: true, accent: .zero)
        let top = pixelsOf(try StillRenderer.snapshot(w, viewport: userMonitor, cell: cell, theme: theme, scale: 1, renderer: renderer))
        let bottom = pixelsOf(try StillRenderer.snapshot(w, viewport: userLaptop, cell: cell, theme: theme, scale: 1, renderer: renderer))
        let xs = stride(from: 0, to: World.sharkNodes, by: 1).map { sh.nodes[$0 * 2] }
        let x0 = Int(xs.min()!) - 40, x1 = Int(xs.max()!) + 40
        func ink(_ p: [UInt8], width: Int, rows: Range<Int>, xOffset: Int) -> Int {
            var n = 0
            for y in rows { for x in max(0, x0 - xOffset)..<min(width, x1 - xOffset) {
                let i = (y * width + x) * 4
                if Int(p[i]) + Int(p[i + 1]) + Int(p[i + 2]) > 150 { n += 1 }
            } }
            return n
        }
        let above = ink(top, width: 2560, rows: (1440 - 60)..<1440, xOffset: 0)
        let below = ink(bottom, width: 1800, rows: 0..<60, xOffset: 375)
        try expect(above > 50 && below > 50, "ink above seam \(above), below \(below)")
    }
}

private func pixelsOf(_ img: CGImage) -> [UInt8] {
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buf
}
