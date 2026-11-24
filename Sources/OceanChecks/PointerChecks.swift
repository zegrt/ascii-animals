import CoreGraphics
import Foundation
import OceanKit

/// r1 right-size: the window the window server handed a pointer event to decides (the live trace, 2026-11-21).
/// The scene is what the trace saw: a notification banner up, and Notification Center's window over the whole
/// built-in screen (layer 21, alpha 1, 1800 x 1169).
func pointerChecks() {
    let screen: CGRect = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    let viewports: [Viewport] = [Viewport(id: 0, rect: screen), Viewport(id: 1, rect: CGRect(x: 1800, y: 0, width: 2560, height: 1440))]
    let desktopIconLayer: Int = Int(CGWindowLevelForKey(.desktopIconWindow))
    let desktopLayer: Int = Int(CGWindowLevelForKey(.desktopWindow))
    let finderDesktop: Int = 120, habitat: Int = 130, banner: Int = 900, safari: Int = 400, menuBar: Int = 25
    let safariRect: CGRect = CGRect(x: 200, y: 200, width: 600, height: 400)
    let listed: [ListedWindow] = [
        ListedWindow(number: menuBar, layer: 24),
        ListedWindow(number: banner, layer: 21),
        ListedWindow(number: safari, layer: 0),
        ListedWindow(number: habitat, layer: desktopLayer),
        ListedWindow(number: finderDesktop, layer: desktopIconLayer),
    ]
    // Today's rectangles (971a216's filter: layer 0 and up, not see-through): the menu bar, the banner, the window.
    let withBanner: [CGRect] = [CGRect(x: 0, y: 0, width: 1800, height: 24), screen, safariRect]
    let noBanner: [CGRect] = [CGRect(x: 0, y: 0, width: 1800, height: 24), safariRect]
    let bare: CGPoint = CGPoint(x: 1200, y: 900)
    let inSafari: CGPoint = CGPoint(x: 300, y: 300)

    func route(_ p: CGPoint, _ number: Int, _ verdicts: EventWindowVerdicts, _ rects: [CGRect]) -> PointerTarget? {
        let v: EventWindow = verdicts.verdict(for: number).0
        return PointerRouter.route(p, eventWindow: v, occluders: { rects }, viewports: viewports)
    }

    check("pointerBannerWindowDoesNotHideTheDesktop") {
        let verdicts = EventWindowVerdicts(read: { listed })
        let want: PointerTarget = PointerTarget(viewportID: 0, local: bare)
        let viaFinder: PointerTarget? = route(bare, finderDesktop, verdicts, withBanner)
        try expect(viaFinder == want, "event to the Finder's desktop with the banner up: \(String(describing: viaFinder))")
        let viaHabitat: PointerTarget? = route(bare, habitat, verdicts, withBanner)
        try expect(viaHabitat == want, "event to our habitat window with the banner up: \(String(describing: viaHabitat))")
        let v: (EventWindow, layer: Int?) = verdicts.verdict(for: finderDesktop)
        try expect(v.0 == .desktop && v.layer == desktopIconLayer, "the Finder's desktop: \(v)")
    }

    check("pointerAnyOtherEventWindowBlocks") {
        let verdicts = EventWindowVerdicts(read: { listed })
        let a: PointerTarget? = route(inSafari, safari, verdicts, withBanner)
        try expect(a == nil, "event to an app window: \(String(describing: a))")
        // The banner itself took the event (a click on the banner): blocked, wherever its rectangle says.
        let b: PointerTarget? = route(bare, banner, verdicts, [])
        try expect(b == nil, "event to the banner's window: \(String(describing: b))")
        try expect(verdicts.verdict(for: safari).0 == .window, "app window verdict")
    }

    check("pointerNoEventWindowFallsBackToRectangles") {
        let verdicts = EventWindowVerdicts(read: { listed })
        try expect(route(bare, 0, verdicts, noBanner) == PointerTarget(viewportID: 0, local: bare), "bare desktop, no banner")
        try expect(route(inSafari, 0, verdicts, noBanner) == nil, "inside a window's rectangle")
        try expect(route(bare, 0, verdicts, withBanner) == nil, "the banner's rectangle, as 971a216")
        try expect(route(CGPoint(x: 1900, y: 100), 0, verdicts, withBanner) == PointerTarget(viewportID: 1, local: CGPoint(x: 100, y: 100)),
                   "the other display")
        try expect(verdicts.reads == 0, "no window number needs no list read: \(verdicts.reads)")
    }

    check("pointerUnlistedEventWindowFallsBackToRectanglesOnce") {
        let verdicts = EventWindowVerdicts(read: { listed })
        let v: (EventWindow, layer: Int?) = verdicts.verdict(for: 777)
        try expect(v.0 == .unknown && v.layer == nil, "an unlisted window: \(v)")
        try expect(route(bare, 777, verdicts, noBanner) == PointerTarget(viewportID: 0, local: bare), "rectangles, bare")
        try expect(route(inSafari, 777, verdicts, noBanner) == nil, "rectangles, inside a window")
        try expect(verdicts.reads == 1, "one read for an unseen number, then the map: \(verdicts.reads)")
    }

    check("pointerDesktopMinuteReadsTheListOnce") {
        // A minute of moving over the desktop at 60 events a second, the banner up, handed to the Finder's desktop
        // and our habitat in turn. 971a216 read the list up to 20 times a second for this (up to 1,200 a minute).
        let verdicts = EventWindowVerdicts(read: { listed })
        var routed: Int = 0
        for i in 0..<3600 {
            let x: CGFloat = CGFloat(100 + (i % 1500))
            let p: CGPoint = CGPoint(x: x, y: 900)
            let number: Int = i % 2 == 0 ? finderDesktop : habitat
            if route(p, number, verdicts, withBanner) != nil { routed += 1 }
        }
        try expect(routed == 3600, "routed \(routed) of 3600")
        try expect(verdicts.reads == 1, "list reads in a minute over the desktop: \(verdicts.reads)")
        print("  a minute over the desktop (3600 moves): \(verdicts.reads) list read(s)")
    }

    check("pointerSpaceOrDisplayChangeForgetsVerdicts") {
        var current: [ListedWindow] = listed
        let verdicts = EventWindowVerdicts(read: { current })
        try expect(verdicts.verdict(for: finderDesktop).0 == .desktop, "before")
        // On the new Space the number belongs to an ordinary window (numbers are the window server's to reuse).
        current = [ListedWindow(number: finderDesktop, layer: 0)]
        try expect(verdicts.verdict(for: finderDesktop).0 == .desktop, "kept until a change: no read per move")
        verdicts.clear()
        try expect(verdicts.verdict(for: finderDesktop).0 == .window, "after the change, read again")
        try expect(verdicts.reads == 2, "reads \(verdicts.reads)")
    }

    check("pointerListedWindowParsesTheWindowList") {
        let raw: [[String: Any]] = [
            [kCGWindowNumber as String: NSNumber(value: banner), kCGWindowLayer as String: NSNumber(value: 21),
             kCGWindowAlpha as String: NSNumber(value: 1.0), kCGWindowOwnerName as String: "Notification Center"],
            [kCGWindowNumber as String: NSNumber(value: finderDesktop), kCGWindowLayer as String: NSNumber(value: desktopIconLayer)],
            [kCGWindowLayer as String: NSNumber(value: 0)],
        ]
        let parsed: [ListedWindow] = ListedWindow.parse(raw)
        let want: [ListedWindow] = [ListedWindow(number: banner, layer: 21), ListedWindow(number: finderDesktop, layer: desktopIconLayer)]
        try expect(parsed == want, "parsed \(parsed)")
    }

    // Right-size fix round 1 (review-r1b @ c74a9c6).

    /// Finding 1: the point comes from the same event as the window number, not from the cursor when the callback runs.
    func clickTakesTheEventsOwnPoint() throws {
        let verdicts = EventWindowVerdicts(read: { listed })
        // A click on bare desktop, banner up; by the time the callback runs the cursor is over the app window.
        let overWindow: PointerEventFacts = PointerEventFacts(window: finderDesktop, location: bare, cursorAtCallback: inSafari)
        let a: PointerTarget? = PointerRouter.route(overWindow, verdicts: verdicts, occluders: { withBanner }, viewports: viewports).target
        try expect(a == PointerTarget(viewportID: 0, local: bare), "desktop click, cursor over a window at callback: \(String(describing: a))")
        // A click near the right edge of the built-in screen; by the callback the cursor is on the other display.
        let edge: CGPoint = CGPoint(x: 1700, y: 900)
        let crossed: PointerEventFacts = PointerEventFacts(window: finderDesktop, location: edge, cursorAtCallback: CGPoint(x: 1900, y: 100))
        let b: PointerTarget? = PointerRouter.route(crossed, verdicts: verdicts, occluders: { withBanner }, viewports: viewports).target
        try expect(b == PointerTarget(viewportID: 0, local: edge), "desktop click, cursor on the other display at callback: \(String(describing: b))")
    }
    check("pointerClickTakesTheEventsOwnPoint", clickTakesTheEventsOwnPoint)

    func downWithNoEventPointDoesNothing() throws {
        let verdicts = EventWindowVerdicts(read: { listed })
        let noPoint: PointerEventFacts = PointerEventFacts(window: finderDesktop, location: nil, cursorAtCallback: bare)
        let a: PointerTarget? = PointerRouter.route(noPoint, verdicts: verdicts, occluders: { noBanner }, viewports: viewports).target
        try expect(a == nil, "a down with no point of its own, cursor on bare desktop: \(String(describing: a))")
        let noNumber: PointerEventFacts = PointerEventFacts(window: 0, location: nil, cursorAtCallback: bare)
        let b: PointerTarget? = PointerRouter.route(noNumber, verdicts: verdicts, occluders: { noBanner }, viewports: viewports).target
        try expect(b == nil, "no point and no window number: \(String(describing: b))")
        try expect(verdicts.reads == 0, "an event with no point reads no list: \(verdicts.reads)")
    }
    check("pointerDownWithNoEventPointDoesNothing", downWithNoEventPointDoesNothing)

    /// Finding 2 (the miss part): a window number not in the list is not remembered, so a desktop window that shows up
    /// in the list late is found on a later event; the list is read for misses at most about once a second.
    func missedDesktopWindowFoundLater() throws {
        let late: Int = 140
        var current: [ListedWindow] = listed
        var t: TimeInterval = 100
        let verdicts = EventWindowVerdicts(read: { current }, now: { t })
        let want: PointerTarget = PointerTarget(viewportID: 0, local: bare)
        let first: PointerTarget? = route(bare, late, verdicts, withBanner)
        try expect(first == nil && verdicts.reads == 1, "not yet listed: rectangles (the banner's), one read: \(String(describing: first)), \(verdicts.reads)")
        current = listed + [ListedWindow(number: late, layer: desktopLayer)]
        t = 100.5
        let soon: PointerTarget? = route(bare, late, verdicts, withBanner)
        try expect(soon == nil && verdicts.reads == 1, "half a second later: no read on the move path: \(String(describing: soon)), \(verdicts.reads)")
        t = 101.1
        let later: PointerTarget? = route(bare, late, verdicts, withBanner)
        try expect(later == want, "a second later, now listed at the desktop layer: \(String(describing: later))")
        try expect(verdicts.reads == 2, "reads \(verdicts.reads)")
        t = 101.2
        let after: PointerTarget? = route(bare, late, verdicts, withBanner)
        try expect(after == want && verdicts.reads == 2, "then remembered: \(String(describing: after)), \(verdicts.reads)")
    }
    check("pointerMissedDesktopWindowFoundLater", missedDesktopWindowFoundLater)

    func missesReadAboutOnceASecond() throws {
        // A minute of moves at 60 a second, each handed to a window number the list never has.
        var t: TimeInterval = 100
        let verdicts = EventWindowVerdicts(read: { listed }, now: { t })
        for i in 0..<3600 {
            t = 100 + Double(i) / 60
            let v: EventWindow = verdicts.verdict(for: 777).0
            try expect(v == .unknown, "move \(i): \(v)")
        }
        try expect(verdicts.reads >= 1 && verdicts.reads <= 61, "list reads in a minute of misses: \(verdicts.reads)")
        print("  a minute of misses (3600 moves): \(verdicts.reads) list read(s)")
    }
    check("pointerMissesReadAboutOnceASecond", missesReadAboutOnceASecond)

    // Right-size fix round 2 (review-r1b-r1 @ 63f40c0, "Regression").

    /// The one-second wait after a miss belongs to the missed number: an event handed to a different number that the
    /// list now has is looked up as before, so a desktop click is not lost and the fish does not react through a window.
    func missWaitsOnlyForTheMissedNumber() throws {
        let newDesktop: Int = 150, newWindow: Int = 160
        var current: [ListedWindow] = listed
        var t: TimeInterval = 100
        let verdicts = EventWindowVerdicts(read: { current }, now: { t })
        let miss: EventWindow = verdicts.verdict(for: 777).0
        try expect(miss == .unknown && verdicts.reads == 1, "the miss: \(miss), reads \(verdicts.reads)")
        current = listed + [ListedWindow(number: newDesktop, layer: desktopLayer), ListedWindow(number: newWindow, layer: 0)]
        t = 100.1
        // A desktop window listed since the miss, banner up: the fish, not the banner's rectangle.
        let desk: PointerTarget? = route(bare, newDesktop, verdicts, withBanner)
        // A normal window listed since the miss, its rectangle not yet in the last move's snapshot: blocked.
        t = 100.2
        let win: PointerTarget? = route(bare, newWindow, verdicts, noBanner)
        let deskOK: Bool = desk == PointerTarget(viewportID: 0, local: bare)
        let winOK: Bool = win == nil
        try expect(deskOK && winOK,
                   "within the second, a newly listed desktop number: \(String(describing: desk)); a newly listed normal window: \(String(describing: win))")
        try expect(verdicts.verdict(for: newWindow).0 == .window, "its verdict")
        // The missed number itself still waits out its second, then is looked up again.
        let reads: Int = verdicts.reads
        t = 100.5
        try expect(verdicts.verdict(for: 777).0 == .unknown && verdicts.reads == reads, "the missed number waits: reads \(verdicts.reads)")
        t = 101.1
        _ = verdicts.verdict(for: 777)
        try expect(verdicts.reads == reads + 1, "a second after its miss, read again: \(verdicts.reads)")
    }
    check("pointerMissWaitsOnlyForTheMissedNumber", missWaitsOnlyForTheMissedNumber)

    func spaceOrDisplayChangeDropsMisses() throws {
        var current: [ListedWindow] = listed
        var t: TimeInterval = 100
        let verdicts = EventWindowVerdicts(read: { current }, now: { t })
        _ = verdicts.verdict(for: 777)
        current = listed + [ListedWindow(number: 777, layer: desktopLayer)]
        verdicts.clear()
        t = 100.1
        let v: EventWindow = verdicts.verdict(for: 777).0
        try expect(v == .desktop && verdicts.reads == 2, "after a change, the missed number is looked up at once: \(v), reads \(verdicts.reads)")
    }
    check("pointerSpaceOrDisplayChangeDropsMisses", spaceOrDisplayChangeDropsMisses)

    func missesOnManyNumbersStaySmall() throws {
        // A minute of moves at 60 a second, each handed to one of 4 numbers the list never has, in turn.
        var t: TimeInterval = 100
        let verdicts = EventWindowVerdicts(read: { listed }, now: { t })
        var most: Int = 0
        for i in 0..<3600 {
            t = 100 + Double(i) / 60
            let number: Int = 770 + (i % 4)
            _ = verdicts.verdict(for: number)
            most = max(most, verdicts.missCount)
        }
        try expect(verdicts.reads <= 4 * 61, "list reads in a minute of misses on 4 numbers: \(verdicts.reads)")
        try expect(most <= 4, "misses remembered at once: \(most)")
        t = 200
        _ = verdicts.verdict(for: 999)
        try expect(verdicts.missCount == 1, "misses older than a second are dropped: \(verdicts.missCount)")
        print("  a minute of misses on 4 numbers (3600 moves): \(verdicts.reads) list read(s)")
    }
    check("pointerMissesOnManyNumbersStaySmall", missesOnManyNumbersStaySmall)
}
