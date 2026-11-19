import Foundation
import OceanKit

/// Settings persisted in UserDefaults as tolerant JSON.
final class SettingsStore {
    static let key = "settings.v2"
    private let defaults = UserDefaults.standard
    var onChange: ((_ old: Settings, _ new: Settings) -> Void)?

    private(set) var settings: Settings

    init() {
        settings = SettingsCodec.decode(defaults.data(forKey: SettingsStore.key))
    }

    func update(_ body: (inout Settings) -> Void) {
        let old = settings
        var s = settings
        body(&s)
        s = s.sanitized()
        guard s != old else { return }
        settings = s
        defaults.set(SettingsCodec.encode(s), forKey: SettingsStore.key)
        onChange?(old, s)
    }
}
