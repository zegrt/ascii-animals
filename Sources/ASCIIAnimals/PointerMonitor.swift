import AppKit
import OceanKit

/// Watches the pointer for the desktop without taking any event from anyone: the AppKit host of `DesktopPointer`
/// (the contract is there). Installed only while a habitat is live, interaction is on and a screen is exposed.
///
/// Sources: a global monitor (events dispatched to other apps), a passive local monitor (events dispatched to ASCII
/// Animals itself; it hands every event back unchanged) and `tick`, the sample the display link calls each step in
/// common modes, which also covers events no monitor sees (a nested tracking loop). The window list is read only as
/// `DesktopPointer` asks; changes that make it stale (own windows, menus, Spaces, the active app) invalidate it.
final class PointerMonitor {
    private var global: Any?
    private var local: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let core: DesktopPointer
    private let apply: ([DesktopPointer.Output]) -> Void
    private let trace: PointerTrace?
    /// The menu-bar screen's height, for flipping AppKit points (read again on every invalidation).
    private var primaryHeight: CGFloat? = nil

    /// `viewports`: the habitat screens; `frames`: frames drawn so far (for the trace); `apply`: what the habitats
    /// are told.
    init(viewports: @escaping () -> [Viewport], frames: @escaping () -> Int,
         apply: @escaping ([DesktopPointer.Output]) -> Void) {
        let me: Int32 = ProcessInfo.processInfo.processIdentifier
        core = DesktopPointer(viewports: viewports, windows: {
            guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
                return nil
            }
            return PointerWindow.parse(raw, ownPID: me, clickThrough: PointerMonitor.ownClickThrough())
        })
        self.apply = apply
        trace = PointerTrace.enabled ? PointerTrace(frames: frames, core: core) : nil
    }

    var isRunning: Bool { core.running }

    func setRunning(_ on: Bool) {
        if on, !core.running {
            primaryHeight = NSScreen.screens.first?.frame.height
            apply(core.start(now: PointerMonitor.now))
            install()
            trace?.started(global: global != nil, local: local != nil)
        } else if !on, core.running {
            uninstall()
            apply(core.stop())
            trace?.stopped()
        }
    }

    /// Screens, windows, Spaces or the app receiving events changed.
    func invalidate() {
        guard core.running else { return }
        primaryHeight = NSScreen.screens.first?.frame.height
        core.invalidate()
    }

    /// One simulation step (the display link, common modes): the newest move, or the cursor.
    func tick() {
        guard core.running, let h = primaryHeight else { return }
        let cursor: CGPoint = ScreenGeometry.flip(NSEvent.mouseLocation, primaryHeight: h)
        let held: Bool = NSEvent.pressedMouseButtons & 1 != 0
        apply(core.tick(cursor: cursor, buttonDown: held, now: PointerMonitor.now))
    }

    // MARK: Inside

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// This app's windows that take no mouse events (the habitats' desktop windows, the welcome's dims).
    static func ownClickThrough() -> Set<Int> {
        var out: Set<Int> = []
        for w in NSApp.windows where w.ignoresMouseEvents { out.insert(w.windowNumber) }
        return out
    }

    private func install() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in
            self?.handle(e, source: .global)
        }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            self?.handle(e, source: .local)
            return e   // passive: the event goes on as if nothing watched it
        }
        if global == nil { Log.write("pointer: the global mouse monitor could not be installed") }
        if local == nil { Log.write("pointer: the local mouse monitor could not be installed") }
        let nc = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter
        let own: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
            NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeOcclusionStateNotification,
            NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification,
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
        ]
        for name in own { observe(nc, name) }
        let system: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in system { observe(ws, name) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token: NSObjectProtocol = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.invalidate()
        }
        observers.append((center, token))
    }

    private func uninstall() {
        if let g = global { NSEvent.removeMonitor(g) }
        if let l = local { NSEvent.removeMonitor(l) }
        global = nil
        local = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    private func handle(_ e: NSEvent, source: PointerSource) {
        guard let h = primaryHeight else { return }
        let kind: DesktopPointer.Kind
        switch e.type {
        case .leftMouseDown: kind = .down
        case .leftMouseDragged: kind = .drag
        default: kind = .move
        }
        let cursor: CGPoint = ScreenGeometry.flip(NSEvent.mouseLocation, primaryHeight: h)
        let event = DesktopPointer.Event(kind: kind, source: source, location: PointerMonitor.location(e, primaryHeight: h),
                                         cursor: cursor, hitWindow: PointerMonitor.hitWindow(e), time: e.timestamp)
        trace?.received(source)
        apply(core.receive(event))
    }

    /// The event's own location at event time, top-left global points (the window server's, else AppKit's).
    static func location(_ e: NSEvent, primaryHeight: CGFloat) -> CGPoint? {
        if let cg = e.cgEvent { return cg.location }
        if let w = e.window { return ScreenGeometry.flip(w.convertPoint(toScreen: e.locationInWindow), primaryHeight: primaryHeight) }
        if e.windowNumber == 0 { return ScreenGeometry.flip(e.locationInWindow, primaryHeight: primaryHeight) }
        return nil
    }

    /// The window the window server handed the event to (nil when the event does not say).
    static func hitWindow(_ e: NSEvent) -> Int? {
        guard let cg = e.cgEvent else { return nil }
        let n: Int64 = cg.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        return n > 0 ? Int(n) : nil
    }
}

/// The energy-test copy's pointer trace (`ASCII_ANIMALS_POINTER_TRACE=1`), for a supervised session: every click and
/// every change of route with its source, point, run-loop mode, the window the window server named, the blocking
/// window (pid, layer, rect, own) and what the habitats were told; once a second, the events per source, the
/// window-list reads and the frames drawn. A missing callback and a callback refused by a rectangle read apart.
final class PointerTrace {
    static let enabled: Bool = Launch.identity.isEnergyTest
        && ProcessInfo.processInfo.environment["ASCII_ANIMALS_POINTER_TRACE"] == "1"

    private let frames: () -> Int
    private weak var core: DesktopPointer?
    private var counts: [PointerSource: Int] = [:]
    private var judged: Int = 0
    private var lastKey: String = ""
    private var lastSummary: Double = 0
    private var readsAtSummary: Int = 0

    init(frames: @escaping () -> Int, core: DesktopPointer) {
        self.frames = frames
        self.core = core
        core.onDecision = { [weak self] d in self?.decided(d) }
    }

    func started(global: Bool, local: Bool) {
        Log.write("pointer trace: start; global monitor \(global ? "on" : "MISSING"), local monitor \(local ? "on" : "MISSING")")
    }

    func stopped() {
        summary(force: true)
        Log.write("pointer trace: stop")
        lastKey = ""
    }

    func received(_ s: PointerSource) {
        counts[s, default: 0] += 1
        summary(force: false)
    }

    private func decided(_ d: DesktopPointer.Decision) {
        judged += 1
        let key: String = PointerTrace.verdictKey(d.verdict)
        if d.kind == .down || key != lastKey {
            lastKey = key
            let mode: String = RunLoop.current.currentMode?.rawValue ?? "none"
            let point: String = String(format: "(%.0f, %.0f)", Double(d.point.x), Double(d.point.y))
            let hit: String = d.hitWindow.map { "\($0)" } ?? "-"
            let told: String = d.outputs.map(PointerTrace.output).joined(separator: ",")
            Log.write("pointer \(d.source.rawValue) \(d.kind?.rawValue ?? "sample") at \(point) mode \(mode) hit \(hit) -> "
                      + "\(PointerTrace.verdict(d.verdict)) read \(d.fetched ? "yes" : "no") told [\(told)] frames \(frames())")
        }
        summary(force: false)
    }

    private func summary(force: Bool) {
        let now: Double = ProcessInfo.processInfo.systemUptime
        guard force || now - lastSummary >= 1 else { return }
        lastSummary = now
        let reads: Int = core?.fetches ?? 0
        let g: Int = counts[.global] ?? 0
        let l: Int = counts[.local] ?? 0
        Log.write("pointer 1s: global \(g) local \(l) judged \(judged) reads \(reads - readsAtSummary) frames \(frames())")
        counts.removeAll()
        judged = 0
        readsAtSummary = reads
    }

    static func verdictKey(_ v: PointerVerdict) -> String {
        switch v {
        case .desktop(let t): return "desktop \(t.viewportID)"
        case .blocked(let w): return "blocked \(w.number)"
        case .gesture: return "gesture"
        case .offDesktop: return "off"
        case .unknown: return "unknown"
        }
    }

    static func verdict(_ v: PointerVerdict) -> String {
        switch v {
        case .desktop(let t):
            return "desktop display \(t.viewportID) " + String(format: "(%.0f, %.0f)", Double(t.local.x), Double(t.local.y))
        case .blocked(let w):
            let r: String = String(format: "%.0f,%.0f %.0fx%.0f", Double(w.bounds.minX), Double(w.bounds.minY),
                                   Double(w.bounds.width), Double(w.bounds.height))
            return "blocked by window \(w.number) pid \(w.pid)\(w.own ? " (own)" : "") layer \(w.layer) alpha "
                + String(format: "%.2f", w.alpha) + " rect \(r)"
        case .gesture: return "a drag owned by a window"
        case .offDesktop: return "off the exposed desktop"
        case .unknown: return "unknown (window list unreadable)"
        }
    }

    static func output(_ o: DesktopPointer.Output) -> String {
        switch o {
        case .moved(let t): return "moved \(t.viewportID)"
        case .left: return "left"
        case .down(let t): return "down \(t.viewportID)"
        }
    }
}
