import AppKit
import OceanKit

/// The menu bar item: a status line, quick choices, and the way to Settings.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private unowned let app: AppDelegate

    private static let appearances: [(Appearance, String, String)] = [
        (.dark, "Dark", "moon"),
        (.light, "Light", "sun.max"),
        (.system, "Match System", "circle.lefthalf.filled"),
    ]

    init(app: AppDelegate) {
        self.app = app
        super.init()
        if let image = NSImage(systemSymbolName: "fish", accessibilityDescription: "ASCII Sharks") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "≈"
        }
        item.button?.toolTip = "ASCII Sharks"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    // MARK: Building

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = app.store.settings

        let status = OceanStatus.make(settings: s, mode: app.director?.mode, inputs: app.signals.inputs,
                                      error: app.startupError ?? app.director?.lastError)
        menu.addItem(statusItem(status))
        menu.addItem(.separator())

        let pause = add(menu, s.paused ? "Resume" : "Pause", #selector(togglePause),
                        symbol: s.paused ? "play.fill" : "pause.fill", key: "p")
        pause.toolTip = s.paused ? "Start the ocean moving again." : "Hold the ocean still. It stays paused until you resume."

        menu.addItem(.separator())

        let sharks = NSMenu()
        sharks.addItem(header("Line-Ups"))
        for (i, p) in Presets.all.enumerated() {
            let it = add(sharks, p.title, #selector(pickPreset(_:)), state: p.sharks == s.sharks, tag: i)
            if i < 9 { it.keyEquivalent = "\(i + 1)" }
            subtitle(it, p.sharks.map(Presets.title).joined(separator: ", "))
        }
        if Presets.matching(s.sharks) == nil {
            let custom = add(sharks, "Your Line-Up", nil, state: true)
            subtitle(custom, s.sharks.map(Presets.title).joined(separator: ", "))
        }
        sharks.addItem(.separator())
        add(sharks, "Edit Line-Up…", #selector(openSettings), symbol: "slider.horizontal.3")
        submenu(menu, "Sharks", symbol: "water.waves", sharks)

        let look = NSMenu()
        look.addItem(header("Appearance"))
        for (i, a) in Self.appearances.enumerated() {
            add(look, a.1, #selector(pickAppearance(_:)), symbol: a.2, state: s.appearance == a.0, tag: i)
        }
        look.addItem(.separator())
        look.addItem(header("Wake"))
        add(look, "Cyan", #selector(pickWake(_:)), state: s.wakeColor == .cyan, tag: 0)
        add(look, "Accent Colour", #selector(pickWake(_:)), state: s.wakeColor == .accent, tag: 1)
        look.addItem(.separator())
        add(look, "Calm", #selector(toggleCalm), state: s.calm)
        add(look, "Grid", #selector(toggleGrid), state: s.grid)
        submenu(menu, "Appearance", symbol: "paintpalette", look)

        let shared = add(menu, "One Ocean Across Displays", #selector(toggleSharedOcean),
                         symbol: "rectangle.split.2x1", state: s.sharedOcean)
        shared.toolTip = NSScreen.screens.count > 1
            ? "Sharks swim from one display to the next."
            : "Takes effect when you connect another display."

        menu.addItem(.separator())
        add(menu, "Settings…", #selector(openSettings), symbol: "gearshape", key: ",")
        add(menu, "Restore Original Wallpaper", #selector(restoreWallpaper), symbol: "photo.on.rectangle")
            .toolTip = "Put your own wallpaper back and stop matching the lock screen."
        add(menu, "Open at Login", #selector(toggleLogin), state: LoginItem.isEnabled)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ASCII Sharks", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = symbol("power")
        menu.addItem(quit)
    }

    /// "● Swimming · 30 fps": the first line, which can't be chosen.
    private func statusItem(_ status: OceanStatus) -> NSMenuItem {
        let it = NSMenuItem(title: status.line, action: nil, keyEquivalent: "")
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(string: status.title, attributes: [
            .font: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        if !status.detail.isEmpty {
            title.append(NSAttributedString(string: (status.tone == .live ? " · " : " — ") + status.detail, attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        it.attributedTitle = title
        it.image = Self.dot(status.color)
        it.isEnabled = false
        return it
    }

    private static func dot(_ color: NSColor) -> NSImage {
        // Same footprint as an SF Symbol so the title lines up with the items below.
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 8, height: 8)).fill()
            return true
        }
        image.accessibilityDescription = "Status"
        return image
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?, symbol name: String? = nil,
                     key: String = "", state: Bool = false, tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = action == nil ? nil : self
        i.state = state ? .on : .off
        i.tag = tag
        if let name { i.image = symbol(name) }
        if action == nil { i.isEnabled = false }
        menu.addItem(i)
        return i
    }

    private func submenu(_ menu: NSMenu, _ title: String, symbol name: String, _ sub: NSMenu) {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.image = symbol(name)
        it.submenu = sub
        menu.addItem(it)
    }

    private func header(_ title: String) -> NSMenuItem { NSMenuItem.sectionHeader(title: title) }

    private func subtitle(_ item: NSMenuItem, _ text: String) {
        if #available(macOS 14.4, *), !text.isEmpty { item.subtitle = text }
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    // MARK: Actions

    @objc private func togglePause() { app.store.update { $0.paused.toggle() } }
    @objc private func toggleCalm() { app.store.update { $0.calm.toggle() } }
    @objc private func toggleGrid() { app.store.update { $0.grid.toggle() } }
    @objc private func toggleSharedOcean() { app.store.update { $0.sharedOcean.toggle() } }
    @objc private func pickPreset(_ i: NSMenuItem) { app.store.update { $0.sharks = Presets.all[i.tag].sharks } }
    @objc private func pickAppearance(_ i: NSMenuItem) { app.store.update { $0.appearance = Self.appearances[i.tag].0 } }
    @objc private func pickWake(_ i: NSMenuItem) { app.store.update { $0.wakeColor = i.tag == 0 ? .cyan : .accent } }
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

    /// Settings changed (and once at launch): e.g. show or hide the menu-bar icon.
    func apply(_ s: OceanKit.Settings) {}
}
