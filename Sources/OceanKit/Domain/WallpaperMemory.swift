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
    /// The memory is the hand-over's copy: the other app's own went with it, so this is the only one left.
    public var memoryIsOurCopy: Bool
    public init(folder: URL, memory: WallpaperMemory = WallpaperMemory(), memoryIsOurCopy: Bool = false) {
        self.folder = folder
        self.memory = memory
        self.memoryIsOurCopy = memoryIsOurCopy
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
    /// Read from a memory written before still records, and the stills on disk not yet adopted (`adopt`; their
    /// folder may not have been readable): they may be up somewhere, unrecorded. Saved, so a relaunch retries.
    public private(set) var predatesStillRecords = false

    enum CodingKeys: String, CodingKey { case originals, stills, restored, adoptionPending }

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
        let pending: Bool = try c.decodeIfPresent(Bool.self, forKey: .adoptionPending) ?? false
        predatesStillRecords = recorded == nil || pending
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(originals, forKey: .originals)
        try c.encode(stills, forKey: .stills)
        try c.encode(restored, forKey: .restored)
        if predatesStillRecords { try c.encode(true, forKey: .adoptionPending) }
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
        if WallpaperMemory.isOurs(current.url, stillsFolder: stillsFolder) { return covered(by: current.url, on: screen) }
        if let foreign, foreign.contains(current.url) { return foreignOriginal(screen, foreign) }
        return nil
    }

    /// What our still covers: what its record says (nil: not known, so it stays up), or, with no record, the
    /// display's original.
    func covered(by still: URL, on screen: String) -> WallpaperEntry? {
        if let record = stills[still.lastPathComponent] { return record.covers }
        return originals[screen]
    }

    /// What the other app's still covers: what it remembered there, else the display's original here.
    func foreignOriginal(_ screen: String, _ foreign: ForeignStills) -> WallpaperEntry? {
        foreign.memory.original(for: screen) ?? originals[screen]
    }

    /// The screen's own picture went back. The original stays: stills on other Spaces still cover it.
    public mutating func forget(screen: String) { restored.insert(screen) }

    /// `still` is going up over `current`: record what it covers (what our still under it covered, never our still).
    public mutating func record(_ still: URL, on screen: String, over current: WallpaperEntry, stillsFolder: URL,
                                foreign: ForeignStills? = nil) {
        let covers: WallpaperEntry?
        if WallpaperMemory.isOurs(current.url, stillsFolder: stillsFolder) {
            covers = covered(by: current.url, on: screen)
        } else if let foreign, foreign.contains(current.url) {
            covers = foreignOriginal(screen, foreign)
        } else {
            covers = current
        }
        stills[still.lastPathComponent] = StillRecord(display: screen, covers: covers)
    }

    /// The still is no longer up anywhere.
    public mutating func drop(_ still: URL) { stills[still.lastPathComponent] = nil }

    /// The still went up on the screen: it isn't showing its own picture now.
    public mutating func shown(on screen: String) { restored.remove(screen) }

    /// Stills found on disk with no record (from before the records): taken as up somewhere, so never deleted, each
    /// with the original saved now for the display in its name (`still-<display>-…`); nil when none is known.
    public mutating func adopt(_ files: [URL], except names: Set<String> = []) {
        for f in files {
            let name: String = f.lastPathComponent
            guard name.hasPrefix("still-"), stills[name] == nil, !names.contains(name) else { continue }
            let display: String? = originals.keys.filter { name.hasPrefix("still-\($0)-") }.max { $0.count < $1.count }
            stills[name] = StillRecord(display: display ?? "", covers: display.flatMap { originals[$0] })
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
    /// The files in a stills folder (ours, or the other app's): empty only when it is readable and empty, or
    /// doesn't exist. Throws when it can't be read.
    func stillFiles(in folder: URL) throws -> [URL]
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
    /// The stills folder couldn't be read, so stills from before the records may be up, unrecorded.
    public var adoptionPending = false
    /// The other app's stills are on disk (or its folder can't be read) and its memory here is the only copy.
    public var foreignStillsLeft = false
    /// The user's own pictures (file names) not back everywhere.
    public var notBack: [String] = []
    public init() {}

    /// Whether uninstall keeps the stills and the memory of the user's wallpaper: anything not verified back.
    public var keepsRecovery: Bool { !failed.isEmpty || stillsLeft > 0 || adoptionPending || foreignStillsLeft }

    /// What uninstall says about the wallpaper, if anything.
    public func uninstallNote(stillsFolder: URL) -> String? {
        guard keepsRecovery else { return nil }
        let folder: String = (stillsFolder.path as NSString).abbreviatingWithTildeInPath
        let yours: String = notBack.isEmpty ? "" : " (yours was \(notBack.joined(separator: ", ")))"
        let whose: String = foreignStillsLeft ? "ASCII Animals' or ASCII Sharks' picture" : "ASCII Animals' picture"
        return "Your own wallpaper couldn't be put back everywhere: a display that failed or isn't connected now, or a "
            + "Space not in view, may still show \(whose). Its pictures are kept in \(folder), so nothing "
            + "goes blank. Choose your wallpaper in System Settings > Wallpaper\(yours), then you can delete that folder."
    }
}

/// Changes and restores the system wallpaper through `DesktopImages`, keeping `WallpaperMemory` on disk (`save`).
/// The app renders the stills; this decides where they go, what they cover and what comes back. Every set and
/// restore is read back before it counts, even one that threw. A still's file stays after it is replaced or put back
/// (one still might show on several Spaces); the files go once a restore has put everything back.
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
    /// Stills named but not yet up or dropped (rendering): cleanup and adoption leave them.
    private var inFlight: Set<String> = []
    /// Uninstall began: from now on only restores run.
    private var uninstalling = false

    public init(memory: WallpaperMemory, stillsFolder: URL, foreign: ForeignStills = ForeignStills(folder: URL(fileURLWithPath: "/nonexistent")),
                desktop: DesktopImages, save: @escaping (WallpaperMemory) -> Void = { _ in },
                log: @escaping (String) -> Void = { _ in }) {
        self.memory = memory
        self.stillsFolder = stillsFolder
        self.foreign = foreign
        self.desktop = desktop
        self.save = save
        self.log = log
        _ = adoptIfPending()
    }

    /// Takes the unrecorded stills on disk as up somewhere. Until their folder can be read, nothing changes
    /// (a failed read is not an empty folder); retried before every change and every restore.
    private func adoptIfPending() -> Bool {
        guard memory.predatesStillRecords else { return true }
        do {
            let files: [URL] = try desktop.stillFiles(in: stillsFolder)
            memory.adopt(files, except: inFlight)
            save(memory)
            return true
        } catch {
            log("could not read the stills folder; no still goes up until it can be read: \(error)")
            return false
        }
    }

    /// Uninstall began: no still goes up and nothing reconciles from now on; only its own restore runs.
    public func beginUninstall() { uninstalling = true }

    /// Before rendering: may a still replace what this display shows? The original is saved before anything changes.
    public func mayApply(on display: String) -> Bool {
        guard !uninstalling, adoptIfPending(), let current = desktop.current(on: display) else { return false }
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
        let written: Bool = ((try? desktop.stillFiles(in: stillsFolder)) ?? []).contains { WallpaperMemory.same($0, still) }
        guard !uninstalling, !memory.predatesStillRecords, written, desktop.displays.contains(display),
              let current = desktop.current(on: display),
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
            // It may have taken effect anyway: what reads back decides.
            log("setting the wallpaper threw: \(error)")
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
        // The still it replaced on this Space: its record goes, its file stays (it may show elsewhere).
        if WallpaperMemory.isOurs(current.url, stillsFolder: stillsFolder), !WallpaperMemory.same(current.url, still) {
            memory.drop(current.url)
        }
        memory.shown(on: display)
        save(memory)
        return true
    }

    /// Everything is back: delete the still files no record names (not the ones rendering).
    private func cleanUp() {
        guard let files = try? desktop.stillFiles(in: stillsFolder) else { return }
        for file in files {
            let name: String = file.lastPathComponent
            guard name.hasPrefix("still-"), memory.stills[name] == nil, !inFlight.contains(name) else { continue }
            try? desktop.removeFile(file)
        }
    }

    /// The other app's stills on disk, when its memory here is the only copy: still needed. An unreadable folder counts.
    private func foreignStillsOnDisk() -> Bool {
        guard foreign.memoryIsOurCopy else { return false }
        guard let files = try? desktop.stillFiles(in: foreign.folder) else { return true }
        return files.contains { $0.lastPathComponent.hasPrefix("still-") }
    }

    /// Put each display's own wallpaper back wherever our still is showing. Counts only what reads back; a still
    /// and its record stay until then.
    @discardableResult
    public func restoreAll() -> RestoreOutcome {
        let before: WallpaperMemory = memory
        var out = RestoreOutcome()
        var notBack: Set<String> = []
        out.adoptionPending = !adoptIfPending()
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
                log("restoring the wallpaper threw: \(error)")   // what reads back decides
            }
            guard let now = desktop.current(on: display), WallpaperMemory.same(now.url, target.url) else {
                log("restored wallpaper did not read back")
                out.failed.append(display)
                notBack.insert(target.url.lastPathComponent)
                continue
            }
            memory.forget(screen: display)
            out.restored.append(display)
            if ours { memory.drop(current.url) }   // its file stays until everything is back
        }
        for record in memory.stills.values {
            if let c = record.covers { notBack.insert(c.url.lastPathComponent) }
        }
        out.stillsLeft = memory.stills.count
        out.foreignStillsLeft = foreignStillsOnDisk()
        if out.foreignStillsLeft {
            for o in foreign.memory.originals.values { notBack.insert(o.url.lastPathComponent) }
        }
        out.notBack = notBack.sorted()
        if memory != before { save(memory) }
        if !out.keepsRecovery { cleanUp() }
        return out
    }

    /// A display came back, the Space changed, the Mac woke or the app launched. With matching off, our still is
    /// replaced by the user's own picture wherever it shows; with it on, the app makes a fresh still instead.
    @discardableResult
    public func reconcile(matching: Bool) -> RestoreOutcome? {
        guard !uninstalling, !matching else { return nil }
        return restoreAll()
    }
}
