import AppKit
import Metal
import OceanKit
import SwiftUI

/// 3.1's what's-new for people upgrading (design d1, option C, as changed after the director's live look): a small card
/// in the welcome's voice on the screen in focus, under the menu bar icon when it shows there (top right otherwise),
/// with the Meadow live in it. Never to new users (`Handover.launchWelcome`).
///
/// It never takes the keyboard from the app in use: it can come up right after an automatic update, mid-work. Its
/// panel never becomes key and has no Return default; Esc closes it while ASCII Animals is the active app. A click
/// elsewhere leaves it be. Untouched, it goes after 20 s, a thin line along its bottom edge draining meanwhile; the
/// pointer over it pauses that (`WhatsNew.Countdown`). Going that way is not an answer: it comes back after 3 hours of
/// awake, unlocked time, at most three showings in all (`WhatsNew.Showings`). Try the Meadow, Keep, Esc and its close
/// button end it for good, as does finding the Meadow. Closing keeps the current habitat; "Try the Meadow" dissolves the
/// desktop to it.
enum WhatsNewCard {
    static let title = "There's a new habitat: the Meadow."
    static let line = "Butterflies drift over a field of flowers. Hold the pointer still and one may land."
    static let tryTitle = "Try the Meadow"
    /// "Keep the Ocean", "Keep the Web": names what stays rather than "Not now", which promises a later ask.
    static func keepTitle(_ h: HabitatKind) -> String { "Keep the \(h.title)" }
    static let closeLabel = "Close"

    private static var current: WhatsNewSession?
    private static var presenter: WhatsNew.Presenter?
    private static var looker: Timer?
    /// Counts awake, unlocked time while an unanswered card waits to come back.
    private static var accruer: Timer?

    /// The energy-test copy launched with `ASCII_ANIMALS_PREVIEW_WHATSNEW=1` (`LaunchPlan.Greeting.whatsNewPreview`;
    /// the app people install ignores the flag): the card on the real desktop once, as an upgrader sees it. Its
    /// settings are the defaults held in memory (`LaunchPlan.transientSettings`), its showings and `arrival.v1` are
    /// neither read nor written (this run's memory only), and "Try the Meadow", Keep and Esc only close it
    /// (`PreviewHost`). The welcome from Help is off for the run.
    static let preview: Bool = Launch.plan.greeting == .whatsNewPreview
    /// The preview's showings: this run's memory only.
    private static var previewShowings = WhatsNew.Showings()

    // MARK: Showings

    /// The card's showings: saved (`Handover.meadowShowingsKey`, with the old once-only flag read as "ended"), or
    /// (previewing) this run's memory.
    static func showings(preview: Bool) -> WhatsNew.Showings {
        if preview { return previewShowings }
        let d = UserDefaults.standard
        return WhatsNew.Showings.load(d.data(forKey: Handover.meadowShowingsKey), legacyShown: d.bool(forKey: Handover.meadowCardKey))
    }

    static func save(_ s: WhatsNew.Showings, preview: Bool) {
        if preview {
            previewShowings = s
        } else {
            UserDefaults.standard.set(s.encoded(), forKey: Handover.meadowShowingsKey)
        }
    }

    private static func update(preview: Bool, _ change: (inout WhatsNew.Showings) -> Void) {
        var s: WhatsNew.Showings = showings(preview: preview)
        change(&s)
        save(s, preview: preview)
    }

    /// Counts a showing once it reached the screen. It writes no energy evidence: the offscreen probe calls it too, and
    /// only the live presenter logs the card (`showWhenSeen`).
    static func markShown(preview: Bool) {
        update(preview: preview) { $0.shown() }
    }

    // MARK: Waiting

    /// From launch (`OnboardingController.showIfNeeded`): the card is due, or comes back once its 3 hours have passed.
    /// Due, it comes about a second later, and only once the screen can be seen: after an automatic update at night it
    /// waits for the screen to wake and unlock rather than spend a showing on a locked screen. It looks once a second
    /// (`WhatsNew.Presenter`); every look reads the session, lock and displays live. Not due yet, it counts awake,
    /// unlocked time every 30 s (`WhatsNew.Showings.accrue`), saved as it goes, and looks again when it is.
    static func showWhenSeen(app: AppDelegate) {
        stopLooking()
        var s: WhatsNew.Showings = showings(preview: preview)
        let settings: OceanKit.Settings = cardHost(app).cardSettings
        if !preview, settings.habitat == .meadow || settings.meadowTried {
            // Found the Meadow meanwhile: nothing to tell, ever.
            s.end()
            save(s, preview: preview)
        }
        if s.finished { return }
        if s.due { present(app) } else { accrue(app) }
    }

    private static func present(_ app: AppDelegate) {
        let previewing: Bool = preview
        let p = WhatsNew.Presenter(moment: { moment(app) }, open: { open(app) },
                                   mark: {
                                       markShown(preview: previewing)
                                       // Tools/energy.sh preview waits for this line, bound to its launch id.
                                       if previewing { Log.write(EnergyLog.cardShown(pid: getpid(), launch: Launch.plan.launchID)) }
                                   })
        presenter = p
        looker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if p.look() != .keepWaiting { stopLooking() }
        }
    }

    private static func accrue(_ app: AppDelegate) {
        var last: TimeInterval = ProcessInfo.processInfo.systemUptime
        let t = CommonTimer.repeating(every: 30) { _ in
            let now: TimeInterval = ProcessInfo.processInfo.systemUptime
            let seen: Bool = target(app).map { seeable(app, NSScreen.screens[$0.screen]) } ?? false
            var s: WhatsNew.Showings = showings(preview: preview)
            s.accrue(now - last, seeable: seen)
            last = now
            save(s, preview: preview)
            if s.due || s.finished { showWhenSeen(app: app) }
        }
        t.tolerance = 5
        accruer = t
    }

    private static func stopLooking() {
        looker?.invalidate()
        looker = nil
        accruer?.invalidate()
        accruer = nil
        presenter?.cancel()
        presenter = nil
    }

    private static func moment(_ app: AppDelegate) -> WhatsNew.Moment {
        let host: WhatsNewHost = cardHost(app)
        let s: OceanKit.Settings = host.cardSettings
        let seen: Bool = target(app).map { seeable(app, NSScreen.screens[$0.screen]) } ?? false
        let shown: Bool = !showings(preview: preview).due || current != nil
        let tried: Bool = preview ? false : s.meadowTried
        return WhatsNew.Moment(seeable: seen, screens: NSScreen.screens.count, shown: shown,
                               habitat: s.habitat, tried: tried, welcomeUp: OnboardingController.isShowing,
                               canDraw: app.director?.renderer != nil)
    }

    /// Who the card answers to: the app, or (previewing) a stand-in over it that changes nothing.
    private static var previewHost: PreviewHost?
    private static func cardHost(_ app: AppDelegate) -> WhatsNewHost {
        guard preview else { return app }
        if let previewHost { return previewHost }
        let h = PreviewHost(over: app)
        previewHost = h
        return h
    }

    /// Unlocked, on the console, no screensaver, and this screen's display awake, as macOS says right now (an
    /// already-asleep display at launch sends no notification).
    static func seeable(_ app: AppDelegate, _ screen: NSScreen) -> Bool {
        let i: PowerInputs = PowerPolicy.reconcile(app.signals.inputs, session: SystemSignals.sessionTruth())
        guard !i.screenLocked, i.sessionActive, !i.screensaverRunning, !i.displaysAsleep else { return false }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let id = (screen.deviceDescription[key] as? NSNumber)?.uint32Value else { return false }
        return CGDisplayIsAsleep(id) == 0
    }

    /// The screens as the menu bar sees them, and the one in focus (`NSScreen.main`: the screen with the active menu
    /// bar and the keyboard focus, whichever app has it).
    static func menuBarScreens() -> (screens: [MenuBarScreen], focused: Int?) {
        let all: [NSScreen] = NSScreen.screens
        let facts: [MenuBarScreen] = all.map { (s: NSScreen) -> MenuBarScreen in
            MenuBarScreen(frame: s.frame, visible: s.visibleFrame,
                          besideNotch: [s.auxiliaryTopLeftArea, s.auxiliaryTopRightArea].compactMap { $0 })
        }
        let focused: Int? = NSScreen.main.flatMap { (m: NSScreen) -> Int? in all.firstIndex(of: m) }
        return (facts, focused)
    }

    /// The screen the card goes on (an index into `NSScreen.screens`), the screen in focus, and the icon it hangs
    /// under when the icon is showing there (`MenuBarIcon.place`: on that screen's menu bar, not behind a notch);
    /// otherwise no icon, and the card goes top right. nil with no screens.
    static func target(_ app: AppDelegate) -> (screen: Int, icon: CGRect?)? {
        let (screens, focused) = menuBarScreens()
        let icon: CGRect? = app.store.settings.showMenuBarIcon ? app.menu?.iconAnchorFrame : nil
        return MenuBarIcon.place(icon: icon, screens: screens, focused: focused)
    }

    /// Builds the card and orders it forward. True only when it reached a usable display that can still be seen;
    /// otherwise it goes again at once, unmarked, and the presenter waits.
    private static func open(_ app: AppDelegate) -> Bool {
        guard current == nil, let renderer = app.director?.renderer, let t = target(app) else { return false }
        let screen: NSScreen = NSScreen.screens[t.screen]
        let session = WhatsNewSession(host: cardHost(app), renderer: renderer, visible: screen.visibleFrame, icon: t.icon)
        current = session
        session.onFinish = { [weak session] in if current === session { current = nil } }
        guard session.orderFront(), seeable(app, screen) else {
            session.close(trying: false, now: true)
            current = nil
            return false
        }
        let previewing: Bool = preview
        let pid: Int32 = getpid()
        let launch: String? = Launch.plan.launchID
        session.onClose = { (reason: WhatsNew.CloseReason, after: Double) in
            update(preview: previewing) { $0.closed(reason) }
            if previewing { Log.write(EnergyLog.cardClosed(pid: pid, launch: launch, reason: reason, after: after)) }
            // Unanswered: it waits to come back (counting from now). The welcome taking over looks again itself.
            if !reason.endsForGood, reason != .welcome {
                DispatchQueue.main.async { showWhenSeen(app: app) }
            }
        }
        session.arm(power: app.signals.inputs)
        if preview { watchPreview(session) }
        return true
    }

    // MARK: The preview's evidence

    /// The preview (`Tools/energy.sh preview`) logs, bound to its launch id, how much of the card is drawn once it has
    /// faded in (`EnergyLog.cardDrawn`, with the window's image saved as build/energy-test/card-drawn.png); `open` logs
    /// when and why it went (`EnergyLog.cardClosed`). A card that draws empty shows in the log, not only to the eye.
    private static func watchPreview(_ session: WhatsNewSession) {
        let pid: Int32 = getpid()
        let launch: String? = Launch.plan.launchID
        DispatchQueue.main.asyncAfter(deadline: .now() + drawnCheckDelay) { [weak session] in
            guard let session, current === session, !session.isClosing else { return }
            let png: URL? = Launch.testFolder.flatMap { (f: URL) -> URL? in
                Launch.confined(f.appendingPathComponent("card-drawn.png"), to: f)
            }
            guard let d = session.measureDrawn(savingTo: png) else {
                Log.write("energy-card: no image of the card to measure")
                return
            }
            Log.write("card drawn check: \(d.source)\(png == nil ? "" : ", saved card-drawn.png")")
            Log.write(EnergyLog.cardDrawn(pid: pid, launch: launch, share: d.share, width: d.width, height: d.height))
        }
    }

    /// After the fade-in (0.45 s) and the content's (0.4 s), with room to spare.
    static let drawnCheckDelay: TimeInterval = 1.5

    /// The welcome is opening from Help: no more looks, and a card up goes at once (no fade under the welcome).
    /// Returns whether a card was still waiting or up, so the caller can wait again if the welcome couldn't open (a
    /// welcome that reached the screen ends the card for good: `Handover.meadowCardKey`).
    @discardableResult
    static func dismiss() -> Bool {
        let waiting: Bool = presenter != nil || accruer != nil || current != nil
        stopLooking()
        current?.close(trying: false, now: true, reason: .welcome)
        current = nil
        return waiting
    }

    /// Settings changed elsewhere (the menu, Settings, the keyboard): on the Meadow, the card has done its job; on
    /// another habitat, its Keep chip names that one.
    static func settingsChanged(_ s: OceanKit.Settings) {
        current?.settingsChanged(s)
    }

    /// The machine's state changed: the live preview holds a still in Low Power Mode and stops when it can't be seen.
    static func powerChanged(_ i: PowerInputs) {
        current?.apply(WhatsNew.preview(i))
    }

    // MARK: Placement

    static var width: CGFloat { WhatsNew.width }
    static let arrowHeight: CGFloat = 8

    // MARK: Snapshot

    /// Debug: render the card as it sits under the menu bar, over the current habitat, to a PNG and exit (no Screen
    /// Recording needed). `--snapshot-whatsnew <png>`; `ASCII_ANIMALS_SNAPSHOT_LIGHT=1` the light look;
    /// `ASCII_ANIMALS_SNAPSHOT_HABITAT=web` someone on the Web ("Keep the Web"; default the Ocean);
    /// `ASCII_ANIMALS_SNAPSHOT_ICON_HIDDEN=1` the menu bar icon hidden (top right, no arrow);
    /// `ASCII_ANIMALS_SNAPSHOT_SCREEN=<w>x<h>` another screen size (a narrow one fits the card to it);
    /// `ASCII_ANIMALS_SNAPSHOT_REMAINING=<0…1>` the countdown's line (default 0.6). The Meadow in the card is its still,
    /// as in Low Power Mode.
    static func snapshot(to url: URL) {
        let env = ProcessInfo.processInfo.environment
        var size = CGSize(width: 1512, height: 982)
        if let wh = env["ASCII_ANIMALS_SNAPSHOT_SCREEN"]?.split(separator: "x").compactMap({ Double($0) }), wh.count == 2 {
            size = CGSize(width: wh[0], height: wh[1])
        }
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
            let menuBar: CGFloat = 33
            // Where a menu-bar icon would sit (as the welcome's snapshot has it), in bottom-left coordinates.
            let icon = CGRect(x: size.width - 214, y: size.height - menuBar, width: 30, height: menuBar)
            let visible = CGRect(x: 0, y: 0, width: size.width, height: size.height - menuBar)
            let model = WhatsNewModel(light: light, keep: s.habitat, reduceMotion: true, width: WhatsNew.width(visible: visible))
            model.still = try WhatsNewSession.still(settings: s, light: light, preview: model.previewSize, renderer: renderer)
            model.cover = true
            model.finishTyping()
            model.contentVisible = true
            // The countdown's line part drained, as a few seconds in (`ASCII_ANIMALS_SNAPSHOT_REMAINING=<0…1>`).
            model.remaining = env["ASCII_ANIMALS_SNAPSHOT_REMAINING"].flatMap(Double.init).map { min(1, max(0, $0)) } ?? 0.6
            let place = WhatsNewSession.layout(model, icon: iconHidden ? nil : icon, visible: visible)
            let host = NSHostingView(rootView: WhatsNewView(model: model, live: nil))
            host.frame = CGRect(origin: .zero, size: place.frame.size)
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
            let frame: String = "card \(Int(place.frame.minX)),\(Int(place.frame.minY)) \(Int(place.frame.width))x\(Int(place.frame.height))"
            let pv: CGSize = model.previewSize
            let pick = WhatsNew.stillFrame(WhatsNewSession.meadow(s), preview: pv, cell: GridSpec.cell(forWidth: WhatsNew.stillArea(pv).width))
            let still: String = pick.map { p in
                "still: seed \(p.seed), a whole \(p.frame.kind.name), \(p.frame.flowersInside) whole blooms, "
                    + "cut \(p.frame.cut) butterflies and \(p.frame.cutBlooms) blooms, covered \(String(format: "%.2f", p.frame.covered))"
            } ?? "still: no frame"
            print("wrote \(url.path) (\(light ? "light" : "dark"), \(where_), \(frame) on \(Int(size.width))x\(Int(size.height)); \(still)): "
                  + "\(title) / \(line) / [\(tryTitle)] [\(keepTitle(s.habitat))]")
        } catch {
            FileHandle.standardError.write(Data("what's-new snapshot failed: \(error)\n".utf8))
        }
    }

    /// Debug: drive a card offscreen and write what it did, one line per probe, to a text file, and exit
    /// (`--snapshot-whatsnew-probe <txt>`). The panel is built but never ordered onto a screen, and nothing is saved:
    /// its host is a stand-in. Probes what needs AppKit: Esc closes and still reaches the window it was meant for; a
    /// closing card lets clicks through; the Keep chip follows the habitat; the preview follows the machine's state.
    static func probe(to url: URL) {
        var lines: [String] = []
        var failed = 0
        func expect(_ ok: Bool, _ what: String) {
            if !ok { failed += 1 }
            lines.append((ok ? "ok    " : "FAIL  ") + what)
        }
        guard let device = MTLCreateSystemDefaultDevice(), let renderer = try? OceanRenderer(device: device) else {
            FileHandle.standardError.write(Data("what's-new probe: no Metal device\n".utf8))
            return
        }
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let icon = CGRect(x: 1298, y: 949, width: 30, height: 33)
        func make(_ host: WhatsNewHost) -> WhatsNewSession {
            WhatsNewSession(host: host, renderer: renderer, visible: visible, icon: icon)
        }
        let esc: NSEvent? = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                             context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                             isARepeat: false, keyCode: 53)
        let a: NSEvent? = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, characters: "a", charactersIgnoringModifiers: "a",
                                           isARepeat: false, keyCode: 0)
        if let esc, let a {
            let host = ProbeHost()
            let card = make(host)
            expect(card.key(esc, appActive: false) === esc && !card.isClosing, "Esc with another app active: passed on, card stays")
            expect(card.key(a, appActive: true) === a && !card.isClosing, "another key: passed on, card stays")
            let back = card.key(esc, appActive: true)
            expect(back === esc, "Esc while ASCII Animals is active: still delivered (Settings, a sheet)")
            expect(card.isClosing, "Esc while ASCII Animals is active: closes the card")
            expect(card.ignoresClicks, "a closing card lets clicks through at once")
            expect(host.tried == 0, "Esc keeps the habitat")
            card.close(trying: false, now: true)
        } else {
            expect(false, "made the key events")
        }

        let host = ProbeHost()
        let card = make(host)
        expect(!card.ignoresClicks, "an open card takes clicks")
        expect(card.keepLabel == "Keep the Ocean", "Keep chip on the Ocean: \(card.keepLabel)")
        var web = host.settings
        web.habitat = .web
        card.settingsChanged(web)
        expect(card.keepLabel == "Keep the Web" && !card.isClosing, "switched to the Web elsewhere: \(card.keepLabel), card stays")
        var lowPower = PowerInputs()
        lowPower.lowPowerMode = true
        card.apply(WhatsNew.preview(PowerInputs()))
        expect(card.previewState == "live", "the preview is live: \(card.previewState)")
        card.apply(WhatsNew.preview(lowPower))
        expect(card.previewState == "still", "Low Power Mode turned on: holds a still (\(card.previewState))")
        var locked = PowerInputs()
        locked.screenLocked = true
        card.apply(WhatsNew.preview(locked))
        expect(card.previewState == "stopped", "screen locked: stops drawing (\(card.previewState))")
        card.apply(WhatsNew.preview(PowerInputs()))
        expect(card.previewState == "live", "unlocked: live again (\(card.previewState))")
        var meadow = web
        meadow.habitat = .meadow
        card.settingsChanged(meadow)
        expect(card.isClosing && host.tried == 0, "the Meadow picked elsewhere: the card goes, nothing more to set")
        card.close(trying: false, now: true)

        let tryHost = ProbeHost()
        let tryCard = make(tryHost)
        tryCard.close(trying: true)
        expect(tryHost.tried == 1 && tryCard.ignoresClicks, "Try the Meadow: the habitat changes once, the fading card lets clicks through")
        tryCard.close(trying: false, now: true)

        // The live preview (ASCII_ANIMALS_PREVIEW_WHATSNEW=1): the same card over a stand-in that changes nothing.
        // The session holds its host weakly, as it holds the app: each stand-in is kept here while its card is up.
        let under = ProbeHost()
        let tryStandIn = PreviewHost(over: under)
        let previewTry = make(tryStandIn)
        expect(previewTry.keepLabel == "Keep the Ocean", "preview: Keep chip on the Ocean: \(previewTry.keepLabel)")
        previewTry.close(trying: true)
        expect(under.tried == 0 && previewTry.isClosing && previewTry.ignoresClicks,
               "preview: Try the Meadow only closes the card (the habitat stays)")
        previewTry.close(trying: false, now: true)
        tryStandIn.tryMeadow()
        expect(under.tried == 0, "preview: its host passes nothing on to the app")
        let keepStandIn = PreviewHost(over: under)
        let previewKeep = make(keepStandIn)
        previewKeep.close(trying: false)
        expect(under.tried == 0 && previewKeep.isClosing, "preview: Keep only closes the card")
        previewKeep.close(trying: false, now: true)
        if let esc {
            let escStandIn = PreviewHost(over: under)
            let previewEsc = make(escStandIn)
            _ = previewEsc.key(esc, appActive: true)
            expect(under.tried == 0 && previewEsc.isClosing, "preview: Esc only closes the card")
            previewEsc.close(trying: false, now: true)
            withExtendedLifetime(escStandIn) {}
        }
        withExtendedLifetime((tryStandIn, keepStandIn)) {}
        var onMeadow = under.settings
        onMeadow.habitat = .meadow
        under.settings = onMeadow
        let meadowHost = PreviewHost(over: under)
        let meadowCard = make(meadowHost)
        expect(meadowHost.cardSettings.habitat == .ocean && meadowCard.keepLabel == "Keep the Ocean" && !meadowCard.isClosing,
               "preview on the Meadow: shown as to someone on the Ocean (\(meadowCard.keepLabel))")
        meadowCard.close(trying: false, now: true)
        let flag: Any? = UserDefaults.standard.object(forKey: Handover.meadowCardKey)
        let saved: Data? = UserDefaults.standard.data(forKey: Handover.meadowShowingsKey)
        let before: WhatsNew.Showings = showings(preview: true)
        markShown(preview: true)
        let after: WhatsNew.Showings = showings(preview: true)
        let flagAfter: Any? = UserDefaults.standard.object(forKey: Handover.meadowCardKey)
        let flagSame: Bool = (flag == nil) == (flagAfter == nil) && (flag as? Bool) == (flagAfter as? Bool)
        let savedSame: Bool = UserDefaults.standard.data(forKey: Handover.meadowShowingsKey) == saved
        expect(before.count == 0 && after.count == 1 && flagSame && savedSame,
               "preview: a showing kept in memory only (the saved flag and showings untouched: \(flagAfter.map { "\($0)" } ?? "absent"))")

        // Fix round 1: clicks elsewhere leave it be; untouched it goes after 20 s, the pointer over it pauses that.
        let timed = make(ProbeHost())
        var reasons: [WhatsNew.CloseReason] = []
        timed.onClose = { (r: WhatsNew.CloseReason, _: Double) in reasons.append(r) }
        timed.arm(power: PowerInputs())
        timed.setHovering(false)
        func run(_ card: WhatsNewSession, _ seconds: Double) {
            var left: Double = seconds
            while left > 0 {
                let step: Double = min(0.1, left)
                card.advance(by: step)
                left -= step
            }
        }
        run(timed, 10)
        expect(!timed.isClosing && abs(timed.countdownRemaining - 10) < 0.01, "10 s untouched: still up, 10 s left (\(timed.countdownRemaining))")
        timed.setHovering(true)
        run(timed, 60)
        expect(!timed.isClosing && abs(timed.countdownRemaining - 10) < 0.01, "the pointer over it for a minute: paused (\(timed.countdownRemaining))")
        timed.setHovering(false)
        timed.advance(by: 30)
        expect(!timed.isClosing && timed.countdownRemaining > 9.7, "a 30 s stall counts a quarter second at most (\(timed.countdownRemaining))")
        var stopped = PowerInputs()
        stopped.screenLocked = true
        timed.apply(WhatsNew.preview(stopped))
        run(timed, 30)
        expect(!timed.isClosing, "the screen locked: paused")
        timed.apply(WhatsNew.preview(PowerInputs()))
        run(timed, 9.5)
        expect(!timed.isClosing, "19.5 s of looking: still up")
        run(timed, 0.6)
        expect(timed.isClosing && reasons == [.timeout] && timed.ignoresClicks, "20 s untouched: it goes, unanswered (\(reasons))")
        timed.close(trying: false, now: true)

        let closer = make(ProbeHost())
        var closeReasons: [WhatsNew.CloseReason] = []
        closer.onClose = { (r: WhatsNew.CloseReason, _: Double) in closeReasons.append(r) }
        closer.arm(power: PowerInputs())
        closer.pressCloseForProbe()
        expect(closer.isClosing && closeReasons == [.close] && WhatsNew.CloseReason.close.endsForGood,
               "the close button: it goes for good (\(closeReasons))")
        closer.close(trying: false, now: true)

        // The return logic as the app runs it: in the preview's memory, the clock faked.
        save(WhatsNew.Showings(), preview: true)
        markShown(preview: true)
        update(preview: true) { $0.closed(.timeout) }
        update(preview: true) { $0.accrue(3 * 3600 - 60, seeable: true) }
        expect(!showings(preview: true).due, "a timeout: not back before 3 h")
        update(preview: true) { $0.accrue(10_000, seeable: false) }
        expect(!showings(preview: true).due, "locked or asleep time doesn't count")
        update(preview: true) { $0.accrue(60, seeable: true) }
        expect(showings(preview: true).due, "3 h awake: back")
        markShown(preview: true)
        update(preview: true) { $0.closed(.timeout) }
        update(preview: true) { $0.accrue(3 * 3600, seeable: true) }
        markShown(preview: true)
        update(preview: true) { $0.closed(.timeout) }
        update(preview: true) { $0.accrue(10 * 3600, seeable: true) }
        let three: WhatsNew.Showings = showings(preview: true)
        expect(three.count == 3 && three.finished && !three.due, "three showings unanswered: never again (\(three))")
        save(WhatsNew.Showings(), preview: true)
        markShown(preview: true)
        update(preview: true) { $0.closed(.keep) }
        expect(showings(preview: true).finished, "Keep: never again")
        save(WhatsNew.Showings(), preview: true)
        // The probe is offscreen: it never writes the live card evidence energy.sh waits for, and has no launch id.
        let cardLine: String = "energy-card: pid=\(getpid()) "
        let logged: Bool = Log.tail(4000).contains { (l: String) -> Bool in l.contains(cardLine) }
        expect(!logged && Launch.plan.launchID == nil, "probe: no live card line logged, no launch id")

        lines.append("\(lines.count) probes, \(failed) failed")
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        print(lines.joined(separator: "\n"))
    }

    /// Debug: the preview's drawn check on the real card, offscreen, and exit (`--snapshot-whatsnew-drawn <png>`).
    /// The card is built as the live one is (the live Meadow in it), placed far off every display (nothing shows),
    /// ordered in, faded in, and after `drawnCheckDelay` its window's own image is measured the way the live preview
    /// measures it (`measureDrawn`) and saved to the PNG. `ASCII_ANIMALS_SNAPSHOT_BLANK=1` hides its content after the
    /// fade-in, the failure the director saw live, to show the check catches it. Prints the line the preview logs. Run it
    /// with the displays awake and the screen unlocked: the window server draws no window otherwise (it says so).
    /// `ASCII_ANIMALS_SNAPSHOT_ICON_HIDDEN=1`: the card with no arrow (the icon hidden).
    static func drawnProbe(to url: URL) {
        NSApp.setActivationPolicy(.accessory)
        guard let device = MTLCreateSystemDefaultDevice(), let renderer = try? OceanRenderer(device: device) else {
            FileHandle.standardError.write(Data("what's-new drawn probe: no Metal device\n".utf8))
            exit(1)
        }
        let blank: Bool = ProcessInfo.processInfo.environment["ASCII_ANIMALS_SNAPSHOT_BLANK"] != nil
        // Far from every display: the window server still keeps its image, and nobody sees it.
        let visible = CGRect(x: -30000, y: -30000, width: 1800, height: 1130)
        let iconHidden: Bool = ProcessInfo.processInfo.environment["ASCII_ANIMALS_SNAPSHOT_ICON_HIDDEN"] != nil
        let icon: CGRect? = iconHidden ? nil : CGRect(x: visible.minX + 1389, y: visible.maxY + 2, width: 30, height: 37)
        let host = PreviewHost(over: ProbeHost())
        let session = WhatsNewSession(host: host, renderer: renderer, visible: visible, icon: icon)
        _ = session.orderFront()
        session.arm(power: PowerInputs())
        if blank {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { session.hideContentForProbe() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + drawnCheckDelay + (blank ? 0.5 : 0)) {
            guard let d = session.measureDrawn(savingTo: url) else {
                FileHandle.standardError.write(Data("what's-new drawn probe: no image of the card\n".utf8))
                exit(1)
            }
            // The window server draws no window while the displays sleep or the screen is locked: say so, so a 0
            // then is not read as the card's fault (the live card waits for a screen that can be seen).
            let asleep: Bool = NSScreen.screens.contains { (screen: NSScreen) -> Bool in
                let id: UInt32 = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                return CGDisplayIsAsleep(id) != 0
            }
            let locked: Bool = SystemSignals.sessionTruth().screenLocked
            let state: String = asleep || locked ? "; NOT MEANINGFUL: the displays are asleep or the screen is locked" : ""
            print("\(EnergyLog.cardDrawn(pid: getpid(), launch: nil, share: d.share, width: d.width, height: d.height)) "
                  + "(\(d.source)\(blank ? ", content hidden" : "")\(state); wrote \(url.path))")
            withExtendedLifetime(host) {}
            exit(0)
        }
        NSApp.run()
    }
}

/// What a card needs from the app: its settings, the Meadow when tried. The app is one; the probe has a stand-in.
protocol WhatsNewHost: AnyObject {
    var cardSettings: OceanKit.Settings { get }
    func tryMeadow()
}

extension AppDelegate: WhatsNewHost {
    var cardSettings: OceanKit.Settings { store.settings }
    func tryMeadow() { store.update { $0.habitat = .meadow } }
}

/// The live preview's host (`WhatsNewCard.preview`): the card reads the app's settings (held in memory in the preview)
/// and changes nothing. On the Meadow it is shown as to someone on the Ocean (an upgrader is never shown it on the Meadow), in memory only.
final class PreviewHost: WhatsNewHost {
    private weak var base: WhatsNewHost?
    init(over base: WhatsNewHost) { self.base = base }
    var cardSettings: OceanKit.Settings {
        var s: OceanKit.Settings = base?.cardSettings ?? .defaults
        if s.habitat == .meadow { s.habitat = .ocean }
        return s
    }
    /// "Try the Meadow" in the preview: the card closes and nothing else happens.
    func tryMeadow() {}
}

/// The probe's host: settings in memory, nothing saved.
private final class ProbeHost: WhatsNewHost {
    var settings: OceanKit.Settings = .defaults
    var tried = 0
    var cardSettings: OceanKit.Settings { settings }
    func tryMeadow() { tried += 1 }
}

// MARK: - Model

final class WhatsNewModel: ObservableObject {
    let light: Bool
    /// The habitat that stays: "Keep the Ocean" or "Keep the Web". Follows a change made elsewhere.
    @Published var keep: HabitatKind
    let reduceMotion: Bool
    /// The card's width: the design's, or narrower on a narrow screen (`WhatsNew.width(visible:)`).
    let width: CGFloat
    @Published var typedTitle = 0
    @Published var cursorOn = true
    @Published var contentVisible = false
    /// The arrow's x in the card, when it hangs under the icon.
    @Published var arrowX: CGFloat?
    /// The Meadow as a still (Low Power Mode, and the snapshot).
    @Published var still: CGImage?
    /// The live view is in the card (it joins the first time the preview goes live, and then stays, its drawing
    /// started and stopped by the session).
    @Published var liveAttached = false
    /// The live view is covered: by the still, or by a plain plate while nothing is drawn.
    @Published var cover = false
    /// The chip under the pointer (SwiftUI's own state needs macros this package can't load).
    @Published var hovered: String?
    /// The countdown's line along the bottom edge: 1 full, 0 run out (`WhatsNew.Countdown.fraction`).
    @Published var remaining: Double = 1
    var onTry: () -> Void = {}
    var onKeep: () -> Void = {}
    var onClose: () -> Void = {}

    init(light: Bool, keep: HabitatKind, reduceMotion: Bool, width: CGFloat) {
        self.light = light
        self.keep = keep
        self.reduceMotion = reduceMotion
        self.width = width
    }

    var previewSize: CGSize { CGSize(width: max(1, width - 32), height: 150) }
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
/// Also tells, in any app state, whether the pointer is over the card (the countdown pauses then).
private final class FirstClickHostingView<V: View>: NSHostingView<V> {
    var onHover: (Bool) -> Void = { _ in }
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover(false)
    }
}

/// One showing of the card: its panel, timers and event monitors. `close` removes all of it.
final class WhatsNewSession {
    private weak var host: WhatsNewHost?
    private let model: WhatsNewModel
    private let panel: NSPanel
    private let live: LiveOceanView
    private let renderer: OceanRenderer
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var typer: Timer?
    private var blinker: Timer?
    private var closing = false
    private var preview: WhatsNew.Preview?
    var onFinish: (() -> Void)?
    /// Told once when the card starts to go, with why and how many seconds after `arm`.
    var onClose: ((WhatsNew.CloseReason, Double) -> Void)?
    private var armedAt: Date?
    private var countdown = WhatsNew.Countdown()
    private var ticker: Timer?
    private var lastTick: CFTimeInterval = 0
    /// The pointer is over the card: the countdown waits.
    private(set) var hovering = false

    /// The Meadow at the person's look and line-up: what the card shows.
    static func meadow(_ s: OceanKit.Settings) -> OceanKit.Settings {
        var m = s
        m.habitat = .meadow
        return m
    }

    /// The card's Meadow as one frame, for Low Power Mode and the snapshot: cut from a bigger meadow around a whole
    /// butterfly beside a whole bloom (`WhatsNew.stillFrame`), at the live preview's cell size.
    static func still(settings s: OceanKit.Settings, light: Bool, preview: CGSize, renderer: OceanRenderer) throws -> CGImage {
        let accent = SIMD3<Float>(0.2, 0.5, 1)
        let m = meadow(s)
        let area: CGSize = WhatsNew.stillArea(preview)
        let cell: CGSize = GridSpec.cell(forWidth: area.width)
        guard let pick = WhatsNew.stillFrame(m, preview: preview, cell: cell) else {
            return try StillRenderer.render(settings: m, size: preview, scale: 2, warmup: 6, systemIsDark: !light,
                                            accent: accent, seed: 7, renderer: renderer)
        }
        let scale: CGFloat = 2
        let full = try StillRenderer.render(settings: m, size: area, scale: scale, warmup: 6, systemIsDark: !light,
                                            accent: accent, seed: pick.seed, renderer: renderer)
        let c: CGRect = pick.frame.crop
        let px = CGRect(x: (c.minX * scale).rounded(), y: (c.minY * scale).rounded(),
                        width: (c.width * scale).rounded(), height: (c.height * scale).rounded())
        guard let cut = full.cropping(to: px) else { throw RenderError(description: "the still's crop") }
        return cut
    }

    /// Sizes the card for its arrow (the arrow's room counts in its height) and places it.
    static func layout(_ model: WhatsNewModel, icon: CGRect?, visible: CGRect) -> (frame: CGRect, arrowX: CGFloat?) {
        model.arrowX = icon == nil ? nil : 0
        let probe = NSHostingView(rootView: WhatsNewView(model: model, live: nil))
        let size = CGSize(width: model.width, height: probe.fittingSize.height)
        let place = WhatsNew.placement(size: size, icon: icon, visible: visible)
        model.arrowX = place.arrowX
        return place
    }

    init(host: WhatsNewHost, renderer: OceanRenderer, visible: CGRect, icon: CGRect?) {
        self.host = host
        self.renderer = renderer
        let s = host.cardSettings
        let meadow = WhatsNewSession.meadow(s)
        let theme = OceanDirector.currentTheme(meadow)
        model = WhatsNewModel(light: theme.light, keep: s.habitat,
                              reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                              width: WhatsNew.width(visible: visible))
        // Drawn only while the preview is live (`apply`).
        live = LiveOceanView(renderer: renderer, settings: meadow, theme: theme, zoom: 1, seed: 7)

        let place = WhatsNewSession.layout(model, icon: icon, visible: visible)
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
        let view = FirstClickHostingView(rootView: WhatsNewView(model: model, live: live))
        view.frame = CGRect(origin: .zero, size: place.frame.size)
        panel.contentView = view

        model.onTry = { [weak self] in self?.close(trying: true, reason: .tryMeadow) }
        model.onKeep = { [weak self] in self?.close(trying: false, reason: .keep) }
        model.onClose = { [weak self] in self?.close(trying: false, reason: .close) }
        view.onHover = { [weak self] inside in self?.hovering = inside }
    }

    /// Puts the panel on screen without activating the app. True when it is there: visible, on a display.
    func orderFront() -> Bool {
        panel.orderFrontRegardless()
        return panel.isVisible && panel.screen != nil
    }

    /// The card is up for good: fade in, type, listen for Esc and clicks elsewhere, and set the preview going.
    func arm(power: PowerInputs) {
        armedAt = Date()
        apply(WhatsNew.preview(power))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = model.reduceMotion ? 0.2 : 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        withAnimation(.easeOut(duration: 0.4)) { model.contentVisible = true }

        // Esc, only while ASCII Animals is the active app (a local monitor sees nothing typed elsewhere).
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            self?.key(e, appActive: NSApp.isActive) ?? e
        }) { monitors.append(m) }
        // A click elsewhere leaves the card be (it reaches what was clicked); untouched, the card goes by itself.
        hovering = panel.frame.contains(NSEvent.mouseLocation)
        lastTick = CACurrentMediaTime()
        ticker = CommonTimer.repeating(every: 1.0 / 30) { [weak self] _ in
            guard let self else { return }
            let now: CFTimeInterval = CACurrentMediaTime()
            self.advance(by: now - self.lastTick)
            self.lastTick = now
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.close(trying: false, reason: .screens)
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

    /// The countdown moves on by `seconds`: paused while the pointer is over the card or nothing is drawn (the screen
    /// can't be seen); run out, the card goes, unanswered (`CloseReason.timeout`). The probe drives it directly.
    func advance(by seconds: Double) {
        guard !closing else { return }
        countdown.advance(by: seconds, paused: hovering || preview == .stopped)
        let f: Double = countdown.fraction
        if abs(model.remaining - f) >= 0.001 || f == 0 { model.remaining = f }
        if countdown.expired { close(trying: false, reason: .timeout) }
    }

    /// The probe's stand-ins for the pointer moving over the card and off it, and for a click on its close button.
    func setHovering(_ inside: Bool) { hovering = inside }
    func pressCloseForProbe() { model.onClose() }

    var countdownRemaining: Double { countdown.remaining }

    /// A key typed while the card is up: Esc closes it when ASCII Animals is the active app. The event always goes on
    /// to the window it was meant for (Esc still cancels a sheet or closes Settings).
    func key(_ e: NSEvent, appActive: Bool) -> NSEvent {
        if e.keyCode == 53, appActive, !closing { close(trying: false, reason: .esc) }
        return e
    }

    /// Settings changed elsewhere: on the Meadow the card goes; otherwise the Keep chip names the habitat now.
    func settingsChanged(_ s: OceanKit.Settings) {
        guard !closing else { return }
        if s.habitat == .meadow { close(trying: false, reason: .meadow); return }
        if model.keep != s.habitat { model.keep = s.habitat }
    }

    /// The preview for the machine's state: live, a held still (rendered once, when first needed), or nothing drawn.
    func apply(_ p: WhatsNew.Preview) {
        guard p != preview, !closing else { return }
        preview = p
        switch p {
        case .live:
            model.liveAttached = true
            model.cover = false
            live.start()
        case .still:
            live.stop()
            if model.still == nil {
                model.still = try? WhatsNewSession.still(settings: host?.cardSettings ?? .defaults, light: model.light,
                                                         preview: model.previewSize, renderer: renderer)
            }
            model.cover = true
        case .stopped:
            live.stop()
            model.cover = true
        }
    }

    var isClosing: Bool { closing }
    var ignoresClicks: Bool { panel.ignoresMouseEvents }
    var keepLabel: String { WhatsNewCard.keepTitle(model.keep) }
    var previewState: String {
        switch preview {
        case .live?: return model.cover ? "live, covered" : "live"
        case .still?: return model.cover && model.still != nil ? "still" : "still, missing"
        case .stopped?: return model.cover ? "stopped" : "stopped, uncovered"
        case nil: return "none"
        }
    }

    /// `trying`: "Try the Meadow". The desktop dissolves to it (the director's habitat change) as the card fades.
    /// From the moment it starts closing, clicks go through it to whatever is under it. `now`: gone at once, no fade
    /// (the welcome opening from Help, or a card that didn't reach the screen).
    func close(trying: Bool, now: Bool = false, reason: WhatsNew.CloseReason? = nil) {
        if closing {
            if now { teardown() }
            return
        }
        closing = true
        if let reason, let armedAt { onClose?(reason, Date().timeIntervalSince(armedAt)) }
        panel.ignoresMouseEvents = true
        if trying { host?.tryMeadow() }
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        typer?.invalidate()
        blinker?.invalidate()
        ticker?.invalidate()
        ticker = nil
        live.stop()
        if now { teardown(); return }
        let duration: Double = trying && !model.reduceMotion ? 0.6 : 0.25
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.teardown() })
        // Whatever happens to the animation, nothing stays on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1) { [weak self] in self?.teardown() }
    }

    // MARK: Drawn check

    /// What the card's window holds now: its image as the window server keeps it (what the screen composites; no
    /// Screen Recording permission is needed for the app's own windows), or, if that can't be had, its content view
    /// drawn by AppKit. nil when neither gives an image.
    func drawnImage() -> (image: CGImage, source: String)? {
        if panel.windowNumber > 0, let image = WhatsNewSession.windowImage(CGWindowID(panel.windowNumber)) {
            return (image, "the window server's image of the card window")
        }
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let image = rep.cgImage else { return nil }
        return (image, "the content view drawn by AppKit (no window server image)")
    }

    /// The drawn share of `drawnImage()` (`WhatsNew.drawnShare`), the window's size in points, and where the image came
    /// from; the image is saved to `png` when one is given.
    func measureDrawn(savingTo png: URL?) -> (share: Double, width: Int, height: Int, source: String)? {
        guard let (image, source) = drawnImage() else { return nil }
        let w: Int = image.width, h: Int = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let made: Bool = bytes.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard made else { return nil }
        if let png { try? StillRenderer.writePNG(image, to: png) }
        let size: CGSize = panel.frame.size
        return (WhatsNew.drawnShare(rgba: bytes), Int(size.width.rounded()), Int(size.height.rounded()), source)
    }

    /// `CGWindowListCreateImage` for one window, looked up at run time: the SDK marks it unavailable (ScreenCaptureKit
    /// replaces it, and that asks for Screen Recording even for the app's own windows), but macOS still serves it.
    private static func windowImage(_ id: CGWindowID) -> CGImage? {
        typealias Create = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let lib = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW) else { return nil }
        defer { dlclose(lib) }
        guard let sym = dlsym(lib, "CGWindowListCreateImage") else { return nil }
        let create: Create = unsafeBitCast(sym, to: Create.self)
        let includingWindow: UInt32 = 1 << 3          // kCGWindowListOptionIncludingWindow
        let options: UInt32 = (1 << 0) | (1 << 3)     // kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution
        return create(CGRect.null, includingWindow, id, options)?.takeRetainedValue()
    }

    /// The drawn probe's stand-in for a card that draws empty: its content hidden at once, no animation.
    func hideContentForProbe() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { model.contentVisible = false }
    }

    private var tornDown = false

    private func teardown() {
        guard !tornDown else { return }
        tornDown = true
        ticker?.invalidate()
        ticker = nil
        live.stop()
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
                .frame(width: model.previewSize.width, height: model.previewSize.height)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ink.opacity(0.14), lineWidth: 1))
                .accessibilityLabel("The Meadow: butterflies over a field of flowers")
                .overlay(alignment: .topTrailing) {
                    CloseButton(light: light, action: model.onClose)
                        .padding(7)
                }

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

            // On a narrow screen the chips keep their words and the "esc close" hint gives way (Esc still closes).
            ViewThatFits(in: .horizontal) {
                chips(escHint: true)
                chips(escHint: false)
            }
            .padding(.top, 18)
        }
        .foregroundStyle(ink)
        .padding(16)
        .padding(.top, model.arrowX == nil ? 0 : WhatsNewCard.arrowHeight)
        .frame(width: model.width, alignment: .leading)
        .background(shape.fill(plate))
        .overlay(alignment: .bottomLeading) { drainingLine }
        .overlay(shape.stroke(ink.opacity(light ? 0.12 : 0.17), lineWidth: 1))
        .opacity(model.contentVisible ? 1 : 0)
    }

    /// The card's time left, a thin line along its bottom edge between the corners, draining from the right.
    private var drainingLine: some View {
        let inset: CGFloat = 14
        let full: CGFloat = max(0, model.width - 2 * inset)
        let fraction: CGFloat = CGFloat(min(1, max(0, model.remaining)))
        return Capsule()
            .fill(Ink.accent(model.light).opacity(0.75))
            .frame(width: full * fraction, height: 2)
            .padding(.leading, inset)
            .padding(.bottom, 3)
            .accessibilityHidden(true)
    }

    private func chips(escHint: Bool) -> some View {
        let ink: Color = Ink.text(model.light)
        return HStack(spacing: 10) {
            CardChip(title: WhatsNewCard.tryTitle, filled: true, model: model, action: model.onTry)
                .fixedSize()
            CardChip(title: WhatsNewCard.keepTitle(model.keep), filled: false, model: model, action: model.onKeep)
                .fixedSize()
            Spacer(minLength: 8)
            if escHint {
                Button(action: model.onKeep) {
                    HStack(spacing: 7) {
                        Keycap(text: "esc", light: model.light, unit: 1)
                        Text("close").font(UIFonts.swiftUI(12))
                    }
                    .foregroundStyle(ink.opacity(0.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(WhatsNewCard.keepTitle(model.keep))
                .fixedSize()
            }
        }
    }

    /// The live view stays put once it has joined (moving an AppKit view in and out of SwiftUI's tree is fragile);
    /// a still or a plain plate covers it whenever it isn't drawing.
    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack {
            shape.fill(Ink.plate(model.light))
            if model.liveAttached, let live {
                LiveMeadow(view: live)
            }
            if model.cover || live == nil {
                if let still = model.still {
                    Image(decorative: still, scale: 2)
                        .resizable()
                        .clipShape(shape)
                } else {
                    shape.fill(Ink.plate(model.light))
                }
            }
        }
    }
}

/// A small round × over the preview's top-right corner: ends the card for good, like Keep.
private struct CloseButton: View {
    let light: Bool
    let action: () -> Void

    var body: some View {
        let ink: Color = Ink.text(light)
        let plate: Color = Ink.plate(light)
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ink.opacity(0.8))
                .frame(width: 20, height: 20)
                .background(Circle().fill(plate.opacity(0.85)))
                .overlay(Circle().strokeBorder(ink.opacity(0.22), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(WhatsNewCard.closeLabel)
        .help(WhatsNewCard.closeLabel)
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
