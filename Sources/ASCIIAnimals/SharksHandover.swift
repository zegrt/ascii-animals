import AppKit
import OceanKit

/// First launch after ASCII Sharks: quits it, takes over its settings, offers to trash it.
enum SharksHandover {
    private static let importedKey = "handover.imported"
    private static let offeredKey = "handover.offered"

    /// Synchronous; returns once Sharks has quit (or there was nothing to do).
    /// Must run before `AppDelegate.store` is first touched, so the imported settings are what it loads.
    static func run(app: AppDelegate) {
        let me = UserDefaults.standard
        let id = Handover.sharksBundleID
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        let facts = HandoverFacts(
            sharksApp: me.bool(forKey: offeredKey) ? nil : installed,
            sharksRunning: !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty,
            alreadyImported: me.bool(forKey: importedKey),
            sharksSettings: UserDefaults(suiteName: id)?.data(forKey: SettingsStore.key))
        for step in Handover.plan(facts) {
            switch step {
            case .quitSharks: quitSharks()
            case .importSettings:
                if let data = facts.sharksSettings { me.set(data, forKey: SettingsStore.key) }
                me.set(true, forKey: importedKey)
            case .skipWelcome: me.set(true, forKey: OnboardingController.seenKey)
            case .offerTrash(let url): offerTrash(url)
            }
        }
    }

    private static func running() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Handover.sharksBundleID)
    }

    /// Asks Sharks to quit (it puts the user's own wallpaper back), and never runs alongside it.
    private static func quitSharks() {
        running().forEach { $0.terminate() }
        for _ in 0..<50 where !running().isEmpty { Thread.sleep(forTimeInterval: 0.1) }
        NSApp.activate(ignoringOtherApps: true)
        while !running().isEmpty {
            let alert = NSAlert()
            alert.messageText = "ASCII Sharks is still running"
            alert.informativeText = "Quit it from its 🐟 menu, then click Continue."
            alert.addButton(withTitle: "Continue")
            alert.runModal()
            running().forEach { $0.terminate() }
            for _ in 0..<20 where !running().isEmpty { Thread.sleep(forTimeInterval: 0.1) }
        }
    }

    private static func offerTrash(_ url: URL) {
        UserDefaults.standard.set(true, forKey: offeredKey)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ASCII Animals takes over from ASCII Sharks"
        alert.informativeText = "Your settings came with you. You don't need ASCII Sharks any more, and having both installed is just clutter."
        alert.addButton(withTitle: "Move ASCII Sharks to the Trash")
        alert.addButton(withTitle: "Keep It")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Open ASCII Animals at login"
        alert.suppressionButton?.state = .on
        let trash = alert.runModal() == .alertFirstButtonReturn
        if alert.suppressionButton?.state == .on { try? LoginItem.set(true) }
        if trash { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }
}
