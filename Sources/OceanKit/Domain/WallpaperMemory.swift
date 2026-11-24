import Foundation

/// A system wallpaper and how it was shown.
public struct WallpaperEntry: Codable, Equatable, Sendable {
    public var url: URL
    /// NSImageScaling raw value.
    public var scaling: Int?
    public var allowClipping: Bool?
    /// sRGB RGBA.
    public var fillColor: [Double]?

    public init(url: URL, scaling: Int? = nil, allowClipping: Bool? = nil, fillColor: [Double]? = nil) {
        self.url = url
        self.scaling = scaling
        self.allowClipping = allowClipping
        self.fillColor = fillColor
    }
}

/// Another app's stills: ASCII Sharks', still showing if it was force-quit, and what it remembered was
/// underneath them. Never the user's own wallpaper.
public struct ForeignStills: Equatable, Sendable {
    public var folder: URL
    public var memory: WallpaperMemory
    public init(folder: URL, memory: WallpaperMemory = WallpaperMemory()) {
        self.folder = folder
        self.memory = memory
    }

    func contains(_ url: URL) -> Bool { WallpaperMemory.isOurs(url, stillsFolder: folder) }
}

/// Bookkeeping that keeps the user's own wallpaper safe while the system
/// wallpaper shows a still of the ocean.
///
/// macOS sets wallpapers per Space and offers no Space identity, so the rules
/// are conservative: remember the first wallpaper seen on each screen; replace
/// only that wallpaper or our own stills; never touch a wallpaper we don't
/// recognise; restore only where our still is showing.
public struct WallpaperMemory: Codable, Equatable, Sendable {
    public enum Decision: Equatable, Sendable { case apply, leaveAlone }

    public private(set) var originals: [String: WallpaperEntry] = [:]

    public init() {}

    public func original(for screen: String) -> WallpaperEntry? { originals[screen] }

    public static func isOurs(_ url: URL, stillsFolder: URL) -> Bool {
        let folder = canonical(stillsFolder.path)
        return canonical(url.path).hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    /// realpath() of the deepest existing ancestor plus the rest, so /tmp and
    /// /private/tmp compare equal even before the file exists.
    static func canonical(_ path: String) -> String {
        var head = (path as NSString).standardizingPath
        var tail: [String] = []
        while !head.isEmpty && head != "/" {
            if let r = realpath(head, nil) {
                defer { free(r) }
                return ([String(cString: r)] + tail.reversed()).joined(separator: "/")
            }
            tail.append((head as NSString).lastPathComponent)
            head = (head as NSString).deletingLastPathComponent
        }
        return path
    }

    /// Whether the still may replace `current` on this screen's current Space. A foreign still (ASCII
    /// Sharks') is replaced too, and what it covered, if known, is remembered as the original.
    public mutating func decide(screen: String, current: WallpaperEntry, stillsFolder: URL,
                                foreign: ForeignStills? = nil) -> Decision {
        if WallpaperMemory.isOurs(current.url, stillsFolder: stillsFolder) { return .apply }
        if let foreign, foreign.contains(current.url) {
            if originals[screen] == nil { originals[screen] = foreign.memory.original(for: screen) }
            return .apply
        }
        guard let known = originals[screen] else {
            originals[screen] = current
            return .apply
        }
        return known.url.standardizedFileURL == current.url.standardizedFileURL ? .apply : .leaveAlone
    }

    /// The wallpaper to put back, if our still (or a foreign one) is what this screen shows.
    public func restoreTarget(screen: String, current: WallpaperEntry, stillsFolder: URL,
                              foreign: ForeignStills? = nil) -> WallpaperEntry? {
        if WallpaperMemory.isOurs(current.url, stillsFolder: stillsFolder) { return originals[screen] }
        if let foreign, foreign.contains(current.url) { return originals[screen] ?? foreign.memory.original(for: screen) }
        return nil
    }

    public mutating func forget(screen: String) { originals[screen] = nil }
}

/// The desktop-image API as the wallpaper keeper sees it: NSWorkspace and the stills folder in the app, a fake with
/// Spaces in the checks. Displays are named by `SystemWallpaper.key(for:)`; each call reads or changes the Space in view.
public protocol DesktopImages: AnyObject {
    /// The displays attached now.
    var displays: [String] { get }
    /// What the display shows on the Space in view; nil when it can't be read.
    func current(on display: String) -> WallpaperEntry?
    /// Shows `entry` on the display's Space in view.
    func set(_ entry: WallpaperEntry, on display: String) throws
    /// The files in the stills folder.
    func stillFiles() -> [URL]
    func removeFile(_ url: URL) throws
}

/// What a restore did.
public struct RestoreOutcome: Equatable, Sendable {
    /// Displays whose own picture went back.
    public var restored: [String] = []
    /// Displays where it couldn't be put back.
    public var failed: [String] = []
    public init() {}
    /// Whether uninstall keeps the stills and the memory of the user's wallpaper.
    public var keepsRecovery: Bool { false }
    /// What uninstall says about the wallpaper, if anything.
    public func uninstallNote(stillsFolder: URL) -> String? { nil }
}

/// Changes and restores the system wallpaper through `DesktopImages`, keeping `WallpaperMemory` on disk (`save`).
/// The app renders the stills; this decides where they go, what they cover and what comes back.
public final class WallpaperKeeper {
    public static let keepStills = 3
    /// How a still is shown: scale proportionally up or down (NSImageScaling 3), clipping allowed, black fill.
    public static func stillEntry(_ url: URL) -> WallpaperEntry {
        WallpaperEntry(url: url, scaling: 3, allowClipping: true, fillColor: [0, 0, 0, 1])
    }

    public private(set) var memory: WallpaperMemory
    public let stillsFolder: URL
    public let foreign: ForeignStills
    private let desktop: DesktopImages
    private let save: (WallpaperMemory) -> Void
    private let log: (String) -> Void

    public init(memory: WallpaperMemory, stillsFolder: URL, foreign: ForeignStills = ForeignStills(folder: URL(fileURLWithPath: "/nonexistent")),
                desktop: DesktopImages, save: @escaping (WallpaperMemory) -> Void = { _ in },
                log: @escaping (String) -> Void = { _ in }) {
        self.memory = memory
        self.stillsFolder = stillsFolder
        self.foreign = foreign
        self.desktop = desktop
        self.save = save
        self.log = log
    }

    /// Before rendering: may a still replace what this display shows? The original is saved before anything changes.
    public func mayApply(on display: String) -> Bool {
        guard let current = desktop.current(on: display) else { return false }
        let ok: Bool = memory.decide(screen: display, current: current, stillsFolder: stillsFolder, foreign: foreign) == .apply
        if ok { save(memory) }
        return ok
    }

    /// Where the next still for this display is written.
    public func newStill(for display: String) -> URL {
        stillsFolder.appendingPathComponent("still-\(display)-\(Int(Date().timeIntervalSince1970 * 1000)).png")
    }

    /// The still is written: put it up if it still may replace what the display shows. Returns whether it went up.
    @discardableResult
    public func commit(_ still: URL, on display: String) -> Bool {
        // Re-check: the wallpaper may have changed, or the display gone, while the still rendered.
        guard desktop.displays.contains(display), let current = desktop.current(on: display),
              memory.decide(screen: display, current: current, stillsFolder: stillsFolder, foreign: foreign) == .apply else {
            try? desktop.removeFile(still)
            return false
        }
        do {
            try desktop.set(WallpaperKeeper.stillEntry(still), on: display)
        } catch {
            log("could not set wallpaper: \(error)")
        }
        prune(display: display, keep: still)
        return true
    }

    /// Keep the newest few stills per display; never the one in use.
    private func prune(display: String, keep: URL) {
        let mine: [URL] = desktop.stillFiles()
            .filter { $0.lastPathComponent.hasPrefix("still-\(display)-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in mine.dropFirst(WallpaperKeeper.keepStills) where old != keep {
            try? desktop.removeFile(old)
        }
    }

    /// Put each display's own wallpaper back wherever our still is showing.
    @discardableResult
    public func restoreAll() -> RestoreOutcome {
        var out = RestoreOutcome()
        for display in desktop.displays {
            guard let current = desktop.current(on: display),
                  let target = memory.restoreTarget(screen: display, current: current, stillsFolder: stillsFolder, foreign: foreign) else { continue }
            do {
                try desktop.set(target, on: display)
                memory.forget(screen: display)
                out.restored.append(display)
            } catch {
                log("could not restore wallpaper: \(error)")
                out.failed.append(display)
            }
        }
        save(memory)
        return out
    }

    /// A display came back, the Space changed or the Mac woke. Nothing happens here today when matching is off;
    /// when it's on, the app makes a fresh still.
    @discardableResult
    public func reconcile(matching: Bool) -> RestoreOutcome? { nil }
}
