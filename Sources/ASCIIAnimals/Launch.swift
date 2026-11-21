import Foundation
import OceanKit

/// This copy's identity and launch plan, decided once from its bundle ID (`AppIdentity`, `LaunchPlan`). Every side
/// effect that reaches past the app's own domain and folders asks here: the updater, the hand-over, the uninstaller,
/// the system wallpaper and the login item.
enum Launch {
    static let identity = AppIdentity(bundleID: Bundle.main.bundleIdentifier)
    static let plan = LaunchPlan(identity: identity, environment: ProcessInfo.processInfo.environment)
}
