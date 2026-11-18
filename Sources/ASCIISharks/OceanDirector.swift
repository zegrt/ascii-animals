import AppKit
import Metal
import OceanKit

/// Owns the screens and applies the power policy, settings, theme and pointer.
final class OceanDirector {
    let renderer: OceanRenderer
    private let store: SettingsStore
    private let signals: SystemSignals
    private(set) var screens: [OceanScreen] = []
    private(set) var scenes: [OceanScene] = []
    private(set) var mode: RunMode = .paused
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
        switch newMode {
        case .live(let fps):
            for s in screens { s.stillPending = false; s.setFrameRate(fps); s.setRunning(true) }
        case .still:
            for s in screens { s.stillPending = true; s.setFrameRate(PowerPolicy.economyFPS); s.setRunning(true) }
        case .paused:
            for s in screens { s.setRunning(false) }
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
        let world = s.scene.world
        if s.stillPending {
            // Reduce Motion / Low Power: let the ecosystem settle, then hold one frame.
            if world.time < 4 { for _ in 0..<240 { world.step(OceanClock.step) } }
        } else {
            s.scene.advance(to: link.targetTimestamp, speed: store.settings.speed)
        }
        guard let drawable = s.view.metalLayer.nextDrawable(), let cb = renderer.queue.makeCommandBuffer() else { return }
        s.viewport.encode(world: world, viewport: s.oceanRect, theme: theme, target: drawable.texture, commandBuffer: cb)
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
    /// unchanged keeps its world (resized to any new geometry); `fresh` forces
    /// new worlds, e.g. when switching between shared and separate oceans.
    func screensChanged(fresh: Bool = false) {
        let current = NSScreen.screens
        guard let primary = current.first else { return }
        let infos = current.map {
            ScreenInfo(id: Int($0.displayID), frame: ScreenGeometry.flip($0.frame, primaryHeight: primary.frame.height),
                       scale: $0.backingScaleFactor)
        }
        let plans = SceneLayout.plan(infos, shared: store.settings.sharedOcean)

        var next: [OceanScene] = []
        for plan in plans {
            let ids = Set(plan.views.map(\.screenID))
            if !fresh, let keep = scenes.first(where: { $0.screenIDs == ids }) {
                keep.update(plan, settings: store.settings)
                next.append(keep)
            } else {
                next.append(OceanScene(plan: plan, settings: store.settings))
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
            NSLog("scenes: %@", scenes.map { "\($0.screenIDs.sorted()) rects=\($0.plan.habitat.rects.count) sharks=\($0.world.sharks.count) fish=\($0.world.fish.count)" }.joined(separator: " | "))
        }
        apply(mode == .paused ? PowerPolicy.mode(signals.inputs) : mode)
    }

    private func report(_ error: Error) {
        lastError = "\(error)"
        NSLog("ASCII Sharks: %@", "\(error)")
    }

    // MARK: Settings and theme

    func settingsChanged(old: Settings, new: Settings) {
        if old.sharedOcean != new.sharedOcean {
            screensChanged(fresh: true)
        } else if old.sharks != new.sharks {
            for s in scenes { s.rebuildWorld(new) }
        } else if old.fishDensity != new.fishDensity {
            for s in scenes { s.setDensity(new) }
        }
        if old.paused != new.paused { signals.setUserPaused(new.paused) }
        if old.fps != new.fps { signals.setFPS(new.fps) }
        if old.lowPowerAnimates != new.lowPowerAnimates { signals.setLowPowerAnimates(new.lowPowerAnimates) }
        refreshTheme()
        if old.interaction != new.interaction { updatePointer() }
        if case .paused = mode {} else { return }
        // Paused: still show the change once.
        for s in screens { s.stillPending = true; s.setRunning(true) }
    }

    func refreshTheme() {
        let t = OceanDirector.currentTheme(store.settings)
        guard t != theme else { return }
        theme = t
        if case .live = mode { return }
        for s in screens { s.stillPending = true; s.setRunning(true) }
    }

    static func currentTheme(_ s: Settings) -> ThemeParams {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let a = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        return ThemeParams.make(s, systemIsDark: dark, accent: SIMD3(Float(a.redComponent), Float(a.greenComponent), Float(a.blueComponent)))
    }

    var systemIsDark: Bool { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    // MARK: Pointer

    /// The pointer in its scene's ocean space.
    private func locate(_ t: PointerTarget) -> (OceanScene, Double, Double)? {
        guard let s = screens.first(where: { Int($0.displayID) == t.viewportID }) else { return nil }
        return (s.scene, Double(s.oceanRect.minX + t.local.x), Double(s.oceanRect.minY + t.local.y))
    }

    private func pointerMoved(_ t: PointerTarget?) {
        let hit = t.flatMap(locate)
        for scene in scenes {
            if let hit, hit.0 === scene {
                scene.world.pointer = (hit.1, hit.2, true)
            } else {
                scene.world.pointer.active = false
            }
        }
    }

    private func pointerDown(_ t: PointerTarget) {
        guard let (scene, x, y) = locate(t) else { return }
        scene.world.splash(x, y)
    }
}
