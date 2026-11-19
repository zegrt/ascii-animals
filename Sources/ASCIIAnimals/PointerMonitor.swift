import AppKit
import OceanKit

/// Watches the cursor without taking any clicks from the desktop. Only
/// installed while the ocean is live and interaction is on.
final class PointerMonitor {
    private var monitor: Any?
    private var cachedOccluders: [CGRect] = []
    private var cachedAt: TimeInterval = 0
    private let viewports: () -> [Viewport]
    private let onMove: (PointerTarget?) -> Void
    private let onDown: (PointerTarget) -> Void
    static var logBlockers = ProcessInfo.processInfo.environment["OCEAN_LOG_POINTER"] != nil

    init(viewports: @escaping () -> [Viewport], onMove: @escaping (PointerTarget?) -> Void, onDown: @escaping (PointerTarget) -> Void) {
        self.viewports = viewports
        self.onMove = onMove
        self.onDown = onDown
    }

    var isRunning: Bool { monitor != nil }

    func setRunning(_ on: Bool) {
        if on, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]) { [weak self] e in
                self?.handle(e)
            }
        } else if !on, let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
            onMove(nil)
        }
    }

    private func handle(_ e: NSEvent) {
        guard let primary = NSScreen.screens.first else { return }
        let p = ScreenGeometry.flip(NSEvent.mouseLocation, primaryHeight: primary.frame.height)
        let isDown = e.type == .leftMouseDown
        let target = PointerRouter.route(p, occluders: occluders(fresh: isDown), viewports: viewports())
        onMove(target)
        if isDown, let target { onDown(target) }
    }

    /// Windows, the menu bar and the Dock, in top-left global coordinates.
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
            if PointerMonitor.logBlockers {
                NSLog("occluder %@ layer %d %@", info[kCGWindowOwnerName as String] as? String ?? "?", info[kCGWindowLayer as String] as? Int ?? 0, NSStringFromRect(r))
            }
            return r
        }
        return cachedOccluders
    }
}
