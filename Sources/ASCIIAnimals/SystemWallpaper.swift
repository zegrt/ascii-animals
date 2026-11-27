import AppKit
import OceanKit

/// Shows a still of the ocean as the system wallpaper (lock screen, Mission
/// Control, menu-bar tint) and puts the user's own wallpaper back on quit.
/// The rules live in WallpaperKeeper and WallpaperMemory; this renders the stills and is their desktop. Two files
/// per display per covered wallpaper in the Stills folder, reused, never deleted.
final class SystemWallpaper {
    static let memoryKey = "wallpaperMemory.v1"
    /// The hand-over's copy of ASCII Sharks' wallpaper memory, taken before its uninstaller removes it.
    static let sharksMemoryCopyKey = "handover.sharksWallpaperMemory"

    let stillsFolder: URL
    private let renderer: OceanRenderer
    private let keeper: WallpaperKeeper
    private var pending: DispatchWorkItem?
    /// Bumped by restoreAll(); a still that finishes rendering after a restore is dropped.
    private var generation = 0
    /// Uninstall began: nothing is scheduled or reconciled any more.
    private var uninstalling = false
    private let work = DispatchQueue(label: "ascii-animals.stills", qos: .utility)

    /// Nil in the energy-test copy (`LaunchPlan.matchesSystemWallpaper`), before anything is read or made: no
    /// stills, no `wallpaperMemory.v1`, the system wallpaper never touched.
    init?(renderer: OceanRenderer) {
        guard Launch.plan.matchesSystemWallpaper else { return nil }
        self.renderer = renderer
        stillsFolder = SystemWallpaper.defaultStillsFolder
        try? FileManager.default.createDirectory(at: stillsFolder, withIntermediateDirectories: true)
        // ASCII Sharks' stills: one left up (Sharks force-quit) goes back to the original Sharks saved for its display
        // (its own memory, or the hand-over's copy once Sharks is gone).
        let data: RestoreData = SystemWallpaper.restoreData(stillsFolder: stillsFolder)
        let sharks = ForeignStills(folder: SystemWallpaper.sharksStillsFolder, memory: data.sharks ?? WallpaperMemory())
        keeper = WallpaperKeeper(memory: data.memory, stillsFolder: stillsFolder, foreign: sharks,
                                 desktop: Desktop(),
                                 save: { m in
                                     if let data = try? JSONEncoder().encode(m) {
                                         UserDefaults.standard.set(data, forKey: SystemWallpaper.memoryKey)
                                     }
                                 },
                                 log: { Log.write($0) })
    }

    private static var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
    static var defaultStillsFolder: URL { support.appendingPathComponent("ASCII Animals/Stills", isDirectory: true) }
    static var sharksStillsFolder: URL { support.appendingPathComponent(Handover.sharksStillsFolder, isDirectory: true) }

    /// The memory and Sharks' saved originals, from the settings (and Sharks' own settings while it is installed).
    static func restoreData(stillsFolder: URL) -> RestoreData {
        RestoreData.resolve(settings: UserDefaults.standard.data(forKey: SystemWallpaper.memoryKey),
                            sharksOwn: UserDefaults(suiteName: Handover.sharksBundleID)?.data(forKey: Handover.sharksWallpaperKey),
                            sharksCopy: UserDefaults.standard.data(forKey: SystemWallpaper.sharksMemoryCopyKey),
                            stillsFolder: stillsFolder)
    }

    /// Debounced: looks changes come in bursts (sliders, appearance switches).
    func scheduleApply(settings: Settings, systemIsDark: Bool, accent: SIMD3<Float>, delay: TimeInterval = 2) {
        guard !uninstalling else { return }
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.apply(settings: settings, systemIsDark: systemIsDark, accent: accent) }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func apply(settings: Settings, systemIsDark: Bool, accent: SIMD3<Float>) {
        guard settings.matchSystemWallpaper else { return }
        for screen in NSScreen.screens {
            let key = SystemWallpaper.key(for: screen)
            guard keeper.mayApply(on: key) else { continue }   // the original is on disk before anything changes
            let size = screen.frame.size, scale = screen.backingScaleFactor
            let url = keeper.newStill(for: key)
            let gen = generation
            work.async { [weak self, renderer] in
                do {
                    let img = try StillRenderer.render(settings: settings, size: size, scale: scale, warmup: 6,
                                                       systemIsDark: systemIsDark, accent: accent,
                                                       seed: UInt64.random(in: 1...UInt64.max), renderer: renderer)
                    try SystemWallpaper.write(img, to: url)
                    DispatchQueue.main.async { self?.set(url, key: key, generation: gen) }
                } catch {
                    Log.write("still failed: \(error)")
                    DispatchQueue.main.async { self?.keeper.discard(url) }
                }
            }
        }
    }

    private func set(_ url: URL, key: String, generation gen: Int) {
        // A restore may have happened while the still rendered.
        guard gen == generation else {
            keeper.discard(url)
            return
        }
        keeper.commit(url, on: key)
    }

    /// Writes the still next to its file, then renames it over the file: a Space not in view that shows the file
    /// (the other of the two files is never the one in view) sees the old picture or the new one, never half of one.
    private static func write(_ image: CGImage, to url: URL) throws {
        let temp: URL = url.deletingLastPathComponent().appendingPathComponent(".writing-" + url.lastPathComponent)
        try StillRenderer.writePNG(image, to: temp)
        guard rename(temp.path, url.path) == 0 else {
            throw RenderError(description: "cannot write \(url.lastPathComponent): errno \(errno)")
        }
    }

    /// Put each display's own wallpaper back on its Space in view, wherever a still shows. Only what reads back counts.
    @discardableResult
    func restoreAll() -> RestoreOutcome {
        pending?.cancel()
        generation += 1
        let out: RestoreOutcome = keeper.restoreAll()
        if !out.failed.isEmpty { Log.write("restore: \(out.restored.count) back, \(out.failed.count) not") }
        return out
    }

    /// A display came back, the Space changed, the Mac woke or the app launched: with matching off, a still on the
    /// Space in view gives way to the person's own wallpaper (a Space not in view at the last restore, a display back).
    func reconcile(matching: Bool) {
        guard !uninstalling, !matching else { return }
        restoreAll()
    }

    /// Uninstall began: scheduled and rendering stills are dropped, and from now on nothing goes up or reconciles.
    func beginUninstall() {
        uninstalling = true
        pending?.cancel()
        generation += 1
        keeper.beginUninstall()
    }

    static func key(for screen: NSScreen) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(screen.displayID)?.takeRetainedValue(),
              let s = CFUUIDCreateString(nil, uuid) as String? else { return "display-\(screen.displayID)" }
        return s
    }

    static func entry(for screen: NSScreen) -> WallpaperEntry? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let o = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let fill = (o[.fillColor] as? NSColor)?.usingColorSpace(.sRGB).map {
            [Double($0.redComponent), Double($0.greenComponent), Double($0.blueComponent), Double($0.alphaComponent)]
        }
        return WallpaperEntry(url: url, scaling: (o[.imageScaling] as? NSNumber)?.intValue,
                              allowClipping: (o[.allowClipping] as? NSNumber)?.boolValue, fillColor: fill)
    }

    /// The real desktop: NSWorkspace on the attached screens. Main thread only.
    private final class Desktop: DesktopImages {
        struct NoScreen: Error, CustomStringConvertible {
            let key: String
            var description: String { "display \(key) is not attached" }
        }

        var displays: [String] { NSScreen.screens.map { SystemWallpaper.key(for: $0) } }

        private func screen(_ key: String) -> NSScreen? { NSScreen.screens.first { SystemWallpaper.key(for: $0) == key } }

        func current(on display: String) -> WallpaperEntry? { screen(display).flatMap { SystemWallpaper.entry(for: $0) } }

        func set(_ entry: WallpaperEntry, on display: String) throws {
            guard let s = screen(display) else { throw NoScreen(key: display) }
            var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
            if let v = entry.scaling { options[.imageScaling] = v }
            if let c = entry.allowClipping { options[.allowClipping] = c }
            if let f = entry.fillColor, f.count == 4 {
                options[.fillColor] = NSColor(srgbRed: f[0], green: f[1], blue: f[2], alpha: f[3])
            }
            try NSWorkspace.shared.setDesktopImageURL(entry.url, for: s, options: options)
        }
    }
}
