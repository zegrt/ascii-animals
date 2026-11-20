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
    /// ⌃⌥⌘P toggles pause from anywhere.
    public var pauseShortcut = true
    public var showMenuBarIcon = true
    public var checkForUpdates = true
    /// Install a new version as soon as it's found, then restart.
    public var autoInstallUpdates = true
    public var paused = false
    public var habitat: HabitatKind = .ocean
    public var webSpiders: [SpiderKind] = SpiderKind.defaultCast
    public var webFlies = true
    public var webJumper = true
    /// The Meadow's species that are on, in `ButterflyKind` order (at least one).
    public var meadowButterflies: [ButterflyKind] = ButterflyKind.allCases
    /// How many butterflies on a laptop screen, 1…12; a bigger display gets more by area (`MeadowTuning.areaCount`).
    public var meadowCount = 7
    /// The Meadow has been picked once: its "New" tag in the menu goes.
    public var meadowTried = false

    public static let defaults = Settings()
    public static let maxSharks = 8
    public static let maxSpiders = 8
    public static let fpsOptions = [15, 30, 60]
    public static let meadowCountRange = 1...12

    public init() {}

    public func sanitized() -> Settings {
        var s = self
        s.fishDensity = min(2.0, max(0.5, fishDensity.isFinite ? fishDensity : 1))
        s.speed = min(1.5, max(0.5, speed.isFinite ? speed : 1))
        // Nearest option; ties go up.
        s.fps = Settings.fpsOptions.min { abs($0 - fps) < abs($1 - fps) || (abs($0 - fps) == abs($1 - fps) && $0 > $1) }!
        s.sharks = Array(sharks.prefix(Settings.maxSharks))
        if s.sharks.isEmpty { s.sharks = Settings.defaults.sharks }
        s.webSpiders = Array(webSpiders.prefix(Settings.maxSpiders))
        if s.webSpiders.isEmpty { s.webSpiders = SpiderKind.defaultCast }
        // Each species once, in order; none on is the default line-up (at least one stays on).
        s.meadowButterflies = ButterflyKind.allCases.filter { meadowButterflies.contains($0) }
        if s.meadowButterflies.isEmpty { s.meadowButterflies = Settings.defaults.meadowButterflies }
        s.meadowCount = min(Settings.meadowCountRange.upperBound, max(Settings.meadowCountRange.lowerBound, meadowCount))
        if s.habitat == .meadow { s.meadowTried = true }
        return s
    }

    private enum K: String, CodingKey {
        case sharks, fishDensity, speed, appearance, calm, grid, wakeColor, interaction, sharedOcean, fps, lowPowerAnimates, matchSystemWallpaper, pauseShortcut, showMenuBarIcon, checkForUpdates, autoInstallUpdates, paused, habitat, webSpiders, webFlies, webJumper
        case meadowButterflies, meadowCount, meadowTried
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
        if let raw = (try? c.decodeIfPresent([String].self, forKey: .webSpiders)) ?? nil {
            webSpiders = raw.compactMap(SpiderKind.init(rawValue:))
        } else {
            webSpiders = d.webSpiders
        }
        if let raw = (try? c.decodeIfPresent(String.self, forKey: .habitat)) ?? nil {
            habitat = HabitatKind(rawValue: raw) ?? d.habitat
        } else {
            habitat = d.habitat
        }
        if let raw = (try? c.decodeIfPresent([String].self, forKey: .meadowButterflies)) ?? nil {
            meadowButterflies = raw.compactMap(ButterflyKind.init(key:))
        } else {
            meadowButterflies = d.meadowButterflies
        }
        meadowCount = get(.meadowCount, d.meadowCount)
        meadowTried = get(.meadowTried, d.meadowTried)
        webFlies = get(.webFlies, d.webFlies)
        webJumper = get(.webJumper, d.webJumper)
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
        pauseShortcut = get(.pauseShortcut, d.pauseShortcut)
        showMenuBarIcon = get(.showMenuBarIcon, d.showMenuBarIcon)
        checkForUpdates = get(.checkForUpdates, d.checkForUpdates)
        autoInstallUpdates = get(.autoInstallUpdates, d.autoInstallUpdates)
        paused = get(.paused, d.paused)
    }
}

/// Saved by name ("monarch", "morpho", "swallowtail", "white"); an unknown name is dropped by `Settings`.
extension ButterflyKind: Codable {
    public var key: String {
        switch self {
        case .monarch: return "monarch"
        case .morpho: return "morpho"
        case .swallowtail: return "swallowtail"
        case .white: return "white"
        }
    }

    public init?(key: String) {
        guard let k = ButterflyKind.allCases.first(where: { $0.key == key }) else { return nil }
        self = k
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let k = ButterflyKind(key: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown butterfly \(raw)"))
        }
        self = k
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(key)
    }
}

/// A ready-made Meadow line-up: which species, and how many on a laptop screen (the director's three, d1).
public struct MeadowLineUp: Equatable, Sendable {
    public let title: String
    public let butterflies: [ButterflyKind]
    public let count: Int

    public init(title: String, butterflies: [ButterflyKind], count: Int) {
        self.title = title
        self.butterflies = butterflies
        self.count = count
    }

    /// "Mixed" is the default (the director's tuned mix); then "Just a Few" and "Blue Morphos".
    public static let all: [MeadowLineUp] = [
        MeadowLineUp(title: "Mixed", butterflies: ButterflyKind.allCases, count: 7),
        MeadowLineUp(title: "Just a Few", butterflies: [.monarch, .morpho, .white], count: 3),
        MeadowLineUp(title: "Blue Morphos", butterflies: [.morpho], count: 5),
    ]

    /// The line-up these settings show, or nil (Custom).
    public static func matching(_ s: Settings) -> MeadowLineUp? {
        all.first { $0.butterflies == s.meadowButterflies && $0.count == s.meadowCount }
    }

    /// Puts this line-up's species and count into the settings.
    public func apply(to s: inout Settings) {
        s.meadowButterflies = butterflies
        s.meadowCount = count
    }

    /// How a fresh meadow shares `count` among the species on (the sketch's `syncFlies` at load, html:1386–1446):
    /// evenly, the odd ones to the first species in order. Species that get none are left out.
    public static func shares(_ on: [ButterflyKind], count: Int) -> [(kind: ButterflyKind, count: Int)] {
        guard !on.isEmpty, count > 0 else { return [] }
        let base: Int = count / on.count
        let extra: Int = count - base * on.count
        var out: [(kind: ButterflyKind, count: Int)] = []
        for (i, k) in on.enumerated() {
            let n: Int = base + (i < extra ? 1 : 0)
            if n > 0 { out.append((kind: k, count: n)) }
        }
        return out
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
