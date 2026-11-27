import CoreGraphics

/// One display as the menu bar sees it, in AppKit's global coordinates (bottom-left origin).
public struct MenuBarScreen: Equatable, Sendable {
    public var frame: CGRect
    public var visible: CGRect
    /// The menu bar's usable areas either side of a camera notch (`NSScreen.auxiliaryTopLeftArea` and
    /// `auxiliaryTopRightArea`); empty on a display without a notch.
    public var besideNotch: [CGRect]

    public init(frame: CGRect, visible: CGRect, besideNotch: [CGRect] = []) {
        self.frame = frame
        self.visible = visible
        self.besideNotch = MenuBarIcon.notchAreas(besideNotch, frame: frame)
    }
}

/// Where the what's-new card and the welcome's "Settings live up here" step go, and whether they may point at the
/// menu bar icon: on the screen the person is working on (the active menu bar's display), with an arrow only to an
/// icon that is really showing there.
public enum MenuBarIcon {
    /// The screen in focus (`focused`, an index into `screens`; the first screen when it is nil or stale) and the
    /// icon on it, when the icon is usable there (`usable`). nil with no screens.
    public static func place(icon: CGRect?, screens: [MenuBarScreen], focused: Int?) -> (screen: Int, icon: CGRect?)? {
        guard !screens.isEmpty else { return nil }
        let i: Int = focused.flatMap { (f: Int) -> Int? in screens.indices.contains(f) ? f : nil } ?? 0
        return (i, usable(icon, on: screens[i]))
    }

    /// The icon's frame, when it can be pointed at on this screen: a real size, on this screen, in its menu bar (at
    /// or above the top of the visible frame; the app menu can push an item off it), and on a display with a notch,
    /// inside the usable menu bar either side of it (an icon pushed behind the notch shows nothing). Else nil: the
    /// card goes top right with no arrow, the welcome uses its hidden-icon words.
    public static func usable(_ icon: CGRect?, on s: MenuBarScreen) -> CGRect? {
        guard let icon, icon.width >= 1, icon.height >= 1, icon.minX.isFinite, icon.minY.isFinite,
              icon.maxX.isFinite, icon.maxY.isFinite else { return nil }
        let mid = CGPoint(x: icon.midX, y: icon.midY)
        guard s.frame.contains(mid) else { return nil }
        let inBar: Bool = icon.minY >= s.visible.maxY - 2 && icon.maxY <= s.frame.maxY + 1
        guard inBar else { return nil }
        if s.besideNotch.isEmpty { return icon }
        let clear: Bool = s.besideNotch.contains { (area: CGRect) -> Bool in
            let left: Bool = icon.minX >= area.minX - 1
            let right: Bool = icon.maxX <= area.maxX + 1
            return left && right
        }
        return clear ? icon : nil
    }

    /// The notch's side areas in global coordinates, empty ones dropped. AppKit gives them in the screen's own space;
    /// on the main display that is the same, elsewhere they are moved by the screen's origin when they don't already
    /// lie on it.
    public static func notchAreas(_ areas: [CGRect], frame: CGRect) -> [CGRect] {
        areas.compactMap { (a: CGRect) -> CGRect? in
            guard !a.isNull, a.width >= 1, a.height >= 1 else { return nil }
            if frame.contains(CGPoint(x: a.midX, y: a.midY)) { return a }
            let moved: CGRect = a.offsetBy(dx: frame.minX, dy: frame.minY)
            return frame.contains(CGPoint(x: moved.midX, y: moved.midY)) ? moved : nil
        }
    }
}
