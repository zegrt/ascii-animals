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
