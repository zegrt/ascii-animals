import CoreGraphics

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
