import Foundation

/// A dotted version like "2.1" or "v2.10.1". Missing parts count as zero.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]
    public init?(_ s: String) {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        let raw = t.split(separator: ".", omittingEmptySubsequences: false)
        guard !t.isEmpty, raw.count <= 4 else { return nil }
        var parts: [Int] = []
        for r in raw {
            guard let n = Int(r), n >= 0 else { return nil }
            parts.append(n)
        }
        // Trailing zeros don't matter: 2.1 == 2.1.0.
        while parts.count > 1 && parts.last == 0 { parts.removeLast() }
        self.parts = parts
    }
    public var description: String { parts.map(String.init).joined(separator: ".") }
    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
    public static func == (a: AppVersion, b: AppVersion) -> Bool { a.parts == b.parts }
}

/// The newest published release.
public struct LatestRelease: Equatable, Sendable {
    public var version: AppVersion
    public var tag: String
    public var pageURL: URL
    /// For people: the drag-to-Applications disk image.
    public var dmgURL: URL?
    /// For the app updating itself: the zipped app and its SHA-256 as GitHub
    /// reports it (lowercase hex). A disk image won't do: macOS doesn't let an
    /// app read a mounted image without asking.
    public var zipURL: URL?
    public var zipSHA256: String?
    public var notes: String
    public static func == (a: LatestRelease, b: LatestRelease) -> Bool { a.tag == b.tag && a.version == b.version }
}

public enum UpdateFeed {
    /// GitHub `releases/latest` JSON.
    public static func parse(_ data: Data) -> LatestRelease? {
        struct Asset: Decodable { let name: String; let browser_download_url: URL; let digest: String? }
        struct Release: Decodable {
            let tag_name: String
            let html_url: URL
            let body: String?
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]?
        }
        guard let r = try? JSONDecoder().decode(Release.self, from: data),
              r.draft != true, r.prerelease != true,
              let v = AppVersion(r.tag_name) else { return nil }
        let dmg = r.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }
        let zip = r.assets?.first { $0.name.lowercased().hasSuffix(".zip") }
        return LatestRelease(version: v, tag: r.tag_name, pageURL: r.html_url, dmgURL: dmg?.browser_download_url,
                             zipURL: zip?.browser_download_url, zipSHA256: zip?.digest.flatMap(sha256), notes: r.body ?? "")
    }

    /// "sha256:<64 hex>" → the hex, lowercased; anything else → nil.
    static func sha256(_ digest: String) -> String? {
        let prefix = "sha256:"
        guard digest.lowercased().hasPrefix(prefix) else { return nil }
        let hex = digest.dropFirst(prefix.count).lowercased()
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return String(hex)
    }
}

/// The rules for installing an update in place. The app does the work; these
/// are the decisions, kept here so they're checked.
public enum SelfUpdate {
    /// Why a copy at `bundlePath` can't replace itself, or nil when it can.
    /// (Whether its folder is writable is the app's to find out.)
    public static func blocker(bundlePath: String) -> String? {
        guard bundlePath.hasSuffix(".app") else { return "This isn't an installed copy of the app." }
        // macOS runs a quarantined app from a random read-only copy until it's moved.
        if bundlePath.contains("/AppTranslocation/") {
            return "macOS is running ASCII Animals from a temporary copy. Move it into Applications, open it from there, and try again."
        }
        return nil
    }

    /// Only this repo's release downloads, over HTTPS.
    public static func isTrustedDownload(_ url: URL, repoPath: String) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "github.com"
            && url.path.hasPrefix("/\(repoPath)/releases/download/")
    }

    /// What's wrong with the app found in the update, or nil when it's the
    /// expected app at exactly the expected version.
    public static func candidateProblem(bundleID: String?, version: String?, expectedID: String, expectedVersion: AppVersion) -> String? {
        guard bundleID == expectedID else { return "The download contains a different app (\(bundleID ?? "no identifier"))." }
        guard let v = version.flatMap(AppVersion.init), v == expectedVersion else {
            return "The download is version \(version ?? "unknown"), not \(expectedVersion)."
        }
        return nil
    }
}

public enum UpdatePolicy {
    public static let interval: TimeInterval = 20 * 3600
    public static func shouldCheck(lastCheck: Date?, now: Date) -> Bool {
        guard let last = lastCheck else { return true }
        // A last check in the future means the clock moved; check again.
        return last > now || now.timeIntervalSince(last) >= interval
    }

    /// Whether to install `tag` now without asking: automatic updates are on
    /// (and checking), the release can be installed from inside the app, it
    /// hasn't already failed once, and the user isn't busy in the app's windows.
    public static func shouldAutoInstall(checking: Bool, autoInstall: Bool, installable: Bool,
                                         tag: String, failedTag: String?, userBusy: Bool) -> Bool {
        checking && autoInstall && installable && tag != failedTag && !userBusy
    }

    /// Only a real version newer than the running one counts; dev builds never nag.
    public static func isNewer(_ latest: AppVersion, than running: String) -> Bool {
        guard let current = AppVersion(running) else { return false }
        return current < latest
    }
}

/// What a problem report says about this Mac and app. No names, no paths.
public struct DiagnosticFacts: Sendable {
    public var appVersion: String
    public var macOS: String
    public var model: String
    public var displays: [String]
    public var power: String
    public var mode: String
    public var settingsJSON: String
    public var crashedLastTime: Bool
    public var logTail: [String]
    /// Each display's size, scale and refresh rate, without its name ("2560x1440 @2x 60 Hz").
    public var displaySizes: [String]
    public init(appVersion: String, macOS: String, model: String, displays: [String], power: String, mode: String,
                settingsJSON: String, crashedLastTime: Bool, logTail: [String], displaySizes: [String] = []) {
        self.appVersion = appVersion; self.macOS = macOS; self.model = model; self.displays = displays
        self.power = power; self.mode = mode; self.settingsJSON = settingsJSON; self.crashedLastTime = crashedLastTime
        self.logTail = logTail; self.displaySizes = displaySizes
    }
}

extension DiagnosticFacts {
    /// The `mode` line: which habitat, and what it is doing. "Web, live(fps: 30), 1 screen(s), 1 scene(s)".
    public static func mode(habitat: HabitatKind, run: RunMode?, screens: Int, scenes: Int, failure: String?) -> String {
        if let failure { return "\(habitat.title), failed to start: \(failure)" }
        guard let run else { return "\(habitat.title), not running" }
        return "\(habitat.title), \(run), \(screens) screen(s), \(scenes) scene(s)"
    }
}

public enum IssueReport {
    /// Markdown for a GitHub issue. The home folder becomes `~` and the user's
    /// name is removed everywhere, so nothing personal leaves the Mac.
    public static func body(_ d: DiagnosticFacts, homePath: String, userName: String) -> String {
        var lines = [
            "**What happened**",
            "",
            "<!-- Describe what you saw and what you expected. -->",
            "",
            "**Diagnostics**",
            "",
            "| | |",
            "|---|---|",
            "| App | \(d.appVersion) |",
            "| macOS | \(d.macOS) |",
            "| Mac | \(d.model) |",
            "| Displays | \(d.displays.joined(separator: "<br>")) |",
            "| Power | \(d.power) |",
            "| Habitat | \(d.mode) |",
        ]
        if d.crashedLastTime { lines.append("| Note | Quit unexpectedly last time |") }
        lines += ["", "<details><summary>Settings</summary>", "", "```json", d.settingsJSON, "```", "</details>"]
        if !d.logTail.isEmpty {
            lines += ["", "<details><summary>Recent log</summary>", "", "```"] + d.logTail + ["```", "</details>"]
        }
        return scrub(lines.joined(separator: "\n"), homePath: homePath, userName: userName)
    }

    static func scrub(_ text: String, homePath: String, userName: String) -> String {
        var t = text
        if !homePath.isEmpty { t = t.replacingOccurrences(of: homePath, with: "~") }
        if userName.count >= 2 { t = t.replacingOccurrences(of: userName, with: "<user>", options: .caseInsensitive) }
        return t
    }

    /// A "new issue" link prefilled with `title` and `body`, at most `limit`
    /// characters: the oldest log lines go first, the facts stay.
    public static func url(base: URL, title: String, body: String, limit: Int = 6000) -> URL {
        func make(_ b: String) -> URL {
            var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            c.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: b)]
            return c.url!
        }
        var lines = body.components(separatedBy: "\n")
        var u = make(body)
        // Drop log lines (between the log fence) oldest first, then cut hard.
        while u.absoluteString.count > limit {
            if let open = lines.firstIndex(of: "<details><summary>Recent log</summary>"),
               let fence = lines[open...].firstIndex(of: "```"), fence + 1 < lines.count, lines[fence + 1] != "```" {
                lines.remove(at: fence + 1)
            } else if lines.count > 1 {
                lines.removeLast()
            } else {
                break
            }
            u = make(lines.joined(separator: "\n"))
        }
        return u
    }
}

extension IssueReport {
    /// The text that goes into the GitHub form (`base`, `title`) from Report a Problem. `includeLog`: the person chose
    /// to add log lines.
    public static func form(_ d: DiagnosticFacts, includeLog: Bool, homePath: String, userName: String, fullName: String,
                            base: URL, title: String) -> String {
        body(d, homePath: homePath, userName: userName)
    }
}

// MARK: - The updater's decisions, behind a seam the checks drive with fakes (the app's UpdateService is the host).

/// Where the updater is.
public enum UpdateState: Equatable, Sendable {
    case idle, checking, upToDate
    case available(LatestRelease)
    case installing(LatestRelease)
    case failed(String)
}

/// What one request for the feed got back: the HTTP status (nil when nothing answered), the body, the ETag and the
/// transport error, if any.
public struct FeedResponse: Sendable {
    public var status: Int?
    public var body: Data?
    public var etag: String?
    public var error: String?
    public init(status: Int?, body: Data? = nil, etag: String? = nil, error: String? = nil) {
        self.status = status; self.body = body; self.etag = etag; self.error = error
    }
}

public struct UpdateFailure: Error, Equatable, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ d: String) { description = d }
}

/// A release downloaded and checked, ready to swap in. `app` is the checked copy; `folder` holds the download.
public struct StagedUpdate: Equatable, Sendable {
    public var release: LatestRelease
    public var app: URL
    public var folder: URL
    public init(release: LatestRelease, app: URL, folder: URL) { self.release = release; self.app = app; self.folder = folder }
}

/// What the person has in front of them from this app, read when a decision is made.
public struct UpdateSurfaces: Equatable, Sendable {
    /// The app is frontmost.
    public var appActive: Bool
    /// One of the app's own windows is up (Settings focused or not, About, the welcome, the card, an alert).
    public var windowUp: Bool
    /// One of the app's menus is open.
    public var menuOpen: Bool
    public init(appActive: Bool = false, windowUp: Bool = false, menuOpen: Bool = false) {
        self.appActive = appActive; self.windowUp = windowUp; self.menuOpen = menuOpen
    }
}

/// What the updater tells the person directly.
public enum UpdateMessage: Equatable, Sendable {
    case upToDate(version: String)
    case couldNotCheck(String)
    /// Couldn't install the release: why; the download is offered.
    case couldNotInstall(LatestRelease, String)
    /// The release is installed but the new copy couldn't be started: the old copy keeps running.
    case restartFailed(LatestRelease)
}

/// Key-value storage (UserDefaults in the app, a dictionary in the checks).
public protocol UpdateStore: AnyObject {
    func data(forKey key: String) -> Data?
    func string(forKey key: String) -> String?
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

/// Everything outside the decisions: the clock, the preferences, the screen, the network, the disk, notifications and
/// the person. The app answers with the real thing, the checks with fakes. Called on one thread (main in the app).
public protocol UpdateHost: AnyObject {
    var now: Date { get }
    /// "Check for updates", read fresh each time.
    var checking: Bool { get }
    /// "Install updates automatically", read fresh each time.
    var autoInstall: Bool { get }
    var surfaces: UpdateSurfaces { get }
    var runningVersion: String { get }
    /// Why this copy can't replace itself, or nil when it can.
    var installBlocker: String? { get }
    var canNotify: Bool { get }
    /// Arms (true) or stops (false) the update timers: a first look soon, then hourly `tick()`s.
    func setSchedule(_ on: Bool)
    func fetchFeed(etag: String?, done: @escaping (FeedResponse) -> Void)
    /// Downloads and checks `release` without touching the installed app.
    func stage(_ release: LatestRelease, done: @escaping (Result<StagedUpdate, UpdateFailure>) -> Void)
    /// Swaps the staged copy in (one rename); the installed app is untouched on failure.
    func commit(_ staged: StagedUpdate) -> Result<URL, UpdateFailure>
    func discard(_ staged: StagedUpdate)
    /// Schedules `app` to open once this copy has quit; false when that couldn't be started.
    func startNewCopy(_ app: URL) -> Bool
    func quit()
    /// Posts a notification; `done` gets whether it went.
    func notify(id: String, title: String, body: String, kind: String, done: @escaping (Bool) -> Void)
    /// Asks whether to install `release` now (after the person checked).
    func offerInstall(_ release: LatestRelease) -> Bool
    func tell(_ message: UpdateMessage)
    func log(_ line: String)
}

/// The updater's decisions. The app's UpdateService wires them to the real world.
public final class UpdateEngine {
    public static let lastCheckKey = "update.lastCheck"
    public static let etagKey = "update.etag"
    public static let cachedKey = "update.cachedBody"
    public static let notifiedKey = "update.notifiedTag"
    /// An automatic install of this tag failed; don't retry it on our own.
    public static let autoFailedKey = "update.autoFailedTag"
    /// Set just before an automatic install restarts the app, to say so after.
    public static let autoInstalledKey = "update.autoInstalledVersion"

    public private(set) var state: UpdateState = .idle { didSet { if state != oldValue { onChange?() } } }
    public var available: LatestRelease? { if case .available(let r) = state { return r }; return nil }
    public var installing: LatestRelease? { if case .installing(let r) = state { return r }; return nil }
    public private(set) var inFlight = false
    public var onChange: (() -> Void)?

    private let store: UpdateStore
    private unowned let host: UpdateHost

    public init(store: UpdateStore, host: UpdateHost) {
        self.store = store
        self.host = host
    }

    /// At launch: says an automatic update happened, shows a release found earlier and arms the timers.
    public func start() {
        announceAutoInstall()
        if let data = store.data(forKey: Self.cachedKey) { apply(data, userInitiated: false) }
        host.setSchedule(true)
    }

    /// A setting changed.
    public func settingsChanged() {}

    /// The hourly tick: checks when due, else installs a release that waited.
    public func tick() {
        guard host.checking else { return }
        let last = store.object(forKey: Self.lastCheckKey) as? Date
        if UpdatePolicy.shouldCheck(lastCheck: last, now: host.now) {
            check(userInitiated: false)
        } else {
            autoInstallIfAllowed()
        }
    }

    public func check(userInitiated: Bool) {
        guard !inFlight, installing == nil else { return }
        inFlight = true
        if userInitiated { state = .checking }
        let etag: String? = store.data(forKey: Self.cachedKey) != nil ? store.string(forKey: Self.etagKey) : nil
        host.fetchFeed(etag: etag) { [weak self] response in self?.finish(response, userInitiated: userInitiated) }
    }

    private func finish(_ response: FeedResponse, userInitiated: Bool) {
        inFlight = false
        store.set(host.now, forKey: Self.lastCheckKey)
        var body = response.body
        if response.status == 304 {
            body = store.data(forKey: Self.cachedKey)
        } else if response.status == 200, let data = response.body {
            store.set(data, forKey: Self.cachedKey)
            if let etag = response.etag { store.set(etag, forKey: Self.etagKey) }
        } else {
            let why: String = response.error ?? "GitHub answered \(response.status ?? 0)."
            host.log("update check failed: \(why)")
            state = .failed(why)
            if userInitiated { host.tell(.couldNotCheck(why)) }
            return
        }
        guard let body else { return }
        apply(body, userInitiated: userInitiated)
    }

    private func apply(_ data: Data, userInitiated: Bool) {
        if installing != nil { return }
        guard let r = UpdateFeed.parse(data), UpdatePolicy.isNewer(r.version, than: host.runningVersion) else {
            state = .upToDate
            if userInitiated { host.tell(.upToDate(version: host.runningVersion)) }
            return
        }
        state = .available(r)
        if userInitiated {
            if host.offerInstall(r) { install() }
        } else if !autoInstallIfAllowed() {
            notifyOnce(r)
        }
    }

    /// Installs the available release without asking, when the policy allows.
    @discardableResult
    private func autoInstallIfAllowed() -> Bool {
        guard let r = available else { return false }
        let go: Bool = UpdatePolicy.shouldAutoInstall(
            checking: host.checking, autoInstall: host.autoInstall,
            installable: r.zipURL != nil && r.zipSHA256 != nil && host.installBlocker == nil,
            tag: r.tag, failedTag: store.string(forKey: Self.autoFailedKey),
            userBusy: host.surfaces.appActive)
        if go { install(automatic: true) }
        return go
    }

    /// Downloads and installs the available release, then restarts. Asked for by the person: when this copy can't
    /// replace itself, or the install fails, says why and offers the download. Automatic: fails quietly to the notice.
    public func install(automatic: Bool = false) {
        guard let r = available else { return }
        if !automatic, let why = host.installBlocker { return host.tell(.couldNotInstall(r, why)) }
        state = .installing(r)
        host.log("installing \(r.tag)\(automatic ? " (automatic)" : "")")
        host.stage(r) { [weak self] staged in
            guard let self else { return }
            switch staged.flatMap({ s in self.host.commit(s) }) {
            case .success(let app):
                self.host.log("installed \(r.tag), restarting")
                if automatic { self.store.set(r.version.description, forKey: Self.autoInstalledKey) }
                _ = self.host.startNewCopy(app)
                self.host.quit()
            case .failure(let why):
                self.host.log("update install failed: \(why)")
                self.state = .available(r)
                if automatic {
                    self.store.set(r.tag, forKey: Self.autoFailedKey)
                    self.notifyOnce(r)
                } else {
                    self.host.tell(.couldNotInstall(r, why.description))
                }
            }
        }
    }

    /// After an automatic update restarts the app: a quiet "now on 2.4".
    private func announceAutoInstall() {
        guard let v = store.string(forKey: Self.autoInstalledKey) else { return }
        store.removeObject(forKey: Self.autoInstalledKey)
        guard host.canNotify, AppVersion(v) == AppVersion(host.runningVersion) else { return }
        host.notify(id: "updated-\(v)", title: "ASCII Animals updated to \(v)", body: "What's new is on GitHub.",
                    kind: "updated") { _ in }
    }

    private func notifyOnce(_ r: LatestRelease) {
        guard host.canNotify, store.string(forKey: Self.notifiedKey) != r.tag else { return }
        host.notify(id: "update-\(r.tag)", title: "ASCII Animals \(r.version) is available",
                    body: "Click to install it. ASCII Animals restarts in a few seconds.", kind: "available") { [weak self] sent in
            if sent { self?.store.set(r.tag, forKey: Self.notifiedKey) }
        }
    }
}
