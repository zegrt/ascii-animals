import AppKit
import OceanKit

/// One line saying what the ocean is doing and why, for the menu and Settings.
struct OceanStatus: Equatable {
    enum Tone: Equatable { case live, resting, problem }

    /// "Swimming", "Paused", "Couldn't Start".
    var title: String
    /// "30 fps", "Low Power Mode", or empty.
    var detail: String
    var tone: Tone

    /// "Swimming · 30 fps", "Paused — Low Power Mode".
    var line: String {
        guard !detail.isEmpty else { return title }
        return tone == .live ? "\(title) · \(detail)" : "\(title) — \(detail)"
    }

    var color: NSColor {
        switch tone {
        case .live: return .systemGreen
        case .resting: return .systemOrange
        case .problem: return .systemRed
        }
    }

    static func make(settings: OceanKit.Settings, mode: RunMode?, inputs: PowerInputs, error: String?) -> OceanStatus {
        if let error { return OceanStatus(title: "Couldn't Start", detail: error, tone: .problem) }
        if settings.paused { return OceanStatus(title: "Paused", detail: "", tone: .resting) }
        guard let mode else { return OceanStatus(title: "Starting…", detail: "", tone: .resting) }
        switch mode {
        case .live(let fps):
            var detail = "\(fps) fps"
            if fps < inputs.fpsSetting {
                if inputs.lowPowerMode { detail += " in Low Power Mode" }
                else if inputs.onBattery { detail += " on battery" }
                else if inputs.thermal == .serious || inputs.thermal == .critical { detail += " while the Mac is warm" }
            }
            return OceanStatus(title: "Swimming", detail: detail, tone: .live)
        case .still:
            let why: String
            if inputs.reduceMotion { why = "Reduce Motion" }
            else if inputs.lowPowerMode && !inputs.lowPowerAnimates { why = "Low Power Mode" }
            else if inputs.thermal == .critical { why = "Mac Is Hot" }
            else { why = "Still Frame" }
            return OceanStatus(title: "Paused", detail: why, tone: .resting)
        case .paused:
            let why: String
            if inputs.screenLocked { why = "Screen Locked" }
            else if inputs.displaysAsleep { why = "Displays Asleep" }
            else if inputs.screensaverRunning { why = "Screen Saver" }
            else if !inputs.sessionActive { why = "Switched User" }
            else if !inputs.anyWindowVisible { why = "Desktop Covered" }
            else { why = "" }
            return OceanStatus(title: "Paused", detail: why, tone: .resting)
        }
    }

    /// The running app's status. Outside the app (the settings snapshot) it reads as swimming at the chosen rate.
    static func current(_ settings: OceanKit.Settings) -> OceanStatus {
        guard let app = NSApp.delegate as? AppDelegate else {
            return OceanStatus(title: "Swimming", detail: "\(settings.fps) fps", tone: .live)
        }
        return make(settings: settings, mode: app.director?.mode, inputs: app.signals.inputs,
                    error: app.startupError ?? app.director?.lastError)
    }
}
