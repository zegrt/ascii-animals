import Foundation

// The flowers seen from above, ported from the sketch (`headSample`, `leafSample`, `drawFlower`, `paperPart`;
// html:980–1281, 534–557). `html:N` is a line of `Tools/meadow-sketch/meadow.html` on `meadow-sketch` at 4e1b869.
//
// A flower's cells are recorded once (`drawFlowerCells`) and replayed each frame with its current depth push, fade
// and shimmer, until its head moves a quarter cell from where it was drawn, or it grows, fades, its visit dim
// changes or it is resized; then it is drawn again.

/// The paper palette per kind and part (`PAPER_PLANTS`, html:537–548).
private enum PaperPlants {
    static let leaf = PaperPart(MeadowRGB(120, 158, 104), 0.17, MeadowRGB(108, 132, 96), 0.5)
    static let thread = PaperPart(MeadowRGB(0, 0, 0), 0, MeadowRGB(124, 144, 110), 0.5)

    static func part(_ kind: FlowerKind, _ p: FlowerPart) -> PaperPart {
        switch p {
        case .leaf: return leaf
        case .thread: return thread
        default: break
        }
        switch kind {
        case .daisy:
            if p == .petal { return PaperPart(MeadowRGB(238, 228, 200), 0.45, MeadowRGB(96, 94, 86), 0.9) }
            if p == .disc { return PaperPart(MeadowRGB(236, 178, 34), 0.75, MeadowRGB(112, 76, 10), 0.9) }
        case .coneflower:
            if p == .petal { return PaperPart(MeadowRGB(206, 96, 170), 0.42, MeadowRGB(130, 52, 104), 0.85) }
            if p == .disc { return PaperPart(MeadowRGB(190, 92, 30), 0.85, MeadowRGB(74, 32, 10), 0.9) }
        case .dandelion:
            if p == .petal { return PaperPart(MeadowRGB(244, 198, 24), 0.55, MeadowRGB(140, 100, 0), 0.85) }
            if p == .disc { return PaperPart(MeadowRGB(230, 150, 20), 0.8, MeadowRGB(110, 70, 0), 0.9) }
        case .milkweed:
            if p == .floret { return PaperPart(MeadowRGB(224, 120, 156), 0.48, MeadowRGB(128, 38, 78), 1) }
            if p == .cluster { return PaperPart(MeadowRGB(176, 96, 130), 0.4, MeadowRGB(176, 96, 128), 0.6) }
        case .clover:
            if p == .floret { return PaperPart(MeadowRGB(206, 104, 150), 0.48, MeadowRGB(124, 40, 82), 1) }
            if p == .tip { return PaperPart(MeadowRGB(226, 170, 196), 0.4, MeadowRGB(150, 80, 112), 0.85) }
            if p == .cluster { return PaperPart(MeadowRGB(170, 90, 128), 0.4, MeadowRGB(170, 90, 128), 0.6) }
        case .fennel:
            if p == .umbel { return PaperPart(MeadowRGB(228, 208, 80), 0.55, MeadowRGB(122, 104, 18), 0.9) }
            if p == .ray { return PaperPart(MeadowRGB(0, 0, 0), 0, MeadowRGB(126, 142, 92), 0.75) }
        case .mustard:
            if p == .mflower { return PaperPart(MeadowRGB(238, 204, 50), 0.6, MeadowRGB(120, 96, 0), 0.95) }
            if p == .mpetal { return PaperPart(MeadowRGB(0, 0, 0), 0, MeadowRGB(196, 156, 20), 0.85) }
            if p == .bud { return PaperPart(MeadowRGB(0, 0, 0), 0, MeadowRGB(112, 126, 56), 0.8) }
        }
        return thread
    }
}

/// The five samples per cell (`SUB5`, html:1194).
let SUB5: [(Double, Double)] = [(0.5, 0.5), (0.25, 0.3), (0.75, 0.3), (0.25, 0.72), (0.75, 0.72)]

extension MeadowFrame {
    /// `paperPart` (html:553–557): a part's paper block, ink and alpha at its shading k.
    @inline(__always) mutating func paperPart(_ kind: FlowerKind, _ part: FlowerPart, _ k: Double) -> (block: (Double, Double, Double), ink: MeadowRGB, alpha: Double) {
        let e = PaperPlants.part(kind, part)
        let c = paperWash(e.pig, e.amount * clamp(1.5 - 0.55 * k, 0.6, 1.4))
        return (c, e.ink, e.alpha)
    }

    /// Every flower, recorded or replayed.
    mutating func drawFlowers() {
        let sparkleK: Double = 1 / (1 + tuning.depth)
        let vx1: Double = ox + Double(cols) * cw, vy1: Double = oy + Double(rows) * ch
        // A recording has at most 3 writes a cell (a block, a glyph and a shade) over the box its reach covers.
        let reachB: Double = world.flowers.reachBound
        let boxC: Double = min(Double(cols), 2 * reachB / cw + 2), boxR: Double = min(Double(rows), 2 * reachB / ch + 2)
        let opsN: Int = boxC.isFinite && boxR.isFinite ? 3 * Int(boxC.rounded(.up)) * Int(boxR.rounded(.up)) : 0
        v.ensureSlots(world.flowers.most, ops: opsN)
        for f in world.flowers.all {
            let fk: Double = f.fading ? ease01(clamp(f.fade, 0, 1)) : 1
            if fk <= 0 { continue }
            let reach = f.reach
            if f.x + reach < ox || f.x - reach > vx1 || f.y + reach < oy || f.y - reach > vy1 { continue }
            let grow: Double = f.grow * (0.6 + 0.4 * fk)
            let leafGrow: Double = (f.age >= 1 ? 1 : clamp(f.age * 1.6, 0, 1)) * (0.85 + 0.15 * fk)
            let vd: Double = (f.visitDim * 50).rounded() / 50
            let hx = f.x + f.ox, hy = f.y + f.oy
            let cache = v.slot(f.id, paint: viewPaints)
            cache.used = viewPaints
            let moved = !(abs(hx - cache.hx) <= 0.25 * cw && abs(hy - cache.hy) <= 0.25 * ch)
            if moved || cache.grow != grow || cache.leafGrow != leafGrow || cache.fk != fk || cache.vd != vd || cache.radius != f.radius {
                cache.ops.removeAll(keepingCapacity: true)
                recording = cache
                drawFlowerCells(f, hx, hy, grow, leafGrow, vd, fk)
                recording = nil
                cache.hx = hx; cache.hy = hy; cache.grow = grow; cache.leafGrow = leafGrow; cache.fk = fk; cache.vd = vd
                cache.radius = f.radius
            }
            // Replay, pushed back with the meadow; a flower being fed comes forward a little (html:1203–1205).
            INK_K = fk
            farPush(tuning.depth * (1 - 0.45 * f.lift))
            let accK: Double = 0.03 * sparkleK * sparkleRate, fleckK: Double = 0.05 * sparkleK * sparkleRate
            cache.ops.withUnsafeMutableBufferPointer { ops in
                for k in 0..<ops.count {
                    let i = Int(ops[k].cell)
                    switch ops[k].kind {
                    case .block: put(i, Double(ops[k].r), Double(ops[k].g), Double(ops[k].b), Double(ops[k].a))
                    case .glyph: putGlyph(i, ops[k].gi, Double(ops[k].r), Double(ops[k].g), Double(ops[k].b), Double(ops[k].a))
                    case .shimmerGlyph:
                        // `shimmer` (html:597–602), its roll kept until the cell's next tick.
                        let key = ops[k].key
                        var s = 0
                        if sparkleRate > 0 {
                            let tick = Int32(clamping: Int(floor(simT * 2.4 + Double(key % 997) / 97)))
                            if ops[k].tick != tick {
                                ops[k].tick = tick
                                ops[k].roll = Float(mhash(Double(key), Double(tick), 7))
                            }
                            let roll = Double(ops[k].roll)
                            s = !LIGHT && roll < accK ? 1 : roll < fleckK ? 2 : 0
                        }
                        if s != 0 { shimmerGlyph(i, ops[k].gi, s, key, false) }
                        else { putGlyph(i, ops[k].gi, Double(ops[k].r), Double(ops[k].g), Double(ops[k].b), Double(ops[k].a)) }
                    case .clearGlyph: touch(i); GI[i] = MG.none
                    case .shade: shadeNow(i, Double(ops[k].a))
                    }
                }
            }
            INK_K = 1
            farPush(0)
        }
        if viewPaints % ViewportCache.sweepEvery == 0 { v.sweep(viewPaints, keepLast: false) }
    }

    @inline(__always) mutating func shadeNow(_ i: Int, _ k: Double) {
        let saved = recording
        recording = nil
        shade(i, k)
        recording = saved
    }

    /// `drawFlower` (html:1198–1281), recorded: the head by the family's coverage rule, the leaves under it and the
    /// head's shadow on them.
    mutating func drawFlowerCells(_ f: Flower, _ hx: Double, _ hy: Double, _ grow: Double, _ leafGrow: Double, _ vd: Double, _ fk: Double) {
        let reach = f.reach
        let c0 = max(0, Int(floor((f.x - reach - ox) / cw))), c1 = min(cols - 1, Int(floor((f.x + reach - ox) / cw)))
        let r0 = max(0, Int(floor((f.y - reach - oy) / ch))), r1 = min(rows - 1, Int(floor((f.y + reach - oy) / ch)))
        guard c0 <= c1 && r0 <= r1 else { return }
        let so: Double = 0.32 * f.radius + 4 * S
        let sx: Double = hx - MeadowLight.x * so, sy: Double = hy - MeadowLight.y * so
        let sRad: Double = f.radius * grow * 0.95
        let headReach: Double = f.radius * grow * 1.12 + cw
        let seed = Double(f.seed)
        for r in r0...r1 {
            for c in c0...c1 {
                let x0: Double = ox + Double(c) * cw, y0: Double = oy + Double(r) * ch
                let px: Double = x0 + 0.5 * cw, py: Double = y0 + 0.5 * ch
                let i = r * cols + c
                var hits = 0
                var h = FlowerHit()
                var centre = false
                if abs(px - hx) <= headReach && abs(py - hy) <= headReach {
                    headSample(f, px - hx, py - hy, grow)
                    centre = fh.hit != 0 && fh.solid
                    if fh.hit != 0 && !fh.solid {
                        // A ray, as silk.
                        if LIGHT {
                            let pp = paperPart(f.kind, fh.part, 1)
                            glyphAt(i, fh.gi, pp.ink.x, pp.ink.y, pp.ink.z, pp.alpha * fh.ia)
                        } else { lGlyph(i, fh.gi, fh.ir, fh.ig, fh.ib, fh.ia) }
                        continue
                    }
                    hits = centre ? 1 : 0
                    h = fh
                    for k in 1..<5 {
                        headSample(f, x0 + SUB5[k].0 * cw - hx, y0 + SUB5[k].1 * ch - hy, grow)
                        if fh.hit != 0 && fh.solid {
                            hits += 1
                            if !centre && hits == 1 {
                                h.r = fh.r; h.g = fh.g; h.b = fh.b; h.ir = fh.ir; h.ig = fh.ig; h.ib = fh.ib; h.part = fh.part; h.k = fh.k
                            }
                        }
                    }
                }
                if hits > 0 {
                    let cov = Double(hits) / 5
                    let key = keyOf(MeadowMath.round((px - hx) / (cw * 0.9)), MeadowMath.round((py - hy) / (cw * 0.9)), seed)
                    var pp = (block: (0.0, 0.0, 0.0), ink: MeadowRGB(0, 0, 0), alpha: 1.0)
                    if LIGHT { pp = paperPart(f.kind, h.part, h.k) }
                    if centre && cov >= 0.6 {
                        var sr = h.r, sg = h.g, sb = h.b
                        var gi = h.gi
                        if h.disc && vd > 0 {
                            let k: Double = 1 - 0.15 * vd
                            sr *= k; sg *= k; sb *= k
                            if vd > 0.5 { gi = MG.dimStep(gi) }
                            if LIGHT {
                                let m: Double = 0.15 * vd
                                pp.block = (pp.block.0 + (247 - pp.block.0) * m, pp.block.1 + (246 - pp.block.1) * m, pp.block.2 + (243 - pp.block.2) * m)
                            }
                        }
                        if LIGHT { blockAt(i, pp.block.0, pp.block.1, pp.block.2, 1) }
                        else if h.lit || lum(sr, sg, sb) > 110 { wBlock(i, sr, sg, sb, 1) } else { sBlock(i, sr, sg, sb, 1) }
                        if gi != MG.none {
                            if LIGHT { recordShimmer(i, gi, pp.ink.x, pp.ink.y, pp.ink.z, pp.alpha * min(1, h.ia + 0.1), key) }
                            else { recordShimmer(i, gi, h.ir, h.ig, h.ib, h.ia, key) }
                        } else { clearGlyph(i) }
                    } else {
                        let e: UInt8 = cov >= 0.5 ? MG.heavy[Int((key >> 8) & 1)] : MG.lightEdge[Int((key >> 8) & 3)]
                        if LIGHT { glyphAt(i, e, pp.ink.x, pp.ink.y, pp.ink.z, pp.alpha * (0.35 + 0.5 * cov)) }
                        else { edgeGlyph(i, e, MeadowRGB(h.ir, h.ig, h.ib), 70 + 80 * cov) }
                    }
                    continue
                }
                // The head's shadow on the leaves and ground.
                let sd = hypot(px - sx, py - sy)
                let shadowK: Double = sd < sRad ? 0.55 * tuning.shadow * MeadowMath.smooth(sRad, f.radius * grow * 0.5, sd) : 0
                if leafGrow > 0 {
                    leafSample(f, (px - f.x) / leafGrow, (py - f.y) / leafGrow)
                    if fh.hit != 0 && LIGHT {
                        let pp = paperPart(f.kind, fh.part, fh.k)
                        if fh.solid { blockAt(i, pp.block.0, pp.block.1, pp.block.2, 1) }
                        if fh.gi != MG.none { glyphAt(i, fh.gi, pp.ink.x, pp.ink.y, pp.ink.z, pp.alpha * fh.ia / 0.7) }
                        else if fh.solid { clearGlyph(i) }
                    } else if fh.hit != 0 {
                        if fh.solid { sBlock(i, fh.r, fh.g, fh.b, 1, 0.16) }
                        if fh.gi != MG.none {
                            if fh.solid { sGlyph(i, fh.gi, fh.ir, fh.ig, fh.ib, fh.ia) } else { lGlyph(i, fh.gi, fh.ir, fh.ig, fh.ib, fh.ia) }
                        } else if fh.solid { clearGlyph(i) }
                    }
                }
                if shadowK > 0 { shade(i, min(0.85, shadowK) * fk) }
            }
        }
    }

    @inline(__always) mutating func recordShimmer(_ i: Int, _ gi: UInt8, _ r: Double, _ g: Double, _ b: Double, _ a: Double, _ key: UInt32) {
        if let rc = recording {
            rc.ops.append(FlowerOp(kind: .shimmerGlyph, gi: gi, cell: Int32(i), r: Float(r), g: Float(g), b: Float(b), a: Float(a), key: key))
        } else {
            putGlyph(i, gi, r, g, b, a)
        }
    }

    /// `headSample` (html:993–1140): a bloom's head at offset (dx, dy) from its centre, always in the dark palette.
    mutating func headSample(_ f: Flower, _ dx: Double, _ dy: Double, _ grow: Double) {
        fh.hit = 0
        let Rr: Double = f.radius * grow
        if Rr <= 0.5 { return }
        let r = (dx * dx + dy * dy).squareRoot()
        if r > Rr * 1.12 { return }
        let P = PlantInk.self
        let th = atan2(dy, dx)
        let lit = cos(th - MeadowLight.angle)
        let s = Double(f.seed)
        let rot = f.turn
        let LX = MeadowLight.x, LY = MeadowLight.y, LZ = MeadowLight.z
        switch f.kind {
        case .daisy, .coneflower, .dandelion:
            let daisy = f.kind == .daisy, cone = f.kind == .coneflower
            let eye: Double = Rr * (daisy ? 0.3 : cone ? 0.42 : 0.26)
            if r < eye {
                let t = r / eye
                let dome: Double = 0.78 + 0.32 * lit * t - 0.18 * t * t
                let base = daisy ? P.daisyEye : cone ? P.coneEye : P.dandelionEye
                let ink = daisy ? P.daisyEyeInk : cone ? P.coneEyeInk : P.dandelion
                let h = mhash(MeadowMath.round(dx / cw * 2), MeadowMath.round(dy / ch * 2), s)
                let gi: UInt8 = cone ? (h < 0.5 ? MG.star : h < 0.75 ? MG.x : MG.plus) : daisy ? (t < 0.35 ? MG.o : h < 0.5 ? MG.mid : MG.deg) : (h < 0.5 ? MG.star : MG.mid)
                fh.set(3, base.x * dome, base.y * dome, base.z * dome, gi, ink.x, ink.y, ink.z, 0.85, true)
                fh.disc = true
                fh.lit = !cone
                fh.part = .disc
                fh.k = dome
                return
            }
            let n = Double(f.petals)
            let u: Double = ((th - rot) / TAU * n).truncatingRemainder(dividingBy: n) + n
            let uu: Double = u.truncatingRemainder(dividingBy: n)
            let idx = Double(Int(floor(uu + 0.5)) % max(1, f.petals))
            let frac: Double = uu - MeadowMath.round(uu)
            let len: Double = Rr * (0.84 + 0.18 * mhash(idx, 3, s)) * (cone ? 0.94 : 1)
            if r > len { return }
            let t: Double = clamp((r - eye) / (len - eye), 0, 1)
            let lat: Double = abs(frac) * TAU / n * r
            let pw0: Double = (daisy ? 0.15 : cone ? 0.24 : 0.2) * Rr
            let pw: Double = pw0 * pow(sin(.pi * clamp(0.2 + 0.8 * t, 0, 1)), 0.6) * (0.6 + 0.4 * t)
            let dense = f.kind == .dandelion
            if lat > pw && !dense { return }
            let base = daisy ? P.daisy : cone ? P.cone : P.dandelion
            let vv: Double = 0.88 + 0.2 * mhash(idx, 7, s)
            var k: Double = daisy ? (0.6 + 0.4 * t) : cone ? (0.95 - 0.35 * t) : (0.7 + 0.3 * t)
            k *= vv * (1 + 0.18 * lit) * (0.75 + 0.25 * MeadowMath.smooth(0, 0.3, t))
            let block: Double = daisy ? 0.22 : cone ? 0.36 : 0.45
            let pa: Double = rot + MeadowMath.round(uu) * TAU / n
            var gi: UInt8
            if dense {
                gi = mhash(MeadowMath.round(dx / cw), MeadowMath.round(dy / ch), s + 3) < 0.35 ? MG.star : meadowLine(cos(th), sin(th), 0.5)
            } else if t > 0.86 {
                gi = mhash(idx, 11, s) < 0.5 ? MG.quote : MG.dot
            } else {
                let ca = cos(pa), sa = sin(pa)
                gi = meadowLine(ca, sa, lineRow(0, 0, ca, sa, dx, dy))
            }
            let ik: Double = min(1.15, 0.75 + 0.45 * k)
            let kb: Double = k * block
            fh.set(2, base.x * kb, base.y * kb, base.z * kb, gi, min(255, base.x * ik), min(255, base.y * ik), min(255, base.z * ik), 0.92, true)
            fh.part = .petal
            fh.k = k
        case .milkweed, .clover:
            let clover = f.kind == .clover
            if r > Rr { return }
            let t = r / Rr
            let nz = max(0, 1 - t * t).squareRoot()
            let nx = dx / Rr, ny = dy / Rr
            let lam: Double = clamp(nx * LX + ny * LY + nz * LZ, 0, 1)
            let body = clover ? P.cloverBody : P.milkweedBody
            let fl = clover ? P.clover : P.milkweed
            let cs = cos(rot), sn = sin(rot)
            let lx: Double = dx * cs + dy * sn, ly: Double = -dx * sn + dy * cs
            let cellR: Double = Rr * (clover ? 0.42 : 0.34)
            let gx = lx / cellR, gy = ly / cellR
            var best = 9.0
            let fx0 = floor(gx), fy0 = floor(gy)
            for j in -1...1 {
                for i in -1...1 {
                    let cx = fx0 + Double(i), cy = fy0 + Double(j)
                    let px: Double = cx + 0.25 + 0.5 * mhash(cx, cy, s)
                    let py: Double = cy + 0.25 + 0.5 * mhash(cx, cy, s + 1)
                    best = min(best, hypot(gx - px, gy - py))
                }
            }
            let shadeK: Double = 0.45 + 0.75 * lam
            if best < 0.36 {
                let tip = clover && t > 0.55 ? P.cloverTip : fl
                let ink = clover ? P.cloverTip : P.milkweedInk
                let gi: UInt8 = clover ? (t > 0.6 ? MG.quote : MG.deg) : (best < 0.18 ? MG.star : MG.deg)
                let bk: Double = shadeK * 0.62
                fh.set(2, tip.x * bk, tip.y * bk, tip.z * bk, gi, ink.x, ink.y, ink.z, 0.6 + 0.4 * lam, true)
                fh.part = clover && t > 0.55 ? .tip : .floret
            } else {
                fh.set(2, body.x * shadeK, body.y * shadeK, body.z * shadeK, best > 0.55 ? MG.mid : MG.none, fl.x, fl.y, fl.z, 0.4, true)
                fh.part = .cluster
            }
            fh.disc = true
            fh.k = shadeK
        case .fennel:
            let n = Double(f.petals)
            let u: Double = (((th - rot) / TAU * n).truncatingRemainder(dividingBy: n) + n).truncatingRemainder(dividingBy: n)
            let idxI = Int(MeadowMath.round(u)) % max(1, f.petals)
            let idx = Double(idxI)
            let ra: Double = rot + MeadowMath.round(u) * TAU / n
            let rr: Double = Rr * (0.58 + 0.14 * mhash(idx, 2, s))
            let ux = cos(ra) * rr, uy = sin(ra) * rr
            let ur: Double = Rr * (0.29 + 0.05 * mhash(idx, 4, s))
            let du = hypot(dx - ux, dy - uy)
            let P2 = P.fennel
            if du < ur {
                let t = du / ur
                let h = mhash(MeadowMath.round(dx / cw * 1.5), MeadowMath.round(dy / ch * 1.5), s + idx)
                let k: Double = (0.75 + 0.35 * (1 - t)) * (1 + 0.15 * lit)
                let gi: UInt8 = t < 0.45 ? (h < 0.5 ? MG.colon : MG.star) : h < 0.55 ? MG.mid : h < 0.8 ? MG.deg : MG.dot
                let bk: Double = 0.3 * (1 - t) * k
                fh.set(2, P2.x * bk, P2.y * bk, P2.z * bk, gi, min(255, P2.x * k), min(255, P2.y * k), min(255, P2.z * k), 0.95, t < 0.55)
                fh.disc = true
                fh.part = .umbel
                fh.k = k
                return
            }
            let ca = cos(ra), sa = sin(ra)
            let along: Double = dx * ca + dy * sa
            let major = abs(ca) >= abs(sa)
            let off: Double = major ? dy - dx * sa / ca : dx - dy * ca / sa
            let c = P.fennelRay
            if along > 0.08 * Rr && along < rr && abs(off) <= (major ? 0.5 * ch : 0.5 * cw) {
                fh.set(1, 0, 0, 0, meadowLine(ca, sa, lineRow(0, 0, ca, sa, dx, dy)), c.x, c.y, c.z, 0.8, false)
            } else if r < 0.1 * Rr {
                fh.set(1, 0, 0, 0, MG.star, c.x, c.y, c.z, 0.9, false)
            }
            fh.part = .ray
            fh.k = 1
        case .mustard:
            var i = f.florets.count - 1
            while i >= 0 {
                let q = f.florets[i]
                let qx: Double = dx - q.x * grow, qy: Double = dy - q.y * grow
                let d = hypot(qx / cw, qy / ch * 1.25)
                if d > 1.15 { i -= 1; continue }
                fh.k = 1
                if !q.open {
                    let c = P.mustardBud
                    fh.set(1, 0, 0, 0, d < 0.6 ? MG.o : MG.mid, c.x, c.y, c.z, 0.85, false)
                    fh.part = .bud
                    return
                }
                let c = P.mustard
                if d < 0.6 {
                    let bk = 0.55
                    fh.set(2, c.x * bk, c.y * bk, c.z * bk, MG.plus, min(255, c.x * 1.1), min(255, c.y * 1.1), min(255, c.z * 1.1), 1, true)
                    fh.part = .mflower
                    return
                }
                fh.set(1, 0, 0, 0, mhash(Double(i), MeadowMath.round(qx), s) < 0.5 ? MG.mid : MG.quote, c.x, c.y, c.z, 0.85, false)
                fh.part = .mpetal
                return
            }
        }
    }

    /// `lineRow` (html:634–637): where a line through (lx, ly) along (dx, dy) runs in the cell centred at (px, py).
    @inline(__always) mutating func lineRow(_ lx: Double, _ ly: Double, _ dx: Double, _ dy: Double, _ px: Double, _ py: Double) -> Double {
        let yAt: Double = abs(dx) > 0.2 * abs(dy) ? ly + (px - lx) * dy / dx : ly
        return clamp(0.5 + (yAt - py) / ch, 0, 1)
    }

    /// `leafSample` (html:1142–1191): the leaves under a bloom at offset (dx, dy) from its foot.
    mutating func leafSample(_ f: Flower, _ dx: Double, _ dy: Double) {
        fh.hit = 0
        let amt = tuning.leaves
        if amt <= 0 { return }
        let P = PlantInk.self
        var i = f.leaves.count - 1
        while i >= 0 {
            let l = f.leaves[i]
            i -= 1
            let len: Double = l.length * min(1, 0.4 + 0.6 * amt), wid: Double = l.width * min(1.3, amt)
            let ca = cos(l.angle), sa = sin(l.angle)
            let along: Double = dx * ca + dy * sa, lat: Double = -dx * sa + dy * ca
            if l.kind == 3 {
                let cx: Double = along - len * 0.55
                for j in 0..<3 {
                    let aa: Double = Double(j) * TAU / 3 + 0.5
                    let lx: Double = cx - cos(aa) * wid * 0.3, ly: Double = lat - sin(aa) * wid * 0.3
                    let d = hypot(lx, ly)
                    if d < wid * 0.3 {
                        let chev = abs(d - wid * 0.16) < cw * 0.35
                        let c = chev ? P.leafLit : P.leaf
                        fh.set(1, c.x, c.y, c.z, chev ? MG.v : MG.none, P.rib.x, P.rib.y, P.rib.z, 0.7, true)
                        fh.part = .leaf
                        fh.k = chev ? 1.15 : 0.9
                        return
                    }
                }
                continue
            }
            if along < 0.08 * len || along > len { continue }
            let t = along / len
            var half: Double = wid * pow(sin(.pi * min(1, t * 1.08)), l.kind == 2 ? 0.55 : 0.8)
            if l.kind == 4 { half *= 0.78 + 0.22 * abs(sin(t * 14)) }
            if l.kind == 1 {
                if abs(lat) < 0.3 * cw {
                    fh.set(1, 0, 0, 0, meadowLine(ca, sa, lineRow(0, 0, ca, sa, dx, dy)), P.leafEdge.x, P.leafEdge.y, P.leafEdge.z, 0.7, false)
                    fh.part = .thread
                    fh.k = 1
                    return
                }
                continue
            }
            if abs(lat) > half { continue }
            let edge = abs(lat) > half - 0.45 * cw
            let mid = abs(lat) < 0.28 * cw
            let sgn: Double = lat > 0 ? 1 : lat < 0 ? -1 : 0
            let k: Double = 0.75 + 0.35 * (1 - abs(lat) / max(1, half)) + 0.15 * sgn * sin(l.angle - MeadowLight.angle)
            let c = P.leaf, cl = P.leafLit
            let bk: Double = clamp(k, 0.5, 1.2)
            let mixK: Double = clamp(0.5 - abs(t - 0.45), 0, 1)
            let br: Double = (c.x + (cl.x - c.x) * mixK) * bk
            let bg: Double = (c.y + (cl.y - c.y) * mixK) * bk
            let bb: Double = (c.z + (cl.z - c.z) * mixK) * bk
            if mid && t < 0.9 {
                fh.set(1, br, bg, bb, meadowLine(ca, sa, lineRow(0, 0, ca, sa, dx, dy)), P.rib.x, P.rib.y, P.rib.z, 0.75, true)
            } else if edge {
                let g: UInt8 = mhash(MeadowMath.round(dx / cw), MeadowMath.round(dy / ch), Double(f.seed)) < 0.5 ? MG.comma : MG.quote
                fh.set(1, br, bg, bb, g, P.leafEdge.x, P.leafEdge.y, P.leafEdge.z, 0.7, true)
            } else {
                fh.set(1, br, bg, bb, MG.none, 0, 0, 0, 0, true)
            }
            fh.part = .leaf
            fh.k = bk * (1 + 0.25 * mixK)
            return
        }
    }
}
