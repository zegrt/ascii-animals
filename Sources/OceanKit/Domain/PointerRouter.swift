import CoreGraphics
import Foundation

/// A screen's area in global coordinates (points, top-left origin). `exposed`: the window server reports the
/// desktop window on that screen at least partly visible (its occlusion state); a covered screen gets no pointer.
public struct Viewport: Equatable, Sendable {
    public var id: Int
    public var rect: CGRect
    public var exposed: Bool
    public init(id: Int, rect: CGRect, exposed: Bool = true) { self.id = id; self.rect = rect; self.exposed = exposed }
}

public struct PointerTarget: Equatable, Sendable {
    public var viewportID: Int
    public var local: CGPoint
    public init(viewportID: Int, local: CGPoint) { self.viewportID = viewportID; self.local = local }
}

/// One on-screen window as the window list gives it (front to back), in global top-left points. `own`: one of ASCII
/// Animals' windows; `wallpaper`: one of its desktop windows (the habitats themselves).
public struct PointerWindow: Equatable, Sendable {
    public var number: Int
    public var pid: Int32
    public var own: Bool
    public var wallpaper: Bool
    public var layer: Int
    public var alpha: Double
    public var bounds: CGRect
    public init(number: Int, pid: Int32, own: Bool = false, wallpaper: Bool = false, layer: Int = 0, alpha: Double = 1,
                bounds: CGRect) {
        self.number = number; self.pid = pid; self.own = own; self.wallpaper = wallpaper
        self.layer = layer; self.alpha = alpha; self.bounds = bounds
    }

    /// A desktop element: a habitat window, the Finder's desktop and icons, the system wallpaper (all below layer 0).
    public var isDesktop: Bool { wallpaper || layer < 0 }

    /// The window list (`CGWindowListCopyWindowInfo`, front to back) as pointer windows. `ownPID`: this process;
    /// `wallpaper`: the window numbers of its desktop windows. An entry without bounds is left out.
    public static func parse(_ list: [[String: Any]], ownPID: Int32, wallpaper: Set<Int>) -> [PointerWindow] {
        var out: [PointerWindow] = []
        out.reserveCapacity(list.count)
        for info in list {
            guard let d = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: d as CFDictionary) else { continue }
            let number: Int = (info[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
            let pid: Int32 = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let layer: Int = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha: Double = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            let own: Bool = pid == ownPID
            out.append(PointerWindow(number: number, pid: pid, own: own, wallpaper: own && wallpaper.contains(number),
                                     layer: layer, alpha: alpha, bounds: r))
        }
        return out
    }
}

/// Where a pointer reading came from: the global monitor (events dispatched to other apps), the local monitor (events
/// dispatched to ASCII Animals itself), or the once-a-step sample of the cursor.
public enum PointerSource: String, Sendable, CaseIterable {
    case global, local, sample
}

/// Where the window server dispatched a mouse event: to another app, to ASCII Animals (through `sendEvent`), or into
/// one of ASCII Animals' nested tracking loops (a menu, a control, a window drag).
public enum PointerDispatch: String, Sendable, CaseIterable {
    case foreign, own, ownTracking
}

public enum PointerDelivery {
    /// Which installed source sees an event dispatched `d` (AppKit's rules: a global monitor gets copies of events
    /// dispatched to other apps; a local monitor gets the app's own events that pass through `sendEvent`, never those
    /// a nested tracking loop takes). Nil: no callback runs for it.
    public static func source(for d: PointerDispatch, installed: Set<PointerSource>) -> PointerSource? {
        switch d {
        case .foreign: return installed.contains(.global) ? .global : nil
        case .own: return installed.contains(.local) ? .local : nil
        case .ownTracking: return nil
        }
    }
}

/// What a point on the screens is, for the desktop.
public enum PointerVerdict: Equatable, Sendable {
    /// Exposed desktop: the habitat under it.
    case desktop(PointerTarget)
    /// A window covers it (the frontmost one that does, or the one the window server handed the event to).
    case blocked(PointerWindow)
    /// A drag of a left-button gesture that began on a window: it belongs to that window, wherever it goes.
    case gesture
    /// In no screen the desktop shows on (a gap, or a covered screen).
    case offDesktop
    /// The window list could not be read: nothing is known, so nothing is routed.
    case unknown

    public var target: PointerTarget? {
        if case .desktop(let t) = self { return t }
        return nil
    }
}

public enum PointerRouter {
    /// The ocean under the cursor, or nil when a window, the menu bar or the
    /// Dock covers that spot, or when it is in no screen.
    public static func route(_ p: CGPoint, occluders: [CGRect], viewports: [Viewport]) -> PointerTarget? {
        if occluders.contains(where: { $0.contains(p) }) { return nil }
        guard let v = viewports.first(where: { $0.rect.contains(p) }) else { return nil }
        return PointerTarget(viewportID: v.id, local: CGPoint(x: p.x - v.rect.minX, y: p.y - v.rect.minY))
    }

    /// The exposed screen under `p`, if any (no window list needed).
    public static func viewport(at p: CGPoint, in viewports: [Viewport]) -> Viewport? {
        guard let v = viewports.first(where: { $0.rect.contains(p) }), v.exposed else { return nil }
        return v
    }

    /// What `p` is. `windows` front to back (nil: the list could not be read). `hit`: the window the window server
    /// handed the event to, when the event says (`mouseEventWindowUnderMousePointerThatCanHandleThisEvent`); it
    /// overrules the rectangles, which know no shape or click-through.
    public static func judge(_ p: CGPoint, windows: [PointerWindow]?, viewports: [Viewport], hit: Int? = nil) -> PointerVerdict {
        // BEFORE (971a216): a failed list is an empty one; any rectangle blocks; no hit test; any screen counts.
        let list: [PointerWindow] = windows ?? []
        for w in list where blocks(w, at: p) { return .blocked(w) }
        guard let v = viewports.first(where: { $0.rect.contains(p) }) else { return .offDesktop }
        let local = CGPoint(x: p.x - v.rect.minX, y: p.y - v.rect.minY)
        return .desktop(PointerTarget(viewportID: v.id, local: local))
    }

    /// The window numbers whose rectangles cover `p` and could block it, front to back.
    public static func covering(_ p: CGPoint, windows: [PointerWindow]?) -> [Int] {
        guard let list = windows else { return [] }
        var out: [Int] = []
        for w in list where blocks(w, at: p) { out.append(w.number) }
        return out
    }

    /// Whether `w` keeps `p` from the desktop: any window of layer 0 or above that is not see-through, the app's own
    /// windows (Settings, About, alerts, the card) included; the desktop elements never.
    public static func blocks(_ w: PointerWindow, at p: CGPoint) -> Bool {
        // BEFORE (971a216): the app's own process is ignored wholesale.
        if w.own { return false }
        if w.layer < 0 { return false }
        if w.alpha < 0.01 { return false }
        return w.bounds.contains(p)
    }
}

/// The desktop's pointer input, MODELLED ON 971a216 (the proof's "before"): one global monitor, the cursor at
/// callback time, a 50 ms window cache that survives start and stop, no sample, one output per event.
public final class DesktopPointer {
    public enum Kind: String, Sendable { case move, drag, down }

    public struct Event: Sendable {
        public var kind: Kind
        public var source: PointerSource
        public var location: CGPoint?
        public var cursor: CGPoint
        public var hitWindow: Int?
        public var time: Double
        public init(kind: Kind, source: PointerSource, location: CGPoint?, cursor: CGPoint, hitWindow: Int? = nil,
                    time: Double) {
            self.kind = kind; self.source = source; self.location = location; self.cursor = cursor
            self.hitWindow = hitWindow; self.time = time
        }
    }

    public enum Output: Equatable, Sendable {
        case moved(PointerTarget)
        case left
        case down(PointerTarget)
    }

    public struct Decision: Sendable {
        public var source: PointerSource
        public var kind: Kind?
        public var point: CGPoint
        public var hitWindow: Int?
        public var verdict: PointerVerdict
        public var fetched: Bool
        public var outputs: [Output]
        public var time: Double
    }

    public static let sources: Set<PointerSource> = [.global]
    public static let moveLife: Double = 0.05
    public static let stillLife: Double = 1.0   // no sample: never used to re-judge
    public static let minRefetch: Double = 0
    public static let sampleGap: Double = 0

    private let viewportSource: () -> [Viewport]
    private let windowSource: () -> [PointerWindow]?
    private var cache: [PointerWindow]? = nil
    private var cachedAt: Double = 0
    public private(set) var fetches: Int = 0
    public private(set) var viewportReads: Int = 0
    public private(set) var running: Bool = false
    public private(set) var last: Decision? = nil
    public var onDecision: ((Decision) -> Void)? = nil

    public init(viewports: @escaping () -> [Viewport], windows: @escaping () -> [PointerWindow]?) {
        viewportSource = viewports
        windowSource = windows
    }

    public func start(now: Double) -> [Output] { running = true; return [] }
    public func stop() -> [Output] { running = false; return [.left] }
    public func invalidate() {}

    public func receive(_ e: Event) -> [Output] {
        guard running else { return [] }
        let p: CGPoint = e.cursor
        let isDown: Bool = e.kind == .down
        var fetched: Bool = false
        if isDown || e.time - cachedAt >= DesktopPointer.moveLife {
            cache = windowSource() ?? []
            cachedAt = e.time
            fetches += 1
            fetched = true
        }
        let vps: [Viewport] = viewportSource()
        viewportReads += 1
        let verdict: PointerVerdict = PointerRouter.judge(p, windows: cache, viewports: vps)
        var out: [Output] = [verdict.target.map { Output.moved($0) } ?? .left]
        if isDown, let t = verdict.target { out.append(.down(t)) }
        last = Decision(source: e.source, kind: e.kind, point: p, hitWindow: e.hitWindow, verdict: verdict,
                        fetched: fetched, outputs: out, time: e.time)
        return out
    }

    public func tick(cursor: CGPoint, buttonDown: Bool = false, now: Double) -> [Output] { [] }
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
