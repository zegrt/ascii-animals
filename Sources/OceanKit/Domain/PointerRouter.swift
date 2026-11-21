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
/// Animals' windows; `clickThrough`: one of those that takes no mouse events (the habitats' desktop windows, the
/// welcome's dims), which AppKit knows exactly in-process.
public struct PointerWindow: Equatable, Sendable {
    public var number: Int
    public var pid: Int32
    public var own: Bool
    public var clickThrough: Bool
    public var layer: Int
    public var alpha: Double
    public var bounds: CGRect
    public init(number: Int, pid: Int32, own: Bool = false, clickThrough: Bool = false, layer: Int = 0,
                alpha: Double = 1, bounds: CGRect) {
        self.number = number; self.pid = pid; self.own = own; self.clickThrough = clickThrough
        self.layer = layer; self.alpha = alpha; self.bounds = bounds
    }

    /// The pointer goes through it to the desktop: a desktop element (the Finder's desktop and icons, the system
    /// wallpaper, a habitat; all below layer 0) or an own window that takes no mouse events.
    public var letsPointerThrough: Bool { clickThrough || layer < 0 }

    /// The window list (`CGWindowListCopyWindowInfo`, front to back) as pointer windows. `ownPID`: this process;
    /// `clickThrough`: the numbers of its windows that take no mouse events. An entry without bounds is left out.
    public static func parse(_ list: [[String: Any]], ownPID: Int32, clickThrough: Set<Int>) -> [PointerWindow] {
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
            let through: Bool = own && clickThrough.contains(number)
            out.append(PointerWindow(number: number, pid: pid, own: own, clickThrough: through, layer: layer,
                                     alpha: alpha, bounds: r))
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
        guard let v = viewport(at: p, in: viewports) else { return .offDesktop }
        guard let list = windows else { return .unknown }
        let local = CGPoint(x: p.x - v.rect.minX, y: p.y - v.rect.minY)
        let target = PointerTarget(viewportID: v.id, local: local)
        if let hit, hit > 0, let w = list.first(where: { $0.number == hit }) {
            return w.letsPointerThrough ? .desktop(target) : .blocked(w)
        }
        for w in list where blocks(w, at: p) { return .blocked(w) }
        return .desktop(target)
    }

    /// The window numbers whose rectangles cover `p` and could block it, front to back.
    public static func covering(_ p: CGPoint, windows: [PointerWindow]?) -> [Int] {
        guard let list = windows else { return [] }
        var out: [Int] = []
        for w in list where blocks(w, at: p) { out.append(w.number) }
        return out
    }

    /// Whether `w` keeps `p` from the desktop: any window of layer 0 or above that is not see-through, the app's own
    /// windows that take the mouse (Settings, About, alerts, the welcome, the card) included; never one that lets the
    /// pointer through.
    public static func blocks(_ w: PointerWindow, at p: CGPoint) -> Bool {
        if w.letsPointerThrough { return false }
        if w.alpha < 0.01 { return false }
        return w.bounds.contains(p)
    }
}

/// The desktop's pointer input: every reading of the pointer, from whichever source, goes through here and comes out
/// as moves, leaves and clicks for the habitats. Pure: the host feeds it events, samples and the window list.
///
/// The contract. Sources: the global and the local monitor (never consuming an event), and a sample of the cursor once
/// a simulation step from the display link (common modes, so modal and tracking loops too). A move or drag is
/// coalesced: the newest waits for the next step, at the event's own location. A click is judged at once, at its own
/// location, against a fresh window list. Every reading is judged against the windows front to back, the app's own
/// windows blocking like any other. A step with no move judges the sampled cursor when it moved, when the windows,
/// Spaces, screens or delivery changed (`invalidate`), and once a second at the least, so hover clears and comes back
/// without a move. The window list is read only for a point on an exposed screen, at most every `moveLife` while
/// the pointer moves, every `stillLife` while it rests and every `minRefetch` after an invalidation; a click reads it.
/// Only changes are told: one `left`, not one per move.
public final class DesktopPointer {
    public enum Kind: String, Sendable { case move, drag, down }

    /// A mouse event as a monitor saw it: its own location at event time (top-left global points; nil when the
    /// event has none), the cursor at the time the callback ran, and the window the window server handed it to.
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

    /// One judged reading, for the diagnostic trace.
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

    /// The sources the host installs.
    public static let sources: Set<PointerSource> = [.global, .local, .sample]
    /// How old a window list a moving pointer may be judged against.
    public static let moveLife: Double = 0.25
    /// How often a resting pointer is judged again (a window opening or closing under it).
    public static let stillLife: Double = 1.0
    /// The shortest time between two reads after an invalidation (a window dragged sends many).
    public static let minRefetch: Double = 0.1
    /// Several screens tick each step: one sample a step.
    public static let sampleGap: Double = OceanClock.step * 0.5

    private let viewportSource: () -> [Viewport]
    private let windowSource: () -> [PointerWindow]?
    private var screens: [Viewport]? = nil
    private var windows: [PointerWindow]? = nil
    private var haveWindows: Bool = false
    private var windowsAt: Double = -Double.infinity
    private var dirty: Bool = true
    private var pending: Event? = nil
    private var judgedPoint: CGPoint? = nil
    private var lastSampleAt: Double = -Double.infinity
    private var told: Bool = false
    private var current: PointerTarget? = nil
    /// A left-button gesture that began off the desktop (on a window): its drags are that window's.
    private var gestureOwned: Bool = false
    /// The window server's answer for a point, kept for the samples there while the same windows cover it.
    private var hint: (point: CGPoint, covering: [Int], verdict: PointerVerdict)? = nil

    /// Times the window list was read.
    public private(set) var fetches: Int = 0
    /// Times the screens were read.
    public private(set) var viewportReads: Int = 0
    public private(set) var running: Bool = false
    public private(set) var last: Decision? = nil
    /// Every judged reading (the energy-test copy's trace).
    public var onDecision: ((Decision) -> Void)? = nil

    public init(viewports: @escaping () -> [Viewport], windows: @escaping () -> [PointerWindow]?) {
        viewportSource = viewports
        windowSource = windows
    }

    public func start(now: Double) -> [Output] {
        reset()
        running = true
        return []
    }

    public func stop() -> [Output] {
        reset()
        running = false
        return [.left]
    }

    /// Windows, Spaces, screens or the app receiving events changed: the screens are read again, the window list at
    /// the next step (within `minRefetch`), and the pointer judged and told again there (a new scene learns it; the
    /// habitats take a repeat as a no-op).
    public func invalidate() {
        screens = nil
        dirty = true
        hint = nil
        told = false
    }

    public func receive(_ e: Event) -> [Output] {
        guard running else { return [] }
        switch e.kind {
        case .move, .drag:
            if e.kind == .move { gestureOwned = false }
            pending = e
            return []
        case .down:
            pending = nil
            let p: CGPoint = e.location ?? e.cursor
            let fetched: Bool = readWindows(now: e.time, at: p)
            let verdict: PointerVerdict = decide(p, hit: e.hitWindow)
            gestureOwned = verdict.target == nil
            var out: [Output] = tell(verdict.target)
            if let t = verdict.target { out.append(.down(t)) }
            record(Decision(source: e.source, kind: e.kind, point: p, hitWindow: e.hitWindow, verdict: verdict,
                            fetched: fetched, outputs: out, time: e.time))
            return out
        }
    }

    /// One simulation step: the newest move since the last step, or else the cursor (`buttonDown`: the left button
    /// is held now).
    public func tick(cursor: CGPoint, buttonDown: Bool = false, now: Double) -> [Output] {
        guard running, now - lastSampleAt >= DesktopPointer.sampleGap else { return [] }
        lastSampleAt = now
        if !buttonDown && pending?.kind != .drag { gestureOwned = false }
        var source: PointerSource = .sample
        var kind: Kind? = nil
        var p: CGPoint = cursor
        var hit: Int? = nil
        if let e = pending {
            pending = nil
            source = e.source
            kind = e.kind
            p = e.location ?? e.cursor
            hit = e.hitWindow
        }
        if gestureOwned && (buttonDown || kind == .drag) {
            return finish(source: source, kind: kind, point: p, hit: hit, verdict: .gesture, fetched: false, now: now)
        }
        let moved: Bool = judgedPoint != p
        let onScreen: Bool = PointerRouter.viewport(at: p, in: viewports()) != nil
        if !onScreen {
            if !moved && told && current == nil { return [] }
            return finish(source: source, kind: kind, point: p, hit: hit, verdict: .offDesktop, fetched: false, now: now)
        }
        let age: Double = now - windowsAt
        let due: Bool = !haveWindows || (dirty && age >= DesktopPointer.minRefetch)
            || (moved && age >= DesktopPointer.moveLife) || age >= DesktopPointer.stillLife
        if !moved && !due { return [] }
        let fetched: Bool = due ? readWindows(now: now, at: p) : false
        let verdict: PointerVerdict = decide(p, hit: hit)
        return finish(source: source, kind: kind, point: p, hit: hit, verdict: verdict, fetched: fetched, now: now)
    }

    // MARK: Inside

    private func reset() {
        screens = nil
        windows = nil
        haveWindows = false
        windowsAt = -Double.infinity
        dirty = true
        pending = nil
        judgedPoint = nil
        lastSampleAt = -Double.infinity
        told = false
        current = nil
        gestureOwned = false
        hint = nil
    }

    private func viewports() -> [Viewport] {
        if let s = screens { return s }
        let s: [Viewport] = viewportSource()
        viewportReads += 1
        screens = s
        return s
    }

    /// Reads the window list, for a point on an exposed screen only. True when it read.
    private func readWindows(now: Double, at p: CGPoint) -> Bool {
        guard PointerRouter.viewport(at: p, in: viewports()) != nil else { return false }
        windows = windowSource()
        fetches += 1
        haveWindows = true
        windowsAt = now
        dirty = false
        return true
    }

    /// The verdict at `p`; the window server's word (`hit`) is kept for later samples at that very point while the
    /// same windows cover it.
    private func decide(_ p: CGPoint, hit: Int?) -> PointerVerdict {
        let list: [PointerWindow]? = haveWindows ? windows : nil
        let v: PointerVerdict = PointerRouter.judge(p, windows: list, viewports: viewports(), hit: hit)
        let cover: [Int] = PointerRouter.covering(p, windows: list)
        if let hit, hit > 0, list != nil {
            hint = (p, cover, v)
            return v
        }
        if let h = hint, h.point == p, h.covering == cover, list != nil { return h.verdict }
        return v
    }

    private func finish(source: PointerSource, kind: Kind?, point: CGPoint, hit: Int?, verdict: PointerVerdict,
                        fetched: Bool, now: Double) -> [Output] {
        judgedPoint = point
        let out: [Output] = tell(verdict.target)
        record(Decision(source: source, kind: kind, point: point, hitWindow: hit, verdict: verdict, fetched: fetched,
                        outputs: out, time: now))
        return out
    }

    /// Only a change: the habitat under the pointer, or that there is none.
    private func tell(_ t: PointerTarget?) -> [Output] {
        if told && t == current { return [] }
        told = true
        current = t
        if let t { return [.moved(t)] }
        return [.left]
    }

    private func record(_ d: Decision) {
        last = d
        onDecision?(d)
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
