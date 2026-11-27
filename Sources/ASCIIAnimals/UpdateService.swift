import AppKit
import OceanKit
import UserNotifications

/// Asks GitHub for the latest release, at most once a day (and whenever the
/// user asks). Sends nothing about the user: one GET for the latest version,
/// with an ETag so an unchanged answer costs nothing. With automatic updates
/// on, a new version installs itself (SelfUpdater) when the user isn't in the
/// app's windows; otherwise it's one click.
final class UpdateService: NSObject, UNUserNotificationCenterDelegate {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(LatestRelease)
        case installing(LatestRelease)
        case failed(String)
    }

    private(set) var state: State = .idle { didSet { if state != oldValue { onChange?() } } }
    var available: LatestRelease? { if case .available(let r) = state { return r }; return nil }
    var installing: LatestRelease? { if case .installing(let r) = state { return r }; return nil }
    /// Called on the main thread whenever `state` changes.
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var enabled: () -> Bool = { false }
    private var autoInstall: () -> Bool = { false }
    private var inFlight = false
    private static let lastCheckKey = "update.lastCheck"
    private static let etagKey = "update.etag"
    private static let cachedKey = "update.cachedBody"
    private static let notifiedKey = "update.notifiedTag"
    /// An automatic install of this tag failed; don't retry it on our own.
    private static let autoFailedKey = "update.autoFailedTag"
    /// Set just before an automatic install restarts the app, to say so after.
    private static let autoInstalledKey = "update.autoInstalledVersion"

    /// The app bundle can post notifications; a bare debug binary can't.
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }
    /// False in the energy-test copy (`LaunchPlan.startsUpdates`): every way in (start, Check for Updates, a notice,
    /// install) does nothing, so it never checks, prompts, writes an update key, replaces itself or restarts.
    private let allowed: Bool = Launch.plan.startsUpdates
    /// Whether the hourly check is scheduled (the identity probe looks).
    var isStarted: Bool { timer != nil }
    /// Whether a check is under way (the identity probe looks).
    var isChecking: Bool { inFlight }

    func start(enabled: @escaping () -> Bool, autoInstall: @escaping () -> Bool) {
        guard allowed else { return }
        self.enabled = enabled
        self.autoInstall = autoInstall
        if canNotify { UNUserNotificationCenter.current().delegate = self }
        announceAutoInstall()
        // Remember a release found earlier, so the menu shows it right away.
        if let data = defaults.data(forKey: UpdateService.cachedKey) { apply(data, userInitiated: false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard enabled() else { return }
        let last = defaults.object(forKey: UpdateService.lastCheckKey) as? Date
        if UpdatePolicy.shouldCheck(lastCheck: last, now: Date()) {
            checkNow(userInitiated: false)
        } else {
            // A release found earlier may have waited for the user to be done.
            autoInstallIfAllowed()
        }
    }

    func checkNow(userInitiated: Bool) {
        guard allowed, !inFlight, installing == nil else { return }
        inFlight = true
        if userInitiated { state = .checking }
        var req = URLRequest(url: AppInfo.latestAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ASCIIAnimals/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if let etag = defaults.string(forKey: UpdateService.etagKey), defaults.data(forKey: UpdateService.cachedKey) != nil {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.finish(data, response as? HTTPURLResponse, error, userInitiated: userInitiated) }
        }.resume()
    }

    private func finish(_ data: Data?, _ http: HTTPURLResponse?, _ error: Error?, userInitiated: Bool) {
        inFlight = false
        defaults.set(Date(), forKey: UpdateService.lastCheckKey)
        var body = data
        if http?.statusCode == 304 {
            body = defaults.data(forKey: UpdateService.cachedKey)
        } else if http?.statusCode == 200, let data {
            defaults.set(data, forKey: UpdateService.cachedKey)
            if let etag = http?.value(forHTTPHeaderField: "ETag") { defaults.set(etag, forKey: UpdateService.etagKey) }
        } else {
            let why = error?.localizedDescription ?? "GitHub answered \(http?.statusCode ?? 0)."
            Log.write("update check failed: \(why)")
            state = .failed(why)
            if userInitiated { alert(title: "Couldn't check for updates", text: why) }
            return
        }
        guard let body else { return }
        apply(body, userInitiated: userInitiated)
    }

    private func apply(_ data: Data, userInitiated: Bool) {
        if installing != nil { return }
        guard let r = UpdateFeed.parse(data), UpdatePolicy.isNewer(r.version, than: AppInfo.version) else {
            state = .upToDate
            if userInitiated { alert(title: "You're up to date", text: "ASCII Animals \(AppInfo.version) is the latest version.") }
            return
        }
        state = .available(r)
        if userInitiated {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "ASCII Animals \(r.version) is available"
            a.informativeText = "You have \(AppInfo.version). It installs in a few seconds, then ASCII Animals restarts."
            a.addButton(withTitle: "Install and Restart")
            a.addButton(withTitle: "Later")
            if a.runModal() == .alertFirstButtonReturn { install() }
        } else if !autoInstallIfAllowed() {
            notifyOnce(r)
        }
    }

    /// Installs the available release without asking, when the policy allows.
    @discardableResult
    private func autoInstallIfAllowed() -> Bool {
        guard allowed, let r = available else { return false }
        let go = UpdatePolicy.shouldAutoInstall(
            checking: enabled(), autoInstall: autoInstall(),
            installable: r.zipURL != nil && r.zipSHA256 != nil && SelfUpdater.blocker() == nil,
            tag: r.tag, failedTag: defaults.string(forKey: UpdateService.autoFailedKey),
            userBusy: NSApp.isActive)   // an accessory app is active only while its own windows are in use
        if go { install(automatic: true) }
        return go
    }

    /// Downloads and installs the available release, then restarts. Asked for
    /// by the user: when this copy can't replace itself, or the install fails,
    /// says why and offers the DMG. Automatic: fails quietly to the notice.
    func install(automatic: Bool = false) {
        guard allowed, let r = available else { return }
        if !automatic, let why = SelfUpdater.blocker() { return offerDownload(r, why) }
        state = .installing(r)
        Log.write("installing \(r.tag)\(automatic ? " (automatic)" : "")")
        SelfUpdater.install(r) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let app):
                Log.write("installed \(r.tag), restarting")
                if automatic { self.defaults.set(r.version.description, forKey: UpdateService.autoInstalledKey) }
                SelfUpdater.relaunch(app)
            case .failure(let why):
                Log.write("update install failed: \(why)")
                self.state = .available(r)
                if automatic {
                    self.defaults.set(r.tag, forKey: UpdateService.autoFailedKey)
                    self.notifyOnce(r)
                } else {
                    self.offerDownload(r, why.description)
                }
            }
        }
    }

    /// After an automatic update restarts the app: a quiet "now on 2.4".
    private func announceAutoInstall() {
        guard let v = defaults.string(forKey: UpdateService.autoInstalledKey) else { return }
        defaults.removeObject(forKey: UpdateService.autoInstalledKey)
        guard canNotify, AppVersion(v) == AppVersion(AppInfo.version) else { return }
        let content = UNMutableNotificationContent()
        content.title = "ASCII Animals updated to \(v)"
        content.body = "What's new is on GitHub."
        content.userInfo = ["kind": "updated"]
        post(content, id: "updated-\(v)") { _ in }
    }

    private func offerDownload(_ r: LatestRelease, _ why: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Couldn't install ASCII Animals \(r.version)"
        a.informativeText = "\(why)\n\nYour current version is untouched. You can download the update and install it by hand."
        a.addButton(withTitle: "Download")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(r.dmgURL ?? r.pageURL) }
    }

    private func notifyOnce(_ r: LatestRelease) {
        guard canNotify, defaults.string(forKey: UpdateService.notifiedKey) != r.tag else { return }
        let content = UNMutableNotificationContent()
        content.title = "ASCII Animals \(r.version) is available"
        content.body = "Click to install it. ASCII Animals restarts in a few seconds."
        post(content, id: "update-\(r.tag)") { [weak self] in
            if $0 { self?.defaults.set(r.tag, forKey: UpdateService.notifiedKey) }
        }
    }

    /// Asks permission (once; macOS remembers) and posts. `done` gets whether it went, on main.
    private func post(_ content: UNNotificationContent, id: String, done: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            if granted { center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) }
            DispatchQueue.main.async { done(granted) }
        }
    }

    // Clicking "available" installs it; clicking "updated" opens the release notes.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let updated = response.notification.request.content.userInfo["kind"] as? String == "updated"
        DispatchQueue.main.async {
            if updated {
                let v = AppInfo.version
                NSWorkspace.shared.open(AppInfo.releasesURL.appendingPathComponent("tag/v\(v)"))
            } else {
                self.install()
            }
        }
        completionHandler()
    }

    private func alert(title: String, text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
