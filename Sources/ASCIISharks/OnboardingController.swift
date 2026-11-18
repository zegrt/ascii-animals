import AppKit

/// The immersive first-launch welcome. (Stub — owned by the UI work.)
enum OnboardingController {
    static let seenKey = "onboarded.v1"

    /// First launch only.
    static func showIfNeeded(app: AppDelegate) {
        guard !UserDefaults.standard.bool(forKey: seenKey) else { return }
        show(app: app)
    }

    static func show(app: AppDelegate) {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    /// Debug: render to a PNG (no Screen Recording needed). `--snapshot-onboarding <png>`
    static func snapshot(to url: URL) {}
}
