/// Facts about the machine that decide how hard the wallpaper may work.
public struct PowerInputs: Equatable, Sendable {
    public enum Thermal: Sendable { case nominal, fair, serious, critical }

    public var anyWindowVisible = true
    public var displaysAsleep = false
    public var screenLocked = false
    public var screensaverRunning = false
    public var sessionActive = true
    public var onBattery = false
    public var lowPowerMode = false
    /// User setting: keep animating (at 30 fps) in Low Power Mode instead of holding a still.
    public var lowPowerAnimates = false
    public var thermal: Thermal = .nominal
    public var reduceMotion = false
    public var userPaused = false
    public var fpsSetting = 30

    public init() {}
}

/// What the OS reports right now, read directly instead of trusting that
/// every notification arrived.
public struct SessionTruth: Equatable, Sendable {
    public var screenLocked: Bool
    public var onConsole: Bool
    public var screensaverEngineRunning: Bool

    public init(screenLocked: Bool, onConsole: Bool, screensaverEngineRunning: Bool) {
        self.screenLocked = screenLocked
        self.onConsole = onConsole
        self.screensaverEngineRunning = screensaverEngineRunning
    }
}

public enum RunMode: Equatable, Sendable {
    /// Animate at up to this many frames per second.
    case live(fps: Int)
    /// Render one settled frame, then stop.
    case still
    /// Keep whatever is on screen; do no work.
    case paused
}

public enum PowerPolicy {
    /// Frame cap on battery, in Low Power Mode and under thermal pressure. Measured:
    /// most of a live wallpaper's cost is WindowServer recompositing the desktop
    /// every frame, so the frame rate is the lever that matters.
    public static let economyFPS = 15

    public static func mode(_ i: PowerInputs) -> RunMode {
        let hidden = !i.anyWindowVisible || i.displaysAsleep || i.screenLocked || i.screensaverRunning || !i.sessionActive
        if hidden || i.userPaused { return .paused }
        if i.reduceMotion || (i.lowPowerMode && !i.lowPowerAnimates) || i.thermal == .critical { return .still }
        var fps = i.fpsSetting
        if i.onBattery || i.lowPowerMode || i.thermal == .serious { fps = min(fps, PowerPolicy.economyFPS) }
        return .live(fps: fps)
    }

    /// The live previews (the what's-new card, the welcome, About): the desktop's own rule (Reduce Motion, Low Power
    /// Mode, heat, the rate on battery), except that a paused desktop or covered desktop windows don't stop a preview
    /// someone is looking at.
    public static func preview(_ i: PowerInputs) -> RunMode {
        var c = i
        c.anyWindowVisible = true
        c.userPaused = false
        return mode(c)
    }

    /// Replace the lock / session / screensaver flags with what the OS says now,
    /// so a missed "unlocked" or "screensaver stopped" notification can't leave
    /// the wallpaper paused forever.
    public static func reconcile(_ i: PowerInputs, session: SessionTruth) -> PowerInputs {
        var r = i
        r.screenLocked = session.screenLocked
        r.sessionActive = session.onConsole
        r.screensaverRunning = session.screensaverEngineRunning
        return r
    }
}

/// The welcome's tour (the full-screen first-launch welcome): how the habitat behind it runs, and which of its steps
/// it shows. Its steps ask for effects only where the habitat can show them.
public enum Tour {
    /// The tour's steps in order (the app's `OnboardingBeat`, the same raw values).
    public enum Step: Int, CaseIterable, Sendable {
        case habitat, hello, pointer, splash, menu, choose, dive

        /// Asks the person to make the habitat react: "Move your pointer", "Click for a splash".
        public var asksForEffect: Bool { self == .pointer || self == .splash }
    }

    /// The habitat behind the tour. PROOF STUB (fix round 3): the previews' rule as it stands.
    public static func mode(_ i: PowerInputs) -> RunMode {
        PowerPolicy.preview(i)
    }

    /// The steps shown. PROOF STUB (fix round 3): all of them.
    public static func steps(_ i: PowerInputs) -> [Step] {
        Step.allCases
    }

    /// The step after `s` for the machine's state now; nil after the last.
    public static func next(after s: Step, _ i: PowerInputs) -> Step? {
        let shown: [Step] = steps(i)
        return shown.first { (t: Step) -> Bool in t.rawValue > s.rawValue }
    }
}
