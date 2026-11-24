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

/// Each event window number's verdict. 971a216's model: it never looked at the event's window (a list read per look).
public final class EventWindowVerdicts {
    public private(set) var reads: Int = 0
    private let read: () -> [ListedWindow]

    public init(read: @escaping () -> [ListedWindow]) { self.read = read }

    /// The verdict for `number` (0 or less: the event carries none) and the listed layer, if any.
    public func verdict(for number: Int) -> (EventWindow, layer: Int?) {
        reads += 1
        _ = read()
        return (.unknown, nil)
    }

    /// A Space or display change: forget every verdict.
    public func clear() {}
}

extension PointerRouter {
    /// The ocean under `p` for an event the window server handed to a window with verdict `eventWindow`.
    /// 971a216: always the rectangles.
    public static func route(_ p: CGPoint, eventWindow: EventWindow, occluders: () -> [CGRect],
                             viewports: [Viewport]) -> PointerTarget? {
        route(p, occluders: occluders(), viewports: viewports)
    }
}
