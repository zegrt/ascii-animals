// The ocean simulation. Port of ascii-sharks world.ts + math.ts (MIT, drewdi / @stackedlol),
// following the verified Luau port in ascii-sharks-rive.
//
// Fish: Reynolds boids (separation / alignment / cohesion) in Couzin-style
// zones, with a blind spot behind each fish. Alarm spreads through a school,
// and fleeing fish break sideways around the shark's path (fountain effect).
// Sharks: wander + pursuit + separation on a follow-the-leader spine. Hunger
// builds, drops when they eat, and eaten fish come back as new schools.
// All randomness comes from the injected Rng.

import CoreGraphics
import Foundation
import simd

public struct Fish: Sendable {
    public var x, y, vx, vy: Double
    public var species: Int
    public var alarm: Double
    public var alive: Bool
    public var respawnAt: Double
    public var phase: Double
    public var turn: Double
    public var depth: Double
    public var millDir: Double
}

public struct Shark: Sendable {
    public var id: Int
    public var kind: SharkKind
    public var length: Double
    /// x0, y0, x1, y1, ... snout first.
    public var nodes: [Double]
    public var heading, speed, phase, turn, hunger, wander: Double
    public var orbitDir: Double
    /// Patrol radius as a fraction of the home screen's short side.
    public var orbitFrac: Double
    public var target: Int?
    public var retargetAt: Double
    public var depth: Double
    /// Index of the terrain rect (screen) this shark patrols.
    public var home: Int
    public var migrateAt: Double
    /// While migrating: the middle of the edge it is crossing.
    public var doorway: SIMD2<Double>?
}

public struct WorldEvent: Sendable {
    public enum Kind: Sendable { case eat, splash }
    public var kind: Kind
    public var x, y: Double
    /// Increasing; each viewport packs only events newer than the last it drew.
    public var seq: Int
    public var time: Double
}

private let tau = Double.pi * 2
private let fishSeparationK = 420.0
private let fishAlignK = 1.4
private let fishCohesionK = 1.0
private let fishFleeK = 1100.0
private let blindCos = -0.6

// angleDiff (shortest signed angle from a to b) is shared with the Web habitat: Web/WebMath.swift.

@inline(__always) private func oceanClamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
@inline(__always) private func hypot2(_ x: Double, _ y: Double) -> Double { (x * x + y * y).squareRoot() }

/// Divergence-free ocean current: the curl of a slowly drifting stream function.
@inline(__always) private func current(_ x: Double, _ y: Double, _ t: Double) -> (Double, Double) {
    let k1 = 1.0 / 260, k2 = 1.0 / 310, k3 = 1.0 / 190, scale = 3400.0
    let a = x * k1 + t * 0.07
    let b = y * k2 - t * 0.05
    let c = (x + y) * k3 + t * 0.11
    let u = (-k2 * sin(a) * sin(b) + 0.5 * k3 * cos(c)) * scale
    let v = (-k1 * cos(a) * cos(b) - 0.5 * k3 * cos(c)) * scale
    return (u, v)
}

public final class World {
    public static let sharkNodes = 20
    public static let maxFish = 1024
    public static let maxSharks = 16
    /// Events are kept this long so every viewport gets to draw them.
    public static let eventLifetime = 2.0

    public private(set) var terrain = Terrain(rects: [])
    public private(set) var width = 0.0
    public private(set) var height = 0.0
    public private(set) var stepCount = 0
    public private(set) var eventSeq = 0
    public var time = 0.0
    public private(set) var fish: [Fish] = []
    public private(set) var sharks: [Shark] = []
    public var events: [WorldEvent] = []
    public var pointer: (x: Double, y: Double, active: Bool) = (0, 0, false)

    private var rng: Rng
    private let specs: [SharkSpec]
    private var density = 1.0
    private var perception = 60.0
    private var sepX = [Double](repeating: 0, count: fishSpecies.count)
    private var sepY = [Double](repeating: 0, count: fishSpecies.count)
    private var foreignSep = 40.0
    private var bucketCols = 0, bucketRows = 0
    private var bucketHead: [Int] = []
    private var bucketCount: [Int] = []
    private var bucketNext: [Int] = []
    private var lastSpawn = 0.0

    public init(sharks: [SharkKind], rng: Rng) {
        self.rng = rng
        self.specs = SharkSpec.lineUp(sharks)
    }

    public func resize(width: Double, height: Double, cell: CGSize, density: Double) {
        resize(terrain: .single(width: width, height: height), cell: cell, density: density)
    }

    /// `terrain` is in ocean space: its bounding box starts at 0,0.
    public func resize(terrain: Terrain, cell: CGSize, density: Double) {
        let first = self.width == 0
        let reseed = first || fish.isEmpty || density != self.density || terrain.rects.count != self.terrain.rects.count
        self.terrain = terrain
        self.width = Double(terrain.bounds.maxX)
        self.height = Double(terrain.bounds.maxY)
        self.density = density
        let cw = Double(cell.width), ch = Double(cell.height)
        for (i, sp) in fishSpecies.enumerated() {
            sepX[i] = sp.spacingX * cw
            sepY[i] = sp.spacingY * ch
        }
        perception = max(ch * 3, cw * 5.5)
        foreignSep = cw * 3
        if reseed {
            seed()
            return
        }
        for i in fish.indices {
            let q = terrain.nearestInside(SIMD2(fish[i].x, fish[i].y))
            fish[i].x = q.x
            fish[i].y = q.y
        }
        for s in sharks.indices where !terrain.rects.indices.contains(sharks[s].home) {
            sharks[s].home = terrain.rectIndex(near: SIMD2(sharks[s].nodes[0], sharks[s].nodes[1]))
            sharks[s].doorway = nil
        }
    }

    private func emit(_ kind: WorldEvent.Kind, _ x: Double, _ y: Double) {
        eventSeq += 1
        events.append(WorldEvent(kind: kind, x: x, y: y, seq: eventSeq, time: time))
    }

    public func splash(_ x: Double, _ y: Double) {
        emit(.splash, x, y)
        let r = 240.0
        for i in fish.indices where fish[i].alive {
            let dx = fish[i].x - x, dy = fish[i].y - y
            let d = hypot2(dx, dy)
            if d <= r && d >= 1e-3 {
                let k = (1 - d / r) * 260
                fish[i].vx += dx / d * k
                fish[i].vy += dy / d * k
                fish[i].alarm = 1
            }
        }
    }

    public func step(_ dt: Double) {
        guard width > 0, height > 0 else { return }
        time += dt
        stepCount += 1
        if let first = events.first, first.time < time - World.eventLifetime {
            events.removeAll { $0.time < time - World.eventLifetime }
        }
        rebuildHash()
        stepFish(dt)
        stepSharks(dt)
        respawn()
    }

    // MARK: Seeding

    private func pickSpecies() -> Int {
        var r = rng.unit() * fishTotalWeight
        for (i, sp) in fishSpecies.enumerated() {
            r -= sp.weight
            if r <= 0 { return i }
        }
        return 0
    }

    private func randInt(_ lo: Int, _ hi: Int) -> Int { Int(floor(rng.range(Double(lo), Double(hi + 1)))) }

    /// Sharks and schools are seeded per screen exactly as world.ts seeds its
    /// single box; with several screens the line-up repeats on each.
    private func seed() {
        let rects = terrain.rects
        let perRect = min(specs.count, World.maxSharks / max(1, rects.count))
        var made: [Shark] = []
        for (r, rect) in rects.enumerated() {
            let W = Double(rect.width), H = Double(rect.height)
            let ox = Double(rect.minX), oy = Double(rect.minY)
            let minSide = min(W, H)
            let baseLength = oceanClamp(minSide * 0.44, 170, 430)
            let count = Double(perRect)
            for (i, spec) in specs.prefix(perRect).enumerated() {
                let length = baseLength * spec.size
                let orbitFrac = rng.range(0.28, 0.4)
                let orbitRadius = minSide * orbitFrac
                let a = Double(i) / count * tau + rng.range(-0.4, 0.4)
                let orbitDir: Double = i % 2 == 0 ? 1 : -1
                let x = ox + W / 2 + cos(a) * orbitRadius * (W / minSide) * 0.9
                let y = oy + H / 2 + sin(a) * orbitRadius
                let heading = a + orbitDir * .pi / 2
                let seg = length / Double(World.sharkNodes - 1)
                var nodes = [Double](repeating: 0, count: World.sharkNodes * 2)
                for n in 0..<World.sharkNodes {
                    nodes[n * 2] = x - cos(heading) * seg * Double(n)
                    nodes[n * 2 + 1] = y - sin(heading) * seg * Double(n)
                }
                made.append(Shark(
                    id: made.count + 1, kind: spec.kind, length: length, nodes: nodes, heading: heading, speed: 30,
                    phase: rng.range(0, tau), turn: 0, hunger: rng.range(0.25, 0.75), wander: 0,
                    orbitDir: orbitDir, orbitFrac: orbitFrac, target: nil, retargetAt: 0, depth: spec.size,
                    home: r, migrateAt: rng.range(25, 70), doorway: nil))
            }
        }
        // Smaller (farther) sharks draw first so the big one swims over them.
        sharks = made.sorted { $0.length < $1.length }

        // Each screen keeps world.ts's density; the total is scaled and capped.
        let quotas = rects.map { r in oceanClamp(floor(Double(r.width * r.height) / 4400 + 0.5), 85, 340) }
        let total = min(World.maxFish, Int(floor(quotas.reduce(0, +) * density + 0.5)))
        fish = []
        fish.reserveCapacity(total)
        var remaining = total
        for (r, rect) in rects.enumerated() {
            let W = Double(rect.width), H = Double(rect.height)
            let ox = Double(rect.minX), oy = Double(rect.minY)
            let share = r == rects.count - 1 ? remaining : min(remaining, Int(floor(quotas[r] * density + 0.5)))
            remaining -= share
            let goal = fish.count + share
            while fish.count < goal {
                let species = pickSpecies()
                let sp = fishSpecies[species]
                let size = min(randInt(sp.schoolMin, sp.schoolMax), goal - fish.count)
                let millDir: Double = rng.chance(0.5) ? 1 : -1
                let cx = ox + rng.range(W * 0.06, W * 0.94)
                let cy = oy + rng.range(H * 0.08, H * 0.92)
                let dir = (rng.chance(0.5) ? 0 : Double.pi) + rng.range(-0.5, 0.5)
                let spread = Double(size).squareRoot()
                for _ in 0..<size {
                    fish.append(Fish(
                        x: cx + rng.range(-1, 1) * sepX[species] * spread,
                        y: cy + rng.range(-1, 1) * sepY[species] * spread * 0.6,
                        vx: cos(dir) * sp.cruise, vy: sin(dir) * sp.cruise,
                        species: species, alarm: 0, alive: true, respawnAt: 0,
                        phase: rng.range(0, tau), turn: 0, depth: rng.range(0.55, 1), millDir: millDir))
                }
            }
        }
        bucketNext = [Int](repeating: -1, count: fish.count)
    }

    // MARK: Spatial hash

    @inline(__always) private func bucketOf(_ x: Double, _ y: Double) -> Int {
        let c = Int(oceanClamp(floor(x / perception) + 2, 0, Double(bucketCols - 1)))
        let r = Int(oceanClamp(floor(y / perception) + 2, 0, Double(bucketRows - 1)))
        return r * bucketCols + c
    }

    private func rebuildHash() {
        bucketCols = Int(ceil(width / perception)) + 4
        bucketRows = Int(ceil(height / perception)) + 4
        let n = bucketCols * bucketRows
        if bucketHead.count != n {
            bucketHead = [Int](repeating: -1, count: n)
            bucketCount = [Int](repeating: 0, count: n)
        } else {
            for b in 0..<n { bucketHead[b] = -1; bucketCount[b] = 0 }
        }
        if bucketNext.count != fish.count { bucketNext = [Int](repeating: -1, count: fish.count) }
        for i in fish.indices {
            bucketNext[i] = -1
            if fish[i].alive {
                let b = bucketOf(fish[i].x, fish[i].y)
                bucketNext[i] = bucketHead[b]
                bucketHead[b] = i
                bucketCount[b] += 1
            }
        }
    }

    // MARK: Fish

    private func stepFish(_ dt: Double) {
        let W = width, H = height, t = time
        let R = perception, R2 = R * R
        let cols = bucketCols, rows = bucketRows
        let calmDecay = exp(-dt * 0.7)
        let contagion = min(1, dt * 6)

        for i in fish.indices {
            var f = fish[i]
            guard f.alive else { continue }
            let sp = fishSpecies[f.species]
            let spread = 1 + 1.8 * f.alarm
            let sepXi = sepX[f.species] * spread
            let sepYi = sepY[f.species] * spread

            var speed = hypot2(f.vx, f.vy)
            if speed == 0 { speed = 1 }
            let hx = f.vx / speed, hy = f.vy / speed

            var ax = 0.0, ay = 0.0
            var sx = 0.0, sy = 0.0
            var avx = 0.0, avy = 0.0
            var cx = 0.0, cy = 0.0
            var n = 0
            var neighbourAlarm = 0.0

            let bc = Int(oceanClamp(floor(f.x / R) + 2, 0, Double(cols - 1)))
            let br = Int(oceanClamp(floor(f.y / R) + 2, 0, Double(rows - 1)))
            for r in max(0, br - 1)...min(rows - 1, br + 1) {
                for c in max(0, bc - 1)...min(cols - 1, bc + 1) {
                    var j = bucketHead[r * cols + c]
                    while j >= 0 {
                        if j != i {
                            let o = fish[j]
                            let dx = o.x - f.x, dy = o.y - f.y
                            let d2 = dx * dx + dy * dy
                            if d2 < R2 && d2 > 1e-6 {
                                let d = d2.squareRoot()
                                if (dx * hx + dy * hy) / d > blindCos {
                                    let qx = dx / sepXi, qy = dy / sepYi
                                    let q2 = qx * qx + qy * qy
                                    if q2 < 1 {
                                        var q = q2.squareRoot()
                                        if q == 0 { q = 1e-3 }
                                        let k = (1 - q) / q
                                        sx -= qx * k
                                        sy -= qy * k
                                    }
                                    if o.species == f.species {
                                        avx += o.vx; avy += o.vy
                                        cx += dx; cy += dy
                                        n += 1
                                    } else if d < foreignSep {
                                        let k = (1 - d / foreignSep) / d * 0.6
                                        sx -= dx * k
                                        sy -= dy * k
                                    }
                                    if o.alarm > neighbourAlarm { neighbourAlarm = o.alarm }
                                }
                            }
                        }
                        j = bucketNext[j]
                    }
                }
            }

            ax += sx * fishSeparationK
            ay += sy * fishSeparationK
            if n > 0 {
                let nn = Double(n)
                let alignK = fishAlignK * sp.align
                let cohesionK = fishCohesionK * sp.cohesion * (1 - 0.8 * f.alarm)
                ax += (avx / nn - f.vx) * alignK + cx / nn * cohesionK
                ay += (avy / nn - f.vy) * alignK + cy / nn * cohesionK
                if sp.mill > 0 {
                    var cl = hypot2(cx, cy)
                    if cl == 0 { cl = 1 }
                    ax += -cy / cl * f.millDir * sp.mill * (1 - f.alarm)
                    ay += cx / cl * f.millDir * sp.mill * (1 - f.alarm)
                }
            }

            // Predators: distance to the nearest point on the front half of each shark.
            var fear = 0.0
            for sh in sharks {
                let fearR = sh.length * 0.6 + 60
                var best = Double.infinity
                var bx = 0.0, by = 0.0
                for k in stride(from: 0, through: 12, by: 3) {
                    let nx = sh.nodes[k * 2], ny = sh.nodes[k * 2 + 1]
                    let d2 = (f.x - nx) * (f.x - nx) + (f.y - ny) * (f.y - ny)
                    if d2 < best { best = d2; bx = nx; by = ny }
                }
                let d = best.squareRoot()
                if d < fearR && d >= 1e-3 {
                    var wgt = 1 - d / fearR
                    wgt *= wgt
                    let awayX = (f.x - bx) / d, awayY = (f.y - by) / d
                    let shx = cos(sh.heading), shy = sin(sh.heading)
                    let side: Double = shx * (f.y - sh.nodes[1]) - shy * (f.x - sh.nodes[0]) >= 0 ? 1 : -1
                    ax += (awayX * 0.7 - shy * side * 0.9) * fishFleeK * wgt
                    ay += (awayY * 0.7 + shx * side * 0.9) * fishFleeK * wgt
                    fear = max(fear, wgt.squareRoot())
                }
            }

            if pointer.active {
                let pr = 130.0
                let dx = f.x - pointer.x, dy = f.y - pointer.y
                let d = hypot2(dx, dy)
                if d < pr && d > 1e-3 {
                    let wgt = (1 - d / pr) * (1 - d / pr)
                    ax += dx / d * fishFleeK * wgt
                    ay += dy / d * fishFleeK * wgt
                    fear = max(fear, wgt.squareRoot() * 0.8)
                }
            }

            var alarm = max(f.alarm * calmDecay, fear)
            let relayed = neighbourAlarm * 0.86
            if relayed > alarm { alarm += (relayed - alarm) * contagion }
            f.alarm = alarm

            // Soft walls: the terrain's real edges (screen edges no other screen continues).
            let wall = terrain.wallPush(SIMD2(f.x, f.y), margin: 36)
            ax += wall.x
            ay += wall.y

            let (cux, cuy) = current(f.x, f.y, t)
            ax += cux * 0.5 + (rng.unit() - 0.5) * sp.jitter
            ay += cuy * 0.5 + (rng.unit() - 0.5) * sp.jitter
            ay -= f.vy * sp.verticalDrag * (1 - 0.7 * f.alarm)

            let preferred = sp.cruise * (1 + 1.3 * f.alarm)
            ax += (preferred - speed) * hx * 1.6
            ay += (preferred - speed) * hy * 1.6

            let before = atan2(f.vy, f.vx)
            f.vx += ax * dt
            f.vy += ay * dt
            let maxSpeed = sp.maxSpeed * (1 + 1.8 * f.alarm)
            let s = hypot2(f.vx, f.vy)
            if s > maxSpeed {
                f.vx *= maxSpeed / s; f.vy *= maxSpeed / s
            } else if s < sp.minSpeed && s > 1e-3 {
                f.vx *= sp.minSpeed / s; f.vy *= sp.minSpeed / s
            }
            f.turn += (angleDiff(before, atan2(f.vy, f.vx)) / dt - f.turn) * min(1, dt * 8)
            f.phase += dt * (7 + hypot2(f.vx, f.vy) * 0.12)
            f.x = oceanClamp(f.x + f.vx * dt, -60, W + 60)
            f.y = oceanClamp(f.y + f.vy * dt, -60, H + 60)
            fish[i] = f
        }
    }

    // MARK: Sharks

    /// Prey in the forward cone, preferring close fish in sparse spots (stragglers).
    private func findPrey(_ sh: Shark) -> Int? {
        let range = sh.length * 0.9 + 160
        let hx = sh.nodes[0], hy = sh.nodes[1]
        let fx = cos(sh.heading), fy = sin(sh.heading)
        var best: Int? = nil
        var bestScore = Double.infinity
        var currentScore = Double.infinity
        for (i, f) in fish.enumerated() where f.alive {
            let dx = f.x - hx, dy = f.y - hy
            let d = hypot2(dx, dy)
            if d > range || d < 1e-3 { continue }
            let c = (dx * fx + dy * fy) / d
            if c < 0.2 { continue }
            let crowd = Double(bucketCount[bucketOf(f.x, f.y)])
            let score = d * (1 + (1 - c) * 0.8) * (1 + crowd * 0.07)
            if score < bestScore { bestScore = score; best = i }
            if i == sh.target { currentScore = score }
        }
        if let t = sh.target, currentScore < bestScore * 1.3 { return t }
        return best
    }

    private func stepSharks(_ dt: Double) {
        let t = time

        for s in sharks.indices {
            var sh = sharks[s]
            let L = sh.length
            let hx = sh.nodes[0], hy = sh.nodes[1]
            // Geometry of the screen this shark patrols.
            if !terrain.rects.indices.contains(sh.home) { sh.home = terrain.rectIndex(near: SIMD2(hx, hy)) }
            let home = terrain.rects[sh.home]
            let W = Double(home.width), H = Double(home.height)
            let minSide = min(W, H)
            let cxW = Double(home.midX), cyW = Double(home.midY)

            sh.hunger = min(1, sh.hunger + dt * 0.03)

            var dx = cos(sh.heading), dy = sin(sh.heading)
            sh.wander = oceanClamp(sh.wander + (rng.unit() - 0.5) * dt * 3.2, -1.1, 1.1)
            dx += cos(sh.heading + sh.wander) * 0.45
            dy += sin(sh.heading + sh.wander) * 0.45

            // Now and then, wander off to a neighbouring screen through the edge they share.
            let doors = terrain.neighbours[sh.home]
            if sh.doorway == nil, !doors.isEmpty, t >= sh.migrateAt {
                let next = doors[rng.int(doors.count)]
                sh.doorway = terrain.doorway(sh.home, next)
                sh.home = next
                sh.migrateAt = t + rng.range(35, 80)
            }
            if let door = sh.doorway {
                let to = door - SIMD2(hx, hy)
                let d = simd_length(to)
                let arrived = terrain.rectIndex(near: SIMD2(hx, hy)) == sh.home && d > L * 0.25
                if arrived {
                    sh.doorway = nil
                } else if d > 1e-3 {
                    dx += to.x / d * 1.4
                    dy += to.y / d * 1.4
                }
            }

            if t >= sh.retargetAt {
                sh.target = findPrey(sh)
                sh.retargetAt = t + 0.45
            }
            var hunting = false
            var closing = 0.0
            if let ti = sh.target, fish[ti].alive, sh.hunger > 0.3 {
                let f = fish[ti]
                let tx = f.x + f.vx * 0.35 - hx
                let ty = f.y + f.vy * 0.35 - hy
                var d = hypot2(tx, ty)
                if d == 0 { d = 1 }
                let wgt = 1.4 + 2.6 * sh.hunger
                dx += tx / d * wgt
                dy += ty / d * wgt
                hunting = true
                closing = oceanClamp(1 - d / (L * 0.9), 0, 1)
            } else {
                // Patrol: a lazy circuit around the middle.
                let rx = (hx - cxW) / (W / minSide)
                let ry = hy - cyW
                var r = hypot2(rx, ry)
                if r == 0 { r = 1 }
                let radius = sh.orbitFrac * minSide * (1 + 0.15 * sin(t * 0.05 + Double(sh.id)))
                let radial = oceanClamp((radius - r) / radius, -1, 1)
                dx += (-ry / r * sh.orbitDir + rx / r * radial * 0.9) * 0.55
                dy += (rx / r * sh.orbitDir + ry / r * radial * 0.9) * 0.55
            }

            // Give other sharks room.
            for (o, other) in sharks.enumerated() where o != s {
                for k in stride(from: 0, to: World.sharkNodes, by: 4) {
                    let ox = hx - other.nodes[k * 2], oy = hy - other.nodes[k * 2 + 1]
                    let d = hypot2(ox, oy)
                    let range = (L + other.length) * 0.45
                    if d < range && d > 1e-3 {
                        let wgt = (1 - d / range) * 3
                        dx += ox / d * wgt
                        dy += oy / d * wgt
                    }
                }
            }

            // Keep the middle mostly clear: a soft elliptical no-swim zone.
            let ex = (hx - cxW) / (W * 0.3)
            let ey = (hy - cyW) / (H * 0.16)
            let e2 = ex * ex + ey * ey
            if e2 < 1 {
                var e = e2.squareRoot()
                if e == 0 { e = 1e-3 }
                let wgt = (1 - e) * (hunting ? 1 : 2.5)
                dx += ex / e * wgt
                dy += ey / e * wgt
            }

            // Turn back once the snout leaves the ocean (screen edges no other screen continues).
            let over = terrain.signedOutside(SIMD2(hx, hy))
            if over > -L * 0.05 {
                let wgt = oceanClamp((over + L * 0.05) / (L * 0.35), 0, 1) * 3.5
                let toX = cxW - hx, toY = cyW - hy
                var d = hypot2(toX, toY)
                if d == 0 { d = 1 }
                dx += toX / d * wgt
                dy += toY / d * wgt
            }

            let desired = atan2(dy, dx)
            let agility = min(hunting ? 1.7 + closing : 0.8, sh.speed / (L * 0.22))
            let maxTurn = agility * dt
            let turned = oceanClamp(angleDiff(sh.heading, desired), -maxTurn, maxTurn)
            sh.heading += turned
            sh.turn += (turned / dt - sh.turn) * min(1, dt * 3)

            let cruise = 30 + L * 0.04
            let targetSpeed = hunting ? cruise * (1.45 + closing * 1.5) : cruise
            sh.speed += (targetSpeed - sh.speed) * min(1, dt * 1.1)
            sh.phase += dt * (2 + sh.speed / 24)

            sh.nodes[0] += cos(sh.heading) * sh.speed * dt
            sh.nodes[1] += sin(sh.heading) * sh.speed * dt

            // Follow-the-leader spine with a bend limit per joint.
            let seg = L / Double(World.sharkNodes - 1)
            let maxBend = 0.16
            var prevAngle = sh.heading + .pi
            for k in 1..<World.sharkNodes {
                let px = sh.nodes[(k - 1) * 2], py = sh.nodes[(k - 1) * 2 + 1]
                var angle = atan2(sh.nodes[k * 2 + 1] - py, sh.nodes[k * 2] - px)
                angle = prevAngle + oceanClamp(angleDiff(prevAngle, angle), -maxBend, maxBend)
                sh.nodes[k * 2] = px + cos(angle) * seg
                sh.nodes[k * 2 + 1] = py + sin(angle) * seg
                prevAngle = angle
            }

            // Feed.
            if sh.hunger > 0.15 {
                let mouthR = L * 0.05 + 8
                let mx = sh.nodes[0], my = sh.nodes[1]
                for i in fish.indices where fish[i].alive {
                    let ddx = fish[i].x - mx, ddy = fish[i].y - my
                    if ddx * ddx + ddy * ddy < mouthR * mouthR {
                        fish[i].alive = false
                        fish[i].respawnAt = t + rng.range(3, 8)
                        sh.hunger = max(0, sh.hunger - 0.16)
                        emit(.eat, fish[i].x, fish[i].y)
                    }
                }
            }
            sharks[s] = sh
        }
    }

    private func respawn() {
        let t = time
        guard !terrain.edges.isEmpty else { return }
        let due = fish.indices.filter { !fish[$0].alive && fish[$0].respawnAt <= t }
        if due.isEmpty { return }
        if due.count < 6 && t - lastSpawn < 9 { return }
        lastSpawn = t

        // A new school swims in from a random real edge, weighted by length.
        let edges = terrain.edges
        var pick = rng.unit() * edges.reduce(0) { $0 + $1.length }
        var edge = edges[0]
        for e in edges {
            pick -= e.length
            if pick <= 0 { edge = e; break }
        }
        let p = edge.a + (edge.b - edge.a) * rng.range(0.15, 0.85) - edge.normal * 20
        let x = p.x, y = p.y
        let target = terrain.rects[edge.rect]
        let inward = atan2(Double(target.midY) - y, Double(target.midX) - x) + rng.range(-0.5, 0.5)
        let species = pickSpecies()
        let sp = fishSpecies[species]
        let millDir: Double = rng.chance(0.5) ? 1 : -1
        for k in 0..<min(due.count, sp.schoolMax) {
            let i = due[k]
            fish[i].alive = true
            fish[i].species = species
            fish[i].alarm = 0
            fish[i].turn = 0
            fish[i].millDir = millDir
            fish[i].x = x + rng.range(-1, 1) * perception
            fish[i].y = y + rng.range(-1, 1) * perception
            fish[i].vx = cos(inward) * sp.cruise * 1.4
            fish[i].vy = sin(inward) * sp.cruise * 1.4
        }
    }
}
