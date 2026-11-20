import Foundation

// The butterflies seen from above, ported from the sketch (`setPose`, `wingTest`, `edgeInfo`, `pattern`, veins,
// `drawButterfly`, `paperWingCell`, `drawRim`, `drawBody`, `drawShadow`; html:2011–2506). `html:N` is a line of
// `Tools/meadow-sketch/meadow.html` on `meadow-sketch` at 4e1b869.
//
// The sketch tests each of a cell's samples against the wing outlines in the wing's own frame. The port lays the four
// outlines (fore and hind, left and right) on the screen once a frame and finds, for each row of samples, where each
// outline crosses it; a sample is inside where an odd number of crossings lie to its right, as the sketch's even-odd
// test (the same answer: the frame change is affine). Only the samples that hit go back to the wing's frame.

private let DEG = Double.pi / 180

/// The four outlines on the screen and their crossings with this row's samples (raw storage, made once by the
/// painter).
struct WingSpans {
    static let maxPoints = 12
    static let maxCross = 24
    /// Outlines 0 fore-left, 1 fore-right, 2 hind-left, 3 hind-right.
    let px: UnsafeMutablePointer<Double>, py: UnsafeMutablePointer<Double>
    let count: UnsafeMutablePointer<Int>
    let minY: UnsafeMutablePointer<Double>, maxY: UnsafeMutablePointer<Double>
    /// Crossings per group (forewings, hindwings) per sample row (3 rows), sorted.
    let cross: UnsafeMutablePointer<Double>
    let crossN: UnsafeMutablePointer<Int>

    static func make() -> WingSpans {
        func buf<T>(_ n: Int, _ z: T) -> UnsafeMutablePointer<T> {
            let p = UnsafeMutablePointer<T>.allocate(capacity: n)
            p.initialize(repeating: z, count: n)
            return p
        }
        return WingSpans(px: buf(4 * maxPoints, 0.0), py: buf(4 * maxPoints, 0.0), count: buf(4, 0), minY: buf(4, 0.0), maxY: buf(4, 0.0),
                         cross: buf(2 * 3 * maxCross, 0.0), crossN: buf(2 * 3, 0))
    }

    func free() { px.deallocate(); py.deallocate(); count.deallocate(); minY.deallocate(); maxY.deallocate(); cross.deallocate(); crossN.deallocate() }

    /// Lays sample row j at y: the forewings' crossings in one sorted list and the hindwings' in another (left and
    /// right never overlap, so the even-odd test over a merged list is each outline's own).
    func row(_ j: Int, _ y: Double) {
        for g in 0..<2 {
            let k = g * 3 + j
            let base = k * WingSpans.maxCross
            var m = 0
            for p in (g * 2)..<(g * 2 + 2) {
                if y < minY[p] || y > maxY[p] { continue }
                let n = count[p], pb = p * WingSpans.maxPoints
                var b = n - 1
                for a in 0..<n {
                    let ay = py[pb + a], by = py[pb + b]
                    if (ay > y) != (by > y) && m < WingSpans.maxCross {
                        let ax = px[pb + a], bx = px[pb + b]
                        let xc: Double = ax + (y - ay) / (by - ay) * (bx - ax)
                        // Insert in order.
                        var q = m
                        while q > 0 && cross[base + q - 1] > xc { cross[base + q] = cross[base + q - 1]; q -= 1 }
                        cross[base + q] = xc
                        m += 1
                    }
                    b = a
                }
            }
            crossN[k] = m
        }
    }

    /// Inside group g (0 forewings, 1 hindwings) at x on row j: an odd number of crossings to its right.
    @inline(__always) func inside(_ g: Int, _ j: Int, _ x: Double) -> Bool {
        let k = g * 3 + j
        let n = crossN[k], base = k * WingSpans.maxCross
        for q in 0..<n where x < cross[base + q] { return (n - q) & 1 == 1 }
        return false
    }

    /// The leftmost and rightmost crossing on the three rows laid last, or nil when no outline crosses them.
    func extent() -> (Double, Double)? {
        var lo = Double.infinity, hi = -Double.infinity
        for k in 0..<6 where crossN[k] > 0 {
            let base = k * WingSpans.maxCross
            lo = min(lo, cross[base])
            hi = max(hi, cross[base + crossN[k] - 1])
        }
        return lo <= hi ? (lo, hi) : nil
    }

    /// Which part covers sample x on row j: -1 none, 0 forewing, 1 hindwing (the tail is told by the wing's frame).
    @inline(__always) func part(_ j: Int, _ x: Double) -> Int {
        if inside(0, j, x) { return 0 }
        if inside(1, j, x) { return 1 }
        return -1
    }
}

/// One butterfly's pose for drawing (`POSE`, html:2015–2044).
struct WingPose {
    var cx = 0.0, cy = 0.0, fx = 1.0, fy = 0.0, rx = 0.0, ry = 1.0
    var hs = 1.0, hh = 1.0, wl = 1.0, wr = 1.0
    var lamL = 0.7, lamR = 0.7, specL = 0.0, specR = 0.0, under = 0.0, depth = 1.0
}

/// An outline's edge at this frame's scale (`edgeInfo`'s numbers, laid once per butterfly per frame).
struct EdgeSeg {
    var ax = 0.0, ay = 0.0, ex = 0.0, ey = 0.0, L2 = 1.0, L = 1.0, acc = 0.0
    var kind = WingOutline.Edge.root
}

/// A vein on the screen this frame.
struct VeinSeg { var part = 0, side = 0; var ax = 0.0, ay = 0.0, dx = 0.0, dy = 0.0 }

extension MeadowFrame {
    static let subX: [Double] = [0.5, 0.25, 0.75, 0.25, 0.75]
    static let subY: [Double] = [0.5, 0.3, 0.3, 0.72, 0.72]
    static let subJ: [Int] = [0, 1, 1, 2, 2]
    static let legAt: [Double] = [0.26, 0.14, 0.02]
    static let legAngle: [Double] = [0.55, 1.5, 2.35]

    /// `setPose` (html:2017–2044), and the outlines laid on the screen.
    mutating func setPose(_ world: MeadowWorld, _ b: Butterfly, shadow: Bool) -> WingPose {
        let sp = b.sp
        let z: Double = shadow ? 0 : b.z
        let k: Double = world.depthScale(z) * b.size
        let span: Double = sp.span * 13 * S * k
        let h: Double = b.heading + (b.landed ? 0 : 0.05 * sin(b.phase))
        var P = WingPose()
        P.fx = cos(h); P.fy = sin(h); P.rx = -P.fy; P.ry = P.fx
        P.hs = span / 2
        P.hh = span * sp.aspect / 2
        let sl = b.stroke - b.bank, sr = b.stroke + b.bank
        P.wl = max(0.1, cos(sl))
        P.wr = max(0.1, cos(sr))
        let LX = MeadowLight.x, LY = MeadowLight.y, LZ = MeadowLight.z
        let rl: Double = P.rx * LX + P.ry * LY
        P.lamR = clamp(-sin(sr) * rl + cos(sr) * LZ, 0, 1)
        P.lamL = clamp(sin(sl) * rl + cos(sl) * LZ, 0, 1)
        let hz: Double = 1 / (LX * LX + LY * LY + (LZ + 1) * (LZ + 1)).squareRoot()
        P.specR = pow(clamp((-sin(sr) * rl + cos(sr) * (LZ + 1)) * hz, 0, 1), 18)
        P.specL = pow(clamp((sin(sl) * rl + cos(sl) * (LZ + 1)) * hz, 0, 1), 18)
        P.under = MeadowMath.smooth(68 * DEG, 86 * DEG, b.stroke)
        P.depth = z
        if shadow {
            let off: Double = b.z * 150 * S + 3 * S
            P.cx = b.x - LX * off
            P.cy = b.y - LY * off
        } else {
            P.cx = b.x
            P.cy = b.y
        }
        // The outlines on the screen.
        for p in 0..<4 {
            let o = p < 2 ? sp.fore : sp.hind
            let side = p % 2   // 0 left (v < 0), 1 right
            let sg: Double = side == 1 ? 1 : -1
            let sx: Double = P.hs * (side == 1 ? P.wr : P.wl), sy = P.hh
            let n = min(o.points.count, WingSpans.maxPoints)
            spans.count[p] = n
            var lo = Double.infinity, hi = -Double.infinity
            for q in 0..<n {
                let v: Double = sg * o.points[q].x * sx, u: Double = o.points[q].y * sy
                let x: Double = P.cx + P.fx * u + P.rx * v
                let y: Double = P.cy + P.fy * u + P.ry * v
                spans.px[p * WingSpans.maxPoints + q] = x
                spans.py[p * WingSpans.maxPoints + q] = y
                lo = min(lo, y); hi = max(hi, y)
            }
            spans.minY[p] = lo
            spans.maxY[p] = hi
        }
        return P
    }

    /// The wing's own frame at a screen point (`wingTest`'s WT, html:2058–2069): X, Y, side, sx, sy.
    @inline(__always) mutating func wingFrame(_ P: WingPose, _ x: Double, _ y: Double) -> (X: Double, Y: Double, side: Int, sx: Double, sy: Double) {
        let dx = x - P.cx, dy = y - P.cy
        let u: Double = dx * P.fx + dy * P.fy, v: Double = dx * P.rx + dy * P.ry
        let side = v < 0 ? 0 : 1
        let sx: Double = P.hs * (side == 1 ? P.wr : P.wl)
        return (abs(v) / sx, u / P.hh, side, sx, P.hh)
    }

    /// The outline's edges at this frame's scale, for `edgeInfo`: outline `p` (0 fore-left, 1 fore-right, 2 hind-left,
    /// 3 hind-right).
    mutating func layEdges(_ sp: ButterflySpecies, _ P: WingPose) {
        for p in 0..<4 {
            let o = p < 2 ? sp.fore : sp.hind
            let sx: Double = P.hs * (p % 2 == 1 ? P.wr : P.wl), sy = P.hh
            let n = min(o.points.count, WingSpans.maxPoints)
            edgeN[p] = n
            var acc = 0.0
            for i in 0..<n {
                let j = (i + 1) % n
                let ax: Double = o.points[i].x * sx, ay: Double = o.points[i].y * sy
                let bx: Double = o.points[j].x * sx, by: Double = o.points[j].y * sy
                let ex = bx - ax, ey = by - ay
                var L2: Double = ex * ex + ey * ey
                if L2 == 0 { L2 = 1e-9 }
                let L = L2.squareRoot()
                edges[p * WingSpans.maxPoints + i] = EdgeSeg(ax: ax, ay: ay, ex: ex, ey: ey, L2: L2, L: L, acc: acc, kind: o.kinds[i])
                acc += L
            }
        }
    }

    /// `edgeInfo` (html:2073–2086): cells to the outline's nearest free edge, its kind and how far along, on outline
    /// `p` as laid by `layEdges`.
    @inline(__always) func edgeInfo(_ p: Int, _ X: Double, _ Y: Double, _ sx: Double, _ sy: Double) -> (d: Double, kind: WingOutline.Edge, along: Double) {
        let qx = X * sx, qy = Y * sy
        var best2 = 1e18, along = 0.0
        var kind = WingOutline.Edge.root
        let base = p * WingSpans.maxPoints
        for i in 0..<edgeN[p] {
            let e = edges[base + i]
            if e.kind == .root { continue }
            let t: Double = clamp(((qx - e.ax) * e.ex + (qy - e.ay) * e.ey) / e.L2, 0, 1)
            let dx: Double = qx - e.ax - e.ex * t, dy: Double = qy - e.ay - e.ey * t
            let d2: Double = dx * dx + dy * dy
            if d2 < best2 { best2 = d2; kind = e.kind; along = e.acc + t * e.L }
        }
        return (best2.squareRoot() / cw, kind, along / cw)
    }

    enum Region { case field, mark, dot, ring, centre, blue, spot, seam }

    /// `pattern` (html:2091–2132): each species' markings on the upper side.
    mutating func pattern(_ kind: ButterflyKind, _ part: Int, _ side: Int, _ X: Double, _ Y: Double, _ sx: Double, _ sy: Double) -> (Region, Double) {
        let ei = edgeInfo(part * 2 + side, X, Y, sx, sy)
        let d = ei.d, ek = ei.kind
        let alt = Int(floor(ei.along / 1.5)) % 2 == 0
        let qx: Double = X * sx / cw, qy: Double = Y * sy / cw
        @inline(__always) func near(_ x: Double, _ y: Double, _ r: Double) -> Bool { hypot(qx - x * sx / cw, qy - y * sy / cw) < r }
        switch kind {
        case .monarch:
            if ek == .outer && d < 0.95 { return (alt && d > 0.22 ? .dot : .mark, d) }
            if part == 0 {
                if X + 0.6 * Y > 1.38 { return (near(0.80, 0.86, 0.55) || near(0.94, 0.62, 0.45) || near(0.66, 0.93, 0.4) ? .spot : .mark, d) }
                if ek == .costa && d < 0.85 && X > 0.38 { return (.mark, d) }
                if ek == .inner && d < 0.6 { return (.mark, d) }
            } else if ek == .inner && d < 0.55 { return (.mark, d) }
            return (.field, d)
        case .morpho:
            if part == 0 && (ek == .outer || ek == .costa) && X > 0.4 && d < 1.45 {
                return (near(0.84, 0.8, 0.5) || near(0.95, 0.5, 0.45) || near(0.7, 0.92, 0.4) ? .dot : .mark, d)
            }
            if part == 1 && ek == .outer && d < 0.85 { return (alt && d > 0.15 ? .dot : .mark, d) }
            if part == 0 && ek == .inner && d < 0.7 { return (.seam, d) }
            return (.field, d)
        case .swallowtail:
            if part == 2 { return (.mark, d) }
            if X < 0.12 { return (.mark, d) }
            if part == 1 && near(0.18, -0.84, 0.65) { return (near(0.18, -0.84, 0.3) ? .centre : .ring, d) }
            if part == 0 && ek == .costa && d < 0.85 && X > 0.2 && Int(floor(ei.along / 2.4)) % 2 == 0 { return (.mark, d) }
            if part == 0 && ek == .outer && d < 1.15 { return (d < 0.6 && alt ? .dot : .mark, d) }
            if part == 0 && X + 0.6 * Y > 1.5 { return (.mark, d) }
            if part == 1 && ek == .outer && d < 1.7 {
                if d < 0.7 { return (alt ? .dot : .mark, d) }
                return (Y < -0.2 ? .blue : .mark, d)
            }
            if part == 1 && ek == .inner && d < 0.6 { return (.mark, d) }
            if part == 0 && ek == .inner && d < 0.8 { return (.seam, d) }
            return (.field, d)
        case .white:
            if part == 0 && ek != .inner && X + 0.5 * Y > 1.18 && d < 1.4 { return (.mark, d) }
            if part == 0 && near(0.55, 0.3, 0.6) { return (.mark, d) }
            if part == 0 && near(0.5, 0.02, 0.5) { return (.mark, d) }
            if part == 1 && ek == .costa && near(0.5, -0.04, 0.45) { return (.mark, d) }
            if part == 0 && ek == .inner && d < 0.8 { return (.seam, d) }
            return (.field, d)
        }
    }

    /// `buildVeins` (html:2147–2156).
    mutating func buildVeins(_ b: Butterfly, _ P: WingPose) -> Int {
        var n = 0
        for v in b.sp.veins {
            for side in 0..<2 {
                let sx: Double = P.hs * (side == 1 ? P.wr : P.wl), sy = P.hh, sg: Double = side == 1 ? 1 : -1
                if (v.from == 1 && sx / cw <= 10) || (v.from == 2 && sx / cw <= 14) { continue }
                let ax: Double = P.cx + P.rx * sg * v.x0 * sx + P.fx * v.y0 * sy
                let ay: Double = P.cy + P.ry * sg * v.x0 * sx + P.fy * v.y0 * sy
                let bx: Double = P.cx + P.rx * sg * v.x1 * sx + P.fx * v.y1 * sy
                let by: Double = P.cy + P.ry * sg * v.x1 * sx + P.fy * v.y1 * sy
                if n < 16 { veins[n] = VeinSeg(part: v.part, side: side, ax: ax, ay: ay, dx: bx - ax, dy: by - ay); n += 1 }
            }
        }
        return n
    }

    /// `veinGlyph` (html:2158–2173).
    @inline(__always) mutating func veinGlyph(_ count: Int, _ part: Int, _ side: Int, _ px: Double, _ py: Double) -> UInt8 {
        for k in 0..<count {
            let s = veins[k]
            if s.part != part || s.side != side { continue }
            if abs(s.dx) >= abs(s.dy) {
                let t = (px - s.ax) / s.dx
                if !(t >= 0 && t <= 1) { continue }
                let y: Double = s.ay + t * s.dy - (py - 0.5 * ch)
                if y < 0 || y >= ch { continue }
                return meadowLine(s.dx, s.dy, y / ch)
            }
            let t = (py - s.ay) / s.dy
            if !(t >= 0 && t <= 1) { continue }
            let x: Double = s.ax + t * s.dx - (px - 0.5 * cw)
            if x < 0 || x >= cw { continue }
            return meadowLine(s.dx, s.dy, 0.5)
        }
        return MG.none
    }

    /// `rampAt` (html:2181–2185).
    @inline(__always) mutating func rampAt(_ ramp: [MeadowRGB], _ p: Double) -> MeadowRGB {
        let k = min(2, Int(floor(p))), t = p - Double(k)
        return ramp[k] + (ramp[k + 1] - ramp[k]) * t
    }

    /// Shadows, then the butterflies, low to high (html:2613–2615).
    mutating func drawButterflies() {
        let world = self.world
        let flies = world.flies
        painter.order.ensure(flies.count)
        let order = painter.order.p
        let count = flies.count
        for i in 0..<count { order[i] = i }
        // Insertion sort by height (stable, as the sketch's sort).
        if count > 1 {
            for a in 1..<count {
                let v = order[a]
                var b = a - 1
                while b >= 0 && flies[order[b]].z > flies[v].z { order[b + 1] = order[b]; b -= 1 }
                order[b + 1] = v
            }
        }
        for k in 0..<count { drawShadow(world, flies[order[k]]) }
        for k in 0..<count { drawButterfly(world, flies[order[k]]) }
    }

    /// The canvas cells a box in the meadow covers, clipped to this screen.
    @inline(__always) mutating func cellBox(_ cx: Double, _ cy: Double, _ reach: Double) -> (Int, Int, Int, Int)? {
        let c0 = max(0, Int(floor((cx - reach - ox) / cw))), c1 = min(cols - 1, Int(floor((cx + reach - ox) / cw)))
        let r0 = max(0, Int(floor((cy - reach - oy) / ch))), r1 = min(rows - 1, Int(floor((cy + reach - oy) / ch)))
        if c0 > c1 || r0 > r1 { return nil }
        return (c0, c1, r0, r1)
    }

    /// `drawButterfly` (html:2187–2309).
    mutating func drawButterfly(_ world: MeadowWorld, _ b: Butterfly) {
        let sp = b.sp
        // Cheap cull before laying out the pose.
        let roughReach: Double = sp.span * 13 * S * b.size * world.depthScale(b.z) * 0.5 * 1.6 + 2 * cw
        guard cellBox(b.x, b.y, roughReach) != nil else { return }
        let P = setPose(world, b, shadow: false)
        let ink = sp.inks
        let reach: Double = max(P.hs, P.hh * (sp.tailY > -9 ? 1.5 : 1.1)) + cw
        guard let (c0, c1, r0, r1) = cellBox(P.cx, P.cy, reach) else { return }
        let depthK = min(1, tuning.depth)
        let flat: Double = 0.78 + 0.28 * P.depth
        let nearK: Double = LIGHT ? 1 - 0.08 * P.depth : 1 + 0.14 * P.depth
        let dim: Double = flat + (nearK - flat) * depthK
        let pflat: Double = 0.88 + 0.12 * P.depth, pnear: Double = 1 + 0.1 * P.depth
        let rich: Double = pflat + (pnear - pflat) * depthK
        let pw = sp.paper
        REC = true
        recN = 0
        recStamp &+= 1
        if recStamp == 0 { for i in 0..<n { recMark[i] = 0 }; recStamp = 1 }
        let under = P.under, U = ink.under, ramp = ink.ramp, marks = ink.marks
        let white = b.kind == .white
        let fhue: MeadowRGB = ramp[2] + (U - ramp[2]) * under
        let pig: MeadowRGB = pw.pig + (pw.under - pw.pig) * under
        let pedge: MeadowRGB = pw.edge + (pw.under * 0.7 - pw.edge) * under
        let nVeins = buildVeins(b, P)
        layEdges(sp, P)
        wingStampN &+= 1
        if wingStampN == 0 { for i in 0..<n { wingStamp[i] = 0 }; wingStampN = 1 }
        let stampV = wingStampN
        let idKey = Double(b.id * 8)
        for r in r0...r1 {
            let y0: Double = oy + Double(r) * ch
            spans.row(0, y0 + 0.5 * ch)
            spans.row(1, y0 + 0.3 * ch)
            spans.row(2, y0 + 0.72 * ch)
            // Only the columns the outlines reach on these rows.
            guard let (lo, hi) = spans.extent() else { continue }
            let ca = max(c0, Int(floor((lo - ox) / cw)) - 1), cb = min(c1, Int(floor((hi - ox) / cw)) + 1)
            if ca > cb { continue }
            for c in ca...cb {
                let x0: Double = ox + Double(c) * cw
                let px: Double = x0 + 0.5 * cw, py: Double = y0 + 0.5 * ch
                let i = r * cols + c
                var hits = 0
                var first = -1
                var firstK = 0
                for k in 0..<5 {
                    let p = spans.part(MeadowFrame.subJ[k], x0 + MeadowFrame.subX[k] * cw)
                    if p >= 0 { hits += 1; if first < 0 { first = p; firstK = k } }
                }
                if hits == 0 { continue }
                let centre = firstK == 0 && first >= 0
                let sxp: Double = x0 + MeadowFrame.subX[firstK] * cw
                let syp: Double = y0 + MeadowFrame.subY[firstK] * ch
                let wf = wingFrame(P, sxp, syp)
                let hp = first == 1 && wf.Y < sp.tailY ? 2 : first
                let cov = Double(hits) / 5, part = hp == 2 ? 1 : hp
                let (region, d) = pattern(b.kind, part, wf.side, wf.X, wf.Y, wf.sx, wf.sy)
                let key = keyOf(MeadowMath.round(wf.X * P.hs / (cw * 0.9)), MeadowMath.round(wf.Y * wf.sy / (cw * 0.9)), idKey + Double(hp) + 3 * Double(wf.side))
                let isField = region == .field || region == .seam
                if !centre || cov < 0.6 {
                    let gi: UInt8 = cov >= 0.5 ? MG.heavy[Int((key >> 8) & 1)] : MG.lightEdge[Int((key >> 8) & 3)]
                    touch(i)
                    rec(i)
                    if isField && shimmer(key, 0.07, 0) == 1 {
                        let a = PlantInk.accents[Int(key % 7)]
                        putGlyph(i, gi, a.x, a.y, a.z, 1)
                    } else if LIGHT {
                        let e = isField ? pedge : pw.markInk
                        putGlyph(i, gi, e.x, e.y, e.z, (0.5 + 0.45 * cov) * (isField ? 1 : 0.8))
                    } else {
                        edgeGlyph(i, gi, isField ? fhue : marks[2], (70 + 80 * cov) * dim * (isField ? 1 : 0.6))
                    }
                    continue
                }
                wingStamp[i] = stampV
                let lam = wf.side == 1 ? P.lamR : P.lamL, spec = wf.side == 1 ? P.specR : P.specL
                let t: Double = clamp(wf.X * 1.2 - 0.12, 0, 1)
                var shadeV: Double = 0.1 + 0.42 * (lam / 0.72) + 0.28 * t + 0.04 * min(d, 3) - (d < 0.5 ? 0.08 : 0)
                if b.kind == .morpho { shadeV += 0.6 * spec * (1 - under) }
                if region == .seam { shadeV -= 0.22 }
                shadeV = clamp(shadeV, 0, 1)
                if LIGHT {
                    paperWingCell(i, region, shadeV, wf.X, key, pw, rich, part, wf.side, px, py, white, pig, nVeins)
                    continue
                }
                switch region {
                case .field, .seam:
                    var p: Double = clamp(shadeV * 3.3 - 0.25, 0, 3)
                    if wf.X < 0.14 { p = min(p, 1.2) }
                    var f = rampAt(ramp, p)
                    if under > 0 { let k: Double = 0.55 + 0.6 * shadeV; f = f + (U * k - f) * under }
                    wBlock(i, f.x * dim, f.y * dim, f.z * dim, 1)
                    let vg = region == .field ? veinGlyph(nVeins, part, wf.side, px, py) : MG.none
                    if vg != MG.none { let m = marks[0]; wGlyph(i, vg, m.x, m.y, m.z, 1); break }
                    let gi = MG.skin[Int(clamp(floor((1 - shadeV) * 8.99) + Double((key >> 4) % 3) - 1, 0, 8))]
                    let s = shimmer(key, 0.06, 0.10)
                    if s != 0 { shimmerGlyph(i, gi, s, key, white); break }
                    if white && (key >> 12) % 10 < 3 { GI[i] = MG.none; break }
                    carved(i, gi, shadeV)
                case .mark:
                    let ml = Int(clamp(floor(shadeV * 2.2 + Double((key >> 6) % 100) / 100 - 0.5), 0, 2))
                    let m = marks[ml], mi = ink.markInk
                    wBlock(i, m.x * dim, m.y * dim, m.z * dim, 1)
                    wGlyph(i, MG.marks[Int((key >> 8) % UInt32(MG.marks.count))], mi.x * 0.7, mi.y * 0.7, mi.z * 0.7, 1)
                case .dot:
                    let m = marks[1], q = ink.dot, k2 = (key >> 10) % 100
                    wBlock(i, m.x * dim, m.y * dim, m.z * dim, 1)
                    wGlyph(i, k2 < 45 ? MG.mid : k2 < 85 ? MG.deg : MG.o, q.x, q.y, q.z, 0.95)
                case .spot:
                    let q = ink.spot, k: Double = (0.62 + 0.2 * shadeV) * dim
                    wBlock(i, q.x * k, q.y * k, q.z * k, 1)
                    wGlyph(i, (key >> 10) % 2 != 0 ? MG.mid : MG.deg, ink.dot.x, ink.dot.y, ink.dot.z, 0.85)
                case .ring:
                    let q = ink.ring
                    wBlock(i, q.x * 0.6 * dim, q.y * 0.6 * dim, q.z * 0.6 * dim, 1)
                    wGlyph(i, MG.o, min(255, q.x * 1.15), min(255, q.y * 1.15), min(255, q.z * 1.15), 0.95)
                case .centre:
                    let q = ink.centre
                    wBlock(i, q.x * dim, q.y * dim, q.z * dim, 1)
                    wGlyph(i, MG.at, ink.ring.x, ink.ring.y, ink.ring.z, 0.95)
                case .blue:
                    let q = ink.blue, k: Double = (0.8 + 0.3 * shadeV) * dim
                    wBlock(i, q.x * k, q.y * k, q.z * k, 1)
                    wGlyph(i, (key >> 10) % 2 != 0 ? MG.mid : MG.colon, min(255, q.x * 1.8), min(255, q.y * 1.6), min(255, q.z * 1.3), 0.8)
                }
            }
        }
        drawBody(world, b, P, ink, dim, stampV)
        REC = false
        drawRim(b)
    }

    /// `paperWingCell` (html:2317–2366).
    mutating func paperWingCell(_ i: Int, _ region: Region, _ shade: Double, _ hX: Double, _ key: UInt32, _ pw: PaperWings, _ rich: Double,
                       _ part: Int, _ side: Int, _ px: Double, _ py: Double, _ white: Bool, _ pig: MeadowRGB, _ nVeins: Int) {
        switch region {
        case .field, .seam:
            var p: Double = clamp(shade * 3.3 - 0.25, 0, 3)
            if hX < 0.14 { p = min(p, 1.2) }
            let c = paperWash(pig, (pw.deep + (pw.lit - pw.deep) * p / 3) * rich)
            blockAt(i, c.0, c.1, c.2, 1)
            let vg = region == .field ? veinGlyph(nVeins, part, side, px, py) : MG.none
            if vg != MG.none { let m = pw.markInk; glyphAt(i, vg, m.x, m.y, m.z, 0.9); return }
            let gi = MG.skin[Int(clamp(floor((1 - shade) * 8.99) + Double((key >> 4) % 3) - 1, 0, 8))]
            let s = shimmer(key, 0.06, 0.10)
            if s != 0 { shimmerGlyph(i, gi, s, key, white); return }
            if white && (key >> 12) % 10 < 3 { GI[i] = MG.none; return }
            let k = pw.ink
            glyphAt(i, gi, k.x, k.y, k.z, shade > 0.55 ? 0.78 : 0.92)
        case .mark:
            let ml = Int(clamp(floor(shade * 2.2 + Double((key >> 6) % 100) / 100 - 0.5), 0, 2))
            let c = paperWash(pw.mark, pw.markA[ml] * rich)
            blockAt(i, c.0, c.1, c.2, 1)
            let m = pw.markInk
            glyphAt(i, MG.marks[Int((key >> 8) % UInt32(MG.marks.count))], m.x, m.y, m.z, 0.95)
        case .dot:
            let c = paperWash(pw.mark, pw.markA[1] * rich), k2 = (key >> 10) % 100
            blockAt(i, c.0, c.1, c.2, 1)
            glyphAt(i, k2 < 45 ? MG.mid : k2 < 85 ? MG.deg : MG.o, 247, 246, 243, 1)
        case .spot:
            let c = paperWash(pw.spot, pw.spotA * (1.2 - 0.4 * shade) * rich)
            blockAt(i, c.0, c.1, c.2, 1)
            let m = pw.ink
            glyphAt(i, (key >> 10) % 2 != 0 ? MG.mid : MG.deg, m.x, m.y, m.z, 0.85)
        case .ring:
            let c = paperWash(pw.ring, pw.ringA * rich)
            blockAt(i, c.0, c.1, c.2, 1)
            let m = pw.markInk
            glyphAt(i, MG.o, m.x, m.y, m.z, 0.9)
        case .centre:
            let c = paperWash(pw.mark, pw.markA[0] * rich)
            blockAt(i, c.0, c.1, c.2, 1)
            glyphAt(i, MG.at, 247, 246, 243, 0.95)
        case .blue:
            let c = paperWash(pw.blue, pw.blueA * (1.15 - 0.3 * shade) * rich)
            blockAt(i, c.0, c.1, c.2, 1)
            let m = pw.markInk
            glyphAt(i, (key >> 10) % 2 != 0 ? MG.mid : MG.colon, m.x, m.y, m.z, 0.8)
        }
    }

    /// `drawRim` (html:2374–2398): one cell of dark ink (the paper on paper) round a high butterfly.
    mutating func drawRim(_ b: Butterfly) {
        let k: Double = min(1, 0.85 * tuning.depth) * MeadowMath.smooth(0.18, 0.72, b.z)
        if k <= 0.02 || recN == 0 { return }
        rimStamp &+= 1
        if rimStamp == 0 { for i in 0..<n { rimMark[i] = 0 }; rimStamp = 1 }
        let rs = rimStamp
        var m = 0
        for j in 0..<recN {
            let i = Int(recList[j])
            let c = i % cols, r = i / cols
            for dr in -1...1 {
                let rr = r + dr
                if rr < 0 || rr >= rows { continue }
                for dc in -1...1 {
                    let cc = c + dc
                    if (dr == 0 && dc == 0) || cc < 0 || cc >= cols { continue }
                    let nb = rr * cols + cc
                    if recMark[nb] == recStamp { continue }
                    let w: Float = dr != 0 && dc != 0 ? 0.55 : 1
                    if rimMark[nb] != rs { rimMark[nb] = rs; rimW[nb] = w; rimList[m] = Int32(nb); m += 1 }
                    else if w > rimW[nb] { rimW[nb] = w }
                }
            }
        }
        let t: SIMD3<Float> = LIGHT ? SIMD3(247, 246, 243) : SIMD3(6, 7, 9)
        for j in 0..<m {
            let nb = Int(rimList[j])
            let kk = Float(k) * rimW[nb]
            touch(nb)
            if LIGHT || lum(Double(BR[nb]), Double(BG[nb]), Double(BB[nb])) > 8 {
                BR[nb] += (t.x - BR[nb]) * kk; BG[nb] += (t.y - BG[nb]) * kk; BB[nb] += (t.z - BB[nb]) * kk
                if HB[nb] == 0 { HB[nb] = 2 }
            }
            IA[nb] *= 1 - 0.8 * kk
        }
    }

    @inline(__always) mutating func cellOf(_ x: Double, _ y: Double) -> Int {
        let c = Int(floor((x - ox) / cw)), r = Int(floor((y - oy) / ch))
        return c < 0 || r < 0 || c >= cols || r >= rows ? -1 : r * cols + c
    }

    /// `drawBody` (html:2400–2485): body, eyes, legs, antennae, proboscis.
    mutating func drawBody(_ world: MeadowWorld, _ b: Butterfly, _ P: WingPose, _ ink: WingInks, _ dim: Double, _ stampV: UInt32) {
        let fx = P.fx, fy = P.fy, rx = P.rx, ry = P.ry, hh = P.hh
        let life = tuning.life
        let breath: Double = b.landed ? 1 + 0.05 * min(2, life) * sin(1.6 * b.slow + Double(b.seed)) : 1
        let head: Double = 0.4 * hh, tail: Double = -0.78 * hh * breath
        let step: Double = 0.45 * min(cw, ch)
        let bl = ink.body, bi = ink.bodyInk
        let eyes = 2 * P.hs / cw >= 15
        var headCell = -1
        var a = tail
        let paperBody = paperWash(MeadowRGB(60, 52, 46), 0.55)
        while a <= head + 0.01 {
            defer { a += step }
            let x: Double = P.cx + fx * a, y: Double = P.cy + fy * a
            let i = cellOf(x, y)
            if i < 0 { continue }
            let t: Double = (a - tail) / (head - tail)
            let cx: Double = ox + (Double(i % cols) + 0.5) * cw, cy: Double = oy + (Double(i / cols) + 0.5) * ch
            let g: UInt8 = t > 0.86 ? (eyes ? MG.pct : MG.o) : t > 0.58 ? MG.eight : t < 0.08 ? MG.mid : meadowLine(fx, fy, lineRow(P.cx, P.cy, fx, fy, cx, cy))
            if LIGHT { blockAt(i, paperBody.0, paperBody.1, paperBody.2, 1) } else { wBlock(i, bl.x * dim, bl.y * dim, bl.z * dim, 1) }
            wingStamp[i] = stampV
            let key = keyOf(MeadowMath.round(a / (cw * 0.9)), 0, Double(b.id * 8 + 7))
            let s = t <= 0.86 ? shimmer(key, 0.06, 0.10) : 0
            if s != 0 { shimmerGlyph(i, g, s, key, false) }
            else if LIGHT { glyphAt(i, g, 26, 22, 20, 0.95) }
            else { wGlyph(i, g, bi.x * dim, bi.y * dim, bi.z * dim, 0.95) }
            if t > 0.86 { headCell = i }
        }
        if eyes {
            for side in 0..<2 {
                let sg: Double = side == 0 ? -1 : 1
                let a2: Double = head - 0.04 * hh
                let x: Double = P.cx + fx * a2 + rx * sg * 0.85 * cw, y: Double = P.cy + fy * a2 + ry * sg * 0.85 * cw
                let i = cellOf(x, y)
                if i < 0 || i == headCell { continue }
                if LIGHT { let c = paperWash(MeadowRGB(36, 36, 42), 0.7); blockAt(i, c.0, c.1, c.2, 1) } else { wBlock(i, 12 * dim, 12 * dim, 14 * dim, 1) }
                wingStamp[i] = stampV
                if LIGHT { glyphAt(i, MG.o, 247, 246, 243, 1) } else { glyphAt(i, MG.o, 154, 160, 173, 1) }
            }
        }
        let fe = ink.feeler, fl = max(1, lum(fe.x, fe.y, fe.z))
        if b.landed && b.stroke > 45 * DEG {
            let len: Double = max(1.6 * cw, 0.36 * hh), lv: Double = 118 * dim
            for leg in 0..<3 {
                let at = MeadowFrame.legAt[leg], ang = MeadowFrame.legAngle[leg]
                for side in 0..<2 {
                    let sg: Double = side == 0 ? -1 : 1
                    let dxL: Double = fx * cos(ang) + rx * sin(ang) * sg, dyL: Double = fy * cos(ang) + ry * sin(ang) * sg
                    let lx: Double = P.cx + fx * at * hh, ly: Double = P.cy + fy * at * hh
                    var last = -1
                    var s: Double = 0.45 * cw
                    while s <= len {
                        defer { s += step }
                        let i = cellOf(lx + dxL * s, ly + dyL * s)
                        if i < 0 || i == last { continue }
                        last = i
                        if wingStamp[i] == stampV { continue }
                        let cx: Double = ox + (Double(i % cols) + 0.5) * cw, cy: Double = oy + (Double(i / cols) + 0.5) * ch
                        let kb: Double = lv * 0.34 / fl, kg: Double = lv * 1.12 / fl
                        sBlock(i, fe.x * kb, fe.y * kb, fe.z * kb, 1)
                        sGlyph(i, meadowLine(dxL, dyL, lineRow(lx, ly, dxL, dyL, cx, cy)), min(255, fe.x * kg), min(255, fe.y * kg), min(255, fe.z * kg), 1)
                    }
                }
            }
        }
        let alen: Double = max(1.6 * cw, 0.62 * hh)
        for side in 0..<2 {
            let sgn: Double = side == 0 ? -1 : 1
            let at = sgn < 0 ? b.antT0 : b.antT1, sideS = sgn < 0 ? b.antS0 : b.antS1
            let tw: Double = at > 0 ? sideS * 0.25 * sin(.pi * (1 - at / 0.3)) : 0
            let ang: Double = (b.landed ? 0.42 : 0.42 + 0.06 * sin(b.phase)) + tw
            let dxA: Double = fx * cos(ang) + rx * sin(ang) * sgn, dyA: Double = fy * cos(ang) + ry * sin(ang) * sgn
            let ax: Double = P.cx + fx * head, ay: Double = P.cy + fy * head
            var last = -1
            var s: Double = 0.7 * cw
            while s <= alen {
                defer { s += step }
                let i = cellOf(ax + dxA * s, ay + dyA * s)
                if i < 0 || i == last { continue }
                last = i
                let cx: Double = ox + (Double(i % cols) + 0.5) * cw, cy: Double = oy + (Double(i / cols) + 0.5) * ch
                let g: UInt8 = s + step > alen ? MG.deg : meadowLine(dxA, dyA, lineRow(ax, ay, dxA, dyA, cx, cy))
                lGlyph(i, g, fe.x * dim, fe.y * dim, fe.z * dim, 0.85)
            }
        }
        if (b.state == .nectar || b.state == .cursor) && b.landK >= 1 {
            let ax: Double = P.cx + fx * head, ay: Double = P.cy + fy * head
            var last = -1
            var s: Double = 0.55 * cw
            while s <= 1.05 * cw {
                defer { s += 0.25 * cw }
                let i = cellOf(ax + fx * s, ay + fy * s)
                if i < 0 || i == last || wingStamp[i] == stampV { continue }
                last = i
                let cx: Double = ox + (Double(i % cols) + 0.5) * cw, cy: Double = oy + (Double(i / cols) + 0.5) * ch
                lGlyph(i, meadowLine(fx, fy, lineRow(ax, ay, fx, fy, cx, cy)), fe.x * dim, fe.y * dim, fe.z * dim, 0.8)
            }
        }
    }

    /// `drawShadow` (html:2487–2506).
    mutating func drawShadow(_ world: MeadowWorld, _ b: Butterfly) {
        let k0: Double = tuning.shadow * (LIGHT ? 0.9 : 0.8) * (1 - 0.55 * b.z)
        if k0 <= 0.01 { return }
        let off: Double = b.z * 150 * S + 3 * S
        let rough: Double = b.sp.span * 13 * S * b.size * world.depthScale(0) * 0.5 * 1.6 + 2 * cw
        guard cellBox(b.x - MeadowLight.x * off, b.y - MeadowLight.y * off, rough) != nil else { return }
        let P = setPose(world, b, shadow: true)
        let reach: Double = max(P.hs, P.hh * 1.5) + cw
        guard let (c0, c1, r0, r1) = cellBox(P.cx, P.cy, reach) else { return }
        let spread: Double = (0.3 + 0.9 * b.z) * 1.5
        let third: Double = 1.0 / 3
        for r in r0...r1 {
            let py: Double = oy + (Double(r) + 0.5) * ch
            spans.row(0, py - third * ch * spread)
            spans.row(1, py)
            spans.row(2, py + third * ch * spread)
            // Only the columns the outlines (and the body along the axis) reach on these rows.
            var lo = Double.infinity, hi = -Double.infinity
            if let (a, b) = spans.extent() { lo = a; hi = b }
            let pad: Double = third * cw * spread + cw
            let ua: Double = -0.78 * P.hh, ub: Double = 0.4 * P.hh
            lo = min(lo, P.cx + P.fx * ua - 2 * cw, P.cx + P.fx * ub - 2 * cw)
            hi = max(hi, P.cx + P.fx * ua + 2 * cw, P.cx + P.fx * ub + 2 * cw)
            if lo > hi { continue }
            let ca = max(c0, Int(floor((lo - pad - ox) / cw)) - 1), cb = min(c1, Int(floor((hi + pad - ox) / cw)) + 1)
            if ca > cb { continue }
            for c in ca...cb {
                let px: Double = ox + (Double(c) + 0.5) * cw
                var cov = 0
                for a in -1...1 {
                    let x: Double = px + Double(a) * third * cw * spread
                    for j in 0..<3 where spans.part(j, x) >= 0 { cov += 1 }
                }
                let dx = px - P.cx, dy = py - P.cy
                let u: Double = dx * P.fx + dy * P.fy, v: Double = dx * P.rx + dy * P.ry
                if abs(v) < 0.5 * cw && u < 0.4 * P.hh && u > -0.78 * P.hh { cov = max(cov, 6) }
                if cov > 0 { shade(r * cols + c, k0 * Double(cov) / 9) }
            }
        }
    }
}
