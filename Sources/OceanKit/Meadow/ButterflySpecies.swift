import Foundation

/// The Meadow's four butterflies (owner decision: the swallowtail is the Old World *Papilio machaon*).
public enum ButterflyKind: String, Codable, CaseIterable, Sendable {
    case monarch, morpho, swallowtail, cabbageWhite
}

/// How a butterfly basks (research §2): wings open flat, closed (the morpho's cryptic underside), or held in a V
/// (the cabbage white's reflectance basking).
public enum BaskPose: Equatable, Sendable {
    case openFlat
    case closed
    /// Wings in a V with projected width `s`.
    case vee(Double)
}

/// How a chrysalis hangs (research §0.5): Nymphalidae hang head-down from a silk pad; Papilionidae and Pieridae
/// are girdled at an angle on a stem.
public enum PupaKind: Equatable, Sendable { case hanging, girdled }

/// One species' numbers: every row of the research's Recommended parameters table, plus the flight model's
/// constants that follow from them (§1.4). Sizes are in cells, speeds in pt/s and accelerations in pt/s² at full
/// size (13 × 19 pt cells); `Butterfly` scales them by `cell.width / 13`. Angles are radians.
public struct ButterflySpecies: Sendable {
    // ── Size ──
    /// Wingspan × height, cells.
    public let span: Double, height: Double
    /// The swallowtail's hindwing tails add a row below the wings.
    public let tailRow: Bool
    /// Individual size spread: ±12 %.
    public let sizeSpread: Double

    // ── Wingbeat (owner decision: screen = real × 0.28, capped at 3 Hz) ──
    public let realBeat: Double
    /// Screen wingbeat, Hz.
    public let beat: Double
    /// Stroke φ = φ_mid + A·cos θ: wings up (the clap) at θ = 0.
    public let strokeMid: Double, strokeAmp: Double

    // ── Speed ──
    public let cruise: Double, forage: Double
    /// Escape burst: speed × 2 and beat × 1.25 (still ≤ 3 Hz) for 0.6–1.2 s, climbing at `escapeClimb`.
    public let escapeSpeed: Double, escapeBeat: Double
    public let escapeSeconds: ClosedRange<Double>
    public let escapeClimb: ClosedRange<Double>
    /// Extra jinks thrown in when it flushes (the white's two).
    public let escapeJinks: Int

    // ── Flap bouts and glides ──
    /// Beats per flapping bout before a glide.
    public let boutBeats: ClosedRange<Int>
    /// Glide length, s.
    public let glideSeconds: ClosedRange<Double>
    /// Glide angle below level (Gibo's 3.6:1 is 15.5°). The white has no measured glide; its rare short glides
    /// use 20° (est.: a small, poor glider).
    public let glideAngle: Double
    /// Projected wing width held in a glide: 0.95 is the monarch's shallow V, 1 flat.
    public let glideWidth: Double

    // ── Turning ──
    /// Chance per beat of a jink, and the jink's spread (σ of the kick to the target heading).
    public let jinkChance: Double, jinkSigma: Double
    /// The morpho's bounds: every `boundBeats` beats the flight tilts up or down by `boundAngle`, about half a
    /// wingspan of height per bound. Zero for the others.
    public let boundBeats: ClosedRange<Int>
    public let boundAngle: Double
    /// Heading spring stiffness (1/s²) and damping ratio.
    public let headingK: Double, headingZeta: Double

    // ── Body ──
    /// Vertical bob amplitude, rows.
    public let bobRows: Double
    /// Body pitch swing about the path, ± radians.
    public let pitchSwing: Double
    /// Bank in turns, max radians.
    public let maxBank: Double

    // ── Behaviour (Task 3) ──
    /// How long a preferred direction lasts, s.
    public let persistence: ClosedRange<Double>
    /// Monarchs prefer crossing screens (×3 weight).
    public let crossingWeight: Double
    public let nectarSeconds: ClosedRange<Double>
    /// The swallowtail keeps fluttering its forewings while nectaring.
    public let nectarFlutter: Bool
    public let baskSeconds: ClosedRange<Double>
    public let baskPose: BaskPose
    /// The morpho rests wings-closed and flashes them open for 0.5 s every 10–30 s.
    public let flashEvery: ClosedRange<Double>?
    /// Flower preferences. Owner decision: morphos sip flowers like the rest, every flower weighted 0.5.
    public let flowerWeights: [FlowerKind: Double]
    /// Weight when choosing who lands on a still cursor.
    public let cursorWeight: Double
    /// Flush distance in cells, slow pointer → fast pointer.
    public let flushCells: ClosedRange<Double>
    /// Life cycle (monarch only in 3.1): the host plant (nil: the morpho's legume shrub isn't in the meadow).
    public let host: FlowerKind?
    public let pupa: PupaKind
    /// Default species mix: white 35 %, monarch 25 %, swallowtail 20 %, morpho 20 %.
    public let share: Double

    // ── The per-beat force model (research §1.4), tuned by `bodyBobsInRange` and `flightPathsMatchMeasurements` ──
    /// Lift on the downstroke, a_up = L·sin θ while sin θ > 0. The half-wave-rectified lift drives the bob at the
    /// beat frequency with amplitude L/2, so L ≈ 2·bob·(2πf)². Drag damps the bob a little and the forward tilt of
    /// the lift takes a little off; `liftTrim` is where that lands the measured bob on the table's value.
    public var lift: Double { 2 * bobRows * 19 * pow(TAU * beat, 2) * ButterflySpecies.liftTrim }
    /// Gravity, set so lift averages to it over a beat: mean(max(sin θ, 0)) = 1/π.
    public var gravity: Double { lift / .pi }
    /// The forward lurch at the clap, pt/s per beat, as a fraction of cruise.
    public let thrust: Double
    /// Air drag rate toward the wanted airspeed, 1/s.
    public static let drag = 8.0
    /// Drag rate toward the glide vector, 1/s: a glide settles onto its slope within ~0.2 s.
    public static let glideDrag = 8.0
    static let liftTrim = 1.0

    private static let deg = Double.pi / 180

    public static func of(_ k: ButterflyKind) -> ButterflySpecies {
        switch k {
        case .monarch: return monarch
        case .morpho: return morpho
        case .swallowtail: return swallowtail
        case .cabbageWhite: return cabbageWhite
        }
    }

    static let monarch = ButterflySpecies(
        span: 13, height: 5, tailRow: false, sizeSpread: 0.12,
        realBeat: 9.5, beat: 2.6, strokeMid: 20 * deg, strokeAmp: 60 * deg,
        cruise: 170, forage: 80, escapeSpeed: 2, escapeBeat: 1.25, escapeSeconds: 0.6...1.2,
        escapeClimb: (15 * deg)...(15 * deg), escapeJinks: 0,
        boutBeats: 3...8, glideSeconds: 1.5...5, glideAngle: 15.5 * deg, glideWidth: 0.95,
        jinkChance: 0.12, jinkSigma: 12 * deg, boundBeats: 0...0, boundAngle: 0,
        headingK: 30, headingZeta: 0.9,
        bobRows: 0.25, pitchSwing: 15 * deg, maxBank: 35 * deg,
        persistence: 180...480, crossingWeight: 3, nectarSeconds: 10...40, nectarFlutter: false,
        baskSeconds: 10...40, baskPose: .openFlat, flashEvery: nil,
        flowerWeights: [.milkweed: 3, .coneflower: 2, .clover: 1, .daisy: 1],
        cursorWeight: 1, flushCells: 3...6, host: .milkweed, pupa: .hanging, share: 0.25,
        thrust: 0.9)

    static let morpho = ButterflySpecies(
        span: 15, height: 5, tailRow: false, sizeSpread: 0.12,
        realBeat: 6, beat: 1.7, strokeMid: 15 * deg, strokeAmp: 65 * deg,
        cruise: 150, forage: 70, escapeSpeed: 2, escapeBeat: 1.25, escapeSeconds: 0.6...1.2,
        escapeClimb: (13 * deg)...(22 * deg), escapeJinks: 0,
        boutBeats: 4...10, glideSeconds: 0.6...2, glideAngle: 11 * deg, glideWidth: 1,
        jinkChance: 0.30, jinkSigma: 30 * deg, boundBeats: 2...4, boundAngle: 22 * deg,
        headingK: 35, headingZeta: 0.85,
        bobRows: 0.35, pitchSwing: 20 * deg, maxBank: 50 * deg,
        persistence: 30...90, crossingWeight: 1, nectarSeconds: 20...60, nectarFlutter: false,
        baskSeconds: 20...90, baskPose: .closed, flashEvery: 10...30,
        flowerWeights: Dictionary(uniqueKeysWithValues: FlowerKind.blooming.map { ($0, 0.5) }),
        cursorWeight: 0.5, flushCells: 2...5, host: nil, pupa: .hanging, share: 0.20,
        thrust: 0.9)

    static let swallowtail = ButterflySpecies(
        span: 13, height: 5, tailRow: true, sizeSpread: 0.12,
        realBeat: 7, beat: 2.0, strokeMid: 20 * deg, strokeAmp: 55 * deg,
        cruise: 170, forage: 80, escapeSpeed: 2, escapeBeat: 1.25, escapeSeconds: 0.6...1.2,
        escapeClimb: (15 * deg)...(15 * deg), escapeJinks: 0,
        boutBeats: 3...6, glideSeconds: 1...3, glideAngle: 12 * deg, glideWidth: 1,
        jinkChance: 0.25, jinkSigma: 25 * deg, boundBeats: 0...0, boundAngle: 0,
        headingK: 45, headingZeta: 0.9,
        bobRows: 0.25, pitchSwing: 15 * deg, maxBank: 40 * deg,
        persistence: 60...180, crossingWeight: 1, nectarSeconds: 6...25, nectarFlutter: true,
        baskSeconds: 10...30, baskPose: .openFlat, flashEvery: nil,
        flowerWeights: [.coneflower: 2, .fennel: 2, .milkweed: 1, .daisy: 1],
        cursorWeight: 2, flushCells: 3...7, host: .fennel, pupa: .girdled, share: 0.20,
        thrust: 0.9)

    static let cabbageWhite = ButterflySpecies(
        span: 9, height: 4, tailRow: false, sizeSpread: 0.12,
        realBeat: 11.8, beat: 3.0, strokeMid: 25 * deg, strokeAmp: 55 * deg,
        cruise: 140, forage: 70, escapeSpeed: 2, escapeBeat: 1.25, escapeSeconds: 0.6...1.2,
        escapeClimb: (20 * deg)...(20 * deg), escapeJinks: 2,
        boutBeats: 30...90, glideSeconds: 0.15...0.4, glideAngle: 20 * deg, glideWidth: 1,
        jinkChance: 0.40, jinkSigma: 40 * deg, boundBeats: 0...0, boundAngle: 0,
        headingK: 60, headingZeta: 0.8,
        bobRows: 0.2, pitchSwing: 12 * deg, maxBank: 45 * deg,
        persistence: 60...120, crossingWeight: 1, nectarSeconds: 6...20, nectarFlutter: false,
        baskSeconds: 8...25, baskPose: .vee(0.5), flashEvery: nil,
        flowerWeights: [.mustard: 3, .clover: 2, .daisy: 2, .dandelion: 2],
        cursorWeight: 2, flushCells: 2...6, host: .mustard, pupa: .girdled, share: 0.35,
        thrust: 1.1)
}
