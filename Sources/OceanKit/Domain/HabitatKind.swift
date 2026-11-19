import Foundation

/// Which world the wallpaper shows.
public enum HabitatKind: String, Codable, CaseIterable, Sendable {
    case ocean, web

    /// The name people see: "Ocean", "Web".
    public var title: String {
        switch self {
        case .ocean: return "Ocean"
        case .web: return "Web"
        }
    }
}

// SpiderKind lives with the spiders, in Web/Spider.swift.
