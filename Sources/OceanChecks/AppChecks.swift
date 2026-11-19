import Foundation
import OceanKit

/// Shape of GitHub's releases/latest payload (fields we read), from the real v2.1 release.
private let latestJSON = #"""
{"tag_name":"v2.1","name":"ASCII Animals 2.1 — one ocean across your displays","draft":false,"prerelease":false,
 "html_url":"https://github.com/zegrt/ascii-animals/releases/tag/v2.1",
 "body":"### New in 2.1\n- One ocean across your displays.",
 "assets":[{"name":"notes.txt","browser_download_url":"https://example.com/notes.txt"},
           {"name":"ASCII-Animals.dmg","browser_download_url":"https://github.com/zegrt/ascii-animals/releases/download/v2.1/ASCII-Animals.dmg",
            "digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111"},
           {"name":"ASCII-Animals.zip","browser_download_url":"https://github.com/zegrt/ascii-animals/releases/download/v2.1/ASCII-Animals.zip",
            "digest":"sha256:856A8D65D0009087ED86532D96B8547291F32D89C55ECED3EEFF7E7B8216AEE5"}]}
"""#

func appChecks() {
    check("versionParsesAndOrders") {
        guard let a = AppVersion("2.1"), let b = AppVersion("v2.10"), let c = AppVersion("2.1.0"), let d = AppVersion("2.2") else {
            throw CheckFailure(detail: "did not parse")
        }
        try expect(a < b && a < d && d < b, "ordering")
        try expect(a == c && !(a < c) && !(c < a), "2.1 vs 2.1.0")
        try expect(AppVersion("dev") == nil && AppVersion("") == nil && AppVersion("2.x") == nil, "garbage parsed")
        try expect(AppVersion("v3")!.description == "3", "description")
    }
    check("feedParsesRealPayload") {
        guard let r = UpdateFeed.parse(Data(latestJSON.utf8)) else { throw CheckFailure(detail: "no release") }
        try expect(r.version == AppVersion("2.1")! && r.tag == "v2.1", "version \(r.version)")
        try expect(r.dmgURL?.lastPathComponent == "ASCII-Animals.dmg", "dmg \(String(describing: r.dmgURL))")
        try expect(r.pageURL.absoluteString.hasSuffix("/tag/v2.1"), "page")
        try expect(r.notes.contains("One ocean"), "notes")
        try expect(r.zipURL?.lastPathComponent == "ASCII-Animals.zip", "zip \(String(describing: r.zipURL))")
        try expect(r.zipSHA256 == "856a8d65d0009087ed86532d96b8547291f32d89c55eced3eeff7e7b8216aee5", "digest \(String(describing: r.zipSHA256))")
    }
    check("feedIgnoresBadDigests") {
        for bad in [#""digest":null"#, #""digest":"md5:abc""#, #""digest":"sha256:xyz""#, #""digest":"sha256:856a""#] {
            let json = latestJSON.replacingOccurrences(of: #""digest":"sha256:856A8D65D0009087ED86532D96B8547291F32D89C55ECED3EEFF7E7B8216AEE5""#, with: bad)
            guard let r = UpdateFeed.parse(Data(json.utf8)) else { throw CheckFailure(detail: "\(bad): no release") }
            try expect(r.zipSHA256 == nil && r.zipURL != nil, "\(bad) gave \(String(describing: r.zipSHA256))")
        }
    }
    check("feedWithoutZipCantSelfUpdate") {
        // Releases before 2.3 had only the DMG.
        let old = #"{"tag_name":"v2.2","html_url":"https://github.com/zegrt/ascii-animals/releases/tag/v2.2","assets":[{"name":"ASCII-Animals.dmg","browser_download_url":"https://github.com/zegrt/ascii-animals/releases/download/v2.2/ASCII-Animals.dmg"}]}"#
        guard let r = UpdateFeed.parse(Data(old.utf8)) else { throw CheckFailure(detail: "no release") }
        try expect(r.zipURL == nil && r.zipSHA256 == nil && r.dmgURL != nil, "old release")
    }
    check("selfUpdateOnlyFromAnInstalledCopy") {
        try expect(SelfUpdate.blocker(bundlePath: "/Applications/ASCII Animals.app") == nil, "Applications")
        try expect(SelfUpdate.blocker(bundlePath: "/Users/x/Applications/ASCII Animals.app") == nil, "~/Applications")
        try expect(SelfUpdate.blocker(bundlePath: "/private/var/folders/ab/T/AppTranslocation/1234/d/ASCII Animals.app") != nil, "translocated")
        try expect(SelfUpdate.blocker(bundlePath: "/Users/x/repo/.build/release") != nil, "bare binary")
    }
    check("selfUpdateTrustsOnlyThisRepo") {
        let repo = "zegrt/ascii-animals"
        let ok = URL(string: "https://github.com/zegrt/ascii-animals/releases/download/v3.0/ASCII-Animals.zip")!
        try expect(SelfUpdate.isTrustedDownload(ok, repoPath: repo), "the real one")
        for bad in ["http://github.com/zegrt/ascii-animals/releases/download/v3.0/ASCII-Animals.zip",
                    "https://github.com.evil.example/zegrt/ascii-animals/releases/download/v3.0/x.zip",
                    "https://github.com/someone/ascii-animals/releases/download/v3.0/x.zip",
                    "https://github.com/zegrt/ascii-animals-fork/releases/download/v3.0/x.zip",
                    "https://example.com/zegrt/ascii-animals/releases/download/v3.0/x.zip",
                    "https://github.com/zegrt/ascii-sharks-wallpaper/releases/download/v2.3/ASCII-Sharks.zip"] {
            try expect(!SelfUpdate.isTrustedDownload(URL(string: bad)!, repoPath: repo), bad)
        }
    }
    check("autoInstallOnlyWhenEverythingAllows") {
        func go(checking: Bool = true, auto: Bool = true, installable: Bool = true, failed: String? = nil, busy: Bool = false) -> Bool {
            UpdatePolicy.shouldAutoInstall(checking: checking, autoInstall: auto, installable: installable,
                                           tag: "v2.4", failedTag: failed, userBusy: busy)
        }
        try expect(go(), "all clear")
        try expect(go(failed: "v2.3"), "an older failure doesn't block a new release")
        try expect(!go(checking: false), "checks off")
        try expect(!go(auto: false), "auto off")
        try expect(!go(installable: false), "no zip or can't replace itself")
        try expect(!go(failed: "v2.4"), "already failed once")
        try expect(!go(busy: true), "user busy")
    }
    check("selfUpdateWantsTheExactApp") {
        let id = "local.ascii-animals.wallpaper", v = AppVersion("2.3")!
        try expect(SelfUpdate.candidateProblem(bundleID: id, version: "2.3", expectedID: id, expectedVersion: v) == nil, "match")
        try expect(SelfUpdate.candidateProblem(bundleID: id, version: "2.3.0", expectedID: id, expectedVersion: v) == nil, "2.3.0")
        try expect(SelfUpdate.candidateProblem(bundleID: "com.other", version: "2.3", expectedID: id, expectedVersion: v) != nil, "other app")
        try expect(SelfUpdate.candidateProblem(bundleID: nil, version: "2.3", expectedID: id, expectedVersion: v) != nil, "no id")
        try expect(SelfUpdate.candidateProblem(bundleID: id, version: "2.2", expectedID: id, expectedVersion: v) != nil, "older")
        try expect(SelfUpdate.candidateProblem(bundleID: id, version: nil, expectedID: id, expectedVersion: v) != nil, "no version")
    }
    check("feedRejectsDraftsAndJunk") {
        let draft = latestJSON.replacingOccurrences(of: #""draft":false"#, with: #""draft":true"#)
        try expect(UpdateFeed.parse(Data(draft.utf8)) == nil, "draft accepted")
        let pre = latestJSON.replacingOccurrences(of: #""prerelease":false"#, with: #""prerelease":true"#)
        try expect(UpdateFeed.parse(Data(pre.utf8)) == nil, "prerelease accepted")
        try expect(UpdateFeed.parse(Data(#"{"message":"Not Found"}"#.utf8)) == nil, "404 accepted")
        try expect(UpdateFeed.parse(Data("<html>".utf8)) == nil, "junk accepted")
    }
    check("updatePolicyDaily") {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try expect(UpdatePolicy.shouldCheck(lastCheck: nil, now: now), "never checked")
        try expect(!UpdatePolicy.shouldCheck(lastCheck: now.addingTimeInterval(-3600), now: now), "checked an hour ago")
        try expect(UpdatePolicy.shouldCheck(lastCheck: now.addingTimeInterval(-21 * 3600), now: now), "21 h ago")
        try expect(UpdatePolicy.shouldCheck(lastCheck: now.addingTimeInterval(3600), now: now), "clock went backwards")
    }
    check("updateIsNewerOnlyWhenGreater") {
        try expect(UpdatePolicy.isNewer(AppVersion("2.2")!, than: "2.1"), "2.2 > 2.1")
        try expect(!UpdatePolicy.isNewer(AppVersion("2.1")!, than: "2.1"), "same")
        try expect(UpdatePolicy.isNewer(AppVersion("2.2.1")!, than: "2.2"), "2.2.1 > 2.2")
        try expect(!UpdatePolicy.isNewer(AppVersion("2.2")!, than: "2.2.1"), "2.2 < 2.2.1")
        try expect(!UpdatePolicy.isNewer(AppVersion("2.1")!, than: "dev"), "dev builds never nag")
    }
}

private func facts(log: [String] = ["launched"]) -> DiagnosticFacts {
    DiagnosticFacts(appVersion: "2.2 (4)", macOS: "26.6.2", model: "Mac17,9",
                    displays: ["Built-in Retina Display 1800x1169 @2x 120 Hz", "BenQ GW2790Q 2560x1440 @1x 100 Hz"],
                    power: "battery, Low Power Mode", mode: "still", settingsJSON: #"{"sharedOcean":true}"#,
                    crashedLastTime: true, logTail: log)
}

func reportChecks() {
    check("reportHasTheFacts") {
        let b = IssueReport.body(facts(), homePath: "/Users/jane", userName: "jane")
        for needle in ["2.2 (4)", "26.6.2", "Mac17,9", "BenQ GW2790Q", "Low Power Mode", "still", #""sharedOcean":true"#, "launched"] {
            try expect(b.contains(needle), "missing \(needle)")
        }
        try expect(b.lowercased().contains("quit unexpectedly"), "crash not mentioned")
    }
    check("reportScrubsHomeAndName") {
        let f = facts(log: ["still failed: /Users/jane/Library/Application Support/ASCII Animals/x.png", "hello from jane's mac"])
        let b = IssueReport.body(f, homePath: "/Users/jane", userName: "jane")
        try expect(!b.contains("/Users/jane") && !b.lowercased().contains("jane"), "personal data left in: \(b)")
        try expect(b.contains("~/Library/Application Support"), "home not shortened to ~")
    }
    check("reportURLIsBounded") {
        let long = (0..<500).map { "line \($0) " + String(repeating: "x", count: 60) }
        let b = IssueReport.body(facts(log: long), homePath: "/Users/jane", userName: "jane")
        let u = IssueReport.url(base: URL(string: "https://github.com/o/r/issues/new")!, title: "Problem: wallpaper", body: b)
        try expect(u.absoluteString.count <= 6000, "url length \(u.absoluteString.count)")
        let q = URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems!
        try expect(q.first { $0.name == "title" }?.value == "Problem: wallpaper", "title lost")
        try expect(q.first { $0.name == "body" }?.value?.contains("2.2 (4)") == true, "facts dropped instead of log lines")
    }
}

func handoverChecks() {
    let url = URL(fileURLWithPath: "/Applications/ASCII Sharks.app")
    func facts(app: URL? = nil, running: Bool = false, offered: Bool = false, imported: Bool = false, settings: Data? = nil,
               onboarded: Bool = false, own: Bool = false) -> HandoverFacts {
        HandoverFacts(sharksApp: app, sharksRunning: running, alreadyOffered: offered, alreadyImported: imported,
                      sharksSettings: settings, sharksOnboarded: onboarded, ownSettings: own)
    }
    let some = Data("{}".utf8)
    check("handoverNothingWithoutSharks") {
        try expect(Handover.plan(facts()) == [], "expected no steps")
        try expect(Handover.plan(facts(own: true)) == [], "an Animals user alone: expected no steps")
    }
    check("handoverQuitsFirst") {
        let p = Handover.plan(facts(app: url, running: true, settings: some))
        try expect(p == [.quitSharks, .importSettings, .skipWelcome, .offerTrash(url)], "plan \(p)")
    }
    check("handoverImportsOnce") {
        let p = Handover.plan(facts(app: url, imported: true, settings: some))
        try expect(p == [.offerTrash(url)], "plan \(p)")
    }
    check("handoverOffersOnce") {
        let p = Handover.plan(facts(app: url, running: true, offered: true, imported: true, settings: some))
        try expect(p == [.quitSharks], "plan \(p)")
    }
    check("handoverRunningButNotFound") {
        let p = Handover.plan(facts(running: true))
        try expect(p.first == .quitSharks && !p.contains { if case .offerTrash = $0 { return true } else { return false } }, "plan \(p)")
    }
    check("handoverSkipsWelcomeForSharksUsers") {
        // Sharks writes settings.v2 only on a change: installed, or onboarded, is enough.
        try expect(Handover.plan(facts(app: url)) == [.skipWelcome, .offerTrash(url)], "installed, no settings")
        try expect(Handover.plan(facts(onboarded: true)) == [.skipWelcome], "onboarded, app gone")
        try expect(!Handover.plan(facts(app: url, imported: true, onboarded: true)).contains(.skipWelcome), "only once")
    }
    check("handoverKeepsAnimalsSettings") {
        let p = Handover.plan(facts(app: url, settings: some, own: true))
        try expect(!p.contains(.importSettings) && p.contains(.skipWelcome), "plan \(p)")
    }
    check("handoverOnlyTheRealApp") {
        try expect(Handover.enabled(bundleID: "local.ascii-animals.wallpaper", environment: [:]), "the app")
        try expect(!Handover.enabled(bundleID: nil, environment: [:]), "a bare binary")
        try expect(!Handover.enabled(bundleID: "local.ascii-animals.wallpaper", environment: ["ASCII_ANIMALS_NO_HANDOVER": "1"]), "opted out")
        try expect(Handover.sharksUninstallArguments == ["--uninstall", "--yes"], "Sharks 2.3's scripted uninstall")
    }
    check("handoverQuitsSharksWhenItOpens") {
        let sharks: String? = Handover.sharksBundleID
        try expect(Handover.shouldQuit(inserted: [sharks], enabled: true, quitting: false), "Sharks opened")
        try expect(Handover.shouldQuit(inserted: ["com.apple.Safari", nil, sharks], enabled: true, quitting: false), "among others")
        try expect(!Handover.shouldQuit(inserted: [sharks], enabled: true, quitting: true), "re-entered a quit under way")
        try expect(!Handover.shouldQuit(inserted: [sharks], enabled: false, quitting: false), "a dev run touched Sharks")
        try expect(!Handover.shouldQuit(inserted: ["com.apple.Safari", nil], enabled: true, quitting: false), "another app")
        try expect(!Handover.shouldQuit(inserted: [], enabled: true, quitting: false), "nothing new")
    }
    check("handoverLoginItemOnlyFromAnInstalledCopy") {
        try expect(Handover.canAddLoginItem(bundlePath: "/Applications/ASCII Animals.app", onReadOnlyVolume: false), "Applications")
        try expect(Handover.canAddLoginItem(bundlePath: "/Users/x/Applications/ASCII Animals.app", onReadOnlyVolume: false), "~/Applications")
        try expect(!Handover.canAddLoginItem(bundlePath: "/Volumes/ASCII Animals/ASCII Animals.app", onReadOnlyVolume: true), "disk image")
        try expect(!Handover.canAddLoginItem(bundlePath: "/private/var/folders/ab/T/AppTranslocation/1234/d/ASCII Animals.app", onReadOnlyVolume: false), "translocated")
        try expect(!Handover.canAddLoginItem(bundlePath: "/Users/x/repo/.build/release", onReadOnlyVolume: false), "bare binary")
    }
}
