import AppKit
import OceanKit

/// What Report a Problem and Copy Diagnostics say about this Mac.
enum Diagnostics {
    static func facts(app: AppDelegate) -> DiagnosticFacts {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let displays = NSScreen.screens.map {
            "\($0.localizedName) \(Int($0.frame.width))x\(Int($0.frame.height)) @\(Int($0.backingScaleFactor))x \($0.maximumFramesPerSecond) Hz"
        }
        let i = app.signals.inputs
        var power = [i.onBattery ? "battery" : "AC power"]
        if i.lowPowerMode { power.append("Low Power Mode") }
        if i.thermal != .nominal { power.append("thermal \(i.thermal)") }
        if i.reduceMotion { power.append("Reduce Motion") }
        let mode = DiagnosticFacts.mode(habitat: app.store.settings.habitat, run: app.director?.mode,
                                        screens: app.director?.screens.count ?? 0, scenes: app.director?.scenes.count ?? 0,
                                        failure: app.startupError)
        return DiagnosticFacts(
            appVersion: "\(AppInfo.version) (\(AppInfo.build))",
            macOS: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            model: String(cString: model),
            displays: displays, power: power.joined(separator: ", "), mode: mode,
            settingsJSON: String(decoding: SettingsCodec.encode(app.store.settings), as: UTF8.self),
            crashedLastTime: app.crashedLastTime, logTail: Log.tail(60))
    }

    static func body(app: AppDelegate) -> String {
        IssueReport.body(facts(app: app), homePath: NSHomeDirectory(), userName: NSUserName())
    }
}
