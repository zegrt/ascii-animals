import AppKit
import Metal
import OceanKit

/// Debug: `--snapshot-identity <txt>` writes which copy this is and what its launch may do (`Launch.plan`), and, in
/// the energy-test copy only, calls every way into the updater, the hand-over, the uninstaller, the system wallpaper
/// and the login item, and checks each did nothing. In any other copy those calls would act, so they are not made.
/// Nothing is drawn, no window opens, no setting is written.
enum IdentityProbe {
    static func run(to url: URL) {
        var lines: [String] = []
        var failed = 0
        func expect(_ ok: Bool, _ what: String) {
            if !ok { failed += 1 }
            lines.append((ok ? "ok    " : "FAIL  ") + what)
        }
        func note(_ what: String) { lines.append("      " + what) }

        let id: String = Bundle.main.bundleIdentifier ?? "(none)"
        let plan: LaunchPlan = Launch.plan
        let domain: String = Bundle.main.bundleIdentifier ?? "named after the executable"
        note("bundle ID \(id), so defaults domain \(domain); executable \(Bundle.main.executableURL?.lastPathComponent ?? "?")")
        note("identity \(plan.identity); greeting \(plan.greeting); transient settings \(plan.transientSettings);"
             + " built-in display only \(plan.builtInDisplayOnly); frame-rate log \(plan.reportsFrameRate)")
        note("updates \(plan.startsUpdates); hand-over \(plan.runsHandover); uninstall \(plan.offersUninstall);"
             + " system wallpaper \(plan.matchesSystemWallpaper); login item \(plan.changesLoginItem)")
        note("log \(Log.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
        note("crash marker \(CrashMarker.file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")

        guard plan.identity.isEnergyTest else {
            note("not the energy-test copy: its entry points act here, so none is called")
            finish(lines, failed, url)
            return
        }

        // Identity and folders: nothing shared with the app people install.
        expect(id == AppIdentity.energyTestBundleID && id.lowercased() != Handover.animalsBundleID.lowercased(),
               "its own bundle ID and defaults domain (\(id))")
        expect(Bundle.main.executableURL?.lastPathComponent == AppIdentity.energyTestExecutable, "its own executable name")
        let ownFolders: Bool = Log.folder.lastPathComponent == "ASCII Animals Energy Test"
            && CrashMarker.folder.lastPathComponent == "ASCII Animals Energy Test"
        expect(ownFolders, "its own log folder and crash marker")
        let allOff: Bool = !plan.startsUpdates && !plan.runsHandover && !plan.offersUninstall
            && !plan.matchesSystemWallpaper && !plan.changesLoginItem
        expect(allOff, "the plan: no updates, hand-over, uninstall, system wallpaper or login item")
        expect(plan.greeting != .asSaved, "no welcome or card from saved flags (greeting \(plan.greeting))")

        // The updater: every way in does nothing.
        let updates = UpdateService()
        updates.start(enabled: { true }, autoInstall: { true })
        expect(!updates.isStarted, "updates.start: no check scheduled")
        updates.checkNow(userInitiated: false)
        expect(!updates.isChecking && updates.state == .idle, "updates.checkNow: no request, no state")
        updates.install()
        expect(updates.state == .idle, "updates.install: nothing")
        expect(SelfUpdater.blocker() != nil, "SelfUpdater.blocker: refuses (\(SelfUpdater.blocker() ?? "nil"))")
        // A release with no download: past the identity guard it would fail for another reason, so the message says
        // which guard answered. Nothing is fetched either way.
        let feed: Data = Data(#"{"tag_name":"v99.0.0","html_url":"https://github.com/zegrt/ascii-animals/releases"}"#.utf8)
        var refusal: String = ""
        if let release = UpdateFeed.parse(feed) {
            SelfUpdater.install(release) { result in if case .failure(let why) = result { refusal = why.description } }
            let until = Date().addingTimeInterval(2)
            while refusal.isEmpty && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        expect(refusal.contains("energy-test"), "SelfUpdater.install: refused by the identity (\(refusal))")

        // The hand-over and its watcher.
        expect(!SharksHandover.enabled, "the Sharks hand-over: off")
        SharksHandover.watch()
        expect(!SharksHandover.isWatching, "the Sharks watcher: never started")

        // The uninstaller: no question asked, nothing removed.
        expect(!Uninstaller.confirm(), "Uninstaller.confirm: no without asking")
        let problems: [String] = Uninstaller.run(app: nil)
        let bundleThere: Bool = FileManager.default.fileExists(atPath: Bundle.main.bundleURL.path)
        expect(problems == ["the energy-test copy has no uninstaller"] && bundleThere, "Uninstaller.run: refused, the bundle stays")

        // The system wallpaper: never made, so no stills and no wallpaperMemory.v1.
        if let device = MTLCreateSystemDefaultDevice(), let renderer = try? OceanRenderer(device: device) {
            expect(SystemWallpaper(renderer: renderer) == nil, "SystemWallpaper: never made")
        } else {
            expect(false, "SystemWallpaper: no Metal device to try")
        }
        let memory: Any? = UserDefaults.standard.object(forKey: SystemWallpaper.memoryKey)
        expect(memory == nil, "wallpaperMemory.v1: absent from this copy's domain")

        // The login item.
        var loginRefused = false
        do { try LoginItem.set(true) } catch { loginRefused = error is LoginItem.Refused }
        expect(loginRefused, "LoginItem.set: refused")

        // The menu: none of those items, and it says which copy it is.
        let menu: [String] = StatusMenu.outline()
        let text: String = menu.joined(separator: "\n")
        let gone: Bool = !text.contains("Check for Updates") && !text.contains("Uninstall") && !text.contains("Open at Login")
            && !text.contains("Restore Original Wallpaper")
        expect(gone, "the menu: no updates, uninstall, login item or restore-wallpaper items")
        expect(text.contains("energy test copy"), "the menu: names the energy-test copy")

        // The preview's settings: in memory (a preview launch) or this copy's own domain (a measurement).
        let store: SettingsStore = AppDelegate().store
        expect(store.persists == !plan.transientSettings,
               plan.transientSettings ? "preview: settings held in memory, never saved" : "measurement: settings saved in this copy's domain only")

        let all: [NSScreen] = NSScreen.screens
        let drawn: [NSScreen] = OceanDirector.drawnScreens(all, builtInOnly: plan.builtInDisplayOnly)
        note("screens: \(all.count) attached, \(drawn.count) drawn")
        if plan.builtInDisplayOnly {
            expect(drawn.allSatisfy { CGDisplayIsBuiltin($0.displayID) != 0 }, "built-in display only: no other screen drawn")
        }
        finish(lines, failed, url)
    }

    private static func finish(_ lines: [String], _ failed: Int, _ url: URL) {
        var out = lines
        out.append("\(lines.filter { !$0.hasPrefix("      ") }.count) probes, \(failed) failed")
        try? (out.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        print(out.joined(separator: "\n"))
    }
}
