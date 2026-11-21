import AppKit
import OceanKit

/// Watches the pointer for the desktop without taking any event from anyone: the AppKit host of `DesktopPointer`
/// (the contract is there). Installed only while a habitat is live, interaction is on and a screen is exposed.
///
/// Sources: the monitors `PointerHost.monitors` names with its mask (a global monitor for events dispatched to other
/// apps, a passive local monitor for events dispatched to ASCII Animals itself; it hands every event back unchanged)
/// and `tick`, the sample the display link calls each step in common modes, which also covers events no monitor sees
/// (a nested tracking loop). Every event is read through `PointerHost` (its kind, its own location, and for a local
/// one the own window AppKit dispatched it to). The window list is read only as `DesktopPointer` asks: a Space change
/// is a boundary (`invalidate`), changes of own windows, menus and the active app are ordinary (`windowsChanged`).
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

    /// A boundary: screens, Spaces or the desktop's visibility changed (the director calls it on every such change).
    func invalidate() {
        guard core.running else { return }
        primaryHeight = NSScreen.screens.first?.frame.height
        core.invalidate()
    }

    /// A habitat was replaced: its new scene is told the pointer at the next step.
    func retell() { core.retell() }

    /// One simulation step (the display link, common modes): the newest move, or the cursor. `DesktopPointer` takes
    /// one a step whichever display ticks first.
    func tick() {
        guard core.running, let h = primaryHeight else { return }
        let cursor: CGPoint = ScreenGeometry.flip(NSEvent.mouseLocation, primaryHeight: h)
        let held: Bool = NSEvent.pressedMouseButtons & 1 != 0
        apply(core.tick(cursor: cursor, buttonDown: held, now: PointerMonitor.now))
        trace?.flushIfDue()
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
        let mask = NSEvent.EventTypeMask(rawValue: PointerHost.mask)
        for source in PointerHost.monitors {
            switch source {
            case .global:
                global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in
                    self?.handle(e, source: .global)
                }
                if global == nil { Log.write("pointer: the global mouse monitor could not be installed") }
            case .local:
                local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
                    self?.handle(e, source: .local)
                    return e   // passive: the event goes on as if nothing watched it
                }
                if local == nil { Log.write("pointer: the local mouse monitor could not be installed") }
            case .sample:
                break   // the display link's tick
            }
        }
        let nc = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter
        let own: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
            NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeOcclusionStateNotification,
            NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification,
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
        ]
        for name in own { observe(nc, name, boundary: false) }
        let apps: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in apps { observe(ws, name, boundary: false) }
        observe(ws, NSWorkspace.activeSpaceDidChangeNotification, boundary: true)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, boundary: Bool) {
        let token: NSObjectProtocol = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if boundary { self.invalidate() } else if self.core.running { self.core.windowsChanged() }
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
        guard let h = primaryHeight, let kind = PointerHost.kind(eventType: UInt(e.type.rawValue)) else { return }
        let cursor: CGPoint = ScreenGeometry.flip(NSEvent.mouseLocation, primaryHeight: h)
        let w: NSWindow? = source == .local ? e.window : nil
        let screenPoint: CGPoint? = w.map { $0.convertPoint(toScreen: e.locationInWindow) }
            ?? (e.windowNumber == 0 ? e.locationInWindow : nil)
        let location: CGPoint? = PointerHost.location(cgLocation: e.cgEvent?.location, screenPoint: screenPoint,
                                                      primaryHeight: h)
        let receiver: PointerReceiver? = w.map {
            PointerHost.receiver(number: $0.windowNumber, appKitFrame: $0.frame, ignoresMouse: $0.ignoresMouseEvents,
                                 primaryHeight: h)
        }
        let event = DesktopPointer.Event(kind: kind, source: source, location: location, cursor: cursor,
                                         hitWindow: PointerMonitor.hitWindow(e), receiver: receiver, time: e.timestamp)
        trace?.received(source)
        apply(core.receive(event))
    }

    /// The window the window server handed the event to (nil when the event does not say). Supporting evidence only
    /// (`PointerRouter.assess`); what it holds for each monitor is for the live trace to show.
    static func hitWindow(_ e: NSEvent) -> Int? {
        guard let cg = e.cgEvent else { return nil }
        let n: Int64 = cg.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        return n > 0 ? Int(n) : nil
    }
}

/// The energy-test copy's pointer trace (`ASCII_ANIMALS_POINTER_TRACE=1`), for a supervised session. Every callback
/// and every judgement is a line (`PointerTraceLog`: shared sequence number, time, source, exact point, run-loop mode,
/// the route's reason, the verdict, the read and what was told), written to `pointer-trace.log` beside the copy's log,
/// at most 16 MB a run, flushed once a second. Once a second the copy's log also gets the events per source, the
/// judgements, the window-list reads and the frames drawn.
final class PointerTrace {
    static let enabled: Bool = Launch.identity.isEnergyTest
        && ProcessInfo.processInfo.environment["ASCII_ANIMALS_POINTER_TRACE"] == "1"
    static let file: URL = Log.folder.appendingPathComponent("pointer-trace.log")

    private let frames: () -> Int
    private weak var core: DesktopPointer?
    private let lines = PointerTraceLog(capacity: 16 << 20)
    private var handle: FileHandle? = nil
    private var counts: [PointerSource: Int] = [:]
    private var judged: Int = 0
    private var lastSummary: Double = 0
    private var readsAtSummary: Int = 0

    init(frames: @escaping () -> Int, core: DesktopPointer) {
        self.frames = frames
        self.core = core
        core.onReceive = { [weak self] e in self?.lines.callback(e, mode: PointerTrace.mode) }
        core.onDecision = { [weak self] d in self?.decided(d) }
    }

    private static var mode: String { RunLoop.current.currentMode?.rawValue ?? "none" }

    func started(global: Bool, local: Bool) {
        if handle == nil {
            try? FileManager.default.createDirectory(at: Log.folder, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: PointerTrace.file.path, contents: nil)
            handle = try? FileHandle(forWritingTo: PointerTrace.file)
        }
        Log.write("pointer trace: start; global monitor \(global ? "on" : "MISSING"), local monitor \(local ? "on" : "MISSING"); "
                  + "lines in \(PointerTrace.file.lastPathComponent)")
    }

    func stopped() {
        summary(force: true)
        flush()
        Log.write("pointer trace: stop")
    }

    func received(_ s: PointerSource) {
        counts[s, default: 0] += 1
    }

    func flushIfDue() { summary(force: false) }

    private func decided(_ d: DesktopPointer.Decision) {
        judged += 1
        lines.judgement(d, mode: PointerTrace.mode, frames: frames())
    }

    private func flush() {
        let out: [String] = lines.take()
        guard !out.isEmpty, let h = handle else { return }
        h.write(Data((out.joined(separator: "\n") + "\n").utf8))
    }

    private func summary(force: Bool) {
        let now: Double = ProcessInfo.processInfo.systemUptime
        guard force || now - lastSummary >= 1 else { return }
        lastSummary = now
        flush()
        let reads: Int = core?.fetches ?? 0
        let g: Int = counts[.global] ?? 0
        let l: Int = counts[.local] ?? 0
        Log.write("pointer 1s: global \(g) local \(l) judged \(judged) reads \(reads - readsAtSummary) frames \(frames())"
                  + (lines.full ? " (trace full)" : ""))
        counts.removeAll()
        judged = 0
        readsAtSummary = reads
    }
}
