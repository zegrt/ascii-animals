import CoreGraphics
import Foundation

/// A screen's area in global coordinates (points, top-left origin).
public struct Viewport: Equatable, Sendable {
    public var id: Int
    public var rect: CGRect
    public init(id: Int, rect: CGRect) { self.id = id; self.rect = rect }
}

public struct PointerTarget: Equatable, Sendable {
    public var viewportID: Int
    public var local: CGPoint
    public init(viewportID: Int, local: CGPoint) { self.viewportID = viewportID; self.local = local }
}

public enum PointerRouter {
    /// The ocean under the cursor, or nil when a window, the menu bar or the
    /// Dock covers that spot, or when it is in no screen.
    public static func route(_ p: CGPoint, occluders: [CGRect], viewports: [Viewport]) -> PointerTarget? {
        if occluders.contains(where: { $0.contains(p) }) { return nil }
        guard let v = viewports.first(where: { $0.rect.contains(p) }) else { return nil }
        return PointerTarget(viewportID: v.id, local: CGPoint(x: p.x - v.rect.minX, y: p.y - v.rect.minY))
    }
}

public enum ScreenGeometry {
    /// AppKit (bottom-left origin) <-> CoreGraphics window list (top-left origin).
    /// The same call converts both ways.
    public static func flip(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    public static func flip(_ p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}

/// What the window the window server handed a pointer event to says about the desktop under it.
public enum EventWindow: Equatable, Sendable {
    /// The event carries no window number, or the number is not in the window list: judge by rectangles.
    case unknown
    /// A desktop-level window (below layer 0: the Finder's desktop, the system wallpaper, our own habitats).
    case desktop
    /// Any other window: it took the event, so the desktop did not.
    case window
}

/// One entry of the window list (`CGWindowListCopyWindowInfo`): its number and layer.
public struct ListedWindow: Equatable, Sendable {
    public var number: Int
    public var layer: Int
    public init(number: Int, layer: Int) { self.number = number; self.layer = layer }

    public static func parse(_ list: [[String: Any]]) -> [ListedWindow] {
        var out: [ListedWindow] = []
        out.reserveCapacity(list.count)
        for info in list {
            guard let n = info[kCGWindowNumber as String] as? NSNumber else { continue }
            let layer: Int = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            out.append(ListedWindow(number: n.intValue, layer: layer))
        }
        return out
    }
}

/// Each event window number's verdict, remembered: the window list is read only for a number not seen before (one
/// read fills the map for every listed window), and forgotten on a Space or display change (`clear`). Moving over
/// the desktop then costs a map lookup.
public final class EventWindowVerdicts {
    public private(set) var reads: Int = 0
    private var known: [Int: Int?] = [:]
    private let read: () -> [ListedWindow]
    private let now: () -> TimeInterval
    /// A bound on the map; past it, it starts again (one more read).
    private let capacity: Int = 512

    public init(read: @escaping () -> [ListedWindow], now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.read = read
        self.now = now
    }

    /// The verdict for `number` (0 or less: the event carries none) and the listed layer, if any.
    public func verdict(for number: Int) -> (EventWindow, layer: Int?) {
        guard number > 0 else { return (.unknown, nil) }
        if let layer = known[number] { return (EventWindowVerdicts.verdict(layer), layer) }
        if known.count >= capacity { known.removeAll(keepingCapacity: true) }
        reads += 1
        for w in read() { known[w.number] = .some(w.layer) }
        if known[number] == nil { known[number] = .some(nil) }
        let layer: Int? = known[number] ?? nil
        return (EventWindowVerdicts.verdict(layer), layer)
    }

    /// A Space or display change: forget every verdict.
    public func clear() { known.removeAll(keepingCapacity: true) }

    private static func verdict(_ layer: Int?) -> EventWindow {
        guard let layer else { return .unknown }
        return layer < 0 ? .desktop : .window
    }
}

extension PointerRouter {
    /// The ocean under `p` for an event the window server handed to a window with verdict `eventWindow`: a
    /// desktop-level window routes to the screen under `p`, whatever lies over it in the list (Notification Center's
    /// full-screen banner window, layer 21); any other window blocks; unknown falls back to the rectangles.
    public static func route(_ p: CGPoint, eventWindow: EventWindow, occluders: () -> [CGRect],
                             viewports: [Viewport]) -> PointerTarget? {
        switch eventWindow {
        case .desktop: return route(p, occluders: [], viewports: viewports)
        case .window: return nil
        case .unknown: return route(p, occluders: occluders(), viewports: viewports)
        }
    }
}

/// One pointer event as the monitor read it: the window number and the location carried by the event itself (top-left
/// global, nil when the event has none), and the cursor when the callback ran (for the trace).
public struct PointerEventFacts: Equatable, Sendable {
    public var window: Int
    public var location: CGPoint?
    public var cursorAtCallback: CGPoint?
    public init(window: Int, location: CGPoint?, cursorAtCallback: CGPoint?) {
        self.window = window
        self.location = location
        self.cursorAtCallback = cursorAtCallback
    }
}

extension PointerRouter {
    /// The ocean an event goes to, with the event window's verdict and listed layer (for the trace).
    public static func route(_ e: PointerEventFacts, verdicts: EventWindowVerdicts, occluders: () -> [CGRect],
                             viewports: [Viewport]) -> (target: PointerTarget?, verdict: EventWindow, layer: Int?) {
        // 5db562e: the point is the cursor when the callback runs.
        let (verdict, layer) = verdicts.verdict(for: e.window)
        guard let p = e.cursorAtCallback ?? e.location else { return (nil, verdict, layer) }
        return (route(p, eventWindow: verdict, occluders: occluders, viewports: viewports), verdict, layer)
    }
}
