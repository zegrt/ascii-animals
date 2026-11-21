import AppKit
import CoreGraphics
import Foundation
import OceanKit

// The desktop's pointer contract (brief r1, audit a1 finding 1), driven on a model desk: two screens, the windows
// front to back, the cursor, a clock, and where the window server dispatches each event (`PointerDelivery`: AppKit's
// rules for which monitor sees it). The desk installs what the host installs (`DesktopPointer.sources`) and feeds the
// pointer as `PointerMonitor` does: events as they come, a tick each simulation step when the sample is installed.

/// A model desk around one `DesktopPointer`.
final class PointerDesk {
    var viewports: [Viewport]
    var windows: [PointerWindow]?
    var cursor: CGPoint = CGPoint(x: 720, y: 450)
    var now: Double = 100
    var button: Bool = false
    var out: [DesktopPointer.Output] = []
    private(set) var pointer: DesktopPointer! = nil

    init(viewports: [Viewport] = PointerDesk.twoScreens, windows: [PointerWindow]? = []) {
        self.viewports = viewports
        self.windows = windows
        pointer = DesktopPointer(viewports: { [unowned self] in self.viewports },
                                 windows: { [unowned self] in self.windows })
        out += pointer.start(now: now)
    }

    static let screen1: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900)
    static let screen2: CGRect = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    static let twoScreens: [Viewport] = [Viewport(id: 1, rect: screen1), Viewport(id: 2, rect: screen2)]

    /// An event at `p` (its own location; nil: the event has none), dispatched `d`; the cursor is at
    /// `cursorAtCallback` (default `p`) by the time a callback runs, and stays there. `receiver`: the own window AppKit
    /// dispatched it to.
    func deliver(_ kind: DesktopPointer.Kind, at p: CGPoint?, via d: PointerDispatch, cursorAtCallback: CGPoint? = nil,
                 hit: Int? = nil, receiver: PointerReceiver? = nil) {
        let c: CGPoint = cursorAtCallback ?? p ?? cursor
        cursor = c
        guard let src = PointerDelivery.source(for: d, installed: DesktopPointer.sources) else { return }
        let e = DesktopPointer.Event(kind: kind, source: src, location: p, cursor: c, hitWindow: hit, receiver: receiver,
                                     time: now)
        out += pointer.receive(e)
    }

    func move(to p: CGPoint, via d: PointerDispatch = .foreign, hit: Int? = nil, receiver: PointerReceiver? = nil) {
        deliver(button ? .drag : .move, at: p, via: d, hit: hit, receiver: receiver)
    }

    func click(at p: CGPoint?, via d: PointerDispatch = .foreign, cursorAtCallback: CGPoint? = nil, hit: Int? = nil,
               receiver: PointerReceiver? = nil) {
        deliver(.down, at: p, via: d, cursorAtCallback: cursorAtCallback, hit: hit, receiver: receiver)
    }

    /// One simulation step later (the host samples on the display link).
    func tick(_ dt: Double = OceanClock.step) {
        now += dt
        guard DesktopPointer.sources.contains(.sample) else { return }
        out += pointer.tick(cursor: cursor, buttonDown: button, now: now)
    }

    func ticks(for seconds: Double) {
        let n: Int = Int((seconds / OceanClock.step).rounded(.up))
        for _ in 0..<n { tick() }
    }

    /// The habitat under the pointer as the outputs so far tell it (nil: none, or nothing told yet).
    var target: PointerTarget? {
        for o in out.reversed() {
            switch o {
            case .moved(let t): return t
            case .left: return nil
            case .down: continue
            }
        }
        return nil
    }

    var downs: [PointerTarget] {
        out.compactMap { o -> PointerTarget? in
            if case .down(let t) = o { return t }
            return nil
        }
    }

    var lefts: Int { out.filter { $0 == .left }.count }

    var routedAnything: Bool {
        out.contains { o -> Bool in
            if case .left = o { return false }
            return true
        }
    }
}

private func t1(_ x: CGFloat, _ y: CGFloat) -> PointerTarget { PointerTarget(viewportID: 1, local: CGPoint(x: x, y: y)) }

private let desktopSpot: CGPoint = CGPoint(x: 100, y: 500)
/// Finder's desktop window (desktop-icon level).
private let finderDesktop: PointerWindow = PointerWindow(number: 5, pid: 300, layer: -2147483603, bounds: PointerDesk.screen1)
/// One of ASCII Animals' own desktop windows (the habitat on screen 1).
private let habitatWindow: PointerWindow = PointerWindow(number: 10, pid: 42, own: true, clickThrough: true,
                                                         layer: -2147483623, bounds: PointerDesk.screen1)
/// Another app's window, and a spot on it.
private let foreignWindow: PointerWindow = PointerWindow(number: 60, pid: 500, layer: 0,
                                                         bounds: CGRect(x: 500, y: 300, width: 400, height: 300))
private let onForeign: CGPoint = CGPoint(x: 600, y: 400)

func pointerChecks() {
    pointerDeliveryChecks()
    pointerEligibilityChecks()
    pointerFreshnessChecks()
    pointerBudgetChecks()
    pointerFeelChecks()
    pointerRound1Checks()
    pointerCadenceChecks()
    pointerHostChecks()
}

// MARK: Delivery: own dispatch, nested loops, the event's own location

private func pointerDeliveryChecks() {
    // An Animals alert (or Settings) is in front: the events go to ASCII Animals, which no global monitor sees.
    func ownDispatchReachesDesktop() throws {
        let alert = PointerWindow(number: 41, pid: 42, own: true, layer: 0,
                                  bounds: CGRect(x: 500, y: 300, width: 420, height: 180))
        let d = PointerDesk(windows: [alert, habitatWindow])
        d.move(to: desktopSpot, via: .own)
        d.tick()
        try expect(d.target == t1(100, 500), "a move dispatched to ASCII Animals never reached the habitat: \(d.out)")
        d.click(at: CGPoint(x: 300, y: 700), via: .own)
        try expect(d.downs == [t1(300, 700)], "a click on bare desktop dispatched to ASCII Animals was lost: \(d.out)")
    }
    check("pointerOwnDispatchReachesDesktop", ownDispatchReachesDesktop)

    func foreignDispatch() throws {
        let d = PointerDesk(windows: [foreignWindow, finderDesktop])
        d.move(to: desktopSpot)
        d.tick()
        try expect(d.target == t1(100, 500), "a foreign move: \(d.out)")
        d.click(at: CGPoint(x: 120, y: 520))
        try expect(d.downs == [t1(120, 520)], "a foreign click: \(d.out)")
    }
    check("pointerForeignDispatch", foreignDispatch)

    // An own menu tracks the mouse in a nested loop: no monitor sees those events, the sample does.
    func nestedLoopFollowsTheCursor() throws {
        let d = PointerDesk(windows: [foreignWindow])
        d.move(to: desktopSpot)
        d.tick()
        let menu = PointerWindow(number: 70, pid: 42, own: true, layer: 101,
                                 bounds: CGRect(x: 80, y: 480, width: 220, height: 300))
        d.windows = [menu, foreignWindow]
        d.pointer.invalidate()   // the host: the menu began tracking
        d.move(to: CGPoint(x: 150, y: 600), via: .ownTracking)
        d.ticks(for: 0.2)
        try expect(d.target == nil, "the pointer went onto an own menu in its tracking loop, the habitat kept it: \(d.out)")
        d.move(to: CGPoint(x: 1000, y: 800), via: .ownTracking)
        d.ticks(for: 0.3)
        try expect(d.target == t1(1000, 800), "a move on bare desktop during the loop never reached the habitat: \(d.out)")
    }
    check("pointerNestedLoopFollowsTheCursor", nestedLoopFollowsTheCursor)

    // The cursor has moved on by the time the callback runs: the click is where the event says.
    func clickAtEventLocation() throws {
        let d = PointerDesk(windows: [foreignWindow, finderDesktop])
        d.click(at: desktopSpot, cursorAtCallback: onForeign)
        try expect(d.downs == [t1(100, 500)], "a click on bare desktop judged where the cursor went later: \(d.out)")
        let e = PointerDesk(windows: [foreignWindow, finderDesktop])
        e.click(at: onForeign, cursorAtCallback: desktopSpot)
        try expect(e.downs.isEmpty, "a click on a window became a click on the desktop where the cursor went: \(e.out)")
    }
    check("pointerClickAtEventLocation", clickAtEventLocation)
}

// MARK: Eligibility: z-order, own windows, shapes, failed lists, screens

private func pointerEligibilityChecks() {
    // An Animals window over the habitat blocks it like any other window (moves over an inactive Animals window go
    // to the active app, so the global monitor sees them).
    func ownWindowBlocks() throws {
        let settings = PointerWindow(number: 40, pid: 42, own: true, layer: 0,
                                     bounds: CGRect(x: 500, y: 300, width: 400, height: 300))
        let d = PointerDesk(windows: [settings, habitatWindow])
        d.move(to: onForeign)
        d.tick()
        try expect(d.target == nil && !d.routedAnything, "the habitat under an Animals window took the pointer: \(d.out)")
        d.click(at: onForeign)
        try expect(d.downs.isEmpty, "a click on an Animals window reached the habitat: \(d.out)")
        d.move(to: desktopSpot)
        d.tick()
        try expect(d.target == t1(100, 500), "the habitat's own window blocked it: \(d.out)")
    }
    check("pointerOwnWindowBlocks", ownWindowBlocks)

    // The welcome dims the other displays with own windows that take no mouse events: the pointer goes through them.
    func ownClickThroughWindowPasses() throws {
        let dim = PointerWindow(number: 43, pid: 42, own: true, clickThrough: true, layer: 24, alpha: 0.55,
                                bounds: PointerDesk.screen2)
        let d = PointerDesk(windows: [dim])
        d.click(at: CGPoint(x: 2000, y: 500))
        try expect(d.downs == [PointerTarget(viewportID: 2, local: CGPoint(x: 560, y: 500))],
                   "an own window that takes no mouse events blocked the desktop: \(d.out)")
    }
    check("pointerOwnClickThroughWindowPasses", ownClickThroughWindowPasses)

    // A display-sized foreign surface whose pixels are clear: the window server hands the click to the desktop.
    func clickThroughSurface() throws {
        let overlay = PointerWindow(number: 77, pid: 600, layer: 25, alpha: 1, bounds: PointerDesk.screen1)
        let d = PointerDesk(windows: [overlay, habitatWindow, finderDesktop])
        d.click(at: desktopSpot, hit: finderDesktop.number)
        try expect(d.downs == [t1(100, 500)], "the window server sent the click to the desktop, a rectangle refused it: \(d.out)")
        // Fix round 1, finding 1: a click's hit is that click's alone; a resting pointer is judged by the rectangles
        // again at its next refresh (before: the click's verdict was kept for the hover with no end).
        d.ticks(for: DesktopPointer.stillLife + 0.1)
        try expect(d.target == nil, "a click's hit held the hover of the resting pointer: \(d.out)")
        let e = PointerDesk(windows: [overlay, habitatWindow, finderDesktop])
        e.click(at: desktopSpot)
        try expect(e.downs.isEmpty, "with no word from the window server the rectangle must hold (conservative): \(e.out)")
        e.click(at: CGPoint(x: 700, y: 20), hit: overlay.number)
        try expect(e.downs.isEmpty, "a click the window server gave the surface reached the habitat: \(e.out)")
    }
    check("pointerClickThroughSurface", clickThroughSurface)

    func unreadableWindowList() throws {
        let d = PointerDesk(windows: nil)
        d.move(to: desktopSpot)
        d.tick()
        d.click(at: desktopSpot)
        try expect(!d.routedAnything, "with no window list the pointer was routed as if nothing covered it: \(d.out)")
        d.windows = [foreignWindow]
        d.ticks(for: DesktopPointer.stillLife + 0.1)
        try expect(d.target == t1(100, 500), "the hover did not come back once the list could be read: \(d.out)")
    }
    check("pointerUnreadableWindowList", unreadableWindowList)

    // A popup on one display, a click on bare desktop on the other.
    func twoScreens() throws {
        let popup = PointerWindow(number: 80, pid: 700, layer: 0, bounds: PointerDesk.screen1)
        let d = PointerDesk(windows: [popup])
        d.click(at: CGPoint(x: 2000, y: 500))
        try expect(d.downs == [PointerTarget(viewportID: 2, local: CGPoint(x: 560, y: 500))], "\(d.out)")
        d.click(at: desktopSpot)
        try expect(d.downs.count == 1, "a click on the popup reached screen 1: \(d.out)")
    }
    check("pointerTwoScreens", twoScreens)

    // A covered screen (a full-screen app): no window list, nothing routed.
    func coveredScreenSkips() throws {
        let covered: [Viewport] = [Viewport(id: 1, rect: PointerDesk.screen1, exposed: false),
                                   Viewport(id: 2, rect: PointerDesk.screen2)]
        let d = PointerDesk(viewports: covered, windows: [foreignWindow])
        for i in 0..<120 {
            let x: CGFloat = 100 + CGFloat(i) * 5
            d.move(to: CGPoint(x: x, y: 700))
            if i % 2 == 1 { d.tick() }
        }
        try expect(d.pointer.fetches == 0, "\(d.pointer.fetches) window-list reads for a pointer on a covered screen")
        try expect(!d.routedAnything, "a covered screen took the pointer: \(d.out)")
    }
    check("pointerCoveredScreenSkips", coveredScreenSkips)

    // A left-button gesture that began on a window is that window's, wherever its drag goes.
    func dragOwnedByItsWindow() throws {
        let d = PointerDesk(windows: [foreignWindow])
        d.click(at: onForeign)
        d.button = true
        d.move(to: CGPoint(x: 450, y: 450))
        d.tick()
        d.move(to: desktopSpot)
        d.tick()
        try expect(!d.routedAnything, "a drag from a window entered the habitat: \(d.out)")
        d.button = false
        d.move(to: CGPoint(x: 110, y: 510))
        d.tick()
        try expect(d.target == t1(110, 510), "after the button came up the hover did not come back: \(d.out)")
        d.click(at: desktopSpot)
        d.button = true
        d.move(to: CGPoint(x: 300, y: 600))
        d.tick()
        try expect(d.target == t1(300, 600), "a drag on bare desktop lost the hover: \(d.out)")
    }
    check("pointerDragOwnedByItsWindow", dragOwnedByItsWindow)
}

// MARK: Freshness: windows that change under a still pointer, start, stop, invalidation

private func pointerFreshnessChecks() {
    func stillPointerRechecks() throws {
        let d = PointerDesk(windows: [habitatWindow])
        d.move(to: desktopSpot)
        d.tick()
        try expect(d.target == t1(100, 500), "\(d.out)")
        let popup = PointerWindow(number: 90, pid: 800, layer: 0, bounds: CGRect(x: 0, y: 400, width: 400, height: 300))
        d.windows = [popup, habitatWindow]
        d.ticks(for: DesktopPointer.stillLife + 0.1)
        try expect(d.target == nil, "a popup opened under the resting pointer, the habitat kept it: \(d.out)")
        d.windows = [habitatWindow]
        d.ticks(for: DesktopPointer.stillLife + 0.1)
        try expect(d.target == t1(100, 500), "the popup closed, the hover did not come back: \(d.out)")
    }
    check("pointerStillPointerRechecks", stillPointerRechecks)

    func restartReadsWindows() throws {
        let d = PointerDesk(windows: [])
        d.move(to: desktopSpot)
        d.tick()
        d.out += d.pointer.stop()
        d.windows = [PointerWindow(number: 91, pid: 800, layer: 0, bounds: CGRect(x: 0, y: 400, width: 400, height: 300))]
        d.now += 0.01
        d.out += d.pointer.start(now: d.now)
        d.move(to: desktopSpot)
        d.tick()
        try expect(d.target == nil, "after a restart the pointer was judged against the old window list: \(d.out)")
    }
    check("pointerRestartReadsWindows", restartReadsWindows)

    // An own window opens (the host invalidates on key, close, move, Space and activation changes).
    func invalidationRejudges() throws {
        let d = PointerDesk(windows: [habitatWindow])
        d.move(to: desktopSpot)
        d.tick()
        let welcome = PointerWindow(number: 92, pid: 42, own: true, layer: 0,
                                    bounds: CGRect(x: 0, y: 300, width: 600, height: 400))
        d.windows = [welcome, habitatWindow]
        d.pointer.invalidate()
        d.ticks(for: DesktopPointer.minRefetch + 2 * OceanClock.step)
        try expect(d.target == nil, "an invalidation left the hover on the habitat under a new window: \(d.out)")
        d.viewports = [Viewport(id: 1, rect: CGRect(x: 0, y: 0, width: 1440, height: 900)),
                       Viewport(id: 2, rect: CGRect(x: -1920, y: 0, width: 1920, height: 1080))]
        d.windows = [habitatWindow]
        d.pointer.invalidate()
        d.move(to: CGPoint(x: -100, y: 500))
        d.tick()
        try expect(d.target == PointerTarget(viewportID: 2, local: CGPoint(x: 1820, y: 500)),
                   "a display rearranged, the old layout routed: \(d.out)")
    }
    check("pointerInvalidationRejudges", invalidationRejudges)

    // Fresh scenes (a display change) learn a resting pointer: an invalidation tells it again, once.
    func invalidationRetells() throws {
        let d = PointerDesk(windows: [habitatWindow])
        d.move(to: desktopSpot)
        d.tick()
        d.out.removeAll()
        d.pointer.invalidate()
        d.ticks(for: 1.5 * DesktopPointer.minRefetch)
        try expect(d.out == [.moved(t1(100, 500))], "after an invalidation the resting pointer was told \(d.out)")
    }
    check("pointerInvalidationRetells", invalidationRetells)
}

// MARK: Budget: window-list reads (audit a2's hot path)

/// `seconds` of foreign moves at 120 Hz over screen 1 (around the windows), a step each 1/60 s; the reads.
private func burstReads(seconds: Double) -> (moves: Int, reads: Int, viewportReads: Int) {
    let w2 = PointerWindow(number: 61, pid: 501, layer: 0, bounds: CGRect(x: 1000, y: 100, width: 300, height: 200))
    let menuBar = PointerWindow(number: 3, pid: 100, layer: 24, bounds: CGRect(x: 0, y: 0, width: 1440, height: 24))
    let d = PointerDesk(windows: [menuBar, foreignWindow, w2, habitatWindow, finderDesktop])
    let moves: Int = Int(seconds * 120)
    for i in 0..<moves {
        let a: Double = Double(i) * 0.05
        let x: CGFloat = CGFloat(720.0 + 600.0 * cos(a))
        let y: CGFloat = CGFloat(450.0 + 380.0 * sin(a))
        d.now += 1.0 / 120.0
        d.move(to: CGPoint(x: x, y: y))
        if i % 2 == 1 { d.tick(0) }
    }
    return (moves, d.pointer.fetches, d.pointer.viewportReads)
}

private func pointerBudgetChecks() {
    func burstBudget() throws {
        let r = burstReads(seconds: 2)
        print("INFO pointer burst: \(r.moves) moves in 2 s, \(r.reads) window-list reads, \(r.viewportReads) screen reads")
        try expect(r.reads <= 10, "\(r.reads) window-list reads for 2 s of moves (at most 10)")
        try expect(r.viewportReads <= 1, "\(r.viewportReads) screen reads for 2 s of moves (no display changed)")
    }
    check("pointerBurstReadBudget", burstBudget)

    func restingBudget() throws {
        let d = PointerDesk(windows: [foreignWindow, habitatWindow])
        d.move(to: desktopSpot)
        d.tick()
        let before: Int = d.pointer.fetches
        d.ticks(for: 60)
        let reads: Int = d.pointer.fetches - before
        print("INFO pointer resting a minute on bare desktop: \(reads) window-list reads")
        try expect(reads <= 61, "\(reads) reads in a resting minute")
    }
    check("pointerRestingBudget", restingBudget)

    // Clicks stay immediate and exact: each reads the list once, at once.
    func clicksReadOnce() throws {
        let d = PointerDesk(windows: [foreignWindow, habitatWindow])
        let before: Int = d.pointer.fetches
        for i in 0..<10 { d.click(at: CGPoint(x: 100 + CGFloat(i), y: 500)); d.now += 0.01 }
        try expect(d.pointer.fetches - before == 10, "\(d.pointer.fetches - before) reads for 10 clicks")
        try expect(d.downs.count == 10, "\(d.downs.count) of 10 clicks told")
    }
    check("pointerClicksReadOnce", clicksReadOnce)

    func oneLeftPerChange() throws {
        let d = PointerDesk(windows: [foreignWindow])
        d.move(to: desktopSpot)
        d.tick()
        for i in 0..<30 {
            d.move(to: CGPoint(x: 550 + CGFloat(i), y: 400))
            d.tick()
        }
        try expect(d.lefts == 1, "\(d.lefts) leaves told for one move off the desktop")
    }
    check("pointerOneLeftPerChange", oneLeftPerChange)

    // Not a pass/fail: what a real window-list read and its bridging cost on this machine (nil on a runner without
    // a window server). The host reads at most the budgets above.
    func windowListCost() throws {
        let canned: [[String: Any]] = [
            [kCGWindowNumber as String: NSNumber(value: 12), kCGWindowOwnerPID as String: NSNumber(value: 42),
             kCGWindowLayer as String: NSNumber(value: -2147483623), kCGWindowAlpha as String: NSNumber(value: 1.0),
             kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 1440, height: 900).dictionaryRepresentation],
            [kCGWindowNumber as String: NSNumber(value: 13), kCGWindowOwnerPID as String: NSNumber(value: 42),
             kCGWindowLayer as String: NSNumber(value: 0), kCGWindowAlpha as String: NSNumber(value: 1.0),
             kCGWindowBounds as String: CGRect(x: 10, y: 20, width: 300, height: 200).dictionaryRepresentation],
            [kCGWindowNumber as String: NSNumber(value: 14), kCGWindowOwnerPID as String: NSNumber(value: 9)],
        ]
        let parsed: [PointerWindow] = PointerWindow.parse(canned, ownPID: 42, clickThrough: [12])
        try expect(parsed.count == 2, "an entry without bounds kept: \(parsed)")
        try expect(parsed[0].clickThrough && parsed[0].own && parsed[0].letsPointerThrough, "the habitat window: \(parsed[0])")
        try expect(parsed[1].own && !parsed[1].clickThrough && parsed[1].bounds == CGRect(x: 10, y: 20, width: 300, height: 200),
                   "an own window: \(parsed[1])")
        let n: Int = 50
        let start: Double = ProcessInfo.processInfo.systemUptime
        var count: Int = 0
        for _ in 0..<n {
            let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            count = PointerWindow.parse(raw, ownPID: getpid(), clickThrough: []).count
        }
        let ms: Double = (ProcessInfo.processInfo.systemUptime - start) * 1000 / Double(n)
        print("INFO pointer window-list read + parse: " + String(format: "%.3f", ms) + " ms each (\(count) windows)")
    }
    check("pointerWindowListCost", windowListCost)
}

// MARK: The same feel on exposed desktop, and the Meadow's still pointer

private func pointerFeelChecks() {
    // Over exposed desktop the habitats get what the old router gave, at each step.
    func sameFeel() throws {
        let menuBar = PointerWindow(number: 3, pid: 100, layer: 24, bounds: CGRect(x: 0, y: 0, width: 3360, height: 24))
        let list: [PointerWindow] = [menuBar, foreignWindow, habitatWindow, finderDesktop]
        let rects: [CGRect] = [menuBar.bounds, foreignWindow.bounds]
        let d = PointerDesk(windows: list)
        var rng = SplitMix(seed: 7)
        var p: CGPoint = CGPoint(x: 200, y: 600)
        for step in 0..<600 {
            let dx: CGFloat = CGFloat(rng.unit() * 40 - 20)
            let dy: CGFloat = CGFloat(rng.unit() * 40 - 20)
            p = CGPoint(x: min(max(p.x + dx, 0), 3359), y: min(max(p.y + dy, 0), 899))
            d.move(to: p)
            d.tick()
            let want: PointerTarget? = PointerRouter.route(p, occluders: rects, viewports: PointerDesk.twoScreens)
            try expect(d.target == want, "step \(step) at \(p): told \(String(describing: d.target)), the router \(String(describing: want))")
            if step % 50 == 0 {
                d.click(at: p)
                let clicked: Bool = d.downs.last == want && want != nil
                try expect(clicked || want == nil, "a click at \(p) not told as the router says")
            }
        }
    }
    check("pointerSameFeelOnExposedDesktop", sameFeel)

    // The Meadow: a resting pointer is told once (its still time accrues, so one may land); a popup opening under it
    // takes it from the meadow within a second, without a move.
    func meadowStillPointer() throws {
        let sim = MeadowSim(settings: .defaults, seed: 3)
        let d = PointerDesk(windows: [habitatWindow])
        func feed() {
            for o in d.out {
                switch o {
                case .moved(let t): sim.pointerMoved(Double(t.local.x), Double(t.local.y))
                case .left: sim.pointerLeft()
                case .down(let t): sim.pointerDown(Double(t.local.x), Double(t.local.y))
                }
            }
            d.out.removeAll()
        }
        d.move(to: desktopSpot)
        d.tick()
        feed()
        try expect(sim.world.pointerHas, "the meadow never got the pointer")
        var told: Int = 0
        for _ in 0..<180 { d.tick(); told += d.out.count; feed() }
        try expect(told == 0, "a resting pointer was told \(told) more times (its still time restarts)")
        d.windows = [PointerWindow(number: 93, pid: 900, layer: 0, bounds: CGRect(x: 0, y: 450, width: 300, height: 200)),
                     habitatWindow]
        for _ in 0..<Int((DesktopPointer.stillLife + 0.1) / OceanClock.step) { d.tick(); feed() }
        try expect(!sim.world.pointerHas, "a popup over the resting pointer, the meadow still holds it")
    }
    check("pointerMeadowStillPointer", meadowStillPointer)
}

/// A small deterministic generator for the walks above.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func unit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
}

// MARK: Fix round 1 (review r1 @ a3f20ee): each finding, then what the review found missing

/// A display-sized foreign surface (an overlay whose pixels may be clear).
private let overlay: PointerWindow = PointerWindow(number: 77, pid: 600, layer: 25, alpha: 1, bounds: PointerDesk.screen1)

private func pointerRound1Checks() {
    // Finding 1: a down judges only its own event against a fresh list; a hint a move left is for hover, and ends.
    func downJudgesItsOwnEvent() throws {
        let d = PointerDesk(windows: [overlay, habitatWindow, finderDesktop])
        d.move(to: desktopSpot, hit: finderDesktop.number)
        d.tick()
        try expect(d.target == t1(100, 500), "a move the window server gave the desktop: \(d.out)")
        d.now += 0.2
        d.click(at: desktopSpot)
        try expect(d.downs.isEmpty, "a click with no hit of its own took the desktop verdict a move left: \(d.out)")
        let e = PointerDesk(windows: [overlay, habitatWindow, finderDesktop])
        e.move(to: desktopSpot, hit: finderDesktop.number)
        e.tick()
        e.ticks(for: DesktopPointer.hintLife + DesktopPointer.stillLife + 0.1)
        try expect(e.target == nil, "one move's hit held the resting pointer's hover with no end: \(e.out)")
    }
    check("pointerDownJudgesItsOwnEvent", downJudgesItsOwnEvent)

    // Finding 2: the own window AppKit dispatched to rejects the point when it holds it (even before the window list
    // has it); a click needs its own location; the hit field is supporting evidence, never against what is known.
    func receiverAndLocation() throws {
        let alert = PointerReceiver(number: 44, frame: CGRect(x: 0, y: 300, width: 420, height: 400))
        let d = PointerDesk(windows: [habitatWindow, finderDesktop])
        d.click(at: desktopSpot, via: .own, receiver: alert)
        try expect(d.downs.isEmpty, "a click AppKit gave an own alert (not yet in the list) reached the habitat: \(d.out)")
        d.move(to: desktopSpot, via: .own, receiver: alert)
        d.tick()
        try expect(d.target == nil, "a move over the own window AppKit named reached the habitat: \(d.out)")
        d.move(to: CGPoint(x: 1000, y: 800), via: .own, receiver: alert)
        d.tick()
        try expect(d.target == t1(1000, 800), "a receiver that does not hold the point blocked bare desktop: \(d.out)")
        let e = PointerDesk(windows: [])
        e.click(at: nil, cursorAtCallback: CGPoint(x: 2000, y: 500))
        try expect(e.downs.isEmpty, "a click with no location of its own was put where the cursor went: \(e.out)")
        let settings = PointerWindow(number: 40, pid: 42, own: true, layer: 0,
                                     bounds: CGRect(x: 0, y: 300, width: 400, height: 400))
        let f = PointerDesk(windows: [settings, habitatWindow, finderDesktop])
        f.click(at: desktopSpot, hit: finderDesktop.number)
        try expect(f.downs.isEmpty, "a hit naming the desktop outranked an own window known to hold the point: \(f.out)")
        let otherDesktop = PointerWindow(number: 6, pid: 300, layer: -2147483603, bounds: PointerDesk.screen2)
        let g = PointerDesk(windows: [overlay, habitatWindow, finderDesktop, otherDesktop])
        g.click(at: desktopSpot, hit: otherDesktop.number)
        try expect(g.downs.isEmpty, "a hit naming a window that does not hold the point was taken: \(g.out)")
    }
    check("pointerReceiverAndLocation", receiverAndLocation)

    // Finding 3: new facts at an unchanged point (a hit; the button going up after a drag) count at the next step,
    // with no extra read.
    func samePointNewFacts() throws {
        let d = PointerDesk(windows: [overlay, habitatWindow, finderDesktop])
        d.move(to: desktopSpot)
        d.tick()
        try expect(d.target == nil, "the overlay's rectangle blocks a move with no hit: \(d.out)")
        let reads: Int = d.pointer.fetches
        d.move(to: desktopSpot, hit: finderDesktop.number)
        d.tick()
        try expect(d.target == t1(100, 500), "a new hit at the same point was dropped: \(d.out)")
        try expect(d.pointer.fetches == reads, "a new hit read the list again (\(d.pointer.fetches - reads))")
        let e = PointerDesk(windows: [foreignWindow, habitatWindow])
        e.click(at: onForeign)
        e.button = true
        e.move(to: desktopSpot)
        e.tick()
        try expect(e.target == nil, "a drag from a window entered the habitat: \(e.out)")
        let reads2: Int = e.pointer.fetches
        e.button = false
        e.tick()
        e.tick()
        try expect(e.target == t1(100, 500), "a drag released over bare desktop stayed the window's: \(e.out)")
        try expect(e.pointer.fetches == reads2, "the release read the list again (\(e.pointer.fetches - reads2))")
    }
    check("pointerSamePointNewFacts", samePointNewFacts)

    // Finding 4: a Space or display change is a boundary (the next step reads); an ordinary window change defers hover
    // until a read is allowed, never judging on the old list; a burst of them keeps the throttle.
    func boundaryWaitsForFreshList() throws {
        let spot2: CGPoint = CGPoint(x: 800, y: 600)
        let opened = PointerWindow(number: 94, pid: 901, layer: 0, bounds: CGRect(x: 700, y: 500, width: 300, height: 300))
        let d = PointerDesk(windows: [habitatWindow])
        d.move(to: desktopSpot)
        d.tick()
        d.windows = [opened, habitatWindow]
        d.pointer.invalidate()
        d.move(to: spot2)
        d.tick()
        try expect(d.target == nil, "after a Space change a move was judged on the old list: \(d.out)")
        let own = PointerWindow(number: 95, pid: 42, own: true, layer: 0, bounds: opened.bounds)
        let e = PointerDesk(windows: [habitatWindow])
        e.move(to: desktopSpot)
        e.tick()
        e.windows = [own, habitatWindow]
        e.pointer.windowsChanged()
        e.move(to: spot2)
        e.tick()
        try expect(!e.out.contains(.moved(t1(800, 600))), "a move inside the throttle was judged on the old list: \(e.out)")
        e.ticks(for: DesktopPointer.minRefetch + 2 * OceanClock.step)
        try expect(e.target == nil, "after the read the new window did not block: \(e.out)")
        let f = PointerDesk(windows: [own, habitatWindow])
        let before: Int = f.pointer.fetches
        var told: Int = 0
        for i in 0..<240 {
            f.now += 1.0 / 120.0
            f.move(to: CGPoint(x: 100 + CGFloat(i), y: 200))
            if i % 2 == 1 {
                f.pointer.windowsChanged()
                let n: Int = f.out.count
                f.tick(0)
                told += f.out.count - n
            }
        }
        let reads: Int = f.pointer.fetches - before
        print("INFO pointer own window changing at 60 Hz for 2 s while moving: \(reads) window-list reads, \(told) told")
        try expect(reads <= 22, "\(reads) reads for 2 s of window changes (the throttle allows 21)")
        try expect(told >= 15, "the hover starved during a burst of window changes: \(told) told in 2 s")
    }
    check("pointerBoundaryWaitsForFreshList", boundaryWaitsForFreshList)

    // Finding 5: every callback and every judgement is its own line, sharing a sequence number, with time, run-loop
    // mode, exact point, source and the route's reason; the trace is bounded.
    func traceRecordsCallbacksAndJudgements() throws {
        let d = PointerDesk(windows: [overlay, habitatWindow, finderDesktop])
        let log = PointerTraceLog(capacity: 1 << 20)
        d.pointer.onReceive = { e in log.callback(e, mode: "kCFRunLoopDefaultMode") }
        d.pointer.onDecision = { r in log.judgement(r, mode: "NSEventTrackingRunLoopMode", frames: 0) }
        d.move(to: CGPoint(x: 100.25, y: 500.75))
        d.move(to: CGPoint(x: 101, y: 500))
        d.move(to: CGPoint(x: 102, y: 500))
        d.tick()
        let a: [String] = log.take()
        let cbs: [String] = a.filter { $0.hasPrefix("cb ") }
        let js: [String] = a.filter { $0.hasPrefix("judge ") }
        try expect(cbs.count == 3 && js.count == 1, "three callbacks and one judgement, as lines: \(a)")
        try expect(cbs[0].contains("#1 ") && cbs[0].contains("(100.25, 500.75)") && cbs[0].contains("kCFRunLoopDefaultMode"),
                   "a callback line: \(cbs[0])")
        try expect(js[0].contains("#3 ") && js[0].contains("reason rectangles") && js[0].contains("NSEventTrackingRunLoopMode")
                   && js[0].contains("t=") && js[0].contains("global move"), "the judgement line: \(js[0])")
        d.move(to: CGPoint(x: 103, y: 500))
        d.tick()
        try expect(log.take().filter { $0.hasPrefix("judge ") }.count == 1, "a judgement with the same verdict left no line")
        d.move(to: CGPoint(x: 103, y: 500), hit: finderDesktop.number)
        d.tick()
        let hitLines: [String] = log.take()
        try expect(hitLines.contains { $0.hasPrefix("judge ") && $0.contains("reason event-hit") }, "no event-hit line: \(hitLines)")
        d.ticks(for: DesktopPointer.stillLife + 0.05)
        let hintLines: [String] = log.take()
        try expect(hintLines.contains { $0.contains("sample") && $0.contains("reason retained-hint") },
                   "no retained-hint line: \(hintLines)")
        let small = PointerTraceLog(capacity: 600)
        d.pointer.onReceive = { e in small.callback(e, mode: "m") }
        d.pointer.onDecision = { r in small.judgement(r, mode: "m", frames: 0) }
        for i in 0..<40 {
            d.move(to: CGPoint(x: 200 + CGFloat(i), y: 500))
            d.tick()
        }
        let b: [String] = small.take()
        let fullLines: Int = b.filter { $0.contains("trace full") }.count
        try expect(small.full && fullLines == 1, "a bounded trace says once that it is full: \(b.suffix(3))")
        try expect(small.written <= 600 + 200, "the trace wrote \(small.written) bytes past a 600-byte cap")
    }
    check("pointerTraceRecordsCallbacksAndJudgements", traceRecordsCallbacksAndJudgements)

    // Finding 6: a replaced habitat is told the resting pointer again at the next step (no click, no read).
    func retellsAReplacedHabitat() throws {
        let d = PointerDesk(windows: [habitatWindow])
        d.move(to: desktopSpot)
        d.tick()
        d.ticks(for: 0.5)
        d.out.removeAll()
        let reads: Int = d.pointer.fetches
        d.pointer.retell()
        d.tick()
        try expect(d.out == [.moved(t1(100, 500))], "a new habitat was not told the resting pointer: \(d.out)")
        try expect(d.pointer.fetches == reads, "telling a new habitat read the list")
        d.ticks(for: 0.3)
        try expect(d.out.count == 1, "told more than once: \(d.out)")
    }
    check("pointerRetellsAReplacedHabitat", retellsAReplacedHabitat)

    // The Meadow through the contract: a resting pointer is landed on (a butterfly comes through dwell and spirals
    // in), the once-a-second refresh does not disturb it, a popup over it takes the pointer, and a replaced meadow is
    // told it again and landed on too.
    func meadowLandsOnRestingPointer() throws {
        let terrain: Terrain = Terrain.single(width: 1440, height: 900)
        let cell: CGSize = CGSize(width: 13, height: 19)
        var w = MeadowWorld(terrain: terrain, cell: cell, seed: 8)
        let d = PointerDesk(viewports: [Viewport(id: 1, rect: PointerDesk.screen1)], windows: [habitatWindow, finderDesktop])
        func step() {
            d.tick()
            for o in d.out {
                switch o {
                case .moved(let t): w.pointerMoved(x: Double(t.local.x), y: Double(t.local.y))
                case .left: w.pointerLeft()
                case .down(let t): w.pointerDown(x: Double(t.local.x), y: Double(t.local.y))
                }
            }
            d.out.removeAll()
            w.step(OceanClock.step)
        }
        func landed() -> Bool { w.flies.contains { $0.state == .cursor } }
        func stepUntilLanded(seconds: Double) -> Bool {
            for _ in 0..<Int(seconds * 60) {
                step()
                if landed() { return true }
            }
            return false
        }
        for _ in 0..<120 { step() }
        d.move(to: CGPoint(x: 720, y: 450))
        try expect(stepUntilLanded(seconds: 40), "nobody landed on the resting pointer in 40 s")
        for _ in 0..<Int(2.5 * 60) { step() }
        try expect(landed(), "the sitter left a resting pointer (the refresh disturbed it)")
        d.windows = [PointerWindow(number: 96, pid: 902, layer: 0, bounds: CGRect(x: 600, y: 350, width: 300, height: 200)),
                     habitatWindow, finderDesktop]
        for _ in 0..<Int((DesktopPointer.stillLife + 0.1) * 60) { step() }
        try expect(!w.pointerHas, "a popup over the resting pointer, the meadow still holds it")
        d.windows = [habitatWindow, finderDesktop]
        for _ in 0..<Int((DesktopPointer.stillLife + 0.1) * 60) { step() }
        try expect(w.pointerHas, "the popup closed, the meadow did not get the pointer back")
        w = MeadowWorld(terrain: terrain, cell: cell, seed: 9)
        d.pointer.retell()
        step()
        try expect(w.pointerHas, "a replaced meadow was not told the resting pointer")
        try expect(stepUntilLanded(seconds: 40), "nobody landed on the resting pointer in the replaced meadow in 40 s")
    }
    check("pointerMeadowLandsOnRestingPointer", meadowLandsOnRestingPointer)
}

// MARK: Cadence: one sample a step across displays, and the reads in each case the review named

private func pointerCadenceChecks() {
    // Two display links at 60 Hz, staggered by `offset`, with 1 ms of jitter each: at most one sample per step, and
    // no step starved. At 30 and 15 fps one callback samples once for the steps it advances.
    func oneSampleAStep() throws {
        let step: Double = OceanClock.step
        for offset in [0.0, 0.004, 0.0084, 0.012, 0.0165] {
            let d = PointerDesk(windows: [habitatWindow])
            var rng = SplitMix(seed: 11)
            var times: [Double] = []
            let start: Double = d.now
            for k in 0..<120 {
                let base: Double = start + Double(k) * step
                times.append(base + (rng.unit() - 0.5) * 0.002)
                times.append(base + offset + (rng.unit() - 0.5) * 0.002)
            }
            times.sort()
            let before: Int = d.pointer.samples
            for t in times {
                d.now = t
                d.out += d.pointer.tick(cursor: d.cursor, now: t)
            }
            let n: Int = d.pointer.samples - before
            let ms: String = String(format: "%.1f", offset * 1000)
            print("INFO pointer two displays staggered \(ms) ms: \(n) samples for 120 steps")
            try expect(n <= 121, "\(n) samples in 120 steps with two displays staggered \(ms) ms")
            try expect(n >= 118, "\(n) samples in 120 steps: steps starved")
        }
        for fps in [30.0, 15.0] {
            let d = PointerDesk(windows: [habitatWindow])
            let before: Int = d.pointer.samples
            let frames: Int = Int(2 * fps)
            for _ in 0..<frames { d.tick(1.0 / fps) }
            let n: Int = d.pointer.samples - before
            print("INFO pointer at \(Int(fps)) fps: \(n) samples in 2 s (one a callback; each advances \(Int(60 / fps)) steps)")
            try expect(n == frames, "\(n) samples for \(frames) callbacks at \(Int(fps)) fps")
        }
    }
    check("pointerOneSampleAStep", oneSampleAStep)

    // Reads in the cases the review named: two staggered displays with moves, idle over bare and over blocked desktop.
    func readsByCase() throws {
        let d = PointerDesk(windows: [foreignWindow, habitatWindow, finderDesktop])
        let before: Int = d.pointer.fetches
        var times: [(Double, Bool)] = []
        let start: Double = d.now
        for k in 0..<240 { times.append((start + Double(k) / 120.0, true)) }
        for k in 0..<120 {
            times.append((start + Double(k) * OceanClock.step + 0.0001, false))
            times.append((start + Double(k) * OceanClock.step + 0.0085, false))
        }
        times.sort { $0.0 < $1.0 }
        var i: Int = 0
        for (t, isMove) in times {
            d.now = t
            if isMove {
                let a: Double = Double(i) * 0.05
                i += 1
                d.move(to: CGPoint(x: CGFloat(720.0 + 600.0 * cos(a)), y: CGFloat(450.0 + 380.0 * sin(a))))
            } else {
                d.out += d.pointer.tick(cursor: d.cursor, now: t)
            }
        }
        let staggered: Int = d.pointer.fetches - before
        print("INFO pointer two staggered displays, 240 moves in 2 s: \(staggered) window-list reads")
        try expect(staggered <= 10, "\(staggered) reads for 2 s of moves on two displays")
        for (label, spot) in [("bare", desktopSpot), ("blocked", onForeign)] {
            let e = PointerDesk(windows: [foreignWindow, habitatWindow, finderDesktop])
            e.move(to: spot)
            e.tick()
            let b: Int = e.pointer.fetches
            e.ticks(for: 60)
            let r: Int = e.pointer.fetches - b
            print("INFO pointer idle a minute over \(label) desktop: \(r) window-list reads")
            try expect(r <= 61, "\(r) reads idle over \(label) desktop")
        }
    }
    check("pointerReadsByCase", readsByCase)

    // Not a pass/fail: the contract's own cost per step (pure; the host's AppKit callbacks are outside it).
    func stepCost() throws {
        let d = PointerDesk(windows: [foreignWindow, habitatWindow, finderDesktop])
        let n: Int = 20_000
        let start: Double = ProcessInfo.processInfo.systemUptime
        for k in 0..<n {
            d.move(to: CGPoint(x: 100 + CGFloat(k % 400), y: 500))
            d.tick()
            if d.out.count > 64 { d.out.removeAll(keepingCapacity: true) }
        }
        let us: Double = (ProcessInfo.processInfo.systemUptime - start) * 1e6 / Double(n)
        print("INFO pointer step with a move (judged, no read): " + String(format: "%.2f", us) + " µs")
    }
    check("pointerStepCost", stepCost)
}

// MARK: The host boundary: what PointerMonitor installs and how it reads an event, held to `PointerHost`

private func pointerHostChecks() {
    func hostInstallsBothMonitors() throws {
        try expect(PointerHost.monitors.contains(.global), "the host installs no global monitor")
        try expect(PointerHost.monitors.contains(.local), "the host installs no local monitor (own dispatch is lost)")
    }
    check("pointerHostInstallsBothMonitors", hostInstallsBothMonitors)

    // A real AppKit local monitor with the host's mask, and events dispatched in this process through `sendEvent`
    // (no window, nothing on screen): it sees exactly moves, drags and downs, hands each back unchanged, and the host's
    // reading gives their kinds.
    func localMonitorWithTheHostMask() throws {
        let app: NSApplication = NSApplication.shared
        var seen: [NSEvent] = []
        var same: Bool = true
        let mask = NSEvent.EventTypeMask(rawValue: PointerHost.mask)
        guard let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { e in
            seen.append(e)
            return e
        }) else { throw CheckFailure(detail: "no local monitor") }
        defer { NSEvent.removeMonitor(m) }
        let types: [NSEvent.EventType] = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown,
                                          .rightMouseDragged, .otherMouseDown, .mouseEntered]
        for t in types {
            let e: NSEvent?
            if t == .mouseEntered {
                e = NSEvent.enterExitEvent(with: t, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 1,
                                           windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)
            } else {
                e = NSEvent.mouseEvent(with: t, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 1,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            }
            guard let ev = e else { continue }
            let n: Int = seen.count
            app.sendEvent(ev)
            if seen.count > n, seen[n] !== ev { same = false }
        }
        let kinds: [DesktopPointer.Kind?] = seen.map { PointerHost.kind(eventType: UInt($0.type.rawValue)) }
        try expect(kinds == [.move, .drag, .down], "the local monitor saw \(seen.map { $0.type.rawValue }) as \(kinds)")
        try expect(same, "the monitor did not see the very event dispatched")
        for t in types where !(t == .mouseMoved || t == .leftMouseDragged || t == .leftMouseDown) {
            try expect(PointerHost.kind(eventType: UInt(t.rawValue)) == nil, "the host reads \(t.rawValue) as pointer input")
        }
    }
    check("pointerLocalMonitorWithTheHostMask", localMonitorWithTheHostMask)

    // The coordinate adapter on real events at AppKit points across an offset, negative-origin layout: the window
    // server's location and AppKit's flipped point agree, in global top-left points.
    func coordinateAdapter() throws {
        guard let primary = NSScreen.screens.first?.frame.height else {
            print("INFO pointer coordinate adapter: no screens, the event half skipped")
            return
        }
        let points: [NSPoint] = [NSPoint(x: 720, y: 450), NSPoint(x: -1500, y: 300), NSPoint(x: 2600, y: -400),
                                 NSPoint(x: 100, y: 1500)]
        for p in points {
            guard let e = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 1,
                                             windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            else { continue }
            let want: CGPoint = ScreenGeometry.flip(p, primaryHeight: primary)
            let screenPoint: CGPoint? = e.windowNumber == 0 ? e.locationInWindow : nil
            let viaCG: CGPoint? = PointerHost.location(cgLocation: e.cgEvent?.location, screenPoint: screenPoint,
                                                       primaryHeight: primary)
            let viaAppKit: CGPoint? = PointerHost.location(cgLocation: nil, screenPoint: screenPoint, primaryHeight: primary)
            for (label, got) in [("the window server's", viaCG), ("AppKit's", viaAppKit)] {
                guard let g = got else { throw CheckFailure(detail: "\(label) location missing at \(p)") }
                try expect(abs(g.x - want.x) < 0.5 && abs(g.y - want.y) < 0.5, "\(label) location of \(p): \(g), want \(want)")
            }
        }
        try expect(PointerHost.location(cgLocation: nil, screenPoint: nil, primaryHeight: primary) == nil,
                   "an event with no location was given one")
        let r: PointerReceiver = PointerHost.receiver(number: 7, appKitFrame: CGRect(x: -1920, y: 100, width: 800, height: 600),
                                                      ignoresMouse: false, primaryHeight: 900)
        try expect(r.frame == CGRect(x: -1920, y: 200, width: 800, height: 600) && r.takesMouse, "a receiver's frame: \(r)")
    }
    check("pointerCoordinateAdapter", coordinateAdapter)
}
