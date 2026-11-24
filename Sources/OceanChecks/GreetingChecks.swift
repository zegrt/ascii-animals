import Foundation
import OceanKit

/// t11 fix round 2 (trimmed): the greetings (the welcome, the Sharks Web welcome, the Meadow card) and their live
/// previews, the rules that need no screen. The app's side is in `--snapshot-whatsnew-probe`.
func greetingChecks() {
    let clear = WhatsNew.Moment(seeable: true, screens: 1, shown: false, habitat: .ocean, tried: false, welcomeUp: false,
                                canDraw: true)

    // 1. A greeting that never reached the person stays owed.
    func greetingCutShortStaysOwed() throws {
        var s = WhatsNew.Showings()
        s.shown()
        s.closed(.screens, reached: false)
        try expect(s.due && s.count == 0, "a display change before its content: still owed, at once (count \(s.count), due \(s.due))")
        s.shown()
        s.closed(.screens, reached: true)
        try expect(!s.due && s.count == 1, "a display change after its content: the showing counts (count \(s.count), due \(s.due))")
        var twice = WhatsNew.Showings(count: 1, ended: false, awake: WhatsNew.Showings.returnAfter)
        twice.shown()
        twice.closed(.screens, reached: false)
        try expect(twice.due && twice.count == 1, "a second showing cut short: owed again (count \(twice.count), due \(twice.due))")
        var esc = WhatsNew.Showings()
        esc.shown()
        esc.closed(.esc, reached: false)
        try expect(esc.finished, "Esc before its content: an answer, never again")
        // The welcome (and the Sharks Web welcome) waits for a seeable screen, like the card.
        let locked: WhatsNew.Moment = .welcome(seeable: false, screens: 1, canDraw: true, welcomeUp: false)
        try expect(WhatsNew.verdict(locked) == .wait, "welcome on a locked or sleeping screen: waits (\(WhatsNew.verdict(locked)))")
        let seen: WhatsNew.Moment = .welcome(seeable: true, screens: 1, canDraw: true, welcomeUp: false)
        try expect(WhatsNew.verdict(seen) == .show, "welcome on a screen that can be seen: shows (\(WhatsNew.verdict(seen)))")
    }
    check("greetingCutShortStaysOwed", greetingCutShortStaysOwed)

    // 3. Nothing ticks for a card nobody can see: no 1 s poll while it waits.
    func greetingWaitingCardHasNoPoll() throws {
        var locked: WhatsNew.Moment = clear
        locked.seeable = false
        var now: WhatsNew.Moment = locked
        let p = WhatsNew.Presenter(moment: { now }, open: { true }, mark: {})
        let first: WhatsNew.Step = p.look()
        let backstop: Double? = WhatsNew.Presenter.backstop
        try expect(first == .keepWaiting && p.nextLook == backstop && (backstop ?? 0) >= 60,
                   "locked: waits for a change, no 1 s look (\(first), next \(String(describing: p.nextLook)))")
        now = clear
        let second: WhatsNew.Step = p.look()
        try expect(second == .keepWaiting && p.nextLook == 1, "unlocked: one look a second later (\(second), next \(String(describing: p.nextLook)))")
        let third: WhatsNew.Step = p.look()
        try expect(third == .open && p.nextLook == nil, "clear for the second: opens, no more looks (\(third))")
    }
    check("greetingWaitingCardHasNoPoll", greetingWaitingCardHasNoPoll)

    // 4. Previews respect the person: Low Power and Reduce Motion as the desktop has them, at the desktop's rate.
    func greetingPreviewsFollowThePowerPolicy() throws {
        var rm = PowerInputs()
        rm.reduceMotion = true
        try expect(PowerPolicy.preview(rm) == .still, "Reduce Motion: the previews hold a still (\(PowerPolicy.preview(rm)))")
        try expect(WhatsNew.preview(rm) == .still, "Reduce Motion: the card holds a still (\(WhatsNew.preview(rm)))")
        var battery = PowerInputs()
        battery.onBattery = true
        try expect(PowerPolicy.preview(battery) == .live(fps: 15), "on battery: live at 15 fps (\(PowerPolicy.preview(battery)))")
        var sixty = PowerInputs()
        sixty.fpsSetting = 60
        try expect(PowerPolicy.preview(sixty) == .live(fps: 60), "60 fps chosen: 60 (\(PowerPolicy.preview(sixty)))")
        var low = PowerInputs()
        low.lowPowerMode = true
        try expect(PowerPolicy.preview(low) == .still, "Low Power Mode: a still (\(PowerPolicy.preview(low)))")
        var paused = PowerInputs()
        paused.userPaused = true
        paused.anyWindowVisible = false
        try expect(PowerPolicy.preview(paused) == .live(fps: 30), "a paused or covered desktop doesn't stop a preview being looked at")
        var locked = PowerInputs()
        locked.screenLocked = true
        try expect(PowerPolicy.preview(locked) == .paused, "locked: nothing drawn")
    }
    check("greetingPreviewsFollowThePowerPolicy", greetingPreviewsFollowThePowerPolicy)
}
