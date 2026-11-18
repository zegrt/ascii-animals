// ASCII Sharks: a live desktop wallpaper. Composition root.
import AppKit
import Metal
import OceanKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SettingsStore()
    let signals = SystemSignals()
    var director: OceanDirector?
    var wallpaper: SystemWallpaper?
    var menu: StatusMenu?
    lazy var settingsModel = SettingsModel(store: store)
    lazy var settingsWindow = SettingsWindowController(model: settingsModel)
    var startupError: String?
    let updates = UpdateService()
    /// The last session ended without a clean quit (Task 2 sets it).
    var crashedLastTime = false
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
            let wp = SystemWallpaper(renderer: renderer)
            wallpaper = wp
            d.onLooksSettled = { [weak self] in self?.refreshSystemWallpaper(delay: 1) }
            signals.onChange = { [weak d] inputs in d?.apply(PowerPolicy.mode(inputs)) }
            store.onChange = { [weak self] old, new in self?.settingsChanged(old, new) }
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.director?.screensChanged()
                self?.refreshSystemWallpaper()
            })
            observers.append(nc.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.themeChanged()
            })
            observers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
                // effectiveAppearance updates on the next run-loop pass.
                DispatchQueue.main.async { self?.themeChanged() }
            })
            d.start()
        } catch {
            startupError = "\(error)"
            NSLog("ASCII Sharks could not start: %@", "\(error)")
        }
        menu = StatusMenu(app: self)
        updates.start { [weak self] in self?.store.settings.checkForUpdates ?? false }
        OnboardingController.showIfNeeded(app: self)
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows Settings —
    /// the way back when the menu-bar icon is hidden or behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func showAbout() { AboutWindow.show(app: self) }
    func showWelcome() { OnboardingController.show(app: self) }
    /// Opens a prefilled GitHub issue in the browser. (Task 2)
    func reportProblem() { NSWorkspace.shared.open(AppInfo.issuesURL) }
    /// Copies a diagnostics summary to the clipboard. (Task 2)
    func copyDiagnostics() {}
    /// Confirms, restores the wallpaper, removes everything, trashes the app and quits. (Task 3)
    func uninstall() {}

    func settingsChanged(_ old: OceanKit.Settings, _ new: OceanKit.Settings) {
        director?.settingsChanged(old: old, new: new)
        settingsModel.refresh()
        if !new.matchSystemWallpaper {
            if old.matchSystemWallpaper { wallpaper?.restoreAll() }
            return
        }
        var a = old, b = new
        // Only looks matter for the still.
        a.paused = false; b.paused = false; a.fps = 0; b.fps = 0; a.interaction = true; b.interaction = true
        a.lowPowerAnimates = false; b.lowPowerAnimates = false; a.speed = 1; b.speed = 1
        if a != b { refreshSystemWallpaper() }
    }

    private func themeChanged() {
        director?.refreshTheme()
        if store.settings.appearance == .system || store.settings.wakeColor == .accent { refreshSystemWallpaper() }
    }

    func refreshSystemWallpaper(delay: TimeInterval = 2) {
        guard let d = director, store.settings.matchSystemWallpaper else { return }
        let t = OceanDirector.currentTheme(store.settings)
        wallpaper?.scheduleApply(settings: store.settings, systemIsDark: d.systemIsDark, accent: t.wake == ThemeParams.cyan ? SIMD3(0.2, 0.5, 1) : t.wake, delay: delay)
    }

    func showSettings() { settingsWindow.show() }

    func applicationWillTerminate(_ notification: Notification) {
        if store.settings.matchSystemWallpaper { wallpaper?.restoreAll() }
    }
}

// SIGTERM (pkill, logout, the installer) quits normally, so the user's own
// wallpaper is put back.
signal(SIGTERM, SIG_IGN)
let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigterm.setEventHandler { NSApp.terminate(nil) }
sigterm.resume()

let app = NSApplication.shared

// Debug: render the settings window to a PNG and exit (the UI can't be
// screenshotted from a terminal without Screen Recording permission).
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-settings"), i + 1 < CommandLine.arguments.count {
    app.setActivationPolicy(.prohibited)
    let model = SettingsModel(store: SettingsStore())
    let view = NSHostingView(rootView: SettingsView(model: model))
    view.frame.size = view.fittingSize
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    window.layoutIfNeeded()
    view.layoutSubtreeIfNeeded()
    if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    }
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
