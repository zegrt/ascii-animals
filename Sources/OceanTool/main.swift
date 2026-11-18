// OceanTool: offline renders.
//   OceanTool still <out.png> <W>x<H> [--scale N] [--light] [--calm] [--seed N] [--warmup S] [--sharks a,b,c]
//   OceanTool iconset <dir.iconset>
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

switch command {
case "still":
    var s = Settings.defaults
    if flag("--light") { s.appearance = .light }
    if flag("--calm") { s.calm = true }
    let seed = UInt64(option("--seed") ?? "1") ?? 1
    let warmup = Double(option("--warmup") ?? "6") ?? 6
    let scale = CGFloat(Double(option("--scale") ?? "2") ?? 2)
    if let list = option("--sharks") { s.sharks = list.split(separator: ",").compactMap { SharkKind(rawValue: String($0)) } }
    guard args.count == 2 else { fail("usage: OceanTool still <out.png> <W>x<H>") }
    let dims = args[1].split(separator: "x").compactMap { Double($0) }
    guard dims.count == 2 else { fail("bad size \(args[1])") }
    let img = try StillRenderer.render(settings: s.sanitized(), size: CGSize(width: dims[0], height: dims[1]), scale: scale,
                                       warmup: warmup, systemIsDark: true, accent: SIMD3(0.2, 0.5, 1), seed: seed)
    try StillRenderer.writePNG(img, to: URL(fileURLWithPath: args[0]))
    print("wrote \(args[0]) \(img.width)x\(img.height)")

case "iconset":
    guard args.count == 1 else { fail("usage: OceanTool iconset <dir.iconset>") }
    try IconMaker.write(to: URL(fileURLWithPath: args[0]))

case "bench":
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
