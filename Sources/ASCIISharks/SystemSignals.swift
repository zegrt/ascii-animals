import AppKit
import IOKit.ps
import OceanKit

/// Turns what macOS reports into `PowerInputs`. Notifications drive it, and
/// every 30 s (and on wake / unlock) the lock, console and screensaver state
/// is re-read from the OS so a missed notification can't leave it paused.
final class SystemSignals {
    private(set) var inputs = PowerInputs()
    var onChange: ((PowerInputs) -> Void)?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var powerSource: CFRunLoopSource?

    init() {
        inputs.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        inputs.thermal = SystemSignals.thermal(ProcessInfo.processInfo.thermalState)
        inputs.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        inputs.onBattery = SystemSignals.onBattery()
        inputs = PowerPolicy.reconcile(inputs, session: SystemSignals.sessionTruth())

        let ws = NSWorkspace.shared.notificationCenter
        let dn = DistributedNotificationCenter.default()
        let nc = NotificationCenter.default
        observe(ws, NSWorkspace.screensDidSleepNotification) { $0.displaysAsleep = true }
        observe(ws, NSWorkspace.screensDidWakeNotification) { $0.displaysAsleep = false; $0 = PowerPolicy.reconcile($0, session: SystemSignals.sessionTruth()) }
        observe(ws, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false }
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification) { $0 = PowerPolicy.reconcile($0, session: SystemSignals.sessionTruth()) }
        observe(ws, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { $0.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        observe(dn, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        observe(dn, Notification.Name("com.apple.screenIsUnlocked")) { $0 = PowerPolicy.reconcile($0, session: SystemSignals.sessionTruth()) }
        observe(dn, Notification.Name("com.apple.screensaver.didstart")) { $0.screensaverRunning = true }
        observe(dn, Notification.Name("com.apple.screensaver.didstop")) { $0.screensaverRunning = false }
        observe(nc, Notification.Name.NSProcessInfoPowerStateDidChange) { $0.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
        observe(nc, ProcessInfo.thermalStateDidChangeNotification) { $0.thermal = SystemSignals.thermal(ProcessInfo.processInfo.thermalState) }

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<SystemSignals>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.set { $0.onBattery = SystemSignals.onBattery() } }
        }, context)?.takeRetainedValue() {
            powerSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.set { $0 = PowerPolicy.reconcile($0, session: SystemSignals.sessionTruth()) }
        }
    }

    deinit {
        for (c, t) in tokens { c.removeObserver(t) }
        timer?.invalidate()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
    }

    func setWindowVisibility(_ anyVisible: Bool) { set { $0.anyWindowVisible = anyVisible } }
    func setUserPaused(_ p: Bool) { set { $0.userPaused = p } }
    func setFPS(_ fps: Int) { set { $0.fpsSetting = fps } }
    func setLowPowerAnimates(_ on: Bool) { set { $0.lowPowerAnimates = on } }

    private func set(_ body: (inout PowerInputs) -> Void) {
        var i = inputs
        body(&i)
        guard i != inputs else { return }
        inputs = i
        onChange?(i)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping (inout PowerInputs) -> Void) {
        let t = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.set(body) }
        tokens.append((center, t))
    }

    static func sessionTruth() -> SessionTruth {
        let d = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        let locked = (d["CGSSessionScreenIsLocked"] as? Bool) ?? false
        let onConsole = (d[kCGSessionOnConsoleKey as String] as? Bool) ?? true
        let saver = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.ScreenSaver.Engine" || $0.bundleIdentifier == "com.apple.ScreenSaver.legacyScreenSaver"
        }
        return SessionTruth(screenLocked: locked, onConsole: onConsole, screensaverEngineRunning: saver)
    }

    static func onBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }

    static func thermal(_ s: ProcessInfo.ThermalState) -> PowerInputs.Thermal {
        switch s {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }
}
