import Foundation

/// What is true about ASCII Sharks on this Mac when ASCII Animals starts.
public struct HandoverFacts: Equatable {
    public var sharksApp: URL?
    public var sharksRunning: Bool
    public var alreadyImported: Bool
    public var sharksSettings: Data?
    public init(sharksApp: URL?, sharksRunning: Bool, alreadyImported: Bool, sharksSettings: Data?) {
        self.sharksApp = sharksApp
        self.sharksRunning = sharksRunning
        self.alreadyImported = alreadyImported
        self.sharksSettings = sharksSettings
    }
}

public enum HandoverStep: Equatable {
    case quitSharks, importSettings, skipWelcome, offerTrash(URL)
}

/// First-launch hand-over from ASCII Sharks: quit it, take its settings, offer to trash it.
public enum Handover {
    public static let sharksBundleID = "local.ascii-sharks.wallpaper"

    public static func plan(_ f: HandoverFacts) -> [HandoverStep] {
        guard f.sharksRunning || f.sharksApp != nil else { return [] }
        var steps: [HandoverStep] = []
        if f.sharksRunning { steps.append(.quitSharks) }
        if !f.alreadyImported, f.sharksSettings != nil { steps += [.importSettings, .skipWelcome] }
        if let app = f.sharksApp { steps.append(.offerTrash(app)) }
        return steps
    }
}
