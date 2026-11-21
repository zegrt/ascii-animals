import AppKit
import Metal
import OceanKit
import SwiftUI

/// 3.1's what's-new for people upgrading (design d1, option C): a small card in the welcome's voice under the menu bar
/// icon (top right of the main display when the icon is hidden), with the Meadow live in it. Shown once
/// (`Handover.meadowCardKey`, decided by `Handover.launchWelcome`), never to new users.
///
/// It never takes the keyboard from the app in use: it can come up right after an automatic update, mid-work. Its
/// panel never becomes key and has no Return default; Esc closes it while ASCII Animals is the active app, and a click
/// anywhere else closes it always. Closing keeps the current habitat; "Try the Meadow" dissolves the desktop to it.
enum WhatsNewCard {
    static let title = "There's a new habitat: the Meadow."
    static let line = "Butterflies drift over a field of flowers. Hold the pointer still and one may land."
    static let tryTitle = "Try the Meadow"
    /// "Keep the Ocean", "Keep the Web": names what stays rather than "Not now", which promises a later ask.
    static func keepTitle(_ h: HabitatKind) -> String { "Keep the \(h.title)" }

    private static var current: WhatsNewSession?
    private static var waiter: Timer?

    /// About a second after launch, and only once the screen can be seen: after an automatic update at night the
    /// card waits for the screen to wake and unlock rather than be marked shown on a locked screen.
    static func showWhenSeen(app: AppDelegate) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if canBeSeen(app) { present(app: app); return }
            waiter?.invalidate()
            waiter = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { t in
                guard canBeSeen(app) else { return }
                t.invalidate()
                waiter = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { present(app: app) }
            }
        }
    }

    private static func canBeSeen(_ app: AppDelegate) -> Bool {
        let i: PowerInputs = app.signals.inputs
        return !i.screenLocked && !i.displaysAsleep && i.sessionActive && !i.screensaverRunning && !NSScreen.screens.isEmpty
    }

    private static func present(app: AppDelegate) {
        guard current == nil, !OnboardingController.isShowing else { return }
        // Found the Meadow meanwhile (the menu, Settings): nothing to tell.
        let s = app.store.settings
        guard s.habitat != .meadow, !s.meadowTried else { return }
        // No renderer, no Meadow to show: the card waits for a launch that can show it.
        guard let renderer = app.director?.renderer else { return }
        let session = WhatsNewSession(app: app, renderer: renderer)
        current = session
        session.onFinish = { current = nil }
        session.start()
        UserDefaults.standard.set(true, forKey: Handover.meadowCardKey)
    }

    /// Something else took over (the welcome tour opened from Help): the card goes, keeping the habitat.
    static func dismiss() {
        waiter?.invalidate()
        waiter = nil
        current?.close(trying: false)
    }

    /// The Meadow was picked some other way while the card was up (the menu, Settings): it has done its job.
    static func settingsChanged(_ s: OceanKit.Settings) {
        if s.habitat == .meadow { current?.close(trying: false) }
    }

    // MARK: Placement

    static let width: CGFloat = 460
    static let arrowHeight: CGFloat = 8

    /// Where the card goes, in screen coordinates (bottom-left origin): its frame, and the arrow's x in the card when
    /// it points at the icon. Under the icon, the arrow toward the card's right, kept on the screen; with the icon
    /// hidden, the top right of the screen.
    static func placement(size: CGSize, icon: CGRect?, visible: CGRect) -> (frame: CGRect, arrowX: CGFloat?) {
        let margin: CGFloat = 8
        guard let icon else {
            let origin = CGPoint(x: visible.maxX - size.width - 12, y: visible.maxY - 10 - size.height)
            return (CGRect(origin: origin, size: size), nil)
        }
        let preferred: CGFloat = icon.midX - size.width * 0.8
        let lo: CGFloat = visible.minX + margin
        let hi: CGFloat = visible.maxX - margin - size.width
        let x: CGFloat = min(max(preferred, lo), max(lo, hi))
        let top: CGFloat = icon.minY - 2
        let frame = CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
        let arrow: CGFloat = min(max(icon.midX - x, 24), size.width - 24)
        return (frame, arrow)
    }

    // MARK: Snapshot

    /// Debug: render the card as it sits under the menu bar, over the current habitat, to a PNG and exit (no Screen
    /// Recording needed). `--snapshot-whatsnew <png>`; `ASCII_ANIMALS_SNAPSHOT_LIGHT=1` the light look;
    /// `ASCII_ANIMALS_SNAPSHOT_HABITAT=web` someone on the Web ("Keep the Web"; default the Ocean);
    /// `ASCII_ANIMALS_SNAPSHOT_ICON_HIDDEN=1` the menu bar icon hidden (top right, no arrow). The Meadow in the card is
    /// its still, as in Low Power Mode.
    static func snapshot(to url: URL) {
        let env = ProcessInfo.processInfo.environment
        let size = CGSize(width: 1512, height: 982)
        let scale: CGFloat = 2
        let light = env["ASCII_ANIMALS_SNAPSHOT_LIGHT"] != nil
        let iconHidden = env["ASCII_ANIMALS_SNAPSHOT_ICON_HIDDEN"] != nil
        var s = OceanKit.Settings.defaults
        s.appearance = light ? .light : .dark
        if let h = env["ASCII_ANIMALS_SNAPSHOT_HABITAT"].flatMap(HabitatKind.init(rawValue:)), h != .meadow { s.habitat = h }
        do {
            guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError(description: "no Metal device") }
            let renderer = try OceanRenderer(device: device)
            let accent = SIMD3<Float>(0.2, 0.5, 1)
            let desk = try StillRenderer.render(settings: s, size: size, scale: scale, warmup: 6, systemIsDark: !light,
                                                accent: accent, seed: 11, renderer: renderer)
            let model = WhatsNewModel(light: light, keep: s.habitat, reduceMotion: true)
            model.still = try WhatsNewSession.still(settings: s, light: light, renderer: renderer)
            model.finishTyping()
            model.contentVisible = true

            let menuBar: CGFloat = 33
            // Where a menu-bar icon would sit (as the welcome's snapshot has it), in bottom-left coordinates.
            let icon = CGRect(x: size.width - 214, y: size.height - menuBar, width: 30, height: menuBar)
            let visible = CGRect(x: 0, y: 0, width: size.width, height: size.height - menuBar)
            // The arrow's room counts in the card's height: probe with one if it hangs under the icon.
            model.arrowX = iconHidden ? nil : 0
            let probe = NSHostingView(rootView: WhatsNewView(model: model, live: nil))
            let cardSize = CGSize(width: width, height: probe.fittingSize.height)
            let place = placement(size: cardSize, icon: iconHidden ? nil : icon, visible: visible)
            model.arrowX = place.arrowX
            let host = NSHostingView(rootView: WhatsNewView(model: model, live: nil))
            host.frame = CGRect(origin: .zero, size: cardSize)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw RenderError(description: "no card") }
            host.cacheDisplay(in: host.bounds, to: rep)

            let w = Int(size.width * scale), h = Int(size.height * scale)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw RenderError(description: "no context") }
            ctx.interpolationQuality = .high
            ctx.draw(desk, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: scale, y: scale)
            // A stand-in menu bar with the fish, so the card reads as it does on screen.
            ctx.setFillColor(CGColor(gray: light ? 0.92 : 0.12, alpha: 0.85))
            ctx.fill(CGRect(x: 0, y: size.height - menuBar, width: size.width, height: menuBar))
            if !iconHidden, let fish = NSImage(systemSymbolName: "fish", accessibilityDescription: nil) {
                let g = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = g
                let tinted = NSImage(size: fish.size, flipped: false) { r in
                    fish.draw(in: r)
                    (light ? NSColor.black : NSColor.white).set()
                    r.fill(using: .sourceIn)
                    return true
                }
                let fishSize: CGSize = fish.size
                let at = CGRect(x: icon.midX - fishSize.width / 2, y: icon.midY - fishSize.height / 2,
                                width: fishSize.width, height: fishSize.height)
                tinted.draw(in: at)
                NSGraphicsContext.restoreGraphicsState()
            }
            if let card = rep.cgImage {
                // The window's shadow, which the panel gets from macOS.
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: CGColor(gray: 0, alpha: light ? 0.22 : 0.6))
                ctx.draw(card, in: place.frame)
                ctx.restoreGState()
            }
            guard let image = ctx.makeImage() else { throw RenderError(description: "no image") }
            try StillRenderer.writePNG(image, to: url)
            let where_: String = place.arrowX == nil ? "top right, icon hidden" : "under the icon"
            print("wrote \(url.path) (\(light ? "light" : "dark"), \(where_)): \(title) / \(line) / [\(tryTitle)] [\(keepTitle(s.habitat))]")
        } catch {
            FileHandle.standardError.write(Data("what's-new snapshot failed: \(error)\n".utf8))
        }
    }
}

// MARK: - Model

final class WhatsNewModel: ObservableObject {
    let light: Bool
    /// The habitat that stays: "Keep the Ocean" or "Keep the Web".
    let keep: HabitatKind
    let reduceMotion: Bool
    @Published var typedTitle = 0
    @Published var cursorOn = true
    @Published var contentVisible = false
    /// The arrow's x in the card, when it hangs under the icon.
    @Published var arrowX: CGFloat?
    /// The Meadow as a still (Low Power Mode, and the snapshot) instead of live.
    @Published var still: CGImage?
    /// The chip under the pointer (SwiftUI's own state needs macros this package can't load).
    @Published var hovered: String?
    var onTry: () -> Void = {}
    var onKeep: () -> Void = {}

    init(light: Bool, keep: HabitatKind, reduceMotion: Bool) {
        self.light = light
        self.keep = keep
        self.reduceMotion = reduceMotion
    }

    var isTyping: Bool { typedTitle < WhatsNewCard.title.count }
    func finishTyping() { typedTitle = WhatsNewCard.title.count }
}

// MARK: - Panel

/// Never key, never main: the keyboard stays with the app in use. Clicks still reach its chips.
private final class WhatsNewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the first click in a window that isn't key, so a chip answers at once.
private final class FirstClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// One showing of the card: its panel, timers and event monitors. `close` removes all of it.
final class WhatsNewSession {
    private unowned let app: AppDelegate
    private let model: WhatsNewModel
    private let panel: NSPanel
    private let live: LiveOceanView?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var typer: Timer?
    private var blinker: Timer?
    private var closing = false
    var onFinish: (() -> Void)?

    static let previewSize = CGSize(width: WhatsNewCard.width - 32, height: 150)

    /// The Meadow at the person's look and line-up: what the card shows.
    static func meadow(_ s: OceanKit.Settings) -> OceanKit.Settings {
        var m = s
        m.habitat = .meadow
        return m
    }

    /// The card's Meadow as one frame, for Low Power Mode and the snapshot.
    static func still(settings s: OceanKit.Settings, light: Bool, renderer: OceanRenderer) throws -> CGImage {
        let accent = SIMD3<Float>(0.2, 0.5, 1)
        return try StillRenderer.render(settings: meadow(s), size: previewSize, scale: 2, warmup: 6, systemIsDark: !light,
                                        accent: accent, seed: 7, renderer: renderer)
    }

    init(app: AppDelegate, renderer: OceanRenderer) {
        self.app = app
        let s = app.store.settings
        let meadow = WhatsNewSession.meadow(s)
        let theme = OceanDirector.currentTheme(meadow)
        model = WhatsNewModel(light: theme.light, keep: s.habitat,
                              reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        // Live only while the card is up; a still in Low Power Mode.
        if app.signals.inputs.lowPowerMode {
            model.still = try? WhatsNewSession.still(settings: s, light: theme.light, renderer: renderer)
            live = nil
        } else {
            live = LiveOceanView(renderer: renderer, settings: meadow, theme: theme, zoom: 1, seed: 7)
        }

        let iconFrame: CGRect? = s.showMenuBarIcon ? app.menu?.iconScreenFrame : nil
        // The arrow's room counts in the card's height: probe with one if it hangs under the icon.
        model.arrowX = iconFrame == nil ? nil : 0
        let probe = NSHostingView(rootView: WhatsNewView(model: model, live: nil))
        let size = CGSize(width: WhatsNewCard.width, height: probe.fittingSize.height)
        let screen: NSScreen = NSScreen.screens.first { sc in iconFrame.map { sc.frame.intersects($0) } ?? false }
            ?? NSScreen.screens[0]
        let place = WhatsNewCard.placement(size: size, icon: iconFrame, visible: screen.visibleFrame)
        model.arrowX = place.arrowX

        panel = WhatsNewPanel(contentRect: place.frame, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.setFrame(place.frame, display: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.alphaValue = 0
        let host = FirstClickHostingView(rootView: WhatsNewView(model: model, live: live))
        host.frame = CGRect(origin: .zero, size: size)
        panel.contentView = host

        model.onTry = { [weak self] in self?.close(trying: true) }
        model.onKeep = { [weak self] in self?.close(trying: false) }
    }

    func start() {
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = model.reduceMotion ? 0.2 : 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        withAnimation(.easeOut(duration: 0.4)) { model.contentVisible = true }

        // Esc, only while ASCII Animals is the active app (a local monitor sees nothing typed elsewhere).
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard e.keyCode == 53, let self, !self.closing else { return e }
            self.close(trying: false)
            return nil
        }) { monitors.append(m) }
        // A click anywhere else: in another app (no permission needed for clicks) or another of this app's windows.
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            self?.close(trying: false)
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] e in
            if let self, e.window !== self.panel { self.close(trying: false) }
            return e
        }) { monitors.append(m) }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.close(trying: false)
        })

        if model.reduceMotion {
            model.finishTyping()
        } else {
            var pause = 12
            typer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] t in
                guard let self else { t.invalidate(); return }
                if pause > 0 { pause -= 1; return }
                self.model.typedTitle += 1
                if !self.model.isTyping { t.invalidate() }
            }
        }
        blinker = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in self?.model.cursorOn.toggle() }
    }

    /// `trying`: "Try the Meadow". The desktop dissolves to it (the director's habitat change) as the card fades.
    func close(trying: Bool) {
        guard !closing else { return }
        closing = true
        if trying { app.store.update { $0.habitat = .meadow } }
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        typer?.invalidate()
        blinker?.invalidate()
        let duration: Double = trying && !model.reduceMotion ? 0.6 : 0.25
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.teardown() })
        // Whatever happens to the animation, nothing stays on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1) { [weak self] in self?.teardown() }
    }

    private var tornDown = false

    private func teardown() {
        guard !tornDown else { return }
        tornDown = true
        live?.stop()
        panel.orderOut(nil)
        panel.close()
        onFinish?()
    }
}

// MARK: - View

/// The card's outline: a rounded rectangle with, when it hangs under the icon, a small arrow up at it.
private struct CardShape: Shape {
    let arrowX: CGFloat?
    let radius: CGFloat
    let arrow: CGFloat

    func path(in rect: CGRect) -> Path {
        let top: CGFloat = arrowX == nil ? 0 : arrow
        let body = CGRect(x: rect.minX, y: rect.minY + top, width: rect.width, height: rect.height - top)
        var p = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        if let x = arrowX {
            var tip = Path()
            tip.move(to: CGPoint(x: x - arrow - 1, y: body.minY + 0.5))
            tip.addLine(to: CGPoint(x: x, y: rect.minY))
            tip.addLine(to: CGPoint(x: x + arrow + 1, y: body.minY + 0.5))
            tip.closeSubpath()
            p = p.union(tip)
        }
        return p
    }
}

private struct LiveMeadow: NSViewRepresentable {
    let view: LiveOceanView
    func makeNSView(context: Context) -> LiveOceanView {
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true
        return view
    }
    func updateNSView(_ nsView: LiveOceanView, context: Context) {}
}

struct WhatsNewView: View {
    @ObservedObject var model: WhatsNewModel
    let live: LiveOceanView?

    var body: some View {
        let light = model.light
        let ink: Color = Ink.text(light)
        let plate: Color = light ? Color(white: 0.965) : Color(white: 0.035)
        let shape = CardShape(arrowX: model.arrowX, radius: 14, arrow: WhatsNewCard.arrowHeight)
        VStack(alignment: .leading, spacing: 0) {
            preview
                .frame(width: WhatsNewSession.previewSize.width, height: WhatsNewSession.previewSize.height)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ink.opacity(0.14), lineWidth: 1))
                .accessibilityLabel("The Meadow: butterflies over a field of flowers")

            Typed(full: WhatsNewCard.title, count: model.typedTitle,
                  cursor: model.isTyping || model.cursorOn, accent: Ink.accent(light))
                .font(UIFonts.swiftUI(19, weight: 500))
                .kerning(-0.2)
                .padding(.top, 16)

            Text(WhatsNewCard.line)
                .font(UIFonts.swiftUI(12.5))
                .foregroundStyle(ink.opacity(0.62))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            HStack(spacing: 10) {
                CardChip(title: WhatsNewCard.tryTitle, filled: true, model: model, action: model.onTry)
                CardChip(title: WhatsNewCard.keepTitle(model.keep), filled: false, model: model, action: model.onKeep)
                Spacer(minLength: 8)
                Button(action: model.onKeep) {
                    HStack(spacing: 7) {
                        Keycap(text: "esc", light: light, unit: 1)
                        Text("close").font(UIFonts.swiftUI(12))
                    }
                    .foregroundStyle(ink.opacity(0.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(WhatsNewCard.keepTitle(model.keep))
            }
            .padding(.top, 18)
        }
        .foregroundStyle(ink)
        .padding(16)
        .padding(.top, model.arrowX == nil ? 0 : WhatsNewCard.arrowHeight)
        .frame(width: WhatsNewCard.width, alignment: .leading)
        .background(shape.fill(plate))
        .overlay(shape.stroke(ink.opacity(light ? 0.12 : 0.17), lineWidth: 1))
        .opacity(model.contentVisible ? 1 : 0)
    }

    @ViewBuilder private var preview: some View {
        if let still = model.still {
            Image(decorative: still, scale: 2)
                .resizable()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if let live {
            LiveMeadow(view: live)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Ink.plate(model.light))
        }
    }
}

/// The welcome's chips at the card's size: "Try the Meadow" filled, the other outlined. Neither is a Return default.
private struct CardChip: View {
    let title: String
    let filled: Bool
    @ObservedObject var model: WhatsNewModel
    let action: () -> Void

    var body: some View {
        let light = model.light
        let hover = model.hovered == title
        let ink: Color = Ink.text(light)
        let plate: Color = Ink.plate(light)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            Text(title)
                .font(UIFonts.swiftUI(13.5, weight: filled ? 500 : 400))
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .foregroundStyle(filled ? plate : ink.opacity(0.92))
                .background(shape.fill(filled ? ink.opacity(hover ? 1 : 0.9) : plate.opacity(hover ? 0.9 : 0.5)))
                .overlay(shape.strokeBorder(ink.opacity(filled ? 0 : (hover ? 0.5 : 0.25)), lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(PressStyle())
        .onHover { inside in
            if inside { model.hovered = title } else if model.hovered == title { model.hovered = nil }
        }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}
