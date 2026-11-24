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
}
