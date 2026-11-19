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
            return "macOS is running ASCII Sharks from a temporary copy. Move it into Applications, open it from there, and try again."
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
    public init(appVersion: String, macOS: String, model: String, displays: [String], power: String, mode: String,
                settingsJSON: String, crashedLastTime: Bool, logTail: [String]) {
        self.appVersion = appVersion; self.macOS = macOS; self.model = model; self.displays = displays
        self.power = power; self.mode = mode; self.settingsJSON = settingsJSON; self.crashedLastTime = crashedLastTime
        self.logTail = logTail
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
            "| Ocean | \(d.mode) |",
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
