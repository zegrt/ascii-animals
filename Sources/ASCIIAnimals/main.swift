// ASCII Animals: a live desktop wallpaper. Composition root.
import AppKit
import Metal
import OceanKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Lazy: the hand-over imports ASCII Sharks' settings first, then the store loads them. The what's-new preview
    /// holds the defaults in memory instead (`LaunchPlan.transientSettings`): nothing read, nothing saved.
    lazy var store: SettingsStore = Launch.plan.transientSettings ? SettingsStore(transient: .defaults) : SettingsStore()
    /// How this person came to 3.1 (`Arrival`): decided at launch, after the hand-over.
    var arrival: Arrival = .since31
    let signals = SystemSignals()
    var director: OceanDirector?
    var wallpaper: SystemWallpaper?
    var menu: StatusMenu?
    lazy var settingsModel = SettingsModel(store: store)
    lazy var settingsWindow = SettingsWindowController(model: settingsModel)
    var startupError: String?
    let updates = UpdateService()
    /// The energy-test copy's frame-rate log (`LaunchPlan.reportsFrameRate`).
    private var frameMeter: Timer?
    /// The last session ended without a clean quit.
    var crashedLastTime = false
    /// Set while uninstalling, so quitting writes nothing back.
    var isUninstalling = false
    private lazy var hotKey = HotKey { [weak self] in self?.store.update { $0.paused.toggle() } }
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        // What this copy may do is decided once from its bundle ID (`Launch.plan`). The energy-test copy is quiet or
        // previews the what's-new card: the welcome, the cards and `arrival.v1` are left alone (the arrival is taken as
        // an upgrade in memory), and the hand-over never runs (`SharksHandover.enabled`).
        let plan: LaunchPlan = Launch.plan
        SharksHandover.run(app: self)
        arrival = plan.greeting == .asSaved ? SettingsStore.decideArrival() : .before31
        SharksHandover.watch()
        crashedLastTime = CrashMarker.launch()
        if plan.identity.isEnergyTest {
            Log.write("energy-test copy: greeting \(plan.greeting), built-in display only \(plan.builtInDisplayOnly)")
        }
        Log.write("launch \(AppInfo.version) (\(AppInfo.build))\(crashedLastTime ? " after an unclean exit" : "")")
        do {
            guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError(description: "This Mac has no Metal device.") }
            let renderer = try OceanRenderer(device: device)
            let d = OceanDirector(renderer: renderer, store: store, signals: signals)
            director = d
            wallpaper = SystemWallpaper(renderer: renderer)   // nil in the energy-test copy
            d.onLooksSettled = { [weak self] in self?.refreshSystemWallpaper(delay: 1) }
            signals.onChange = { [weak d] inputs in
                d?.apply(PowerPolicy.mode(inputs))
                WhatsNewCard.powerChanged(inputs)
            }
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
            Log.write("could not start: \(error)")
        }
        menu = StatusMenu(app: self)
        menu?.apply(store.settings)
        hotKey.setEnabled(store.settings.pauseShortcut)
        if plan.startsUpdates {
            updates.start(enabled: { [weak self] in self?.store.settings.checkForUpdates ?? false },
                          autoInstall: { [weak self] in self?.store.settings.autoInstallUpdates ?? false })
        }
        if plan.reportsFrameRate { startFrameMeter() }
        switch plan.greeting {
        case .asSaved: OnboardingController.showIfNeeded(app: self)
        case .whatsNewPreview:
            Log.write("what's-new preview: the card once, settings in memory, nothing saved")
            WhatsNewCard.showWhenSeen(app: self)
        case .quiet: break
        }
    }

    /// The energy-test copy logs, every 5 seconds, the power mode and the frames actually drawn per second per screen,
    /// so Tools/energy.sh can report what was measured (a hot Mac can hold 30 fps at 15).
    private func startFrameMeter() {
        var lastFrames: Int = director?.framesDrawn ?? 0
        var lastTime: TimeInterval = ProcessInfo.processInfo.systemUptime
        frameMeter = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, let d = self.director else { return }
            let now: TimeInterval = ProcessInfo.processInfo.systemUptime
            let frames: Int = d.framesDrawn
            let screens: Int = max(1, d.screens.count)
            let elapsed: Double = max(0.001, now - lastTime)
            let perScreen: Double = Double(frames - lastFrames) / elapsed / Double(screens)
            lastFrames = frames
            lastTime = now
            let i: PowerInputs = self.signals.inputs
            let fps: String = String(format: "%.1f", perScreen)
            let mode: String
            switch d.mode {
            case .live(let f): mode = "live\(f)"
            case .still: mode = "still"
            case .paused: mode = "paused"
            }
            let s: OceanKit.Settings = self.store.settings
            let fields: [String] = ["mode=\(mode)", "fps=\(fps)", "screens=\(d.screens.count)", "setting=\(s.fps)",
                                    "habitat=\(s.habitat.rawValue)", "count=\(s.meadowCount)", "lowPower=\(i.lowPowerMode)",
                                    "battery=\(i.onBattery)", "thermal=\(i.thermal)"]
            Log.write("energy: " + fields.joined(separator: " "))
        }
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows Settings —
    /// the way back when the menu-bar icon is hidden or behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func showAbout() { AboutWindow.show(app: self) }
    /// The welcome from Help. Off in the energy-test copy: it saves the welcome's flags and would draw over a run.
    func showWelcome() {
        if Launch.plan.greeting != .asSaved {
            Log.write("welcome from Help: off in this developer run")
            return
        }
        OnboardingController.show(app: self)
    }
    /// Opens a prefilled GitHub issue in the browser (nothing is sent until the user submits it).
    func reportProblem() {
        NSWorkspace.shared.open(IssueReport.url(base: AppInfo.issuesURL, title: "Problem: ", body: Diagnostics.body(app: self)))
    }

    /// Copies the diagnostics summary to the clipboard.
    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Diagnostics.body(app: self), forType: .string)
    }

    /// Confirms, restores the wallpaper, removes everything, trashes the app and quits.
    func uninstall() {
        guard Launch.plan.offersUninstall, Uninstaller.confirm() else { return }
        Uninstaller.run(app: self)
        exit(0)
    }

    func settingsChanged(_ old: OceanKit.Settings, _ new: OceanKit.Settings) {
        director?.settingsChanged(old: old, new: new)
        WhatsNewCard.settingsChanged(new)
        settingsModel.refresh()
        menu?.apply(new)
        if old.pauseShortcut != new.pauseShortcut { hotKey.setEnabled(new.pauseShortcut) }
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
        guard !isUninstalling else { return }
        if store.settings.matchSystemWallpaper { wallpaper?.restoreAll() }
        Log.write("quit")
        CrashMarker.cleanQuit()
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
    let model = SettingsModel(store: SettingsStore.snapshot())
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

// `ASCIIAnimals --uninstall [--yes]`: scripted removal (Tools/uninstall.sh).
// A running copy is asked to quit first so it puts the wallpaper back.
if CommandLine.arguments.contains("--uninstall") {
    guard Launch.plan.offersUninstall else {
        print("The energy-test copy has no uninstaller; Tools/energy.sh removes what it made.")
        exit(1)
    }
    app.setActivationPolicy(.accessory)
    if let id = Bundle.main.bundleIdentifier {
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: id) where other != .current {
            other.terminate()
            for _ in 0..<50 where !other.isTerminated { Thread.sleep(forTimeInterval: 0.1) }
        }
    }
    if CommandLine.arguments.contains("--yes") || Uninstaller.confirm() {
        let renderer = MTLCreateSystemDefaultDevice().flatMap { try? OceanRenderer(device: $0) }
        let wp = renderer.flatMap { SystemWallpaper(renderer: $0) }
        wp?.restoreAll()
        let problems = Uninstaller.run(app: nil)
        print(problems.isEmpty ? "ASCII Animals uninstalled." : "Uninstalled, except: \(problems.joined(separator: "; "))")
    }
    exit(0)
}

// Debug: render the welcome, the what's-new card or About to a PNG, or write the menu's outline, and exit.
let snapshots: [(String, (URL) -> Void)] = [("--snapshot-onboarding", OnboardingController.snapshot(to:)),
                                            ("--snapshot-whatsnew", WhatsNewCard.snapshot(to:)),
                                            ("--snapshot-whatsnew-probe", WhatsNewCard.probe(to:)),
                                            ("--snapshot-identity", IdentityProbe.run(to:)),
                                            ("--snapshot-about", AboutWindow.snapshot(to:)),
                                            ("--snapshot-menu", StatusMenu.snapshot(to:))]
for (flag, render) in snapshots {
    if let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count {
        app.setActivationPolicy(.prohibited)
        render(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        exit(0)
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
