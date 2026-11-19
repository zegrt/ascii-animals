import AppKit
import Metal
import OceanKit

/// Owns the screens and applies the power policy, settings, theme and pointer.
final class OceanDirector {
    let renderer: OceanRenderer
    private let store: SettingsStore
    private let signals: SystemSignals
    private(set) var screens: [OceanScreen] = []
    private(set) var scenes: [HabitatScene] = []
    private(set) var mode: RunMode = .paused
    /// A habitat switch dissolving on a live desktop; nil when none is.
    private var dissolve: DissolveRun?
    private var theme: ThemeParams
    private lazy var pointer = PointerMonitor(
        viewports: { [weak self] in self?.viewports ?? [] },
        onMove: { [weak self] t in self?.pointerMoved(t) },
        onDown: { [weak self] t in self?.pointerDown(t) })
    /// Called after the first frame on every screen, and after looks change.
    var onLooksSettled: (() -> Void)?
    private(set) var lastError: String?

    init(renderer: OceanRenderer, store: SettingsStore, signals: SystemSignals) {
        self.renderer = renderer
        self.store = store
        self.signals = signals
        theme = OceanDirector.currentTheme(store.settings)
        signals.setUserPaused(store.settings.paused)
        signals.setFPS(store.settings.fps)
        signals.setLowPowerAnimates(store.settings.lowPowerAnimates)
    }

    var viewports: [Viewport] { screens.map { Viewport(id: Int($0.displayID), rect: $0.viewportRect) } }

    func start() {
        screensChanged()
        apply(PowerPolicy.mode(signals.inputs))
    }

    // MARK: Policy

    static let debug = ProcessInfo.processInfo.environment["OCEAN_DEBUG"] != nil

    func apply(_ newMode: RunMode) {
        if OceanDirector.debug {
            NSLog("mode %@ inputs %@ screens %@", "\(newMode)", "\(signals.inputs)",
                  screens.map { "\($0.displayID) visible=\($0.visible) presented=\($0.presented) paused=\($0.link?.isPaused ?? true)" }.joined(separator: "; "))
        }
        mode = newMode
        // Stopped animating mid-switch: finish it at once (Review Focus 1).
        if dissolve != nil, !Dissolve.shouldAnimate(newMode) { finishSwitch() }
        switch newMode {
        case .live(let fps):
            for s in screens { s.stillPending = false; s.setFrameRate(fps); s.setRunning(true) }
        case .still:
            for s in screens { s.stillPending = true; s.setFrameRate(PowerPolicy.economyFPS); s.setRunning(true) }
        case .paused:
            // Do no work, except a still owed to a user pause (see showChangeIfHeld),
            // drawn once its screen is visible. Covered, locked or asleep: drop
            // any still left over from `.still`; the next visible mode draws.
            let owed = Dissolve.drawsStillNow(newMode, userPaused: signals.inputs.userPaused)
            for s in screens {
                if !owed { s.stillPending = false }
                s.setRunning(owed && s.stillPending)
            }
        }
        updatePointer()
    }

    private func updatePointer() {
        if case .live = mode, store.settings.interaction {
            pointer.setRunning(true)
        } else {
            pointer.setRunning(false)
        }
    }

    private func visibilityChanged() {
        signals.setWindowVisibility(screens.contains { $0.visible || !$0.presented })
        // A screen that became visible while live needs its link back.
        apply(PowerPolicy.mode(signals.inputs))
    }

    // MARK: Frames

    private func tick(_ s: OceanScreen, _ link: CADisplayLink) {
        var reveal: Float = 1
        if var d = dissolve {
            let f = d.frame(at: link.targetTimestamp)
            dissolve = f.done ? nil : d
            if f.swap { rebuildScenes() }
            reveal = f.reveal
        }
        let sim = s.scene.sim
        let drawable: CAMetalDrawable
        if s.stillPending {
            // Reduce Motion / Low Power / a paused change: let the ecosystem
            // settle, then hold one frame. No drawable (a hidden screen): stop
            // rather than fire every frame; `stillPending` stays, so the next
            // mode or visibility change runs it again.
            guard let d = s.view.metalLayer.nextDrawable() else { s.setRunning(false); return }
            drawable = d
            sim.settle()
        } else {
            s.scene.advance(to: link.targetTimestamp, speed: store.settings.speed)
            guard let d = s.view.metalLayer.nextDrawable() else { return }
            drawable = d
        }
        guard let cb = renderer.queue.makeCommandBuffer() else {
            if s.stillPending { s.setRunning(false) }
            return
        }
        s.viewport.encode(habitat: sim, viewport: s.oceanRect, theme: theme, reveal: reveal, target: drawable.texture, commandBuffer: cb)
        cb.present(drawable)
        let first = !s.presented
        cb.addScheduledHandler { _ in
            if first { DispatchQueue.main.async { [weak self] in self?.firstFrame(s) } }
        }
        cb.commit()
        if s.stillPending {
            s.stillPending = false
            s.setRunning(false)
        }
    }

    private func firstFrame(_ s: OceanScreen) {
        if OceanDirector.debug { NSLog("first frame on %u", s.displayID) }
        s.markPresented()
        if screens.allSatisfy(\.presented) { onLooksSettled?() }
    }

    // MARK: Screens

    /// Lay the scenes out for the current screens. A scene whose screens are
    /// unchanged keeps its sim (laid out to any new geometry); `fresh` forces
    /// new sims, e.g. when switching between shared and separate oceans.
    func screensChanged(fresh: Bool = false) {
        let current = NSScreen.screens
        guard let primary = current.first else { return }
        let infos = current.map {
            ScreenInfo(id: Int($0.displayID), frame: ScreenGeometry.flip($0.frame, primaryHeight: primary.frame.height),
                       scale: $0.backingScaleFactor)
        }
        let plans = SceneLayout.plan(infos, shared: store.settings.sharedOcean)

        var next: [HabitatScene] = []
        for plan in plans {
            let ids = Set(plan.views.map(\.screenID))
            if !fresh, let keep = scenes.first(where: { $0.screenIDs == ids }) {
                keep.update(plan, settings: store.settings)
                next.append(keep)
            } else {
                next.append(HabitatScene(plan: plan, settings: store.settings))
            }
        }
        scenes = next

        let ids = Set(current.map(\.displayID))
        for s in screens where !ids.contains(s.displayID) { s.close() }
        screens.removeAll { !ids.contains($0.displayID) }
        for screen in current {
            let id = Int(screen.displayID)
            guard let scene = scenes.first(where: { $0.screenIDs.contains(id) }), let rect = scene.rect(for: id) else { continue }
            do {
                if let existing = screens.first(where: { $0.displayID == screen.displayID }) {
                    try existing.fit(to: screen, scene: scene, rect: rect)
                } else {
                    let s = try OceanScreen(screen: screen, renderer: renderer, scene: scene, rect: rect,
                                            onTick: { [weak self] s, l in self?.tick(s, l) },
                                            onVisibility: { [weak self] in self?.visibilityChanged() })
                    screens.append(s)
                }
            } catch { report(error) }
        }
        if OceanDirector.debug {
            NSLog("scenes: %@", scenes.map { "\($0.screenIDs.sorted()) rects=\($0.plan.terrain.rects.count) \($0.sim.kind)" }.joined(separator: " | "))
        }
        apply(mode == .paused ? PowerPolicy.mode(signals.inputs) : mode)
    }

    private func report(_ error: Error) {
        lastError = "\(error)"
        Log.write("error: \(error)")
    }

    // MARK: Settings and theme

    func settingsChanged(old: Settings, new: Settings) {
        // Power inputs first: they settle the mode, which decides how a switch shows.
        if old.paused != new.paused { signals.setUserPaused(new.paused) }
        if old.fps != new.fps { signals.setFPS(new.fps) }
        if old.lowPowerAnimates != new.lowPowerAnimates { signals.setLowPowerAnimates(new.lowPowerAnimates) }
        if old.sharedOcean != new.sharedOcean {
            dissolve = nil
            screensChanged(fresh: true)
        } else if old.habitat != new.habitat, Dissolve.shouldAnimate(mode) {
            // Live: dissolve out, rebuild at the swap (with whatever is chosen
            // by then), dissolve in. See tick.
            let now = CACurrentMediaTime()
            if dissolve == nil { dissolve = DissolveRun(start: now) } else { dissolve?.restart(at: now) }
        } else if Habitats.needsRebuild(old: old, new: new) {
            // A switch still dissolving out rebuilds at its swap anyway.
            let swapPending = dissolve.map { !$0.swapped } ?? false
            if !swapPending { rebuildScenes() }
        } else {
            for s in scenes { s.sim.update(settings: new) }
        }
        refreshTheme()
        if old.interaction != new.interaction { updatePointer() }
        showChangeIfHeld()
    }

    /// Fresh sims for every scene, from the current settings.
    private func rebuildScenes() {
        for s in scenes { s.rebuild(store.settings) }
    }

    /// A switch cut short by a still or a pause: swap now if it hadn't, and
    /// show the new habitat as a still when the held frame must.
    private func finishSwitch() {
        if let d = dissolve, !d.swapped { rebuildScenes() }
        dissolve = nil
        if Dissolve.drawsStillNow(mode, userPaused: signals.inputs.userPaused) {
            for s in screens { s.stillPending = true }
        }
    }

    /// Not animating: draw one settled still of a change now when the held
    /// frame must show it (a Low Power / Reduce Motion still, a user pause).
    /// A covered or locked desktop just keeps the change; its next visible
    /// frame shows it.
    private func showChangeIfHeld() {
        guard Dissolve.drawsStillNow(mode, userPaused: signals.inputs.userPaused) else { return }
        for s in screens { s.stillPending = true; s.setRunning(true) }
    }

    func refreshTheme() {
        let t = OceanDirector.currentTheme(store.settings)
        guard t != theme else { return }
        theme = t
        showChangeIfHeld()
    }

    static func currentTheme(_ s: Settings) -> ThemeParams {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let a = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        return ThemeParams.make(s, systemIsDark: dark, accent: SIMD3(Float(a.redComponent), Float(a.greenComponent), Float(a.blueComponent)))
    }

    var systemIsDark: Bool { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    // MARK: Pointer

    /// The pointer in its scene's ocean space.
    private func locate(_ t: PointerTarget) -> (HabitatScene, Double, Double)? {
        guard let s = screens.first(where: { Int($0.displayID) == t.viewportID }) else { return nil }
        return (s.scene, Double(s.oceanRect.minX + t.local.x), Double(s.oceanRect.minY + t.local.y))
    }

    private func pointerMoved(_ t: PointerTarget?) {
        let hit = t.flatMap(locate)
        for scene in scenes {
            if let hit, hit.0 === scene {
                scene.sim.pointerMoved(hit.1, hit.2)
            } else {
                scene.sim.pointerLeft()
            }
        }
    }

    private func pointerDown(_ t: PointerTarget) {
        guard let (scene, x, y) = locate(t) else { return }
        scene.sim.pointerDown(x, y)
    }
}
