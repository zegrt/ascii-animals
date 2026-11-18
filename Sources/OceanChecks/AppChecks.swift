import Foundation
import OceanKit

/// Shape of GitHub's releases/latest payload (fields we read), from the real v2.1 release.
private let latestJSON = #"""
{"tag_name":"v2.1","name":"ASCII Sharks 2.1 — one ocean across your displays","draft":false,"prerelease":false,
 "html_url":"https://github.com/zegrt/ascii-sharks-wallpaper/releases/tag/v2.1",
 "body":"### New in 2.1\n- One ocean across your displays.",
 "assets":[{"name":"notes.txt","browser_download_url":"https://example.com/notes.txt"},
           {"name":"ASCII-Sharks.dmg","browser_download_url":"https://github.com/zegrt/ascii-sharks-wallpaper/releases/download/v2.1/ASCII-Sharks.dmg"}]}
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
        try expect(r.dmgURL?.lastPathComponent == "ASCII-Sharks.dmg", "dmg \(String(describing: r.dmgURL))")
        try expect(r.pageURL.absoluteString.hasSuffix("/tag/v2.1"), "page")
        try expect(r.notes.contains("One ocean"), "notes")
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
        let f = facts(log: ["still failed: /Users/jane/Library/Application Support/ASCII Sharks/x.png", "hello from jane's mac"])
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
