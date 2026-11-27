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

/// ASCII Sharks' stills (its own folder), still showing if it was force-quit, and its memory: the original it saved
/// for each display, which its stills go back to. Never the user's own wallpaper.
public struct ForeignStills: Equatable, Sendable {
    public var folder: URL
    public var memory: WallpaperMemory
    public init(folder: URL, memory: WallpaperMemory = WallpaperMemory()) {
        self.folder = folder
        self.memory = memory
    }

    func contains(_ url: URL) -> Bool { WallpaperMemory.isOurs(url, stillsFolder: folder) }
}

/// What the Space in view on a display shows, as the wallpaper keeper reads it.
public enum Showing: Equatable, Sendable {
    /// Anything outside our folders: the person's own wallpaper.
    case own(WallpaperEntry)
    /// One of our files, `<display>-<code>-<A|B>.png`: it covers the wallpaper with that code.
    case ours(display: String, code: String, slot: String)
    /// A still from 3.0 (`still-…` in our folder) or from ASCII Sharks (its folder): it goes back to the original
    /// saved for the display it shows on.
    case old(sharks: Bool)
    /// Some other file in our folder: nothing known.
    case unknown
}

/// What keeps the person's own wallpaper safe while the system wallpaper shows a still of the habitat.
///
/// A file in our folder is ours; anything else is the person's. Each of our files names the wallpaper it covers by a
/// code, and `covered` maps the code back to that wallpaper (URL and options): no per-still records. macOS sets
/// wallpapers per Space and offers no Space identity, so whatever a Space shows says what goes back there.
public struct WallpaperMemory: Codable, Equatable, Sendable {
    /// The person's wallpapers our files cover, by the code in their names. Never shrinks: a Space not in view may
    /// still show a file with any of these codes.
    public private(set) var covered: [String: WallpaperEntry] = [:]
    /// Each display's own wallpaper as last seen on a Space in view (its code).
    public private(set) var own: [String: String] = [:]
    /// The original 3.0 (or ASCII Sharks) saved for each display: what their stills go back to. Never changed.
    public private(set) var saved: [String: WallpaperEntry] = [:]

    /// `originals` is 3.0's key (and ASCII Sharks'), kept so a memory written by 3.0 reads as its saved originals.
    enum CodingKeys: String, CodingKey { case covered, own, saved = "originals" }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        covered = try c.decodeIfPresent([String: WallpaperEntry].self, forKey: .covered) ?? [:]
        own = try c.decodeIfPresent([String: String].self, forKey: .own) ?? [:]
        saved = try c.decodeIfPresent([String: WallpaperEntry].self, forKey: .saved) ?? [:]
    }

    /// ASCII Sharks' memory with an earlier copy filling the displays it no longer remembers (its quit forgets the
    /// display in view): this memory's own saved original wins where both have one.
    public func fillingSaved(from earlier: WallpaperMemory) -> WallpaperMemory {
        var m: WallpaperMemory = self
        m.saved.merge(earlier.saved) { mine, _ in mine }
        return m
    }

    /// The display's own wallpaper: as last seen there, else the one 3.0 saved.
    public func original(for display: String) -> WallpaperEntry? {
        own[display].flatMap { covered[$0] } ?? saved[display]
    }

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

    // MARK: names

    /// The code for a wallpaper: 16 hex digits of an FNV-1a hash of its URL and options. The same wallpaper always
    /// gets the same code, so a lost table can't make a file name point at another picture.
    public static func code(for entry: WallpaperEntry) -> String {
        let fill: String = entry.fillColor.map { $0.map { String($0) }.joined(separator: ",") } ?? "-"
        let key: String = "\(entry.url.standardizedFileURL.absoluteString)|\(entry.scaling.map { String($0) } ?? "-")|"
            + "\(entry.allowClipping.map { $0 ? "1" : "0" } ?? "-")|\(fill)"
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex: String = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// `<display>-<code>-<A|B>.png`.
    public static func fileName(display: String, code: String, slot: String) -> String { "\(display)-\(code)-\(slot).png" }

    /// The display, code and slot in one of our file names; nil for any other name.
    static func parse(_ name: String) -> (display: String, code: String, slot: String)? {
        guard name.hasSuffix(".png") else { return nil }
        let parts: [Substring] = name.dropLast(4).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 3, let slot = parts.last, slot == "A" || slot == "B" else { return nil }
        let code: Substring = parts[parts.count - 2]
        guard code.count == 16, code.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        let display: String = parts.dropLast(2).joined(separator: "-")
        return display.isEmpty ? nil : (display, String(code), String(slot))
    }

    // MARK: rules

    /// What `current` is.
    public static func showing(_ current: WallpaperEntry, stillsFolder: URL, foreign: ForeignStills? = nil) -> Showing {
        let name: String = current.url.lastPathComponent
        if isOurs(current.url, stillsFolder: stillsFolder) {
            if let p = parse(name) { return .ours(display: p.display, code: p.code, slot: p.slot) }
            if name.hasPrefix("still-") { return .old(sharks: false) }
            return .unknown
        }
        if let foreign, foreign.contains(current.url) { return .old(sharks: true) }
        return .own(current)
    }

    /// The person's wallpaper under a still this display shows (ours, 3.0's or Sharks'): nil when not known.
    /// Also nil for the person's own wallpaper: check `showing` first.
    public func under(_ current: WallpaperEntry, on display: String, stillsFolder: URL,
                      foreign: ForeignStills? = nil) -> WallpaperEntry? {
        switch WallpaperMemory.showing(current, stillsFolder: stillsFolder, foreign: foreign) {
        case .own, .unknown:
            return nil
        case let .ours(_, code, _):
            return covered[code]
        case let .old(sharks):
            return sharks ? foreign?.memory.saved[display] : saved[display]
        }
    }

    /// The file a refresh writes for this display over `current`: the A or B of the wallpaper it covers, whichever
    /// isn't showing on the Space in view. The person's own wallpaper is remembered first (its code). Nil: leave it
    /// (a still with nothing known under it).
    public mutating func nextStill(on display: String, over current: WallpaperEntry, stillsFolder: URL,
                                   foreign: ForeignStills? = nil) -> URL? {
        let shows: Showing = WallpaperMemory.showing(current, stillsFolder: stillsFolder, foreign: foreign)
        let code: String
        var slot: String = "A"
        switch shows {
        case .unknown:
            return nil
        case let .own(entry):
            code = WallpaperMemory.code(for: entry)
            covered[code] = entry
            own[display] = code
        case let .ours(shownDisplay, shownCode, shownSlot):
            code = shownCode
            if shownDisplay == display, shownSlot == "A" { slot = "B" }
        case .old:
            guard let entry = under(current, on: display, stillsFolder: stillsFolder, foreign: foreign) else { return nil }
            code = WallpaperMemory.code(for: entry)
            covered[code] = entry
        }
        return stillsFolder.appendingPathComponent(WallpaperMemory.fileName(display: display, code: code, slot: slot))
    }
}

/// The desktop-image API as the wallpaper keeper sees it: NSWorkspace in the app, a fake with Spaces in the checks.
/// Displays are named by `SystemWallpaper.key(for:)`; each call reads or changes the Space in view.
public protocol DesktopImages: AnyObject {
    /// The displays attached now.
    var displays: [String] { get }
    /// What the display shows on the Space in view; nil when it can't be read.
    func current(on display: String) -> WallpaperEntry?
    /// Shows `entry` on the display's Space in view.
    func set(_ entry: WallpaperEntry, on display: String) throws
}

/// What a restore did on the Spaces in view.
public struct RestoreOutcome: Equatable, Sendable {
    /// Displays whose own picture went back (read back and checked).
    public var restored: [String] = []
    /// Displays where it couldn't be put back, couldn't be read (one we covered), or nothing is known under the still.
    public var failed: [String] = []
    public init() {}

    /// Something on a Space in view isn't back, so the Stills folder must stay. Uninstall keeps the folder anyway
    /// whenever it holds files: a Space not in view may show one.
    public var keepsRecovery: Bool { !failed.isEmpty }
}

/// Changes and restores the system wallpaper through `DesktopImages`, keeping `WallpaperMemory` on disk (`save`).
/// The app renders the stills; this picks their files, puts them up and puts the person's wallpaper back. Two files
/// per display per covered wallpaper, written in turn and reused: no file is ever deleted, so a Space not in view
/// never loses its picture (at worst it shows a newer still of the animals).
public final class WallpaperKeeper {
    /// How a still is shown: scale proportionally up or down (NSImageScaling 3), clipping allowed, black fill.
    public static func stillEntry(_ url: URL) -> WallpaperEntry {
        WallpaperEntry(url: url, scaling: 3, allowClipping: true, fillColor: [0, 0, 0, 1])
    }

    /// What uninstall says when it keeps the Stills folder (the director's words, briefs/r2.md).
    public static func uninstallNote(stillsFolder: URL) -> String {
        let folder: String = (stillsFolder.path as NSString).abbreviatingWithTildeInPath
        return "If a desktop still shows the animals, choose your wallpaper in System Settings, then delete this folder: \(folder)."
    }

    public private(set) var memory: WallpaperMemory
    public let stillsFolder: URL
    public let foreign: ForeignStills
    private let desktop: DesktopImages
    private let save: (WallpaperMemory) -> Void
    private let log: (String) -> Void
    /// The file planned for each display by `mayApply`, while it renders.
    private var planned: [String: URL] = [:]
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
    }

    /// Uninstall began: no still goes up and nothing reconciles from now on; only its own restore runs.
    public func beginUninstall() { uninstalling = true }

    /// The file to write over what the display shows now, with the person's wallpaper (its code) saved first.
    private func plan(on display: String) -> URL? {
        guard let current = desktop.current(on: display) else { return nil }   // a failed read: do nothing
        var m: WallpaperMemory = memory
        guard let file = m.nextStill(on: display, over: current, stillsFolder: stillsFolder, foreign: foreign) else { return nil }
        if m != memory {
            memory = m
            save(memory)
        }
        return file
    }

    /// Before rendering: may a still go up on this display's Space in view? Plans its file (`newStill`).
    public func mayApply(on display: String) -> Bool {
        planned[display] = uninstalling ? nil : plan(on: display)
        return planned[display] != nil
    }

    /// The file the next still for this display is written to (after `mayApply` said yes): `<display>-<code>-A.png`
    /// or `-B.png`, whichever isn't showing on the Space in view.
    public func newStill(for display: String) -> URL {
        planned[display] ?? stillsFolder.appendingPathComponent(".unplanned-\(display).png")
    }

    /// A still that won't go up (superseded, or its render failed). Its file stays: it is one of the two.
    public func discard(_ still: URL) {
        planned = planned.filter { !WallpaperMemory.same($0.value, still) }
    }

    /// The still is written: put it up if it is still the file to show on this display. Returns whether it is up.
    @discardableResult
    public func commit(_ still: URL, on display: String) -> Bool {
        discard(still)
        // Re-check: the picture may have changed, or the display gone, while the still rendered.
        guard !uninstalling, desktop.displays.contains(display), let file = plan(on: display),
              WallpaperMemory.same(file, still) else { return false }
        do {
            try desktop.set(WallpaperKeeper.stillEntry(still), on: display)
        } catch {
            log("setting the wallpaper threw: \(error)")   // it may have taken effect anyway: what reads back says
        }
        guard let now = desktop.current(on: display) else {
            log("could not read the wallpaper back")
            return false
        }
        return WallpaperMemory.same(now.url, still)
    }

    /// Put the person's wallpaper back on each display's Space in view, wherever a still (ours, 3.0's or Sharks')
    /// shows. Counts only what reads back. A Space not in view gets its own back on its next visit (`reconcile`).
    @discardableResult
    public func restoreAll() -> RestoreOutcome {
        var out = RestoreOutcome()
        for display in desktop.displays {
            guard let current = desktop.current(on: display) else {
                // A failed read: do nothing. If we ever covered this display, it may show our still.
                if memory.original(for: display) != nil {
                    out.failed.append(display)
                    log("could not read the wallpaper of a display we covered")
                }
                continue
            }
            if case .own = WallpaperMemory.showing(current, stillsFolder: stillsFolder, foreign: foreign) { continue }
            guard let target = memory.under(current, on: display, stillsFolder: stillsFolder, foreign: foreign) else {
                out.failed.append(display)
                log("no wallpaper known under a still")
                continue
            }
            do {
                try desktop.set(target, on: display)
            } catch {
                log("restoring the wallpaper threw: \(error)")   // what reads back says
            }
            guard let now = desktop.current(on: display), WallpaperMemory.same(now.url, target.url) else {
                log("restored wallpaper did not read back")
                out.failed.append(display)
                continue
            }
            out.restored.append(display)
        }
        return out
    }

    /// A display came back, the Space changed, the Mac woke or the app launched. With matching off, a still on the
    /// Space in view gives way to the person's own wallpaper; with it on, nothing here (the app sets a still only on
    /// launch, a look change, a theme or accent change or a display change).
    @discardableResult
    public func reconcile(matching: Bool) -> RestoreOutcome? {
        guard !uninstalling, !matching else { return nil }
        return restoreAll()
    }
}

// MARK: restore data on disk (briefs/r2.md, "Fix round")

/// What puts the person's wallpaper back under the stills: our memory, and ASCII Sharks' saved originals (its own
/// memory, or the hand-over's copy once Sharks is gone). It lives in the settings; uninstall leaves it in the Stills
/// folder (`restore.json`) beside the stills it describes, so a reinstall can still put back what a Space shows.
public struct RestoreData: Codable, Equatable, Sendable {
    public var memory: WallpaperMemory
    public var sharks: WallpaperMemory?
    public init(memory: WallpaperMemory = WallpaperMemory(), sharks: WallpaperMemory? = nil) {
        self.memory = memory
        self.sharks = sharks
    }

    /// ASCII Sharks' memory as read now, with the hand-over's earlier copy for the displays Sharks forgot since (its
    /// quit forgets the display in view). Either alone when the other is missing or unreadable.
    public static func sharksCopy(current: Data?, copy: Data?) -> Data? {
        func decode(_ data: Data?) -> WallpaperMemory? { data.flatMap { try? JSONDecoder().decode(WallpaperMemory.self, from: $0) } }
        guard let now = decode(current) else { return decode(copy) != nil ? copy : current }
        guard let kept = decode(copy) else { return current }
        return (try? JSONEncoder().encode(now.fillingSaved(from: kept))) ?? current
    }

    /// The file in the Stills folder.
    public static let fileName = "restore.json"

    /// The restore data uninstall left in the Stills folder; nil when there is none or it can't be read.
    public static func read(in stillsFolder: URL) -> RestoreData? {
        guard let data = try? Data(contentsOf: stillsFolder.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(RestoreData.self, from: data)
    }

    /// Writes it into the Stills folder (made if missing), whole or not at all.
    public func write(in stillsFolder: URL) throws {
        try FileManager.default.createDirectory(at: stillsFolder, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: stillsFolder.appendingPathComponent(RestoreData.fileName), options: .atomic)
    }

    /// What the app starts from: the settings' memory, else what uninstall left in the Stills folder; Sharks' own
    /// memory, with the hand-over's copy for the displays it forgot (`sharksCopy(current:copy:)`), else the folder's.
    public static func resolve(settings: Data?, sharksOwn: Data?, sharksCopy: Data?, stillsFolder: URL) -> RestoreData {
        func decode(_ data: Data?) -> WallpaperMemory? { data.flatMap { try? JSONDecoder().decode(WallpaperMemory.self, from: $0) } }
        let file: RestoreData? = (decode(settings) == nil || decode(sharksOwn ?? sharksCopy) == nil) ? read(in: stillsFolder) : nil
        let memory: WallpaperMemory = decode(settings) ?? file?.memory ?? WallpaperMemory()
        let sharks: WallpaperMemory? = decode(RestoreData.sharksCopy(current: sharksOwn, copy: sharksCopy)) ?? file?.sharks
        return RestoreData(memory: memory, sharks: sharks)
    }

    /// What uninstall keeps for the stills it leaves on disk.
    public struct Kept: Equatable, Sendable {
        /// The Stills folder stays.
        public var folder: Bool
        /// The restore data is in the folder.
        public var written: Bool
        /// The restore data couldn't go into the folder, so the settings keep it.
        public var keepsSettings: Bool
        public init(folder: Bool, written: Bool, keepsSettings: Bool) {
            self.folder = folder
            self.written = written
            self.keepsSettings = keepsSettings
        }
    }

    /// Uninstall: the Stills folder stays while a Space may show a still it can put back (one in our folder, or one
    /// can't tell because the folder can't be read; or an ASCII Sharks still with Sharks' originals known), and the
    /// restore data goes into it, also when the restore failed. If it can't be written there, the settings keep it.
    public func keepOnUninstall(stillsFolder: URL, sharksStills: URL) -> Kept {
        let fm: FileManager = .default
        let ours: [String]? = try? fm.contentsOfDirectory(atPath: stillsFolder.path)
        let oursShown: Bool = ours.map { $0.contains { $0 != RestoreData.fileName } } ?? fm.fileExists(atPath: stillsFolder.path)
        let theirs: [String]? = try? fm.contentsOfDirectory(atPath: sharksStills.path)
        let theirsShown: Bool = sharks != nil && (theirs.map { !$0.isEmpty } ?? fm.fileExists(atPath: sharksStills.path))
        guard oursShown || theirsShown else { return Kept(folder: false, written: false, keepsSettings: false) }
        let written: Bool = (try? write(in: stillsFolder)) != nil
        return Kept(folder: true, written: written, keepsSettings: !written)
    }
}

/// Asking a running ASCII Sharks to quit at the hand-over. Its quit restores the Space in view and forgets that
/// display's saved original, while a Space not in view may still show one of its stills: its originals are kept
/// first, as the hand-over's copy.
public enum SharksQuit {
    /// Reads Sharks' wallpaper memory (`memory`), keeps it with the hand-over's copy so far (`copy`) as the new copy
    /// (`keepCopy`), then asks Sharks to quit (`quit`).
    public static func run(memory: () -> Data?, copy: Data?, keepCopy: (Data) -> Void, quit: () -> Void) {
        if let kept = RestoreData.sharksCopy(current: memory(), copy: copy) { keepCopy(kept) }
        quit()
    }
}

/// Removing ASCII Sharks once the person accepts the hand-over's offer. Sharks' own uninstaller deletes its whole
/// support folder, stills included, while a Space not in view may still show one: they are copied aside first and
/// any that went are put back at their old paths, where the wallpaper keeper restores them to Sharks' saved original
/// on a visit.
public enum SharksRemoval {
    /// Keeps a copy of Sharks' wallpaper memory (`keepCopy`), with the hand-over's copy so far (`copy`, taken before
    /// Sharks quit) for the displays it forgot, sets its stills aside in `aside`, runs Sharks' own uninstaller
    /// (`uninstall`, true when it finished) and puts back every still it removed. Returns `uninstall`'s answer.
    public static func run(sharksMemory: Data?, copy: Data? = nil, sharksStills: URL, aside: URL, keepCopy: (Data) -> Void,
                           log: (String) -> Void = { _ in }, uninstall: () -> Bool) -> Bool {
        if let kept = RestoreData.sharksCopy(current: sharksMemory, copy: copy) { keepCopy(kept) }
        let fm: FileManager = .default
        let names: [String] = (try? fm.contentsOfDirectory(atPath: sharksStills.path)) ?? []
        var setAside: [String] = []
        if !names.isEmpty {
            try? fm.removeItem(at: aside)
            do {
                try fm.createDirectory(at: aside, withIntermediateDirectories: true)
                for name in names {
                    do {
                        try fm.copyItem(at: sharksStills.appendingPathComponent(name), to: aside.appendingPathComponent(name))
                        setAside.append(name)
                    } catch { log("could not set aside an ASCII Sharks still: \(error.localizedDescription)") }
                }
            } catch { log("could not set ASCII Sharks' stills aside: \(error.localizedDescription)") }
        }
        let finished: Bool = uninstall()
        guard !setAside.isEmpty else { return finished }
        var notBack: Int = 0
        for name in setAside where !fm.fileExists(atPath: sharksStills.appendingPathComponent(name).path) {
            do {
                try fm.createDirectory(at: sharksStills, withIntermediateDirectories: true)
                try fm.moveItem(at: aside.appendingPathComponent(name), to: sharksStills.appendingPathComponent(name))
            } catch {
                notBack += 1
                log("could not put an ASCII Sharks still back: \(error.localizedDescription)")
            }
        }
        if notBack == 0 { try? fm.removeItem(at: aside) }   // else the copies stay in the Stills folder, which uninstall keeps
        return finished
    }
}
