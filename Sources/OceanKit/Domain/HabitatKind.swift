import Foundation

/// Which world the wallpaper shows.
public enum HabitatKind: String, Codable, CaseIterable, Sendable {
    case ocean, web, meadow

    /// The habitats the app offers (menu, Settings, welcome), in that order.
    public static let offered: [HabitatKind] = [.ocean, .web, .meadow]

    /// The name people see: "Ocean", "Web", "Meadow".
    public var title: String {
        switch self {
        case .ocean: return "Ocean"
        case .web: return "Web"
        case .meadow: return "Meadow"
        }
    }
}

// SpiderKind lives with the spiders, in Web/Spider.swift.
