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
        try expect(d.pauseShortcut && d.showMenuBarIcon && d.checkForUpdates, "defaults \(d)")
        let s = SettingsCodec.decode(Data(#"{"pauseShortcut":false,"showMenuBarIcon":false,"checkForUpdates":false}"#.utf8))
        try expect(!s.pauseShortcut && !s.showMenuBarIcon && !s.checkForUpdates, "not decoded")
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
    check("settingsRoundTrip") {
        var s = Settings.defaults
        s.calm = true; s.appearance = .light; s.sharks = [.nurse, .zebra]
        try expect(SettingsCodec.decode(SettingsCodec.encode(s)) == s, "round trip changed settings")
    }
}
