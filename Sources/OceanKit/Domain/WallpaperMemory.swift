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

/// One of our stills that went up on a display's Space, and the picture it covers there (the user's own).
public struct StillRecord: Codable, Equatable, Sendable {
    /// The display it went up on ("" for a still found on disk from before these records).
    public var display: String
    /// What to put back over it; nil when nobody knows (a foreign still with no memory under it).
    public var covers: WallpaperEntry?
    public init(display: String, covers: WallpaperEntry?) {
        self.display = display
        self.covers = covers
    }
}

/// Bookkeeping that keeps the user's own wallpaper safe while the system
/// wallpaper shows a still of the ocean.
///
/// macOS sets wallpapers per Space and offers no Space identity, so the rules
/// are conservative: remember the first wallpaper seen on each screen; replace
/// only that wallpaper or our own stills; never touch a wallpaper we don't
/// recognise; restore only where our still is showing. Each still that went up
/// is recorded with the picture it covers, so a Space restored later gets its
/// own picture back, however many restores happened in between.
public struct WallpaperMemory: Codable, Equatable, Sendable {
    public enum Decision: Equatable, Sendable { case apply, leaveAlone }

    /// The user's own picture on each display: what `decide` recognises. Recorded once; a restore keeps it.
    public private(set) var originals: [String: WallpaperEntry] = [:]
    /// Our stills that are up on some Space, by filename: never deleted while recorded.
    public private(set) var stills: [String: StillRecord] = [:]
    /// Displays whose own picture went back since their last still: a different picture seen there next is the
    /// user's new choice.
    public private(set) var restored: Set<String> = []
    /// Read from a memory written before still records: the stills on disk may be up somewhere, unrecorded.
    public private(set) var predatesStillRecords = false

    enum CodingKeys: String, CodingKey { case originals, stills, restored }

    public init() {}

    /// A memory that knows nothing yet, so the stills already on disk are taken as up somewhere (`adopt`).
    public static func unrecorded() -> WallpaperMemory {
        var m = WallpaperMemory()
        m.predatesStillRecords = true
        return m
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        originals = try c.decode([String: WallpaperEntry].self, forKey: .originals)
        let recorded: [String: StillRecord]? = try c.decodeIfPresent([String: StillRecord].self, forKey: .stills)
        stills = recorded ?? [:]
        restored = try c.decodeIfPresent(Set<String>.self, forKey: .restored) ?? []
        predatesStillRecords = recorded == nil
    }

    public func original(for screen: String) -> WallpaperEntry? { originals[screen] }

    public static func isOurs(_ url: URL, stillsFolder: URL) -> Bool {
        let folder = canonical(stillsFolder.path)
        return canonical(url.path).hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    /// Whether two URLs name the same file (symlinks resolved).
    public static func same(_ a: URL, _ b: URL) -> Bool { canonical(a.path) == canonical(b.path) }

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
        if known.url.standardizedFileURL == current.url.standardizedFileURL { return .apply }
        // Put back, then changed by the user: their new choice. Stills still up elsewhere keep what they cover.
        guard restored.contains(screen) else { return .leaveAlone }
        originals[screen] = current
        restored.remove(screen)
        return .apply
    }

    /// The wallpaper to put back, if our still (or a foreign one) is what this screen shows.
    public func restoreTarget(screen: String, current: WallpaperEntry, stillsFolder: URL,
                              foreign: ForeignStills? = nil) -> WallpaperEntry? {
        if WallpaperMemory.isOurs(current.url, stillsFolder: stillsFolder) {
            return stills[current.url.lastPathComponent]?.covers ?? originals[screen]
        }
        if let foreign, foreign.contains(current.url) { return originals[screen] ?? foreign.memory.original(for: screen) }
        return nil
    }

    /// The screen's own picture went back. The original stays: stills on other Spaces still cover it.
    public mutating func forget(screen: String) { restored.insert(screen) }

    /// `still` is going up over `current`: record what it covers (what our still under it covered, never our still).
    public mutating func record(_ still: URL, on screen: String, over current: WallpaperEntry, stillsFolder: URL,
                                foreign: ForeignStills? = nil) {
        let covers: WallpaperEntry?
        if WallpaperMemory.isOurs(current.url, stillsFolder: stillsFolder) {
            covers = stills[current.url.lastPathComponent]?.covers ?? originals[screen]
        } else if let foreign, foreign.contains(current.url) {
            covers = originals[screen] ?? foreign.memory.original(for: screen)
        } else {
            covers = current
        }
        stills[still.lastPathComponent] = StillRecord(display: screen, covers: covers)
    }

    /// The still is no longer up anywhere.
    public mutating func drop(_ still: URL) { stills[still.lastPathComponent] = nil }

    /// The still went up on the screen: it isn't showing its own picture now.
    public mutating func shown(on screen: String) { restored.remove(screen) }

    /// Stills found on disk with no record (from before the records): taken as up somewhere, so never deleted.
    public mutating func adopt(_ files: [URL]) {
        for f in files where f.lastPathComponent.hasPrefix("still-") && stills[f.lastPathComponent] == nil {
            stills[f.lastPathComponent] = StillRecord(display: "", covers: nil)
        }
        predatesStillRecords = false
    }
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
    /// Displays whose own picture went back (read back and checked).
    public var restored: [String] = []
    /// Displays where it couldn't be put back, or couldn't be read.
    public var failed: [String] = []
    /// Our stills still up somewhere: a Space not in view, a display not connected, a display that failed.
    public var stillsLeft = 0
    /// The user's own pictures (file names) not back everywhere.
    public var notBack: [String] = []
    public init() {}

    /// Whether uninstall keeps the stills and the memory of the user's wallpaper: anything not verified back.
    public var keepsRecovery: Bool { !failed.isEmpty || stillsLeft > 0 }

    /// What uninstall says about the wallpaper, if anything.
    public func uninstallNote(stillsFolder: URL) -> String? {
        guard keepsRecovery else { return nil }
        let folder: String = (stillsFolder.path as NSString).abbreviatingWithTildeInPath
        let yours: String = notBack.isEmpty ? "" : " (yours was \(notBack.joined(separator: ", ")))"
        return "Your own wallpaper couldn't be put back everywhere: a display that failed or isn't connected now, or a "
            + "Space not in view, may still show ASCII Animals' picture. Its pictures are kept in \(folder), so nothing "
            + "goes blank. Choose your wallpaper in System Settings > Wallpaper\(yours), then you can delete that folder."
    }
}

/// Changes and restores the system wallpaper through `DesktopImages`, keeping `WallpaperMemory` on disk (`save`).
/// The app renders the stills; this decides where they go, what they cover and what comes back. Every set and
/// restore is read back before it counts; a still is deleted only once nothing shows it.
public final class WallpaperKeeper {
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
    /// Stills named but not yet up or dropped (rendering): pruning leaves them.
    private var inFlight: Set<String> = []

    public init(memory: WallpaperMemory, stillsFolder: URL, foreign: ForeignStills = ForeignStills(folder: URL(fileURLWithPath: "/nonexistent")),
                desktop: DesktopImages, save: @escaping (WallpaperMemory) -> Void = { _ in },
                log: @escaping (String) -> Void = { _ in }) {
        self.memory = memory
        self.stillsFolder = stillsFolder
        self.foreign = foreign
        self.desktop = desktop
        self.save = save
        self.log = log
        if memory.predatesStillRecords {
            self.memory.adopt(desktop.stillFiles())
            save(self.memory)
        }
    }

    /// Before rendering: may a still replace what this display shows? The original is saved before anything changes.
    public func mayApply(on display: String) -> Bool {
        guard let current = desktop.current(on: display) else { return false }
        let ok: Bool = memory.decide(screen: display, current: current, stillsFolder: stillsFolder, foreign: foreign) == .apply
        if ok { save(memory) }
        return ok
    }

    /// Where the next still for this display is written: a name of its own, whatever the clock says.
    public func newStill(for display: String) -> URL {
        let name = "still-\(display)-\(UUID().uuidString).png"
        inFlight.insert(name)
        return stillsFolder.appendingPathComponent(name)
    }

    /// A still that won't go up (superseded, or its render failed).
    public func discard(_ still: URL) {
        inFlight.remove(still.lastPathComponent)
        if memory.stills[still.lastPathComponent] == nil { try? desktop.removeFile(still) }
    }

    /// The still is written: put it up if it still may replace what the display shows. Returns whether it is up.
    @discardableResult
    public func commit(_ still: URL, on display: String) -> Bool {
        inFlight.remove(still.lastPathComponent)
        // Re-check: the wallpaper may have changed, or the display gone, while the still rendered.
        let written: Bool = desktop.stillFiles().contains { WallpaperMemory.same($0, still) }
        guard written, desktop.displays.contains(display), let current = desktop.current(on: display),
              memory.decide(screen: display, current: current, stillsFolder: stillsFolder, foreign: foreign) == .apply else {
            discard(still)
            return false
        }
        // Recorded before it goes up, so a quit or a crash mid-set still knows what it covers.
        memory.record(still, on: display, over: current, stillsFolder: stillsFolder, foreign: foreign)
        save(memory)
        do {
            try desktop.set(WallpaperKeeper.stillEntry(still), on: display)
        } catch {
            log("could not set wallpaper: \(error)")
            memory.drop(still)
            save(memory)
            discard(still)
            return false
        }
        guard let now = desktop.current(on: display) else {
            log("could not read the wallpaper back; keeping the still and its record")
            return false
        }
        guard WallpaperMemory.same(now.url, still) else {
            log("the wallpaper did not change")
            memory.drop(still)
            save(memory)
            discard(still)
            return false
        }
        // The still it replaced on this Space is no longer shown anywhere.
        if WallpaperMemory.isOurs(current.url, stillsFolder: stillsFolder), !WallpaperMemory.same(current.url, still) {
            memory.drop(current.url)
        }
        memory.shown(on: display)
        save(memory)
        prune(display: display, keep: still)
        return true
    }

    /// Delete this display's stills that nothing shows: not recorded as up, not rendering, not the new one.
    private func prune(display: String, keep: URL) {
        for file in desktop.stillFiles() where file.lastPathComponent.hasPrefix("still-\(display)-") {
            let name = file.lastPathComponent
            guard memory.stills[name] == nil, !inFlight.contains(name), !WallpaperMemory.same(file, keep) else { continue }
            try? desktop.removeFile(file)
        }
    }

    /// Put each display's own wallpaper back wherever our still is showing. Counts only what reads back; a still
    /// and its record stay until then.
    @discardableResult
    public func restoreAll() -> RestoreOutcome {
        let before: WallpaperMemory = memory
        var out = RestoreOutcome()
        var notBack: Set<String> = []
        for display in desktop.displays {
            guard let current = desktop.current(on: display) else {
                // Can't tell what it shows; if we ever changed it, it may be our still.
                if let o = memory.original(for: display) {
                    out.failed.append(display)
                    notBack.insert(o.url.lastPathComponent)
                    log("could not read the wallpaper of a display we changed")
                }
                continue
            }
            let ours: Bool = WallpaperMemory.isOurs(current.url, stillsFolder: stillsFolder)
            guard ours || foreign.contains(current.url) else { continue }   // the user's own: never touched
            guard let target = memory.restoreTarget(screen: display, current: current, stillsFolder: stillsFolder, foreign: foreign) else {
                out.failed.append(display)
                log("no original known under a still")
                continue
            }
            do {
                try desktop.set(target, on: display)
            } catch {
                log("could not restore wallpaper: \(error)")
                out.failed.append(display)
                notBack.insert(target.url.lastPathComponent)
                continue
            }
            guard let now = desktop.current(on: display), WallpaperMemory.same(now.url, target.url) else {
                log("restored wallpaper did not read back")
                out.failed.append(display)
                notBack.insert(target.url.lastPathComponent)
                continue
            }
            memory.forget(screen: display)
            out.restored.append(display)
            if ours {
                memory.drop(current.url)
                try? desktop.removeFile(current.url)
            }
        }
        for record in memory.stills.values {
            if let c = record.covers { notBack.insert(c.url.lastPathComponent) }
        }
        out.stillsLeft = memory.stills.count
        out.notBack = notBack.sorted()
        if memory != before { save(memory) }
        return out
    }

    /// A display came back, the Space changed, the Mac woke or the app launched. With matching off, our still is
    /// replaced by the user's own picture wherever it shows; with it on, the app makes a fresh still instead.
    @discardableResult
    public func reconcile(matching: Bool) -> RestoreOutcome? {
        matching ? nil : restoreAll()
    }
}
