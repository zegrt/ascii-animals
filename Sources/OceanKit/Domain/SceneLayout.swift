import CoreGraphics

/// A display, in global points with a top-left origin.
public struct ScreenInfo: Equatable, Sendable {
    public var id: Int
    public var frame: CGRect
    public var scale: CGFloat
    public init(id: Int, frame: CGRect, scale: CGFloat) { self.id = id; self.frame = frame; self.scale = scale }
}

/// One world and the screens that look into it.
public struct ScenePlan: Equatable, Sendable {
    public struct View: Equatable, Sendable {
        public var screenID: Int
        /// The screen's area in ocean space.
        public var rect: CGRect
    }

    public var habitat: Habitat
    public var views: [View]
    /// One cell size for the whole scene, so the grid matches across screens.
    public var cell: CGSize
    /// Where ocean space's 0,0 sits in global coordinates.
    public var originInGlobal: CGPoint

    public var viewports: [(screenID: Int, rect: CGRect)] { views.map { ($0.screenID, $0.rect) } }
}

public enum SceneLayout {
    /// Shared: one scene spanning every screen. Separate (or a single screen):
    /// one scene per screen, sized and celled exactly as before.
    public static func plan(_ screens: [ScreenInfo], shared: Bool) -> [ScenePlan] {
        guard shared, screens.count > 1 else {
            return screens.map { s in
                let rect = CGRect(origin: .zero, size: s.frame.size)
                return ScenePlan(habitat: Habitat(rects: [rect]), views: [.init(screenID: s.id, rect: rect)],
                                 cell: GridSpec.cell(forWidth: s.frame.width), originInGlobal: s.frame.origin)
            }
        }
        let origin = CGPoint(x: screens.map(\.frame.minX).min()!, y: screens.map(\.frame.minY).min()!)
        let views = screens.map { s in
            ScenePlan.View(screenID: s.id, rect: s.frame.offsetBy(dx: -origin.x, dy: -origin.y))
        }
        let widest = screens.map(\.frame.width).max()!
        return [ScenePlan(habitat: Habitat(rects: views.map(\.rect)), views: views,
                          cell: GridSpec.cell(forWidth: widest), originInGlobal: origin)]
    }
}
