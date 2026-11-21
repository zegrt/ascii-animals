import Foundation

/// Which copy of the app this is, decided from its bundle ID alone, and what that copy may do on this Mac.
///
/// The energy-test copy (`Tools/build.sh --test`, driven by `Tools/energy.sh`) is a separate identity: its own bundle
/// ID, name and executable, so its own defaults domain (macOS keys `UserDefaults.standard` by bundle ID), and its own
/// log and Application Support folders. It never reaches past them: no self-updater or update checks, no ASCII Sharks
/// hand-over or watcher, no uninstaller, no system-wallpaper match (so no `wallpaperMemory.v1` and no stills), no login
/// item. Only the exact test ID takes that path, so the app people install (`Handover.animalsBundleID`) never can.
public enum AppIdentity: Equatable, Sendable {
    /// The app people install.
    case real
    /// The energy-test copy.
    case energyTest
    /// Anything else: a bare dev binary (no bundle ID) or another ID. Behaves like the app, without the hand-over.
    case other

    public static let energyTestBundleID = "local.ascii-animals.energy-test"
    public static let energyTestName = "ASCII Animals Test"
    public static let energyTestExecutable = "ASCIIAnimalsEnergyTest"

    public init(bundleID: String?) {
        if bundleID == Handover.animalsBundleID {
            self = .real
        } else if bundleID == AppIdentity.energyTestBundleID {
            self = .energyTest
        } else {
            self = .other
        }
    }

    public var isEnergyTest: Bool { self == .energyTest }
    /// The self-updater, its update checks, notices and installs.
    public var runsUpdates: Bool { !isEnergyTest }
    /// The ASCII Sharks hand-over and its watcher (also off with ASCII_ANIMALS_NO_HANDOVER: `Handover.enabled`).
    public var runsHandover: Bool { self == .real }
    /// "Uninstall ASCII Animals…" in Help and `--uninstall` on the command line.
    public var offersUninstall: Bool { !isEnergyTest }
    /// "Match System Wallpaper": the stills, `wallpaperMemory.v1` and "Restore Original Wallpaper".
    public var matchesSystemWallpaper: Bool { !isEnergyTest }
    /// "Open at Login" (a login item outlives the run).
    public var changesLoginItem: Bool { !isEnergyTest }
    /// The folder name under ~/Library/Logs and ~/Library/Application Support (the log and the crash marker).
    public var folderName: String { isEnergyTest ? "ASCII Animals Energy Test" : "ASCII Animals" }
}

/// How this launch runs: the identity's limits and, in the energy-test copy only, its developer modes. The app
/// people install ignores every developer flag here except the hand-over opt-out it has always had.
public struct LaunchPlan: Equatable, Sendable {
    /// What greets the launch.
    public enum Greeting: Equatable, Sendable {
        /// The welcome or a what's-new card, as the saved flags decide (the app people install).
        case asSaved
        /// Nothing: no welcome, no card, `arrival.v1` neither read nor saved (energy runs).
        case quiet
        /// The Meadow card once, as an upgrader sees it, over transient settings; nothing read or saved.
        case whatsNewPreview
    }

    public static let quietFlag = "ASCII_ANIMALS_QUIET_LAUNCH"
    public static let previewFlag = "ASCII_ANIMALS_PREVIEW_WHATSNEW"
    public static let builtInOnlyFlag = "ASCII_ANIMALS_BUILTIN_DISPLAY_ONLY"
    /// This launch's id, made by Tools/energy.sh for each launch and written in every energy log line, so a plan,
    /// card or reading from another launch (a reused pid, an old log, a probe) never counts.
    public static let launchFlag = "ASCII_ANIMALS_ENERGY_LAUNCH"

    public let identity: AppIdentity
    public let greeting: Greeting
    /// Settings held in memory from the defaults, never read from or written to the domain.
    public let transientSettings: Bool
    /// Draw on the built-in display alone (calibrating the Meadow's count at the laptop's density).
    public let builtInDisplayOnly: Bool
    /// Log the actual frame rate and power mode every few seconds (energy.sh reads it).
    public let reportsFrameRate: Bool
    /// The id energy.sh gave this launch (`launchFlag`): the energy-test copy only, 8 to 64 letters, digits or
    /// dashes; anything else is no id ("none" in the log, which energy.sh never accepts).
    public let launchID: String?
    public let startsUpdates: Bool
    public let runsHandover: Bool
    public let matchesSystemWallpaper: Bool
    public let offersUninstall: Bool
    public let changesLoginItem: Bool

    public init(identity: AppIdentity, environment: [String: String]) {
        self.identity = identity
        let test: Bool = identity.isEnergyTest
        // The energy-test copy is quiet unless asked for the preview; asked for both, quiet wins (a card must
        // never draw over a measurement).
        let quiet: Bool = environment[LaunchPlan.quietFlag] == "1"
        let preview: Bool = environment[LaunchPlan.previewFlag] == "1"
        if !test {
            greeting = .asSaved
        } else if preview && !quiet {
            greeting = .whatsNewPreview
        } else {
            greeting = .quiet
        }
        transientSettings = greeting == .whatsNewPreview
        builtInDisplayOnly = test && environment[LaunchPlan.builtInOnlyFlag] == "1"
        reportsFrameRate = test
        launchID = test ? LaunchPlan.validLaunchID(environment[LaunchPlan.launchFlag]) : nil
        startsUpdates = identity.runsUpdates
        runsHandover = identity.runsHandover && environment["ASCII_ANIMALS_NO_HANDOVER"] == nil
        matchesSystemWallpaper = identity.matchesSystemWallpaper
        offersUninstall = identity.offersUninstall
        changesLoginItem = identity.changesLoginItem
    }

    public init(bundleID: String?, environment: [String: String]) {
        self.init(identity: AppIdentity(bundleID: bundleID), environment: environment)
    }

    /// `value` when it is 8 to 64 ASCII letters, digits or dashes; else nil.
    public static func validLaunchID(_ value: String?) -> String? {
        guard let v = value, (8...64).contains(v.utf8.count) else { return nil }
        let ok: Bool = v.utf8.allSatisfy { (c: UInt8) -> Bool in
            (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 45
        }
        return ok ? v : nil
    }
}

extension LaunchPlan.Greeting {
    /// One word for the energy-test copy's log (`EnergyLog.plan`).
    public var word: String {
        switch self {
        case .asSaved: return "asSaved"
        case .quiet: return "quiet"
        case .whatsNewPreview: return "preview"
        }
    }
}

/// The energy-test copy's one folder: `build/energy-test`, next to `build/ASCII Animals Test.app`. Its log and crash
/// marker live there, its `--snapshot-*` outputs may only go there, and Tools/energy.sh keeps its lock and scratch
/// there. Nothing of the test copy's own files reaches the user's Library.
public enum EnergyTestFolder {
    public static let name = "energy-test"
    /// The subfolder for the test copy's log and crash marker.
    public static let appFolder = "app"

    /// The folder for a test bundle at `bundle`.
    public static func url(bundle: URL) -> URL {
        bundle.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
    }

    /// True when `path` lies strictly inside `folder`. Both must already have their symbolic links resolved; no
    /// component may be empty, `.` or `..` (so a sibling such as `energy-test2` or an escape never counts).
    public static func contains(_ path: String, in folder: String) -> Bool {
        guard folder.hasPrefix("/"), path.hasPrefix("/") else { return false }
        let base: String = folder.hasSuffix("/") ? folder : folder + "/"
        guard path.count > base.count, path.hasPrefix(base) else { return false }
        let rest: Substring = path.dropFirst(base.count)
        let parts: [Substring] = rest.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.contains { (p: Substring) -> Bool in p.isEmpty || p == "." || p == ".." }
    }
}

/// The energy-test copy's log lines that Tools/energy.sh reads (its selftest parses these exact shapes, and
/// OceanChecks pins them). One plan line at launch, then a reading every few seconds.
public enum EnergyLog {
    /// One display's frames actually drawn per second in the last interval.
    public struct Display: Equatable, Sendable {
        public let id: UInt32
        public let builtIn: Bool
        public let fps: Double
        public init(id: UInt32, builtIn: Bool, fps: Double) {
            self.id = id
            self.builtIn = builtIn
            self.fps = fps
        }
    }

    /// The launch id as logged: the id, or "none" (never accepted by energy.sh).
    public static func launchWord(_ id: String?) -> String { id ?? "none" }

    /// `energy-plan: pid=<pid> launch=<id> greeting=<quiet|preview> builtInOnly=<0|1>`
    public static func plan(pid: Int32, _ p: LaunchPlan) -> String {
        let only: String = p.builtInDisplayOnly ? "1" : "0"
        return "energy-plan: pid=\(pid) launch=\(launchWord(p.launchID)) greeting=\(p.greeting.word) builtInOnly=\(only)"
    }

    /// `energy: pid=<pid> launch=<id> mode=<live30|still|paused> setting=<fps> habitat=<h> count=<n> attached=<n> drawn=<n>
    /// displays=<id>:<b|e>:<fps>,... lowPower=<bool> battery=<bool> thermal=<state>` (`b` built-in, `e` external;
    /// `displays=none` when nothing is drawn).
    public static func reading(pid: Int32, launch: String?, mode: RunMode, setting: Int, habitat: String, count: Int, attached: Int,
                               displays: [Display], inputs: PowerInputs) -> String {
        let modeWord: String
        switch mode {
        case .live(let f): modeWord = "live\(f)"
        case .still: modeWord = "still"
        case .paused: modeWord = "paused"
        }
        let list: [String] = displays.map { (d: Display) -> String in
            let kind: String = d.builtIn ? "b" : "e"
            return "\(d.id):\(kind):" + String(format: "%.1f", d.fps)
        }
        let shown: String = list.isEmpty ? "none" : list.joined(separator: ",")
        let fields: [String] = ["pid=\(pid)", "launch=\(launchWord(launch))", "mode=\(modeWord)", "setting=\(setting)", "habitat=\(habitat)",
                                "count=\(count)", "attached=\(attached)", "drawn=\(displays.count)", "displays=\(shown)",
                                "lowPower=\(inputs.lowPowerMode)", "battery=\(inputs.onBattery)",
                                "thermal=\(inputs.thermal)"]
        return "energy: " + fields.joined(separator: " ")
    }

    /// The preview card reached the live screen (written by the live presenter only, never by a probe).
    public static func cardShown(pid: Int32, launch: String?) -> String {
        "energy-card: pid=\(pid) launch=\(launchWord(launch)) shown"
    }

    /// `energy-card: pid=<pid> launch=<id> drawn=<share> size=<w>x<h>`: after the fade-in, the share of the card
    /// window's pixels that are not transparent (0.000 to 1.000, three places; `WhatsNew.drawnShare`), read from the
    /// window's own image inside the app (no Screen Recording needed), and the window's size in points.
    public static func cardDrawn(pid: Int32, launch: String?, share: Double, width: Int, height: Int) -> String {
        let s: Double = min(1, max(0, share.isFinite ? share : 0))
        return "energy-card: pid=\(pid) launch=\(launchWord(launch)) drawn=" + String(format: "%.3f", s) + " size=\(width)x\(height)"
    }

    /// `energy-card: pid=<pid> launch=<id> closed=<reason> after=<s>s`: the preview card went, why, and how long after
    /// it was shown (whole seconds).
    public static func cardClosed(pid: Int32, launch: String?, reason: WhatsNew.CloseReason, after: Double) -> String {
        let secs: Int = after.isFinite ? max(0, Int(after.rounded())) : 0
        return "energy-card: pid=\(pid) launch=\(launchWord(launch)) closed=\(reason.rawValue) after=\(secs)s"
    }
}
