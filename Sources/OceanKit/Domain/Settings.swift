import Foundation

public enum SharkKind: String, CaseIterable, Codable, Sendable {
    case classic, hammerhead, tiger, zebra, greathammer, mako, thresher, nurse
    /// Index used by the shaders.
    public var index: Int { SharkKind.allCases.firstIndex(of: self)! }
}

public enum Appearance: String, Codable, CaseIterable, Sendable { case dark, light, system }
public enum WakeColor: String, Codable, CaseIterable, Sendable { case cyan, accent }

/// Everything the user can change. Decoding is tolerant: a missing or bad key
/// keeps its default, unknown species are dropped, and `sanitized()` clamps.
public struct Settings: Codable, Equatable, Sendable {
    public var sharks: [SharkKind] = [.greathammer, .classic, .mako, .tiger]
    public var fishDensity: Double = 1.0
    public var speed: Double = 1.0
    public var appearance: Appearance = .dark
    public var calm = false
    public var grid = true
    public var wakeColor: WakeColor = .cyan
    public var interaction = true
    /// One ocean spanning every display (otherwise one per display).
    public var sharedOcean = true
    public var fps = 30
    public var lowPowerAnimates = false
    public var matchSystemWallpaper = true
    public var paused = false

    public static let defaults = Settings()
    public static let maxSharks = 8
    public static let fpsOptions = [15, 30, 60]

    public init() {}

    public func sanitized() -> Settings {
        var s = self
        s.fishDensity = min(2.0, max(0.5, fishDensity.isFinite ? fishDensity : 1))
        s.speed = min(1.5, max(0.5, speed.isFinite ? speed : 1))
        // Nearest option; ties go up.
        s.fps = Settings.fpsOptions.min { abs($0 - fps) < abs($1 - fps) || (abs($0 - fps) == abs($1 - fps) && $0 > $1) }!
        s.sharks = Array(sharks.prefix(Settings.maxSharks))
        if s.sharks.isEmpty { s.sharks = Settings.defaults.sharks }
        return s
    }

    private enum K: String, CodingKey {
        case sharks, fishDensity, speed, appearance, calm, grid, wakeColor, interaction, sharedOcean, fps, lowPowerAnimates, matchSystemWallpaper, paused
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        func get<T: Decodable>(_ k: K, _ d: T) -> T { ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? d }
        let d = Settings.defaults
        if let raw = (try? c.decodeIfPresent([String].self, forKey: .sharks)) ?? nil {
            sharks = raw.compactMap(SharkKind.init(rawValue:))
        } else {
            sharks = d.sharks
        }
        fishDensity = get(.fishDensity, d.fishDensity)
        speed = get(.speed, d.speed)
        appearance = get(.appearance, d.appearance)
        calm = get(.calm, d.calm)
        grid = get(.grid, d.grid)
        wakeColor = get(.wakeColor, d.wakeColor)
        interaction = get(.interaction, d.interaction)
        sharedOcean = get(.sharedOcean, d.sharedOcean)
        fps = get(.fps, d.fps)
        lowPowerAnimates = get(.lowPowerAnimates, d.lowPowerAnimates)
        matchSystemWallpaper = get(.matchSystemWallpaper, d.matchSystemWallpaper)
        paused = get(.paused, d.paused)
    }
}

public enum SettingsCodec {
    public static func decode(_ data: Data?) -> Settings {
        guard let data, let s = try? JSONDecoder().decode(Settings.self, from: data) else { return .defaults }
        return s.sanitized()
    }

    public static func encode(_ s: Settings) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return (try? e.encode(s)) ?? Data("{}".utf8)
    }
}
