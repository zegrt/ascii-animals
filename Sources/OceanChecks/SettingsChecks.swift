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
    check("meadowCountByArea") {
        let laptop: Int = MeadowTuning.areaCount(7, width: 1440, height: 900)
        let big: Int = MeadowTuning.areaCount(7, width: 2560, height: 1440)
        let small: Int = MeadowTuning.areaCount(7, width: 900, height: 324)
        let huge: Int = MeadowTuning.areaCount(12, width: 6016, height: 3384)
        try expect(laptop == 7 && big == 20 && small == 7 && huge == 24, "laptop \(laptop) big \(big) small \(small) huge \(huge)")
        // The app's sim: the settings reach the tuning, and a shared scene counts each screen by its own area.
        var s = Settings.defaults
        s.habitat = .meadow; s.meadowButterflies = [.morpho]; s.meadowCount = 5; s.interaction = false
        let t = MeadowSim.tuning(.director, s)
        try expect(t.species == [false, true, false, false] && t.count == 5 && t.areaCount && !t.cursorLand, "tuning \(t)")
        let sim = MeadowSim(settings: s, seed: 3)
        let screens = [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 375, y: 1440, width: 1440, height: 900)]
        sim.layout(terrain: Terrain(rects: screens), cell: CGSize(width: 13, height: 19), settings: s)
        let n: Int = sim.world.flies.count
        try expect(n == 14 + 5 && sim.world.flies.allSatisfy { $0.kind == .morpho }, "flies \(n)")
        s.meadowButterflies = [.monarch, .white]
        sim.update(settings: s)
        let active = sim.world.flies.filter { !$0.leaving }
        try expect(active.count == 19 && active.allSatisfy { $0.kind != .morpho }, "after a new line-up: \(active.map(\.kind))")
    }
    check("settingsRoundTrip") {
        var s = Settings.defaults
        s.calm = true; s.appearance = .light; s.sharks = [.nurse, .zebra]
        try expect(SettingsCodec.decode(SettingsCodec.encode(s)) == s, "round trip changed settings")
    }
}
