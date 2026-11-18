import Foundation

/// A dotted version like "2.1" or "v2.10.1". Missing parts count as zero.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]
    public init?(_ s: String) {
        _ = s
        return nil // Task 1
    }
    public var description: String { parts.map(String.init).joined(separator: ".") }
    public static func < (a: AppVersion, b: AppVersion) -> Bool { false }
    public static func == (a: AppVersion, b: AppVersion) -> Bool { a.parts == b.parts }
}

/// The newest published release.
public struct LatestRelease: Equatable, Sendable {
    public var version: AppVersion
    public var tag: String
    public var pageURL: URL
    public var dmgURL: URL?
    public var notes: String
    public static func == (a: LatestRelease, b: LatestRelease) -> Bool { a.tag == b.tag && a.version == b.version }
}

public enum UpdateFeed {
    /// GitHub `releases/latest` JSON.
    public static func parse(_ data: Data) -> LatestRelease? { nil } // Task 1
}

public enum UpdatePolicy {
    public static let interval: TimeInterval = 20 * 3600
    public static func shouldCheck(lastCheck: Date?, now: Date) -> Bool { false } // Task 1
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
    public static func body(_ d: DiagnosticFacts, homePath: String, userName: String) -> String { "" } // Task 2
    public static func url(base: URL, title: String, body: String) -> URL { base } // Task 2
}
