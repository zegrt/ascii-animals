import AppKit
import OceanKit

/// First launch after ASCII Sharks: quits it, takes over its settings, offers to remove it; and while
/// ASCII Animals runs, quits it whenever it opens, so the two never run together.
enum SharksHandover {
    private static let importedKey = "handover.imported"
    private static let offeredKey = "handover.offered"
    /// How long Sharks' own uninstaller may take (it starts Metal to put the wallpaper back).
    private static let uninstallTimeout: TimeInterval = 30

    /// Only the real app acts on Sharks: never a bare dev binary (no bundle ID, its own defaults),
    /// and never a test run that opts out with ASCII_ANIMALS_NO_HANDOVER=1.
    private static var enabled: Bool {
        Handover.enabled(bundleID: Bundle.main.bundleIdentifier, environment: ProcessInfo.processInfo.environment)
    }

    /// Synchronous; returns once Sharks has quit (or there was nothing to do).
    /// Must run before `AppDelegate.store` is first touched, so the imported settings are what it loads.
    static func run(app: AppDelegate) {
        guard enabled else { return }
        let me = UserDefaults.standard
        let id = Handover.sharksBundleID
        let sharks = UserDefaults(suiteName: id)
        let live = running()
        // The copy that is running is the one to act on, wherever it is.
        let location = live.lazy.compactMap(\.bundleURL).first ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        let facts = HandoverFacts(
            sharksApp: location,
            sharksRunning: !live.isEmpty,
            alreadyOffered: me.bool(forKey: offeredKey),
            alreadyImported: me.bool(forKey: importedKey),
            sharksSettings: sharks?.data(forKey: Handover.sharksSettingsKey),
            sharksOnboarded: sharks?.bool(forKey: Handover.sharksOnboardedKey) ?? false,
            ownSettings: me.data(forKey: SettingsStore.key) != nil)
        let steps = Handover.plan(facts)
        if !steps.isEmpty { Log.write("hand-over: \(steps)") }
        var imported = false
        for step in steps {
            switch step {
            case .quitSharks: quitSharks()
            case .importSettings:
                if let data = facts.sharksSettings { me.set(data, forKey: SettingsStore.key); imported = true }
            case .skipWelcome: me.set(true, forKey: OnboardingController.seenKey)
            case .offerTrash(let url): offerTrash(url, settingsCame: imported)
            }
        }
        if !steps.isEmpty, !facts.alreadyImported { me.set(true, forKey: importedKey) }
    }

    private static func running() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Handover.sharksBundleID)
    }

    /// Asks Sharks to quit (it puts the user's own wallpaper back), and never runs alongside it.
    private static func quitSharks() {
        running().forEach { $0.terminate() }
        for _ in 0..<50 where !running().isEmpty { Thread.sleep(forTimeInterval: 0.1) }
        NSApp.activate(ignoringOtherApps: true)
        while !running().isEmpty {
            let alert = NSAlert()
            alert.messageText = "ASCII Sharks is still running"
            alert.informativeText = "Quit it from its 🐟 menu, then click Continue."
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Quit ASCII Animals")
            if alert.runModal() == .alertSecondButtonReturn {
                // A way out for someone who can't quit Sharks; never run alongside it.
                NSApp.terminate(nil)
                exit(0)
            }
            running().forEach { $0.terminate() }
            for _ in 0..<20 where !running().isEmpty { Thread.sleep(forTimeInterval: 0.1) }
        }
    }

    // MARK: While running

    private static var watcher: NSKeyValueObservation?
    private static var quitting = false

    /// From launch on: ASCII Sharks opening (its login item, or out of habit) is asked to quit at once,
    /// and if it won't, the same alert as at launch. KVO on the running list, not the did-launch
    /// notification, which macOS doesn't post for an LSUIElement app like Sharks.
    static func watch() {
        guard enabled, watcher == nil else { return }
        watcher = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { _, change in
            let inserted = change.newValue ?? []
            DispatchQueue.main.async { sharksAppeared(inserted) }
        }
    }

    private static func sharksAppeared(_ inserted: [NSRunningApplication]) {
        guard Handover.shouldQuit(inserted: inserted.map(\.bundleIdentifier), enabled: true, quitting: quitting) else { return }
        quitting = true
        Log.write("hand-over: ASCII Sharks opened; asking it to quit")
        inserted.filter { $0.bundleIdentifier == Handover.sharksBundleID }.forEach { $0.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if !running().isEmpty { quitSharks() }
            quitting = false
        }
    }

    // MARK: Removing Sharks

    private static func offerTrash(_ url: URL, settingsCame: Bool) {
        UserDefaults.standard.set(true, forKey: offeredKey)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ASCII Animals takes over from ASCII Sharks"
        alert.informativeText = (settingsCame ? "Your settings came with you, so you" : "You")
            + " don't need ASCII Sharks any more. Moving it to the Trash also removes its login item and saved files."
            + " If you keep it, ASCII Animals will close it whenever it opens."
        alert.addButton(withTitle: "Keep It")
        alert.addButton(withTitle: "Move ASCII Sharks to the Trash")
        // Not from a disk image or a translocated copy: a login item there would point at the wrong place.
        let bundle = Bundle.main.bundleURL
        let readOnly = (try? bundle.deletingLastPathComponent().resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true
        let canLogin = Handover.canAddLoginItem(bundlePath: bundle.path, onReadOnlyVolume: readOnly)
        alert.showsSuppressionButton = canLogin
        alert.suppressionButton?.title = "Open ASCII Animals at login"
        alert.suppressionButton?.state = .on
        let trash = alert.runModal() == .alertSecondButtonReturn
        if canLogin, alert.suppressionButton?.state == .on {
            do { try LoginItem.set(true) } catch { Log.write("hand-over: could not add login item: \(error)") }
        }
        guard trash else { return }
        if runSharksUninstaller(url), !FileManager.default.fileExists(atPath: url.path) { return }
        // Its uninstaller couldn't finish: at least the app goes.
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            Log.write("hand-over: moved ASCII Sharks to the Trash")
        } catch {
            Log.write("hand-over: could not trash ASCII Sharks: \(error)")
            let failed = NSAlert()
            failed.messageText = "ASCII Sharks couldn't be moved to the Trash"
            failed.informativeText = "You can drag it there from Applications."
            failed.runModal()
        }
    }

    /// Runs Sharks' own scripted uninstall (`ASCIISharks --uninstall --yes`): it puts the user's wallpaper
    /// back, removes its login item (which only Sharks itself can), settings, stills and logs, then
    /// trashes itself and exits. True if it exited on its own with success, within the time allowed.
    private static func runSharksUninstaller(_ app: URL) -> Bool {
        // Its wallpaper memory goes with its settings: keep a copy in case its restore didn't happen.
        if let memory = UserDefaults(suiteName: Handover.sharksBundleID)?.data(forKey: Handover.sharksWallpaperKey) {
            UserDefaults.standard.set(memory, forKey: SystemWallpaper.sharksMemoryCopyKey)
        }
        guard let exe = Bundle(url: app)?.executableURL, FileManager.default.isExecutableFile(atPath: exe.path) else {
            Log.write("hand-over: no ASCII Sharks executable in \(app.path)")
            return false
        }
        let p = Process()
        p.executableURL = exe
        p.arguments = Handover.sharksUninstallArguments
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch {
            Log.write("hand-over: could not run ASCII Sharks' uninstaller: \(error)")
            return false
        }
        if done.wait(timeout: .now() + uninstallTimeout) == .timedOut {
            // It ignores SIGTERM (and has no run loop here to act on it).
            kill(p.processIdentifier, SIGKILL)
            _ = done.wait(timeout: .now() + 2)
            Log.write("hand-over: ASCII Sharks' uninstaller took more than \(Int(uninstallTimeout)) s; stopped it")
            return false
        }
        let said = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        Log.write("hand-over: ASCII Sharks' uninstaller exited \(p.terminationStatus): \(said)")
        return p.terminationStatus == 0
    }
}
