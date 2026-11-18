import Foundation

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    static let company = "Xero Works Pvt Ltd"
    static let copyright = "© 2026 Xero Works Pvt Ltd"
    static let repoURL = URL(string: "https://github.com/zegrt/ascii-sharks-wallpaper")!
    static let releasesURL = URL(string: "https://github.com/zegrt/ascii-sharks-wallpaper/releases")!
    static let issuesURL = URL(string: "https://github.com/zegrt/ascii-sharks-wallpaper/issues/new")!
    static let originalURL = URL(string: "https://github.com/stackedlol/ascii-sharks")!
    static let latestAPI = URL(string: "https://api.github.com/repos/zegrt/ascii-sharks-wallpaper/releases/latest")!
}
