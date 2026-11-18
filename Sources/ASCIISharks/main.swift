// ASCII Sharks: a live desktop wallpaper. Composition root.
import AppKit
import Metal
import OceanKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SettingsStore()
    let signals = SystemSignals()
    var director: OceanDirector?
    var menu: StatusMenu?
    var startupError: String?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        do {
            guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError(description: "This Mac has no Metal device.") }
            let renderer = try OceanRenderer(device: device)
            let d = OceanDirector(renderer: renderer, store: store, signals: signals)
            director = d
            signals.onChange = { [weak d] inputs in d?.apply(PowerPolicy.mode(inputs)) }
            store.onChange = { [weak self] old, new in self?.settingsChanged(old, new) }
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak d] _ in
                d?.screensChanged()
            })
            observers.append(nc.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak d] _ in
                d?.refreshTheme()
            })
            observers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak d] _ in
                // effectiveAppearance updates on the next run-loop pass.
                DispatchQueue.main.async { d?.refreshTheme() }
            })
            d.start()
        } catch {
            startupError = "\(error)"
            NSLog("ASCII Sharks could not start: %@", "\(error)")
        }
        menu = StatusMenu(app: self)
    }

    func settingsChanged(_ old: Settings, _ new: Settings) {
        director?.settingsChanged(old: old, new: new)
    }

    func applicationWillTerminate(_ notification: Notification) {}
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
