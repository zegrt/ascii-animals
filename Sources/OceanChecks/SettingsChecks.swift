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
    check("settingsRoundTrip") {
        var s = Settings.defaults
        s.calm = true; s.appearance = .light; s.sharks = [.nurse, .zebra]
        try expect(SettingsCodec.decode(SettingsCodec.encode(s)) == s, "round trip changed settings")
    }
}
