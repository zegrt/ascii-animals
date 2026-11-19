import CoreGraphics
import Foundation

// Port of world.ts from ascii-spiders by @stackedlol (MIT), commit 89a7721, with the pointer and click
// handling of engine.ts. See docs/reference/web-port-notes.md for what differs and why.

/**
 * The spiders' wall: orb webs strung over the whole page wherever there is room, the weavers that live on
 * them, the flies they catch, and a jumping spider loose on the wall.
 *
 * Webs: no grid. They come in mixed sizes, biggest first, and each goes into the emptiest part of the page
 * left (best of many random candidates, by clearance from the webs already there), so together they cover
 * it without piling up. Frames are irregular polygons at odd angles, and run off the edges. One web always
 * hangs in the bottom-left. Spiders take the first webs; the smaller ones left over are old and empty, and
 * fainter.
 *
 * Move through a web to pluck it: the silk rings, and its spider turns toward the tug. A fly dropped on
 * silk sticks there and the spider comes for it.
 */

public struct WebPointer {
    public var x = 0.0
    public var y = 0.0
    /// Where it was last step, so a move plucks the silk it crossed.
    public var lx = 0.0
    public var ly = 0.0
    public var active = false
    public init() {}
}

/// A spark where the jumping spider took a fly.
public struct Heat {
    public var x: Double
    public var y: Double
    public var life: Double
}

private struct Site {
    var x: Double
    var y: Double
    var R: Double
}

/// How far a web's frame can reach from its hub, in radii: anchors sit at up to R · 1.3 · 1.15 (web.ts).
let FRAME_REACH = 1.5

/// `clamp`, except an empty range gives its middle (a screen too small for the margin).
@inline(__always) func fitClamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    lo <= hi ? clamp(v, lo, hi) : (lo + hi) / 2
}

/// One screen of the terrain, in Doubles.
public struct Screen {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double
    public var w: Double { maxX - minX }
    public var h: Double { maxY - minY }
    public var midX: Double { (minX + maxX) / 2 }
    public var midY: Double { (minY + maxY) / 2 }
    init(_ r: CGRect) { minX = Double(r.minX); minY = Double(r.minY); maxX = Double(r.maxX); maxY = Double(r.maxY) }
}

public final class WebWorld {
    public private(set) var time = 0.0
    public private(set) var width = 0.0
    public private(set) var height = 0.0
    /// The ASCII cell, so webs space their threads in glyphs.
    public private(set) var cw = 12.0
    public private(set) var ch = 17.0
    public private(set) var webs: [OrbWeb] = []
    public private(set) var weavers: [Weaver] = []
    public private(set) var jumper: Jumper? = nil
    public private(set) lazy var swarm = Swarm(self)
    public private(set) var heat: [Heat] = []
    public var pointer = WebPointer()
    private let spiders: [SpiderKind]
    /// A roster was asked for: every spider in it gets a web. (The demo page's default cast is not one.)
    private let cast: Bool
    /// `options.flies`: nil is the original's default count, 0 none.
    private let flies: Int?
    private let jumperOn: Bool
    /// `options.corner`: the demo page keeps the default, the first web always in the bottom-left.
    private let corner = true
    /// `Math.random()` for the whole wall.
    public let random: WebRandom
    public private(set) var terrain = Terrain.single(width: 0, height: 0)
    /// One screen: the original's W × H page, every formula verbatim. Several: see web-port-notes.md.
    public private(set) var single = true
    public private(set) var screens: [Screen] = []
    private var screenArea = 0.0
    private var wallLength = 0.0

    public init(spiders: [SpiderKind], flies: Bool, jumper: Bool, random: WebRandom) {
        self.spiders = spiders
        cast = spiders != SpiderKind.defaultCast
        self.flies = flies ? nil : 0
        jumperOn = jumper
        self.random = random
    }

    /// Lay the wall out over the terrain. `settled` is for a single still frame: every web finished.
    public func layout(terrain: Terrain, cell: CGSize, settled: Bool) {
        self.terrain = terrain
        screens = terrain.rects.map(Screen.init)
        single = screens.count <= 1
        screenArea = screens.reduce(0) { $0 + $1.w * $1.h }
        wallLength = terrain.edges.reduce(0) { $0 + $1.length }
        let W = Double(terrain.bounds.width)
        let H = Double(terrain.bounds.height)
        width = W
        height = H
        cw = Double(cell.width)
        ch = Double(cell.height)
        // The engine lays nothing out for an empty canvas.
        if screens.isEmpty || W < 1 || H < 1 {
            webs = []
            weavers = []
            jumper = nil
            swarm.populate(0)
            return
        }
        // Several screens: areas add up, and sizes are capped by the biggest screen, as the page caps them.
        let area = single ? W * H : screenArea
        let big = screens.max { $0.w * $0.h < $1.w * $1.h }
        let ms = single ? min(W, H) : min(big?.w ?? 0, big?.h ?? 0)
        let count = Int(clamp(mathRound(area / 215_000), 2, 10))
        let room = count + (corner ? 1 : 0)
        let total = max(0, cast ? max(spiders.count, room) : room)
        let roster = Array(spiders.prefix(total))
        let free = total - (corner && total > 0 ? 1 : 0)
        // Sizes from the area each free web would get, never more than the canvas can hold (a lone web keeps its
        // frame inside it).
        let base = min((area / Double(max(1, free))).squareRoot() * 0.5, ms * (free <= 1 ? 0.34 : 0.45))
        var sizes: [Double] = []
        for i in 0..<max(0, free) {
            sizes.append(base * lerp(1.3, 0.72, free > 1 ? Double(i) / Double(free - 1) : 0) * random.range(0.92, 1.08))
        }
        // One always hangs in the bottom-left; the rest find their own room around it.
        var placed: [Site] = []
        if corner && total > 0 {
            if single {
                let x = random.range(0.12, 0.2) * W
                let y = random.range(0.72, 0.8) * H
                placed.append(Site(x: x, y: y, R: base * random.range(0.92, 1.02)))
            } else if let r = screens.max(by: { ($0.maxY, -$0.minX) < ($1.maxY, -$1.minX) }) {
                // Several screens: the bottom-left corner of the lowest screen (leftmost of equals), and it fits.
                let x = r.minX + random.range(0.12, 0.2) * r.w
                let y = r.minY + random.range(0.72, 0.8) * r.h
                let R = fit(base * random.range(0.92, 1.02), r)
                placed.append(Site(x: fitClamp(x, r.minX + R * FRAME_REACH, r.maxX - R * FRAME_REACH),
                                   y: fitClamp(y, r.minY + R * FRAME_REACH, r.maxY - R * FRAME_REACH), R: R))
            }
        }
        // (The original also keeps clear of a floating nav bar at the top centre of a full page: a web-page
        // specific, dropped. It skips candidates only after drawing them, so the random stream is unchanged.)
        for size in sizes {
            var best: (site: Site, score: Double)? = nil
            for _ in 0..<300 {
                var R = size
                var x: Double
                var y: Double
                var score: Double
                if single {
                    x = random.range(0.06, 0.94) * W
                    y = random.range(0.08, 0.94) * H
                    score = min(x, W - x, y, H - y) / (R * 0.55) // the page edge counts, softly
                } else {
                    // Several screens: drawn inside one screen (by area), and the whole frame fits on it.
                    let r = screenByArea()
                    R = fit(size, r)
                    x = r.minX + random.range(0.06, 0.94) * r.w
                    y = r.minY + random.range(0.08, 0.94) * r.h
                    x = fitClamp(x, r.minX + R * FRAME_REACH, r.maxX - R * FRAME_REACH)
                    y = fitClamp(y, r.minY + R * FRAME_REACH, r.maxY - R * FRAME_REACH)
                    score = min(x - r.minX, r.maxX - x, y - r.minY, r.maxY - y) / (R * 0.55)
                }
                for p in placed { score = min(score, hypot(x - p.x, y - p.y) / (p.R + R)) }
                if best == nil || score > best!.score { best = (Site(x: x, y: y, R: R), score) }
            }
            if let best { placed.append(best.site) }
        }

        webs = []
        weavers = []
        for (i, p) in placed.enumerated() {
            let kind: SpiderKind? = i < roster.count ? roster[i] : nil
            // Empty webs are old and faint, unless the wall has no spiders at all to set them off.
            let depth = kind != nil || roster.isEmpty ? random.range(0.78, 1) : random.range(0.5, 0.6)
            let web = OrbWeb(cx: p.x, cy: p.y, radius: p.R, depth: depth, cw: cw, ch: ch, stab: kind == .argiope, random: random)
            webs.append(web)
            // Spiders vary a little with their webs, not as much.
            if let kind { weavers.append(Weaver(self, web, kind, lerp(base, p.R, 0.35) * 0.31 * 1)) } else { web.buildInstant() }
        }
        webs = stableSorted(webs) { $0.depth < $1.depth }
        // Far to near, so nearer spiders draw over farther ones.
        let home = corner ? weavers.first : nil
        weavers = stableSorted(weavers) { $0.web.depth < $1.web.depth }

        // (options.build is off on the demo page.)
        // Most are home on finished webs; one is partway round its capture spiral, one has only just begun.
        // The bottom-left one always starts at home, so it's there from the first frame.
        let busy = weavers.filter { $0 !== home }
        for w in weavers {
            let route = w.web.route.count
            let k = busy.count - 1 - (busy.firstIndex { $0 === w } ?? -1) // 0 is the nearest
            if !settled && w !== home && k == 1 {
                w.startAt(Int(mathRound(Double(w.web.spiralStart) + Double(route - w.web.spiralStart) * 0.3)))
            } else if !settled && w !== home && k == 3 {
                w.startAt(Int(mathRound(Double(w.web.spiralStart) * 0.35)))
            } else { w.startAt(route) }
        }

        jumper = nil
        if jumperOn {
            let j = Jumper(self, clamp(ms * 0.1, 50, 104))
            jumper = j
            if single { j.place(W * 0.62, H * 0.74) } else if let r = big { j.place(r.minX + r.w * 0.62, r.minY + r.h * 0.74) }
        }

        swarm.populate(max(0, Int(mathRound(Double(flies ?? Int(clamp(mathRound(area / 140_000), 5, 12)))))))
        // An opening catch: one fly is headed for the near web.
        if !settled, let near = weavers.last, let f = swarm.flies.first {
            let web = near.web
            let a = random.range(-0.6, 0.6) + (random.unit() < 0.5 ? 0 : Double.pi)
            let r = web.rin + (web.radius * 0.86 - web.rin) * 0.55
            let aim = Vec(x: web.cx + cos(a) * r, y: web.cy + sin(a) * r)
            f.aim = aim
            f.aimWeb = web
            let s = single ? Screen(CGRect(x: 0, y: 0, width: W, height: H)) : screen(near: web.home.x, web.home.y)
            f.x = clamp(web.cx + cos(a) * web.outer * 1.25, s.minX + 10, s.maxX - 10)
            f.ox = f.x
            f.y = clamp(web.cy + sin(a) * web.outer * 1.25, s.minY + 10, s.maxY - 10)
            f.oy = f.y
            f.h = atan2(aim.y - f.y, aim.x - f.x)
        }
        if settled { for fly in swarm.flies { fly.mode = .rest; fly.timer = 99 } }
    }

    public func step(_ dt: Double) {
        time += dt
        let p = pointer
        if p.active {
            let vx = p.x - p.lx
            let vy = p.y - p.ly
            if vx != 0 || vy != 0 {
                for web in webs {
                    let touched = web.pluck(p.x, p.y, vx, vy, cw * 1.15)
                    if touched > 0.2 { weavers.first { $0.web === web }?.feel(p.x, p.y, touched) }
                }
            }
        }
        pointer.lx = pointer.x
        pointer.ly = pointer.y
        for w in weavers { w.update(dt) }
        jumper?.update(dt)
        swarm.update(dt)
        for w in weavers { w.weigh() }
        for web in webs { web.step(time) }
        for i in heat.indices { heat[i].life -= dt * 1.4 }
        heat.removeAll { !($0.life > 0) }
    }

    /// Drop a fly at (x, y): onto silk, it sticks there.
    @discardableResult
    public func release(x: Double, y: Double) -> Fly {
        swarm.release(x, y)
    }

    /// A spark of glyphs where a fly was taken.
    public func burst(x: Double, y: Double) {
        for _ in 0..<6 {
            let hx = x + random.range(-1.6, 1.6) * cw
            let hy = y + random.range(-1.2, 1.2) * ch
            heat.append(Heat(x: hx, y: hy, life: random.range(0.8, 1.3)))
        }
    }

    // ── the pointer, as engine.ts feeds it ──

    /// The pointer moved to (x, y): it plucks the silk it crosses while it is over the terrain.
    public func pointerMoved(x: Double, y: Double) {
        let inside = terrain.contains(SIMD2(x, y))
        if !pointer.active { pointer.lx = x; pointer.ly = y }
        pointer.x = x
        pointer.y = y
        pointer.active = inside
    }

    public func pointerLeft() { pointer.active = false }

    /// A click: over the terrain, it drops a fly there. (The engine also ignores clicks on a still wall.)
    @discardableResult
    public func pointerDown(x: Double, y: Double) -> Fly? {
        terrain.contains(SIMD2(x, y)) ? release(x: x, y: y) : nil
    }

    // ── platform: a terrain of several screens (never used for one screen) ──

    /// A screen picked at random, in proportion to its area: one draw.
    func screenByArea() -> Screen {
        var u = random.unit() * screenArea
        for s in screens {
            u -= s.w * s.h
            if u < 0 { return s }
        }
        return screens[screens.count - 1]
    }

    /// The screen containing (x, y), else the nearest.
    func screen(near x: Double, _ y: Double) -> Screen { screens[terrain.rectIndex(near: SIMD2(x, y))] }

    /// A web's radius, capped so its whole frame fits on screen `r`.
    private func fit(_ R: Double, _ r: Screen) -> Double { min(R, min(r.w, r.h) / (2 * FRAME_REACH)) }

    /// A real wall (an edge not shared with another screen) picked in proportion to its length: one draw.
    func wallByLength() -> Terrain.Edge {
        var u = random.unit() * wallLength
        for e in terrain.edges {
            u -= e.length
            if u < 0 { return e }
        }
        return terrain.edges[terrain.edges.count - 1]
    }

    /// Whether the square of half-side `m` round (x, y) lies on the screens: at least `m` from every wall,
    /// while a shared edge between touching screens is no wall at all.
    func clear(_ x: Double, _ y: Double, _ m: Double) -> Bool {
        var covered = 0.0
        for s in screens {
            let w = min(x + m, s.maxX) - max(x - m, s.minX)
            let h = min(y + m, s.maxY) - max(y - m, s.minY)
            if w > 0 && h > 0 { covered += w * h }
        }
        return covered >= 4 * m * m * (1 - 1e-9)
    }

    /// The jumper's clamp: (x, y) if it is `margin` clear of the walls, else it slides along the wall (keeping
    /// the move in x, or in y), else it stays where it was. Only a start that is itself not clear (a fresh
    /// layout) is pulled into the screen it is on.
    func inside(_ x: Double, _ y: Double, from px: Double, _ py: Double, margin m: Double) -> Vec {
        if clear(x, y, m) { return Vec(x: x, y: y) }
        if clear(x, py, m) { return Vec(x: x, y: py) }
        if clear(px, y, m) { return Vec(x: px, y: y) }
        if clear(px, py, m) { return Vec(x: px, y: py) }
        let s = screen(near: px, py)
        return Vec(x: clamp(x, s.minX + m, s.maxX - m), y: clamp(y, s.minY + m, s.maxY - m))
    }

    /// The flies' clamp: (x, y) if it is within `slack` of a screen, else pulled back to within `slack` of the
    /// screen it came from (the original lets flies 20 px off the page).
    func loose(_ x: Double, _ y: Double, from px: Double, _ py: Double, slack: Double) -> Vec {
        for s in screens where x >= s.minX - slack && x <= s.maxX + slack && y >= s.minY - slack && y <= s.maxY + slack {
            return Vec(x: x, y: y)
        }
        let s = screen(near: px, py)
        return Vec(x: clamp(x, s.minX - slack, s.maxX + slack), y: clamp(y, s.minY - slack, s.maxY + slack))
    }

    /// Somewhere for the jumper to wander to: on any screen if the way there is clear, else on its own.
    func wanderGoal(from x: Double, _ y: Double, margin m: Double) -> Vec {
        let r = screenByArea()
        let g = Vec(x: r.minX + random.range(m, r.w - m), y: r.minY + random.range(m, r.h - m))
        var open = true
        for i in 1...16 {
            let t = Double(i) / 16
            if !clear(x + (g.x - x) * t, y + (g.y - y) * t, m * 0.5) { open = false; break }
        }
        if open { return g }
        let s = screen(near: x, y)
        return Vec(x: s.minX + random.range(m, s.w - m), y: s.minY + random.range(m, s.h - m))
    }
}
