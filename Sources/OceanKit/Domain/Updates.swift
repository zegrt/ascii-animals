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
    /// The same release with the same download: its link and the checksum it's checked against match too.
    public func sameDownload(as other: LatestRelease) -> Bool {
        self == other && zipURL == other.zipURL && zipSHA256 == other.zipSHA256
    }
}

public enum UpdateFeed {
    /// What an answer from the feed says.
    public enum Reading: Equatable, Sendable {
        /// A published release (newer or not).
        case release(LatestRelease)
        /// A readable answer with nothing to install (a draft, a pre-release).
        case nothing
        /// Not a release at all (an error page, a rate-limit answer, cut-off JSON), or a published release whose tag
        /// isn't a version or whose page isn't an absolute URL: the check failed.
        case garbled
    }

    /// GitHub `releases/latest` JSON.
    public static func parse(_ data: Data) -> LatestRelease? {
        if case .release(let r) = read(data) { return r }
        return nil
    }

    public static func read(_ data: Data) -> Reading {
        struct Asset: Decodable { let name: String; let browser_download_url: URL; let digest: String? }
        struct Release: Decodable {
            let tag_name: String
            let html_url: URL
            let body: String?
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]?
        }
        guard let r = try? JSONDecoder().decode(Release.self, from: data) else { return .garbled }
        guard r.draft != true, r.prerelease != true else { return .nothing }
        guard let v = AppVersion(r.tag_name), r.html_url.scheme != nil, r.html_url.host != nil else { return .garbled }
        let dmg = r.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }
        let zip = r.assets?.first { $0.name.lowercased().hasSuffix(".zip") }
        return .release(LatestRelease(version: v, tag: r.tag_name, pageURL: r.html_url, dmgURL: dmg?.browser_download_url,
                                      zipURL: zip?.browser_download_url, zipSHA256: zip?.digest.flatMap(sha256),
                                      notes: r.body ?? ""))
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
    /// The recent log, oldest first: whole entries (`LogEntries`), each its stamped line and the lines after it.
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
    public static func body(_ d: DiagnosticFacts, homePath: String, userName: String, fullName: String = "") -> String {
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
            let entries: [String] = d.logTail.map { (e: String) -> String in
                scrub(e, homePath: homePath, userName: userName, fullName: fullName, wholeEntry: true)
            }
            lines += ["", "<details><summary>Recent log</summary>", "", "```"] + entries + ["```", "</details>"]
        }
        return scrub(lines.joined(separator: "\n"), homePath: homePath, userName: userName, fullName: fullName)
    }

    /// The home folder becomes `~`; the account's short and full names, other accounts' folders and volume names go.
    /// `wholeEntry`: `text` is one log entry, scrubbed as a unit: an error keeps only its domain and code and the rest
    /// of the entry goes (its message, its details, every line after), and a volume name runs to the next `/` even
    /// across the entry's lines.
    static func scrub(_ text: String, homePath: String, userName: String, fullName: String = "",
                      wholeEntry: Bool = false) -> String {
        var t = text
        if !homePath.isEmpty {
            t = t.replacingOccurrences(of: homePath, with: "~")
            // As a file URL writes it ("/Users/jane%20doe").
            if let encoded = homePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), encoded != homePath {
                t = t.replacingOccurrences(of: encoded, with: "~")
            }
        }
        // An error keeps only its domain and code: its message and details can name files, folders and volumes.
        let errorRest: String = wholeEntry ? #"[\s\S]*"# : ".*"
        t = t.replacingOccurrences(of: #"(Error Domain=\S+ Code=-?\d+)"# + errorRest, with: "$1", options: .regularExpression)
        if fullName.count >= 2 { t = t.replacingOccurrences(of: fullName, with: "<user>", options: .caseInsensitive) }
        if userName.count >= 2 { t = t.replacingOccurrences(of: userName, with: "<user>", options: .caseInsensitive) }
        t = t.replacingOccurrences(of: #"/Users/[^/\s]+"#, with: "/Users/<user>", options: .regularExpression)
        let volume: String = wholeEntry ? #"/Volumes/[^/]+"# : #"/Volumes/[^/\n]+"#
        t = t.replacingOccurrences(of: volume, with: "/Volumes/<volume>", options: .regularExpression)
        return t
    }

    /// A "new issue" link prefilled with `title` and `body`, at most `limit`
    /// characters: the oldest log lines go first, the facts stay.
    public static func url(base: URL, title: String, body: String, limit: Int = 6000) -> URL {
        make(base, title, fitted(base: base, title: title, body: body, limit: limit))
    }

    private static func make(_ base: URL, _ title: String, _ body: String) -> URL {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        // Foundation leaves "+" as is, and a web form reads it as a space.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }

    /// `body` cut to fit the link: log lines (inside the log's fence) oldest first, then lines from the end.
    static func fitted(base: URL, title: String, body: String, limit: Int = 6000) -> String {
        var lines = body.components(separatedBy: "\n")
        var b = body
        while make(base, title, b).absoluteString.count > limit {
            if let open = lines.firstIndex(of: "<details><summary>Recent log</summary>"),
               let fence = lines[open...].firstIndex(where: { $0.hasPrefix("```") }), fence + 1 < lines.count,
               lines[fence + 1] != lines[fence] {
                lines.remove(at: fence + 1)
            } else if lines.count > 1 {
                lines.removeLast()
            } else {
                break
            }
            b = lines.joined(separator: "\n")
        }
        return b
    }
}

extension IssueReport {
    /// The text that goes into the GitHub form (`base`, `title`) from Report a Problem, exactly: the person reviews
    /// this before anything leaves the Mac, and it already fits the link, so nothing is cut after. Only the app version,
    /// macOS, the displays' sizes and the settings; the recent log only when the person chose it (`includeLog`): whole
    /// entries only, each scrubbed as a unit (`scrub(wholeEntry:)`), and the oldest entries go first to fit the link.
    public static func form(_ d: DiagnosticFacts, includeLog: Bool, homePath: String, userName: String, fullName: String,
                            base: URL, title: String, limit: Int = 6000) -> String {
        let displays: String = "\(d.displaySizes.count): " + d.displaySizes.joined(separator: "<br>")
        let head: [String] = [
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
            "| Displays | \(displays) |",
            "",
            "<details><summary>Settings</summary>", "", "```json", d.settingsJSON, "```", "</details>",
        ]
        let entries: [String] = includeLog ? d.logTail.map { (e: String) -> String in
            scrub(e, homePath: homePath, userName: userName, fullName: fullName, wholeEntry: true)
        } : []
        var first: Int = 0
        while true {
            let kept: ArraySlice<String> = entries[first...]
            var lines: [String] = head
            if !kept.isEmpty { lines += logSection(Array(kept)) }
            let text: String = scrub(lines.joined(separator: "\n"), homePath: homePath, userName: userName, fullName: fullName)
            if kept.isEmpty || make(base, title, text).absoluteString.count <= limit {
                return fitted(base: base, title: title, body: text, limit: limit)
            }
            first += 1
        }
    }

    /// The log's part of the form: `entries` in a fence longer than any run of backticks in them, so none can close it.
    private static func logSection(_ entries: [String]) -> [String] {
        var longest: Int = 0
        for entry in entries {
            var run: Int = 0
            for ch in entry { run = ch == "`" ? run + 1 : 0; longest = max(longest, run) }
        }
        let fence: String = String(repeating: "`", count: max(3, longest + 1))
        return ["", "<details><summary>Recent log</summary>", "", fence] + entries + [fence, "</details>"]
    }
}

/// The recent log as Report a Problem picks it, from the log file's text: only entries this version wrote, whole. The
/// file must start with `header` (this version's first start begins the log with it, `LogFile.start`); a file without
/// it was written before, and none of it is read. An entry is a line that starts with the stamp `Log.write` puts on
/// it ("2026-11-25T10:00:00Z ") and the lines after it up to the next one (a message that ran over several lines,
/// indented). Lines before the first stamp are the end of an entry whose start isn't there: they go. An entry that
/// doesn't end with the writer's newline is an unfinished write: it goes too.
public enum LogEntries {
    static let stamp: String = #"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(Z|[+-]\d\d:?\d\d) "#

    /// The log's first line, written by this version when it starts a log: the mark that every entry after it is
    /// this writer's (stamped, a message's later lines indented).
    public static let header: String = "ASCII Animals log: each entry stamped, a message's later lines indented\n"

    /// One entry as `Log.write` puts it in the file: the stamp, the message and a newline. The message's later lines
    /// are indented, so none of them can pass for an entry of its own (a volume name with a newline and a stamp in it).
    public static func entry(stamp: String, message: String) -> String {
        let body: String = message.replacingOccurrences(of: "\n", with: "\n  ")
        return "\(stamp) \(body)\n"
    }

    /// Whether `line` starts an entry.
    public static func starts(_ line: String) -> Bool {
        line.range(of: stamp, options: .regularExpression) != nil
    }

    /// `text` without an unfinished last entry: when it doesn't end with the writer's newline, its last entry goes
    /// from the stamp on (only the last line, if no line before it starts an entry).
    public static func finished(_ text: String) -> String {
        if text.isEmpty || text.hasSuffix("\n") { return text }
        let lines: [Substring] = text.split(separator: "\n", omittingEmptySubsequences: false)
        let cut: Int = lines.indices.last { (i: Int) -> Bool in starts(String(lines[i])) } ?? (lines.count - 1)
        if cut == 0 { return "" }
        return lines[..<cut].joined(separator: "\n") + "\n"
    }

    /// The last `n` entries of the log (`text`), oldest first, each whole (its lines joined with newlines). Nothing
    /// from a log this version didn't start (no `header`).
    public static func last(_ n: Int, in text: String) -> [String] {
        guard text.hasPrefix(header) else { return [] }
        var entries: [[String]] = []
        for sub in finished(String(text.dropFirst(header.count))).split(separator: "\n", omittingEmptySubsequences: false) {
            let line: String = String(sub)
            if starts(line) {
                entries.append([line])
            } else if !entries.isEmpty {
                entries[entries.count - 1].append(line)
            }
        }
        return entries.suffix(max(0, n)).map { (lines: [String]) -> String in
            var kept: [String] = lines
            while kept.count > 1, kept.last?.isEmpty == true { kept.removeLast() }
            return kept.joined(separator: "\n")
        }
    }
}

/// The log file on disk, `file` with one backup: `Log` calls these on its queue, the checks on a scratch folder.
public enum LogFile {
    /// Call before the run's first read or write of the log. A log this version started (it begins with
    /// `LogEntries.header`) is kept, less an unfinished last entry, so the next entry can't run on from it. Anything
    /// else (an older version's log, or none: an upgrade or a fresh install) is deleted with its backup and a fresh
    /// log begun. True when it started a fresh log: once, on this version's first start.
    @discardableResult
    public static func start(file: URL, backup: URL) -> Bool {
        let fm = FileManager.default
        if let data = try? Data(contentsOf: file), data.starts(with: Data(LogEntries.header.utf8)) {
            if data.last != UInt8(ascii: "\n") {
                let text: String = String(decoding: data, as: UTF8.self)
                try? Data(LogEntries.finished(text).utf8).write(to: file, options: .atomic)
            }
            return false
        }
        try? fm.removeItem(at: backup)
        try? fm.removeItem(at: file)
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(LogEntries.header.utf8).write(to: file, options: .atomic)
        return true
    }

    /// Appends `entry` (`LogEntries.entry`) to `file`, first moving a file over `limit` bytes to `backup`. A new file
    /// begins with `LogEntries.header`.
    public static func append(_ entry: String, file: URL, backup: URL, limit: Int) {
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > limit {
            try? fm.removeItem(at: backup)
            try? fm.moveItem(at: file, to: backup)
        }
        if fm.fileExists(atPath: file.path), let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile()
            h.write(Data(entry.utf8))
            try? h.close()
        } else {
            try? Data((LogEntries.header + entry).utf8).write(to: file)
        }
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
    /// The transport error's domain and code, for the log (`UpdateFailure.code(of:)`).
    public var errorCode: String?
    public init(status: Int?, body: Data? = nil, etag: String? = nil, error: String? = nil, errorCode: String? = nil) {
        self.status = status; self.body = body; self.etag = etag; self.error = error; self.errorCode = errorCode
    }
}

public struct UpdateFailure: Error, Equatable, CustomStringConvertible, Sendable {
    /// For the person.
    public let description: String
    /// For the log: an error only by its domain and code, never its free-form text.
    public let logText: String
    public init(_ d: String, log: String? = nil) { description = d; logText = log ?? d }
    /// "Error Domain=NSCocoaErrorDomain Code=513": what the log keeps of an error.
    public static func code(of error: Error) -> String {
        let ns = error as NSError
        return "Error Domain=\(ns.domain) Code=\(ns.code)"
    }
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
    /// The person is using the app: no automatic install now.
    public var busy: Bool { appActive || windowUp || menuOpen }
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
    /// Installed, but the new copy couldn't be started: this copy runs on and doesn't install it again.
    private var restartPending: LatestRelease?
    /// Which install is running: only the one that started a download may swap it in.
    private var installID: Int = 0
    /// A checked download whose automatic install waits because the app is in use: the next try swaps it in
    /// instead of downloading again. It goes when it no longer applies.
    private var held: StagedUpdate?
    static let inUse = "the app is in use"

    public init(store: UpdateStore, host: UpdateHost) {
        self.store = store
        self.host = host
    }

    /// At launch: says an automatic update happened, shows a release found earlier (installing it waits for the
    /// first tick, after the welcome or the card has had its moment) and arms the timers if checks are on.
    public func start() {
        announceAutoInstall()
        if let data = store.data(forKey: Self.cachedKey), case .release(let r) = UpdateFeed.read(data),
           UpdatePolicy.isNewer(r.version, than: host.runningVersion) {
            state = .available(r)
        }
        host.setSchedule(host.checking)
    }

    /// A setting changed: the timers run only while checks are on (Check for Updates works either way).
    public func settingsChanged() {
        host.setSchedule(host.checking)
        if !host.checking || !host.autoInstall { dropHeld() }
    }

    /// The hourly tick: checks when due, else installs a release that waited.
    public func tick() {
        guard host.checking else { return }
        let last = store.object(forKey: Self.lastCheckKey) as? Date
        if UpdatePolicy.shouldCheck(lastCheck: last, now: host.now) {
            check(userInitiated: false)
        } else if !autoInstallIfAllowed(), let r = available {
            notifyOnce(r)
        }
    }

    public func check(userInitiated: Bool) {
        guard !inFlight, installing == nil else { return }
        inFlight = true
        if userInitiated { state = .checking }
        let etag: String? = store.data(forKey: Self.cachedKey) != nil ? store.string(forKey: Self.etagKey) : nil
        host.fetchFeed(etag: etag) { [weak self] response in self?.finish(response, userInitiated: userInitiated) }
    }

    /// Only a readable answer counts as a check (and is kept for a 304). A failure says so when the person asked,
    /// and the next hourly tick tries again.
    private func finish(_ response: FeedResponse, userInitiated: Bool) {
        inFlight = false
        var body: Data? = nil
        var why: String? = nil
        var logged: String? = nil
        if response.status == 304 {
            // An unreadable answer kept by an earlier version doesn't count either; dropping it asks afresh next time.
            body = store.data(forKey: Self.cachedKey).flatMap { UpdateFeed.read($0) == .garbled ? nil : $0 }
            if body == nil {
                store.removeObject(forKey: Self.cachedKey)
                why = "GitHub said nothing changed, but no readable earlier answer is kept."
            }
        } else if response.status == 200, let data = response.body {
            if UpdateFeed.read(data) == .garbled {
                why = "GitHub's answer couldn't be read."
            } else {
                body = data
                store.set(data, forKey: Self.cachedKey)
                if let etag = response.etag { store.set(etag, forKey: Self.etagKey) }
            }
        } else {
            why = response.error ?? "GitHub answered \(response.status ?? 0)."
            logged = response.errorCode
        }
        guard let body, why == nil else {
            let reason: String = why ?? "No answer."
            host.log("update check failed: \(logged ?? reason)")
            // An install under way stays: only its own download decides how it ends.
            if installing == nil { state = .failed(reason) }
            if userInitiated { host.tell(.couldNotCheck(reason)) }
            return
        }
        store.set(host.now, forKey: Self.lastCheckKey)
        apply(body, userInitiated: userInitiated)
    }

    private func apply(_ data: Data, userInitiated: Bool) {
        if installing != nil { return }
        if let pending = restartPending {
            state = .idle
            if userInitiated { host.tell(.restartFailed(pending)) }
            return
        }
        let running: String = host.runningVersion
        let latest: LatestRelease? = UpdateFeed.parse(data).flatMap { UpdatePolicy.isNewer($0.version, than: running) ? $0 : nil }
        // A held download goes unless it is this release's current download (its link and checksum still match).
        let stillCurrent: Bool = latest.map { (r: LatestRelease) -> Bool in held?.release.sameDownload(as: r) == true } ?? false
        if !stillCurrent { dropHeld() }
        guard let r = latest else {
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
            userBusy: host.surfaces.busy)
        if go { install(automatic: true) }
        return go
    }

    /// Downloads and installs the available release, then restarts. Asked for by the person: when this copy can't
    /// replace itself, or the install fails, says why and offers the download. Automatic: fails quietly to the notice.
    public func install(automatic: Bool = false) {
        guard let r = available else { return }
        if !automatic, let why = host.installBlocker { return host.tell(.couldNotInstall(r, why)) }
        state = .installing(r)
        installID += 1
        let id: Int = installID
        host.log("installing \(r.tag)\(automatic ? " (automatic)" : "")")
        let ready: (Result<StagedUpdate, UpdateFailure>) -> Void = { [weak self] staged in
            guard let self else { return }
            guard self.installID == id, self.installing == r else {
                if case .success(let s) = staged { self.host.discard(s) }
                return
            }
            // Automatic: look again right before replacing; the person may have opened Settings or a menu, or turned
            // automatic installs off, while it downloaded. In use: the checked download waits for the next try and
            // the notice says the update is there. Turned off or failed before: the download goes.
            if automatic, case .success(let s) = staged, let why = self.automaticBlocker(r) {
                self.host.log("update \(r.tag) waits: \(why)")
                self.state = .available(r)
                if why == Self.inUse {
                    self.held = s
                    self.notifyOnce(r)
                } else {
                    self.host.discard(s)
                }
                return
            }
            switch staged.flatMap({ s in self.host.commit(s) }) {
            case .success(let app):
                if automatic { self.store.set(r.version.description, forKey: Self.autoInstalledKey) }
                if self.host.startNewCopy(app) {
                    self.host.log("installed \(r.tag), restarting")
                    self.host.quit()
                } else {
                    // Nothing would open the new copy: this one keeps running and says so.
                    self.host.log("installed \(r.tag), but the restart couldn't be started; still running \(self.host.runningVersion)")
                    self.restartPending = r
                    self.state = .idle
                    self.host.tell(.restartFailed(r))
                }
            case .failure(let why):
                self.host.log("update install failed: \(why.logText)")
                self.state = .available(r)
                if automatic {
                    self.store.set(r.tag, forKey: Self.autoFailedKey)
                    self.notifyOnce(r)
                } else {
                    self.host.tell(.couldNotInstall(r, why.description))
                }
            }
        }
        if let kept = held, kept.release.sameDownload(as: r) {
            held = nil
            ready(.success(kept))
        } else {
            dropHeld()
            host.stage(r, done: ready)
        }
    }

    /// Throws away a kept download.
    private func dropHeld() {
        guard let kept = held else { return }
        held = nil
        host.discard(kept)
    }

    /// Why an automatic install of `r` can't replace the app right now, read fresh, or nil when it can.
    private func automaticBlocker(_ r: LatestRelease) -> String? {
        if !host.checking { return "checks are off" }
        if !host.autoInstall { return "automatic installs are off" }
        if host.surfaces.busy { return Self.inUse }
        if r.tag == store.string(forKey: Self.autoFailedKey) { return "it failed before" }
        return nil
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
