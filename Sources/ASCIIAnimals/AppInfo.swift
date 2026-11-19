import Foundation

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    /// Brand name: two words, capitals, every time (XERO WORKS brand book).
    static let company = "XERO WORKS"
    /// Legal name, for copyright lines only.
    static let legalName = "XERO WORKS PRIVATE LIMITED"
    static let copyright = "© 2026 XERO WORKS PRIVATE LIMITED"
    static let companyURL = URL(string: "https://xeroworks.org")!
    static let repoURL = URL(string: "https://github.com/zegrt/ascii-animals")!
    static let releasesURL = URL(string: "https://github.com/zegrt/ascii-animals/releases")!
    static let issuesURL = URL(string: "https://github.com/zegrt/ascii-animals/issues/new")!
    static let originalURL = URL(string: "https://github.com/stackedlol/ascii-sharks")!
    static let latestAPI = URL(string: "https://api.github.com/repos/zegrt/ascii-animals/releases/latest")!
}
