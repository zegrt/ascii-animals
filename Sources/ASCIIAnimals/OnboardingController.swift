import AppKit
import Metal
import OceanKit
import SwiftUI

/// The immersive first-launch welcome: a full-screen live habitat with a few
/// typed lines over it, ending in a dissolve to the real desktop one.
/// Return or a click moves on, Esc leaves at any time.
/// The same window, as a single card, tells people who came from ASCII Sharks about the Web.
enum OnboardingController {
    static let seenKey = "onboarded.v1"
    private static var current: OnboardingSession?

    /// First launch: the tour. After the hand-over from ASCII Sharks (which skips it): the Web card, once. Upgrading
    /// to 3.1: the small Meadow card under the menu bar icon, once (`WhatsNewCard`).
    static func showIfNeeded(app: AppDelegate) {
        let d = UserDefaults.standard
        let s = app.store.settings
        let welcome = Handover.launchWelcome(onboarded: d.bool(forKey: seenKey), handedOver: SharksHandover.happened,
                                             webCardShown: d.bool(forKey: Handover.webCardKey), habitat: s.habitat,
                                             arrival: app.arrival, meadowCardShown: d.bool(forKey: Handover.meadowCardKey),
                                             meadowTried: s.meadowTried)
        switch welcome {
        case .nothing:
            return
        case .meadowCard:
            WhatsNewCard.showWhenSeen(app: app)
        case .tour, .webCard:
            // A moment for the desktop habitat to come up first, so the dissolve has something to reveal.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { present(app: app, card: welcome == .webCard) }
        }
    }

    /// The welcome from Help. The Meadow card goes first, at once, and stops waiting; if the welcome couldn't open,
    /// a card that was still waiting waits again (it reads the saved flag at every look).
    static func show(app: AppDelegate) {
        let cardWaiting: Bool = WhatsNewCard.dismiss()
        present(app: app, card: false)
        if cardWaiting && !isShowing { WhatsNewCard.showWhenSeen(app: app) }
    }

    private static func present(app: AppDelegate, card: Bool) {
        if let current { current.focus(); return }
        // No renderer means no ocean to show; the menu still explains a failed start.
        // Nothing is marked seen until it reaches the user: a launch that can't show it tries again next time.
        guard let renderer = app.director?.renderer, !NSScreen.screens.isEmpty else { return }
        let session = OnboardingSession(app: app, renderer: renderer, card: card)
        current = session
        session.onSeen = {
            let d = UserDefaults.standard
            // The tour opens with the habitat choice, so whoever sees it knows about the Web too.
            d.set(true, forKey: Handover.webCardKey)
            if !card {
                d.set(true, forKey: seenKey)
                // And about the Meadow.
                d.set(true, forKey: Handover.meadowCardKey)
            }
        }
        session.onFinish = { current = nil }
        session.start()
    }

    static var isShowing: Bool { current != nil }

    /// The status menu opened: on the "Settings live up here" step, that's the step done.
    static func statusMenuOpened() { current?.statusMenuOpened() }

    /// Debug: render to a PNG (no Screen Recording needed). `--snapshot-onboarding <png>`
    /// `ASCII_ANIMALS_ONBOARDING_STEP=0…6` picks the step (default 0: 0 habitat, 1 hello, 2 pointer, 3 splash,
    /// 4 menu, 5 make it yours, 6 dive), or `card` the Web card for people from ASCII Sharks;
    /// `ASCII_ANIMALS_SNAPSHOT_LIGHT=1` the light look;
    /// `ASCII_ANIMALS_SNAPSHOT_HABITAT=web|meadow` the Web or the Meadow (default Ocean, as a new user has it; the card
    /// always shows the Web). The Meadow card under the menu bar icon has its own flag (`--snapshot-whatsnew`).
    static func snapshot(to url: URL) {
        let env = ProcessInfo.processInfo.environment
        let step = env["ASCII_ANIMALS_ONBOARDING_STEP"] ?? ""
        let card = step == "card"
        let beat = OnboardingBeat(rawValue: Int(step) ?? 0) ?? .habitat
        let size = CGSize(width: 1512, height: 982)
        let scale: CGFloat = 2
        do {
            guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError(description: "no Metal device") }
            let renderer = try OceanRenderer(device: device)
            var s = OceanKit.Settings.defaults
            if env["ASCII_ANIMALS_SNAPSHOT_LIGHT"] != nil { s.appearance = .light }
            if let h = env["ASCII_ANIMALS_SNAPSHOT_HABITAT"].flatMap(HabitatKind.init(rawValue:)) { s.habitat = h }
            if card { s.habitat = .web }
            let theme = ThemeParams.make(s, systemIsDark: true, accent: SIMD3(0.2, 0.5, 1))
            let vp = try renderer.makeViewport(pointSize: size, scale: scale)
            let sim = Habitats.make(s, seed: 11)
            sim.layout(terrain: .single(width: size.width, height: size.height), cell: vp.grid.cell, settings: s)
            // Warm up; on the interactive steps, sweep a pointer and click (a splash, a fly) in the last seconds.
            let total = 7 * 60
            for i in 0..<total {
                let t = Double(i - (total - 150)) / 150
                if beat == .pointer, t >= 0 {
                    sim.pointerMoved(size.width * (0.62 + 0.16 * t), size.height * (0.72 - 0.1 * sin(t * 3)))
                }
                if beat == .splash, i == total - 40 { sim.pointerDown(size.width * 0.7, size.height * 0.74) }
                sim.step(OceanClock.step)
                if i >= total - 180, let cb = renderer.queue.makeCommandBuffer() {
                    vp.encode(habitat: sim, theme: theme, target: nil, commandBuffer: cb)
                    cb.commit()
                }
            }
            guard let ocean = LiveOceanView.image(of: sim, viewport: vp, theme: theme, renderer: renderer) else {
                throw RenderError(description: "no habitat frame")
            }

            let model = OnboardingModel(settings: s, light: theme.light)
            model.card = card
            model.beat = beat
            model.iconHidden = false
            model.finishTyping()
            model.hintVisible = true
            model.contentVisible = true
            model.done = !card && (beat == .pointer || beat == .splash)
            // Where a menu-bar icon would sit, for the callout.
            model.iconRect = CGRect(x: size.width - 214, y: 0, width: 30, height: 33)
            let host = NSHostingView(rootView: OnboardingView(model: model))
            host.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw RenderError(description: "no overlay") }
            host.cacheDisplay(in: host.bounds, to: rep)

            let w = Int(size.width * scale), h = Int(size.height * scale)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw RenderError(description: "no context") }
            let full = CGRect(x: 0, y: 0, width: w, height: h)
            ctx.interpolationQuality = .high
            ctx.draw(ocean, in: full)
            // A stand-in menu bar, so the menu step reads as it does on screen.
            ctx.setFillColor(CGColor(gray: theme.light ? 0.92 : 0.12, alpha: 0.72))
            ctx.fill(CGRect(x: 0, y: CGFloat(h) - 33 * scale, width: CGFloat(w), height: 33 * scale))
            if let overlay = rep.cgImage { ctx.draw(overlay, in: full) }
            guard let image = ctx.makeImage() else { throw RenderError(description: "no image") }
            try StillRenderer.writePNG(image, to: url)
            print("wrote \(url.path) (\(card ? "card" : "step \(beat.rawValue)"), \(s.habitat.rawValue)): \(model.title) / \(model.subtitle)"
                  + (model.doneLine.isEmpty ? "" : " / \(model.doneLine)"))
        } catch {
            FileHandle.standardError.write(Data("onboarding snapshot failed: \(error)\n".utf8))
        }
    }
}

// MARK: - Steps

enum OnboardingBeat: Int, CaseIterable {
    case habitat, hello, pointer, splash, menu, choose, dive

    func title(iconHidden: Bool, habitat: HabitatKind) -> String {
        let web = habitat == .web
        let meadow = habitat == .meadow
        switch self {
        case .habitat: return "Meet ASCII Animals."
        case .hello:
            if meadow { return "Your desktop is now a meadow." }
            return web ? "Your desktop is now covered in webs." : "Your desktop is now an ocean."
        case .pointer: return "Move your pointer."
        case .splash:
            if meadow { return "Click to bloom a flower." }
            return web ? "Click to drop a fly." : "Click for a splash."
        case .menu: return iconHidden ? "Settings are one launch away." : "Settings live up here."
        case .choose: return "Make it yours."
        case .dive: return "Dive in."
        }
    }

    func subtitle(iconHidden: Bool, habitat: HabitatKind) -> String {
        let web = habitat == .web
        let meadow = habitat == .meadow
        switch self {
        case .habitat: return "Pick a habitat. You can change it any time."
        case .hello:
            if meadow { return "Butterflies drift between the flowers, and all of it is drawn in text." }
            return web ? "Orb weavers spin, flies wander, and all of it is drawn in text."
                       : "Sharks hunt, fish school, and all of it is drawn in text."
        case .pointer:
            if meadow { return "The air stirs: the flowers sway and the butterflies veer." }
            return web ? "The silk rings, and the spiders turn toward it." : "The fish scatter out of its way."
        case .splash:
            if meadow { return "Anywhere on the meadow." }
            return web ? "Anywhere near a web." : "Anywhere in the water."
        case .menu:
            return iconHidden
                ? "The menu bar icon is hidden. Open ASCII Animals again any time to get Settings."
                : "Click the fish in the menu bar for habitats, looks and pause."
        case .choose: return "Pick a look and a line-up. Both can change in Settings."
        case .dive:
            if meadow { return "It flutters behind your windows from now on." }
            return web ? "It lives behind your windows from now on." : "It swims behind your windows from now on."
        }
    }

    /// The steps with chips: their clicks pick, they don't move on.
    var hasChoices: Bool { self == .habitat || self == .choose }

    /// Shown once the step's little task is done.
    func doneLine(habitat: HabitatKind) -> String {
        switch self {
        case .pointer: return "They noticed."
        case .splash:
            switch habitat {
            case .ocean: return "Splash."
            case .web: return "Dinner."
            case .meadow: return "Bloom."
            }
        case .menu: return "That's the one."
        default: return ""
        }
    }
}

/// The three looks offered in the welcome, mapped onto appearance + calm.
enum OnboardingLook: Int, CaseIterable {
    case dark, light, calm

    var title: String { ["Dark", "Light", "Calm"][rawValue] }

    static func of(_ s: OceanKit.Settings, systemIsDark: Bool) -> OnboardingLook {
        if s.calm { return .calm }
        let light = s.appearance == .light || (s.appearance == .system && !systemIsDark)
        return light ? .light : .dark
    }

    func apply(_ s: inout OceanKit.Settings) {
        switch self {
        case .dark: s.appearance = .dark; s.calm = false
        case .light: s.appearance = .light; s.calm = false
        case .calm: s.appearance = .dark; s.calm = true
        }
    }
}

// MARK: - Model

/// The card for people who came from ASCII Sharks, who skipped the tour and its habitat choice.
enum WebCard {
    static let title = "There's a new habitat: the Web."
    static let subtitle = "Spiders spin webs on your desktop. Flies wander in."
}

final class OnboardingModel: ObservableObject {
    @Published var beat: OnboardingBeat = .habitat
    /// The Web card instead of the tour.
    @Published var card = false
    @Published var typedTitle = 0
    @Published var typedSubtitle = 0
    @Published var cursorOn = true
    @Published var hintVisible = false
    @Published var contentVisible = false
    @Published var done = false
    @Published var settings: OceanKit.Settings
    @Published var light: Bool
    @Published var iconHidden = false
    /// The menu-bar icon in this window's SwiftUI space (top-left origin).
    @Published var iconRect: CGRect?
    @Published var hovered: String?

    var onHabitat: (HabitatKind) -> Void = { _ in }
    var onLook: (OnboardingLook) -> Void = { _ in }
    var onPreset: (Int) -> Void = { _ in }
    var onContinue: () -> Void = {}
    var onTryWeb: () -> Void = {}

    init(settings: OceanKit.Settings, light: Bool) {
        self.settings = settings
        self.light = light
    }

    var title: String { card ? WebCard.title : beat.title(iconHidden: iconHidden, habitat: settings.habitat) }
    var subtitle: String { card ? WebCard.subtitle : beat.subtitle(iconHidden: iconHidden, habitat: settings.habitat) }
    var doneLine: String { card ? "" : beat.doneLine(habitat: settings.habitat) }
    /// Chips on screen: clicks pick, they don't move on.
    var hasChoices: Bool { card || beat.hasChoices }
    var isTyping: Bool { typedTitle < title.count || typedSubtitle < subtitle.count }

    func finishTyping() {
        typedTitle = title.count
        typedSubtitle = subtitle.count
    }

    var look: OnboardingLook {
        OnboardingLook.of(settings, systemIsDark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
}

// MARK: - Window

final class OnboardingWindow: NSWindow {
    var onKey: ((NSEvent) -> Bool)?
    var onMouse: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ e: NSEvent) {
        switch e.type {
        case .keyDown:
            if onKey?(e) == true { return }
        case .mouseMoved, .leftMouseDragged, .leftMouseDown, .mouseExited:
            onMouse?(e)
        default:
            break
        }
        super.sendEvent(e)
    }
}

/// One showing of the welcome: its windows, timers and observers. Everything it
/// puts on screen is removed by `teardown`, which every exit reaches.
final class OnboardingSession: NSObject {
    private unowned let app: AppDelegate
    private let model: OnboardingModel
    private let window: OnboardingWindow
    private let ocean: LiveOceanView
    private var dims: [NSWindow] = []
    private var typer: Timer?
    private var blinker: Timer?
    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var travelled: CGFloat = 0
    private var lastPointer: NSPoint?
    private var finishing = false
    private var tornDown = false
    private var typingPause = 0
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private let card: Bool
    var onFinish: (() -> Void)?
    /// Once, when the user has had the welcome in front of them: in front and key after 3 s, or
    /// they ended it themselves sooner. Not when it was closed because it never got the focus.
    var onSeen: (() -> Void)?

    /// `card`: the Web card, with the Web live behind it (the desktop stays as it is until "Try the Web").
    init(app: AppDelegate, renderer: OceanRenderer, card: Bool = false) {
        self.app = app
        self.card = card
        var s = app.store.settings
        if card { s.habitat = .web }
        let theme = OceanDirector.currentTheme(s)
        model = OnboardingModel(settings: s, light: theme.light)
        model.card = card

        // The display with the menu-bar icon (it follows the active display), else the main one.
        let iconFrame = app.menu?.iconScreenFrame
        let screen = NSScreen.screens.first { s in iconFrame.map { s.frame.intersects($0) } ?? false }
            ?? NSScreen.screens[0]
        let frame = screen.frame

        window = OnboardingWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(frame, display: false)
        // Above the Dock and every app, just under the menu bar, so the real menu bar stays in view.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = theme.light ? NSColor(white: 0.96, alpha: 1) : .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.animationBehavior = .none
        window.alphaValue = 0

        ocean = LiveOceanView(renderer: renderer, settings: s, theme: theme, zoom: 1)
        ocean.handlesMouse = false // the window routes the pointer, so it works over the text too
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        ocean.frame = container.bounds
        ocean.autoresizingMask = [.width, .height]
        container.addSubview(ocean)
        let host = NSHostingView(rootView: OnboardingView(model: model))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        window.contentView = container

        // Other displays: gently dimmed, so the eye stays on the welcome.
        for other in NSScreen.screens where other != screen {
            let d = NSWindow(contentRect: other.frame, styleMask: .borderless, backing: .buffered, defer: false)
            d.setFrame(other.frame, display: false)
            d.level = window.level
            d.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            d.isOpaque = false
            d.backgroundColor = .black
            d.ignoresMouseEvents = true
            d.hasShadow = false
            d.isReleasedWhenClosed = false
            d.animationBehavior = .none
            d.alphaValue = 0
            dims.append(d)
        }
        super.init()

        if let f = iconFrame, app.store.settings.showMenuBarIcon, frame.intersects(f) {
            model.iconRect = CGRect(x: f.minX - frame.minX, y: frame.maxY - f.maxY, width: f.width, height: f.height)
        }
        model.iconHidden = model.iconRect == nil
        model.onHabitat = { [weak self] h in self?.pickHabitat(h) }
        model.onLook = { [weak self] l in self?.pickLook(l) }
        model.onPreset = { [weak self] i in self?.pickPreset(i) }
        model.onContinue = { [weak self] in self?.advance() }
        model.onTryWeb = { [weak self] in self?.tryWeb() }
        window.onKey = { [weak self] e in self?.key(e) ?? false }
        window.onMouse = { [weak self] e in self?.mouse(e) }
    }

    // MARK: Lifecycle

    func start() {
        for d in dims { d.orderFrontRegardless() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduceMotion ? 0.3 : 1.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            for d in dims { d.animator().alphaValue = 0.55 }
        }
        let nc = NotificationCenter.default
        // Never trap: leaving the app, opening another of its windows or changing displays ends the welcome.
        observers.append(nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.finish(fast: false)
        })
        observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] n in
            // Settings or About opened from the menu would sit behind the welcome; make way.
            guard let self, let w = n.object as? NSWindow, w !== self.window, w.styleMask.contains(.titled) else { return }
            self.finish(fast: true)
        })
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.finish(fast: true)
        })
        // If macOS didn't let the app come forward, keys can't reach the welcome: don't sit on top of everything.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.finishing else { return }
            if NSApp.isActive, self.window.isKeyWindow { self.markSeen() } else { self.finish(fast: false, seen: false) }
        }
        blinker = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in self?.model.cursorOn.toggle() }
        after(reduceMotion ? 0.2 : 0.9) { [weak self] in self?.enter(.habitat) }
    }

    func focus() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func after(_ seconds: Double, _ body: @escaping () -> Void) {
        let item = DispatchWorkItem(block: body)
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    // MARK: Steps

    private func enter(_ beat: OnboardingBeat) {
        guard !finishing else { return }
        pending?.cancel()
        model.beat = beat
        model.done = false
        model.typedTitle = 0
        model.typedSubtitle = 0
        model.hintVisible = false
        travelled = 0
        withAnimation(.easeOut(duration: 0.45)) { model.contentVisible = true }
        if reduceMotion { model.finishTyping() }
        typingPause = 6
        typer?.invalidate()
        typer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.type() }
    }

    /// Calm typing: about 30 characters a second, a breath between the lines.
    private func type() {
        if typingPause > 0 { typingPause -= 1; return }
        if model.typedTitle < model.title.count {
            model.typedTitle += 1
            if model.typedTitle == model.title.count { typingPause = 12 }
        } else if model.typedSubtitle < model.subtitle.count {
            model.typedSubtitle = min(model.subtitle.count, model.typedSubtitle + 2)
        } else {
            typer?.invalidate()
            typer = nil
            after(0.9) { [weak self] in
                withAnimation(.easeOut(duration: 0.6)) { self?.model.hintVisible = true }
            }
        }
    }

    /// Return / click: finish the line being typed, else go on (on the card: keep the Ocean).
    private func advance() {
        guard !finishing else { return }
        if model.isTyping {
            model.finishTyping()
            return
        }
        if card { finish(fast: false); return }
        guard let next = OnboardingBeat(rawValue: model.beat.rawValue + 1) else {
            finish(fast: false)
            return
        }
        typer?.invalidate()
        pending?.cancel()
        withAnimation(.easeIn(duration: 0.3)) { model.contentVisible = false }
        after(0.42) { [weak self] in self?.enter(next) }
    }

    private func completeStep(after delay: Double) {
        guard !model.done else { return }
        let beat = model.beat
        model.finishTyping()
        withAnimation(.easeOut(duration: 0.4)) { model.done = true }
        after(delay) { [weak self] in
            guard let self, self.model.beat == beat else { return }
            self.advance()
        }
    }

    func statusMenuOpened() {
        if model.beat == .menu { completeStep(after: 2.2) }
    }

    private func pickLook(_ look: OnboardingLook) {
        app.store.update { look.apply(&$0) }
        model.settings = app.store.settings
        let theme = OceanDirector.currentTheme(model.settings)
        ocean.setTheme(theme)
        window.backgroundColor = theme.light ? NSColor(white: 0.96, alpha: 1) : .black
        withAnimation(.easeInOut(duration: 0.35)) { model.light = theme.light }
    }

    /// The desktop behind dissolves to it too; the welcome's own scene follows here.
    private func pickHabitat(_ h: HabitatKind) {
        app.store.update { $0.habitat = h }
        model.settings = app.store.settings
        ocean.rebuild(model.settings)
    }

    /// The card's "Try the Web": the desktop dissolves to it as the card goes.
    private func tryWeb() {
        guard !finishing else { return }
        app.store.update { $0.habitat = .web }
        finish(fast: false)
    }

    /// A line-up of the current habitat: sharks or spiders.
    private func pickPreset(_ i: Int) {
        switch model.settings.habitat {
        case .ocean:
            guard Presets.all.indices.contains(i) else { return }
            app.store.update { $0.sharks = Presets.all[i].sharks }
        case .web:
            guard Presets.spiderPresets.indices.contains(i) else { return }
            app.store.update { $0.webSpiders = Presets.spiderPresets[i].spiders }
        case .meadow:
            guard Presets.meadowPresets.indices.contains(i) else { return }
            app.store.update { Presets.meadowPresets[i].apply(to: &$0) }
            model.settings = app.store.settings
            // The Meadow takes a new line-up in place, as on the desktop: spares fly off, newcomers fly in.
            ocean.sim.update(settings: model.settings)
            return
        }
        model.settings = app.store.settings
        ocean.rebuild(model.settings)
    }

    // MARK: Input

    private func key(_ e: NSEvent) -> Bool {
        if e.modifierFlags.contains(.command) {
            // ⌘W, ⌘Q, ⌘. leave too.
            if [13, 12, 47].contains(e.keyCode) { finish(fast: true); return true }
            return false
        }
        switch e.keyCode {
        case 53: finish(fast: true); return true            // esc
        case 36, 76, 49, 124: advance(); return true       // return, enter, space, →
        default: return false
        }
    }

    private func mouse(_ e: NSEvent) {
        let p = ocean.convert(e.locationInWindow, from: nil)
        switch e.type {
        case .mouseExited:
            ocean.pointer(at: nil)
        case .leftMouseDown:
            if model.hasChoices {
                ocean.pointer(at: p)
                return // the habitat, look, line-up and card buttons own clicks here
            }
            ocean.splash(at: p)
            switch model.beat {
            case .splash: completeStep(after: 1.6)
            case .pointer: completeStep(after: 0.9)
            case .dive: if !model.isTyping { finish(fast: false) } else { advance() }
            default: advance()
            }
        default:
            ocean.pointer(at: p)
            if let last = lastPointer { travelled += hypot(p.x - last.x, p.y - last.y) }
            lastPointer = p
            if model.beat == .pointer, !model.isTyping, travelled > 900 { completeStep(after: 1.8) }
        }
    }

    // MARK: Leaving

    /// The dissolve: the words go first, then the ocean melts into the desktop's own.
    private func markSeen() {
        onSeen?()
        onSeen = nil
    }

    /// `seen: false` only when the welcome never reached the user, so it comes back next launch.
    func finish(fast: Bool, seen: Bool = true) {
        guard !finishing else { return }
        finishing = true
        if seen { markSeen() }
        typer?.invalidate()
        blinker?.invalidate()
        pending?.cancel()
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        withAnimation(.easeIn(duration: fast ? 0.2 : 0.4)) {
            model.contentVisible = false
            model.hintVisible = false
        }
        let delay = fast || reduceMotion ? 0.05 : 0.35
        let duration = fast ? 0.45 : (reduceMotion ? 0.5 : 1.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.window.animator().alphaValue = 0
                for d in self.dims { d.animator().alphaValue = 0 }
            }, completionHandler: { [weak self] in self?.teardown() })
        }
        // Belt and braces: whatever happens to the animation, nothing stays on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration + 1) { [weak self] in self?.teardown() }
    }

    private func teardown() {
        guard !tornDown else { return }
        tornDown = true
        ocean.stop()
        window.onKey = nil
        window.onMouse = nil
        window.orderOut(nil)
        window.close()
        for d in dims { d.orderOut(nil); d.close() }
        dims = []
        onFinish?()
    }
}

// MARK: - View

enum Ink {
    static func text(_ light: Bool) -> Color { light ? Color(white: 0.07) : Color(white: 0.96) }
    static func plate(_ light: Bool) -> Color { light ? Color(white: 0.965) : Color(white: 0.01) }
    static func accent(_ light: Bool) -> Color {
        light ? Color(red: 0.0, green: 0.42, blue: 0.56) : Color(red: 110 / 255, green: 230 / 255, blue: 1)
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        GeometryReader { geo in
            let unit = min(max(geo.size.width / 1512, 0.8), 1.35)
            ZStack {
                // A soft plate behind the words, so they read over the busiest water.
                EllipticalGradient(gradient: Gradient(stops: [
                    .init(color: Ink.plate(model.light).opacity(0.93), location: 0),
                    .init(color: Ink.plate(model.light).opacity(0.82), location: 0.5),
                    .init(color: Ink.plate(model.light).opacity(0), location: 1),
                ]), center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                    .frame(width: 1240 * unit, height: plateHeight * unit)
                    .opacity(model.contentVisible ? 1 : 0)
                    .allowsHitTesting(false)

                StepContent(model: model, unit: unit)
                    .frame(width: min(geo.size.width - 80, 1100 * unit))
                    .opacity(model.contentVisible ? 1 : 0)
                    .offset(y: model.contentVisible ? 0 : -8 * unit)

                VStack {
                    Spacer()
                    HintBar(model: model, unit: unit)
                        .opacity(model.hintVisible && model.contentVisible ? 1 : 0)
                        .padding(.bottom, 54 * unit)
                }

                if model.beat == .menu, let r = model.iconRect {
                    MenuCallout(rect: r, model: model)
                        .opacity(model.contentVisible ? 1 : 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .foregroundStyle(Ink.text(model.light))
        .ignoresSafeArea()
    }

    private var plateHeight: CGFloat {
        if model.card { return 600 }
        switch model.beat {
        case .choose: return 760
        case .habitat: return 620
        default: return 560
        }
    }
}

private struct StepContent: View {
    @ObservedObject var model: OnboardingModel
    let unit: CGFloat

    var body: some View {
        let ink = Ink.text(model.light)
        VStack(spacing: 0) {
            if !model.card {
                Progress(model: model, unit: unit)
                    .padding(.bottom, 34 * unit)
            }

            Typed(full: model.title, count: model.typedTitle,
                  cursor: model.typedTitle < model.title.count || model.cursorOn,
                  accent: Ink.accent(model.light))
                .font(UIFonts.swiftUI(50 * unit, weight: 500))
                .kerning(-0.5 * unit)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20 * unit)

            Typed(full: model.subtitle, count: model.typedSubtitle, cursor: false, accent: .clear)
                .font(UIFonts.swiftUI(19 * unit, weight: 400))
                .foregroundStyle(ink.opacity(0.66))
                .multilineTextAlignment(.center)
                .lineSpacing(5 * unit)
                .frame(maxWidth: 760 * unit)

            ZStack {
                if model.card {
                    CardChoices(model: model, unit: unit)
                } else if model.beat == .habitat {
                    HabitatChoices(model: model, unit: unit)
                } else if model.beat == .choose {
                    Choices(model: model, unit: unit)
                        .transition(.opacity)
                } else if model.beat == .dive {
                    Chip(title: "Dive in  ↵", selected: true, light: model.light, unit: unit, prominent: true, model: model) {
                        model.onContinue()
                    }
                    .opacity(model.isTyping ? 0 : 1)
                    .animation(.easeOut(duration: 0.5), value: model.isTyping)
                } else {
                    Text(model.doneLine)
                        .font(UIFonts.swiftUI(15 * unit, weight: 500))
                        .kerning(1 * unit)
                        .foregroundStyle(Ink.accent(model.light))
                        .opacity(model.done ? 1 : 0)
                        .offset(y: model.done ? 0 : 4)
                }
            }
            .padding(.top, 40 * unit)
            .frame(minHeight: 60 * unit, alignment: .top)
        }
    }
}

/// The whole line is laid out from the start (the untyped rest is clear), so
/// typing never reflows it.
struct Typed: View {
    let full: String
    let count: Int
    let cursor: Bool
    let accent: Color

    var body: some View {
        let shown = String(full.prefix(count))
        let rest = String(full.dropFirst(count))
        return Text(shown)
            + Text("▍").foregroundColor(cursor ? accent.opacity(0.85) : .clear)
            + Text(rest).foregroundColor(.clear)
    }
}

private struct Progress: View {
    @ObservedObject var model: OnboardingModel
    let unit: CGFloat

    var body: some View {
        HStack(spacing: 7 * unit) {
            ForEach(OnboardingBeat.allCases, id: \.rawValue) { b in
                Capsule()
                    .fill(b == model.beat ? Ink.accent(model.light) : Ink.text(model.light).opacity(b.rawValue < model.beat.rawValue ? 0.5 : 0.18))
                    .frame(width: (b == model.beat ? 26 : 8) * unit, height: 3 * unit)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: model.beat)
        .accessibilityLabel("Step \(model.beat.rawValue + 1) of \(OnboardingBeat.allCases.count)")
    }
}

private struct Choices: View {
    @ObservedObject var model: OnboardingModel
    let unit: CGFloat

    var body: some View {
        let ink = Ink.text(model.light)
        let look = model.look
        let habitat = model.settings.habitat
        VStack(spacing: 22 * unit) {
            row("LOOK") {
                ForEach(OnboardingLook.allCases, id: \.rawValue) { l in
                    Chip(title: l.title, selected: l == look, light: model.light, unit: unit, model: model) { model.onLook(l) }
                }
            }
            switch habitat {
            case .ocean:
                let preset = Presets.matching(model.settings.sharks)
                row("SHARKS") {
                    ForEach(Array(Presets.all.enumerated()), id: \.offset) { i, p in
                        Chip(title: p.title, selected: preset?.title == p.title, light: model.light, unit: unit, model: model) { model.onPreset(i) }
                    }
                }
            case .web:
                let preset = Presets.matching(model.settings.webSpiders)
                row("SPIDERS") {
                    ForEach(Array(Presets.spiderPresets.enumerated()), id: \.offset) { i, p in
                        Chip(title: p.title, selected: preset?.title == p.title, light: model.light, unit: unit, model: model) { model.onPreset(i) }
                    }
                }
            case .meadow:
                let lineUp: MeadowLineUp? = MeadowLineUp.matching(model.settings)
                row("BUTTERFLIES") {
                    ForEach(Array(Presets.meadowPresets.enumerated()), id: \.offset) { i, p in
                        Chip(title: p.title, selected: lineUp == p, light: model.light, unit: unit, model: model) { model.onPreset(i) }
                    }
                }
            }
            Text(summary)
                .font(UIFonts.swiftUI(13 * unit))
                .foregroundStyle(ink.opacity(0.5))
                .padding(.top, 2 * unit)
            Chip(title: "Continue  ↵", selected: false, light: model.light, unit: unit, quiet: true, model: model) { model.onContinue() }
                .padding(.top, 14 * unit)
        }
        .opacity(model.isTyping ? 0 : 1)
        .animation(.easeOut(duration: 0.5), value: model.isTyping)
    }

    /// The line-up under the rows: "Classic · Great Hammerhead", "2 Garden Spiders · …", "2 Monarchs · …".
    private var summary: String {
        let s = model.settings
        switch s.habitat {
        case .ocean: return s.sharks.map(Presets.title).joined(separator: " · ")
        case .web: return Presets.summary(s.webSpiders, separator: " · ")
        case .meadow: return Presets.summary(butterflies: s.meadowButterflies, count: s.meadowCount, separator: " · ")
        }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 10 * unit) {
            Text(label)
                .font(UIFonts.swiftUI(11 * unit, weight: 500))
                .kerning(2.5 * unit)
                .foregroundStyle(Ink.text(model.light).opacity(0.45))
            HStack(spacing: 10 * unit) { content() }
        }
    }
}

/// The first step: the habitat the rest of the tour plays in. The scene behind switches at once.
private struct HabitatChoices: View {
    @ObservedObject var model: OnboardingModel
    let unit: CGFloat

    var body: some View {
        let habitat = model.settings.habitat
        VStack(spacing: 22 * unit) {
            HStack(spacing: 12 * unit) {
                ForEach(HabitatKind.offered, id: \.self) { h in
                    Chip(title: h.title, selected: h == habitat, light: model.light, unit: unit, prominent: true, model: model) {
                        model.onHabitat(h)
                    }
                }
            }
            Chip(title: "Continue  ↵", selected: false, light: model.light, unit: unit, quiet: true, model: model) { model.onContinue() }
                .padding(.top, 14 * unit)
        }
        .opacity(model.isTyping ? 0 : 1)
        .animation(.easeOut(duration: 0.5), value: model.isTyping)
    }
}

/// The Web card's two answers; keeping the Ocean is the default (Return).
private struct CardChoices: View {
    @ObservedObject var model: OnboardingModel
    let unit: CGFloat

    var body: some View {
        HStack(spacing: 12 * unit) {
            Chip(title: "Try the Web", selected: false, light: model.light, unit: unit, prominent: true, model: model) { model.onTryWeb() }
            Chip(title: "Keep the Ocean  ↵", selected: true, light: model.light, unit: unit, prominent: true, model: model) { model.onContinue() }
        }
        .opacity(model.isTyping ? 0 : 1)
        .animation(.easeOut(duration: 0.5), value: model.isTyping)
    }
}

private struct Chip: View {
    let title: String
    let selected: Bool
    let light: Bool
    let unit: CGFloat
    var prominent = false
    var quiet = false
    @ObservedObject var model: OnboardingModel
    let action: () -> Void

    var body: some View {
        let ink = Ink.text(light)
        let hover = model.hovered == title
        Button(action: action) {
            Text(title)
                .font(UIFonts.swiftUI((prominent ? 17 : 15) * unit, weight: selected ? 500 : 400))
                .padding(.horizontal, (prominent ? 26 : 16) * unit)
                .padding(.vertical, (prominent ? 13 : 9) * unit)
                .foregroundStyle(selected ? Ink.plate(light) : ink.opacity(quiet && !hover ? 0.7 : 0.92))
                .background(
                    RoundedRectangle(cornerRadius: 9 * unit, style: .continuous)
                        .fill(selected ? ink.opacity(hover ? 1 : 0.92) : Ink.plate(light).opacity(hover ? 0.75 : 0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9 * unit, style: .continuous)
                        .strokeBorder(ink.opacity(selected ? 0 : (hover ? 0.55 : (quiet ? 0.0 : 0.25))), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9 * unit, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .onHover { inside in
            if inside { model.hovered = title } else if model.hovered == title { model.hovered = nil }
        }
        .animation(.easeOut(duration: 0.15), value: hover)
        .animation(.easeOut(duration: 0.2), value: selected)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct HintBar: View {
    @ObservedObject var model: OnboardingModel
    let unit: CGFloat

    var body: some View {
        let ink = Ink.text(model.light)
        HStack(spacing: 10 * unit) {
            Keycap(text: "return", light: model.light, unit: unit)
            Text(returnLine)
            Spacer().frame(width: 22 * unit)
            Keycap(text: "esc", light: model.light, unit: unit)
            Text(model.card || model.beat == .dive ? "close" : "skip the tour")
        }
        .font(UIFonts.swiftUI(12.5 * unit))
        .foregroundStyle(ink.opacity(0.55))
        .padding(.horizontal, 16 * unit)
        .padding(.vertical, 9 * unit)
        .background(Capsule().fill(Ink.plate(model.light).opacity(0.6)))
    }

    private var returnLine: String {
        if model.card { return "keep the ocean" }
        return model.beat == .dive ? "dive in" : "continue"
    }
}

struct Keycap: View {
    let text: String
    let light: Bool
    let unit: CGFloat

    var body: some View {
        Text(text)
            .font(UIFonts.swiftUI(11 * unit, weight: 500))
            .padding(.horizontal, 7 * unit)
            .padding(.vertical, 3 * unit)
            .overlay(RoundedRectangle(cornerRadius: 5 * unit, style: .continuous)
                .strokeBorder(Ink.text(light).opacity(0.35), lineWidth: 1))
    }
}

/// An arrow up at the real menu-bar icon, bobbing gently.
private struct MenuCallout: View {
    let rect: CGRect
    @ObservedObject var model: OnboardingModel

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let bob = CGFloat(sin(t * 2.4)) * 4
            let accent = Ink.accent(model.light)
            let top = rect.maxY + 10
            ZStack(alignment: .top) {
                Path { p in
                    p.move(to: CGPoint(x: rect.midX, y: top + 18))
                    p.addLine(to: CGPoint(x: rect.midX, y: top + 120))
                }
                .stroke(accent.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 6]))
                Path { p in
                    p.move(to: CGPoint(x: rect.midX, y: top + bob))
                    p.addLine(to: CGPoint(x: rect.midX - 8, y: top + 12 + bob))
                    p.addLine(to: CGPoint(x: rect.midX + 8, y: top + 12 + bob))
                    p.closeSubpath()
                }
                .fill(accent)
                Circle()
                    .fill(accent.opacity(0.9))
                    .frame(width: 5, height: 5)
                    .position(x: rect.midX, y: top + 124)
                Text("ASCII Animals")
                    .font(UIFonts.swiftUI(12, weight: 500))
                    .kerning(0.5)
                    .foregroundStyle(accent)
                    .fixedSize()
                    .position(x: rect.midX, y: top + 144)
            }
        }
        .allowsHitTesting(false)
    }
}
