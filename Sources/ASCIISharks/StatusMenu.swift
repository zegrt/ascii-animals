import AppKit
import OceanKit

/// The menu bar item. (Task 6: minimal; Task 7 completes it.)
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
        super.init()
        if let image = NSImage(systemSymbolName: "fish", accessibilityDescription: "ASCII Sharks") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "≈"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let e = app.startupError ?? app.director?.lastError {
            let err = NSMenuItem(title: "Error: \(e)", action: nil, keyEquivalent: "")
            err.isEnabled = false
            menu.addItem(err)
            menu.addItem(.separator())
        }
        let pause = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = app.store.settings.paused ? .on : .off
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ASCII Sharks", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func togglePause() { app.store.update { $0.paused.toggle() } }
}
