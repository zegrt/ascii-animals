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
        var t: Double = 0
        let p = WhatsNew.Presenter(moment: { now }, open: { true }, mark: {}, clock: { t })
        let first: WhatsNew.Step = p.look()
        let backstop: Double? = WhatsNew.Presenter.backstop
        try expect(first == .keepWaiting && p.nextLook == backstop && (backstop ?? 0) >= 60,
                   "locked: waits for a change, no 1 s look (\(first), next \(String(describing: p.nextLook)))")
        t = 40
        now = clear
        let second: WhatsNew.Step = p.look()
        try expect(second == .keepWaiting && p.nextLook == 1, "unlocked: one look a second later (\(second), next \(String(describing: p.nextLook)))")
        // Fix round 3: a second wake notification at the same moment is not a clear second (round 2 expected .open).
        let third: WhatsNew.Step = p.look()
        try expect(third == .keepWaiting && p.nextLook == 1, "a second clear look at the same moment: still waiting (\(third))")
        t = 41
        let fourth: WhatsNew.Step = p.look()
        try expect(fourth == .open && p.nextLook == nil, "clear for the second: opens, no more looks (\(fourth))")
    }
    check("greetingWaitingCardHasNoPoll", greetingWaitingCardHasNoPoll)

    // Fix round 3, 3: only a full second of clear screen opens a greeting that waited; a lock cancels the pending
    // confirmation.
    func greetingWaitsAFullClearSecond() throws {
        var locked: WhatsNew.Moment = clear
        locked.seeable = false
        var now: WhatsNew.Moment = locked
        var t: Double = 0
        var opened: Int = 0
        let p = WhatsNew.Presenter(moment: { now }, open: { opened += 1; return true }, mark: {}, clock: { t })
        _ = p.look()
        t = 100
        now = clear
        let wake: WhatsNew.Step = p.look()
        let burst: WhatsNew.Step = p.look()
        try expect(wake == .keepWaiting && burst == .keepWaiting && opened == 0,
                   "two clear events at the same moment: still waiting (\(wake), \(burst), opened \(opened))")
        t = 100.4
        let early: WhatsNew.Step = p.look()
        let left: Double = p.nextLook ?? -1
        try expect(early == .keepWaiting && abs(left - 0.6) < 1e-9,
                   "a third event 0.4 s in: still waiting, the confirmation still due at the full second (next \(left))")
        t = 100.5
        now = locked
        let relock: WhatsNew.Step = p.look()
        try expect(relock == .keepWaiting && p.nextLook == WhatsNew.Presenter.backstop,
                   "a lock 0.5 s in cancels the pending confirmation (next \(String(describing: p.nextLook)))")
        t = 101
        now = clear
        let again: WhatsNew.Step = p.look()
        t = 101.5
        let half: WhatsNew.Step = p.look()
        try expect(again == .keepWaiting && half == .keepWaiting && opened == 0,
                   "clear again: half a second is not enough (\(again), \(half), opened \(opened))")
        t = 102
        let full: WhatsNew.Step = p.look()
        try expect(full == .open && opened == 1, "a full clear second: opens, once (\(full), opened \(opened))")
    }
    check("greetingWaitsAFullClearSecond", greetingWaitsAFullClearSecond)

    // Fix round 3, 4: the tour finishes in every power state without asking for an effect the habitat can't show.
    func greetingTourShowsNoInvisibleStep() throws {
        var lowPower = PowerInputs()
        lowPower.lowPowerMode = true
        var reduce = PowerInputs()
        reduce.reduceMotion = true
        var both: PowerInputs = reduce
        both.lowPowerMode = true
        var battery = PowerInputs()
        battery.onBattery = true
        var hot = PowerInputs()
        hot.thermal = .critical
        let states: [(String, PowerInputs)] = [("plugged in", PowerInputs()), ("on battery", battery),
                                               ("Low Power Mode", lowPower), ("Reduce Motion", reduce),
                                               ("Reduce Motion and Low Power", both), ("too hot", hot)]
        for (name, i) in states {
            var walked: [Tour.Step] = [.habitat]
            while let n = Tour.next(after: walked[walked.count - 1], i) { walked.append(n) }
            let mode: RunMode = Tour.mode(i)
            let moves: Bool = mode != .still
            let invisible: [Tour.Step] = walked.filter { (s: Tour.Step) -> Bool in s.asksForEffect && !moves }
            let raw: [Int] = walked.map { (s: Tour.Step) -> Int in s.rawValue }
            try expect(walked.last == .dive && invisible.isEmpty,
                       "\(name): the tour \(raw) under \(mode) asks for no effect it can't show and ends at the dive")
        }
        try expect(Tour.mode(lowPower) == .live(fps: 15) && Tour.steps(lowPower) == Tour.Step.allCases,
                   "Low Power Mode alone: the tour stays live at 15 fps, every step (\(Tour.mode(lowPower)))")
        let reduced: [Tour.Step] = Tour.steps(reduce)
        try expect(Tour.mode(reduce) == .still && !reduced.contains(.pointer) && !reduced.contains(.splash),
                   "Reduce Motion: a still, no pointer or splash step (\(reduced.map { (s: Tour.Step) -> Int in s.rawValue }))")
        try expect(Tour.mode(PowerInputs()) == .live(fps: 30) && Tour.steps(PowerInputs()) == Tour.Step.allCases,
                   "plugged in: live at 30, every step")
    }
    check("greetingTourShowsNoInvisibleStep", greetingTourShowsNoInvisibleStep)

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
