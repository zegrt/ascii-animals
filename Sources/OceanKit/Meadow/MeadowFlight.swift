import Foundation

// The butterflies' flight from above and their landed life, ported term for term from the sketch (`stepFly`,
// `stepLanded`, `landedPose`, `takeOff`, `land`, glides, `clap`, `relayAlarm`; html:1538–1902). `html:N` is a line of
// `Tools/meadow-sketch/meadow.html` on `meadow-sketch` at 4e1b869.

private let DEG = Double.pi / 180

/// The sketch's `angDiff` (html:144): the shortest signed angle from a to b.
@inline(__always) func angDiff(_ a: Double, _ b: Double) -> Double { atan2(sin(b - a), cos(b - a)) }
@inline(__always) func ease01(_ t: Double) -> Double { t * t * (3 - 2 * t) }

extension MeadowWorld {
    /// `takeOff(b, awayX, awayY, escape)` (html:1538–1568).
    func takeOff(_ b: Butterfly, away: (Double, Double)? = nil, escape: Bool = false) {
        let sp = b.sp
        let was = b.state
        if b.flower != 0, let i = flowers.index(of: b.flower) {
            if was == .nectar { flowers.visited(id: b.flower, rng: rng) }
            let f = flowers.all[i]
            for _ in 0..<7 {
                let x: Double = f.x + f.ox + rng.range(-6, 6) * S
                let y: Double = f.y + f.oy + rng.range(-6, 6) * S
                let vx: Double = rng.range(-15, 15) * S
                let vy: Double = rng.range(-15, 15) * S
                let life = rng.range(2.5, 4.5)
                addDust(MeadowDust(x: x, y: y, vx: vx, vy: vy, life: life, max: 4.5, spark: false))
            }
            nodFlower(b.flower, -cos(b.heading), -sin(b.heading), b, 0.5)
        }
        releaseFlower(b)
        if was == .bask { b.airT = 0 }
        b.state = .fly
        b.goal = .none
        b.spiral = nil
        b.tag = 0
        b.tagTries = 0
        b.circleT = 0
        b.alert = 0
        b.flushIn = 0
        b.boost = escape ? rng.range(0.6, 1.2) : rng.range(0.6, 1.0)
        b.boostK = escape ? 2 : 1.8
        b.zv = was == .cursor ? 0.05 : 0.45
        b.bobAmp = 1
        b.gliding = false
        b.armed = false
        b.brake = 0
        b.beatsLeft = max(rng.int(sp.bout.0, sp.bout.1), 6)
        pickWaypoint(b)
        if let (ax, ay) = away {
            let a: Double = atan2(b.y - ay, b.x - ax) + (escape ? rng.range(-0.5, 0.5) : 0)
            if !b.leaving && !screens.isEmpty {
                let s = screens[screen(near: b.x, b.y)]
                b.wx = clamp(b.x + cos(a) * 500 * S, s.minX + 40, s.maxX - 40)
                b.wy = clamp(b.y + sin(a) * 500 * S, s.minY + 40, s.maxY - 40)
            }
            if tuning.ease > 0 { b.turn = clamp(b.turn + angDiff(b.heading, a) * 3.5, -6, 6) } else { b.heading = a }
        }
        if tuning.ease > 0 {
            let th = acos(clamp((b.stroke - sp.mid) / sp.amp, -1, 1))
            b.phase = b.stroke >= sp.mid ? th : TAU - th
            b.blendFrom = b.stroke
            b.blendK = 0
        } else {
            b.phase = 0
            b.blendK = 1
        }
    }

    /// `land(b)` (html:1570–1580).
    func land(_ b: Butterfly) {
        switch b.goal {
        case .nectar: b.state = .nectar
        case .bask: b.state = .bask
        case .cursor: b.state = .cursor
        case .none: b.state = .fly
        }
        b.called = false
        let sp = b.sp
        if b.goal == .cursor {
            b.timer = rng.range(25, 45)
            b.flash = rng.range(1.5, 3.5)
            b.flashT = 0
        } else {
            let r = b.goal == .nectar ? sp.nectar : sp.bask
            b.timer = max(0.8, rng.range(r.0, r.1) * tuning.stay * bold(b))
        }
        b.landHeading = b.goal == .cursor ? b.heading : b.heading + rng.gauss() * 0.5
        b.gliding = false
        b.zv = 0
        b.spiral = nil
        b.relayDepth = 0
        b.stillT = 0
        b.alert = 0
        b.flushIn = 0
        b.landFrom = b.stroke
        b.landK = tuning.ease > 0 ? 0 : 1
        b.brake = 0
        if b.flower != 0 { nodFlower(b.flower, cos(b.heading), sin(b.heading), b, 1) }
    }

    /// `startGlide` (html:1582–1587).
    func startGlide(_ b: Butterfly) {
        b.gliding = true
        b.armed = false
        b.glideLeft = rng.range(b.sp.glideS.0, b.sp.glideS.1) * min(1.6, tuning.glide)
        b.glideHeading = b.heading
        b.phase = b.sp.glidePhase
        b.stroke = b.sp.glideStroke
    }

    /// `endGlide` (html:1588–1593).
    func endGlide(_ b: Butterfly) {
        b.gliding = false
        let k = max(0.3, tuning.glide)
        let n = Double(rng.int(b.sp.bout.0, b.sp.bout.1)) / k
        b.beatsLeft = max(2, Int(MeadowMath.round(n)))
        if tuning.ease > 0 { b.blendFrom = b.stroke; b.blendK = 0 }
    }

    /// `clap` (html:1597–1607): one beat done; jinks, side-slips, the white's surge, the morpho's bounds.
    func clap(_ b: Butterfly, _ speed: Double, _ hx: Double, _ hy: Double) {
        let sp = b.sp, zz = tuning.zigzag
        b.beatsLeft -= 1
        if b.beatsLeft <= 0 { b.armed = true }
        if sp.surge > 0 { b.pace = clamp(1 + sp.surge * rng.gauss(), 0.4, 1.6) }
        let calm: Double = b.state == .approach ? 0.45 : 1
        if rng.unit() < min(0.95, sp.jinkChance * zz) {
            let spread: Double = sp.jinkSigma * DEG * b.jinkF * min(1.6, 0.4 + 0.6 * zz) * calm
            b.jink += rng.gauss() * spread
        }
        b.jink = clamp(b.jink, -1.2, 1.2)
        let slip: Double = rng.gauss() * 0.3 * speed * zz * sp.slip * calm
        b.ux += -hy * slip
        b.uy += hx * slip
        if sp.bound {
            b.boundLeft -= 1
            if b.boundLeft <= 0 {
                b.bound = -b.bound
                b.boundLeft = rng.int(2, 4)
                b.zv += b.bound * 0.22 * min(2, tuning.bob)
            }
        }
    }

    /// `relayAlarm` (html:1611–1621).
    func relayAlarm(_ src: Butterfly) {
        if tuning.relay <= 0 || src.relayDepth >= 2 { return }
        for o in flies {
            if o === src || !o.landed || o.state == .cursor || o.flushIn > 0 { continue }
            let d = hypot(o.x - src.x, o.y - src.y)
            if d > 1.5 * (spanRef(src) + spanRef(o)) { continue }
            let p: Double = tuning.relay * clamp(1.5 - bold(o), 0, 1) * (src.relayDepth != 0 ? 0.5 : 1)
            if rng.unit() < p {
                o.flushIn = rng.range(0.15, 0.4)
                o.relayDepth = src.relayDepth + 1
                o.fleeX = src.x
                o.fleeY = src.y
            }
        }
    }

    /// The sketch's edge steer (html:1730–1735): `(ex, ey)` toward the screens once the body is a quarter span past a
    /// real edge. One screen: the sketch's own test. Several: past the terrain by a quarter span, or in a gap at all,
    /// toward the nearest point on a screen.
    @inline(__always) func edgeSteer(_ b: Butterfly, _ span: Double) -> (Double, Double) {
        let m = 0.25 * span
        if single {
            let s = screens[0]
            var ex = 0.0, ey = 0.0
            if b.x < s.minX - m { ex = 1 } else if b.x > s.maxX + m { ex = -1 }
            if b.y < s.minY - m { ey = 1 } else if b.y > s.maxY + m { ey = -1 }
            return (ex, ey)
        }
        let p = SIMD2(b.x, b.y)
        if onScreens(b.x, b.y) { return (0, 0) }
        let out = signedOutside(b.x, b.y)
        guard out > m || inGap(b.x, b.y) else { return (0, 0) }
        let q = terrain.nearestInside(p)
        let ex: Double = q.x > b.x + 1e-9 ? 1 : q.x < b.x - 1e-9 ? -1 : 0
        let ey: Double = q.y > b.y + 1e-9 ? 1 : q.y < b.y - 1e-9 ? -1 : 0
        return (ex, ey)
    }

    /// `stepFly` (html:1635–1831).
    func stepFly(_ b: Butterfly, _ dt: Double) {
        let sp = b.sp
        b.t += dt
        if b.startleCd > 0 { b.startleCd -= dt }
        if b.wait > 0 { b.wait -= dt; return }
        if b.entering {
            let span = spanRef(b)
            let s = screens[screen(near: b.x, b.y)]
            let ix: Double = min(0.6 * span, 0.15 * s.w), iy: Double = min(0.6 * span, 0.15 * s.h)
            if single {
                if b.x > s.minX + ix && b.y > s.minY + iy && b.x < s.maxX - ix && b.y < s.maxY - iy { b.entering = false }
            } else if signedOutside(b.x, b.y) <= -min(ix, iy) {
                b.entering = false
            }
        }
        if b.landed { stepLanded(b, dt); return }
        // ── wants ──
        b.energy = max(0, b.energy - 0.01 * tuning.hunger * dt)
        b.airT += dt
        if b.airT > 60 { b.warmth = max(0, b.warmth - 0.012 * tuning.warmth * dt) }
        let span = spanRef(b)
        // ── where it is going ──
        var tx = 0.0, ty = 0.0
        if b.leaving {
            tx = b.wx; ty = b.wy
            if outOfSight(b) { b.dead = true; return }
        } else if b.state == .approach {
            if b.goal == .nectar && flowers.index(of: b.flower) == nil {
                b.state = .fly; b.goal = .none; b.flower = 0; b.called = false
                pickWaypoint(b)
            }
            if b.state == .approach { (tx, ty) = target(b) } else { tx = b.wx; ty = b.wy }
        } else {
            tx = b.wx; ty = b.wy
        }
        var dx: Double = tx - b.x, dy: Double = ty - b.y
        var dist: Double = hypot(dx, dy)
        // The pointer spiral.
        if b.goal == .cursor && b.state == .approach, var S_ = b.spiral {
            let cx = pointerX, cy = pointerY
            let ang = atan2(b.y - cy, b.x - cx), dc = hypot(b.x - cx, b.y - cy)
            if !S_.on && dc < S_.r0 * 1.25 { S_.on = true; S_.last = ang }
            if S_.on {
                S_.swept += max(0, angDiff(S_.last, ang) * S_.dir)
                S_.last = ang
                S_.t += dt
                let done: Double = min(1, max(S_.swept / (S_.loops * TAU), S_.t / (S_.loops * 2.4)))
                let r: Double = S_.r0 * (1 - done)
                S_.done = done
                if done < 1 && r > 0.45 * span {
                    let g = ang + S_.dir * 0.75
                    tx = cx + cos(g) * r; ty = cy + sin(g) * r
                    dx = tx - b.x; dy = ty - b.y
                    dist = max(hypot(dx, dy), 1.3 * span)
                    b.spiral = S_
                } else {
                    b.spiral = nil
                }
            } else {
                tx = cx; ty = cy
                dx = tx - b.x; dy = ty - b.y
                dist = hypot(dx, dy)
                b.spiral = S_
            }
        }
        // Touch-and-go: circle the bloom once.
        if b.circleT > 0 {
            b.circleT -= dt
            let ang = atan2(b.y - ty, b.x - tx), g = ang + b.circleDir * 0.9, r: Double = 1.1 * span
            tx += cos(g) * r; ty += sin(g) * r
            dx = tx - b.x; dy = ty - b.y
            dist = max(hypot(dx, dy), 2.2 * span)
            if b.circleT <= 0 { b.tag = 0 }
        }
        if !b.leaving {
            if b.state == .fly {
                b.wpLeft -= dt
                if dist < 1.1 * span || b.wpLeft <= 0 { chooseNext(b); return }
            } else {
                b.timer -= dt
                if b.timer <= 0 {
                    releaseFlower(b); b.state = .fly; b.goal = .none; b.spiral = nil
                    pickWaypoint(b)
                    return
                }
            }
            if b.state == .fly && tuning.hunger > 0.005 && b.energy < 0.3 {
                b.senseT -= dt
                if b.senseT <= 0 {
                    b.senseT = 0.7
                    if rng.unit() < 0.5 * min(1, tuning.visits / 0.35), let f = pickFlower(b) { goToFlower(b, f); return }
                }
            }
        }

        // ── how fast, and how fast it beats ──
        var speed: Double = sp.cruise * S * tuning.speed * b.pace
        var near = 1.0
        if b.state == .approach {
            near = clamp(dist / (2.2 * span), 0, 1)
            speed = lerp(sp.forage * S * tuning.speed, speed, near)
            if b.goal == .cursor, let s = b.spiral, s.on { speed = lerp(sp.forage, sp.cruise, 0.6) * S * min(tuning.speed, 1.8) }
        }
        var f: Double = sp.realBeat * tuning.wingbeat * b.beatF
        if b.boost > 0 { b.boost -= dt; speed *= b.boostK; f *= 1.25 }
        let air = breeze.sample(b.x, b.y)
        let wx = air.x, wy = air.y, pxs = air.pointerX, pys = air.pointerY
        if air.speed > 0.3 * speed { f *= 1.15 }
        f = min(ButterflySpecies.beatCap, f)
        let pm = hypot(pxs, pys)
        if pm > tuning.airFlush * S * (0.7 + 0.3 * bold(b)) && b.startleCd <= 0 && b.goal != .cursor {
            b.startleCd = 1.5
            b.boost = max(b.boost, 0.7)
            b.boostK = 1.8
            let flow = atan2(pys, pxs)
            let side: Double = sin(b.heading - flow) >= 0 ? 1 : -1
            let across: Double = flow + side * rng.range(0.6, 1.3)
            b.jink += angDiff(b.heading, across) * 0.8
            if b.state == .approach && b.goal != .cursor {
                releaseFlower(b); b.state = .fly; b.goal = .none
                pickWaypoint(b)
            }
        }

        // ── the heading it wants ──
        var want = atan2(dy, dx)
        if b.state == .fly && !b.leaving { want += 0.45 * MeadowMath.n1(b.t * 0.16, Double(b.seed)) }
        var px = 0.0, py = 0.0
        for o in flies where o !== b {
            let hk: Double = tuning.spaceByHeight ? MeadowMath.smooth(0.35, 0.15, abs(b.z - o.z)) : 1
            let ox = b.x - o.x, oy = b.y - o.y
            let d = hypot(ox, oy)
            let so = spanRef(o)
            let lim: Double = 2.4 * (span + so) / 2
            let lk: Double = o.landed ? 0.6 * (b.state == .approach ? MeadowMath.smooth(0.25, 0.9, near) : 1) : 1
            if d < lim && d > 0.1 {
                let w: Double = (1 - d / lim) * lk * (0.7 + 0.3 * hk)
                px += ox / d * w * w * 2
                py += oy / d * w * w * 2
            }
            let touch: Double = 0.8 * (span + so)
            if d < touch && d > 0.1 {
                let push: Double = (1 - d / touch) * 260 * S * dt * (0.25 + 0.75 * hk)
                b.ux += ox / d * push
                b.uy += oy / d * push
            }
        }
        var ex = 0.0, ey = 0.0
        if !b.leaving { (ex, ey) = edgeSteer(b, span) }
        if px != 0 || py != 0 || ex != 0 || ey != 0 {
            let sy: Double = sin(want) + 2.6 * py + 2 * ey
            let sx: Double = cos(want) + 2.6 * px + 2 * ex
            want = atan2(sy, sx)
        }

        // ── heading on a spring ──
        if b.gliding { b.glideHeading += angDiff(b.glideHeading, want) * min(1, 0.7 * dt) }
        let aim: Double = b.gliding ? b.glideHeading : want + b.jink
        b.jink *= exp(-dt / 0.9)
        let k: Double = sp.headingK * tuning.turning
        let spring: Double = k * angDiff(b.heading, aim) - 2 * sp.zeta * k.squareRoot() * b.turn
        b.turn += spring * dt
        let maxTurn: Double = 6 * tuning.turning.squareRoot()
        b.turn = clamp(b.turn, -maxTurn, maxTurn)
        b.heading += b.turn * dt
        let hx = cos(b.heading), hy = sin(b.heading)

        // ── wings and forces ──
        let brakeT: Double = tuning.ease > 0 && b.state == .approach && b.circleT <= 0 && b.spiral == nil && dist < 0.9 * span ? 1 : 0
        b.brake += (brakeT - b.brake) * min(1, 5 * dt)
        let drag = 8.0
        let impulse: Double = sp.thrust * speed * tuning.lurch * (1 - 0.7 * b.brake)
        let w: Double = TAU * f
        let zNoise: Double = 0.3 * MeadowMath.n1(b.t * 0.045, Double(b.seed + 3))
        let zBase: Double = clamp(tuning.height + zNoise + 0.375 * (bold(b) - 1), 0.06, 0.96)
        var zc: Double = b.state == .approach ? lerp(0, zBase, MeadowMath.smooth(0.1, 1, near)) : (b.boost > 0 ? max(zBase, 0.55) : zBase)
        if b.goal == .cursor {
            if let s = b.spiral { zc = s.on ? lerp(zBase, 0.92, min(1, s.done + 0.3)) : zBase } else { zc = 0.92 }
        }
        if b.circleT > 0 { zc = max(zc, 0.2) }
        if !b.gliding {
            let prev = b.phase
            b.phase += w * dt
            let s = sin(b.phase)
            if s > 0 {
                let a: Double = impulse * .pi * f * s
                b.ux += a * hx * dt
                b.uy += a * hy * dt
                if b.z < 0.35 && tuning.downwash > 0 { breeze.downstroke(x: b.x, y: b.y, z: b.z, sinStroke: s, span: span) }
            }
            if b.phase >= TAU { b.phase -= TAU; clap(b, speed, hx, hy) }
            let v: Double = max(0.12 * speed, speed - impulse * f / drag)
            b.ux += -drag * (b.ux - v * hx) * dt
            b.uy += -drag * (b.uy - v * hy) * dt
            b.stroke = sp.mid + sp.amp * (1 - 0.5 * b.brake) * cos(b.phase)
            let kz = 1.4
            b.zv += (kz * (zc - b.zs) - 2 * kz.squareRoot() * b.zv) * dt
            b.bobAmp += (1 - b.bobAmp) * min(1, 6 * dt)
            let canGlide = tuning.glide > 0.01 && b.boost <= 0 && b.zs > zc - 0.1 && (b.state == .fly || near > 0.7) && b.goal != .cursor
            if b.armed && canGlide && prev < sp.glidePhase && b.phase >= sp.glidePhase { startGlide(b) }
        } else {
            b.glideLeft -= dt
            if b.glideLeft <= 0 || (b.state == .approach && near < 0.6) || b.zs < 0.05 { endGlide(b) }
            let gv: Double = speed * 0.8
            let gk: Double = min(1, 2.2 * dt)
            b.ux += (gv * hx - b.ux) * gk
            b.uy += (gv * hy - b.uy) * gk
            b.zv += (-0.08 - b.zv) * min(1, 3 * dt)
            b.bobAmp *= exp(-5 * dt)
            b.stroke = sp.glideStroke + 4 * DEG * sin(b.t * 2.3 + Double(b.seed))
        }
        if b.blendK < 1 {
            b.blendK = min(1, b.blendK + dt / (0.15 * max(0.05, tuning.ease)))
            b.stroke = lerp(b.blendFrom, b.stroke, ease01(b.blendK))
        }
        b.zs += b.zv * dt
        if b.zs < 0.02 { b.zs = 0.02; if b.zv < 0 { b.zv = 0 } }
        if b.zs > 0.97 { b.zs = 0.97; if b.zv > 0 { b.zv = 0 } }
        let bobZ: Double = 0.045 * tuning.bob * (sp.bob / 0.25) * b.bobAmp * (1 - 0.5 * b.brake)
        b.z = clamp(b.zs - bobZ * sin(b.phase), 0, 1)

        // ── bank into turns ──
        let bankT: Double = sp.maxBank * 0.35 * tanh(b.turn / 1.5)
        b.bank += (bankT - b.bank) * min(1, 6 * dt)

        // ── ground velocity = airspeed + some of the breeze ──
        b.vx = b.ux + wx * 0.55
        b.vy = b.uy + wy * 0.55
        let nx: Double = b.x + b.vx * dt, ny: Double = b.y + b.vy * dt
        move(b, nx, ny)

        // ── settling onto the flower, the ground or the pointer ──
        if b.state == .approach && b.circleT <= 0 && b.spiral == nil {
            (tx, ty) = target(b)
            dx = tx - b.x; dy = ty - b.y
            dist = hypot(dx, dy)
            if dist < 0.6 * span {
                if b.goal == .nectar && b.tag == 0 {
                    b.tag = 1
                    if rng.unit() < tuning.touchGo {
                        b.tagTries += 1
                        if b.tagTries > 1 {
                            let other = pickFlower(b)
                            releaseFlower(b)
                            if let other { goToFlower(b, other) } else { b.state = .fly; b.goal = .none; pickWaypoint(b) }
                            b.tagTries = 2
                            b.tag = 1
                        } else {
                            b.circleT = rng.range(1.0, 1.6)
                            b.circleDir = rng.unit() < 0.5 ? 1 : -1
                            b.zv += 0.4
                        }
                        return
                    }
                }
                let pull: Double = min(1, (1 - dist / (0.6 * span)) * 6 * dt)
                move(b, b.x + dx * pull, b.y + dy * pull)
                if b.goal == .cursor {
                    b.zv = max(b.zv, 0.2 + 0.4 * (1 - dist / (0.6 * span)))
                    if dist < 0.15 * span && b.zs > 0.8 { land(b) }
                } else {
                    b.zv = min(b.zv, -0.35 - 0.6 * (1 - dist / (0.6 * span)))
                    if dist < 0.12 * span && b.zs < 0.1 { land(b) }
                }
            }
        }
    }

    /// `landedPose` (html:1834–1856): the wings' pose when landed.
    func landedPose(_ b: Butterfly, _ dt: Double) -> Double {
        let sp = b.sp
        if b.state == .cursor {
            b.flash -= dt
            if b.flash <= 0 { b.flashT = 1.6; b.flash = rng.range(4, 10) }
            if b.flashT > 0 {
                b.flashT -= dt
                let k = sin(.pi * clamp(1 - b.flashT / 1.6, 0, 1))
                return (64 - 56 * k) * DEG
            }
            return (64 + 6 * sin(b.slow * 0.7)) * DEG
        }
        if b.state == .nectar {
            if sp.flutterOnFlower {
                b.phase += TAU * min(ButterflySpecies.beatCap, sp.realBeat * tuning.wingbeat * 0.8) * dt
                return (34 + 16 * cos(b.phase)) * DEG
            }
            let slow: Double = 0.5 + 0.5 * sin(b.slow * 1.3 + Double(b.seed))
            return (28 + 46 * pow(slow, 1.5)) * DEG
        }
        switch sp.baskPose {
        case .open: return (4 + 6 * max(0, sin(b.slow * 0.9))) * DEG
        case .vee: return (52 + 8 * sin(b.slow * 0.8)) * DEG
        case .closed:
            b.flash -= dt
            if b.flash <= 0 { b.flashT = 0.6; b.flash = rng.range(5, 14) }
            if b.flashT > 0 {
                b.flashT -= dt
                return (10 + 76 * abs(cos(.pi * (b.flashT / 0.6)))) * DEG
            }
            return 86 * DEG
        }
    }

    /// `stepLanded` (html:1858–1902).
    func stepLanded(_ b: Butterfly, _ dt: Double) {
        let sp = b.sp, life = tuning.life
        b.timer -= dt
        b.slow += dt
        b.stillT += dt
        if b.state == .cursor && (!pointerHas || !tuning.cursorLand) { takeOff(b); return }
        if b.state == .nectar && flowers.index(of: b.flower) == nil { takeOff(b); return }
        if b.state == .nectar { b.energy = min(1, b.energy + 0.08 * dt) }
        if b.state == .bask { b.warmth = min(1, b.warmth + 0.12 * dt) } else { b.warmth = min(1, b.warmth + 0.02 * dt) }
        let air = breeze.sample(b.x, b.y)
        let am = hypot(air.landedX, air.landedY), bo = bold(b)
        let closeAt: Double = tuning.airClose * S * (0.7 + 0.3 * bo)
        let flushAt: Double = tuning.airFlush * S * (0.7 + 0.3 * bo)
        let alertT: Double = b.state == .cursor ? 0 : MeadowMath.smooth(0.6 * closeAt, max(closeAt + 1, 0.9 * flushAt), am)
        b.alert += (alertT - b.alert) * min(1, (alertT > b.alert ? 8 : 1.5) * dt)
        if am > flushAt && b.flushIn <= 0 && b.state != .cursor {
            b.flushIn = rng.range(0.05, 0.15)
            b.fleeX = b.x - air.landedX / am * 100
            b.fleeY = b.y - air.landedY / am * 100
        }
        if b.flushIn > 0 {
            b.flushIn -= dt
            if b.flushIn <= 0 { takeOff(b, away: (b.fleeX, b.fleeY)); relayAlarm(b); return }
        }
        let brake: Double = exp(-7 * dt)
        b.ux *= brake
        b.uy *= brake
        let lean: Double = 0.1 * spanRef(b) * min(2, life) * MeadowMath.smooth(0.5 * closeAt, flushAt, am)
        let lx: Double = am > 1 ? air.landedX / am * lean : 0
        let ly: Double = am > 1 ? air.landedY / am * lean : 0
        b.leanX += (lx - b.leanX) * min(1, 6 * dt)
        b.leanY += (ly - b.leanY) * min(1, 6 * dt)
        let (tx, ty) = target(b)
        let pull: Double = min(1, 10 * dt)
        let lx1: Double = b.x + (b.ux * dt + (tx + b.leanX - b.x) * pull)
        let ly1: Double = b.y + (b.uy * dt + (ty + b.leanY - b.y) * pull)
        move(b, lx1, ly1)
        b.vx = b.ux
        b.vy = b.uy
        let zT: Double = b.state == .cursor ? 0.92 : 0
        b.zs += (zT - b.zs) * min(1, 6 * dt)
        b.z = b.zs
        b.zv = 0
        if life > 0 {
            b.shuffleT -= dt
            if b.shuffleT <= 0 {
                b.shuffleT = rng.range(4, 9)
                b.landHeading += rng.range(-0.15, 0.15) * min(2, life)
            }
        }
        b.heading += angDiff(b.heading, b.landHeading) * min(1, 2 * dt)
        b.bank *= exp(-4 * dt)
        if b.antT0 > 0 { b.antT0 = max(0, b.antT0 - dt) }
        if b.antT1 > 0 { b.antT1 = max(0, b.antT1 - dt) }
        if life > 0 && b.stillT > 1.5 && rng.unit() < 0.3 * min(2, life) * dt {
            let side = rng.unit() < 0.5 ? 0 : 1
            if side == 0 {
                if b.antT0 <= 0 { b.antT0 = 0.3; b.antS0 = rng.unit() < 0.5 ? 1 : -1 }
            } else if b.antT1 <= 0 {
                b.antT1 = 0.3; b.antS1 = rng.unit() < 0.5 ? 1 : -1
            }
        }
        var pose = landedPose(b, dt)
        pose += 1.5 * DEG * life * sin(1.6 * b.slow + Double(b.seed))
        pose = lerp(pose, 86 * DEG, 0.7 * b.alert * min(1, life + 0.5))
        if b.landK < 1 {
            b.landK = min(1, b.landK + dt / (0.35 * max(0.05, tuning.ease)))
            b.stroke = lerp(b.landFrom, pose, ease01(b.landK))
        } else {
            b.stroke = pose
        }
        if b.state == .nectar && sp.flutterOnFlower && tuning.downwash > 0 {
            let s = sin(b.phase)
            if s > 0 { breeze.flutter(x: b.x, y: b.y, sinStroke: s, span: spanRef(b)) }
        }
        if b.timer <= 0 { takeOff(b) }
    }
}
