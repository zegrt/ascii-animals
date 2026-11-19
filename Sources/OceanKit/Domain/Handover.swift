import Foundation

/// What is true about ASCII Sharks on this Mac when ASCII Animals starts.
public struct HandoverFacts: Equatable {
    /// Where ASCII Sharks is: the running copy's bundle, else the one LaunchServices finds.
    public var sharksApp: URL?
    public var sharksRunning: Bool
    /// The trash offer was made on an earlier launch.
    public var alreadyOffered: Bool
    /// The one-time take-over (settings, welcome) was done on an earlier launch.
    public var alreadyImported: Bool
    /// Sharks' `settings.v2` (it writes them only once the user changes something).
    public var sharksSettings: Data?
    /// Sharks' `onboarded.v1`: its welcome was seen.
    public var sharksOnboarded: Bool
    /// ASCII Animals already has its own `settings.v2`, which are never overwritten.
    public var ownSettings: Bool

    public init(sharksApp: URL?, sharksRunning: Bool, alreadyOffered: Bool = false, alreadyImported: Bool,
                sharksSettings: Data?, sharksOnboarded: Bool = false, ownSettings: Bool = false) {
        self.sharksApp = sharksApp
        self.sharksRunning = sharksRunning
        self.alreadyOffered = alreadyOffered
        self.alreadyImported = alreadyImported
        self.sharksSettings = sharksSettings
        self.sharksOnboarded = sharksOnboarded
        self.ownSettings = ownSettings
    }
}

public enum HandoverStep: Equatable {
    case quitSharks, importSettings, skipWelcome, offerTrash(URL)
}

/// What greets someone at launch, once the hand-over is done.
public enum LaunchWelcome: Equatable {
    /// The welcome tour, which opens with the habitat choice.
    case tour
    /// The one "There's a new habitat: the Web." card, for someone who came from ASCII Sharks.
    case webCard
    case nothing
}

/// The hand-over from ASCII Sharks: quit it, take its settings, offer to remove it, and never run
/// alongside it.
public enum Handover {
    public static let animalsBundleID = "local.ascii-animals.wallpaper"
    public static let sharksBundleID = "local.ascii-sharks.wallpaper"

    // What ASCII Sharks 2.3 keeps, by its own names (its SettingsStore, OnboardingController,
    // SystemWallpaper and main.swift).
    public static let sharksSettingsKey = "settings.v2"
    public static let sharksOnboardedKey = "onboarded.v1"
    public static let sharksWallpaperKey = "wallpaperMemory.v1"
    /// Under Application Support. Sharks' uninstaller deletes it (with the rest of "ASCII Sharks").
    public static let sharksStillsFolder = "ASCII Sharks/Stills"
    /// Its scripted uninstall (Tools/uninstall.sh): puts the user's wallpaper back, removes its login item,
    /// settings, stills and logs, trashes the app and exits, with no questions.
    public static let sharksUninstallArguments = ["--uninstall", "--yes"]

    /// Whether ASCII Animals acts on ASCII Sharks at all: only the real app, never a bare dev binary
    /// (no bundle ID, its own defaults) nor a run with ASCII_ANIMALS_NO_HANDOVER set.
    public static func enabled(bundleID: String?, environment: [String: String]) -> Bool {
        bundleID == animalsBundleID && environment["ASCII_ANIMALS_NO_HANDOVER"] == nil
    }

    /// Apps that appeared in the running list while ASCII Animals runs (KVO on `runningApplications`:
    /// Sharks is LSUIElement, and macOS posts no did-launch notification for those). If one is ASCII
    /// Sharks (its login item, or opened by habit) it is quit, unless a quit is already under way.
    public static func shouldQuit(inserted bundleIDs: [String?], enabled: Bool, quitting: Bool) -> Bool {
        enabled && !quitting && bundleIDs.contains(sharksBundleID)
    }

    /// Whether the hand-over may add ASCII Animals as a login item: not from a disk image (read-only
    /// volume) or a translocated or bare copy, where it would point at the wrong place. An app folder
    /// the user can't write to (an admin-installed copy) is fine.
    public static func canAddLoginItem(bundlePath: String, onReadOnlyVolume: Bool) -> Bool {
        !onReadOnlyVolume && SelfUpdate.blocker(bundlePath: bundlePath) == nil
    }

    /// Marks the Web card as shown (the tour sets it too: it opens with the habitat choice).
    public static let webCardKey = "whatsNew.web.v1"

    /// A new user gets the tour. Someone who came from ASCII Sharks skipped it, habitat choice and all,
    /// so they get the Web card instead: once (this launch or a later one, so 3.0 hand-overs get it
    /// too), and not if they found the Web already.
    public static func launchWelcome(onboarded: Bool, handedOver: Bool, webCardShown: Bool, habitat: HabitatKind) -> LaunchWelcome {
        if !onboarded { return .tour }
        return handedOver && !webCardShown && habitat == .ocean ? .webCard : .nothing
    }

    public static func plan(_ f: HandoverFacts) -> [HandoverStep] {
        let trace = f.sharksRunning || f.sharksApp != nil || f.sharksSettings != nil || f.sharksOnboarded
        guard trace else { return [] }
        var steps: [HandoverStep] = []
        if f.sharksRunning { steps.append(.quitSharks) }
        if !f.alreadyImported {
            if f.sharksSettings != nil, !f.ownSettings { steps.append(.importSettings) }
            // A Sharks user has seen the tour already.
            if f.sharksApp != nil || f.sharksOnboarded || f.sharksSettings != nil { steps.append(.skipWelcome) }
        }
        if let app = f.sharksApp, !f.alreadyOffered { steps.append(.offerTrash(app)) }
        return steps
    }
}
