import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// The energy-test copy never registers or removes a login item: one would outlive the run.
    static func set(_ on: Bool) throws {
        guard Launch.plan.changesLoginItem else { throw Refused() }
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    struct Refused: LocalizedError {
        var errorDescription: String? { "The energy-test copy doesn't open at login." }
    }
}
