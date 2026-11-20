import Foundation

// Where the butterflies go and what they choose, ported from the sketch (`pickWaypoint`, `pickFlower`, `chooseNext`,
// `stepPointer`, `openingMoment`; html:1452–1513, 1906–1926, 1946–1972). `html:N` is a line of
// `Tools/meadow-sketch/meadow.html` on `meadow-sketch` at 4e1b869.

extension MeadowWorld {
    /// `pickWaypoint` (html:1452–1467): the best of 9 random points for being far from here, away from the others
    /// and their goals, and roughly ahead; a waypoint lasts 4–9 s. Several screens: each point on a screen picked by
    /// area, kept only if the straight way there stays on the screens (Web's `wanderGoal`), else one on its own screen.
    func pickWaypoint(_ b: Butterfly) {
        guard !screens.isEmpty else { return }
        if b.leaving { aimAtExit(b); b.wpLeft = 1e9; return }
        let own = screens[screen(near: b.x, b.y)]
        let diag = own.diag
        var bx = 0.0, by = 0.0
        var bs = -1e9
        var found = false
        for _ in 0..<9 {
            let s = screens[screenByArea()]
            let m: Double = 0.07 * min(s.w, s.h)
            let x: Double = s.minX + rng.range(m, s.w - m)
            let y: Double = s.minY + rng.range(m, s.h - m)
            let d = hypot(x - b.x, y - b.y)
            var sep = 1e9
            for o in flies where o !== b {
                sep = min(sep, hypot(o.x - x, o.y - y), hypot(o.wx - x, o.wy - y) * 1.3)
            }
            let ahead = cos(atan2(y - b.y, x - b.x) - b.heading)
            let far: Double = 0.9 * min(1, d / (0.5 * diag))
            let apart: Double = 1.1 * min(1, sep / (0.32 * diag))
            let near: Double = d < 0.18 * diag ? 1 : 0
            let score: Double = far + apart + 0.35 * ahead + 0.25 * rng.unit() - near
            if !single && !wayOpen(b.x, b.y, x, y) { continue }
            if score > bs { bs = score; bx = x; by = y; found = true }
        }
        if !found {
            let m: Double = 0.07 * min(own.w, own.h)
            bx = own.minX + rng.range(m, own.w - m)
            by = own.minY + rng.range(m, own.h - m)
        }
        b.wx = bx
        b.wy = by
        b.wpLeft = rng.range(4, 9)
    }

    /// `pickFlower` (html:1471–1490): a flower it can sense, within `sense` wingspans and not behind it, weighted by
    /// the species' favourites and by room from the others. Returns its index in `flowers.all`.
    func pickFlower(_ b: Butterfly) -> Int? {
        guard !screens.isEmpty else { return nil }
        let diag = screens[screen(near: b.x, b.y)].diag
        let sr = spanRef(b)
        let range: Double = tuning.sense * sr
        let hx = cos(b.heading), hy = sin(b.heading)
        var tot = 0.0
        candFlower.removeAll(keepingCapacity: true)
        candWeight.removeAll(keepingCapacity: true)
        let all = flowers.all
        for (i, f) in all.enumerated() {
            if f.busy != 0 || f.age < 0.6 || f.fading { continue }
            let dx = f.x - b.x, dy = f.y - b.y, d = hypot(dx, dy)
            if d < 1.2 * sr || d > range || !onScreens(f.x, f.y) { continue }
            if (dx * hx + dy * hy) / d < -0.2 { continue }
            var crowded = false
            for o in flies where o !== b && o.landed && hypot(o.x - f.x, o.y - f.y) < 0.9 * (sr + spanRef(o)) { crowded = true; break }
            if crowded { continue }
            var w: Double = b.sp.weight(f.kind) * (1.2 - 0.6 * d / range)
            var sep = 1e9
            for o in flies where o !== b { sep = min(sep, hypot(o.x - f.x, o.y - f.y)) }
            w *= 0.25 + min(1, sep / (0.25 * diag))
            if w > 0 { candFlower.append(i); candWeight.append(w); tot += w }
        }
        if candFlower.isEmpty { return nil }
        var u = rng.unit() * tot
        for k in 0..<candFlower.count {
            u -= candWeight[k]
            if u <= 0 { return candFlower[k] }
        }
        return candFlower[candFlower.count - 1]
    }

    /// `visitChance`, `baskChance` (html:1493–1494).
    func visitChance(_ b: Butterfly) -> Double {
        tuning.visits * (tuning.hunger > 0.005 ? clamp(0.2 + 1.6 * (1 - b.energy), 0.2, 1.8) : 1)
    }
    func baskChance(_ b: Butterfly) -> Double {
        tuning.bask * (tuning.warmth > 0.005 ? clamp(0.45 + 1.4 * (1 - b.warmth), 0.45, 1.8) : 1)
    }

    /// `chooseNext` (html:1498–1513): on arrival, a flower visit, a bask on open ground, or travel on.
    func chooseNext(_ b: Butterfly) {
        releaseFlower(b)
        guard !screens.isEmpty else { return }
        let u = rng.unit(), pv = clamp(visitChance(b), 0, 1)
        if u < pv {
            if let f = pickFlower(b) { goToFlower(b, f); return }
        } else if u < pv + baskChance(b) * (1 - pv) {
            b.state = .approach
            b.goal = .bask
            b.flower = 0
            b.timer = 18
            b.tag = 1
            var best = (x: b.x, y: b.y)
            var bs = -1.0
            for _ in 0..<6 {
                let s = screens[screenByArea()]
                let m: Double = 0.1 * min(s.w, s.h)
                let x: Double = s.minX + rng.range(m, s.w - m)
                let y: Double = s.minY + rng.range(m, s.h - m)
                var sep = 1e9
                for o in flies where o !== b { sep = min(sep, hypot(o.x - x, o.y - y)) }
                let d = hypot(x - b.x, y - b.y)
                let sc: Double = min(sep, 400 * S) + (d > 200 * S ? 200 : 0)
                if sc > bs { bs = sc; best = (x, y) }
            }
            b.gx = best.x
            b.gy = best.y
            return
        }
        b.state = .fly
        b.goal = .none
        pickWaypoint(b)
    }

    /// `stepPointer` (html:1906–1926): hold the pointer still and one comes, weighted by species and nearness, and
    /// spirals in.
    func stepPointer(_ dt: Double) {
        cursorCd -= dt
        if !pointerHas || screens.isEmpty { pointerStill = 0; return }
        pointerStill += dt
        if !tuning.cursorLand || pointerStill < tuning.holdTime || cursorCd > 0 { return }
        for b in flies where b.goal == .cursor || b.state == .cursor { return }
        let diag = screens[screen(near: pointerX, pointerY)].diag
        var tot = 0.0
        candFly.removeAll(keepingCapacity: true)
        candWeight.removeAll(keepingCapacity: true)
        for b in flies {
            if b.leaving || b.entering || b.landed { continue }
            let w: Double = b.sp.cursorWeight / (1 + hypot(b.x - pointerX, b.y - pointerY) / (0.35 * diag))
            candFly.append(b)
            candWeight.append(w)
            tot += w
        }
        if candFly.isEmpty { return }
        var u = rng.unit() * tot
        var pick = candFly[candFly.count - 1]
        for k in 0..<candFly.count {
            u -= candWeight[k]
            if u <= 0 { pick = candFly[k]; break }
        }
        candFly.removeAll(keepingCapacity: true)
        releaseFlower(pick)
        pick.state = .approach
        pick.goal = .cursor
        pick.timer = 30
        pick.gliding = false
        pick.circleT = 0
        let span = spanRef(pick)
        var s = Spiral()
        s.loops = rng.range(1.5, 2.2)
        s.r0 = rng.range(1.3, 1.9) * span
        s.dir = rng.unit() < 0.5 ? 1 : -1
        pick.spiral = s
        cursorCd = 2
    }

    /// `openingMoment` (html:1946–1972): one already nectaring, one basking, one about to land on a flower, the
    /// rest flying.
    func openingMoment() {
        var fl = flies
        rng.shuffle(&fl)
        func onScreen(_ f: Flower) -> Bool {
            guard f.busy == 0 else { return false }
            let s = screens[screen(near: f.x, f.y)]
            return f.x > s.minX + 0.08 * s.w && f.x < s.maxX - 0.08 * s.w && f.y > s.minY + 0.08 * s.h && f.y < s.maxY - 0.08 * s.h
        }
        var i = 0
        if i < fl.count {
            let nect = fl[i]
            // The favourite (a stable sort by weight, highest first).
            var pick: Int? = nil
            var pw = -1.0
            for (k, f) in flowers.all.enumerated() where onScreen(f) {
                let w = nect.sp.weight(f.kind)
                if w > pw { pw = w; pick = k }
            }
            if let k = pick {
                let f = flowers.all[k]
                nect.x = f.x
                nect.y = f.y
                nect.flower = f.id
                flowers.setBusy(id: f.id, by: nect.id)
                nect.goal = .nectar
                nect.z = 0
                nect.zs = 0
                land(nect)
                nect.timer *= rng.range(0.5, 0.9)
                nect.landK = 1
                nect.heading = nect.landHeading
                nect.stroke = landedPose(nect, 0)
                i += 1
            }
        }
        if i < fl.count {
            let bask = fl[i]
            var best = (x: 0.0, y: 0.0)
            var bs = -1.0
            for _ in 0..<12 {
                let s = screens[screenByArea()]
                let x: Double = s.minX + rng.range(0.12, 0.88) * s.w
                let y: Double = s.minY + rng.range(0.12, 0.88) * s.h
                var sep = 1e9
                for o in flies where o !== bask && o.landed { sep = min(sep, hypot(o.x - x, o.y - y)) }
                for f in flowers.all { sep = min(sep, 1.5 * hypot(f.x - x, f.y - y)) }
                if sep > bs { bs = sep; best = (x, y) }
            }
            bask.x = best.x; bask.gx = best.x
            bask.y = best.y; bask.gy = best.y
            bask.goal = .bask
            bask.flower = 0
            bask.z = 0
            bask.zs = 0
            land(bask)
            bask.timer *= rng.range(0.5, 0.9)
            bask.landK = 1
            bask.heading = bask.landHeading
            bask.stroke = landedPose(bask, 0)
            i += 1
        }
        if i < fl.count {
            let come = fl[i]
            var opts: [Int] = []
            for (k, f) in flowers.all.enumerated() where onScreen(f) {
                var taken = false
                for o in flies where o.landed && hypot(o.x - f.x, o.y - f.y) < 0.9 * (spanRef(come) + spanRef(o)) { taken = true; break }
                if !taken { opts.append(k) }
            }
            if !opts.isEmpty {
                let k = opts[rng.int(0, opts.count - 1)]
                let f = flowers.all[k]
                let a = rng.range(0, TAU)
                let d: Double = rng.range(3, 4.5) * spanRef(come)
                let s = screens[screen(near: f.x, f.y)]
                come.x = clamp(f.x + cos(a) * d, s.minX + 0.05 * s.w, s.maxX - 0.05 * s.w)
                come.y = clamp(f.y + sin(a) * d, s.minY + 0.05 * s.h, s.maxY - 0.05 * s.h)
                come.heading = atan2(f.y - come.y, f.x - come.x)
                come.ux = cos(come.heading) * 60 * S
                come.uy = sin(come.heading) * 60 * S
                goToFlower(come, k)
                come.tag = 1
                come.zs = 0.3
                come.z = 0.3
            }
        }
    }
}

// ── the sketch's sheets (a development aid, html:3055–3070) ──

extension MeadowWorld {
    public enum Sheet: String, Sendable { case flowers, flies }

    /// `?sheet=flowers`: one bloom of each kind, grown, at the sketch's places; `?sheet=flies`: each species at four
    /// wing phases, at height `z`. Draws on the meadow's stream after the opening, as the sketch does. One screen.
    public func showSheet(_ sheet: Sheet, z: Double = 0.5) {
        guard let s = screens.first else { return }
        let W = s.w, H = s.h
        rng = simRandom
        flies.removeAll()
        flowers.showOnly([])
        switch sheet {
        case .flowers:
            var list: [Flower] = []
            for (i, k) in FlowerKind.allCases.enumerated() {
                let x: Double = s.minX + W * (0.14 + 0.24 * Double(i % 4)), y: Double = s.minY + H * (i < 4 ? 0.28 : 0.72)
                var f = flowers.make(k, x: x, y: y, grown: true, rng: simRandom)
                f.radius = k.spec.r * S * tuning.flowerSize * 1.05
                list.append(f)
            }
            flowers.showOnly(list)
        case .flies:
            let phases: [Double] = [0, 1.2, 2.2, 3.4]
            for (j, k) in ButterflyKind.allCases.enumerated() {
                for (i, ph) in phases.enumerated() {
                    let b = makeFly(k, edge: false)
                    b.x = s.minX + W * (0.13 + 0.25 * Double(i))
                    b.y = s.minY + H * (0.13 + 0.245 * Double(j))
                    b.heading = -Double.pi / 2 + (j % 2 == 1 ? 0.5 : -0.3)
                    b.phase = ph
                    b.stroke = b.sp.mid + b.sp.amp * cos(ph)
                    b.z = z
                    b.zs = z
                    flies.append(b)
                }
            }
        }
    }
}
