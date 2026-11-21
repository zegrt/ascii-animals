import Foundation
import OceanKit

/// The energy-test copy (`AppIdentity`, `LaunchPlan`): decided from the bundle ID alone; the app people install
/// never takes its path, and it never reaches the updater, the hand-over, the uninstaller, the system wallpaper or a
/// login item. Tools/build.sh and Tools/energy.sh name the same identity.
func identityChecks() {
    let real: String = Handover.animalsBundleID
    let test: String = AppIdentity.energyTestBundleID
    let devFlags: [String: String] = [LaunchPlan.quietFlag: "1", LaunchPlan.previewFlag: "1", LaunchPlan.builtInOnlyFlag: "1"]

    check("identityFromBundleIDAlone") {
        try expect(AppIdentity(bundleID: real) == .real, "the app")
        try expect(AppIdentity(bundleID: test) == .energyTest, "the energy-test copy")
        try expect(AppIdentity(bundleID: nil) == .other, "a bare binary")
        let spellings: [String] = [test.uppercased(), test + ".plist", " " + test, test + "x", "local.ascii-animals.energy"]
        for s in spellings {
            try expect(AppIdentity(bundleID: s) == .other, "only the exact test ID is the test copy: \(s)")
        }
        try expect(test.lowercased() != real.lowercased() && !test.hasPrefix(real), "the test ID is not the app's in any case")
        try expect(AppIdentity.energyTestExecutable != "ASCIIAnimals" && AppIdentity.energyTestName != "ASCII Animals",
                   "its own executable and name")
    }

    check("identityTestCopyReachesNothingOutside") {
        let envs: [[String: String]] = [[:], devFlags, ["ASCII_ANIMALS_NO_HANDOVER": "1"]]
        for env in envs {
            let p = LaunchPlan(bundleID: test, environment: env)
            try expect(!p.startsUpdates, "no updater (\(env))")
            try expect(!p.runsHandover, "no hand-over or watcher (\(env))")
            try expect(!p.offersUninstall, "no uninstaller (\(env))")
            try expect(!p.matchesSystemWallpaper, "no system wallpaper, no wallpaperMemory.v1 (\(env))")
            try expect(!p.changesLoginItem, "no login item (\(env))")
            try expect(p.greeting != .asSaved, "no welcome or card from saved flags (\(env))")
            try expect(p.reportsFrameRate, "logs its frame rate (\(env))")
        }
        try expect(!Handover.enabled(bundleID: test, environment: [:]), "Handover.enabled agrees")
        try expect(AppIdentity.energyTest.folderName == "ASCII Animals Energy Test", "its own folder name (its log lives in build/energy-test)")
    }

    check("identityRealAppUnchanged") {
        let envs: [[String: String]] = [[:], devFlags]
        for env in envs {
            let p = LaunchPlan(bundleID: real, environment: env)
            try expect(p.startsUpdates && p.runsHandover && p.offersUninstall && p.matchesSystemWallpaper && p.changesLoginItem,
                       "the app keeps everything (\(env))")
            try expect(p.greeting == .asSaved && !p.transientSettings && !p.builtInDisplayOnly && !p.reportsFrameRate,
                       "the app ignores the developer flags (\(env))")
        }
        try expect(!LaunchPlan(bundleID: real, environment: ["ASCII_ANIMALS_NO_HANDOVER": "1"]).runsHandover, "opt-out kept")
        try expect(AppIdentity.real.folderName == "ASCII Animals", "the app's folders unchanged")
        let bare = LaunchPlan(bundleID: nil, environment: devFlags)
        try expect(!bare.runsHandover && bare.startsUpdates && bare.greeting == .asSaved, "a bare binary as before")
    }

    check("identityTestCopyModes") {
        let quiet = LaunchPlan(bundleID: test, environment: [:])
        try expect(quiet.greeting == .quiet && !quiet.transientSettings && !quiet.builtInDisplayOnly, "default: quiet, saved in its domain")
        let preview = LaunchPlan(bundleID: test, environment: [LaunchPlan.previewFlag: "1"])
        try expect(preview.greeting == .whatsNewPreview && preview.transientSettings, "preview: the card, settings in memory")
        let both = LaunchPlan(bundleID: test, environment: [LaunchPlan.previewFlag: "1", LaunchPlan.quietFlag: "1"])
        try expect(both.greeting == .quiet && !both.transientSettings, "quiet wins over the preview")
        let notOne = LaunchPlan(bundleID: test, environment: [LaunchPlan.previewFlag: "yes", LaunchPlan.builtInOnlyFlag: "true"])
        try expect(notOne.greeting == .quiet && !notOne.builtInDisplayOnly, "flags count only as 1")
        let calibrate = LaunchPlan(bundleID: test, environment: [LaunchPlan.builtInOnlyFlag: "1"])
        try expect(calibrate.builtInDisplayOnly && calibrate.greeting == .quiet, "calibration: built-in display only, quiet")
    }

    check("identityExplicitZeroFlags") {
        // energy.sh sets every flag on each launch, to 1 or 0; 0 must mean off whatever else is set.
        let zeros: [String: String] = [LaunchPlan.quietFlag: "0", LaunchPlan.previewFlag: "0", LaunchPlan.builtInOnlyFlag: "0"]
        let measure = LaunchPlan(bundleID: test, environment: zeros.merging([LaunchPlan.quietFlag: "1"]) { (_: String, b: String) -> String in b })
        try expect(measure.greeting == .quiet && !measure.builtInDisplayOnly && !measure.transientSettings, "measure: quiet, every display")
        let preview = LaunchPlan(bundleID: test, environment: zeros.merging([LaunchPlan.previewFlag: "1"]) { (_: String, b: String) -> String in b })
        try expect(preview.greeting == .whatsNewPreview && preview.transientSettings && !preview.builtInDisplayOnly, "preview: the card")
        let calibrate = LaunchPlan(bundleID: test, environment: zeros.merging([LaunchPlan.quietFlag: "1", LaunchPlan.builtInOnlyFlag: "1"]) { (_: String, b: String) -> String in b })
        try expect(calibrate.greeting == .quiet && calibrate.builtInDisplayOnly, "calibrate: quiet, built-in only")
    }

    check("identityTestFolderContainment") {
        let f: String = "/x/build/energy-test"
        let inside: [String] = [f + "/a.txt", f + "/app/ascii-animals.log", f + "/run/top.txt"]
        for p in inside { try expect(EnergyTestFolder.contains(p, in: f), "inside: \(p)") }
        try expect(EnergyTestFolder.contains(f + "/a.txt", in: f + "/"), "a trailing slash on the folder")
        let outside: [String] = [f, f + "/", f + "2/a.txt", "/x/build/a.txt", f + "/../a.txt", f + "/./a.txt", f + "//a.txt",
                                 f + "/a/../../a.txt", "a.txt", "", "/tmp/a.txt"]
        for p in outside { try expect(!EnergyTestFolder.contains(p, in: f), "outside: '\(p)'") }
        try expect(!EnergyTestFolder.contains(f + "/a.txt", in: "build/energy-test"), "a relative folder never contains")
        let bundle: URL = URL(fileURLWithPath: "/x/build/ASCII Animals Test.app")
        try expect(EnergyTestFolder.url(bundle: bundle).path == f, "build/energy-test next to the test bundle")
    }

    check("identityEnergyLogShapes") {
        // energy.sh's selftest parses these exact lines; a change here must change it too.
        let quiet = LaunchPlan(bundleID: test, environment: [LaunchPlan.quietFlag: "1", LaunchPlan.previewFlag: "0", LaunchPlan.builtInOnlyFlag: "0"])
        try expect(EnergyLog.plan(pid: 501, quiet) == "energy-plan: pid=501 greeting=quiet builtInOnly=0", EnergyLog.plan(pid: 501, quiet))
        var inputs = PowerInputs()
        inputs.lowPowerMode = false
        inputs.onBattery = false
        let displays: [EnergyLog.Display] = [EnergyLog.Display(id: 1, builtIn: true, fps: 29.84),
                                             EnergyLog.Display(id: 2, builtIn: false, fps: 29.6)]
        let line: String = EnergyLog.reading(pid: 501, mode: .live(fps: 30), setting: 30, habitat: "meadow", count: 7,
                                             attached: 2, displays: displays, inputs: inputs)
        let want: String = "energy: pid=501 mode=live30 setting=30 habitat=meadow count=7 attached=2 drawn=2 "
            + "displays=1:b:29.8,2:e:29.6 lowPower=false battery=false thermal=nominal"
        try expect(line == want, line)
        let none: String = EnergyLog.reading(pid: 501, mode: .still, setting: 30, habitat: "meadow", count: 7,
                                             attached: 2, displays: [], inputs: inputs)
        try expect(none.contains(" mode=still ") && none.contains(" drawn=0 displays=none "), none)
        try expect(EnergyLog.cardShown(pid: 501) == "energy-card: pid=501 shown", "the preview card's line")
        let root: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let energy: String = (try? String(contentsOf: root.appendingPathComponent("Tools/energy.sh"), encoding: .utf8)) ?? ""
        try expect(energy.contains("displays=1:b:29.8,2:e:29.6 lowPower=false battery=false thermal=nominal"),
                   "energy.sh's selftest uses the same reading shape")
        try expect(energy.contains("energy-plan: pid=") && energy.contains("energy-card: pid="), "energy.sh reads the plan and card lines")
    }

    check("identityToolsAgree") {
        let root: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let build = try? String(contentsOf: root.appendingPathComponent("Tools/build.sh"), encoding: .utf8),
              let energy = try? String(contentsOf: root.appendingPathComponent("Tools/energy.sh"), encoding: .utf8) else {
            throw CheckFailure(detail: "Tools/build.sh or Tools/energy.sh not found next to the sources")
        }
        let idLine: String = "TEST_ID=\"\(test)\""
        let exeLine: String = "TEST_EXE=\"\(AppIdentity.energyTestExecutable)\""
        let nameLine: String = "TEST_NAME=\"\(AppIdentity.energyTestName)\""
        for (name, text) in [("build.sh", build), ("energy.sh", energy)] {
            try expect(text.contains(idLine) && text.contains(exeLine) && text.contains(nameLine), "\(name) names the same identity")
        }
        try expect(energy.contains("REAL_ID=\"\(real)\""), "energy.sh knows the ID it refuses")
    }
}
