import CoreGraphics
import Foundation
import OceanKit

// The desk as the app's scene host lays it out (`HabitatScene.arrange`, which `OceanDirector.screensChanged` calls):
// displays attached, detached and resized, counts and line-ups changed live and while paused, with the Meadow's
// "never more than 12 across all screens" held on every step, and the Ocean and the Web left alone by changes that
// are not theirs (m8's review, findings 1–6 and "What is missing").

/// A desk laid out by the app's scene host, with fixed seeds (1, 2, … from `seed`).
final class HostedDesk {
    let desk = SceneDesk()
    private(set) var scenes: [HabitatScene] = []
    private var seed: UInt64
    private(set) var settings: Settings

    init(_ screens: [ScreenInfo], shared: Bool, _ s: Settings, seed: UInt64) {
        self.seed = seed - 1
        settings = s.sanitized()
        arrange(screens, shared: shared)
    }

    /// The screens changed (`OceanDirector.screensChanged`).
    func arrange(_ screens: [ScreenInfo], shared: Bool, fresh: Bool = false) {
        scenes = HabitatScene.arrange(scenes, plans: SceneLayout.plan(screens, shared: shared), settings: settings,
                                      fresh: fresh, desk: desk, seeds: { [unowned self] in
                                          self.seed += 1
                                          return self.seed
                                      })
    }

    /// A change made in place (`OceanDirector.settingsChanged`, no rebuild).
    func update(_ s: Settings) {
        settings = s.sanitized()
        for sc in scenes { sc.sim.update(settings: settings) }
    }

    /// One held frame on every screen (a pause): each screen's tick settles its scene (`OceanDirector.tick`).
    func held() { for sc in scenes { sc.sim.settle() } }

    func step() { for sc in scenes { sc.sim.step(OceanClock.step) } }

    var meadows: [MeadowSim] { scenes.compactMap { $0.sim as? MeadowSim } }
    /// Each scene's butterflies drawn now, the ones leaving included: exactly the list the painter draws.
    var drawn: [Int] { meadows.map { (m: MeadowSim) -> Int in m.world.flies.count } }
    /// Each scene's butterflies staying (not leaving).
    var staying: [Int] { meadows.map { (m: MeadowSim) -> Int in m.world.flies.filter { !$0.leaving }.count } }
}

private func screen(_ id: Int, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> ScreenInfo {
    ScreenInfo(id: id, frame: CGRect(x: x, y: y, width: w, height: h), scale: 2)
}

private let monitor: ScreenInfo = screen(1, 0, 0, 2560, 1440)
private let laptop: ScreenInfo = screen(2, 375, 1440, 1800, 1169)
private let third: ScreenInfo = screen(3, 2560, 0, 1920, 1080)

private func meadowSettings(_ count: Int = 7) -> Settings {
    var s = Settings.defaults
    s.habitat = .meadow
    s.meadowCount = count
    return s
}

/// Steps `d` for up to `seconds`, failing the moment the desk draws more than 12; returns once every scene stays at
/// and draws exactly `want` (nobody still leaving or coming), else fails.
private func settle(_ d: HostedDesk, to want: [Int], within seconds: Double, _ what: String) throws {
    for i in 0..<Int(seconds * 60) {
        let drawn: [Int] = d.drawn
        try expect(drawn.reduce(0, +) <= 12, "\(what): \(drawn) drawn at step \(i)")
        let arrived: Bool = d.staying == want && drawn == want
        let calm: Bool = d.meadows.allSatisfy { (m: MeadowSim) -> Bool in
            m.world.flies.allSatisfy { !$0.leaving && $0.wait <= 0 && !$0.entering }
        }
        if arrived && calm { return }
        d.step()
    }
    throw CheckFailure(detail: "\(what): staying \(d.staying), drawn \(d.drawn) after \(seconds) s, want \(want)")
}

private func shares(_ count: Int, _ screens: [ScreenInfo]) -> [Int] {
    MeadowTuning.areaCountShares(count, screens: screens.map { (s: ScreenInfo) -> CGSize in s.frame.size })
}

/// Attach, detach, resize, a count change and a line-up change, live: never more than 12 drawn on the desk on any
/// step (the ones leaving count until they are out of sight), and each change settles at the desk's shares.
private func meadowDeskTransitionsHoldTwelve() throws {
    let d = HostedDesk([monitor], shared: false, meadowSettings(), seed: 11)
    try settle(d, to: [12], within: 5, "the monitor alone")
    for _ in 0..<(5 * 60) { d.step() }
    // Attach the laptop: the monitor's share drops from 12 to 8; the laptop's 4 wait for room.
    d.arrange([monitor, laptop], shared: false)
    try expect(d.drawn.reduce(0, +) <= 12, "attach: \(d.drawn)")
    for _ in 0..<30 {
        d.step()
        try expect(d.drawn.reduce(0, +) <= 12, "attach: \(d.drawn)")
    }
    // A third display before the departures are done: a fresh scene starts within the room left.
    d.arrange([monitor, laptop, third], shared: false)
    try expect(d.drawn.reduce(0, +) <= 12, "a third display mid-change: \(d.drawn)")
    try settle(d, to: shares(7, [monitor, laptop, third]), within: 120, "three displays")
    // Detach two: the monitor alone takes the whole 12 again.
    d.arrange([monitor], shared: false)
    try settle(d, to: [12], within: 120, "detached")
    // Attach, then resize the monitor (2560 × 1440 to 1920 × 1080): the shares follow the areas.
    d.arrange([monitor, laptop], shared: false)
    try settle(d, to: shares(7, [monitor, laptop]), within: 120, "attached again")
    let small: ScreenInfo = screen(1, 0, 0, 1920, 1080)
    let smallLaptop: ScreenInfo = screen(2, 0, 1080, 1800, 1169)
    d.arrange([small, smallLaptop], shared: false)
    try settle(d, to: shares(7, [small, smallLaptop]), within: 120, "resized")
    // Count changes live: up to 12, down to 3.
    for n in [12, 3] {
        d.update(meadowSettings(n))
        try settle(d, to: shares(n, [small, smallLaptop]), within: 120, "count \(n)")
    }
    // One scene across the desk: Mixed to Blue Morphos (5 on a laptop; 9 + 5 by area, so 12), the old ones leaving
    // while the morphos come: never more than 12 (the review saw 21).
    let one = HostedDesk([monitor, laptop], shared: true, meadowSettings(), seed: 21)
    try settle(one, to: [12], within: 5, "one scene")
    for _ in 0..<(3 * 60) { one.step() }
    var morphos = meadowSettings(5)
    morphos.meadowButterflies = [.morpho]
    one.update(morphos)
    try settle(one, to: [12], within: 120, "Blue Morphos across the desk")
    let kinds: [ButterflyKind] = one.meadows[0].world.flies.map(\.kind)
    try expect(kinds.allSatisfy { $0 == .morpho }, "Blue Morphos across the desk: \(kinds)")
}

/// A held frame (paused, Low Power, Reduce Motion) finishes a change at once across the desk: a line-up change and
/// a display attached while paused show the new state on the next held frame, never more than 12.
private func meadowDeskHeldFrameResolves() throws {
    let d = HostedDesk([monitor, laptop], shared: false, meadowSettings(), seed: 31)
    try settle(d, to: [8, 4], within: 5, "fresh")
    for _ in 0..<(3 * 60) { d.step() }
    var morphos = meadowSettings(5)
    morphos.meadowButterflies = [.morpho]
    d.update(morphos)
    d.held()
    let want: [Int] = shares(5, [monitor, laptop])
    let kinds: [ButterflyKind] = d.meadows.flatMap { (m: MeadowSim) -> [ButterflyKind] in m.world.flies.map(\.kind) }
    try expect(d.drawn == want && d.staying == want && kinds.allSatisfy { $0 == .morpho },
               "a paused line-up change: drawn \(d.drawn), staying \(d.staying), want \(want), \(kinds)")
    // A held frame with nothing on its way changes nothing.
    let before: [Double] = d.meadows.flatMap { (m: MeadowSim) -> [Double] in m.world.flies.flatMap { [$0.x, $0.y] } }
    d.held()
    let after: [Double] = d.meadows.flatMap { (m: MeadowSim) -> [Double] in m.world.flies.flatMap { [$0.x, $0.y] } }
    try expect(before == after, "a held frame moved butterflies with nothing to finish")
    // A display attached while paused.
    let p = HostedDesk([monitor], shared: false, meadowSettings(), seed: 41)
    for _ in 0..<(3 * 60) { p.step() }
    p.arrange([monitor, laptop], shared: false)
    p.held()
    try expect(p.drawn == [8, 4] && p.staying == [8, 4], "attached while paused: drawn \(p.drawn), staying \(p.staying)")
}

/// What the Ocean and the Web show of their state: fish and sharks; the painted cells.
private func fingerprint(_ sim: HabitatSim) -> [Double] {
    if let o = sim as? OceanSim {
        var v: [Double] = []
        for f in o.world.fish { v += [f.x, f.y, f.vx, f.vy] }
        for s in o.world.sharks { v += s.nodes }
        return v
    }
    guard let p = sim as? CellPainter else { return [] }
    let r = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let g = GridSpec.make(viewportSize: r.size, cell: GridSpec.cell(forWidth: 2560))
    let c = CellCanvas(cols: g.cols, rows: g.rows)
    p.paint(viewport: r, grid: g, theme: ThemeParams.make(Settings.defaults, systemIsDark: true, accent: .zero), into: c)
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    func add<T>(_ a: [T]) { a.withUnsafeBytes { b in for x in b { h = (h ^ UInt64(x)) &* 0x100_0000_01b3 } } }
    add(c.block); add(c.ink); add(c.glyph); add(c.overGlyph); add(c.overInk)
    return [Double(h >> 32), Double(h & 0xffff_ffff)]
}

/// Each screen its own scene: a peer display attached, resized and detached never lays out the monitor's Ocean or
/// Web scene, whose own geometry is unchanged. Its sim matches a twin on a desk where nothing happened, on the change
/// and for steps after.
private func meadowDeskLeavesOceanAndWebAlone() throws {
    for kind in [HabitatKind.ocean, .web] {
        var s = Settings.defaults
        s.habitat = kind
        let d = HostedDesk([monitor], shared: false, s, seed: 51)
        let twin = HostedDesk([monitor], shared: false, s, seed: 51)
        let sim: HabitatSim = d.scenes[0].sim
        func same(_ what: String) throws {
            try expect(d.scenes[0].sim === sim, "\(kind) \(what): the monitor's scene was rebuilt")
            try expect(fingerprint(sim) == fingerprint(twin.scenes[0].sim), "\(kind) \(what): the monitor's scene changed")
        }
        func run(_ n: Int) { for _ in 0..<n { d.scenes[0].sim.step(OceanClock.step); twin.step() } }
        run(120)
        d.arrange([monitor, laptop], shared: false)
        try same("attach")
        run(300)
        try same("after attach")
        d.arrange([monitor, screen(2, 375, 1440, 1512, 982)], shared: false)
        try same("peer resized")
        run(120)
        d.arrange([monitor], shared: false)
        try same("detach")
        run(300)
        try same("after detach")
    }
}

/// More displays than places: the 12 is absolute, some displays get none.
private func meadowDeskZeroShares() throws {
    for n in [1, 7, 12] {
        for count in [12, 13, 20] {
            let sizes: [CGSize] = Array(repeating: CGSize(width: 1440, height: 900), count: count)
            let got: [Int] = MeadowTuning.areaCountShares(n, screens: sizes)
            try expect(got.reduce(0, +) <= 12 && got.allSatisfy { $0 >= 0 }, "count \(n) on \(count) displays: \(got)")
            if count == 12 { try expect(got.allSatisfy { $0 >= 1 }, "count \(n) on 12 displays: \(got)") }
        }
    }
    let wall: [ScreenInfo] = (0..<13).map { (i: Int) -> ScreenInfo in screen(i + 1, Double(i) * 1440, 0, 1440, 900) }
    let d = HostedDesk(wall, shared: false, meadowSettings(), seed: 61)
    try settle(d, to: shares(7, wall), within: 30, "13 displays")
    try expect(d.drawn.reduce(0, +) == 12, "13 displays: \(d.drawn)")
}

/// A fresh scene's species split is the line-up's as Settings advertises it (`MeadowLineUp.shares`: Mixed's 7 is
/// 2 Monarchs, 2 Blue Morphos, 2 Swallowtails, 1 Cabbage White), on any seed.
private func meadowFreshLineUpAsAdvertised() throws {
    var lineUps: [(String, [ButterflyKind], Int)] = MeadowLineUp.all.map { ($0.title, $0.butterflies, $0.count) }
    lineUps.append(("Custom", [.monarch, .white], 7))
    let one: ScreenInfo = screen(1, 0, 0, 1800, 1169)
    for (title, on, count) in lineUps {
        for seed in UInt64(1)...UInt64(12) {
            var s = meadowSettings(count)
            s.meadowButterflies = on
            let d = HostedDesk([one], shared: false, s, seed: seed)
            let flies = d.meadows[0].world.flies
            let got: [Int] = on.map { (k: ButterflyKind) -> Int in flies.filter { $0.kind == k }.count }
            let want: [Int] = MeadowLineUp.shares(on, count: count).map(\.count)
            try expect(got == want, "\(title), seed \(seed): \(got), advertised \(want)")
        }
    }
}

/// The About banner shown again takes a new Meadow line-up (a live scene takes it in place).
private func meadowAboutTakesNewLineUp() throws {
    var mixed = meadowSettings()
    mixed.meadowButterflies = ButterflyKind.allCases
    var morphos = mixed
    MeadowLineUp.all[2].apply(to: &morphos)
    try expect(!Habitats.needsRebuild(old: mixed, new: morphos), "a live scene rebuilds for a line-up")
    try expect(Habitats.needsFreshLook(old: mixed, new: morphos), "reopened About keeps the old line-up")
    var faster = mixed
    faster.speed = 1.5
    try expect(!Habitats.needsFreshLook(old: mixed, new: faster), "reopened About rebuilt for a speed change")
    var ocean = Settings.defaults
    ocean.meadowButterflies = [.morpho]
    try expect(!Habitats.needsFreshLook(old: Settings.defaults, new: ocean), "the Ocean rebuilt for a Meadow line-up")
}

/// The "New" badge, by the one 3.1 upgrade rule (`Arrival`, which t9's what's-new uses too): only for someone
/// upgrading from before 3.1, decided once.
private func arrivalDecidesOnce() throws {
    let fresh: Arrival = Arrival.decide(stored: nil, savedSettings: false, onboarded: false, handedOver: false)
    try expect(fresh == .since31, "a fresh install is \(fresh)")
    try expect(!fresh.meadowIsNew(Settings.defaults), "the badge shows on a fresh install")
    let traces: [(Bool, Bool, Bool)] = [(true, false, false), (false, true, false), (false, false, true)]
    for (saved, onboarded, handedOver) in traces {
        let a: Arrival = Arrival.decide(stored: nil, savedSettings: saved, onboarded: onboarded, handedOver: handedOver)
        try expect(a == .before31, "an upgrade (saved \(saved), onboarded \(onboarded), handed over \(handedOver)) is \(a)")
    }
    // Kept once decided: a fresh install that later saves settings and sees the welcome stays fresh.
    let later: Arrival = Arrival.decide(stored: fresh.rawValue, savedSettings: true, onboarded: true, handedOver: false)
    try expect(later == .since31, "a decided arrival changed to \(later)")
    let upgrade: Arrival = .before31
    try expect(upgrade.meadowIsNew(Settings.defaults), "no badge for an upgrade")
    var tried = Settings.defaults
    tried.habitat = .meadow
    try expect(!upgrade.meadowIsNew(tried.sanitized()), "the badge stays once the Meadow was picked")
}

func meadowDeskChecks() {
    check("meadowDeskTransitionsHoldTwelve", meadowDeskTransitionsHoldTwelve)
    check("meadowDeskHeldFrameResolves", meadowDeskHeldFrameResolves)
    check("meadowDeskLeavesOceanAndWebAlone", meadowDeskLeavesOceanAndWebAlone)
    check("meadowDeskZeroShares", meadowDeskZeroShares)
    check("meadowFreshLineUpAsAdvertised", meadowFreshLineUpAsAdvertised)
    check("meadowAboutTakesNewLineUp", meadowAboutTakesNewLineUp)
    check("arrivalDecidesOnce", arrivalDecidesOnce)
}
