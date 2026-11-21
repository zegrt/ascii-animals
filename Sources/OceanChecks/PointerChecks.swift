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

    /// An event at `p` (its own location), dispatched `d`; the cursor is at `cursorAtCallback` (default `p`) by the
    /// time a callback runs, and stays there.
    func deliver(_ kind: DesktopPointer.Kind, at p: CGPoint, via d: PointerDispatch, cursorAtCallback: CGPoint? = nil,
                 hit: Int? = nil) {
        let c: CGPoint = cursorAtCallback ?? p
        cursor = c
        guard let src = PointerDelivery.source(for: d, installed: DesktopPointer.sources) else { return }
        let e = DesktopPointer.Event(kind: kind, source: src, location: p, cursor: c, hitWindow: hit, time: now)
        out += pointer.receive(e)
    }

    func move(to p: CGPoint, via d: PointerDispatch = .foreign, hit: Int? = nil) {
        deliver(button ? .drag : .move, at: p, via: d, hit: hit)
    }

    func click(at p: CGPoint, via d: PointerDispatch = .foreign, cursorAtCallback: CGPoint? = nil, hit: Int? = nil) {
        deliver(.down, at: p, via: d, cursorAtCallback: cursorAtCallback, hit: hit)
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
private let habitatWindow: PointerWindow = PointerWindow(number: 10, pid: 42, own: true, wallpaper: true,
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

    // A display-sized foreign surface whose pixels are clear: the window server hands the click to the desktop.
    func clickThroughSurface() throws {
        let overlay = PointerWindow(number: 77, pid: 600, layer: 25, alpha: 1, bounds: PointerDesk.screen1)
        let d = PointerDesk(windows: [overlay, habitatWindow, finderDesktop])
        d.click(at: desktopSpot, hit: finderDesktop.number)
        try expect(d.downs == [t1(100, 500)], "the window server sent the click to the desktop, a rectangle refused it: \(d.out)")
        d.ticks(for: 3)
        try expect(d.target == t1(100, 500), "the resting pointer lost the desktop the window server named: \(d.out)")
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
}

// MARK: Budget: window-list reads (audit a2's hot path)

/// `n` foreign moves at 120 Hz over screen 1 (around the windows), a tick each 1/60 s; the window-list reads.
private func burstReads(seconds: Double) -> (moves: Int, reads: Int, viewportReads: Int) {
    let w2 = PointerWindow(number: 61, pid: 501, layer: 0, bounds: CGRect(x: 1000, y: 100, width: 300, height: 200))
    let menuBar = PointerWindow(number: 3, pid: 100, layer: 24, bounds: CGRect(x: 0, y: 0, width: 1440, height: 24))
    let d = PointerDesk(windows: [menuBar, foreignWindow, w2, habitatWindow, finderDesktop])
    let moves: Int = Int(seconds * 120)
    for i in 0..<moves {
        let a: Double = Double(i) * 0.05
        let x: CGFloat = CGFloat(720.0 + 600.0 * cos(a))
        let y: CGFloat = CGFloat(450.0 + 380.0 * sin(a))
        d.move(to: CGPoint(x: x, y: y))
        if i % 2 == 1 { d.tick() } else { d.now += 1.0 / 240.0 }
    }
    return (moves, d.pointer.fetches, d.pointer.viewportReads)
}

private func pointerBudgetChecks() {
    func burstBudget() throws {
        let r = burstReads(seconds: 2)
        print("INFO pointer burst: \(r.moves) moves in 2 s, \(r.reads) window-list reads, \(r.viewportReads) screen reads")
        let bound: Int = Int(2.0 / DesktopPointer.moveLife) + 2
        try expect(r.reads <= 10, "\(r.reads) window-list reads for 2 s of moves (bound 10, \(bound) from moveLife)")
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
        let parsed: [PointerWindow] = PointerWindow.parse(canned, ownPID: 42, wallpaper: [12])
        try expect(parsed.count == 2, "an entry without bounds kept: \(parsed)")
        try expect(parsed[0].wallpaper && parsed[0].own && parsed[0].isDesktop, "the habitat window: \(parsed[0])")
        try expect(parsed[1].own && !parsed[1].wallpaper && parsed[1].bounds == CGRect(x: 10, y: 20, width: 300, height: 200),
                   "an own window: \(parsed[1])")
        let n: Int = 50
        let start: Double = ProcessInfo.processInfo.systemUptime
        var count: Int = 0
        for _ in 0..<n {
            let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            count = PointerWindow.parse(raw, ownPID: getpid(), wallpaper: []).count
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
