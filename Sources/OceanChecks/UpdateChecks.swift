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
    /// What the swap answers when it fails (nil: it works).
    var commitFailure: UpdateFailure? = nil
    var offerAnswer: Bool = true

    var scheduled: Bool = false
    var fetches: Int = 0
    var staged: [String] = []
    var committed: [String] = []
    /// What each swap put in: the download's link and the checksum it was checked against.
    var committedDownloads: [String] = []
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
        if let commitFailure { return .failure(commitFailure) }
        committed.append(staged.release.tag)
        committedDownloads.append("\(staged.release.zipURL?.absoluteString ?? "none") \(staged.release.zipSHA256 ?? "none")")
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

/// A GitHub `releases/latest` answer for `tag`, installable (a zip, `asset`, with a digest of `hex`).
private func releaseJSON(_ tag: String, hex: String = String(repeating: "ab", count: 32),
                         asset: String = "ASCII-Animals.zip") -> Data {
    let digest: String = "sha256:" + hex
    let json: String = """
    {"tag_name":"\(tag)","html_url":"https://github.com/zegrt/ascii-animals/releases/tag/\(tag)","body":"notes",
     "assets":[{"name":"\(asset)",
                "browser_download_url":"https://github.com/zegrt/ascii-animals/releases/download/\(tag)/\(asset)",
                "digest":"\(digest)"}]}
    """
    return Data(json.utf8)
}

/// An engine whose store already knows release `tag` from a check an hour ago (so the next tick isn't a check and
/// tries the waiting release instead). Started while the person is in the app (so nothing installs at the start),
/// then with nothing up, and the host's notices and counts cleared. `noticeSent: false`: the earlier check's notice
/// didn't go (the release is known from the cache, as after a restart).
private func engineKnowing(_ tag: String, _ host: FakeHost, noticeSent: Bool = true) -> UpdateEngine {
    let store = MemoryStore()
    let warm = UpdateEngine(store: store, host: host)
    host.autoInstall = false
    host.canNotify = noticeSent
    host.feed = FeedResponse(status: 200, body: releaseJSON(tag), etag: "\"a\"")
    warm.check(userInitiated: false)
    host.release()
    host.canNotify = true
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
    updateRound1Checks()
    reportFormChecks()
    reportRound1Checks()
    updateRound2Checks()
    reportRound2Checks()
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
            // In use: the checked download is kept for the next try. Turned off: it goes.
            let inUse: Bool = change == "Settings opens" || change == "a menu opens"
            let wantDiscarded: [String] = inUse ? [] : ["v3.1"]
            try expect(host.discarded == wantDiscarded, "\(change): discarded \(host.discarded), want \(wantDiscarded)")
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

// MARK: - Fix round 1 (review-r3 @ 04a9e42, findings 3, 4, 5 and the updater's own log lines from 1)

private func updateRound1Checks() {
    // Finding 3: a published stable release whose tag isn't a version, or whose page isn't an absolute URL, is a
    // failed check, never "up to date". A draft or a prerelease still offers nothing.
    func malformedStableReleaseFails() throws {
        let page: String = "https://github.com/zegrt/ascii-animals/releases/tag/v3.1"
        let cases: [(String, String)] = [
            ("tag isn't a version", #"{"tag_name":"latest-build","html_url":"\#(page)","body":"x"}"#),
            ("relative page URL", #"{"tag_name":"v3.1","html_url":"releases/tag/v3.1","body":"x"}"#),
        ]
        for (name, json) in cases {
            let host = FakeHost()
            let e = UpdateEngine(store: MemoryStore(), host: host)
            host.feed = FeedResponse(status: 200, body: Data(json.utf8), etag: "\"m\"")
            e.check(userInitiated: true)
            host.release()
            try expect(!host.said(isUpToDate), "\(name): said you're up to date: \(host.told)")
            try expect(host.said(isCouldNotCheck), "\(name): the person wasn't told the check failed: \(host.told)")
            if case .failed = e.state {} else { try expect(false, "\(name): state \(e.state)") }
        }
        let excluded: [(String, String)] = [
            ("draft", #"{"tag_name":"nightly","html_url":"x","draft":true}"#),
            ("prerelease", #"{"tag_name":"v9.0-beta","html_url":"https://github.com/o/r/releases/tag/b","prerelease":true}"#),
        ]
        for (name, json) in excluded {
            let host = FakeHost()
            let e = UpdateEngine(store: MemoryStore(), host: host)
            host.feed = FeedResponse(status: 200, body: Data(json.utf8))
            e.check(userInitiated: true)
            host.release()
            try expect(e.available == nil && host.staged.isEmpty, "\(name): offered an install: \(e.state)")
            try expect(!host.said(isCouldNotCheck), "\(name): reported as a failed check: \(host.told)")
        }
    }
    check("updateMalformedStableReleaseIsAFailedCheck", malformedStableReleaseFails)

    // Finding 4: a scheduled check is out when the person installs; the check then fails. The install stays in
    // progress, so a second check and a second install can't start, and only one download is swapped in.
    func feedFailureKeepsTheInstall() throws {
        let host = FakeHost()
        let e = engineKnowing("v3.1", host)
        host.now = host.now.addingTimeInterval(21 * 3600)
        host.surfaces = UpdateSurfaces(appActive: true)
        host.feed = FeedResponse(status: 502)
        e.tick()                       // the scheduled check, still out
        e.install()                    // the person picks the release from the menu
        try expect(host.staged == ["v3.1"], "the install didn't start: \(host.staged)")
        let feedAnswer: () -> Void = host.pending.removeFirst()
        feedAnswer()                   // the check fails while the download runs
        try expect(e.installing?.tag == "v3.1", "the failed check replaced the install: \(e.state)")
        host.feed = FeedResponse(status: 200, body: releaseJSON("v3.1"))
        e.check(userInitiated: true)   // the person checks again and accepts, before the first download is in
        if host.pending.count > 1 {
            let second: () -> Void = host.pending.removeLast()
            second()
        }
        host.release()
        try expect(host.staged == ["v3.1"], "a second download started: \(host.staged)")
        try expect(host.committed == ["v3.1"], "swapped in \(host.committed.count) times: \(host.committed)")
    }
    check("updateFeedFailureKeepsTheInstall", feedFailureKeepsTheInstall)

    // Finding 5: an automatic update held because the app is in use says so once, and its checked download waits
    // for the next try instead of being fetched again.
    func heldAtTheTick() throws {
        let host = FakeHost()
        let e = engineKnowing("v3.1", host, noticeSent: false)
        host.surfaces = UpdateSurfaces(windowUp: true)
        for _ in 0..<3 {
            host.now = host.now.addingTimeInterval(3600)
            e.tick()
            host.release()
        }
        try expect(host.notified == ["update-v3.1"], "notices while held: \(host.notified)")
        try expect(host.committed.isEmpty, "replaced the app while in use")
    }
    check("updateHeldAtTheTickNotifiesOnce", heldAtTheTick)

    func heldAtTheSwap() throws {
        let host = FakeHost()
        let e = engineKnowing("v3.1", host, noticeSent: false)
        e.tick()
        host.surfaces = UpdateSurfaces(menuOpen: true)   // a menu opens as the download is ready
        host.release()
        for surfaces in [UpdateSurfaces(menuOpen: true), UpdateSurfaces(windowUp: true)] {
            host.now = host.now.addingTimeInterval(3600)
            host.surfaces = surfaces                      // still in use at the next tries
            e.tick()
            host.release()
        }
        try expect(host.staged == ["v3.1"], "downloaded \(host.staged.count) times: \(host.staged)")
        try expect(host.discarded.isEmpty, "the checked download was thrown away: \(host.discarded)")
        try expect(host.notified == ["update-v3.1"], "notices while held: \(host.notified)")
        try expect(host.committed.isEmpty, "replaced the app with a menu open")
        // Nothing up: the kept download goes in, without a new one.
        host.now = host.now.addingTimeInterval(3600)
        host.surfaces = UpdateSurfaces()
        e.tick()
        host.release()
        try expect(host.staged == ["v3.1"] && host.committed == ["v3.1"], "staged \(host.staged), swapped \(host.committed)")
    }
    check("updateHeldAtTheSwapKeepsTheDownload", heldAtTheSwap)

    // Finding 5: the kept download goes when it no longer applies (automatic installs off, or a newer release).
    func heldDownloadDropped() throws {
        for change in ["automatic installs off", "a newer release"] {
            let host = FakeHost()
            let e = engineKnowing("v3.1", host)
            e.tick()
            host.surfaces = UpdateSurfaces(menuOpen: true)
            host.release()
            try expect(host.discarded.isEmpty, "\(change): not kept in the first place")
            if change == "automatic installs off" {
                host.autoInstall = false
                e.settingsChanged()
            } else {
                host.now = host.now.addingTimeInterval(21 * 3600)
                host.feed = FeedResponse(status: 200, body: releaseJSON("v3.2"))
                e.tick()
                host.release()
            }
            try expect(host.discarded == ["v3.1"], "\(change): the kept v3.1 download stayed: \(host.discarded)")
        }
    }
    check("updateHeldDownloadDroppedWhenItNoLongerApplies", heldDownloadDropped)

    // Finding 1, the updater's own lines: an error is logged by its domain and code only.
    func updaterLogsCodes() throws {
        let host = FakeHost()
        let e = engineKnowing("v3.1", host)
        host.commitFailure = UpdateFailure("Couldn't replace the app: You can’t save the file “ASCII Animals” because the volume “Jane's Photos” is read only.",
                                           log: "Couldn't replace the app: Error Domain=NSCocoaErrorDomain Code=642")
        e.install()
        host.release()
        host.feed = FeedResponse(status: nil, error: "The file “Jane's Photos” couldn’t be opened.",
                                 errorCode: "Error Domain=NSCocoaErrorDomain Code=260")
        e.check(userInitiated: false)
        host.release()
        let logged: String = host.lines.joined(separator: "\n")
        try expect(!logged.contains("Jane"), "a volume name in the log:\n\(logged)")
        try expect(logged.contains("Code=642") && logged.contains("Code=260"), "the codes are missing:\n\(logged)")
    }
    check("updateLogKeepsErrorCodesOnly", updaterLogsCodes)
}

// MARK: - Fix round 1 (review-r3 @ 04a9e42, findings 1 and 6): the opted-in log and the form

private func reportRound1Checks() {
    let base: URL = URL(string: "https://github.com/o/r/issues/new")!
    let home: String = "/Volumes/Data/jane doe"
    func facts(_ log: [String]) -> DiagnosticFacts {
        DiagnosticFacts(appVersion: "3.1 (12)", macOS: "26.1.0", model: "Mac17,9", displays: [], power: "AC power",
                        mode: "Ocean, live", settingsJSON: #"{"fps":30}"#, crashedLastTime: false, logTail: log,
                        displaySizes: ["2560x1440 @2x 60 Hz"])
    }
    func form(_ log: [String]) -> String {
        IssueReport.form(facts(log), includeLog: true, homePath: home, userName: "jdoe", fullName: "Jane Doe",
                         base: base, title: "Problem: ")
    }
    /// What Log.write and Log.tail make of a message: a stamp, then the text split at its newlines.
    func logged(_ message: String) -> [String] {
        "2026-11-25T10:00:00Z \(message)".split(separator: "\n").map(String.init)
    }

    // A real Foundation file error on a named volume (nothing is there: reading the folder just fails), and a home
    // folder on a named volume as a file URL, percent-encoded.
    func errorsAndEncodedHome() throws {
        var lines: [String] = []
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: "/Volumes/Jane's Photos")
            try expect(false, "the fixture folder exists")
        } catch {
            lines += logged("still failed: \(error)")
        }
        let homeURL: URL = URL(fileURLWithPath: home + "/Pictures/a b.png")
        lines += logged("wallpaper: \(homeURL.absoluteString)")
        lines += logged("next line")
        let text: String = form(lines)
        for leak in ["Jane", "Photos", "doe", "jane"] {
            try expect(!text.contains(leak), "\(leak) left in:\n\(text)")
        }
        try expect(text.contains("still failed: Error Domain=NSCocoaErrorDomain Code=260"), "the error's domain and code are missing:\n\(text)")
        try expect(text.contains("next line"), "a later line went too:\n\(text)")
    }
    check("reportLogErrorsKeepDomainAndCode", errorsAndEncodedHome)

    // Finding 6: a literal + reaches the form as +, read the way a web form reads its query.
    func plusSurvivesFormDecoding() throws {
        let shown: String = form(logged("speed 1+1 = 2, C++ and a+b"))
        let u: URL = IssueReport.url(base: base, title: "Problem: +", body: shown)
        let items: [URLQueryItem] = URLComponents(url: u, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
        func formDecoded(_ name: String) -> String? {
            items.first { $0.name == name }?.value?.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        }
        try expect(formDecoded("body") == shown, "the body read as a form differs from what was shown")
        try expect(formDecoded("title") == "Problem: +", "the title read as a form: \(formDecoded("title") ?? "nil")")
    }
    check("reportPlusSurvivesFormDecoding", plusSurvivesFormDecoding)
}

// MARK: - Fix round 2 (review-r3-r1 @ a46e3e1, remaining findings 1 and 2)

private func updateRound2Checks() {
    // Remaining 2: the same tag with a replaced asset (a new checksum, or a new download link). The held download
    // was checked against the old asset, so it goes and the current one is fetched and swapped in.
    func heldReplacedAsset() throws {
        let newHex: String = String(repeating: "cd", count: 32)
        let cases: [(String, Data, String)] = [
            ("a new checksum", releaseJSON("v3.1", hex: newHex),
             "https://github.com/zegrt/ascii-animals/releases/download/v3.1/ASCII-Animals.zip \(newHex)"),
            ("a new download link", releaseJSON("v3.1", asset: "ASCII-Animals-3.1.zip"),
             "https://github.com/zegrt/ascii-animals/releases/download/v3.1/ASCII-Animals-3.1.zip "
                + String(repeating: "ab", count: 32)),
        ]
        for (change, feed, wanted) in cases {
            let host = FakeHost()
            let e = engineKnowing("v3.1", host)
            e.tick()
            host.surfaces = UpdateSurfaces(menuOpen: true)   // in use as the download is ready: it's held
            host.release()
            try expect(host.staged == ["v3.1"] && host.discarded.isEmpty, "\(change): not held in the first place")
            host.now = host.now.addingTimeInterval(21 * 3600)
            host.surfaces = UpdateSurfaces()
            host.feed = FeedResponse(status: 200, body: feed, etag: "\"b\"")
            e.tick()                                         // the next check: same tag, replaced asset
            host.release()
            try expect(host.discarded == ["v3.1"], "\(change): the held download wasn't dropped: \(host.discarded)")
            try expect(host.staged == ["v3.1", "v3.1"], "\(change): not fetched again: \(host.staged)")
            try expect(host.committedDownloads == [wanted], "\(change): swapped in \(host.committedDownloads)")
        }
    }
    check("updateHeldDownloadMustMatchTheCurrentAsset", heldReplacedAsset)
}

private func reportRound2Checks() {
    let base: URL = URL(string: "https://github.com/o/r/issues/new")!
    let stamp: String = "2026-11-25T10:00:00Z"
    func facts(_ log: [String]) -> DiagnosticFacts {
        DiagnosticFacts(appVersion: "3.1 (12)", macOS: "26.1.0", model: "Mac17,9", displays: [], power: "AC power",
                        mode: "Ocean, live", settingsJSON: #"{"fps":30}"#, crashedLastTime: false, logTail: log,
                        displaySizes: ["2560x1440 @2x 60 Hz"])
    }
    func form(_ log: [String]) -> String {
        IssueReport.form(facts(log), includeLog: true, homePath: "/Users/jdoe", userName: "jdoe",
                         fullName: "Jane Doe", base: base, title: "Problem: ")
    }
    /// The log file's text as Log.write leaves it: each message stamped, ending in a newline.
    func file(_ messages: [String]) -> String {
        messages.map { (m: String) -> String in "\(stamp) \(m)\n" }.joined()
    }
    /// The lines between the log's fences in a form.
    func logLines(_ text: String) -> [String] {
        let lines: [String] = text.components(separatedBy: "\n")
        guard let open = lines.firstIndex(of: "<details><summary>Recent log</summary>"),
              let fence = lines[open...].firstIndex(where: { (l: String) -> Bool in l.hasPrefix("```") }),
              let close = lines[(fence + 1)...].firstIndex(of: lines[fence]) else { return [] }
        return Array(lines[(fence + 1)..<close])
    }
    func isStamped(_ line: String) -> Bool { line.hasPrefix(stamp + " ") }

    // Remaining 1: at the old 60-line boundary the tail's first lines are an error's continuation (a volume name
    // with a newline in it). None of it shows. Two errors: a real Foundation one and one written out by hand.
    func boundaryError() throws {
        var real: String = ""
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: "/Volumes/Jane's\nPhotos")
            try expect(false, "the fixture folder exists")
        } catch {
            real = "still failed: \(error)"
        }
        try expect(real.contains("\n"), "the Foundation error is on one line: \(real)")
        let byHand: String = "could not set wallpaper: Error Domain=NSCocoaErrorDomain Code=4 \"The file doesn’t exist.\" "
            + "UserInfo={NSFilePath=/Volumes/Jane's\nPhotos/Walls/a.png,\nNSURL=file:///Volumes/Jane's%0APhotos/Walls/a.png}"
        for error in [real, byHand] {
            let errorLines: Int = error.components(separatedBy: "\n").count
            let newer: [String] = (0..<(60 - (errorLines - 1))).map { (i: Int) -> String in "frame \(i)" }
            let text: String = file(["launched", error] + newer)
            let picked: [String] = LogEntries.last(60, in: text)
            let shown: String = form(picked)
            for leak in ["Jane", "Photos", "Walls", "NSURL", "NSFilePath"] {
                try expect(!shown.contains(leak), "\(leak) shown:\n\(logLines(shown).prefix(4).joined(separator: "\n"))")
            }
            try expect(shown.contains("frame \(newer.count - 1)"), "the newest entry is missing")
            for line in logLines(shown) {
                try expect(isStamped(line), "a line that isn't a stamped entry: \(line)")
            }
        }
    }
    check("reportLogBoundaryErrorShowsNone", boundaryError)

    // Whole entries only: the last n entries (never a line count), each with its own lines, and nothing from an
    // entry whose stamp isn't in the text (the file starting inside one).
    func wholeEntries() throws {
        let text: String = "Photos/Walls (the end of an entry cut off)\nmore of it\n"
            + file(["one", "two\n  two's detail\n  more detail", "three", "four\n  four's detail"])
        let three: [String] = LogEntries.last(3, in: text)
        let wanted: [String] = ["\(stamp) two\n  two's detail\n  more detail", "\(stamp) three", "\(stamp) four\n  four's detail"]
        try expect(three == wanted, "last 3: \(three)")
        let all: [String] = LogEntries.last(60, in: text)
        try expect(all.count == 4 && all.first == "\(stamp) one", "all entries: \(all)")
        try expect(!all.joined().contains("Photos") && !all.joined().contains("more of it"), "the headless start kept: \(all)")
    }
    check("reportLogIsWholeEntries", wholeEntries)

    // Fitting the form to the link drops whole entries, oldest first: the log never starts inside an entry.
    func fittingDropsWholeEntries() throws {
        for pad in 0..<8 {
            let messages: [String] = (0..<120).map { (i: Int) -> String in
                "entry \(i) " + String(repeating: "x", count: 150 + 7 * pad) + "\n  detail of \(i)"
            }
            let shown: [String] = logLines(form(LogEntries.last(60, in: file(messages))))
            try expect(!shown.isEmpty, "pad \(pad): no log left")
            try expect(isStamped(shown[0]), "pad \(pad): the log starts inside an entry: \(shown[0])")
            for (i, line) in shown.enumerated() where isStamped(line) {
                let n: String = line.components(separatedBy: " ")[2]
                let next: String = i + 1 < shown.count ? shown[i + 1] : ""
                try expect(next == "  detail of \(n)", "pad \(pad): entry \(n) cut: \(next)")
            }
        }
    }
    check("reportFittingDropsWholeEntries", fittingDropsWholeEntries)
}
