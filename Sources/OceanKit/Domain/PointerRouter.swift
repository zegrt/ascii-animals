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

/// The window AppKit dispatched a local event to (`NSEvent.window`): one of ASCII Animals' own, known exactly
/// in-process. `frame`: global top-left points; `takesMouse`: it does not ignore mouse events.
public struct PointerReceiver: Equatable, Sendable {
    public var number: Int
    public var frame: CGRect
    public var takesMouse: Bool
    public init(number: Int, frame: CGRect, takesMouse: Bool = true) {
        self.number = number; self.frame = frame; self.takesMouse = takesMouse
    }
}

/// Why a reading was judged as it was (the trace's route reason).
public enum PointerReason: String, Sendable, CaseIterable {
    /// The own window AppKit dispatched it to holds the point.
    case receiver
    /// The window server named the window under the point (the event's hit field), and the list agrees.
    case eventHit = "event-hit"
    /// The hit named the desktop, but an own window the app knows holds the point.
    case ownWindow = "own-window"
    /// A hit an earlier move gave at this very point, still in its life.
    case retainedHint = "retained-hint"
    /// The window list's rectangles, front to back.
    case rectangles
    /// The list could not be read.
    case noList = "no-list"
    /// In no exposed screen.
    case offScreen = "off-screen"
    /// A drag of a gesture that began on a window.
    case gesture
    /// A click without its own location (never judged at the cursor).
    case noLocation = "no-location"
    /// The list is known stale and a read is not yet allowed: hover waits for it.
    case deferred
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

    /// What `p` is (see `assess`).
    public static func judge(_ p: CGPoint, windows: [PointerWindow]?, viewports: [Viewport], hit: Int? = nil,
                             receiver: PointerReceiver? = nil) -> PointerVerdict {
        assess(p, windows: windows, viewports: viewports, hit: hit, receiver: receiver).verdict
    }

    /// What `p` is, and why. `windows` front to back (nil: the list could not be read). In order of trust:
    /// - `receiver`, the own window AppKit dispatched the event to: when it takes the mouse and its frame holds `p`,
    ///   it blocks, listed or not (a window just opened may not be in the list yet);
    /// - `hit`, the window the window server named under the pointer
    ///   (`mouseEventWindowUnderMousePointerThatCanHandleThisEvent`): supporting evidence only, taken when the list
    ///   has that window and its bounds hold `p`, and never against an own window the app knows holds `p`;
    /// - else the rectangles, front to back (they know no shape or click-through: conservative).
    public static func assess(_ p: CGPoint, windows: [PointerWindow]?, viewports: [Viewport], hit: Int? = nil,
                              receiver: PointerReceiver? = nil) -> (verdict: PointerVerdict, reason: PointerReason) {
        guard let v = viewport(at: p, in: viewports) else { return (.offDesktop, .offScreen) }
        if let r = receiver, r.takesMouse, r.frame.contains(p) {
            let listed: PointerWindow? = windows?.first(where: { $0.number == r.number })
            let w: PointerWindow = listed ?? PointerWindow(number: r.number, pid: 0, own: true, layer: 0, bounds: r.frame)
            return (.blocked(w), .receiver)
        }
        guard let list = windows else { return (.unknown, .noList) }
        let local = CGPoint(x: p.x - v.rect.minX, y: p.y - v.rect.minY)
        let target = PointerTarget(viewportID: v.id, local: local)
        if let hit, hit > 0, let w = list.first(where: { $0.number == hit }), w.bounds.contains(p) {
            if !w.letsPointerThrough { return (.blocked(w), .eventHit) }
            if let own = list.first(where: { $0.own && blocks($0, at: p) }) { return (.blocked(own), .ownWindow) }
            return (.desktop(target), .eventHit)
        }
        for w in list where blocks(w, at: p) { return (.blocked(w), .rectangles) }
        return (.desktop(target), .rectangles)
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
/// The contract. Sources: the global and the local monitor (never consuming an event), and a sample of the cursor and
/// the left button from the display link (common modes, so modal and tracking loops too), at most once per simulation
/// step whichever display ticks (`tick`). A move or drag is coalesced: the newest waits for the next step, at the
/// event's own location. A click is judged at once, on its own event alone (its location, its hit, its receiver) and
/// a list read for it; a click with no location of its own is not a click. A step judges when there is something new:
/// a move, a new event at the same point, a gesture's button going up, a habitat to tell again (`retell`), or a read
/// that falls due. Freshness: `invalidate` (start, a Space or display change) is a boundary: the list is dropped,
/// read at the next step and once more `minRefetch` later; `windowsChanged` (an ordinary window change) marks it
/// stale: it is read at the next step if no read came within `minRefetch`, else hover waits for that read and is
/// never judged on the stale list. Otherwise the list is read at most every `moveLife` while the pointer moves and
/// every `stillLife` while it rests, so hover clears and comes back without a move. A hit a move gave is kept for the
/// samples at that very point for `hintLife`, while the same windows cover it; never for a click. Only changes are
/// told: one `left`, not one per move.
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
        /// The own window AppKit dispatched it to (local events only).
        public var receiver: PointerReceiver?
        public var time: Double
        /// The trace's sequence number, given on receipt.
        public var seq: Int = 0
        public init(kind: Kind, source: PointerSource, location: CGPoint?, cursor: CGPoint, hitWindow: Int? = nil,
                    receiver: PointerReceiver? = nil, time: Double) {
            self.kind = kind; self.source = source; self.location = location; self.cursor = cursor
            self.hitWindow = hitWindow; self.receiver = receiver; self.time = time
        }
    }

    public enum Output: Equatable, Sendable {
        case moved(PointerTarget)
        case left
        case down(PointerTarget)
    }

    /// One judged reading, for the diagnostic trace.
    public struct Decision: Sendable {
        /// The judged event's sequence number (a sample gets its own).
        public var seq: Int = 0
        public var reason: PointerReason = .rectangles
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
    /// The shortest time between two reads for an ordinary window change (a window dragged sends many), and the
    /// settle read after a boundary.
    public static let minRefetch: Double = 0.1
    /// How long a hit a move gave is kept for samples at that point.
    public static let hintLife: Double = 1.0

    private let viewportSource: () -> [Viewport]
    private let windowSource: () -> [PointerWindow]?
    private var screens: [Viewport]? = nil
    private var windows: [PointerWindow]? = nil
    private var haveWindows: Bool = false
    private var windowsAt: Double = -Double.infinity
    /// An ordinary window change since the last read.
    private var stale: Bool = false
    /// Reads still owed to a boundary (the one at the next step, and the settle read).
    private var settleReads: Int = 0
    private var pending: Event? = nil
    private var judgedPoint: CGPoint? = nil
    /// Something new to judge at the next step even at an unchanged point.
    private var rejudge: Bool = false
    /// The simulation step last sampled (one sample a step, whichever display ticks).
    private var lastStep: Int? = nil
    private var told: Bool = false
    private var current: PointerTarget? = nil
    /// A left-button gesture that began off the desktop (on a window): its drags are that window's.
    private var gestureOwned: Bool = false
    /// The window server's answer a move gave for a point, for the samples there while the same windows cover it.
    private var hint: (point: CGPoint, covering: [Int], verdict: PointerVerdict, at: Double)? = nil
    private var sequence: Int = 0

    /// Times the window list was read.
    public private(set) var fetches: Int = 0
    /// Times the screens were read.
    public private(set) var viewportReads: Int = 0
    /// Steps that sampled the pointer.
    public private(set) var samples: Int = 0
    public private(set) var running: Bool = false
    public private(set) var last: Decision? = nil
    /// Every judged reading (the energy-test copy's trace).
    public var onDecision: ((Decision) -> Void)? = nil
    /// Every event received (the trace's callback lines).
    public var onReceive: ((Event) -> Void)? = nil

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

    /// A boundary: Spaces, screens or what the desktop shows changed. The screens are read again, the list is dropped
    /// and read at the next step (and once more `minRefetch` later, for a transition still settling); the pointer is
    /// judged and told again there (a new scene learns it; the habitats take a repeat as a no-op).
    public func invalidate() {
        screens = nil
        windows = nil
        haveWindows = false
        stale = false
        settleReads = 2
        hint = nil
        told = false
        rejudge = true
    }

    /// An ordinary window change (an own window moved, resized, keyed, closed; a menu; the active app): the list is
    /// stale. It is read at the next step unless one came within `minRefetch`; until then hover waits.
    public func windowsChanged() {
        stale = true
        hint = nil
        rejudge = true
    }

    /// A habitat was replaced: tell its new scene the pointer at the next step (a move or a leave; never a click).
    public func retell() {
        guard running else { return }
        told = false
        rejudge = true
    }

    public func receive(_ e: Event) -> [Output] {
        guard running else { return [] }
        var e = e
        sequence += 1
        e.seq = sequence
        onReceive?(e)
        switch e.kind {
        case .move, .drag:
            if e.kind == .move { gestureOwned = false }
            pending = e
            return []
        case .down:
            pending = nil
            guard let p = e.location else {
                record(Decision(seq: e.seq, reason: .noLocation, source: e.source, kind: e.kind, point: e.cursor,
                                hitWindow: e.hitWindow, verdict: .unknown, fetched: false, outputs: [], time: e.time))
                return []
            }
            let fetched: Bool = readWindows(now: e.time, at: p)
            let a = PointerRouter.assess(p, windows: list, viewports: viewports(), hit: e.hitWindow, receiver: e.receiver)
            gestureOwned = a.verdict.target == nil
            judgedPoint = p
            var out: [Output] = tell(a.verdict.target)
            if let t = a.verdict.target { out.append(.down(t)) }
            record(Decision(seq: e.seq, reason: a.reason, source: e.source, kind: e.kind, point: p, hitWindow: e.hitWindow,
                            verdict: a.verdict, fetched: fetched, outputs: out, time: e.time))
            return out
        }
    }

    /// One simulation step: the newest move since the last step, or else the cursor (`buttonDown`: the left button
    /// is held now). Only the first call for a step samples; the others (more displays ticking) return at once.
    public func tick(cursor: CGPoint, buttonDown: Bool = false, now: Double) -> [Output] {
        guard running else { return [] }
        let step: Int = Int((now / OceanClock.step).rounded())
        if let l = lastStep, l == step { return [] }
        lastStep = step
        samples += 1
        if !buttonDown && pending?.kind != .drag {
            if gestureOwned { rejudge = true }
            gestureOwned = false
        }
        let e: Event? = pending
        pending = nil
        let source: PointerSource = e?.source ?? .sample
        let kind: Kind? = e?.kind
        let p: CGPoint = e.map { $0.location ?? $0.cursor } ?? cursor
        let hit: Int? = e?.hitWindow
        let moved: Bool = judgedPoint != p
        let news: Bool = e != nil || moved || rejudge
        if gestureOwned && (buttonDown || kind == .drag) {
            if !news { return [] }
            return finish(e, source: source, kind: kind, point: p, verdict: .gesture, reason: .gesture, fetched: false,
                          now: now)
        }
        if PointerRouter.viewport(at: p, in: viewports()) == nil {
            if !news && told && current == nil { return [] }
            return finish(e, source: source, kind: kind, point: p, verdict: .offDesktop, reason: .offScreen,
                          fetched: false, now: now)
        }
        let age: Double = now - windowsAt
        let mayRead: Bool = age >= DesktopPointer.minRefetch
        let due: Bool = !haveWindows || ((stale || settleReads > 0) && mayRead)
            || (moved && age >= DesktopPointer.moveLife) || age >= DesktopPointer.stillLife
        if stale && !due {
            // An ordinary window change inside the throttle: hover waits for the read, never judged on the old list.
            if let e { pending = e }
            if news {
                rejudge = true
                record(Decision(seq: e?.seq ?? nextSeq(), reason: .deferred, source: source, kind: kind, point: p,
                                hitWindow: hit, verdict: .unknown, fetched: false, outputs: [], time: now))
            }
            return []
        }
        if !due && !news { return [] }
        let fetched: Bool = due ? readWindows(now: now, at: p) : false
        let a = decide(p, event: e, now: now)
        return finish(e, source: source, kind: kind, point: p, verdict: a.verdict, reason: a.reason, fetched: fetched,
                      now: now)
    }

    // MARK: Inside

    private func reset() {
        screens = nil
        windows = nil
        haveWindows = false
        windowsAt = -Double.infinity
        stale = false
        settleReads = 0
        pending = nil
        judgedPoint = nil
        rejudge = false
        lastStep = nil
        told = false
        current = nil
        gestureOwned = false
        hint = nil
    }

    private var list: [PointerWindow]? { haveWindows ? windows : nil }

    private func nextSeq() -> Int {
        sequence += 1
        return sequence
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
        stale = false
        if settleReads > 0 { settleReads -= 1 }
        return true
    }

    /// Hover's verdict at `p`: a move's hit is kept as a hint; a sample at that very point takes the hint while it
    /// lives and the same windows cover the point.
    private func decide(_ p: CGPoint, event e: Event?, now: Double) -> (verdict: PointerVerdict, reason: PointerReason) {
        let l: [PointerWindow]? = list
        let a = PointerRouter.assess(p, windows: l, viewports: viewports(), hit: e?.hitWindow, receiver: e?.receiver)
        if a.reason == .eventHit, e != nil {
            hint = (p, PointerRouter.covering(p, windows: l), a.verdict, now)
            return a
        }
        if e == nil, a.reason == .rectangles, let h = hint, h.point == p, now - h.at < DesktopPointer.hintLife,
           h.covering == PointerRouter.covering(p, windows: l) {
            return (h.verdict, .retainedHint)
        }
        return a
    }

    private func finish(_ e: Event?, source: PointerSource, kind: Kind?, point: CGPoint, verdict: PointerVerdict,
                        reason: PointerReason, fetched: Bool, now: Double) -> [Output] {
        judgedPoint = point
        rejudge = false
        let out: [Output] = tell(verdict.target)
        record(Decision(seq: e?.seq ?? nextSeq(), reason: reason, source: source, kind: kind, point: point,
                        hitWindow: e?.hitWindow, verdict: verdict, fetched: fetched, outputs: out, time: now))
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

/// What the AppKit host installs and how it reads an event, as data the checks hold it to (`PointerMonitor` installs
/// exactly these monitors with this mask, and reads every event through `kind` and `location`).
public enum PointerHost {
    /// The monitors the host installs (the sample comes from the display link).
    public static let monitors: [PointerSource] = [.global, .local]
    /// The `NSEvent.EventType` raw values the monitors match: leftMouseDown 1, mouseMoved 5, leftMouseDragged 6.
    public static let eventTypes: [UInt] = [1, 5, 6]

    /// The monitors' `NSEvent.EventTypeMask` raw value.
    public static var mask: UInt64 {
        var m: UInt64 = 0
        for t in eventTypes { m |= UInt64(1) << UInt64(t) }
        return m
    }

    /// The pointer reading an event type is; nil for any other.
    public static func kind(eventType: UInt) -> DesktopPointer.Kind? {
        switch eventType {
        case 1: return .down
        case 5: return .move
        case 6: return .drag
        default: return nil
        }
    }

    /// The event's own location at event time, top-left global points: the window server's (`cgLocation`), else
    /// AppKit's screen point (bottom-left; from the receiving window, or a windowless event's own) flipped.
    public static func location(cgLocation: CGPoint?, screenPoint: CGPoint?, primaryHeight: CGFloat) -> CGPoint? {
        if let cg = cgLocation { return cg }
        if let s = screenPoint { return ScreenGeometry.flip(s, primaryHeight: primaryHeight) }
        return nil
    }

    /// An own window as a receiver: its AppKit frame (bottom-left) flipped to global top-left points.
    public static func receiver(number: Int, appKitFrame: CGRect, ignoresMouse: Bool, primaryHeight: CGFloat) -> PointerReceiver {
        PointerReceiver(number: number, frame: ScreenGeometry.flip(appKitFrame, primaryHeight: primaryHeight),
                        takesMouse: !ignoresMouse)
    }
}

/// The energy-test copy's pointer trace as lines, for a supervised session: every callback (`cb #n`) and every
/// judgement (`judge #n`), the judgement of a coalesced move sharing the number of the callback it judged; each with
/// its time (seconds since boot), source, kind, exact point, run-loop mode, and for a judgement the route's reason,
/// the verdict, whether it read the list and what the habitats were told. Bounded: past `capacity` bytes one line
/// says the trace is full, and no more are kept.
public final class PointerTraceLog {
    public let capacity: Int
    public private(set) var written: Int = 0
    public private(set) var full: Bool = false
    /// Lines not kept once full.
    public private(set) var dropped: Int = 0
    private var lines: [String] = []

    public init(capacity: Int = 16 << 20) { self.capacity = capacity }

    public func callback(_ e: DesktopPointer.Event, mode: String) {
        let at: String = e.location.map(PointerTraceLog.point) ?? "none"
        let hit: String = e.hitWindow.map { "\($0)" } ?? "-"
        let recv: String = e.receiver.map { r -> String in
            "\(r.number)\(r.takesMouse ? "" : " (no mouse)") \(PointerTraceLog.rect(r.frame))"
        } ?? "-"
        add("cb #\(e.seq) t=\(PointerTraceLog.time(e.time)) \(e.source.rawValue) \(e.kind.rawValue) at \(at) cursor "
            + "\(PointerTraceLog.point(e.cursor)) hit \(hit) receiver \(recv) mode \(mode)")
    }

    public func judgement(_ d: DesktopPointer.Decision, mode: String, frames: Int) {
        let hit: String = d.hitWindow.map { "\($0)" } ?? "-"
        let told: String = d.outputs.map(PointerTraceLog.output).joined(separator: ",")
        add("judge #\(d.seq) t=\(PointerTraceLog.time(d.time)) \(d.source.rawValue) \(d.kind?.rawValue ?? "sample") at "
            + "\(PointerTraceLog.point(d.point)) mode \(mode) reason \(d.reason.rawValue) hit \(hit) -> "
            + "\(PointerTraceLog.verdict(d.verdict)) read \(d.fetched ? "yes" : "no") told [\(told)] frames \(frames)")
    }

    /// The lines since the last take.
    public func take() -> [String] {
        let out: [String] = lines
        lines.removeAll(keepingCapacity: true)
        return out
    }

    private func add(_ line: String) {
        guard !full else { dropped += 1; return }
        let n: Int = line.utf8.count + 1
        if written + n > capacity {
            full = true
            dropped += 1
            let note: String = "pointer trace full at \(written) bytes: no more callback or judgement lines this run"
            lines.append(note)
            written += note.utf8.count + 1
            return
        }
        lines.append(line)
        written += n
    }

    static func time(_ t: Double) -> String { String(format: "%.6f", t) }
    static func point(_ p: CGPoint) -> String { String(format: "(%.2f, %.2f)", Double(p.x), Double(p.y)) }
    static func rect(_ r: CGRect) -> String {
        String(format: "%.0f,%.0f %.0fx%.0f", Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
    }

    public static func verdict(_ v: PointerVerdict) -> String {
        switch v {
        case .desktop(let t):
            return "desktop display \(t.viewportID) " + String(format: "(%.0f, %.0f)", Double(t.local.x), Double(t.local.y))
        case .blocked(let w):
            return "blocked by window \(w.number) pid \(w.pid)\(w.own ? " (own)" : "") layer \(w.layer) alpha "
                + String(format: "%.2f", w.alpha) + " rect \(rect(w.bounds))"
        case .gesture: return "a drag owned by a window"
        case .offDesktop: return "off the exposed desktop"
        case .unknown: return "unknown"
        }
    }

    public static func output(_ o: DesktopPointer.Output) -> String {
        switch o {
        case .moved(let t): return "moved \(t.viewportID)"
        case .left: return "left"
        case .down(let t): return "down \(t.viewportID)"
        }
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
