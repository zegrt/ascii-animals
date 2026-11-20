import Foundation

/// Every number the Meadow takes from the sketch, in one place, named as in the sketch (slider keys and constant
/// names), each with the line it comes from: `html:N` is `Tools/meadow-sketch/meadow.html` on `meadow-sketch` at
/// 4e1b869, the sketch the port copies (s1 closed there). Lengths are sketch points at a 13-pt cell; the code multiplies
/// them by `S = cell width / 13` (html:655), as the sketch does. Times are seconds of simulation, stepped at 1/60 s
/// (`OceanClock`).
///
/// The instance holds the director's slider settings (the sketch's defaults, `CONTROLS`, html:200–315); the app keeps
/// them fixed (the plan: everything but the presets and "land on a still pointer" stays at the director's numbers),
/// and the checks and the replay fixture may set others. The nested enums hold the sketch's constants. Each rule is
/// written here as the sketch runs it; where the port runs a rule differently, the comment says so and why.
///
/// The flight, the behaviours and the painter (task mp) keep their constants beside the code that uses them, each
/// with its `html:N` line, since they are the sketch's own expressions copied term for term; their sliders are here.
public struct MeadowTuning: Equatable, Sendable {
    // ── the director's slider settings (html:200–315, the defaults of 2026-11-20) ──

    /// `breeze`, 0…3 (html:292): the wind's strength.
    public var breeze = 1.7
    /// `downwash`, 0…3 (html:278): how hard a low butterfly's downstrokes push the air out under it.
    public var downwash = 1.0
    /// `nod`, 0…3 (html:280): how far a flower nods to a landing, a take-off or a touch.
    public var nod = 1.0
    /// `density`, 0.2…3 (html:284): planted patches across the screen.
    public var density = 0.85
    /// `flowerSize`, 0.4…2 (html:286): the size of every bloom, the clicked ones too.
    public var flowerSize = 1.32
    /// `leaves`, 0…2 (html:288): how much of the leaf rosettes is drawn (the painter's; the rosettes' size is not
    /// scaled by it).
    public var leaves = 0.9
    /// `clickLimit`, 1…30 (html:268): clicked flowers kept; beyond it the oldest closes and fades.
    public var clickLimit = 12

    // Butterflies (html:201–210).
    /// `count`, 1…12: butterflies on the meadow at once (per scene; `areaCount` is off at the director's settings).
    public var count = 7
    /// `areaCount` (html:204): scale the count by screen area (`wantedCount`, html:1382). Off at the director's
    /// settings; the app turns it on (m8), so `count` is the number on a laptop screen (at most
    /// `areaCountLimit` in a scene).
    public var areaCount = false
    /// `sizeLow`, 0.2…1.5, and `sizeHigh`, 0.4…2.5: drawn size at ground level and at the top of the flight
    /// (`depthScale`, html:2016). Size up is never below size down.
    public var sizeLow = 0.75
    public var sizeHigh = 1.4
    /// `species`: which are on (all four at the director's settings), in `ButterflyKind` order.
    public var species: [Bool] = [true, true, true, true]
    // Flight (html:212–233).
    /// `wingbeat`, 0.1…1: share of the real wingbeat (capped at `Flight.beatCap`).
    public var wingbeat = 0.5
    /// `lurch`, 0…3: the push forward each downstroke gives.
    public var lurch = 2.0
    /// `zigzag`, 0…3: jinks and side-slips at each wingbeat.
    public var zigzag = 1.29
    /// `glide`, 0…3: how often and how long they glide.
    public var glide = 0.1
    /// `speed`, 0.3…3: travel speed (1 is the measured cruise at screen scale).
    public var speed = 2.0
    /// `turning`, 0.2…2: how quickly they swing round to face where they fly.
    public var turning = 1.23
    /// `bob`, 0…3: the rise on each downstroke.
    public var bob = 1.0
    /// `height`, 0…1: time spent high vs low.
    public var height = 0.5
    /// `ease`, 0…3: soft take-off and landing (0: the snap of round 2).
    public var ease = 1.0
    // Visits and wants (html:234–250).
    public var visits = 0.35
    public var stay = 0.25
    public var bask = 0.2
    public var hunger = 1.0
    public var warmth = 1.0
    /// `sense`, 3…30 wingspans.
    public var sense = 12.0
    public var touchGo = 0.25
    // Temperament and the air (html:251–262).
    public var boldness = 1.0
    /// pt/s at a 13-pt cell.
    public var airClose = 60.0
    public var airFlush = 120.0
    public var relay = 0.6
    public var spaceByHeight = true
    // Your pointer (html:263–272).
    /// `cursorLand`: hold the pointer still and one lands on it (m8 ties it to the app's interaction setting).
    public var cursorLand = true
    /// `holdTime`, 1…10 s: how long the pointer stays still before one comes.
    public var holdTime = 3.0
    /// `answerGap`, 0…20 s: one butterfly answers a fresh bloom at most this often.
    public var answerGap = 5.0
    // Small life (html:273–276).
    public var life = 1.0
    // Air and ground, look (html:291–306).
    public var shadow = 1.0
    public var green = 0.69
    public var grass = 1.0
    public var depth = 1.0
    public var sparkle = 1.0

    public init() {}

    /// The director's settings: the sketch's defaults.
    public static let director = MeadowTuning()

    /// The screen the count is for: the director's laptop, 1800 × 1169 points, where the 7 was tuned (board,
    /// 2026-11-21; the sketch's is 1440 × 900, html:1382), so that screen shows exactly the chosen count.
    public static let areaCountReference = 1800.0 * 1169.0

    /// The most butterflies in one scene with `areaCount` on, however many screens it spans (the director, 2026-11-21:
    /// "Scale, but cap at 12 total"), so the Meadow stays within Web's CPU.
    public static let areaCountLimit = 12

    /// `wantedCount` with `areaCount` on, for one screen of `width × height` points: the count in proportion to the
    /// screen's area, rounded, at most 24 (html:1382); the scene then holds at most `areaCountLimit` in all. The
    /// port's difference: a screen smaller than the reference keeps the count, so the small previews (Settings,
    /// About) show the line-up itself.
    public static func areaCount(_ count: Int, width: Double, height: Double) -> Int {
        let area: Double = width * height
        guard area.isFinite, area > 0 else { return count }
        let scale: Double = max(1, area / areaCountReference)
        let n: Double = (Double(count) * scale).rounded()
        return min(24, max(1, Int(n)))
    }

    /// Every value finite and inside its slider's range (the sketch's `normalize`, html:345–351, less the rounding
    /// to the slider's step, which only matters to the sketch's panel).
    public func sanitized() -> MeadowTuning {
        func fit(_ v: Double, _ lo: Double, _ hi: Double, _ d: Double) -> Double { v.isFinite ? min(hi, max(lo, v)) : d }
        let d = MeadowTuning.director
        var t = self
        t.breeze = fit(breeze, 0, 3, d.breeze)
        t.downwash = fit(downwash, 0, 3, d.downwash)
        t.nod = fit(nod, 0, 3, d.nod)
        t.density = fit(density, 0.2, 3, d.density)
        t.flowerSize = fit(flowerSize, 0.4, 2, d.flowerSize)
        t.leaves = fit(leaves, 0, 2, d.leaves)
        t.clickLimit = min(30, max(1, clickLimit))
        t.count = min(12, max(1, count))
        t.sizeLow = fit(sizeLow, 0.2, 1.5, d.sizeLow)
        t.sizeHigh = max(t.sizeLow, fit(sizeHigh, 0.4, 2.5, d.sizeHigh))
        t.species = (0..<4).map { $0 < species.count ? species[$0] : true }
        t.wingbeat = fit(wingbeat, 0.1, 1, d.wingbeat)
        t.lurch = fit(lurch, 0, 3, d.lurch)
        t.zigzag = fit(zigzag, 0, 3, d.zigzag)
        t.glide = fit(glide, 0, 3, d.glide)
        t.speed = fit(speed, 0.3, 3, d.speed)
        t.turning = fit(turning, 0.2, 2, d.turning)
        t.bob = fit(bob, 0, 3, d.bob)
        t.height = fit(height, 0, 1, d.height)
        t.ease = fit(ease, 0, 3, d.ease)
        t.visits = fit(visits, 0, 1, d.visits)
        t.stay = fit(stay, 0, 1.5, d.stay)
        t.bask = fit(bask, 0, 1, d.bask)
        t.hunger = fit(hunger, 0, 3, d.hunger)
        t.warmth = fit(warmth, 0, 3, d.warmth)
        t.sense = fit(sense, 3, 30, d.sense)
        t.touchGo = fit(touchGo, 0, 0.8, d.touchGo)
        t.boldness = fit(boldness, 0, 1, d.boldness)
        t.airClose = fit(airClose, 20, 200, d.airClose)
        t.airFlush = fit(airFlush, 40, 400, d.airFlush)
        t.relay = fit(relay, 0, 1, d.relay)
        t.holdTime = fit(holdTime, 1, 10, d.holdTime)
        t.answerGap = fit(answerGap, 0, 20, d.answerGap)
        t.life = fit(life, 0, 3, d.life)
        t.shadow = fit(shadow, 0, 1.5, d.shadow)
        t.green = fit(green, 0, 2.5, d.green)
        t.grass = fit(grass, 0, 2, d.grass)
        t.depth = fit(depth, 0, 2, d.depth)
        t.sparkle = fit(sparkle, 0, 3, d.sparkle)
        return t
    }

    // ── the sketch's constants ──

    /// The cell, the unit and the pace (html:655, 308).
    public enum Unit {
        /// `S = cw / 13`: sketch points per point at the app's cell width.
        public static let referenceCell = 13.0
        /// The port's guard: the cell width the meadow uses is held to this (the sketch's are 8–13 pt, html:655,
        /// as the app's `GridSpec.cell(forWidth:)`); one that isn't a positive number is 13. So S stays a usable
        /// scale: a subnormal width can't underflow it to 0.
        public static let cellRange = 2.0...100.0
        /// The sketch's Slow motion (`timeScale`, 0.05…1.5, html:308): the pace a step's real time is divided by. The
        /// app's speed setting (0.5…1.5) lies inside it; one that isn't a positive number is 1.
        public static let paceRange = 0.05...1.5
        /// The port's guard: places are held to ±1e7 pt before the wind's arithmetic (a desk is under 1e5 pt), so
        /// no product overflows.
        public static let coordinateLimit = 1e7

        /// The cell width the meadow uses for `w`.
        public static func cellWidth(_ w: Double) -> Double {
            guard w.isFinite && w > 0 else { return referenceCell }
            return min(cellRange.upperBound, max(cellRange.lowerBound, w))
        }

        /// The pace the meadow uses for a speed setting `v`.
        public static func pace(_ v: Double) -> Double {
            guard v.isFinite && v > 0 else { return 1 }
            return min(paceRange.upperBound, max(paceRange.lowerBound, v))
        }
    }

    /// The breeze: a slowly turning wind with gust bands rolling downwind (`updateWind`, `gustAt`, `windAt`,
    /// html:724–753).
    public enum Wind {
        /// Direction, rad: `0.35 + 1.1 · n1(t · 0.013, 91)` (html:725).
        public static let directionMean = 0.35
        public static let directionSwing = 1.1
        public static let directionRate = 0.013
        public static let directionNoise = 91.0
        /// Base speed, pt/s: `26 · S · breeze · (0.75 + 0.35 · n1(t · 0.05, 17))` (html:727).
        public static let baseSpeed = 26.0
        public static let baseMean = 0.75
        public static let baseSwing = 0.35
        public static let baseRate = 0.05
        public static let baseNoise = 17.0
        /// Gust bands: 300 · S pt along the wind by 520 · S across it, rolling downwind at 0.42 bands/s (html:733–734).
        public static let bandAlong = 300.0
        public static let bandAcross = 520.0
        public static let bandRoll = 0.42
        /// Two value-noise octaves, 0.62 · vnoise(a, b, 5) + 0.38 · vnoise(2.3a + 3.3, 1.9b, 9) (html:735).
        public static let octave1 = 0.62
        public static let octave1Noise = 5.0
        public static let octave2 = 0.38
        public static let octave2Noise = 9.0
        public static let octave2Along = 2.3
        public static let octave2Shift = 3.3
        public static let octave2Across = 1.9
        /// Gust strength `smooth(0.42, 0.82, g)` (html:736).
        public static let gustFrom = 0.42
        public static let gustTo = 0.82
        /// Speed at a point: `base · (0.2 + 1.7 · gust)` (html:741). At breeze 1.7 and S = 1 it peaks at
        /// 26 · 1.7 · 1.1 · 1.9 ≈ 92 pt/s.
        public static let lull = 0.2
        public static let gustGain = 1.7
    }

    /// The air the pointer stirs and the wings' downwash: two fields on one coarse grid (`pfInit`, `updateWind`,
    /// `stir`, `wash`, `stirStep`; html:722–730, 755–764, 1625–1633, 1987–1996).
    public enum Stir {
        /// Grid spacing `PG = 48 · S` pt (html:723).
        public static let grid = 48.0
        /// Both fields decay as `exp(−1.6 · dt)` each step: a half-life of ln 2 / 1.6 ≈ 0.43 s (html:728).
        public static let decay = 1.6
        /// A stir writes within 3 grid cells, weight `(1 − d)² · 0.16`, clamped to ±260 pt/s (html:756–762).
        public static let radius = 3.0
        public static let gain = 0.16
        public static let limit = 260.0
        /// Each step stirs along the way the pointer went since the last step, at its speed as you moved it
        /// (`d / (dt / timeScale)`, each axis clamped to ±1500 pt/s), with an impulse of 60 · dt × that speed,
        /// split into one stir per 48 · S pt of the way (html:1987–1996). Only the pointer's latest position counts:
        /// at 30 Hz input every other step's way is empty and the next one twice as long, as in the sketch. The port
        /// stirs one way the sketch drops: the way the pointer went between the last step and leaving
        /// (`Breeze.pointerLeft`).
        public static let speedLimit = 1500.0
        public static let impulseRate = 60.0
        /// The port's guard: a way is split into at most this many stirs (a real step's way is a few grid
        /// spacings; only a broken jump comes near it).
        public static let maxStirs = 100_000.0
        /// Downwash (`wash`, html:1625–1633): outward from the butterfly, weight `1 − d / radius`, clamped to ±200.
        public static let washLimit = 200.0
        /// Under a butterfly with z < 0.35 on each downstroke: `520 · S · downwash · (1 − z / 0.35) · sinθ · dt`
        /// within 1.2 spans (html:1770).
        public static let washBelow = 0.35
        public static let washFlight = 520.0
        public static let washFlightRadius = 1.2
        /// A swallowtail fluttering on a flower: `300 · S · downwash · sinθ · dt` within 1.0 span (html:1900).
        public static let washFlutter = 300.0
        public static let washFlutterRadius = 1.0
        /// The port's guard: a wash reaches at most this many grid spacings.
        public static let washReach = 1e4
        /// The port's guard: the grid never holds more than this many samples (a huge or broken viewport widens the
        /// spacing instead of allocating without bound). Real desks stay far below it (six 6K screens: ~30 000).
        public static let maxSamples = 1 << 20
    }

    /// Flowers seen from above (`KIND`, `makeFlower`, `plant`, `stepFlowers`; html:769–976).
    public enum Flowers {
        /// Bloom radius `R = r · S · flowerSize · U(0.82, 1.18)` (html:784).
        public static let sizeLow = 0.82
        public static let sizeHigh = 1.18
        /// Patches: `max(1, round(area / (190000 · S²) · density))` (html:820); the port counts per screen.
        public static let patchArea = 190_000.0
        /// Each patch centre is the best of 10 candidates for distance from the others, 20 · S from the edges
        /// (html:822–828).
        public static let patchCandidates = 10
        public static let patchMargin = 20.0
        /// A patch's blooms lie within `r · S · flowerSize · (1.6 + 0.5 · n)` of its centre, up to 14 tries each
        /// (html:832–835).
        public static let patchSpread = 1.6
        public static let patchSpreadPerBloom = 0.5
        public static let bloomTries = 14
        /// Blooms may lie up to 10 pt past the screen's edge (html:839). The port: past a real edge only, never in a
        /// gap between screens and never across an edge two screens share.
        public static let edgeSlack = 10.0
        /// No overlap: centres at least `(R1 + R2) · 1.05` apart (html:842).
        public static let spacing = 1.05
        /// The port's guard on a huge viewport: at most this many patches per screen.
        public static let maxPatches = 4000
        /// The head on its stem is a damped spring: ζ 0.12 at the kind's f0, forced by
        /// `wind · |wind| · 0.0035 · (1 + 0.6 · R / (30 · S))`, its offset capped at 0.45 R (html:965–974).
        public static let zeta = 0.12
        public static let drag = 0.0035
        public static let dragBySize = 0.6
        public static let dragSize = 30.0
        public static let swingLimit = 0.45
        /// Growth: `age += dt / 2.2`, drawn at `easeOutBack(age)` with overshoot 1.4 (html:963, 1282).
        public static let growTime = 2.2
        public static let growOvershoot = 1.4
        /// Fed: lit back up while a butterfly feeds on it, eased at 1.6/s (html:961).
        public static let liftRate = 1.6
        /// Visited: the disc dims for 20–40 s after a visit (html:1543), by `smooth(0, 0.35, left / of)` (html:986):
        /// fully for the first 65 % of the time, easing back over the last 35 %.
        public static let dimLow = 20.0
        public static let dimHigh = 40.0
        public static let dimEase = 0.35
        /// A flower's reach (how far its drawing goes): `max(1.15 R, longest leaf) + 2 cells` (html:802).
        public static let reachHead = 1.15
        public static let reachCells = 2.0
    }

    /// A number a recipe draws, or one it doesn't: `between` draws once (`R(lo, hi)`), `fixed` draws nothing, so the
    /// stream stays the sketch's.
    public enum Pick: Equatable, Sendable {
        case fixed(Double)
        case between(Double, Double)
    }

    /// One leaf of a fixed recipe: at the rosette's angle plus `offset`, `length` and `width` in bloom radii.
    public struct Leaf: Equatable, Sendable {
        public var offset: Double
        public var length: Pick
        public var width: Pick
        public var kind: Int
    }

    /// A leaf rosette on the ground under a bloom (`makeFlower`, html:791–803): leaf kinds 0 plain, 1 thread
    /// (fennel), 2 toothed, 3 trefoil (clover), 4 lobed (dandelion), as the painter draws them.
    public enum Rosette: Equatable, Sendable {
        /// `count` leaves (`RI`), evenly round (`step` nil: 2π / n) or `step` rad apart, each jittered by
        /// ±`jitter` rad: `add(a0 + i·step + R(−j, j), length, width, kind)`.
        case ring(count: ClosedRange<Int>, step: Double?, jitter: Double, length: Pick, width: Pick, kind: Int)
        /// Fixed leaves, then with `chance` (one draw) the `extra` ones (milkweed's cross).
        case cross(main: [Leaf], chance: Double, extra: [Leaf])
    }

    /// A kind's numbers (`KIND`, html:770–778): radius r (sketch points), blooms per patch, its share when a kind is
    /// picked, the head's natural frequency f0 (Hz) and its petal count, and its rosette.
    public struct Kind: Equatable, Sendable {
        public var r: Double
        public var perPatch: ClosedRange<Int>
        public var weight: Double
        public var f0: (Double, Double)
        public var petals: ClosedRange<Int>
        public var rosette: Rosette

        public static func == (a: Kind, b: Kind) -> Bool {
            a.r == b.r && a.perPatch == b.perPatch && a.weight == b.weight && a.f0 == b.f0 && a.petals == b.petals
                && a.rosette == b.rosette
        }
    }

    /// The seven kinds, in the sketch's `KINDS` order (html:769–778, rosettes html:791–803).
    public static let kinds: [Kind] = [
        // daisy
        Kind(r: 66, perPatch: 2...4, weight: 1.4, f0: (1.5, 2.2), petals: 10...13,
             rosette: .ring(count: 4...6, step: nil, jitter: 0.3, length: .between(1.3, 1.6), width: .between(0.24, 0.3), kind: 2)),
        // coneflower
        Kind(r: 72, perPatch: 1...3, weight: 1.2, f0: (0.7, 1.1), petals: 10...12,
             rosette: .ring(count: 3...4, step: nil, jitter: 0.3, length: .between(1.5, 1.85), width: .between(0.26, 0.32), kind: 0)),
        // milkweed
        Kind(r: 52, perPatch: 1...3, weight: 0.9, f0: (0.8, 1.2), petals: 0...0,
             rosette: .cross(main: [Leaf(offset: 0, length: .between(1.7, 2.0), width: .fixed(0.5), kind: 0),
                                    Leaf(offset: Double.pi, length: .between(1.6, 1.9), width: .fixed(0.48), kind: 0)],
                             chance: 0.6,
                             extra: [Leaf(offset: Double.pi / 2, length: .fixed(1.4), width: .fixed(0.42), kind: 0),
                                     Leaf(offset: -Double.pi / 2, length: .fixed(1.35), width: .fixed(0.42), kind: 0)])),
        // fennel
        Kind(r: 80, perPatch: 1...2, weight: 0.8, f0: (0.7, 1.0), petals: 6...9,
             rosette: .ring(count: 7...10, step: nil, jitter: 0.2, length: .between(1.1, 1.45), width: .fixed(0.06), kind: 1)),
        // clover
        Kind(r: 38, perPatch: 3...5, weight: 0.5, f0: (1.8, 2.5), petals: 0...0,
             rosette: .ring(count: 1...2, step: 2.6, jitter: 0.3, length: .between(1.5, 1.8), width: .fixed(0.9), kind: 3)),
        // mustard
        Kind(r: 52, perPatch: 1...3, weight: 0.5, f0: (1.2, 1.8), petals: 0...0,
             rosette: .ring(count: 3...4, step: nil, jitter: 0.3, length: .between(1.4, 1.7), width: .between(0.3, 0.36), kind: 2)),
        // dandelion
        Kind(r: 50, perPatch: 2...4, weight: 1, f0: (1.6, 2.4), petals: 30...36,
             rosette: .ring(count: 6...8, step: nil, jitter: 0.2, length: .between(1.5, 1.9), width: .between(0.2, 0.24), kind: 4)),
    ]

    /// Mustard's florets (html:805–809): `RI(6, 9)` small four-petalled flowers in a loose spiral raceme, at
    /// `R · (0.18 + 0.78 · √((i + 0.5) / m))`, the golden angle 2.39996 apart from the bloom's turn, each
    /// `R · U(0.26, 0.34) · (1 − 0.25 · i / m)` across, the first still a bud.
    public enum Florets {
        public static let count = 6...9
        public static let inner = 0.18
        public static let spread = 0.78
        public static let turn = 2.39996
        public static let sizeLow = 0.26
        public static let sizeHigh = 0.34
        public static let shrink = 0.25
    }

    /// Clicks on the meadow (`clickAt`, `touchFlower`, `limitClicked`, `fadeFlower`; html:886–954).
    public enum Clicks {
        /// A click hits a bloom within `max(R · grow, 0.35 R) + 0.5 · cell` of its swaying head (html:895).
        public static let hitBloom = 0.35
        public static let hitCells = 0.5
        /// A touch nods the head away from the click: `0.25 · R · 2π · f0 · nod`, less by `1 − offset / 0.45 R`
        /// (down to 0.2) when it is already swung (html:930). A click within 0.15 R of the head nods it a random way.
        public static let touchNod = 0.25
        public static let touchCentre = 0.15
        public static let touchLeast = 0.2
        /// The puff: 8 pollen sparks, 3 if touched again within 0.5 s; at 15–45 · S pt/s from within 0.3 R, pushed
        /// 20 · S pt/s away from the click, living 0.7–1.4 s (html:932–936).
        ///
        /// The sketch's test is `simT − (f.touchT || −9) < 0.5` (html:932): its `||` treats a touch at simulation time
        /// 0 as never touched, so touches at time 0 all puff 8. The port's deviation: `touchedAt` starts at −9 and a
        /// touch at time 0 counts, so a second touch within 0.5 s of one at time 0 puffs 3 (and draws 5 fewer sparks'
        /// worth from the input stream than the sketch would there). Only a touch in the first step differs.
        public static let puff = 8
        public static let puffAgain = 3
        public static let puffWithin = 0.5
        public static let neverTouched = -9.0
        public static let puffSpeedLow = 15.0
        public static let puffSpeedHigh = 45.0
        public static let puffFrom = 0.3
        public static let puffPush = 20.0
        public static let puffLifeLow = 0.7
        public static let puffLifeHigh = 1.4
        /// A new bloom: 16 sparks at 20–70 · S pt/s, living 1.2–2.2 s (html:908–911).
        public static let bloomSparks = 16
        public static let bloomSpeedLow = 20.0
        public static let bloomSpeedHigh = 70.0
        public static let bloomLifeLow = 1.2
        public static let bloomLifeHigh = 2.2
        /// The sparks wait in a buffer of this many for the world's dust (`Flowers.takeSparks`, which the world calls
        /// every step). The port's: a spark past it is dropped (its random numbers are still drawn, so the input stream
        /// keeps the sketch's order). Between two takes it holds 16 new blooms' sparks (16 each) or 32 touches' (8
        /// each); 30 new blooms in one step ask for 480 and keep 256.
        public static let sparkBuffer = 256
        /// Over the limit, the oldest clicked flower closes and fades over `FADE_S` = 2 s (html:886).
        public static let fadeTime = 2.0
        /// The port's cap on flowers fading at once (the sketch has none): past it the most faded one goes at once,
        /// so clicks faster than the meadow steps, or relayouts in a row, can't pile up fading flowers. A person
        /// clicking ten times a second keeps about 20 fading, so the look never meets it.
        public static let fadingMost = 32
        /// A landing nods the flower `0.12 · R · size · 2π · f0 · nod` along the butterfly's way; a take-off kicks it
        /// half as much back (html:1532–1536, 1546, 1579).
        public static let landingNod = 0.12
    }

    /// Relayout (the sketch's `resize`, html:3076–3082).
    public enum Relayout {
        /// The sketch replants (`replant(false)`) when the window changes by more than 80 pt either way
        /// (html:3081), and keeps only clicked flowers still on it (html:870). The port's rules (the sketch's
        /// re-check, finding 4, and m1's review, finding 2):
        /// - it replants when a screen moves or changes size by more than this, when screens come or go, and when
        ///   the cell size changes (S changes every size, so the replant's sizing transition runs);
        /// - at any size of change, a flower the change leaves off the screens closes and fades over 2 s rather
        ///   than vanishing: a clicked one whose centre is off the screens, a planted one that stood on a screen
        ///   and no longer does (the 10 pt planting slack is for new planting only), and one that may no longer
        ///   stand where it is (in a gap, or past a shared edge);
        /// - a replant keeps every fading flower until its fade ends.
        public static let replantBeyond = 80.0
    }
}
