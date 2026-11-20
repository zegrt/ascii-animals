import Foundation

/// Every number the Meadow takes from the sketch, in one place, named as in the sketch (slider keys and constant
/// names), each with the line it comes from: `html:N` is `Tools/meadow-sketch/meadow.html` on `meadow-sketch` at
/// f20b833, the commit the sketch's re-check passed. Lengths are sketch points at a 13-pt cell; the code multiplies
/// them by `S = cell width / 13` (html:646), as the sketch does. Times are seconds of simulation, stepped at 1/60 s
/// (`OceanClock`).
///
/// The instance holds the director's slider settings (the sketch's defaults, `CONTROLS`, html:195–310); the app keeps
/// them fixed (the plan: everything but the presets and "land on a still pointer" stays at the director's numbers),
/// and the checks and the replay fixture may set others. The nested enums hold the sketch's constants. Each rule is
/// written here as the sketch runs it; where the port runs a rule differently, the comment says so and why.
///
/// Later tasks add their sliders and constants here.
public struct MeadowTuning: Equatable, Sendable {
    // ── the director's slider settings (html:195–310, the defaults of 2026-11-20) ──

    /// `breeze`, 0…3 (html:287): the wind's strength.
    public var breeze = 1.7
    /// `downwash`, 0…3 (html:273): how hard a low butterfly's downstrokes push the air out under it.
    public var downwash = 1.0
    /// `nod`, 0…3 (html:275): how far a flower nods to a landing, a take-off or a touch.
    public var nod = 1.0
    /// `density`, 0.2…3 (html:279): planted patches across the screen.
    public var density = 0.85
    /// `flowerSize`, 0.4…2 (html:281): the size of every bloom, the clicked ones too.
    public var flowerSize = 1.32
    /// `leaves`, 0…2 (html:283): how much of the leaf rosettes is drawn (the painter's; the rosettes' size is not
    /// scaled by it).
    public var leaves = 0.9
    /// `clickLimit`, 1…30 (html:263): clicked flowers kept; beyond it the oldest closes and fades.
    public var clickLimit = 12

    public init() {}

    /// The director's settings: the sketch's defaults.
    public static let director = MeadowTuning()

    /// Every value finite and inside its slider's range (the sketch's `normalize`, html:340–346, less the rounding
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
        return t
    }

    // ── the sketch's constants ──

    /// The cell and the unit (html:645–646).
    public enum Unit {
        /// `S = cw / 13`: sketch points per point at the app's cell width.
        public static let referenceCell = 13.0
    }

    /// The breeze: a slowly turning wind with gust bands rolling downwind (`updateWind`, `gustAt`, `windAt`,
    /// html:716–745).
    public enum Wind {
        /// Direction, rad: `0.35 + 1.1 · n1(t · 0.013, 91)` (html:717).
        public static let directionMean = 0.35
        public static let directionSwing = 1.1
        public static let directionRate = 0.013
        public static let directionNoise = 91.0
        /// Base speed, pt/s: `26 · S · breeze · (0.75 + 0.35 · n1(t · 0.05, 17))` (html:719).
        public static let baseSpeed = 26.0
        public static let baseMean = 0.75
        public static let baseSwing = 0.35
        public static let baseRate = 0.05
        public static let baseNoise = 17.0
        /// Gust bands: 300 · S pt along the wind by 520 · S across it, rolling downwind at 0.42 bands/s (html:725–726).
        public static let bandAlong = 300.0
        public static let bandAcross = 520.0
        public static let bandRoll = 0.42
        /// Two value-noise octaves, 0.62 · vnoise(a, b, 5) + 0.38 · vnoise(2.3a + 3.3, 1.9b, 9) (html:727).
        public static let octave1 = 0.62
        public static let octave1Noise = 5.0
        public static let octave2 = 0.38
        public static let octave2Noise = 9.0
        public static let octave2Along = 2.3
        public static let octave2Shift = 3.3
        public static let octave2Across = 1.9
        /// Gust strength `smooth(0.42, 0.82, g)` (html:728).
        public static let gustFrom = 0.42
        public static let gustTo = 0.82
        /// Speed at a point: `base · (0.2 + 1.7 · gust)` (html:733). At breeze 1.7 and S = 1 it peaks at
        /// 26 · 1.7 · 1.1 · 1.9 ≈ 92 pt/s.
        public static let lull = 0.2
        public static let gustGain = 1.7
    }

    /// The air the pointer stirs and the wings' downwash: two fields on one coarse grid (`pfInit`, `updateWind`,
    /// `stir`, `wash`, `stirStep`; html:714–722, 747–756, 1607–1615, 1969–1978).
    public enum Stir {
        /// Grid spacing `PG = 48 · S` pt (html:715).
        public static let grid = 48.0
        /// Both fields decay as `exp(−1.6 · dt)` each step: a half-life of ln 2 / 1.6 ≈ 0.43 s (html:720).
        public static let decay = 1.6
        /// A stir writes within 3 grid cells, weight `(1 − d)² · 0.16`, clamped to ±260 pt/s (html:748–754).
        public static let radius = 3.0
        public static let gain = 0.16
        public static let limit = 260.0
        /// Each step stirs along the way the pointer went since the last step, at its speed as you moved it
        /// (`d / (dt / timeScale)`, each axis clamped to ±1500 pt/s), with an impulse of 60 · dt × that speed,
        /// split into one stir per 48 · S pt of the way (html:1969–1978).
        public static let speedLimit = 1500.0
        public static let impulseRate = 60.0
        /// The port's rule for the pointer's path (the sketch's re-check, finding 7, routed to m1): the stir point
        /// plays the pointer's path back 0.1 s behind it, from the samples at the times they were taken, one point
        /// a step. Input at 15, 30, 60 or 120 Hz, arriving regularly or in bursts up to 0.1 s late, then stirs the
        /// same air, where the sketch's per-step difference alternates empty and doubled steps at 30 Hz and loses
        /// way at its speed clamp when two steps' worth arrives together. Samples later than the lag are caught up
        /// in one step: the way is never dropped. With no lag it is the sketch's `stirStep` exactly (the replay of
        /// the sketch runs it so).
        public static let pathLag = 0.1
        /// Downwash (`wash`, html:1607–1615): outward from the butterfly, weight `1 − d / radius`, clamped to ±200.
        public static let washLimit = 200.0
        /// Under a butterfly with z < 0.35 on each downstroke: `520 · S · downwash · (1 − z / 0.35) · sinθ · dt`
        /// within 1.2 spans (html:1752).
        public static let washBelow = 0.35
        public static let washFlight = 520.0
        public static let washFlightRadius = 1.2
        /// A swallowtail fluttering on a flower: `300 · S · downwash · sinθ · dt` within 1.0 span (html:1882).
        public static let washFlutter = 300.0
        public static let washFlutterRadius = 1.0
        /// The port's guard: the grid never holds more than this many samples (a huge or broken viewport widens the
        /// spacing instead of allocating without bound). Real desks stay far below it (six 6K screens: ~30 000).
        public static let maxSamples = 1 << 20
    }

    /// Flowers seen from above (`KIND`, `makeFlower`, `plant`, `stepFlowers`; html:761–968).
    public enum Flowers {
        /// Bloom radius `R = r · S · flowerSize · U(0.82, 1.18)` (html:776).
        public static let sizeLow = 0.82
        public static let sizeHigh = 1.18
        /// Patches: `max(1, round(area / (190000 · S²) · density))` (html:812); the port counts per screen.
        public static let patchArea = 190_000.0
        /// Each patch centre is the best of 10 candidates for distance from the others, 20 · S from the edges
        /// (html:814–820).
        public static let patchCandidates = 10
        public static let patchMargin = 20.0
        /// A patch's blooms lie within `r · S · flowerSize · (1.6 + 0.5 · n)` of its centre, up to 14 tries each
        /// (html:824–827).
        public static let patchSpread = 1.6
        public static let patchSpreadPerBloom = 0.5
        public static let bloomTries = 14
        /// Blooms may lie up to 10 pt past the screen's edge (html:829). The port: past a real edge only, never in a
        /// gap between screens and never across an edge two screens share.
        public static let edgeSlack = 10.0
        /// No overlap: centres at least `(R1 + R2) · 1.05` apart (html:832).
        public static let spacing = 1.05
        /// The port's guard on a huge viewport: at most this many patches per screen.
        public static let maxPatches = 4000
        /// The head on its stem is a damped spring: ζ 0.12 at the kind's f0, forced by
        /// `wind · |wind| · 0.0035 · (1 + 0.6 · R / (30 · S))`, its offset capped at 0.45 R (html:961–967).
        public static let zeta = 0.12
        public static let drag = 0.0035
        public static let dragBySize = 0.6
        public static let dragSize = 30.0
        public static let swingLimit = 0.45
        /// Growth: `age += dt / 2.2`, drawn at `easeOutBack(age)` with overshoot 1.4 (html:955, 1274).
        public static let growTime = 2.2
        public static let growOvershoot = 1.4
        /// Fed: lit back up while a butterfly feeds on it, eased at 1.6/s (html:953).
        public static let liftRate = 1.6
        /// Visited: the disc dims for 20–40 s after a visit (html:1525, 978).
        public static let dimLow = 20.0
        public static let dimHigh = 40.0
        /// A flower's reach (how far its drawing goes): `max(1.15 R, longest leaf) + 2 cells` (html:799).
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

    /// A leaf rosette on the ground under a bloom (`makeFlower`, html:783–795): leaf kinds 0 plain, 1 thread
    /// (fennel), 2 toothed, 3 trefoil (clover), 4 lobed (dandelion), as the painter draws them.
    public enum Rosette: Equatable, Sendable {
        /// `count` leaves (`RI`), evenly round (`step` nil: 2π / n) or `step` rad apart, each jittered by
        /// ±`jitter` rad: `add(a0 + i·step + R(−j, j), length, width, kind)`.
        case ring(count: ClosedRange<Int>, step: Double?, jitter: Double, length: Pick, width: Pick, kind: Int)
        /// Fixed leaves, then with `chance` (one draw) the `extra` ones (milkweed's cross).
        case cross(main: [Leaf], chance: Double, extra: [Leaf])
    }

    /// A kind's numbers (`KIND`, html:762–770): radius r (sketch points), blooms per patch, its share when a kind is
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

    /// The seven kinds, in the sketch's `KINDS` order (html:761–770, rosettes html:783–795).
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

    /// Mustard's florets (html:797–801): `RI(6, 9)` small four-petalled flowers in a loose spiral raceme, at
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

    /// Clicks on the meadow (`clickAt`, `touchFlower`, `limitClicked`, `fadeFlower`; html:878–946).
    public enum Clicks {
        /// A click hits a bloom within `max(R · grow, 0.35 R) + 0.5 · cell` of its swaying head (html:887).
        public static let hitBloom = 0.35
        public static let hitCells = 0.5
        /// A touch nods the head away from the click: `0.25 · R · 2π · f0 · nod`, less by `1 − offset / 0.45 R`
        /// (down to 0.2) when it is already swung (html:924). A click within 0.15 R of the head nods it a random way.
        public static let touchNod = 0.25
        public static let touchCentre = 0.15
        public static let touchLeast = 0.2
        /// The puff: 8 pollen sparks, 3 if touched again within 0.5 s; at 15–45 · S pt/s from within 0.3 R, pushed
        /// 20 · S pt/s away from the click, living 0.7–1.4 s (html:926–930).
        public static let puff = 8
        public static let puffAgain = 3
        public static let puffWithin = 0.5
        /// A new bloom: 16 sparks at 20–70 · S pt/s, living 1.2–2.2 s (html:900–903).
        public static let bloomSparks = 16
        /// Over the limit, the oldest clicked flower closes and fades over `FADE_S` = 2 s (html:878).
        public static let fadeTime = 2.0
        /// A landing nods the flower `0.12 · R · size · 2π · f0 · nod` along the butterfly's way; a take-off kicks it
        /// half as much back (html:1514–1518, 1528, 1561).
        public static let landingNod = 0.12
    }

    /// Relayout (the sketch's `resize`, html:2881–2886).
    public enum Relayout {
        /// The sketch replants when the window changes by more than 80 pt either way. The port: the same for a
        /// screen that changes by more than this; and any clicked flower a relayout leaves off the screens fades
        /// out, at any size of change (the sketch's re-check, finding 4, routed to m1).
        public static let replantBeyond = 80.0
    }
}
