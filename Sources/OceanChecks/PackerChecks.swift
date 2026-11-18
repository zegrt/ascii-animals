import CoreGraphics
import Foundation
import OceanKit

private struct Packed {
    let uniforms: UnsafeMutableRawPointer
    let fish: UnsafeMutablePointer<UInt8>
    let grid: GridSpec
    func hd(_ i: Int) -> SIMD4<Float> { uniforms.load(fromByteOffset: i * 16, as: SIMD4<Float>.self) }
    func shark(_ i: Int, _ slot: Int) -> SIMD4<Float> { hd(FrameLayout.sharkBase + i * FrameLayout.sharkStride + slot) }
    func event(_ i: Int) -> SIMD4<Float> { hd(FrameLayout.eventBase + i) }
    func fishCell(_ c: Int, _ r: Int) -> (present: Bool, v: UInt8, near: Bool) {
        let o = (r * grid.cols + c) * 4
        return (fish[o] == 255, fish[o + 1], fish[o + 3] == 255)
    }
    var presentCells: Int { (0..<(grid.cols * grid.rows)).filter { fish[$0 * 4] == 255 }.count }
}

private func pack(_ w: World, theme: ThemeParams = ThemeParams.make(.defaults, systemIsDark: true, accent: .zero), clear: Bool = false) -> Packed {
    let cell = GridSpec.cell(forWidth: w.width)
    let grid = GridSpec.make(viewportSize: CGSize(width: w.width, height: w.height), cell: cell)
    let u = UnsafeMutableRawPointer.allocate(byteCount: FrameLayout.bytes, alignment: 16)
    let f = UnsafeMutablePointer<UInt8>.allocate(capacity: grid.cols * grid.rows * 4)
    FramePacker.pack(world: w, grid: grid, pixelSize: CGSize(width: w.width * 2, height: w.height * 2), scale: 2,
                     theme: theme, clearWake: clear, uniforms: u, fishGrid: f)
    return Packed(uniforms: u, fish: f, grid: grid)
}

private func world(_ kinds: [SharkKind] = [.greathammer, .classic, .mako, .tiger]) -> World {
    let w = World(sharks: kinds, rng: Rng(seed: 3))
    let cell = GridSpec.cell(forWidth: 800)
    w.resize(width: 800, height: 500, cell: cell, density: 1)
    return w
}

func packerChecks() {
    check("gridSpec1800") {
        let cell = GridSpec.cell(forWidth: 1800)
        try expect(cell == CGSize(width: 13, height: 19), "cell \(cell)")
        let g = GridSpec.make(viewportSize: CGSize(width: 1800, height: 1169), cell: cell)
        try expect(g.cols == 139 && g.rows == 62, "grid \(g.cols)x\(g.rows)")
        try expect(GridSpec.cell(forWidth: 800) == CGSize(width: 8, height: 12), "800 cell \(GridSpec.cell(forWidth: 800))")
    }
    check("packerHeader") {
        let p = pack(world())
        try expect(p.hd(0) == SIMD4<Float>(800, 500, Float(p.grid.cols), Float(p.grid.rows)), "hd0 \(p.hd(0))")
        try expect(p.hd(1).x == 8 && p.hd(1).y == 12, "hd1 \(p.hd(1))")
        try expect(p.hd(2).x == 1600 && p.hd(2).z == 2, "hd2 \(p.hd(2))")
        try expect(p.hd(3).x == 4 && p.hd(3).w == 0, "hd3 \(p.hd(3))")
        try expect(pack(world(), clear: true).hd(3).w == 1, "clear flag")
    }
    check("packerSharkRecord") {
        let w = world()
        let p = pack(w)
        let s = w.sharks[3]
        try expect(p.shark(3, 0).x == Float(s.length) && p.shark(3, 0).z == Float(s.kind.index), "slot0 \(p.shark(3, 0))")
        // Arc length along the render spine is close to the body length.
        try expectClose(Double(p.shark(3, 1).w), s.length, tol: s.length * 0.1, "arc total")
        // Bounding box contains every spine node.
        let bb = p.shark(3, FrameLayout.sharkStride - 1)
        for k in 0..<World.sharkNodes {
            let n = p.shark(3, 8 + k)
            try expect(n.x >= bb.x && n.x <= bb.z && n.y >= bb.y && n.y <= bb.w, "node \(k) outside bbox")
        }
    }
    check("packerFishGrid") {
        let w = world()
        let p = pack(w)
        let alive = w.fish.filter { $0.alive && $0.x >= 0 && $0.y >= 0 && $0.x < 800 && $0.y < 500 }
        try expect(p.presentCells > 0 && p.presentCells <= alive.count, "present \(p.presentCells) alive \(alive.count)")
        let f = alive[0]
        try expect(p.fishCell(Int(f.x / 8), Int(f.y / 12)).present, "first fish's cell empty")
    }
    check("packerNearFishWins") {
        let w = world()
        let p = pack(w)
        // Any cell holding a near fish must be marked near.
        for f in w.fish where f.alive && f.depth > 0.78 && f.x >= 0 && f.y >= 0 && f.x < 800 && f.y < 500 {
            try expect(p.fishCell(Int(f.x / 8), Int(f.y / 12)).near, "near fish lost its cell")
        }
    }
    check("packerWrapsTime") {
        let w = world()
        w.time = 7200.5
        try expectClose(Double(pack(w).hd(1).z), 0.5, tol: 1e-3, "time")
    }
    check("packerCopiesEventsWithoutClearing") {
        let w = world()
        w.splash(100, 120)
        let p = pack(w)
        try expect(p.hd(3).y == 1 && p.event(0) == SIMD4<Float>(100, 120, 1, 0), "event \(p.event(0))")
        try expect(w.events.count == 1, "packer cleared events")
    }
    check("packerThemeHeader") {
        var s = Settings.defaults; s.calm = true; s.grid = false
        let p = pack(world(), theme: ThemeParams.make(s, systemIsDark: true, accent: .zero))
        try expectClose(Double(p.hd(5).y), 0.62, tol: 1e-4, "brightness")
        try expect(p.hd(5).w == 0, "grid flag")
    }
    check("themeCalmDims") {
        var s = Settings.defaults; s.calm = true
        let t = ThemeParams.make(s, systemIsDark: true, accent: .zero)
        try expect(t.brightness == 0.62 && t.accentRate == 0.35, "\(t)")
    }
    check("themeSystemFollowsAppearance") {
        var s = Settings.defaults; s.appearance = .system
        try expect(ThemeParams.make(s, systemIsDark: false, accent: .zero).light, "system light not light")
        try expect(!ThemeParams.make(s, systemIsDark: true, accent: .zero).light, "system dark is light")
        s.appearance = .light
        try expect(ThemeParams.make(s, systemIsDark: true, accent: .zero).light, "light not light")
    }
    check("themeWakeAccent") {
        var s = Settings.defaults; s.wakeColor = .accent
        try expect(ThemeParams.make(s, systemIsDark: true, accent: SIMD3(1, 0, 0)).wake == SIMD3(1, 0, 0), "accent wake")
    }
}
