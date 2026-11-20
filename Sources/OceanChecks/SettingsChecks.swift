import Foundation
import OceanKit

func settingsChecks() {
    check("rngDeterministic") {
        var a = Rng(seed: 7), b = Rng(seed: 7)
        for _ in 0..<100 {
            try expect(a.next() == b.next(), "same seed diverged")
            let u = a.unit(); _ = b.unit()
            try expect(u >= 0 && u < 1, "unit out of range: \(u)")
        }
    }
    check("settingsHabitatDefaultsToOcean") {
        let d = Settings.defaults
        try expect(d.habitat == .ocean, "habitat \(d.habitat)")
        try expect(d.webSpiders == SpiderKind.defaultCast, "spiders \(d.webSpiders)")
        try expect(d.webFlies && d.webJumper, "flies/jumper default off")
    }
    check("settingsFromSharksKeepOcean") {
        let s = SettingsCodec.decode(Data(#"{"sharks":["mako"],"checkForUpdates":true}"#.utf8))
        try expect(s.habitat == .ocean, "habitat \(s.habitat)")
        try expect(s.sharks == [.mako], "sharks \(s.sharks)")
    }
    check("settingsHabitatRoundTrips") {
        var s = Settings.defaults
        s.habitat = .web; s.webSpiders = [.nephila]; s.webFlies = false
        let t = SettingsCodec.decode(SettingsCodec.encode(s))
        try expect(t.habitat == .web && t.webSpiders == [.nephila] && !t.webFlies && t.webJumper, "got \(t)")
        let u = SettingsCodec.decode(Data(#"{"habitat":"mars"}"#.utf8))
        try expect(u.habitat == .ocean, "unknown habitat -> \(u.habitat)")
    }
    check("settingsUnknownSpiderDropped") {
        let s = SettingsCodec.decode(Data(#"{"webSpiders":["araneus","tarantula"]}"#.utf8))
        try expect(s.webSpiders == [.araneus], "got \(s.webSpiders)")
        var t = Settings.defaults
        t.webSpiders = Array(repeating: .argiope, count: 9)
        try expect(t.sanitized().webSpiders.count == 8, "cap")
        t.webSpiders = []
        try expect(t.sanitized().webSpiders == SpiderKind.defaultCast, "refill")
    }
    check("settingsDecodeEmptyIsDefaults") {
        try expect(SettingsCodec.decode(Data("{}".utf8)) == Settings.defaults, "{} is not defaults")
    }
    check("settingsDropsUnknownSpecies") {
        let s = SettingsCodec.decode(Data(#"{"sharks":["whale","mako"]}"#.utf8))
        try expect(s.sharks == [.mako], "got \(s.sharks)")
    }
    check("settingsSanitizeClamps") {
        var s = Settings.defaults
        s.fishDensity = 99; s.speed = 0; s.fps = 45
        s.sharks = Array(repeating: .mako, count: 9)
        let t = s.sanitized()
        try expect(t.fishDensity == 2.0, "density \(t.fishDensity)")
        try expect(t.speed == 0.5, "speed \(t.speed)")
        try expect(t.fps == 60, "fps \(t.fps)")
        try expect(t.sharks.count == 8, "sharks \(t.sharks.count)")
        s.sharks = []
        try expect(s.sanitized().sharks == Settings.defaults.sharks, "empty sharks not defaulted")
    }
    check("settingsFpsOptions") {
        var s = Settings.defaults
        for (input, want) in [(30, 30), (59, 60), (120, 60), (1, 15), (20, 15), (23, 30)] {
            s.fps = input
            try expect(s.sanitized().fps == want, "fps \(input) -> \(s.sanitized().fps), want \(want)")
        }
    }
    check("settingsSharedOceanDefaultsOn") {
        try expect(Settings.defaults.sharedOcean, "shared ocean default off")
        try expect(!SettingsCodec.decode(Data(#"{"sharedOcean":false}"#.utf8)).sharedOcean, "not decoded")
    }
    check("settingsAppFieldsDefaultOn") {
        let d = Settings.defaults
        try expect(d.pauseShortcut && d.showMenuBarIcon && d.checkForUpdates && d.autoInstallUpdates, "defaults \(d)")
        let s = SettingsCodec.decode(Data(#"{"pauseShortcut":false,"showMenuBarIcon":false,"checkForUpdates":false,"autoInstallUpdates":false}"#.utf8))
        try expect(!s.pauseShortcut && !s.showMenuBarIcon && !s.checkForUpdates && !s.autoInstallUpdates, "not decoded")
        // Settings saved before 2.3 have no autoInstallUpdates: it comes on.
        try expect(SettingsCodec.decode(Data(#"{"checkForUpdates":true}"#.utf8)).autoInstallUpdates, "old settings")
        try expect(String(decoding: SettingsCodec.encode(d), as: UTF8.self).contains(#""autoInstallUpdates":true"#), "not encoded")
    }
    check("settingsDefaultFps30") { try expect(Settings.defaults.fps == 30, "default fps \(Settings.defaults.fps)") }
    check("settingsCorruptJSONFallsBack") {
        try expect(SettingsCodec.decode(Data("nope".utf8)) == Settings.defaults, "garbage not defaults")
        try expect(SettingsCodec.decode(nil) == Settings.defaults, "nil not defaults")
    }
    check("settingsLowPowerAnimatesDefaultsOff") {
        try expect(!Settings.defaults.lowPowerAnimates, "default on")
        try expect(SettingsCodec.decode(Data(#"{"lowPowerAnimates":true}"#.utf8)).lowPowerAnimates, "not decoded")
    }
    check("diagnosticsNameTheHabitat") {
        let web = DiagnosticFacts.mode(habitat: .web, run: .live(fps: 30), screens: 1, scenes: 1, failure: nil)
        try expect(web.contains("Web"), "web session: \(web)")
        let ocean = DiagnosticFacts.mode(habitat: .ocean, run: .still, screens: 2, scenes: 1, failure: nil)
        try expect(ocean.contains("Ocean") && !ocean.contains("Web"), "ocean session: \(ocean)")
        let failed = DiagnosticFacts.mode(habitat: .web, run: nil, screens: 0, scenes: 0, failure: "no Metal device")
        try expect(failed.contains("Web") && failed.contains("no Metal device"), "failed start: \(failed)")
    }
    check("meadowSettingsDefaults") {
        let d = Settings.defaults
        try expect(d.meadowButterflies == ButterflyKind.allCases && d.meadowCount == 7 && !d.meadowTried, "defaults \(d)")
        try expect(MeadowLineUp.matching(d)?.title == "Mixed", "default is not Mixed")
        try expect(HabitatKind.offered == [.ocean, .web, .meadow], "offered \(HabitatKind.offered)")
    }
    check("meadowSettingsOldFilesKeepEverythingElse") {
        // A settings file from before 3.1 has no Meadow fields: the Meadow takes its defaults, nothing else moves.
        let old = #"{"sharks":["mako","tiger"],"habitat":"web","webSpiders":["nephila"],"speed":1.2,"fps":60,"calm":true}"#
        let s = SettingsCodec.decode(Data(old.utf8))
        try expect(s.sharks == [.mako, .tiger] && s.habitat == .web && s.webSpiders == [.nephila], "family moved: \(s)")
        try expect(s.speed == 1.2 && s.fps == 60 && s.calm, "family moved: \(s)")
        try expect(s.meadowButterflies == ButterflyKind.allCases && s.meadowCount == 7 && !s.meadowTried, "meadow \(s)")
    }
    check("meadowSettingsDecodeTolerantly") {
        let a = SettingsCodec.decode(Data(#"{"meadowButterflies":["white","dragonfly","monarch","white"],"meadowCount":9}"#.utf8))
        try expect(a.meadowButterflies == [.monarch, .white] && a.meadowCount == 9, "unknown dropped, order kept: \(a.meadowButterflies)")
        let b = SettingsCodec.decode(Data(#"{"meadowButterflies":["moth"],"meadowCount":"many","meadowTried":"yes"}"#.utf8))
        try expect(b.meadowButterflies == ButterflyKind.allCases, "none left keeps the default: \(b.meadowButterflies)")
        try expect(b.meadowCount == 7 && !b.meadowTried, "bad types keep defaults: \(b.meadowCount) \(b.meadowTried)")
        let c = SettingsCodec.decode(Data(#"{"meadowButterflies":"monarch","meadowCount":40}"#.utf8))
        try expect(c.meadowButterflies == ButterflyKind.allCases && c.meadowCount == 12, "\(c.meadowButterflies) \(c.meadowCount)")
        try expect(SettingsCodec.decode(Data(#"{"meadowCount":-3}"#.utf8)).meadowCount == 1, "low count")
    }
    check("meadowSettingsAtLeastOneStaysOn") {
        var s = Settings.defaults
        s.meadowButterflies = []
        try expect(s.sanitized().meadowButterflies == ButterflyKind.allCases, "none on")
        s.meadowButterflies = [.white, .morpho, .white]
        try expect(s.sanitized().meadowButterflies == [.morpho, .white], "order and repeats: \(s.sanitized().meadowButterflies)")
    }
    check("meadowSettingsRoundTrip") {
        var s = Settings.defaults
        s.habitat = .meadow; s.meadowButterflies = [.swallowtail]; s.meadowCount = 11
        let t = SettingsCodec.decode(SettingsCodec.encode(s))
        try expect(t.habitat == .meadow && t.meadowButterflies == [.swallowtail] && t.meadowCount == 11, "got \(t)")
        try expect(t.meadowTried, "picking the Meadow is not remembered")
        let json = String(decoding: SettingsCodec.encode(t), as: UTF8.self)
        try expect(json.contains(#""meadowButterflies":["swallowtail"]"#), "saved by name: \(json)")
        var u = t
        u.habitat = .ocean
        try expect(SettingsCodec.decode(SettingsCodec.encode(u)).meadowTried, "the New tag came back")
    }
    check("meadowLineUpsRoundTrip") {
        let titles = MeadowLineUp.all.map(\.title)
        try expect(titles == ["Mixed", "Just a Few", "Blue Morphos"], "line-ups \(titles)")
        for p in MeadowLineUp.all {
            var s = Settings.defaults
            s.habitat = .meadow
            p.apply(to: &s)
            let t = SettingsCodec.decode(SettingsCodec.encode(s))
            try expect(t.meadowButterflies == p.butterflies && t.meadowCount == p.count, "\(p.title) changed: \(t)")
            try expect(MeadowLineUp.matching(t) == p, "\(p.title) does not match itself")
        }
        var custom = Settings.defaults
        custom.meadowButterflies = [.monarch, .white]
        try expect(MeadowLineUp.matching(custom.sanitized()) == nil, "Custom: species")
        custom = Settings.defaults
        custom.meadowCount = 8
        try expect(MeadowLineUp.matching(custom.sanitized()) == nil, "Custom: count")
    }
    check("meadowSharesAsTheSketch") {
        func line(_ on: [ButterflyKind], _ n: Int) -> String { MeadowLineUp.shares(on, count: n).map { "\($0.count)\($0.kind.key)" }.joined(separator: " ") }
        try expect(line(ButterflyKind.allCases, 7) == "2monarch 2morpho 2swallowtail 1white", line(ButterflyKind.allCases, 7))
        try expect(line([.monarch, .white], 7) == "4monarch 3white", line([.monarch, .white], 7))
        try expect(line([.monarch, .morpho, .white], 3) == "1monarch 1morpho 1white", "just a few")
        try expect(line(ButterflyKind.allCases, 2) == "1monarch 1morpho", "fewer than species")
    }
    check("meadowCountByArea", meadowCountByArea)
    check("meadowTwelveOnTheDeskEitherWay", meadowTwelveOnTheDeskEitherWay)
    meadowDeskChecks()
    check("settingsRoundTrip") {
        var s = Settings.defaults
        s.calm = true; s.appearance = .light; s.sharks = [.nurse, .zebra]
        try expect(SettingsCodec.decode(SettingsCodec.encode(s)) == s, "round trip changed settings")
    }
}

/// How Many by screen area: the director's laptop shows the chosen count, bigger screens more, a scene at most 12.
private func meadowCountByArea() throws {
    // The director's laptop (1800 × 1169) shows exactly the chosen count, every count.
    let exact: [Int] = (1...12).map { (n: Int) -> Int in MeadowTuning.areaCount(n, width: 1800, height: 1169) }
    try expect(exact == Array(1...12), "director's laptop \(exact)")
    let air: Int = MeadowTuning.areaCount(7, width: 1470, height: 956)
    let laptop: Int = MeadowTuning.areaCount(7, width: 1440, height: 900)
    let big: Int = MeadowTuning.areaCount(7, width: 2560, height: 1440)
    let small: Int = MeadowTuning.areaCount(7, width: 900, height: 324)
    let huge: Int = MeadowTuning.areaCount(12, width: 6016, height: 3384)
    try expect(air == 7 && laptop == 7 && big == 12 && small == 7 && huge == 24, "air \(air) laptop \(laptop) big \(big) small \(small) huge \(huge)")
    try expect(MeadowTuning.areaCountLimit == 12, "limit \(MeadowTuning.areaCountLimit)")
    // A scene never holds more than 12 in all, on any desk, at any count.
    let desks: [[CGRect]] = [
        [CGRect(x: 0, y: 0, width: 1800, height: 1169)],
        [CGRect(x: 0, y: 0, width: 6016, height: 3384)],
        [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1800, height: 1169)],
        [CGRect(x: 0, y: 0, width: 1800, height: 1169), CGRect(x: 1800, y: 0, width: 1800, height: 1169), CGRect(x: 3600, y: 0, width: 1800, height: 1169)],
    ]
    for rects in desks {
        for n in [1, 3, 7, 12] {
            var d = Settings.defaults
            d.habitat = .meadow; d.meadowCount = n
            let ds = MeadowSim(settings: d, seed: 5)
            ds.layout(terrain: Terrain(rects: rects), cell: CGSize(width: 13, height: 19), settings: d)
            let got: Int = ds.world.flies.count
            let one: Bool = rects.count == 1 && rects[0].width == 1800
            try expect(got <= 12 && got >= min(n, 12) && (!one || got == n), "\(rects.count) screens, count \(n): \(got)")
        }
    }
    // The app's sim: the settings reach the tuning, and a shared scene counts each screen by its own area.
    var s = Settings.defaults
    s.habitat = .meadow; s.meadowButterflies = [.morpho]; s.meadowCount = 5; s.interaction = false
    let t = MeadowSim.tuning(.director, s)
    try expect(t.species == [false, true, false, false] && t.count == 5 && t.areaCount && !t.cursorLand, "tuning \(t)")
    let sim = MeadowSim(settings: s, seed: 3)
    let screens = [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1440, height: 900)]
    sim.layout(terrain: Terrain(rects: screens), cell: CGSize(width: 13, height: 19), settings: s)
    let n: Int = sim.world.flies.count
    // 9 + 5 by area, held to 12 in all.
    try expect(n == 12 && sim.world.flies.allSatisfy { $0.kind == .morpho }, "flies \(n)")
    // Below the cap the scene holds each screen's share: 3 → 5 + 3.
    var few = s
    few.meadowCount = 3
    let fewSim = MeadowSim(settings: few, seed: 3)
    fewSim.layout(terrain: Terrain(rects: screens), cell: CGSize(width: 13, height: 19), settings: few)
    let fewN: Int = fewSim.world.flies.count
    try expect(fewN == 5 + 3, "count 3 over two screens: \(fewN)")
    // A new line-up in place: the morphos leave and the newcomers fly in, never more than 12 drawn on the way (the
    // ones leaving count until they are out of sight), and in the end 12, none of them morphos.
    s.meadowButterflies = [.monarch, .white]
    sim.update(settings: s)
    var most: Int = sim.world.flies.count
    for _ in 0..<(90 * 60) {
        sim.step(OceanClock.step)
        most = max(most, sim.world.flies.count)
    }
    let active = sim.world.flies.filter { !$0.leaving }
    try expect(most <= 12, "after a new line-up, \(most) drawn at once")
    try expect(active.count == 12 && sim.world.flies.count == 12 && active.allSatisfy { $0.kind != .morpho },
               "after a new line-up: \(active.map(\.kind))")
}

/// "Cap at 12 total" on fresh desks, whether one scene spans the screens or each screen is its own scene.
private func meadowTwelveOnTheDeskEitherWay() throws {
    // "Cap at 12 total": the desk never holds more than 12, whether one scene spans the screens or each screen
    // is its own scene ("One habitat across displays" off), on the owner's desk and on three displays.
    let owner: [ScreenInfo] = [ScreenInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), scale: 2),
                               ScreenInfo(id: 2, frame: CGRect(x: 375, y: 1440, width: 1800, height: 1169), scale: 2)]
    let three: [ScreenInfo] = [ScreenInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), scale: 2),
                               ScreenInfo(id: 2, frame: CGRect(x: 1800, y: 0, width: 2560, height: 1440), scale: 2),
                               ScreenInfo(id: 3, frame: CGRect(x: 4360, y: 0, width: 1920, height: 1080), scale: 1)]
    // The app's way: the app's scene host lays the desk out (HabitatScene.arrange).
    func scenes(_ screens: [ScreenInfo], shared: Bool, _ s: Settings) -> HostedDesk {
        HostedDesk(screens, shared: shared, s, seed: 7)
    }
    func onDesk(_ d: HostedDesk) -> [Int] { d.meadows.map { (m: MeadowSim) -> Int in m.world.flies.filter { !$0.leaving }.count } }
    for (name, screens) in [("owner's desk", owner), ("three displays", three)] {
        for n in 1...12 {
            var s = Settings.defaults
            s.habitat = .meadow; s.meadowCount = n
            let one: Int = onDesk(scenes(screens, shared: true, s)).reduce(0, +)
            let each: [Int] = onDesk(scenes(screens, shared: false, s))
            let total: Int = each.reduce(0, +)
            // Both ways hold the same number: each screen's count by area, at most 12 in all, each screen at least 1.
            try expect(one <= 12 && total <= 12 && total == one && each.allSatisfy { $0 >= 1 },
                       "\(name), count \(n): one scene \(one), separate \(each)")
        }
    }
    // The owner's desk at the default 7: 12 + 7 by area, shared as 8 + 4 (one scene across it holds 12).
    var d = Settings.defaults
    d.habitat = .meadow; d.meadowCount = 7
    let ownerSeven: [Int] = onDesk(scenes(owner, shared: false, d))
    try expect(ownerSeven == [8, 4], "owner's desk at 7: \(ownerSeven)")
    // Below the cap each screen keeps its own count: 3 gives 5 + 3.
    d.meadowCount = 3
    let ownerThree: [Int] = onDesk(scenes(owner, shared: false, d))
    try expect(ownerThree == [5, 3], "owner's desk at 3: \(ownerThree)")
    // One display alone keeps the whole 12.
    let alone: [Int] = MeadowTuning.areaCountShares(7, screens: [CGSize(width: 2560, height: 1440)])
    try expect(alone == [12], "one display: \(alone)")
    // A new count in place keeps the share: 3 → 12 → 5 → 12 on separate scenes, never more than 12 on the desk.
    let sims = scenes(owner, shared: false, d)
    for n in [12, 5, 12] {
        d.meadowCount = n
        for m in sims.meadows {
            m.update(settings: d)
            for _ in 0..<30 { m.step(1.0 / 60.0) }
        }
        let now: Int = sims.drawn.reduce(0, +)
        try expect(now <= 12, "after a change to \(n): \(sims.drawn)")
    }
    // Many small screens: each at least 1 while places are left, the rest by area.
    let wall: [CGSize] = Array(repeating: CGSize(width: 1920, height: 1080), count: 6) + [CGSize(width: 6016, height: 3384)]
    let wallShares: [Int] = MeadowTuning.areaCountShares(12, screens: wall)
    try expect(wallShares.reduce(0, +) == 12 && wallShares.allSatisfy { $0 >= 1 }, "seven screens: \(wallShares)")
}
