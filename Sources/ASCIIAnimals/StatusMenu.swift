import AppKit
import OceanKit

/// The menu bar item: a status line, quick choices, and the way to Settings.
final class StatusMenu: NSObject, NSMenuDelegate {
    /// Made on first use, so the menu snapshot never puts an icon in the menu bar.
    private lazy var item: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private unowned let app: AppDelegate
    /// The snapshot's status line (no director runs there).
    private var statusOverride: OceanStatus?

    private static let appearances: [(Appearance, String, String)] = [
        (.dark, "Dark", "moon"),
        (.light, "Light", "sun.max"),
        (.system, "Match System", "circle.lefthalf.filled"),
    ]

    init(app: AppDelegate) {
        self.app = app
        super.init()
        if let image = NSImage(systemSymbolName: "fish", accessibilityDescription: "ASCII Animals") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "≈"
        }
        item.button?.toolTip = "ASCII Animals"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        app.updates.onChange = { [weak self] in self?.refreshIcon() }
        refreshIcon()
    }

    /// The menu's contents only: no menu bar item, no update watching.
    private init(snapshotOf app: AppDelegate) {
        self.app = app
        super.init()
    }

    /// Debug: write the menu as built for the snapshot settings (`SettingsStore.snapshot()`) to a text file, one item
    /// a line, submenus indented: `--snapshot-menu <txt>`. A menu can't be drawn off screen, so this is its outline:
    /// titles, checkmarks, badges, subtitles, key equivalents and what's disabled.
    static func snapshot(to url: URL) {
        let app = AppDelegate()
        app.store = SettingsStore.snapshot()
        app.arrival = SettingsStore.snapshotArrival()
        let s = app.store.settings
        let m = StatusMenu(snapshotOf: app)
        m.statusOverride = OceanStatus(title: OceanStatus.running(s.habitat), detail: "\(s.fps) fps", tone: .live)
        let menu = NSMenu()
        m.menuNeedsUpdate(menu)
        var lines: [String] = []
        func walk(_ menu: NSMenu, _ depth: Int) {
            let pad = String(repeating: "    ", count: depth)
            for it in menu.items {
                if it.isSeparatorItem { lines.append(pad + "  ---"); continue }
                if it.isSectionHeader { lines.append(pad + "  [\(it.title)]"); continue }
                var line = pad + (it.state == .on ? "✓ " : "  ") + it.title
                if let b = it.badge?.stringValue { line += "  (\(b))" }
                if !it.keyEquivalent.isEmpty { line += "  ⌘\(it.keyEquivalent.uppercased())" }
                if it.submenu != nil { line += "  ▸" }
                if !it.isEnabled && it.submenu == nil { line += "  (disabled)" }
                if #available(macOS 14.4, *), let sub = it.subtitle, !sub.isEmpty { line += "\n" + pad + "      " + sub }
                lines.append(line)
                if let sub = it.submenu { walk(sub, depth + 1) }
            }
        }
        walk(menu, 0)
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        print("wrote \(url.path)")
    }

    /// The icon's frame on screen, for the welcome's "Settings live up here"; nil when hidden.
    var iconScreenFrame: NSRect? {
        guard item.isVisible, let w = item.button?.window, w.isVisible else { return nil }
        return w.frame
    }

    /// The icon's frame for the what's-new card to hang under: as above, and actually showing (`isVisible` can stay
    /// true while the app menu covers the item). The card checks it lies in a menu bar (`WhatsNew.anchor`).
    var iconAnchorFrame: NSRect? {
        guard let f = iconScreenFrame, let w = item.button?.window, w.occlusionState.contains(.visible) else { return nil }
        return f
    }

    /// The crash notice goes once it's been acted on.
    private var crashNoticeDismissed = false

    /// The fish, with a small accent dot while an update waits.
    private func refreshIcon() {
        guard let fish = NSImage(systemSymbolName: "fish", accessibilityDescription: "ASCII Animals") else { return }
        guard app.updates.available != nil || app.updates.installing != nil else {
            fish.isTemplate = true
            item.button?.image = fish
            item.button?.toolTip = "ASCII Animals"
            return
        }
        let size = fish.size
        let badged = NSImage(size: size, flipped: false) { rect in
            // Template-style drawing in the menu bar's own colour, plus a coloured dot.
            // Drawn per draw, so it follows the menu bar's own (wallpaper-dependent) appearance.
            let tint = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor.white : NSColor.black
            let glyph = NSImage(size: size, flipped: false) { r in
                fish.draw(in: r)
                tint.set()
                r.fill(using: .sourceIn)
                return true
            }
            glyph.draw(in: rect)
            let d: CGFloat = 6
            let dot = NSRect(x: rect.maxX - d + 1, y: rect.maxY - d, width: d, height: d)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        badged.isTemplate = false
        badged.accessibilityDescription = "ASCII Animals, update available"
        item.button?.image = badged
        item.button?.toolTip = "ASCII Animals — an update is available"
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === item.menu { OnboardingController.statusMenuOpened() }
    }

    // MARK: Building

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = app.store.settings

        // Things that want attention come first.
        var notices = false
        if let update = app.updates.available {
            menu.addItem(updateItem(update))
            notices = true
        } else if let update = app.updates.installing {
            let it = NSMenuItem(title: "Installing \(update.version)…", action: nil, keyEquivalent: "")
            it.isEnabled = false
            it.image = symbol("arrow.down.circle")
            subtitle(it, "ASCII Animals restarts when it's done")
            menu.addItem(it)
            notices = true
        }
        if app.crashedLastTime && !crashNoticeDismissed {
            menu.addItem(crashItem())
            notices = true
        }
        if notices { menu.addItem(.separator()) }

        let status = statusOverride ?? OceanStatus.make(settings: s, mode: app.director?.mode, inputs: app.signals.inputs,
                                                        error: app.startupError ?? app.director?.lastError)
        menu.addItem(statusItem(status))
        menu.addItem(.separator())

        let pause = add(menu, s.paused ? "Resume" : "Pause", #selector(togglePause),
                        symbol: s.paused ? "play.fill" : "pause.fill", key: "p")
        pause.toolTip = s.paused ? "Start the wallpaper moving again." : "Hold the wallpaper still. It stays paused until you resume."

        menu.addItem(.separator())

        menu.addItem(header("Habitat"))
        for (i, h) in HabitatKind.offered.enumerated() {
            let it = add(menu, h.title, #selector(pickHabitat(_:)), state: s.habitat == h, tag: i)
            // macOS's own menu badge, for someone upgrading from before 3.1 until the Meadow has been picked once.
            if h == .meadow && app.arrival.meadowIsNew(s) { it.badge = NSMenuItemBadge(string: "New") }
        }

        menu.addItem(.separator())

        switch s.habitat {
        case .ocean:
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
        case .web:
            let spiders = NSMenu()
            spiders.addItem(header("Line-Ups"))
            for (i, p) in Presets.spiderPresets.enumerated() {
                let it = add(spiders, p.title, #selector(pickSpiders(_:)), state: p.spiders == s.webSpiders, tag: i)
                if i < 9 { it.keyEquivalent = "\(i + 1)" }
                subtitle(it, Presets.summary(p.spiders))
            }
            if Presets.matching(s.webSpiders) == nil {
                let custom = add(spiders, "Your Line-Up", nil, state: true)
                subtitle(custom, Presets.summary(s.webSpiders))
            }
            spiders.addItem(.separator())
            add(spiders, "Flies", #selector(toggleFlies), state: s.webFlies)
            add(spiders, "Jumping Spider", #selector(toggleJumper), state: s.webJumper)
            submenu(menu, "Spiders", symbol: "ant", spiders)
        case .meadow:
            let butterflies = NSMenu()
            butterflies.addItem(header("Line-Ups"))
            let matched = MeadowLineUp.matching(s)
            for (i, p) in Presets.meadowPresets.enumerated() {
                let it = add(butterflies, p.title, #selector(pickButterflies(_:)), state: p == matched, tag: i)
                if i < 9 { it.keyEquivalent = "\(i + 1)" }
                subtitle(it, Presets.summary(p))
            }
            if matched == nil {
                let custom = add(butterflies, "Your Line-Up", nil, state: true)
                subtitle(custom, Presets.meadowSummary(s))
            }
            butterflies.addItem(.separator())
            add(butterflies, "Edit Line-Up…", #selector(openSettings), symbol: "slider.horizontal.3")
            submenu(menu, "Butterflies", symbol: "camera.macro", butterflies)
        }

        let look = NSMenu()
        look.addItem(header("Appearance"))
        for (i, a) in Self.appearances.enumerated() {
            add(look, a.1, #selector(pickAppearance(_:)), symbol: a.2, state: s.appearance == a.0, tag: i)
        }
        if s.habitat == .ocean {
            look.addItem(.separator())
            look.addItem(header("Wake"))
            add(look, "Cyan", #selector(pickWake(_:)), state: s.wakeColor == .cyan, tag: 0)
            add(look, "Accent Colour", #selector(pickWake(_:)), state: s.wakeColor == .accent, tag: 1)
        }
        look.addItem(.separator())
        add(look, "Calm", #selector(toggleCalm), state: s.calm)
        add(look, "Grid", #selector(toggleGrid), state: s.grid)
        submenu(menu, "Appearance", symbol: "paintpalette", look)

        let shared = add(menu, "One Habitat Across Displays", #selector(toggleSharedOcean),
                         symbol: "rectangle.split.2x1", state: s.sharedOcean)
        shared.toolTip = NSScreen.screens.count > 1
            ? "Animals move from one display to the next."
            : "Takes effect when you connect another display."

        menu.addItem(.separator())
        add(menu, "Settings…", #selector(openSettings), symbol: "gearshape", key: ",")
        add(menu, "Restore Original Wallpaper", #selector(restoreWallpaper), symbol: "photo.on.rectangle")
            .toolTip = "Put your own wallpaper back and stop matching the lock screen."
        add(menu, "Open at Login", #selector(toggleLogin), state: LoginItem.isEnabled)
        menu.addItem(.separator())

        add(menu, "About ASCII Animals", #selector(openAbout), symbol: "info.circle")
        add(menu, app.updates.state == .checking ? "Checking for Updates…" : "Check for Updates…",
            app.updates.state == .checking ? nil : #selector(checkUpdates), symbol: "arrow.triangle.2.circlepath")
        let help = NSMenu()
        add(help, "Welcome Tour", #selector(welcomeTour), symbol: "sparkles")
            .toolTip = "The first-launch welcome, again."
        help.addItem(.separator())
        add(help, "Report a Problem…", #selector(reportProblem), symbol: "exclamationmark.bubble")
            .toolTip = "Opens a GitHub issue with diagnostics filled in. You see it before anything is sent."
        add(help, "Copy Diagnostics", #selector(copyDiagnostics), symbol: "doc.on.clipboard")
            .toolTip = "Version, macOS, displays and settings, for pasting into a message."
        help.addItem(.separator())
        add(help, "Uninstall ASCII Animals…", #selector(uninstall), symbol: "trash")
            .toolTip = "Puts your wallpaper back and removes the app and everything it saved."
        submenu(menu, "Help", symbol: "questionmark.circle", help)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ASCII Animals", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = symbol("power")
        menu.addItem(quit)
    }

    /// "Update to 2.3": accented, so it's seen without shouting. One click installs and restarts.
    private func updateItem(_ r: LatestRelease) -> NSMenuItem {
        let it = NSMenuItem(title: "Update to \(r.version)", action: #selector(installUpdate), keyEquivalent: "")
        it.target = self
        let font = NSFont.menuFont(ofSize: 0)
        it.attributedTitle = NSAttributedString(string: it.title, attributes: [
            .font: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor,
        ])
        let config = NSImage.SymbolConfiguration(paletteColors: [.white, .controlAccentColor])
        it.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        subtitle(it, "Installs and restarts in a few seconds")
        it.toolTip = r.notes.isEmpty ? nil : String(r.notes.prefix(400))
        return it
    }

    /// "Quit unexpectedly last time — Report…"
    private func crashItem() -> NSMenuItem {
        let it = NSMenuItem(title: "Quit unexpectedly last time — Report…", action: #selector(reportCrash), keyEquivalent: "")
        it.target = self
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(string: "Quit unexpectedly last time", attributes: [
            .font: font, .foregroundColor: NSColor.labelColor,
        ])
        title.append(NSAttributedString(string: " — Report…", attributes: [
            .font: font, .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        it.attributedTitle = title
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
        it.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")?.withSymbolConfiguration(config)
        it.toolTip = "Opens a GitHub issue with diagnostics filled in, so it can be fixed."
        return it
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
    @objc private func pickHabitat(_ i: NSMenuItem) { app.store.update { $0.habitat = HabitatKind.offered[i.tag] } }
    @objc private func pickPreset(_ i: NSMenuItem) { app.store.update { $0.sharks = Presets.all[i.tag].sharks } }
    @objc private func pickButterflies(_ i: NSMenuItem) {
        guard Presets.meadowPresets.indices.contains(i.tag) else { return }
        app.store.update { Presets.meadowPresets[i.tag].apply(to: &$0) }
    }
    @objc private func pickSpiders(_ i: NSMenuItem) { app.store.update { $0.webSpiders = Presets.spiderPresets[i.tag].spiders } }
    @objc private func toggleFlies() { app.store.update { $0.webFlies.toggle() } }
    @objc private func toggleJumper() { app.store.update { $0.webJumper.toggle() } }
    @objc private func pickAppearance(_ i: NSMenuItem) { app.store.update { $0.appearance = Self.appearances[i.tag].0 } }
    @objc private func pickWake(_ i: NSMenuItem) { app.store.update { $0.wakeColor = i.tag == 0 ? .cyan : .accent } }
    @objc private func openSettings() { app.showSettings() }
    @objc private func restoreWallpaper() {
        // Stop matching too, or the still would come straight back.
        app.store.update { $0.matchSystemWallpaper = false }
        app.wallpaper?.restoreAll()
    }
    @objc private func openAbout() { app.showAbout() }
    @objc private func checkUpdates() { app.updates.checkNow(userInitiated: true) }
    @objc private func installUpdate() { app.updates.install() }
    @objc private func welcomeTour() { app.showWelcome() }
    @objc private func reportProblem() { app.reportProblem() }
    @objc private func reportCrash() {
        crashNoticeDismissed = true
        app.reportProblem()
    }
    @objc private func copyDiagnostics() { app.copyDiagnostics() }
    @objc private func uninstall() { app.uninstall() }
    @objc private func toggleLogin() {
        do { try LoginItem.set(!LoginItem.isEnabled) } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    /// Settings changed (and once at launch): e.g. show or hide the menu-bar icon.
    func apply(_ s: OceanKit.Settings) {
        if item.isVisible != s.showMenuBarIcon { item.isVisible = s.showMenuBarIcon }
    }
}
