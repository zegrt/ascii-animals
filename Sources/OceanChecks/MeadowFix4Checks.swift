import CoreGraphics
import Foundation
import OceanKit

// m8's re-check (fix round 4): the hosted Meadow steps without allocating, full or waiting for room (R3-1); a display
// change while paused owes the held frame (R3-2); the allocation counter counts only the calling thread.

private func screen(_ id: Int, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> ScreenInfo {
    ScreenInfo(id: id, frame: CGRect(x: x, y: y, width: w, height: h), scale: 2)
}

private func meadowSettings() -> Settings {
    var s = Settings.defaults
    s.habitat = .meadow
    s.meadowCount = 7
    return s.sanitized()
}

/// The scenes as `OceanDirector` keeps them, stepped the app's way: each display link's timestamp through
/// `HabitatScene.advance` (one step per 1/60 s).
private final class Host {
    let desk = SceneDesk()
    var scenes: [HabitatScene] = []
    let settings: Settings = meadowSettings()
    private var seed: UInt64 = 60
    private var frame = 0

    init(_ screens: [ScreenInfo], shared: Bool) { arrange(screens, shared: shared) }

    func arrange(_ screens: [ScreenInfo], shared: Bool) {
        scenes = HabitatScene.arrange(scenes, plans: SceneLayout.plan(screens, shared: shared), settings: settings,
                                      fresh: false, desk: desk, seeds: { [unowned self] in
                                          self.seed += 1
                                          return self.seed
                                      })
    }

    /// `n` display frames on the scenes in `only` (every scene when nil).
    func frames(_ n: Int, only: Int? = nil) {
        for _ in 0..<n {
            frame += 1
            let t: Double = 1000 + Double(frame) / 60
            for (i, s) in scenes.enumerated() where only == nil || only == i {
                s.advance(to: t, speed: settings.speed)
            }
        }
    }

    var drawn: [Int] { scenes.map { (s: HabitatScene) -> Int in (s.sim as? MeadowSim)?.world.flies.count ?? -1 } }
    var staying: [Int] {
        scenes.map { (s: HabitatScene) -> Int in
            (s.sim as? MeadowSim)?.world.flies.filter { !$0.leaving }.count ?? -1
        }
    }
}

/// R3-1: after warm-up, a hosted desk steps without allocating, one scene across it and one per screen, and with a
/// scene whose newcomers wait for room while another screen's leavers are still drawn (that screen's link paused,
/// as a covered screen's is, so the wait lasts).
private func meadowHostedStepsAllocateNothing() throws {
    let monitor: ScreenInfo = screen(1, 0, 0, 2560, 1440)
    let laptop: ScreenInfo = screen(2, 2560, 0, 1800, 1169)
    var failures: [String] = []
    for shared in [true, false] {
        let h = Host([monitor, laptop], shared: shared)
        h.frames(600)
        let what: String = shared ? "one scene across the desk" : "a scene per screen"
        _ = allocationSites()
        guard let n = allocations({ h.frames(600) }) else {
            print("  (allocator not watchable here: skipped the count)")
            return
        }
        if n > 0 {
            print("  where (\(what)): \(allocationSites())")
            failures.append("\(what): \(n) allocations in 600 warmed frames (drawn \(h.drawn))")
        }
    }
    // Swap the two screens' sizes: the first scene's share drops from 8 to 4 (its 4 spares leave, still drawn), the
    // second's rises to 8 and its 4 newcomers wait for room.
    let h = Host([monitor, laptop], shared: false)
    h.frames(600)
    try expect(h.drawn == [8, 4], "before the swap: \(h.drawn)")
    h.arrange([screen(1, 0, 0, 1800, 1169), screen(2, 1800, 0, 2560, 1440)], shared: false)
    h.frames(120, only: 1)
    _ = allocationSites()
    guard let n = allocations({ h.frames(600, only: 1) }) else { return }
    if n > 0 { print("  where (waiting for room): \(allocationSites())") }
    try expect(h.drawn == [8, 4] && h.staying == [4, 4],
               "the wait did not last: drawn \(h.drawn), staying \(h.staying)")
    if n > 0 { failures.append("waiting for room: \(n) allocations in 600 warmed frames") }
    try expect(failures.isEmpty, failures.joined(separator: "; "))
}

/// R3-2: a display attached, detached or resized while the user has paused draws one held frame on every screen (so
/// the paused desktop shows the settled line-up); a covered or locked desktop draws nothing; a Low Power or Reduce
/// Motion still draws one; live runs on.
private func heldFrameAfterDisplayChange() throws {
    let live: RunMode = .live(fps: 30)
    let cases: [(RunMode, Bool, Bool, Bool, String)] = [
        // mode, user paused, owes a still, runs
        (.paused, true, true, true, "paused by the user"),
        (.paused, false, false, false, "covered or locked"),
        (.still, false, true, true, "a Low Power or Reduce Motion still"),
        (live, false, false, true, "live"),
    ]
    for (mode, userPaused, owes, runs, what) in cases {
        // A screen kept from before (its held frame already drawn) and a new one: both start owing nothing.
        let pending: Bool = HeldFrame.stillPending(afterDisplayChange: mode, was: false, userPaused: userPaused)
        let link: (stillPending: Bool, running: Bool) = HeldFrame.link(mode, stillPending: pending, userPaused: userPaused)
        try expect(link.stillPending == owes && link.running == runs,
                   "\(what): pending \(link.stillPending), running \(link.running); want \(owes), \(runs)")
    }
    // A still left over from before the change stays owed while paused by the user, and is dropped when covered.
    let kept: Bool = HeldFrame.stillPending(afterDisplayChange: .paused, was: true, userPaused: false)
    let covered: (stillPending: Bool, running: Bool) = HeldFrame.link(.paused, stillPending: kept, userPaused: false)
    try expect(!covered.stillPending && !covered.running, "covered kept a still: \(covered)")
}

/// The allocation counter counts the calling thread only: another thread allocating all through the count adds
/// nothing (the "where" report still tallies it).
private func allocationCounterCountsThisThread() throws {
    let stop = UnsafeMutablePointer<Int>.allocate(capacity: 2)
    stop.initialize(repeating: 0, count: 2)
    defer { stop.deallocate() }
    let done = DispatchSemaphore(value: 0)
    let churn = Thread {
        while stop[0] == 0 {
            churnOnce()
            stop[1] += 1
            usleep(50)
        }
        done.signal()
    }
    churn.start()
    while stop[1] < 10 { usleep(1000) }
    _ = allocationSites()
    let n = allocations({ usleep(100_000) })
    let elsewhere: Int = allocationsElsewhere()
    let sites: String = allocationSites()
    stop[0] = 1
    done.wait()
    guard let n else { print("  (allocator not watchable here: skipped the count)"); return }
    try expect(elsewhere > 0, "the other thread allocated nothing during the count (\(sites))")
    try expect(n == 0, "\(n) allocations counted from another thread (\(sites))")
}

nonisolated(unsafe) private var churnSink: UnsafeMutableRawPointer?
@inline(never) private func churnOnce() {
    let p = UnsafeMutableRawPointer.allocate(byteCount: 96, alignment: 16)
    churnSink = p
    p.deallocate()
}

func meadowFix4Checks() {
    check("meadowHostedStepsAllocateNothing", meadowHostedStepsAllocateNothing)
    check("heldFrameAfterDisplayChange", heldFrameAfterDisplayChange)
    check("allocationCounterCountsThisThread", allocationCounterCountsThisThread)
}
