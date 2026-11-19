import CoreGraphics
import Foundation
import OceanKit

/// Renders a shark swimming from one screen into another, in a given
/// arrangement, as PNG frames of the region around the crossing plus an
/// overview of the whole layout.
enum Crossing {
    static func run(out dir: URL, screens: [CGRect], seed: UInt64, seconds: Double, fps: Int) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let terrain = Terrain(rects: screens)
        let cell = GridSpec.cell(forWidth: Double(screens.map(\.width).max()!))
        let kinds: [SharkKind] = [.greathammer, .classic, .mako, .tiger]
        func makeWorld() -> World {
            let w = World(sharks: kinds, rng: Rng(seed: seed))
            w.resize(terrain: terrain, cell: cell, density: 1)
            return w
        }

        // Probe: find when a shark's body straddles the shared edge.
        guard let (i, j) = terrain.neighbours.enumerated().lazy.flatMap({ i, ns in ns.map { (i, $0) } }).first,
              let door = terrain.doorway(i, j) else { throw CocoaError(.featureUnsupported) }
        let probe = makeWorld()
        var hit: (step: Int, x: Double)?
        for step in 1...(400 * 60) {
            probe.step(OceanClock.step)
            for sh in probe.sharks {
                let ys = (0..<World.sharkNodes).map { sh.nodes[$0 * 2 + 1] }
                let xs = (0..<World.sharkNodes).map { sh.nodes[$0 * 2] }
                let a = terrain.rects[i], b = terrain.rects[j]
                let lo = Double(max(a.minX, b.minX)) + 250, hi = Double(min(a.maxX, b.maxX)) - 250
                if ys.min()! < door.y - 60 && ys.max()! > door.y + 60 && xs.min()! > lo && xs.max()! < hi {
                    hit = (step, (0..<World.sharkNodes).map { sh.nodes[$0 * 2] }.reduce(0, +) / Double(World.sharkNodes))
                    break
                }
            }
            if hit != nil { break }
        }
        guard let hit else { throw CocoaError(.fileReadUnknown) }
        print("crossing at \(Double(hit.step) / 60) s, x \(Int(hit.x))")

        // Replay the same ocean up to a few seconds before the crossing.
        let world = makeWorld()
        let theme = ThemeParams.make(.defaults, systemIsDark: true, accent: .zero)
        let rec = try SceneRecorder(world: world, viewports: screens, cell: cell, scale: 1, theme: theme)
        let start = max(0, hit.step - Int(seconds * 0.45 * 60))
        for s in 0..<start {
            world.step(OceanClock.step)
            if s >= start - 180 { rec.advanceWake() }
        }

        let bounds = terrain.bounds
        let cw = 1200.0, chh = 760.0
        let crop = CGRect(x: min(max(0, hit.x - cw / 2), Double(bounds.width) - cw), y: door.y - chh / 2, width: cw, height: chh)
        let count = Int(seconds * Double(fps))
        for f in 0..<count {
            for _ in 0..<(60 / fps) { world.step(OceanClock.step) }
            let shots = try rec.capture()
            try write(compose(shots, screens: screens, region: crop, scale: 1), dir.appendingPathComponent(String(format: "f%04d.png", f)))
            if f == count / 2 {
                try write(compose(shots, screens: screens, region: bounds, scale: 0.36), dir.appendingPathComponent("overview.png"))
            }
        }
        print("wrote \(count) frames and overview.png to \(dir.path)")
    }

    /// Lay the screen images out as they sit on the desk; areas no screen
    /// covers are dark, and each screen gets a thin bezel.
    static func compose(_ shots: [CGImage], screens: [CGRect], region: CGRect, scale: CGFloat) -> CGImage {
        let w = Int(region.width * scale), h = Int(region.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = scale < 1 ? .high : .none
        ctx.setFillColor(CGColor(srgbRed: 0.09, green: 0.09, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // CoreGraphics is bottom-up; ocean space is top-down.
        func place(_ r: CGRect) -> CGRect {
            CGRect(x: (r.minX - region.minX) * scale, y: CGFloat(h) - (r.maxY - region.minY) * scale,
                   width: r.width * scale, height: r.height * scale)
        }
        for (img, r) in zip(shots, screens) { ctx.draw(img, in: place(r)) }
        ctx.setStrokeColor(CGColor(srgbRed: 0.42, green: 0.42, blue: 0.46, alpha: 1))
        ctx.setLineWidth(max(2, 6 * scale))
        for r in screens { ctx.stroke(place(r).insetBy(dx: -1.5 * scale, dy: -1.5 * scale)) }
        return ctx.makeImage()!
    }

    static func write(_ img: CGImage, _ url: URL) throws { try StillRenderer.writePNG(img, to: url) }
}
