import Foundation

/// Which world the wallpaper shows.
public enum HabitatKind: String, Codable, CaseIterable, Sendable {
    case ocean, web, meadow

    /// The habitats the app offers (menu, Settings, welcome). The Meadow is not offered yet: OceanTool runs it.
    public static let offered: [HabitatKind] = [.ocean, .web]

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
