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
    public var thermal: Thermal = .nominal
    public var reduceMotion = false
    public var userPaused = false
    public var fpsSetting = 60

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
    public static func mode(_ i: PowerInputs) -> RunMode {
        let hidden = !i.anyWindowVisible || i.displaysAsleep || i.screenLocked || i.screensaverRunning || !i.sessionActive
        if hidden || i.userPaused { return .paused }
        if i.reduceMotion || i.lowPowerMode || i.thermal == .critical { return .still }
        var fps = i.fpsSetting
        if i.onBattery || i.thermal == .serious { fps = min(fps, 30) }
        return .live(fps: fps)
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
