// ASCII Sharks: a live desktop wallpaper.
//
// One borderless window per screen at the desktop window level: above the
// system wallpaper, below the desktop icons and every app. Each window hosts
// the original web ocean in a WKWebView. The windows ignore the mouse so the
// desktop keeps working; the cursor is forwarded to the ocean only while it
// is over bare desktop, so moving leaves a wake and clicking makes a splash.

import AppKit
import ServiceManagement
import WebKit

let presets: [(title: String, sharks: String)] = [
    ("Four classics", ""),
    ("Mixed", "greathammer,classic,mako,tiger"),
    ("Hammerheads", "greathammer,hammerhead,hammerhead"),
    ("Thresher and nurses", "thresher,nurse,nurse"),
    ("All eight", "greathammer,thresher,tiger,mako,zebra,classic,nurse,hammerhead"),
]

final class OceanWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var oceans: [(window: OceanWindow, web: WKWebView)] = []
    private var statusItem: NSStatusItem!
    private var monitor: Any?
    private var pointerScreen: Int?
    private var lastHitCheck: TimeInterval = 0
    private var lastHitResult = false

    private let defaults = UserDefaults.standard
    private var sharks: String {
        get { defaults.string(forKey: "sharks") ?? presets[1].sharks }
        set { defaults.set(newValue, forKey: "sharks") }
    }
    private var paused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused") }
    }
    private var webRoot: URL { Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        rebuildOceans()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // Mouse events need no Accessibility permission; only keys would.
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        ) { [weak self] event in
            self?.forward(event)
        }
    }

    // MARK: Windows

    private func rebuildOceans() {
        for ocean in oceans { ocean.window.orderOut(nil) }
        oceans = []
        pointerScreen = nil
        for screen in NSScreen.screens {
            oceans.append(makeOcean(on: screen))
        }
    }

    private func makeOcean(on screen: NSScreen) -> (window: OceanWindow, web: WKWebView) {
        let window = OceanWindow(
            contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        let config = WKWebViewConfiguration()
        let boot = "window.__SHARKS = \(jsString(sharks)); window.__PAUSED = \(paused);"
        config.userContentController.addUserScript(
            WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let web = WKWebView(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: config)
        web.autoresizingMask = [.width, .height]
        window.contentView = web
        web.loadFileURL(webRoot.appendingPathComponent("index.html"), allowingReadAccessTo: webRoot)
        window.orderFrontRegardless()
        return (window, web)
    }

    @objc private func screensChanged() {
        let screens = NSScreen.screens
        if screens.count == oceans.count {
            // Same displays, new arrangement or resolution: resize in place
            // so the ocean keeps swimming.
            for (ocean, screen) in zip(oceans, screens) {
                ocean.window.setFrame(screen.frame, display: true)
            }
        } else {
            rebuildOceans()
        }
    }

    // MARK: Pointer

    private func forward(_ event: NSEvent) {
        let p = NSEvent.mouseLocation
        let isDown = event.type == .leftMouseDown
        let bare = desktopIsBare(at: p, fresh: isDown)
        for (i, ocean) in oceans.enumerated() {
            let f = ocean.window.frame
            if bare && f.contains(p) {
                let x = p.x - f.minX
                let y = f.maxY - p.y
                let call = isDown ? "down" : "move"
                ocean.web.evaluateJavaScript("window.wallpaper && wallpaper.\(call)(\(x), \(y))")
                pointerScreen = i
            } else if pointerScreen == i {
                ocean.web.evaluateJavaScript("window.wallpaper && wallpaper.leave()")
                pointerScreen = nil
            }
        }
    }

    /// True when nothing but the desktop is under the point: no app window,
    /// menu bar or Dock. Checked at most 20 times a second while moving.
    private func desktopIsBare(at p: NSPoint, fresh: Bool) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if !fresh && now - lastHitCheck < 0.05 { return lastHitResult }
        lastHitCheck = now

        guard let primary = NSScreen.screens.first else { return false }
        // Window bounds come in global coordinates with a top-left origin.
        let q = CGPoint(x: p.x, y: primary.frame.maxY - p.y)
        let me = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var bare = true
        for info in list {
            if (info[kCGWindowOwnerPID as String] as? pid_t) == me { continue }
            if (info[kCGWindowLayer as String] as? Int ?? 0) < 0 { continue }
            if (info[kCGWindowAlpha as String] as? Double ?? 1) < 0.01 { continue }
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: dict)
            else { continue }
            if rect.contains(q) {
                bare = false
                break
            }
        }
        lastHitResult = bare
        return bare
    }

    // MARK: Menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "fish", accessibilityDescription: "ASCII Sharks") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "≈"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let sharksItem = NSMenuItem(title: "Sharks", action: nil, keyEquivalent: "")
        let sharksMenu = NSMenu()
        for (i, preset) in presets.enumerated() {
            let item = NSMenuItem(title: preset.title, action: #selector(pickPreset(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = preset.sharks == sharks ? .on : .off
            sharksMenu.addItem(item)
        }
        sharksItem.submenu = sharksMenu
        menu.addItem(sharksItem)

        let pause = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = paused ? .on : .off
        menu.addItem(pause)

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ASCII Sharks", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func pickPreset(_ sender: NSMenuItem) {
        sharks = presets[sender.tag].sharks
        rebuildOceans()
    }

    @objc private func togglePause() {
        paused.toggle()
        for ocean in oceans {
            ocean.web.evaluateJavaScript("window.wallpaper && wallpaper.pause(\(paused))")
        }
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    private func jsString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s])
        return String(String(data: data, encoding: .utf8)!.dropFirst().dropLast())
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
