import AppKit
import OceanKit
import UserNotifications

/// Asks GitHub for the latest release, at most once a day (and whenever the
/// user asks). Sends nothing about the user: one GET for the latest version,
/// with an ETag so an unchanged answer costs nothing. With automatic updates
/// on, a new version installs itself (SelfUpdater) when the user isn't in the
/// app's windows; otherwise it's one click. The decisions are `UpdateEngine`'s
/// (OceanKit, checked); this is its host: the network, the disk, the screen.
final class UpdateService: NSObject, UNUserNotificationCenterDelegate, UpdateHost {
    typealias State = UpdateState

    var state: State { engine?.state ?? .idle }
    var available: LatestRelease? { engine?.available }
    var installing: LatestRelease? { engine?.installing }
    /// Called on the main thread whenever `state` changes.
    var onChange: (() -> Void)? {
        didSet { engine?.onChange = onChange }
    }

    private var engine: UpdateEngine?
    private var timer: Timer?
    private var firstLook: Timer?
    private var enabled: () -> Bool = { false }
    private var autoInstallSetting: () -> Bool = { false }

    /// False in the energy-test copy (`LaunchPlan.startsUpdates`): every way in (start, Check for Updates, a notice,
    /// install) does nothing, so it never checks, prompts, writes an update key, replaces itself or restarts.
    private let allowed: Bool = Launch.plan.startsUpdates
    /// Whether the hourly check is scheduled (the identity probe looks).
    var isStarted: Bool { timer != nil }
    /// Whether a check is under way (the identity probe looks).
    var isChecking: Bool { engine?.inFlight ?? false }

    func start(enabled: @escaping () -> Bool, autoInstall: @escaping () -> Bool) {
        guard allowed else { return }
        self.enabled = enabled
        self.autoInstallSetting = autoInstall
        if canNotify { UNUserNotificationCenter.current().delegate = self }
        let e = UpdateEngine(store: UserDefaults.standard, host: self)
        e.onChange = onChange
        engine = e
        e.start()
    }

    func checkNow(userInitiated: Bool) {
        guard allowed else { return }
        engine?.check(userInitiated: userInitiated)
    }

    func install() {
        guard allowed else { return }
        engine?.install()
    }

    // MARK: UpdateHost

    var now: Date { Date() }
    var checking: Bool { enabled() }
    var autoInstall: Bool { autoInstallSetting() }
    var surfaces: UpdateSurfaces { UpdateSurfaces(appActive: NSApp.isActive) }
    var runningVersion: String { AppInfo.version }
    var installBlocker: String? { SelfUpdater.blocker() }
    /// The app bundle can post notifications; a bare debug binary can't.
    var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    func setSchedule(_ on: Bool) {
        if !on {
            firstLook?.invalidate(); firstLook = nil
            timer?.invalidate(); timer = nil
            return
        }
        guard timer == nil else { return }
        firstLook = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.firstLook = nil
            self?.engine?.tick()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.engine?.tick() }
    }

    func fetchFeed(etag: String?, done: @escaping (FeedResponse) -> Void) {
        var req = URLRequest(url: AppInfo.latestAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ASCIIAnimals/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        URLSession.shared.dataTask(with: req) { data, response, error in
            let http = response as? HTTPURLResponse
            let answer = FeedResponse(status: http?.statusCode, body: data, etag: http?.value(forHTTPHeaderField: "ETag"),
                                      error: error?.localizedDescription)
            DispatchQueue.main.async { done(answer) }
        }.resume()
    }

    func stage(_ release: LatestRelease, done: @escaping (Result<StagedUpdate, UpdateFailure>) -> Void) {
        SelfUpdater.stage(release, done: done)
    }

    func commit(_ staged: StagedUpdate) -> Result<URL, UpdateFailure> { SelfUpdater.commit(staged) }
    func discard(_ staged: StagedUpdate) { SelfUpdater.discard(staged) }
    func startNewCopy(_ app: URL) -> Bool { SelfUpdater.scheduleRelaunch(app) }
    func quit() { NSApp.terminate(nil) }
    func log(_ line: String) { Log.write(line) }

    func notify(id: String, title: String, body: String, kind: String, done: @escaping (Bool) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["kind": kind]
        let center = UNUserNotificationCenter.current()
        // Asks permission (once; macOS remembers) and posts.
        center.requestAuthorization(options: [.alert]) { granted, _ in
            if granted { center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) }
            DispatchQueue.main.async { done(granted) }
        }
    }

    func offerInstall(_ r: LatestRelease) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "ASCII Animals \(r.version) is available"
        a.informativeText = "You have \(AppInfo.version). It installs in a few seconds, then ASCII Animals restarts."
        a.addButton(withTitle: "Install and Restart")
        a.addButton(withTitle: "Later")
        return a.runModal() == .alertFirstButtonReturn
    }

    func tell(_ message: UpdateMessage) {
        switch message {
        case .upToDate(let v):
            alert(title: "You're up to date", text: "ASCII Animals \(v) is the latest version.")
        case .couldNotCheck(let why):
            alert(title: "Couldn't check for updates", text: why)
        case .couldNotInstall(let r, let why):
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Couldn't install ASCII Animals \(r.version)"
            a.informativeText = "\(why)\n\nYour current version is untouched. You can download the update and install it by hand."
            a.addButton(withTitle: "Download")
            a.addButton(withTitle: "Cancel")
            if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(r.dmgURL ?? r.pageURL) }
        case .restartFailed(let r):
            alert(title: "ASCII Animals \(r.version) is installed",
                  text: "It couldn't restart by itself, so this copy keeps running. Quit ASCII Animals and open it again to finish.")
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

/// UserDefaults is the updater's store.
extension UserDefaults: UpdateStore {}
