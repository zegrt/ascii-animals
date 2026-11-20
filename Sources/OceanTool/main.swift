// OceanTool: offline renders.
//   OceanTool still <out.png> <W>x<H> [--scale N] [--light] [--calm] [--seed N] [--warmup S] [--sharks a,b,c]
//                   [--habitat ocean|web] [--spiders a,b] [--live]
//   OceanTool iconset <dir.iconset>
//   OceanTool frames <dir> <W>x<H> [--seconds S] [--fps F] [--scale N] [--light] [--calm] [--seed N] [--sharks a,b]
//                    [--habitat ocean|web] [--spiders a,b] [--warmup S] [--interact]
//     --interact (Web): the parity script (WebScript.swift): the pointer drawn through the near web, a click
//     dropping a fly on it, the pointer held still near the jumper.
//   OceanTool bench [--habitat ocean|web]
//   OceanTool bench --desk [--habitat ocean|web] [--separate] [--laptop WxH] [--density D] [--seconds S]
//     CPU per second on the owner's desk (Bench.swift): both viewports drawn as the app draws them, at 30 and 15 fps.
//   OceanTool meadow-air <out.png> <W>x<H> [--seed N] [--seconds S] [--under sketch.png] [--stir]
//     The Meadow's planting and air (MeadowAir.swift): the port's flowers outlined over the sketch's own render at the
//     same seed and size, beside the port's air field.
//   OceanTool bench --digest [--separate] [--laptop WxH] [--frames N]
//     A fingerprint of every Web canvas over a scripted run on the desk: unchanged digest, unchanged output.
// A Web still is the original's ?still=1 (settled), unless --live: then the live wall after the warm-up.
import CoreGraphics
import Foundation
import ImageIO
import OceanKit

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }
    return false
}
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

guard let command = args.first else { fail("usage: OceanTool still|iconset ...") }
args.removeFirst()

/// `--habitat` and `--spiders` into `s`.
func habitatOptions(_ s: inout Settings) {
    if let h = option("--habitat") {
        guard let kind = HabitatKind(rawValue: h) else { fail("unknown habitat \(h)") }
        s.habitat = kind
    }
    if let list = option("--spiders") { s.webSpiders = list.split(separator: ",").compactMap { SpiderKind(rawValue: String($0)) } }
}

switch command {
case "still":
    var s = Settings.defaults
    if flag("--light") { s.appearance = .light }
    if flag("--calm") { s.calm = true }
    let seed = UInt64(option("--seed") ?? "1") ?? 1
    let warmup = Double(option("--warmup") ?? "6") ?? 6
    let scale = CGFloat(Double(option("--scale") ?? "2") ?? 2)
    if let list = option("--sharks") { s.sharks = list.split(separator: ",").compactMap { SharkKind(rawValue: String($0)) } }
    habitatOptions(&s)
    let live = flag("--live")
    guard args.count == 2 else { fail("usage: OceanTool still <out.png> <W>x<H>") }
    let dims = args[1].split(separator: "x").compactMap { Double($0) }
    guard dims.count == 2 else { fail("bad size \(args[1])") }
    let img = try StillRenderer.render(settings: s.sanitized(), size: CGSize(width: dims[0], height: dims[1]), scale: scale,
                                       warmup: warmup, systemIsDark: true, accent: SIMD3(0.2, 0.5, 1), seed: seed,
                                       settle: s.habitat != .ocean && !live)
    try StillRenderer.writePNG(img, to: URL(fileURLWithPath: args[0]))
    print("wrote \(args[0]) \(img.width)x\(img.height)")

case "frames":
    var s = Settings.defaults
    if flag("--light") { s.appearance = .light }
    if flag("--calm") { s.calm = true }
    let seed = UInt64(option("--seed") ?? "1") ?? 1
    let seconds = Double(option("--seconds") ?? "6") ?? 6
    let fps = Int(option("--fps") ?? "20") ?? 20
    let frameWarmup = Double(option("--warmup") ?? "8") ?? 8
    let interact = flag("--interact")
    let scale = CGFloat(Double(option("--scale") ?? "1") ?? 1)
    if let list = option("--sharks") { s.sharks = list.split(separator: ",").compactMap { SharkKind(rawValue: String($0)) } }
    habitatOptions(&s)
    guard args.count == 2, 60 % fps == 0 else { fail("usage: OceanTool frames <dir> <W>x<H> [--fps 10|12|15|20|30|60]") }
    let dims = args[1].split(separator: "x").compactMap { Double($0) }
    guard dims.count == 2 else { fail("bad size \(args[1])") }
    let dir = URL(fileURLWithPath: args[0], isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let rec = try FrameRecorder(settings: s.sanitized(), size: CGSize(width: dims[0], height: dims[1]), scale: scale, seed: seed,
                                warmup: frameWarmup)
    let count = Int(seconds * Double(fps))
    let script = interact ? (rec.habitat as? WebSim).map { WebScript(world: $0.world) } : nil
    if interact && script == nil { fail("--interact needs --habitat web") }
    for i in 0..<count {
        let img = try rec.next(steps: 60 / fps) { script?.step() }
        try StillRenderer.writePNG(img, to: dir.appendingPathComponent(String(format: "f%04d.png", i)))
    }
    if let script { for e in script.events { print(e) } }
    print("wrote \(count) frames to \(dir.path)")

case "crossing":
    // The user's desk: 2560x1440 monitor above an 1800x1169 laptop, offset 375 pt.
    guard args.count == 1 else { fail("usage: OceanTool crossing <dir> [--seed N]") }
    let seed = UInt64(option("--seed") ?? "5") ?? 5
    try Crossing.run(out: URL(fileURLWithPath: args[0], isDirectory: true),
                     screens: [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1800, height: 1169)],
                     seed: seed, seconds: 9, fps: 15)

case "meadow-air":
    let seed = MeadowRandom.seed(Double(option("--seed") ?? "4242") ?? 4242)
    let seconds = Double(option("--seconds") ?? "3") ?? 3
    let under = option("--under").map { URL(fileURLWithPath: $0) }
    let stir = flag("--stir")
    guard args.count == 2 else { fail("usage: OceanTool meadow-air <out.png> <W>x<H> [--seed N] [--seconds S] [--under sketch.png] [--stir]") }
    let dims = args[1].split(separator: "x").compactMap { Double($0) }
    guard dims.count == 2, dims.allSatisfy({ $0.isFinite && $0 >= 16 && $0 <= 8192 }) else { fail("bad size \(args[1])") }
    guard seconds.isFinite && seconds >= 0 && seconds <= 600 else { fail("--seconds must be 0…600") }
    try MeadowAir.run(out: URL(fileURLWithPath: args[0]), size: CGSize(width: dims[0], height: dims[1]), seed: seed,
                      seconds: seconds, under: under, stir: stir)

case "iconset":
    guard args.count == 1 else { fail("usage: OceanTool iconset <dir.iconset>") }
    try IconMaker.write(to: URL(fileURLWithPath: args[0]))

case "bench":
    var s = Settings.defaults
    habitatOptions(&s)
    let separate = flag("--separate")
    let laptopDims = (option("--laptop") ?? "1800x1169").split(separator: "x").compactMap { Double($0) }
    guard laptopDims.count == 2 else { fail("bad --laptop size") }
    let laptop = CGSize(width: laptopDims[0], height: laptopDims[1])
    if let d = option("--density"), let v = Double(d) { s.fishDensity = v }
    if flag("--desk") {
        try Bench.run(s.sanitized(), laptop: laptop, separate: separate, seconds: Double(option("--seconds") ?? "20") ?? 20)
        break
    }
    if flag("--digest") {
        s.habitat = .web
        Bench.digest(s, laptop: laptop, separate: separate, frames: Int(option("--frames") ?? "900") ?? 900)
        break
    }
    if s.habitat == .web {
        // Simulation per step and painting per frame (one 1800 x 1169 screen, its cell canvas), the demo wall.
        let size = CGSize(width: 1800, height: 1169)
        let cell = GridSpec.cell(forWidth: 1800)
        let grid = GridSpec.make(viewportSize: size, cell: cell)
        let sim = WebSim(settings: s.sanitized(), seed: 1)
        sim.layout(terrain: .single(width: 1800, height: 1169), cell: cell, settings: s)
        let canvas = CellCanvas(cols: grid.cols, rows: grid.rows)
        let viewport = CGRect(origin: .zero, size: size)
        for _ in 0..<600 { sim.step(OceanClock.step) }
        for light in [false, true] {
            var ts = s
            ts.appearance = light ? .light : .dark
            let theme = ThemeParams.make(ts, systemIsDark: true, accent: .zero)
            var stepT = 0.0, paintT = 0.0, worstPaint = 0.0
            let frames = 1800
            for _ in 0..<frames {
                var t0 = DispatchTime.now().uptimeNanoseconds
                sim.step(OceanClock.step)
                stepT += Double(DispatchTime.now().uptimeNanoseconds - t0)
                t0 = DispatchTime.now().uptimeNanoseconds
                canvas.clear()
                sim.paint(viewport: viewport, grid: grid, theme: theme, into: canvas)
                let p = Double(DispatchTime.now().uptimeNanoseconds - t0)
                paintT += p
                worstPaint = max(worstPaint, p)
            }
            print(String(format: "web %@  webs %d  weavers %d  flies %d  sim %.1f µs/step = %.3f ms per simulated second (%.2f%% of a core at 60 steps/s)  paint %.3f ms/frame (worst %.3f; clear included)  grid %dx%d",
                         light ? "light" : "dark", sim.world.webs.count, sim.world.weavers.count, sim.world.swarm.flies.count,
                         stepT / Double(frames) / 1000, stepT / Double(frames) * 60 / 1e6, stepT / Double(frames) * 60 / 1e7, paintT / Double(frames) / 1e6, worstPaint / 1e6,
                         grid.cols, grid.rows))
        }
        break
    }
    // Simulation + packing cost per simulated second at the built-in display's size.
    let w = World(sharks: Settings.defaults.sharks, rng: Rng(seed: 1))
    let cell = GridSpec.cell(forWidth: 1800)
    w.resize(width: 1800, height: 1169, cell: cell, density: 1)
    let grid = GridSpec.make(viewportSize: CGSize(width: 1800, height: 1169), cell: cell)
    let u = UnsafeMutableRawPointer.allocate(byteCount: FrameLayout.bytes, alignment: 16)
    let g = UnsafeMutablePointer<UInt8>.allocate(capacity: grid.cols * grid.rows * 4)
    let theme = ThemeParams.make(.defaults, systemIsDark: true, accent: .zero)
    for _ in 0..<600 { w.step(OceanClock.step) }
    var t0 = Date()
    for _ in 0..<1800 { w.step(OceanClock.step) }
    let sim = Date().timeIntervalSince(t0) / 30
    t0 = Date()
    for _ in 0..<450 { FramePacker.pack(world: w, grid: grid, pixelSize: CGSize(width: 3600, height: 2338), scale: 2, theme: theme, clearWake: false, uniforms: u, fishGrid: g) }
    let packPerFrame = Date().timeIntervalSince(t0) / 450
    print(String(format: "fish %d  sim %.2f ms per simulated second (%.2f%% of a core)  pack %.3f ms/frame", w.fish.count, sim * 1000, sim * 100, packPerFrame * 1000))

default:
    fail("unknown command \(command)")
}
