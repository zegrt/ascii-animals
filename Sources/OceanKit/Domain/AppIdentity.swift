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

    public let identity: AppIdentity
    public let greeting: Greeting
    /// Settings held in memory from the defaults, never read from or written to the domain.
    public let transientSettings: Bool
    /// Draw on the built-in display alone (calibrating the Meadow's count at the laptop's density).
    public let builtInDisplayOnly: Bool
    /// Log the actual frame rate and power mode every few seconds (energy.sh reads it).
    public let reportsFrameRate: Bool
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
        startsUpdates = identity.runsUpdates
        runsHandover = identity.runsHandover && environment["ASCII_ANIMALS_NO_HANDOVER"] == nil
        matchesSystemWallpaper = identity.matchesSystemWallpaper
        offersUninstall = identity.offersUninstall
        changesLoginItem = identity.changesLoginItem
    }

    public init(bundleID: String?, environment: [String: String]) {
        self.init(identity: AppIdentity(bundleID: bundleID), environment: environment)
    }
}
