import Foundation

/// What a butterfly is doing (the sketch's `state`, html:1294).
public enum ButterflyState: Sendable {
    case fly, approach, nectar, bask, cursor
    /// `isLanded` (html:1294).
    public var landed: Bool { self == .nectar || self == .bask || self == .cursor }
}

/// Where an approach is going (the sketch's `goal`).
public enum ButterflyGoal: Sendable { case none, nectar, bask, cursor }

/// The spiral in to a still pointer (html:1924).
struct Spiral {
    var on = false
    var swept = 0.0
    var last = 0.0
    var t = 0.0
    var done = 0.0
    var loops = 0.0
    var r0 = 0.0
    var dir = 1.0
}

/// One butterfly: the sketch's fly object (`makeFly`, html:1316–1342). A class, as the sketch's objects are shared by
/// reference; made only when one joins the meadow, never per step.
public final class Butterfly {
    public let id: Int
    public let kind: ButterflyKind
    public let sp: ButterflySpecies
    public internal(set) var x = 0.0, y = 0.0
    var ux = 0.0, uy = 0.0
    public internal(set) var vx = 0.0, vy = 0.0
    public internal(set) var heading = 0.0
    var turn = 0.0, jink = 0.0
    public internal(set) var phase = 0.0
    public internal(set) var stroke = 0.0
    public internal(set) var bank = 0.0
    public internal(set) var z = 0.5
    var zs = 0.5, zv = 0.0, bobAmp = 1.0
    public internal(set) var size = 1.0
    var beatF = 1.0, jinkF = 1.0
    public internal(set) var seed = 0
    var gliding = false, glideLeft = 0.0, glideHeading = 0.0, beatsLeft = 0, armed = false, pace = 1.0
    var bound = 1.0, boundLeft = 0, boost = 0.0, boostK = 1.8
    public internal(set) var state = ButterflyState.fly
    public internal(set) var goal = ButterflyGoal.none
    public internal(set) var flower = 0
    var gx = 0.0, gy = 0.0, wx = 0.0, wy = 0.0, wpLeft = 0.0
    var timer = 0.0, landHeading = 0.0
    public internal(set) var slow = 0.0
    var flash = 0.0, flashT = 0.0
    var t = 0.0
    var boldU = 0.0, energy = 0.0, warmth = 0.0, airT = 0.0
    var blendK = 1.0, blendFrom = 0.0
    public internal(set) var landK = 1.0
    var landFrom = 0.0, brake = 0.0
    var alert = 0.0, leanX = 0.0, leanY = 0.0, flushIn = 0.0, fleeX = 0.0, fleeY = 0.0, relayDepth = 0, startleCd = 0.0
    var senseT = 0.0
    var tag = 0, tagTries = 0, circleT = 0.0, circleDir = 1.0
    var spiral: Spiral? = nil
    /// Called to a fresh bloom by a click (one at a time).
    public internal(set) var called = false
    /// Antenna twitches: time left and side (html:1329).
    public internal(set) var antT0 = 0.0, antT1 = 0.0
    public internal(set) var antS0 = 1.0, antS1 = -1.0
    var stillT = 0.0, shuffleT = 0.0
    public internal(set) var leaving = false
    public internal(set) var entering = false
    var dead = false
    public internal(set) var wait = 0.0

    init(id: Int, kind: ButterflyKind) {
        self.id = id
        self.kind = kind
        sp = kind.species
    }

    public var landed: Bool { state.landed }
}
