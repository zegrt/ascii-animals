import CoreGraphics
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
    func welcome(onboarded: Bool, handedOver: Bool, cardShown: Bool = false, habitat: HabitatKind = .ocean) -> LaunchWelcome {
        Handover.launchWelcome(onboarded: onboarded, handedOver: handedOver, webCardShown: cardShown, habitat: habitat)
    }
    check("welcomeTourForNewUsers") {
        try expect(welcome(onboarded: false, handedOver: false) == .tour, "a new user")
        // A hand-over that didn't skip the tour: the tour opens with the habitat choice, so no card on top.
        try expect(welcome(onboarded: false, handedOver: true) == .tour, "handed over, tour not skipped")
        try expect(welcome(onboarded: true, handedOver: false) == .nothing, "a new user who saw the tour")
    }
    check("welcomeWebCardOnceForSharksUsers") {
        try expect(welcome(onboarded: true, handedOver: true) == .webCard, "came from ASCII Sharks")
        try expect(welcome(onboarded: true, handedOver: true, cardShown: true) == .nothing, "only once")
        try expect(welcome(onboarded: true, handedOver: true, habitat: .web) == .nothing, "already on the Web")
        try expect(Handover.webCardKey == "whatsNew.web.v1", "the flag's name")
    }

    // 3.1's Meadow card (t9): what a launch shows, from what is saved. Each launch below is a fresh decision, as at a
    // real launch, with the flags the earlier launches left.
    struct Saved {
        var onboarded: Bool
        var handedOver: Bool
        var webShown = false
        var meadowShown = false
        var habitat: HabitatKind = .ocean
        var meadowTried = false
        var arrival: Arrival
    }
    func launch(_ s: Saved) -> LaunchWelcome {
        Handover.launchWelcome(onboarded: s.onboarded, handedOver: s.handedOver, webCardShown: s.webShown, habitat: s.habitat,
                               arrival: s.arrival, meadowCardShown: s.meadowShown, meadowTried: s.meadowTried)
    }
    func meadowCardOnceForUpgraders() throws {
        // A 3.0 user: the welcome seen, settings saved.
        let arrival: Arrival = Arrival.decide(stored: nil, savedSettings: true, onboarded: true, handedOver: false)
        try expect(arrival == .before31, "a 3.0 user is an upgrade")
        var s = Saved(onboarded: true, handedOver: false, arrival: arrival)
        try expect(launch(s) == .meadowCard, "first 3.1 launch: the card")
        s.meadowShown = true
        try expect(launch(s) == .nothing, "shown once, never again")
        var picked = Saved(onboarded: true, handedOver: false, arrival: .before31)
        picked.habitat = .meadow
        picked.meadowTried = true
        try expect(launch(picked) == .nothing, "on the Meadow already")
        picked.habitat = .ocean
        try expect(launch(picked) == .nothing, "picked the Meadow once, then went back: never")
        var web = Saved(onboarded: true, handedOver: false, arrival: .before31)
        web.habitat = .web
        try expect(launch(web) == .meadowCard, "someone on the Web gets it too")
        try expect(Handover.meadowCardKey == "whatsNew.meadow.v1", "the flag's name (d1)")
        try expect(Handover.meadowCardKey != Handover.webCardKey, "its own flag")
    }
    check("meadowCardOnceForUpgraders", meadowCardOnceForUpgraders)
    func meadowCardNeverForNewUsers() throws {
        let fresh: Arrival = Arrival.decide(stored: nil, savedSettings: false, onboarded: false, handedOver: false)
        try expect(fresh == .since31, "a fresh install")
        var s = Saved(onboarded: false, handedOver: false, arrival: fresh)
        try expect(launch(s) == .tour, "a new user gets the tour")
        // The tour marks itself and both cards seen (OnboardingController); and even if the Meadow flag were lost,
        // a fresh install's arrival is kept, so saved settings since never make it an upgrade.
        s.onboarded = true
        s.webShown = true
        try expect(launch(s) == .nothing, "after the tour")
        let later: Arrival = Arrival.decide(stored: fresh.rawValue, savedSettings: true, onboarded: true, handedOver: false)
        let lost = Saved(onboarded: true, handedOver: false, arrival: later)
        try expect(launch(lost) == .nothing, "a new user never gets the card, flag or not")
    }
    check("meadowCardNeverForNewUsers", meadowCardNeverForNewUsers)
    func meadowCardLeavesTheSharksHandoverIntact() throws {
        // Someone coming from ASCII Sharks straight to 3.1: the hand-over skips the tour, then the Web card as ever;
        // the Meadow card waits for the next launch, so only one card shows at a time.
        let steps: [HandoverStep] = Handover.plan(facts(app: url, running: true, settings: Data("{}".utf8)))
        try expect(steps.contains(.skipWelcome) && steps.contains(.quitSharks) && steps.contains(.importSettings), "plan \(steps)")
        let arrival: Arrival = Arrival.decide(stored: nil, savedSettings: true, onboarded: true, handedOver: true)
        try expect(arrival == .before31, "a Sharks user is an upgrade")
        var s = Saved(onboarded: true, handedOver: true, arrival: arrival)
        try expect(launch(s) == .webCard, "the Web card first, unchanged")
        s.webShown = true
        try expect(launch(s) == .meadowCard, "the Meadow card on the next launch")
        s.meadowShown = true
        try expect(launch(s) == .nothing, "then nothing")
        var tried = Saved(onboarded: true, handedOver: true, arrival: arrival)
        tried.habitat = .web
        try expect(launch(tried) == .meadowCard, "found the Web already: straight to the Meadow card")
        // The old entry point (no arrival) still decides exactly as before 3.1.
        try expect(welcome(onboarded: true, handedOver: true) == .webCard && welcome(onboarded: true, handedOver: false) == .nothing,
                   "the four-argument decision is unchanged")
    }
    check("meadowCardLeavesTheSharksHandoverIntact", meadowCardLeavesTheSharksHandoverIntact)
    // t9 fix round 1, finding 5: a 3.0 user whose tour was never marked seen gets the card, not the tour.
    func meadowCardForAnUpgraderWhoNeverFinishedTheTour() throws {
        let arrival: Arrival = Arrival.decide(stored: nil, savedSettings: true, onboarded: false, handedOver: false)
        try expect(arrival == .before31, "saved 3.0 settings: an upgrade")
        var s = Saved(onboarded: false, handedOver: false, arrival: arrival)
        try expect(launch(s) == .meadowCard, "the card, not the full tour: \(launch(s))")
        s.meadowShown = true
        try expect(launch(s) == .nothing, "and then nothing, tour mark or not")
        var web = Saved(onboarded: false, handedOver: false, arrival: arrival)
        web.habitat = .web
        try expect(launch(web) == .meadowCard, "on the Web too")
        var tried = Saved(onboarded: false, handedOver: false, arrival: arrival)
        tried.meadowTried = true
        try expect(launch(tried) == .nothing, "found the Meadow already")
        // The Sharks Web card still goes first for someone handed over.
        let sharks = Saved(onboarded: false, handedOver: true, arrival: .before31)
        try expect(launch(sharks) == .webCard, "handed over, never onboarded: the Web card first: \(launch(sharks))")
        // A fresh install whose tour never reached the screen still gets the tour.
        let fresh = Saved(onboarded: false, handedOver: false, arrival: .since31)
        try expect(launch(fresh) == .tour, "a new user: the tour")
    }
    check("meadowCardForAnUpgraderWhoNeverFinishedTheTour", meadowCardForAnUpgraderWhoNeverFinishedTheTour)
    whatsNewCardChecks()
    cardDrawnChecks()
    check("handoverLoginItemOnlyFromAnInstalledCopy") {
        try expect(Handover.canAddLoginItem(bundlePath: "/Applications/ASCII Animals.app", onReadOnlyVolume: false), "Applications")
        try expect(Handover.canAddLoginItem(bundlePath: "/Users/x/Applications/ASCII Animals.app", onReadOnlyVolume: false), "~/Applications")
        try expect(!Handover.canAddLoginItem(bundlePath: "/Volumes/ASCII Animals/ASCII Animals.app", onReadOnlyVolume: true), "disk image")
        try expect(!Handover.canAddLoginItem(bundlePath: "/private/var/folders/ab/T/AppTranslocation/1234/d/ASCII Animals.app", onReadOnlyVolume: false), "translocated")
        try expect(!Handover.canAddLoginItem(bundlePath: "/Users/x/repo/.build/release", onReadOnlyVolume: false), "bare binary")
    }
}

/// t9 fix round 1: the what's-new card's rules that need no screen (`WhatsNew`): when a waiting card opens and is
/// marked, where it goes, what its preview does, and how its still is framed.
func whatsNewCardChecks() {
    let clear = WhatsNew.Moment(seeable: true, screens: 1, shown: false, habitat: .ocean, tried: false, welcomeUp: false,
                                canDraw: true)

    /// A launch's card driven look by look: `moments` the state at each look; `opens` whether each opening reaches
    /// a usable display. Returns each look's step, how many times it opened and how many times it was marked.
    func run(_ moments: [WhatsNew.Moment], opens: [Bool] = []) -> (steps: [WhatsNew.Step], opened: Int, marked: Int) {
        var i = 0, opened = 0, marked = 0, tries = 0
        var shown = false
        let p = WhatsNew.Presenter(moment: {
            var m = moments[min(i, moments.count - 1)]
            m.shown = m.shown || shown
            return m
        }, open: {
            let ok: Bool = tries < opens.count ? opens[tries] : true
            tries += 1
            if ok { opened += 1 }
            return ok
        }, mark: {
            marked += 1
            shown = true
        })
        var steps: [WhatsNew.Step] = []
        while i < moments.count + 2 {
            let st: WhatsNew.Step = p.look()
            steps.append(st)
            i += 1
            if st != .keepWaiting { break }
        }
        return (steps, opened, marked)
    }

    func whatsNewOpensAtOnceWhenClear() throws {
        let r = run([clear])
        try expect(r.steps == [.open] && r.opened == 1 && r.marked == 1, "first look clear: opened and marked once \(r)")
    }
    check("whatsNewOpensAtOnceWhenClear", whatsNewOpensAtOnceWhenClear)

    func whatsNewWaitsOutARelock() throws {
        // Finding 1: locked at launch, a wake that relocks within the second spends nothing.
        var locked = clear
        locked.seeable = false
        let r = run([locked, locked, clear, locked, clear, clear])
        try expect(r.steps == [.keepWaiting, .keepWaiting, .keepWaiting, .keepWaiting, .keepWaiting, .open],
                   "opens only after a full clear second: \(r.steps)")
        try expect(r.opened == 1 && r.marked == 1, "once: \(r)")
        let never = run([locked, clear, locked, clear, locked])
        try expect(never.opened == 0 && never.marked == 0, "a screen that keeps relocking: never opened, never marked \(never)")
    }
    check("whatsNewWaitsOutARelock", whatsNewWaitsOutARelock)

    func whatsNewMarksOnlyWhatReachedTheScreen() throws {
        // Finding 1: an opening that didn't reach a usable display (it went at once) is not marked; it waits again.
        let r = run([clear, clear, clear, clear], opens: [false, true])
        try expect(r.steps == [.keepWaiting, .keepWaiting, .open], "failed, then a clear second, then open: \(r.steps)")
        try expect(r.opened == 1 && r.marked == 1, "marked once, for the one that reached the screen: \(r)")
        let none = run([clear, clear, clear], opens: [false, false, false, false])
        try expect(none.marked == 0, "never reached the screen: never marked \(none)")
    }
    check("whatsNewMarksOnlyWhatReachedTheScreen", whatsNewMarksOnlyWhatReachedTheScreen)

    func whatsNewWaitsWithNoScreens() throws {
        var noScreens = clear
        noScreens.screens = 0
        try expect(WhatsNew.verdict(noScreens) == .wait, "no displays: wait")
        let r = run([noScreens, noScreens, clear, clear])
        try expect(r.opened == 1 && r.steps.last == .open, "a display attached: opens \(r.steps)")
        var noRenderer = clear
        noRenderer.canDraw = false
        try expect(WhatsNew.verdict(noRenderer) == .drop, "nothing to draw with: a later launch")
    }
    check("whatsNewWaitsWithNoScreens", whatsNewWaitsWithNoScreens)

    func whatsNewYieldsToTheWelcome() throws {
        // Finding 2: the welcome from Help is up: the card waits; the welcome marks the flag: it never comes.
        var welcome = clear
        welcome.welcomeUp = true
        var after = clear
        after.shown = true
        let r = run([welcome, welcome, after])
        try expect(r.steps == [.keepWaiting, .keepWaiting, .stop] && r.opened == 0, "never over or after the welcome: \(r.steps)")
        var meadow = clear
        meadow.habitat = .meadow
        meadow.tried = true
        try expect(run([meadow]).steps == [.stop], "the Meadow picked meanwhile: nothing to tell")
        let p = WhatsNew.Presenter(moment: { clear }, open: { true }, mark: {})
        p.cancel()
        try expect(p.look() == .stop, "cancelled (the welcome opened): no more looks")
    }
    check("whatsNewYieldsToTheWelcome", whatsNewYieldsToTheWelcome)

    func whatsNewPlacement() throws {
        // Finding 6. A laptop screen and a narrow one beside it, in AppKit's bottom-left coordinates.
        let main: (frame: CGRect, visible: CGRect) = (CGRect(x: 0, y: 0, width: 1512, height: 982),
                                                      CGRect(x: 0, y: 0, width: 1512, height: 949))
        let narrow: (frame: CGRect, visible: CGRect) = (CGRect(x: 1512, y: 0, width: 400, height: 700),
                                                        CGRect(x: 1512, y: 0, width: 400, height: 667))
        let screens = [main, narrow]
        let icon = CGRect(x: 1298, y: 949, width: 30, height: 33)
        let a = WhatsNew.anchor(icon: icon, screens: screens)
        try expect(a?.icon == icon && a?.visible == main.visible, "an icon in the menu bar anchors on its screen")
        try expect(WhatsNew.anchor(icon: CGRect(x: 5000, y: 949, width: 30, height: 33), screens: screens) == nil,
                   "a stale frame on no screen: the top-right fallback")
        try expect(WhatsNew.anchor(icon: CGRect(x: 1298, y: 400, width: 30, height: 33), screens: screens) == nil,
                   "a frame inside the visible frame (not in the menu bar): the fallback")
        try expect(WhatsNew.anchor(icon: CGRect(x: 1298, y: 949, width: 0, height: 0), screens: screens) == nil,
                   "a zero-size frame: the fallback")
        try expect(WhatsNew.anchor(icon: nil, screens: screens) == nil, "hidden: the fallback")

        for v in [main.visible, narrow.visible, CGRect(x: 0, y: 0, width: 300, height: 200)] {
            let w: CGFloat = WhatsNew.width(visible: v)
            let room: CGFloat = v.width - 16
            try expect(w <= WhatsNew.width && w <= room + 0.001, "width \(w) fits \(v.width)")
            let size = CGSize(width: w, height: 333)
            let top = WhatsNew.placement(size: size, icon: nil, visible: v)
            try expect(top.arrowX == nil, "the fallback has no arrow")
            try expect(top.frame.minX >= v.minX && top.frame.maxX <= v.maxX, "fallback inside \(v): \(top.frame)")
            try expect(top.frame.minY >= v.minY, "never below the screen: \(top.frame)")
            if v.height >= 333 + 10 { try expect(top.frame.maxY <= v.maxY, "under the top: \(top.frame)") }
        }
        try expect(WhatsNew.width(visible: main.visible) == WhatsNew.width, "the design's width where it fits")
        try expect(WhatsNew.width(visible: narrow.visible) == 384, "a 400 pt screen: 384")
        let fallback = WhatsNew.placement(size: CGSize(width: 460, height: 333), icon: nil, visible: main.visible)
        let right: CGFloat = main.visible.maxX - fallback.frame.maxX
        let below: CGFloat = main.visible.maxY - fallback.frame.maxY
        try expect(right == 12 && below == 10, "the fallback: 12 pt from the right, 10 pt from the top \(fallback.frame)")
        let under = WhatsNew.placement(size: CGSize(width: 460, height: 333), icon: icon, visible: main.visible)
        let belowIcon: Bool = under.frame.maxY <= icon.minY
        let onScreen: Bool = under.frame.minX >= main.visible.minX && under.frame.maxX <= main.visible.maxX
        try expect(belowIcon && onScreen, "under the icon, inside the screen \(under.frame)")
        if let x = under.arrowX {
            let off: CGFloat = under.frame.minX + x - icon.midX
            try expect(abs(off) < 0.5, "the arrow points at the icon")
        } else {
            try expect(false, "an arrow under the icon")
        }
    }
    check("whatsNewPlacement", whatsNewPlacement)

    func whatsNewPreviewFollowsTheMachine() throws {
        // Finding 4.
        let calm = PowerInputs()
        try expect(WhatsNew.preview(calm) == .live, "live")
        var low = calm
        low.lowPowerMode = true
        try expect(WhatsNew.preview(low) == .still, "Low Power Mode: a still")
        low.lowPowerAnimates = true
        try expect(WhatsNew.preview(low) == .live, "Low Power Mode, kept animating in Settings: live")
        var hot = calm
        hot.thermal = .critical
        try expect(WhatsNew.preview(hot) == .still, "too hot: a still")
        let hidden: [(String, (inout PowerInputs) -> Void)] = [
            ("locked", { $0.screenLocked = true }), ("displays asleep", { $0.displaysAsleep = true }),
            ("screensaver", { $0.screensaverRunning = true }), ("another session", { $0.sessionActive = false }),
        ]
        for (what, change) in hidden {
            var i = calm
            change(&i)
            try expect(WhatsNew.preview(i) == .stopped, "\(what): stops drawing")
            i.lowPowerMode = true
            try expect(WhatsNew.preview(i) == .stopped, "\(what) in Low Power Mode: stops drawing")
        }
        var paused = calm
        paused.userPaused = true
        paused.anyWindowVisible = false
        try expect(WhatsNew.preview(paused) == .live, "a paused or covered desktop doesn't stop a card being read")
    }
    check("whatsNewPreviewFollowsTheMachine", whatsNewPreviewFollowsTheMachine)

    func whatsNewStillFramesAButterflyAndABloom() throws {
        // Finding 7: for each line-up, a whole butterfly with open wings, most of a bloom, no other butterfly cut,
        // at the live preview's own cell size.
        let preview = CGSize(width: WhatsNew.width - 32, height: 150)
        let area: CGSize = WhatsNew.stillArea(preview)
        let cell: CGSize = GridSpec.cell(forWidth: area.width)
        try expect(cell == GridSpec.cell(forWidth: preview.width), "the still's cell is the live preview's: \(cell)")
        let narrow = CGSize(width: 384 - 32, height: 150)
        try expect(GridSpec.cell(forWidth: WhatsNew.stillArea(narrow).width) == GridSpec.cell(forWidth: narrow.width),
                   "on a narrow screen too")
        let started = Date()
        for lineUp in MeadowLineUp.all {
            var s = Settings.defaults
            lineUp.apply(to: &s)
            s.habitat = .meadow
            guard let pick = WhatsNew.stillFrame(s, preview: preview, cell: cell) else {
                try expect(false, "\(lineUp.title): a frame")
                continue
            }
            let f = pick.frame
            let c: CGRect = f.crop
            let inMeadow: Bool = c.minX >= 0 && c.minY >= 0 && c.maxX <= area.width && c.maxY <= area.height
            try expect(inMeadow, "\(lineUp.title): inside the meadow \(c)")
            try expect(c.size == preview, "\(lineUp.title): the preview's size")
            try expect(f.cut == 0, "\(lineUp.title): no butterfly cut at the edge (\(f.cut))")
            try expect(f.kind != .white || lineUp.butterflies == [.white], "\(lineUp.title): a bold butterfly, not the pale white (\(f.kind.name))")
            // Check the frame against the world itself, laid out again from its seed.
            let world: MeadowWorld = WhatsNew.stillWorld(s, seed: pick.seed, area: area, cell: cell)
            guard let b = world.flies.first(where: { $0.id == f.butterfly }) else {
                try expect(false, "\(lineUp.title): its butterfly is there again")
                continue
            }
            let e = WhatsNew.extent(b, in: world)
            let cx0: Double = Double(c.minX), cx1: Double = Double(c.maxX), cy0: Double = Double(c.minY), cy1: Double = Double(c.maxY)
            let wholeAcross: Bool = b.x - e.x >= cx0 && b.x + e.x <= cx1
            let wholeDown: Bool = b.y - e.y >= cy0 && b.y + e.y <= cy1
            try expect(wholeAcross && wholeDown, "\(lineUp.title): the \(b.sp.kind.name) whole in the crop")
            try expect(WhatsNew.openness(b) >= 0.6, "\(lineUp.title): wings open (\(WhatsNew.openness(b)))")
            let bloom: Bool = world.flowers.all.contains { fl in
                let r: Double = fl.radius * 1.12 * 0.6
                let x: Double = fl.x + fl.ox, y: Double = fl.y + fl.oy
                let across: Bool = x - r >= cx0 && x + r <= cx1
                let down: Bool = y - r >= cy0 && y + r <= cy1
                return !fl.fading && across && down
            }
            try expect(bloom, "\(lineUp.title): most of a bloom in the crop")
            print("    \(lineUp.title): seed \(pick.seed), a \(f.kind.name), \(f.flowersInside) whole blooms, \(f.cutBlooms) cut")
        }
        let took: Double = Date().timeIntervalSince(started)
        print("    three line-ups framed in \(String(format: "%.2f", took)) s")
    }
    check("whatsNewStillFramesAButterflyAndABloom", whatsNewStillFramesAButterflyAndABloom)
}

/// t11: the live preview's evidence (the card's drawn check and why it went, `EnergyLog.cardDrawn`, `cardClosed`) and
/// the test copy's readings in the run loop's common modes (`CommonTimer`), so an open menu no longer pauses them.
func cardDrawnChecks() {
    let root: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func source(_ path: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    func cardDrawnLogShapes() throws {
        // energy.sh's selftest parses these exact lines; a change here must change it too.
        let drawn: String = EnergyLog.cardDrawn(pid: 501, launch: "0a1b2c3d4e5f6789", share: 0.97666, width: 460, height: 333)
        try expect(drawn == "energy-card: pid=501 launch=0a1b2c3d4e5f6789 drawn=0.977 size=460x333", drawn)
        let empty: String = EnergyLog.cardDrawn(pid: 501, launch: nil, share: 0, width: 460, height: 333)
        try expect(empty == "energy-card: pid=501 launch=none drawn=0.000 size=460x333", empty)
        let wild: String = EnergyLog.cardDrawn(pid: 501, launch: nil, share: Double.nan, width: 1, height: 1)
        try expect(wild.contains(" drawn=0.000 "), "a share that is not a number logs as 0: \(wild)")
        let over: String = EnergyLog.cardDrawn(pid: 501, launch: nil, share: 1.5, width: 1, height: 1)
        try expect(over.contains(" drawn=1.000 "), "a share over 1 logs as 1: \(over)")
        let closed: String = EnergyLog.cardClosed(pid: 501, launch: "0a1b2c3d4e5f6789", reason: .click, after: 41.4)
        try expect(closed == "energy-card: pid=501 launch=0a1b2c3d4e5f6789 closed=click after=41s", closed)
        let reasons: [String] = WhatsNew.CloseReason.allCases.map { (r: WhatsNew.CloseReason) -> String in r.rawValue }
        let wordy: Bool = reasons.allSatisfy { (r: String) -> Bool in
            !r.isEmpty && r.unicodeScalars.allSatisfy { (c: Unicode.Scalar) -> Bool in (c >= "a" && c <= "z") || c == "-" }
        }
        try expect(wordy && Set(reasons).count == reasons.count, "close reasons are distinct lowercase words: \(reasons)")
        let energy: String = source("Tools/energy.sh")
        try expect(energy.contains("drawn=0.977 size=460x333") && energy.contains("closed=click after=1s"),
                   "energy.sh's selftest uses the same drawn and closed shapes")
    }
    check("cardDrawnLogShapes", cardDrawnLogShapes)

    func cardDrawnShare() throws {
        let clear: [UInt8] = [UInt8](repeating: 0, count: 4 * 100)
        try expect(WhatsNew.drawnShare(rgba: clear) == 0, "a transparent bitmap: nothing drawn")
        try expect(WhatsNew.drawnShare(rgba: []) == 0, "an empty bitmap: nothing drawn")
        var quarter: [UInt8] = clear
        for i in 0..<25 { quarter[i * 4 + 3] = 255 }
        try expect(WhatsNew.drawnShare(rgba: quarter) == 0.25, "a quarter opaque: \(WhatsNew.drawnShare(rgba: quarter))")
        var faint: [UInt8] = clear
        for i in 0..<100 { faint[i * 4 + 3] = 8 }
        try expect(WhatsNew.drawnShare(rgba: faint) == 0, "alpha at the threshold (8 of 255) does not count")
        var colourOnly: [UInt8] = clear
        for i in 0..<100 { colourOnly[i * 4] = 255; colourOnly[i * 4 + 1] = 255 }
        try expect(WhatsNew.drawnShare(rgba: colourOnly) == 0, "colour with no alpha is not drawn")
    }
    check("cardDrawnShare", cardDrawnShare)

    func cardPreviewWiring() throws {
        let card: String = source("Sources/ASCIIAnimals/WhatsNewCard.swift")
        try expect(card.contains("if preview { watchPreview(session) }"), "the live preview measures and watches the card it opened")
        try expect(card.contains("EnergyLog.cardDrawn(pid: pid, launch: launch"), "the preview logs the drawn line with its launch id")
        try expect(card.contains("EnergyLog.cardClosed(pid: pid, launch: launch"), "the preview logs why the card went")
        // Every way the card goes names its reason (the probe's and a failed opening's teardown need none).
        let reasons: [String] = ["reason: .click", "reason: .ownClick", "reason: .screens", "reason: .esc", "reason: .meadow",
                                 "reason: .tryMeadow", "reason: .keep", "reason: .welcome"]
        for r in reasons { try expect(card.contains(r), "a close with \(r)") }
        let energy: String = source("Tools/energy.sh")
        try expect(energy.contains("launch_test 0 1 0 preview bg") && energy.contains("exec open ${5:+-g} "),
                   "the preview opens the test copy in the background (the director answers without a click)")
        try expect(energy.contains("card_drawn_check \"$APPLOG\" \"$TEST_PID\" \"$LAUNCH_ID\""), "the preview checks the drawn line before asking")
    }
    check("cardPreviewWiring", cardPreviewWiring)

    func readingTimerCommonModes() throws {
        // A stand-in for AppKit's event-tracking mode (a menu open): a mode of its own, made common.
        let loop: RunLoop = RunLoop.current
        let tracking = RunLoop.Mode("OceanChecks.tracking")
        CFRunLoopAddCommonMode(loop.getCFRunLoop(), CFRunLoopMode(tracking.rawValue as CFString))
        var common = 0, plain = 0
        let a: Timer = CommonTimer.repeating(every: 0.01, on: loop) { (_: Timer) in common += 1 }
        let b = Timer(timeInterval: 0.01, repeats: true) { (_: Timer) in plain += 1 }
        loop.add(b, forMode: .default)
        let until: Date = Date().addingTimeInterval(0.2)
        while Date() < until { _ = loop.run(mode: tracking, before: until) }
        a.invalidate()
        b.invalidate()
        try expect(common >= 3, "a common-mode timer fires while the loop tracks (\(common) times)")
        try expect(plain == 0, "a default-mode timer waits while the loop tracks (\(plain) times): the old gap")
        let app: String = source("Sources/ASCIIAnimals/main.swift")
        try expect(app.contains("frameMeter = CommonTimer.repeating(every: 5)"), "the test copy's readings use the common modes")
    }
    check("readingTimerCommonModes", readingTimerCommonModes)
}
