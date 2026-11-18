import AppKit
import OceanKit

/// The menu bar item.
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

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?, key: String = "", state: Bool = false, tag: Int = 0) {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = action == nil ? nil : self
        i.state = state ? .on : .off
        i.tag = tag
        if action == nil { i.isEnabled = false }
        menu.addItem(i)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = app.store.settings
        if let e = app.startupError ?? app.director?.lastError {
            add(menu, "Error: \(e)", nil)
            menu.addItem(.separator())
        }
        add(menu, "Pause", #selector(togglePause), state: s.paused)

        let sharks = NSMenu()
        for (i, p) in Presets.all.enumerated() { add(sharks, p.title, #selector(pickPreset(_:)), state: p.sharks == s.sharks, tag: i) }
        sharks.addItem(.separator())
        add(sharks, "Custom…", #selector(openSettings))
        let sharksItem = NSMenuItem(title: "Sharks", action: nil, keyEquivalent: "")
        sharksItem.submenu = sharks
        menu.addItem(sharksItem)

        let look = NSMenu()
        for (i, a) in [(Appearance.dark, "Dark"), (.light, "Light"), (.system, "Match System")].enumerated() {
            add(look, a.1, #selector(pickAppearance(_:)), state: s.appearance == a.0, tag: i)
        }
        look.addItem(.separator())
        add(look, "Calm", #selector(toggleCalm), state: s.calm)
        let lookItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        lookItem.submenu = look
        menu.addItem(lookItem)

        menu.addItem(.separator())
        add(menu, "Settings…", #selector(openSettings), key: ",")
        add(menu, "Restore Original Wallpaper", #selector(restoreWallpaper))
        add(menu, "Open at Login", #selector(toggleLogin), state: LoginItem.isEnabled)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ASCII Sharks", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func togglePause() { app.store.update { $0.paused.toggle() } }
    @objc private func toggleCalm() { app.store.update { $0.calm.toggle() } }
    @objc private func pickPreset(_ i: NSMenuItem) { app.store.update { $0.sharks = Presets.all[i.tag].sharks } }
    @objc private func pickAppearance(_ i: NSMenuItem) {
        app.store.update { $0.appearance = [Appearance.dark, .light, .system][i.tag] }
    }
    @objc private func openSettings() { app.showSettings() }
    @objc private func restoreWallpaper() {
        // Stop matching too, or the still would come straight back.
        app.store.update { $0.matchSystemWallpaper = false }
        app.wallpaper?.restoreAll()
    }
    @objc private func toggleLogin() {
        do { try LoginItem.set(!LoginItem.isEnabled) } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }
}
