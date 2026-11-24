import AppKit
import OceanKit

/// Watches the cursor without taking any clicks from the desktop. Only
/// installed while the ocean is live and interaction is on.
///
/// Each move, drag and click is judged by the window the window server handed it to (the event's window number):
/// a desktop-level window (below layer 0, our habitats included) routes to the ocean, any other window blocks, and an
/// event with no window number falls back to the window rectangles. A notification banner's full-screen window
/// (layer 21) therefore no longer hides the desktop. The point is the event's own location (the same event as the window
/// number), never the cursor when the callback runs; an event without one does nothing. Verdicts are remembered per
/// window number and forgotten on a Space or display change, so moving over the desktop reads no window list; a number
/// the list does not have is not remembered (looked up again at most once a second).
final class PointerMonitor {
    private var monitor: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var cachedOccluders: [CGRect] = []
    private var cachedAt: TimeInterval = 0
    private let verdicts = EventWindowVerdicts(read: {
        ListedWindow.parse(CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
    })
    private let viewports: () -> [Viewport]
    private let onMove: (PointerTarget?) -> Void
    private let onDown: (PointerTarget) -> Void
    private let trace: PointerTrace? = PointerTrace.enabled ? PointerTrace() : nil

    init(viewports: @escaping () -> [Viewport], onMove: @escaping (PointerTarget?) -> Void, onDown: @escaping (PointerTarget) -> Void) {
        self.viewports = viewports
        self.onMove = onMove
        self.onDown = onDown
    }

    var isRunning: Bool { monitor != nil }

    func setRunning(_ on: Bool) {
        if on, monitor == nil {
            forget()
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]) { [weak self] e in
                self?.handle(e)
            }
            observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification)
            observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
        } else if !on, let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
            for (center, token) in observers { center.removeObserver(token) }
            observers.removeAll()
            onMove(nil)
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.forget() }
        observers.append((center, token))
    }

    /// A Space or display change: window numbers and rectangles from before it say nothing now.
    private func forget() {
        verdicts.clear()
        cachedAt = 0
    }

    private func handle(_ e: NSEvent) {
        let cg: CGEvent? = e.cgEvent
        let isDown = e.type == .leftMouseDown
        let facts = PointerEventFacts(window: PointerMonitor.eventWindow(cg), location: cg?.location,
                                      cursorAtCallback: trace == nil ? nil : PointerMonitor.cursorNow())
        let routed = PointerRouter.route(facts, verdicts: verdicts, occluders: { self.occluders(fresh: isDown) },
                                         viewports: viewports())
        trace?.line(e.type, facts: facts, layer: routed.layer, verdict: routed.verdict, target: routed.target)
        // No point of its own: the event does nothing (no move, no click).
        guard facts.location != nil else { return }
        onMove(routed.target)
        if isDown, let target = routed.target { onDown(target) }
    }

    /// The window the window server handed the event to (0 when the event does not say).
    private static func eventWindow(_ cg: CGEvent?) -> Int {
        guard let cg else { return 0 }
        let n: Int64 = cg.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        return n > 0 ? Int(n) : 0
    }

    /// The cursor now, in top-left global coordinates (for the trace only).
    private static func cursorNow() -> CGPoint? {
        guard let primary = NSScreen.screens.first else { return nil }
        return ScreenGeometry.flip(NSEvent.mouseLocation, primaryHeight: primary.frame.height)
    }

    /// Windows, the menu bar and the Dock, in top-left global coordinates (only for events with no window number).
    private func occluders(fresh: Bool) -> [CGRect] {
        let now = ProcessInfo.processInfo.systemUptime
        if !fresh && now - cachedAt < 0.05 { return cachedOccluders }
        cachedAt = now
        let me = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        cachedOccluders = list.compactMap { info in
            if (info[kCGWindowOwnerPID as String] as? pid_t) == me { return nil }
            if (info[kCGWindowLayer as String] as? Int ?? 0) < 0 { return nil }
            if (info[kCGWindowAlpha as String] as? Double ?? 1) < 0.01 { return nil }
            guard let d = info[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: d) else { return nil }
            return r
        }
        return cachedOccluders
    }
}

/// The energy-test copy's pointer trace (`ASCII_ANIMALS_POINTER_TRACE=1`): one line per event (type, the event's
/// window number and listed layer, the verdict, the event's point, the cursor when the callback ran and where it went)
/// in `pointer-trace.log` beside the copy's log, at most 16 MB a run.
final class PointerTrace {
    static let enabled: Bool = Launch.identity.isEnergyTest
        && ProcessInfo.processInfo.environment["ASCII_ANIMALS_POINTER_TRACE"] == "1"
    private let handle: FileHandle?
    private var written: Int = 0

    init() {
        let file: URL = Log.folder.appendingPathComponent("pointer-trace.log")
        try? FileManager.default.createDirectory(at: Log.folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        handle = try? FileHandle(forWritingTo: file)
        Log.write("pointer trace: lines in \(file.lastPathComponent)")
    }

    func line(_ type: NSEvent.EventType, facts: PointerEventFacts, layer: Int?, verdict: EventWindow, target: PointerTarget?) {
        guard let h = handle, written < 16 << 20 else { return }
        let kind: String = type == .leftMouseDown ? "down" : type == .leftMouseDragged ? "drag" : "move"
        let t: String = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        let at: String = PointerTrace.text(facts.location)
        let cursor: String = PointerTrace.text(facts.cursorAtCallback)
        let to: String = target.map { "screen \($0.viewportID)" } ?? "none"
        let lay: String = layer.map { "\($0)" } ?? "-"
        let s: String = "\(t) \(kind) window \(facts.window) layer \(lay) verdict \(verdict) at \(at) cursor \(cursor) -> \(to)\n"
        let data: Data = Data(s.utf8)
        written += data.count
        h.write(data)
    }

    private static func text(_ p: CGPoint?) -> String {
        guard let p else { return "-" }
        return "\(Int(p.x)),\(Int(p.y))"
    }
}
