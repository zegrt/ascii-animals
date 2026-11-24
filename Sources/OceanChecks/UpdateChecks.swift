import Foundation
import OceanKit

// r3: updates, settings and Report a Problem that tell the truth. The updater is driven with fakes (a feed, a clock,
// the app's surfaces, a notification centre); nothing here touches the network, the disk or the screen.

/// Key-value storage in a dictionary.
private final class MemoryStore: UpdateStore {
    var values: [String: Any] = [:]
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func string(forKey key: String) -> String? { values[key] as? String }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}

/// Everything outside the engine, faked. Asynchronous answers (the feed, the download, notifications) wait in a queue
/// until the check releases them, so a check can change the world in between.
private final class FakeHost: UpdateHost {
    var now: Date = Date(timeIntervalSince1970: 1_800_000_000)
    var checking: Bool = true
    var autoInstall: Bool = true
    var surfaces: UpdateSurfaces = UpdateSurfaces()
    var runningVersion: String = "3.0"
    var installBlocker: String? = nil
    var canNotify: Bool = true

    /// What the next feed request answers.
    var feed: FeedResponse = FeedResponse(status: 200, body: releaseJSON("v3.1"), etag: "\"a\"")
    var startAnswer: Bool = true
    var offerAnswer: Bool = true

    var scheduled: Bool = false
    var fetches: Int = 0
    var staged: [String] = []
    var committed: [String] = []
    var discarded: [String] = []
    var started: Int = 0
    var quits: Int = 0
    var notified: [String] = []
    var told: [UpdateMessage] = []
    var lines: [String] = []

    /// Answers still to come, in order.
    var pending: [() -> Void] = []
    func release() { while !pending.isEmpty { pending.removeFirst()() } }

    func setSchedule(_ on: Bool) { scheduled = on }
    func fetchFeed(etag: String?, done: @escaping (FeedResponse) -> Void) {
        fetches += 1
        let answer: FeedResponse = feed
        pending.append { done(answer) }
    }
    func stage(_ release: LatestRelease, done: @escaping (Result<StagedUpdate, UpdateFailure>) -> Void) {
        staged.append(release.tag)
        let folder = URL(fileURLWithPath: "/fake/staged/\(release.tag)")
        let s = StagedUpdate(release: release, app: folder.appendingPathComponent("ASCII Animals.app"), folder: folder)
        pending.append { done(.success(s)) }
    }
    func commit(_ staged: StagedUpdate) -> Result<URL, UpdateFailure> {
        committed.append(staged.release.tag)
        return .success(URL(fileURLWithPath: "/fake/ASCII Animals.app"))
    }
    func discard(_ staged: StagedUpdate) { discarded.append(staged.release.tag) }
    func startNewCopy(_ app: URL) -> Bool { started += 1; return startAnswer }
    func quit() { quits += 1 }
    func notify(id: String, title: String, body: String, kind: String, done: @escaping (Bool) -> Void) {
        notified.append(id)
        pending.append { done(true) }
    }
    func offerInstall(_ release: LatestRelease) -> Bool { offerAnswer }
    func tell(_ message: UpdateMessage) { told.append(message) }
    func log(_ line: String) { lines.append(line) }

    func said(_ match: (UpdateMessage) -> Bool) -> Bool { told.contains(where: match) }
}

/// A GitHub `releases/latest` answer for `tag`, installable (a zip with a digest).
private func releaseJSON(_ tag: String) -> Data {
    let digest: String = "sha256:" + String(repeating: "ab", count: 32)
    let json: String = """
    {"tag_name":"\(tag)","html_url":"https://github.com/zegrt/ascii-animals/releases/tag/\(tag)","body":"notes",
     "assets":[{"name":"ASCII-Animals.zip",
                "browser_download_url":"https://github.com/zegrt/ascii-animals/releases/download/\(tag)/ASCII-Animals.zip",
                "digest":"\(digest)"}]}
    """
    return Data(json.utf8)
}

/// An engine whose store already knows release `tag` from a check an hour ago (so the next tick isn't a check and
/// tries the waiting release instead). Started while the person is in the app (so nothing installs at the start),
/// then with nothing up, and the host's notices and counts cleared.
private func engineKnowing(_ tag: String, _ host: FakeHost) -> UpdateEngine {
    let store = MemoryStore()
    let warm = UpdateEngine(store: store, host: host)
    host.autoInstall = false
    host.feed = FeedResponse(status: 200, body: releaseJSON(tag), etag: "\"a\"")
    warm.check(userInitiated: false)
    host.release()
    host.autoInstall = true
    host.now = host.now.addingTimeInterval(3600)
    let e = UpdateEngine(store: store, host: host)
    host.surfaces = UpdateSurfaces(appActive: true)
    e.start()
    host.release()
    host.surfaces = UpdateSurfaces()
    host.notified = []; host.fetches = 0; host.staged = []
    return e
}

private func isUpToDate(_ m: UpdateMessage) -> Bool { if case .upToDate = m { return true }; return false }
private func isCouldNotCheck(_ m: UpdateMessage) -> Bool { if case .couldNotCheck = m { return true }; return false }
private func isRestartFailed(_ m: UpdateMessage) -> Bool { if case .restartFailed = m { return true }; return false }

func updateChecks() {
    updateBusyChecks()
    updateFeedChecks()
    updateRestartChecks()
    updateTimerChecks()
    reportFormChecks()
    // Last: on 971a216 an extreme saved fps traps (overflow), which ends the run.
    settingsExtremeChecks()
}

// MARK: - 1. An update never replaces the app under the user

private func updateBusyChecks() {
    // Settings open but not focused (the person clicked the desktop), a menu open, the card or the welcome up: the
    // app isn't frontmost in any of these, yet the person is in the middle of something.
    check("updateWaitsWhileSettingsMenuCardOrWelcomeIsUp") {
        let cases: [(String, UpdateSurfaces)] = [
            ("Settings open, unfocused", UpdateSurfaces(appActive: false, windowUp: true, menuOpen: false)),
            ("a menu open", UpdateSurfaces(appActive: false, windowUp: false, menuOpen: true)),
            ("the card or the welcome up", UpdateSurfaces(appActive: false, windowUp: true, menuOpen: false)),
        ]
        for (name, surfaces) in cases {
            let host = FakeHost()
            let e = engineKnowing("v3.1", host)
            host.surfaces = surfaces
            e.tick()
            host.release()
            try expect(host.committed.isEmpty && host.quits == 0, "\(name): replaced the app (\(host.committed))")
            try expect(e.available?.tag == "v3.1", "\(name): the release isn't offered any more: \(e.state)")
        }
    }
    // A release found earlier doesn't start installing the moment the app opens, ahead of the welcome or the card.
    check("updateNotAtLaunch") {
        let fresh = FakeHost()
        let store = MemoryStore()
        store.set(releaseJSON("v3.1"), forKey: UpdateEngine.cachedKey)
        store.set(fresh.now.addingTimeInterval(-3600), forKey: UpdateEngine.lastCheckKey)
        let launched = UpdateEngine(store: store, host: fresh)
        launched.start()
        fresh.release()
        try expect(fresh.staged.isEmpty && fresh.committed.isEmpty, "installing at launch: \(fresh.staged)")
        try expect(launched.available?.tag == "v3.1", "the release found earlier isn't shown: \(launched.state)")
    }
    // The download takes a while: Settings opens, a menu opens, or automatic installs are turned off before the swap.
    check("updateRechecksRightBeforeReplacing") {
        for change in ["Settings opens", "a menu opens", "automatic installs off", "checks off"] {
            let host = FakeHost()
            let e = engineKnowing("v3.1", host)
            e.tick()
            try expect(host.staged == ["v3.1"], "\(change): didn't start: \(host.staged)")
            switch change {
            case "Settings opens": host.surfaces = UpdateSurfaces(windowUp: true)
            case "a menu opens": host.surfaces = UpdateSurfaces(menuOpen: true)
            case "automatic installs off": host.autoInstall = false
            default: host.checking = false
            }
            host.release()
            try expect(host.committed.isEmpty && host.quits == 0, "\(change): replaced the app anyway")
            try expect(host.discarded == ["v3.1"], "\(change): the download wasn't thrown away: \(host.discarded)")
            try expect(e.available?.tag == "v3.1", "\(change): the release isn't offered any more: \(e.state)")
        }
    }
    // Asked for by the person (the menu, a notice): installs even with Settings open.
    check("updateAskedForInstallsAnyway") {
        let host = FakeHost()
        let e = engineKnowing("v3.1", host)
        host.surfaces = UpdateSurfaces(appActive: true, windowUp: true, menuOpen: false)
        e.install()
        host.release()
        try expect(host.committed == ["v3.1"] && host.quits == 1, "the asked-for install didn't run: \(host.committed)")
    }
    check("updateInstallsWhenNothingIsUp") {
        let host = FakeHost()
        let e = engineKnowing("v3.1", host)
        e.tick()
        host.release()
        try expect(host.committed == ["v3.1"] && host.quits == 1, "an idle Mac didn't update: \(host.committed)")
    }
}

// MARK: - 2. "You're up to date" only after a valid check

private func updateFeedChecks() {
    check("updateGarbledFeedIsNotUpToDate") {
        let host = FakeHost()
        let e = UpdateEngine(store: MemoryStore(), host: host)
        host.feed = FeedResponse(status: 200, body: Data("<html>rate limited</html>".utf8), etag: "\"x\"")
        e.check(userInitiated: true)
        host.release()
        try expect(!host.said(isUpToDate), "an unreadable answer said you're up to date: \(host.told)")
        try expect(host.said(isCouldNotCheck), "the person wasn't told the check failed: \(host.told)")
        try expect(e.state != .upToDate, "state \(e.state)")
    }
    check("updateFailureRetriesWithinAnHour") {
        for (name, answer) in [("offline", FeedResponse(status: nil, error: "The Internet connection appears to be offline.")),
                               ("garbled", FeedResponse(status: 200, body: Data("{}".utf8))),
                               ("server error", FeedResponse(status: 502))] {
            let host = FakeHost()
            let e = UpdateEngine(store: MemoryStore(), host: host)
            host.feed = answer
            e.tick()
            host.release()
            try expect(host.fetches == 1, "\(name): first try")
            host.now = host.now.addingTimeInterval(3600)
            host.feed = FeedResponse(status: 200, body: releaseJSON("v3.0"))
            e.tick()
            host.release()
            try expect(host.fetches == 2, "\(name): no new try an hour after the failure")
            try expect(e.state == .upToDate, "\(name): state after the retry: \(e.state)")
        }
    }
    // A valid answer still holds for the usual 20 hours.
    check("updateValidCheckWaits") {
        let host = FakeHost()
        let e = UpdateEngine(store: MemoryStore(), host: host)
        host.feed = FeedResponse(status: 200, body: releaseJSON("v3.0"))
        e.tick()
        host.release()
        host.now = host.now.addingTimeInterval(3600)
        e.tick()
        try expect(host.fetches == 1 && e.state == .upToDate, "checked again an hour after a valid answer")
    }
}

// MARK: - 3. A relaunch that can't start doesn't quit

private func updateRestartChecks() {
    check("updateRestartFailureKeepsRunningAndSaysSo") {
        for automatic in [false, true] {
            let host = FakeHost()
            let e = engineKnowing("v3.1", host)
            host.startAnswer = false
            if automatic { e.tick() } else { e.install() }
            host.release()
            try expect(host.started == 1, "auto \(automatic): no restart tried")
            try expect(host.quits == 0, "auto \(automatic): quit with nothing to take over")
            try expect(host.said(isRestartFailed), "auto \(automatic): the person wasn't told: \(host.told)")
            try expect(e.installing == nil, "auto \(automatic): stuck installing")
            // The new copy is in place: the next tick doesn't download and swap the same release again.
            host.now = host.now.addingTimeInterval(21 * 3600)
            e.tick()
            host.release()
            try expect(host.staged.count == 1, "auto \(automatic): installed again: \(host.staged)")
        }
    }
}

// MARK: - 6. No update timers while checks are off

private func updateTimerChecks() {
    check("updateNoTimersWhileChecksOff") {
        let host = FakeHost()
        host.checking = false
        let e = UpdateEngine(store: MemoryStore(), host: host)
        e.start()
        try expect(!host.scheduled, "timers armed with checks off")
        host.checking = true
        e.settingsChanged()
        try expect(host.scheduled, "turning checks on didn't arm them")
        host.checking = false
        e.settingsChanged()
        try expect(!host.scheduled, "turning checks off left them running")
        // Check for Updates still works by hand.
        host.feed = FeedResponse(status: 200, body: releaseJSON("v3.0"))
        e.check(userInitiated: true)
        host.release()
        try expect(host.fetches == 1 && host.said(isUpToDate), "the manual check: \(host.fetches), \(host.told)")
    }
}

// MARK: - 5. Report a Problem sends nothing unseen

private func reportFormChecks() {
    let base: URL = URL(string: "https://github.com/o/r/issues/new")!
    let log: [String] = [
        "still failed: /Users/jane/Library/Application Support/ASCII Animals/x.png",
        "hand-over: Jane Appleseed's ASCII Sharks quit",
        "wallpaper on /Volumes/Jane's Photos/Walls/a.png",
        "other account: /Users/bob/Desktop/b.png",
    ]
    func facts(_ log: [String]) -> DiagnosticFacts {
        DiagnosticFacts(appVersion: "3.1 (12)", macOS: "26.1.0", model: "Mac17,9",
                        displays: ["Jane's Studio Display 2560x1440 @2x 60 Hz"], power: "AC power", mode: "Ocean, live",
                        settingsJSON: #"{"fps":30}"#, crashedLastTime: false, logTail: log,
                        displaySizes: ["2560x1440 @2x 60 Hz"])
    }
    func form(_ log: [String], includeLog: Bool) -> String {
        IssueReport.form(facts(log), includeLog: includeLog, homePath: "/Users/jane", userName: "jane",
                         fullName: "Jane Appleseed", base: base, title: "Problem: ")
    }
    check("reportFormIsTheSummary") {
        let text: String = form(log, includeLog: false)
        for needle in ["3.1 (12)", "26.1.0", "2560x1440", #""fps":30"#] {
            try expect(text.contains(needle), "missing \(needle):\n\(text)")
        }
        for leak in ["Studio Display", "still failed", "Appleseed", "/Volumes", "/Users"] {
            try expect(!text.contains(leak), "\(leak) is in the form without being asked for:\n\(text)")
        }
    }
    check("reportFormLogLinesRedacted") {
        let text: String = form(log, includeLog: true)
        try expect(text.contains("still failed") && text.contains("other account"), "the chosen log lines are missing")
        for leak in ["/Users/jane", "/Users/bob", "Jane's Photos", "Appleseed", "jane"] {
            try expect(!text.contains(leak), "\(leak) left in:\n\(text)")
        }
    }
    // What the review shows is exactly what the GitHub form gets: nothing cut or added after.
    check("reportShownIsSent") {
        let long: [String] = (0..<500).map { "line \($0) " + String(repeating: "x", count: 60) }
        for includeLog in [false, true] {
            let shown: String = form(long, includeLog: includeLog)
            let u: URL = IssueReport.url(base: base, title: "Problem: ", body: shown)
            let sent: String? = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value
            try expect(sent == shown, "log \(includeLog): the form gets something other than what was shown")
            try expect(u.absoluteString.count <= 6000, "log \(includeLog): url length \(u.absoluteString.count)")
        }
    }
}

// MARK: - 4. No crash from a stored setting

private func settingsExtremeChecks() {
    check("settingsExtremeIntsDecode") {
        let cases: [(Int, Int, Int)] = [(Int.min, 15, 1), (Int.max, 60, 12), (Int.min + 1, 15, 1), (-1, 15, 1), (0, 15, 1)]
        for (raw, wantFps, wantCount) in cases {
            let json: String = #"{"fps":\#(raw),"meadowCount":\#(raw)}"#
            let s: Settings = SettingsCodec.decode(Data(json.utf8))
            try expect(s.fps == wantFps, "fps \(raw) -> \(s.fps), want \(wantFps)")
            try expect(s.meadowCount == wantCount, "meadowCount \(raw) -> \(s.meadowCount), want \(wantCount)")
        }
    }
    check("settingsExtremeIntsSanitize") {
        for raw in [Int.min, Int.max] {
            var s: Settings = Settings.defaults
            s.fps = raw
            s.meadowCount = raw
            let t: Settings = s.sanitized()
            try expect(Settings.fpsOptions.contains(t.fps), "fps \(raw) -> \(t.fps)")
            try expect(Settings.meadowCountRange.contains(t.meadowCount), "count \(raw) -> \(t.meadowCount)")
            try expect(t.sanitized() == t, "sanitize isn't stable at \(raw)")
        }
    }
    check("settingsOldSettingsThroughTheCodec") {
        // 3.0's saved settings (no Meadow keys), and ASCII Sharks' (only a few keys), round-trip.
        let v30: String = #"{"appearance":"system","autoInstallUpdates":false,"calm":false,"checkForUpdates":true,"fishDensity":1.3,"fps":15,"grid":true,"habitat":"web","interaction":true,"lowPowerAnimates":false,"matchSystemWallpaper":true,"paused":false,"pauseShortcut":true,"sharedOcean":false,"sharks":["mako"],"showMenuBarIcon":true,"speed":0.8,"wakeColor":"accent","webFlies":false,"webJumper":true,"webSpiders":["nephila","argiope"]}"#
        let s: Settings = SettingsCodec.decode(Data(v30.utf8))
        let kept: Bool = s.habitat == .web && s.fps == 15 && !s.autoInstallUpdates && s.sharks == [.mako]
        try expect(kept, "3.0: \(s)")
        let meadow: Bool = s.meadowCount == 7 && s.meadowButterflies == ButterflyKind.allCases
        try expect(meadow, "3.0 meadow: \(s)")
        try expect(SettingsCodec.decode(SettingsCodec.encode(s)) == s, "3.0 doesn't round-trip")
        let sharks: Settings = SettingsCodec.decode(Data(#"{"sharks":["tiger"],"fps":60,"speed":1.4}"#.utf8))
        try expect(sharks.fps == 60 && sharks.sharks == [.tiger], "Sharks: \(sharks)")
    }
}
