import AppKit
import OceanKit
import UserNotifications

/// Asks GitHub for the latest release, at most once a day (and whenever the
/// user asks). Sends nothing about the user: one GET for the latest version,
/// with an ETag so an unchanged answer costs nothing.
final class UpdateService: NSObject, UNUserNotificationCenterDelegate {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(LatestRelease)
        case failed(String)
    }

    private(set) var state: State = .idle { didSet { if state != oldValue { onChange?() } } }
    var available: LatestRelease? { if case .available(let r) = state { return r }; return nil }
    /// Called on the main thread whenever `state` changes.
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var enabled: () -> Bool = { false }
    private var inFlight = false
    private static let lastCheckKey = "update.lastCheck"
    private static let etagKey = "update.etag"
    private static let cachedKey = "update.cachedBody"
    private static let notifiedKey = "update.notifiedTag"

    /// The app bundle can post notifications; a bare debug binary can't.
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    func start(enabled: @escaping () -> Bool) {
        self.enabled = enabled
        if canNotify { UNUserNotificationCenter.current().delegate = self }
        // Remember a release found earlier, so the menu shows it right away.
        if let data = defaults.data(forKey: UpdateService.cachedKey) { apply(data, userInitiated: false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard enabled() else { return }
        let last = defaults.object(forKey: UpdateService.lastCheckKey) as? Date
        if UpdatePolicy.shouldCheck(lastCheck: last, now: Date()) { checkNow(userInitiated: false) }
    }

    func checkNow(userInitiated: Bool) {
        guard !inFlight else { return }
        inFlight = true
        if userInitiated { state = .checking }
        var req = URLRequest(url: AppInfo.latestAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ASCIISharks/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
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
        guard let r = UpdateFeed.parse(data), UpdatePolicy.isNewer(r.version, than: AppInfo.version) else {
            state = .upToDate
            if userInitiated { alert(title: "You're up to date", text: "ASCII Sharks \(AppInfo.version) is the latest version.") }
            return
        }
        state = .available(r)
        if userInitiated {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "ASCII Sharks \(r.version) is available"
            a.informativeText = "You have \(AppInfo.version). Download the new version, quit this one from the menu, and drag the new one into Applications."
            a.addButton(withTitle: "Download")
            a.addButton(withTitle: "Later")
            if a.runModal() == .alertFirstButtonReturn { download() }
        } else {
            notifyOnce(r)
        }
    }

    /// Opens the DMG download (or the release page) in the browser.
    func download() {
        if let r = available { NSWorkspace.shared.open(r.dmgURL ?? r.pageURL) } else { NSWorkspace.shared.open(AppInfo.releasesURL) }
    }

    private func notifyOnce(_ r: LatestRelease) {
        guard canNotify, defaults.string(forKey: UpdateService.notifiedKey) != r.tag else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "ASCII Sharks \(r.version) is available"
            content.body = "Click to download the update."
            center.add(UNNotificationRequest(identifier: "update-\(r.tag)", content: content, trigger: nil))
            DispatchQueue.main.async { self?.defaults.set(r.tag, forKey: UpdateService.notifiedKey) }
        }
    }

    // Clicking the notification downloads the update.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.download() }
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
