import Foundation

/// Which world the wallpaper shows.
public enum HabitatKind: String, Codable, CaseIterable, Sendable { case ocean, web }

public enum SpiderKind: String, Codable, CaseIterable, Sendable {
    case araneus, argiope, nephila

    /// The original ascii-spiders `DEFAULT_SPIDERS`, bottom-left first.
    public static let defaultCast: [SpiderKind] = [.araneus, .nephila, .argiope, .nephila, .araneus, .argiope]
}
