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

    /// The snapshots' settings: the saved ones, with `ASCII_ANIMALS_SNAPSHOT_HABITAT=ocean|web` picking the habitat.
    static func snapshot() -> SettingsStore {
        var s = SettingsStore().settings
        if let h = ProcessInfo.processInfo.environment["ASCII_ANIMALS_SNAPSHOT_HABITAT"].flatMap(HabitatKind.init(rawValue:)) {
            s.habitat = h
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
