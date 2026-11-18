import AppKit
import OceanKit

/// Checks GitHub for a newer release (stub; Task 1 fills it in).
final class UpdateService {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(LatestRelease)
        case failed(String)
    }

    private(set) var state: State = .idle
    var available: LatestRelease? { if case .available(let r) = state { return r }; return nil }
    /// Called on the main thread whenever `state` changes.
    var onChange: (() -> Void)?

    func start(enabled: @escaping () -> Bool) {}
    func checkNow(userInitiated: Bool) {}
    /// Opens the release page (or the DMG) in the browser.
    func download() {
        if let r = available { NSWorkspace.shared.open(r.dmgURL ?? r.pageURL) } else { NSWorkspace.shared.open(AppInfo.releasesURL) }
    }
}
