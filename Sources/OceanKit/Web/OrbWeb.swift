import Foundation

// Port of web.ts from ascii-spiders by @stackedlol (MIT), commit 89a7721.
// See docs/reference/web-port-notes.md for what differs and why.

/**
 * An orb web as a Verlet mesh of silk.
 *
 * Geometry follows a real orb: mooring lines out to unseen twigs, a frame polygon, radials from the hub to
 * the frame, a small hub mesh, a free zone, then the sticky capture spiral, laid as straight chords between
 * radials. Argiope webs add a stabilimentum, the zigzag ribbon above and below the hub.
 *
 * Silk is a one-sided constraint: a thread resists stretching but goes slack instead of pushing, so the
 * pre-tensioned web hangs, sags a touch under gravity and the spider's weight, rings when plucked, and
 * snaps when pulled too far.
 *
 * `route` is the order the spider builds it in, node to node: frame, then radials in alternating order
 * (each laid out from the hub and walked back), hub rings, the capture spiral from the outside in, and
 * the stabilimentum. Walking the route backwards is how the spider eats the web before rebuilding.
 */

public let MOOR = 1
public let FRAME = 2
public let RADIAL = 3
public let HUB = 4
public let SPIRAL = 5
public let STAB = 6

// Indexed by kind. Rest length as a fraction of the drawn length (pre-tension), stiffness, and the stretch
// that snaps a thread. Capture silk is the stretchiest; the frame and radials are dragline silk.
private let TENSION: [Double] = [1, 0.99, 0.975, 0.965, 0.975, 0.985, 0.99]
private let STIFF: [Double] = [1, 1, 1, 1, 0.9, 0.7, 0.8]
private let BREAK: [Double] = [99, 99, 2.4, 2.0, 2.2, 2.1, 2.2]
/// How bright each kind of silk reads: the capture spiral is finest, the stabilimentum a dense ribbon.
public let SILK_ALPHA: [Double] = [0, 0.75, 0.95, 1, 1, 0.8, 1.8]

private let ITERATIONS = 6
@inline(__always) private func wrap(_ a: Double) -> Double { fmod(fmod(a, TAU) + TAU, TAU) }
@inline(__always) private func pairKey(_ a: Int, _ b: Int) -> Int { a < b ? a * 1_048_576 + b : b * 1_048_576 + a }

/// A corner of the frame, moored to a twig at (mx, my).
public struct FramePoint {
    public var x: Double
    public var y: Double
    public var mx: Double
    public var my: Double
    public init(x: Double, y: Double, mx: Double, my: Double) { self.x = x; self.y = y; self.mx = mx; self.my = my }
}

/// One leg of the build route: walk from node to node, laying `link` on the way if `lay`.
public struct RouteStep {
    public var from: Int
    public var to: Int
    public var link: Int
    public var lay: Bool
}

/// A point on a thread: which link, and how far along it (0..1).
public struct ThreadPoint {
    public var link: Int
    public var t: Double
    public init(link: Int, t: Double) { self.link = link; self.t = t }
}

private struct Anchor {
    var a: Double
    var x: Double
    var y: Double
    var mx: Double? = nil
    var my: Double? = nil
}

public struct Radial {
    public var th: Double
    public var L: Double
}

/// The original's typed arrays (Float32Array, Uint8Array, …): fixed-size buffers shared by reference, so
/// `let x = web.x` aliases the web's storage as `const { x } = this` does. Owned by the web; replaced (and
/// the old ones freed) by `generate`, so don't hold one across a rebuild.
@inline(__always) private func typed<T>(_ count: Int, _ v: T) -> UnsafeMutableBufferPointer<T> {
    let b = UnsafeMutableBufferPointer<T>.allocate(capacity: count)
    b.initialize(repeating: v)
    return b
}

public final class OrbWeb {
    public var cx: Double
    public var cy: Double
    public var radius: Double
    public var depth: Double
    public var cw: Double
    public var ch: Double
    public var stab: Bool
    public var frame: [FramePoint]?
    /// Where the web was first strung; rebuilt webs stay near it.
    public let home: Vec
    /// The loose end of the thread being laid: the spider has it, so it doesn't swing.
    public var held = -1
    /// Bumped each rebuild, so prey stuck to an old web can tell.
    public var gen = 0
    /// Flies stuck to this web. (Typed `[Fly]` once flies.ts is ported.)
    public var prey: [AnyObject] = []
    /// `Math.random()` for this web: the world's shared stream.
    public let random: WebRandom

    public private(set) var seed = 0.0
    /// Nodes.
    public private(set) var n = 0
    public private(set) var x = UnsafeMutableBufferPointer<Float>(start: nil, count: 0)
    public private(set) var y = UnsafeMutableBufferPointer<Float>(start: nil, count: 0)
    public private(set) var ox = UnsafeMutableBufferPointer<Float>(start: nil, count: 0)
    public private(set) var oy = UnsafeMutableBufferPointer<Float>(start: nil, count: 0)
    public private(set) var pin = UnsafeMutableBufferPointer<UInt8>(start: nil, count: 0)
    public private(set) var on = UnsafeMutableBufferPointer<UInt8>(start: nil, count: 0)
    public private(set) var deg = UnsafeMutableBufferPointer<UInt16>(start: nil, count: 0)
    public private(set) var speed = UnsafeMutableBufferPointer<Float>(start: nil, count: 0)
    /// Links (threads). state: 0 unlaid · 1 laid · 2 broken.
    public private(set) var m = 0
    public private(set) var la = UnsafeMutableBufferPointer<Int>(start: nil, count: 0)
    public private(set) var lb = UnsafeMutableBufferPointer<Int>(start: nil, count: 0)
    public private(set) var kind = UnsafeMutableBufferPointer<Int>(start: nil, count: 0)
    public private(set) var state = UnsafeMutableBufferPointer<Int>(start: nil, count: 0)
    public private(set) var rest = UnsafeMutableBufferPointer<Float>(start: nil, count: 0)
    /// Where on a capture thread a dew bead sits, or -1.
    public private(set) var dew = UnsafeMutableBufferPointer<Float>(start: nil, count: 0)
    public private(set) var hub = 0
    public private(set) var chain: [[Int]] = []
    public private(set) var rad: [Radial] = []
    public private(set) var N = 0
    public private(set) var T = 0
    public private(set) var rin = 0.0
    public private(set) var spacing = 0.0
    public private(set) var route: [RouteStep] = []
    public private(set) var spiralStart = 0
    public private(set) var radialsLaid = 0
    public private(set) var laid = 0
    public private(set) var broken = 0
    /// Furthest free node from the hub.
    public private(set) var outer = 0.0

    public init(
        cx: Double, cy: Double, radius: Double, depth: Double, cw: Double, ch: Double,
        stab: Bool = false, frame: [FramePoint]? = nil, random: WebRandom
    ) {
        self.cx = cx
        self.cy = cy
        self.radius = radius
        self.depth = depth
        self.cw = cw
        self.ch = ch
        self.stab = stab
        self.frame = frame
        self.home = Vec(x: cx, y: cy)
        self.random = random
        generate()
    }

    deinit { releaseBuffers() }

    private func releaseBuffers() {
        for b in [x, y, ox, oy, speed, rest, dew] { b.deallocate() }
        pin.deallocate(); on.deallocate(); deg.deallocate()
        la.deallocate(); lb.deallocate(); kind.deallocate(); state.deallocate()
    }

    /// Build a fresh web around (cx, cy). `startNear` picks the frame corner the route starts from.
    public func generate(_ startNear: Vec? = nil) {
        let cx = self.cx, cy = self.cy, R = radius, cw = self.cw, ch = self.ch
        seed = Double(random.int(1, 1_000_000))
        var X: [Double] = []
        var Y: [Double] = []
        var PIN: [UInt8] = []
        func node(_ x: Double, _ y: Double, _ pin: UInt8 = 0) -> Int {
            X.append(x); Y.append(y); PIN.append(pin)
            return X.count - 1
        }
        var LA: [Int] = []
        var LB: [Int] = []
        var LK: [Int] = []
        var links: [Int: Int] = [:]
        @discardableResult func link(_ a: Int, _ b: Int, _ kind: Int) -> Int {
            LA.append(a)
            LB.append(b)
            LK.append(kind)
            links[pairKey(a, b)] = LA.count - 1
            return LA.count - 1
        }

        // Anchors: the frame's corners, strung off twigs we never see. The hub sits high in a real orb, so the
        // frame reaches further below it.
        var anchors: [Anchor] = []
        if let frame {
            for f in frame {
                let x = f.x + random.range(-0.5, 0.5) * cw
                let y = f.y + random.range(-0.5, 0.5) * ch
                anchors.append(Anchor(a: wrap(atan2(y - cy, x - cx)), x: x, y: y, mx: f.mx, my: f.my))
            }
        } else {
            let n = R > 200 ? random.int(4, 5) : random.int(3, 4)
            let a0 = random.range(0, TAU)
            for i in 0..<n {
                let a = a0 + ((Double(i) + random.range(-0.2, 0.2)) * TAU) / Double(n)
                let r = R * random.range(1.1, 1.3) * (sin(a) > 0.25 ? 1.15 : 1)
                anchors.append(Anchor(a: wrap(a), x: cx + cos(a) * r, y: cy + sin(a) * r))
            }
        }
        anchors = stableSorted(anchors) { $0.a < $1.a }
        let nA = anchors.count

        func hitFrame(_ th: Double) -> Double {
            let dx = cos(th)
            let dy = sin(th)
            var best = Double.infinity
            for i in 0..<nA {
                let p = anchors[i]
                let q = anchors[(i + 1) % nA]
                let ex = q.x - p.x
                let ey = q.y - p.y
                let den = dx * ey - dy * ex
                if abs(den) < 1e-9 { continue }
                let wx = p.x - cx
                let wy = p.y - cy
                let s = (wx * ey - wy * ex) / den
                let u = (dy * wx - dx * wy) / den
                if s > 0 && u >= -1e-6 && u <= 1 + 1e-6 && s < best { best = s }
            }
            return best.isFinite ? best : R
        }

        // Radials, about ten glyphs apart at the rim, so each reads as its own line.
        let N = Int(clamp(mathRound((TAU * R) / (cw * 10)), 9, 20))
        let t0 = random.range(0, TAU)
        var rad: [Radial] = []
        for k in 0..<N {
            let th = t0 + ((Double(k) + random.range(-0.16, 0.16)) * TAU) / Double(N)
            rad.append(Radial(th: wrap(th), L: hitFrame(th)))
        }

        // Hub mesh, free zone, then the capture spiral: an open one, a turn every three rows or so, so the
        // webs stay quiet behind everything.
        let hub = node(cx, cy)
        let h1 = max(cw * 1.2, R * 0.05)
        let h2 = h1 * 1.9
        let rin = max(h2 + ch * 1.5, R * 0.27)
        let spacing = ch * random.range(3, 3.5)
        var outSum = 0.0
        for r in rad { outSum += r.L * 0.86 }
        let T = Int(max(2, mathRound((outSum / Double(N) - rin) / spacing)))
        var spiral = [Int](repeating: 0, count: T * N)
        var chain: [[Int]] = []
        var frameNode: [Int] = []
        for k in 0..<N {
            let c = cos(rad[k].th)
            let s = sin(rad[k].th)
            var ck = [hub, node(cx + c * h1, cy + s * h1), node(cx + c * h2, cy + s * h2)]
            let rout = max(rin + spacing, rad[k].L * 0.86)
            for j in stride(from: T - 1, through: 0, by: -1) {
                let r = lerp(rout, rin, (Double(j) + Double(k) / Double(N)) / Double(T))
                let i = node(cx + c * r, cy + s * r)
                spiral[j * N + k] = i
                ck.append(i)
            }
            let F = node(cx + c * rad[k].L, cy + s * rad[k].L)
            ck.append(F)
            frameNode.append(F)
            chain.append(ck)
        }

        // Frame: anchors and radial ends, in order round the hub.
        var fp = anchors.map { p in (a: p.a, i: node(p.x, p.y, 1)) }
        let anchorNodes = fp.map(\.i)
        for k in 0..<N { fp.append((a: rad[k].th, i: frameNode[k])) }
        fp = stableSorted(fp) { $0.a < $1.a }
        for i in 0..<fp.count { link(fp[i].i, fp[(i + 1) % fp.count].i, FRAME) }

        // Mooring lines out past the anchors: to the shared twig, or out at a slant.
        for (n, ai) in anchorNodes.enumerated() {
            let an = anchors[n]
            if let mx = an.mx, let my = an.my {
                link(ai, node(mx, my, 1), MOOR)
                continue
            }
            let a = atan2(Y[ai] - cy, X[ai] - cx) + random.range(-0.35, 0.35)
            let len = R * random.range(0.35, 0.7)
            link(ai, node(X[ai] + cos(a) * len, Y[ai] + sin(a) * len, 1), MOOR)
        }

        for k in 0..<N {
            let ck = chain[k]
            for i in 0..<(ck.count - 1) { link(ck[i], ck[i + 1], RADIAL) }
        }
        for k in 0..<N {
            link(chain[k][1], chain[(k + 1) % N][1], HUB)
            link(chain[k][2], chain[(k + 1) % N][2], HUB)
        }
        var spiralSeq: [Int] = []
        for j in 0..<T {
            for k in 0..<N {
                spiralSeq.append(spiral[j * N + k])
                let next = k < N - 1 ? spiral[j * N + k + 1] : j < T - 1 ? spiral[(j + 1) * N] : -1
                if next >= 0 { link(spiral[j * N + k], next, SPIRAL) }
            }
        }

        // Stabilimentum: a zigzag between the two radials either side of straight up, and of straight down.
        var bands: [[(k: Int, c: Int)]] = []
        if stab {
            for dir in [-Double.pi / 2, Double.pi / 2] {
                var kA = 0
                for k in 1..<N where abs(angleDiff(rad[k].th, dir)) < abs(angleDiff(rad[kA].th, dir)) { kA = k }
                let kB = (angleDiff(rad[kA].th, dir) > 0 ? kA + 1 : kA - 1 + N) % N
                let M = min(T, 6) + 1
                var zig: [(k: Int, c: Int)] = []
                for m in 0...M { zig.append((k: m % 2 != 0 ? kB : kA, c: 2 + m)) }
                for m in 1..<zig.count { link(chain[zig[m - 1].k][zig[m - 1].c], chain[zig[m].k][zig[m].c], STAB) }
                bands.append(zig)
            }
        }

        // ── the build route ──
        var route: [RouteStep] = []
        func walk<S: Collection>(_ seq: S, _ lay: Bool) where S.Element == Int {
            var prev: Int? = nil
            for to in seq {
                if let from = prev {
                    let l = links[pairKey(from, to)]
                    route.append(RouteStep(from: from, to: to, link: l ?? -1, lay: lay && l != nil))
                }
                prev = to
            }
        }
        // Start at the frame point nearest the spider, or at an anchor.
        var s0 = fp.firstIndex { $0.i == anchorNodes[0] } ?? -1
        if let startNear {
            var best = Double.infinity
            for i in 0..<fp.count {
                let d = hypot(X[fp[i].i] - startNear.x, Y[fp[i].i] - startNear.y)
                if d < best { best = d; s0 = i }
            }
        }
        var ring: [Int] = []
        for i in 0...fp.count { ring.append(fp[(s0 + i) % fp.count].i) }
        walk(ring, true)
        // Along the frame to the first radial end, then down that radial to the hub.
        var r0 = 0
        var toR0 = [ring[0]]
        for i in 0..<fp.count {
            let ni = ring[i]
            if i > 0 { toR0.append(ni) }
            if let k = frameNode.firstIndex(of: ni) {
                r0 = k
                break
            }
        }
        walk(toR0, false)
        walk(chain[r0].reversed(), true)
        // The rest of the radials in alternating order (bit-reversed), so tension stays balanced.
        var order = [r0]
        var seen: Set<Int> = [r0]
        var i = 1
        while order.count < N && i < N * 8 {
            var f = 0.0
            var b = 0.5
            var n = i
            while n != 0 {
                if n & 1 != 0 { f += b }
                n >>= 1
                b *= 0.5
            }
            let k = (r0 + Int(mathRound(f * Double(N)))) % N
            if !seen.contains(k) { seen.insert(k); order.append(k) }
            i += 1
        }
        for k in 0..<N where !seen.contains(k) { order.append(k) }
        for o in 1..<order.count {
            walk(chain[order[o]], true)
            walk(chain[order[o]].reversed(), false)
        }
        // Hub rings.
        walk([hub, chain[0][1]], false)
        walk(chain.map { $0[1] } + [chain[0][1]], true)
        walk([chain[0][1], chain[0][2]], false)
        walk(chain.map { $0[2] } + [chain[0][2]], true)
        // Out to the rim, spiral in, back to the hub.
        walk(chain[0][2..<min(3 + T, chain[0].count)], false)
        self.spiralStart = route.count
        walk(spiralSeq, true)
        walk([chain[N - 1][3], chain[N - 1][2], chain[N - 1][1], hub], false)
        for zig in bands {
            walk(chain[zig[0].k][0..<(zig[0].c + 1)], false)
            walk(zig.map { chain[$0.k][$0.c] }, true)
            let last = zig[zig.count - 1]
            walk(chain[last.k][0..<(last.c + 1)].reversed(), false)
        }

        // ── typed state ──
        let n = X.count
        let m = LA.count
        releaseBuffers()
        self.n = n
        self.m = m
        self.x = typed(n, 0)
        self.y = typed(n, 0)
        self.ox = typed(n, 0)
        self.oy = typed(n, 0)
        for i in 0..<n {
            x[i] = Float(X[i]); y[i] = Float(Y[i]); ox[i] = Float(X[i]); oy[i] = Float(Y[i])
        }
        self.pin = typed(n, 0)
        for i in 0..<n { pin[i] = PIN[i] }
        self.on = typed(n, 0)
        self.deg = typed(n, 0)
        self.speed = typed(n, 0)
        self.la = typed(m, 0)
        self.lb = typed(m, 0)
        self.kind = typed(m, 0)
        for l in 0..<m { la[l] = LA[l]; lb[l] = LB[l]; kind[l] = LK[l] }
        self.state = typed(m, 0)
        self.rest = typed(m, 0)
        self.dew = typed(m, -1)
        for l in 0..<m {
            let k = LK[l]
            rest[l] = Float(hypot(X[LB[l]] - X[LA[l]], Y[LB[l]] - Y[LA[l]]) * TENSION[k])
            // Dew catches on the capture spiral: a few beads per web that glint.
            if k == SPIRAL && hash3(seed, Double(l), 3) < 0.085 { dew[l] = Float(0.2 + 0.6 * hash3(seed, Double(l), 5)) }
        }
        self.hub = hub
        self.chain = chain
        self.rad = rad
        self.N = N
        self.T = T
        self.rin = rin
        self.spacing = spacing
        self.route = route
        self.radialsLaid = 0
        self.laid = 0
        self.broken = 0
        var outer = 0.0
        for i in 0..<n where PIN[i] == 0 { outer = max(outer, hypot(X[i] - cx, Y[i] - cy)) }
        self.outer = outer
        prey.removeAll()

        // Mooring lines were spun on an earlier night: they are up from the start.
        for l in 0..<m where LK[l] == MOOR { lay(l) }
    }

    public var hubPinned: Bool { radialsLaid < 4 }

    /// Free to move: not pinned to a twig, not the hub before it has radials, not the end the spider holds.
    @inline(__always) public func isFree(_ i: Int) -> Bool {
        pin[i] == 0 && i != held && !(i == hub && hubPinned)
    }

    public func lay(_ l: Int) {
        if l < 0 || state[l] == 1 { return }
        let a = la[l]
        let b = lb[l]
        state[l] = 1
        deg[a] &+= 1
        deg[b] &+= 1
        on[a] = 1
        on[b] = 1
        laid += 1
        if kind[l] == RADIAL && (a == hub || b == hub) { radialsLaid += 1 }
    }

    /// Take a thread down: `broken` marks it snapped rather than eaten.
    public func cut(_ l: Int, _ broken: Bool = false) {
        if l < 0 || state[l] != 1 { return }
        let a = la[l]
        let b = lb[l]
        state[l] = broken ? 2 : 0
        if broken { self.broken += 1 } else { laid -= 1 }
        if kind[l] == RADIAL && (a == hub || b == hub) { radialsLaid -= 1 }
        // for (const i of [a, b]), without the array
        for e in 0..<2 {
            let i = e == 0 ? a : b
            deg[i] &-= 1
            if deg[i] == 0 && pin[i] == 0 { on[i] = 0 }
        }
    }

    /// Everything up to route step `upTo` laid at once (scene start and reduced motion). Default: the whole route.
    public func buildInstant(_ upTo: Int? = nil) {
        let upTo = upTo ?? route.count
        for s in stride(from: 0, to: upTo, by: 1) where route[s].lay { lay(route[s].link) }
        for _ in 0..<240 { step(0) }
    }

    public var damage: Double { Double(broken) / Double(max(1, laid + broken)) }

    public func step(_ t: Double) {
        let n = self.n, x = self.x, y = self.y, ox = self.ox, oy = self.oy, on = self.on, speed = self.speed
        let la = self.la, lb = self.lb, state = self.state, rest = self.rest, kind = self.kind, m = self.m
        let g = 0.012 * (radius / 300)
        let wind = noise1(t * 0.12, seed) * 0.0026 * (radius / 300)
        // isFree(i) with its inputs read once: nothing below changes them before the break pass.
        let pin = self.pin, held = self.held, hub = self.hub, hubPinned = self.hubPinned
        @inline(__always) func isFree(_ i: Int) -> Bool { pin[i] == 0 && i != held && !(i == hub && hubPinned) }
        for i in 0..<n {
            if on[i] == 0 || !isFree(i) { continue }
            let vx = (Double(x[i]) - Double(ox[i])) * 0.962
            let vy = (Double(y[i]) - Double(oy[i])) * 0.962
            ox[i] = x[i]
            oy[i] = y[i]
            x[i] = Float(Double(x[i]) + (vx + wind))
            y[i] = Float(Double(y[i]) + (vy + g))
        }
        STIFF.withUnsafeBufferPointer { STIFF in
            for _ in 0..<ITERATIONS {
                for l in 0..<m {
                    if state[l] != 1 { continue }
                    let a = la[l]
                    let b = lb[l]
                    let dx = Double(x[b]) - Double(x[a])
                    let dy = Double(y[b]) - Double(y[a])
                    let d = (dx * dx + dy * dy).squareRoot()
                    let r = Double(rest[l])
                    if d <= r { continue } // slack silk pushes nothing
                    let wa = isFree(a) ? 1.0 : 0
                    let wb = isFree(b) ? 1.0 : 0
                    let ws = wa + wb
                    if ws == 0 { continue }
                    let k = ((d - r) / (d * ws)) * STIFF[kind[l]]
                    x[a] = Float(Double(x[a]) + dx * k * wa)
                    y[a] = Float(Double(y[a]) + dy * k * wa)
                    x[b] = Float(Double(x[b]) - dx * k * wb)
                    y[b] = Float(Double(y[b]) - dy * k * wb)
                }
            }
        }
        for l in 0..<m {
            if state[l] != 1 { continue }
            let a = la[l]
            let b = lb[l]
            if hypot(Double(x[b]) - Double(x[a]), Double(y[b]) - Double(y[a])) > Double(rest[l]) * BREAK[kind[l]] { cut(l, true) }
        }
        for i in 0..<n { speed[i] = on[i] != 0 ? Float(hypot(Double(x[i]) - Double(ox[i]), Double(y[i]) - Double(oy[i]))) : 0 }
    }

    /**
     * The pointer through the silk: threads it touches are nudged away and dragged a little along its path,
     * then spring back and ring. Returns how much silk it touched.
     */
    public func pluck(_ px: Double, _ py: Double, _ vx: Double, _ vy: Double, _ R: Double) -> Double {
        if hypot(px - cx, py - cy) > outer + R { return 0 }
        let x = self.x, y = self.y, la = self.la, lb = self.lb, state = self.state, kind = self.kind, m = self.m
        var total = 0.0
        let force = min(R * 0.12, 2.2)
        for l in 0..<m {
            if state[l] != 1 || kind[l] == MOOR { continue }
            let a = la[l]
            let b = lb[l]
            let ax = Double(x[a])
            let ay = Double(y[a])
            let bx = Double(x[b])
            let by = Double(y[b])
            if (ax < px - R && bx < px - R) || (ax > px + R && bx > px + R) || (ay < py - R && by < py - R) || (ay > py + R && by > py + R) { continue }
            let t = closestT(px, py, ax, ay, bx, by)
            let dx = ax + (bx - ax) * t - px
            let dy = ay + (by - ay) * t - py
            let d = hypot(dx, dy)
            if d >= R { continue }
            let k = 1 - d / R
            let nx = d > 1e-3 ? dx / d : 0
            let ny = d > 1e-3 ? dy / d : 0
            let fx = nx * force * k + vx * k * 0.2
            let fy = ny * force * k + vy * k * 0.2
            if isFree(a) { x[a] = Float(Double(x[a]) + fx * (1 - t)); y[a] = Float(Double(y[a]) + fy * (1 - t)) }
            if isFree(b) { x[b] = Float(Double(x[b]) + fx * t); y[b] = Float(Double(y[b]) + fy * t) }
            total += k
        }
        return total
    }

    /// A struggling fly or a landing foot: shake a thread at t.
    public func jolt(_ l: Int, _ t: Double, _ s: Double) {
        if l < 0 || state[l] != 1 { return }
        let a = la[l]
        let b = lb[l]
        let ang = random.range(0, TAU)
        let dx = cos(ang) * s
        let dy = sin(ang) * s
        if isFree(a) { x[a] = Float(Double(x[a]) + dx * (1 - t)); y[a] = Float(Double(y[a]) + dy * (1 - t)) }
        if isFree(b) { x[b] = Float(Double(x[b]) + dx * t); y[b] = Float(Double(y[b]) + dy * t) }
    }

    /// Pull a point of a thread down by `w` px (the spider's weight through a foot).
    public func load(_ l: Int, _ t: Double, _ w: Double) {
        if l < 0 || state[l] != 1 { return }
        let a = la[l]
        let b = lb[l]
        if isFree(a) { y[a] = Float(Double(y[a]) + w * (1 - t)) }
        if isFree(b) { y[b] = Float(Double(y[b]) + w * t) }
    }

    /// Nearest point of live silk to (px, py) within r, as { link, t }.
    public func snap(_ px: Double, _ py: Double, _ r: Double) -> ThreadPoint? {
        let x = self.x, y = self.y, la = self.la, lb = self.lb, state = self.state, kind = self.kind, m = self.m
        var best = r * r
        var found = -1
        var ft = 0.0
        for l in 0..<m {
            if state[l] != 1 || kind[l] == MOOR { continue }
            let a = la[l]
            let b = lb[l]
            let t = closestT(px, py, Double(x[a]), Double(y[a]), Double(x[b]), Double(y[b]))
            let qx = Double(x[a]) + (Double(x[b]) - Double(x[a])) * t - px
            let qy = Double(y[a]) + (Double(y[b]) - Double(y[a])) * t - py
            let d2 = qx * qx + qy * qy
            if d2 < best { best = d2; found = l; ft = t }
        }
        if found < 0 { return nil }
        return ThreadPoint(link: found, t: ft)
    }

    /// Where the capture spiral crosses the segment (x0, y0) → (x1, y1), as { link, t }.
    public func catches(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> ThreadPoint? {
        if hypot(x1 - cx, y1 - cy) > outer + 4 { return nil }
        let x = self.x, y = self.y, la = self.la, lb = self.lb, state = self.state, kind = self.kind, m = self.m
        for l in 0..<m {
            if state[l] != 1 || kind[l] != SPIRAL { continue }
            let a = la[l]
            let b = lb[l]
            let u = crossAlong(x0, y0, x1, y1, Double(x[a]), Double(y[a]), Double(x[b]), Double(y[b]))
            if u >= 0 { return ThreadPoint(link: l, t: u) }
        }
        return nil
    }

    @inline(__always) public func pos(_ l: Int, _ t: Double) -> Vec {
        let a = la[l]
        let b = lb[l]
        return Vec(x: Double(x[a]) + (Double(x[b]) - Double(x[a])) * t, y: Double(y[a]) + (Double(y[b]) - Double(y[a])) * t)
    }

    /// Hub → along the radial nearest (px, py) → the last node short of it. Node indices.
    public func pathToward(_ px: Double, _ py: Double) -> [Int] {
        let hx = Double(x[hub])
        let hy = Double(y[hub])
        let ang = atan2(py - hy, px - hx)
        let dist = hypot(px - hx, py - hy)
        var k = 0
        for i in 1..<max(1, N) where abs(angleDiff(rad[i].th, ang)) < abs(angleDiff(rad[k].th, ang)) { k = i }
        var path = [hub]
        let ck = chain[k]
        for i in 1..<max(1, ck.count - 1) {
            let ni = ck[i]
            if hypot(Double(x[ni]) - hx, Double(y[ni]) - hy) > dist - spacing * 0.5 { break }
            path.append(ni)
        }
        return path
    }
}

/// JavaScript's Array.prototype.sort is stable; Swift's sort makes no such promise, so ties keep their order.
private func stableSorted<E>(_ a: [E], by less: (E, E) -> Bool) -> [E] {
    a.indices.sorted { i, j in less(a[i], a[j]) || (!less(a[j], a[i]) && i < j) }.map { a[$0] }
}
