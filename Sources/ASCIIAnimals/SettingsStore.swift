import Foundation
import OceanKit

/// Settings persisted in UserDefaults as tolerant JSON.
final class SettingsStore {
    static let key = "settings.v2"
    private let defaults = UserDefaults.standard
    var onChange: ((_ old: Settings, _ new: Settings) -> Void)?

    private(set) var settings: Settings
    /// False for the snapshots: changes stay in memory.
    private let persists: Bool

    init() {
        settings = SettingsCodec.decode(defaults.data(forKey: SettingsStore.key))
        persists = true
    }

    /// Settings that are never saved (the snapshots).
    init(transient settings: Settings) {
        self.settings = settings.sanitized()
        persists = false
    }

    /// The snapshots' settings: the saved ones, with `ASCII_ANIMALS_SNAPSHOT_HABITAT=ocean|web|meadow` picking the
    /// habitat, `ASCII_ANIMALS_SNAPSHOT_LIGHT=1` the light appearance, and
    /// `ASCII_ANIMALS_SNAPSHOT_BUTTERFLIES=monarch,white:7` the Meadow's species and count (a Custom line-up).
    static func snapshot() -> SettingsStore {
        var s = SettingsStore().settings
        let env = ProcessInfo.processInfo.environment
        if let h = env["ASCII_ANIMALS_SNAPSHOT_HABITAT"].flatMap(HabitatKind.init(rawValue:)) {
            s.habitat = h
        }
        if env["ASCII_ANIMALS_SNAPSHOT_LIGHT"] != nil { s.appearance = .light }
        if let b = env["ASCII_ANIMALS_SNAPSHOT_BUTTERFLIES"] {
            let parts = b.split(separator: ":")
            s.meadowButterflies = parts.first.map { $0.split(separator: ",").compactMap { ButterflyKind(key: String($0)) } } ?? []
            if parts.count > 1, let n = Int(parts[1]) { s.meadowCount = n }
        }
        return SettingsStore(transient: s)
    }

    func update(_ body: (inout Settings) -> Void) {
        let old = settings
        var s = settings
        body(&s)
        s = s.sanitized()
        guard s != old else { return }
        settings = s
        if persists { defaults.set(SettingsCodec.encode(s), forKey: SettingsStore.key) }
        onChange?(old, s)
    }
}
