import AppKit
import Metal
import OceanKit

/// Owns the screens and applies the power policy, settings, theme and pointer.
final class OceanDirector {
    let renderer: OceanRenderer
    private let store: SettingsStore
    private let signals: SystemSignals
    private(set) var screens: [OceanScreen] = []
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
        var steps = 0
        if s.stillPending {
            // Reduce Motion / Low Power: let the ecosystem settle, then hold one frame.
            if s.world.time < 4 { for _ in 0..<240 { s.world.step(OceanClock.step) } }
            s.world.events.removeAll()
        } else {
            steps = s.clock.advance(to: link.targetTimestamp, speed: store.settings.speed)
            for _ in 0..<steps { s.world.step(OceanClock.step) }
        }
        guard let drawable = s.view.metalLayer.nextDrawable(), let cb = renderer.queue.makeCommandBuffer() else { return }
        s.viewport.encode(world: s.world, theme: theme, steps: steps, target: drawable.texture, commandBuffer: cb)
        s.world.events.removeAll()
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

    func screensChanged() {
        let current = NSScreen.screens
        let ids = Set(current.map(\.displayID))
        for s in screens where !ids.contains(s.displayID) { s.close() }
        screens.removeAll { !ids.contains($0.displayID) }
        for screen in current {
            if let existing = screens.first(where: { $0.displayID == screen.displayID }) {
                do { try existing.fit(to: screen, settings: store.settings) } catch { report(error) }
            } else {
                do {
                    let s = try OceanScreen(screen: screen, renderer: renderer, settings: store.settings,
                                            onTick: { [weak self] s, l in self?.tick(s, l) },
                                            onVisibility: { [weak self] in self?.visibilityChanged() })
                    screens.append(s)
                } catch { report(error) }
            }
        }
        apply(mode == .paused ? PowerPolicy.mode(signals.inputs) : mode)
    }

    private func report(_ error: Error) {
        lastError = "\(error)"
        NSLog("ASCII Sharks: %@", "\(error)")
    }

    // MARK: Settings and theme

    func settingsChanged(old: Settings, new: Settings) {
        if old.sharks != new.sharks {
            for s in screens { s.rebuildWorld(new) }
        } else if old.fishDensity != new.fishDensity {
            for s in screens { s.setDensity(new) }
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

    private func pointerMoved(_ t: PointerTarget?) {
        for s in screens {
            if let t, t.viewportID == Int(s.displayID) {
                s.world.pointer = (Double(t.local.x), Double(t.local.y), true)
            } else {
                s.world.pointer.active = false
            }
        }
    }

    private func pointerDown(_ t: PointerTarget) {
        guard let s = screens.first(where: { Int($0.displayID) == t.viewportID }) else { return }
        s.world.splash(Double(t.local.x), Double(t.local.y))
    }
}
