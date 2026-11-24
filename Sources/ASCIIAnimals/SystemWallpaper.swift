import AppKit
import OceanKit

/// Shows a still of the ocean as the system wallpaper (lock screen, Mission
/// Control, menu-bar tint) and puts the user's own wallpaper back on quit.
/// The rules live in WallpaperKeeper and WallpaperMemory; this renders the stills and is their desktop.
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
    private let work = DispatchQueue(label: "ascii-animals.stills", qos: .utility)

    /// Nil in the energy-test copy (`LaunchPlan.matchesSystemWallpaper`), before anything is read or made: no
    /// stills, no `wallpaperMemory.v1`, the system wallpaper never touched.
    init?(renderer: OceanRenderer) {
        guard Launch.plan.matchesSystemWallpaper else { return nil }
        self.renderer = renderer
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        stillsFolder = support.appendingPathComponent("ASCII Animals/Stills", isDirectory: true)
        try? FileManager.default.createDirectory(at: stillsFolder, withIntermediateDirectories: true)
        let memory: WallpaperMemory = UserDefaults.standard.data(forKey: SystemWallpaper.memoryKey)
            .flatMap { try? JSONDecoder().decode(WallpaperMemory.self, from: $0) } ?? WallpaperMemory()
        let sharksMemory = (UserDefaults(suiteName: Handover.sharksBundleID)?.data(forKey: Handover.sharksWallpaperKey)
            ?? UserDefaults.standard.data(forKey: SystemWallpaper.sharksMemoryCopyKey))
            .flatMap { try? JSONDecoder().decode(WallpaperMemory.self, from: $0) }
        // ASCII Sharks' stills: one left up (Sharks force-quit) is never taken for the user's wallpaper.
        let sharks = ForeignStills(folder: support.appendingPathComponent(Handover.sharksStillsFolder, isDirectory: true),
                                   memory: sharksMemory ?? WallpaperMemory())
        keeper = WallpaperKeeper(memory: memory, stillsFolder: stillsFolder, foreign: sharks,
                                 desktop: Desktop(stillsFolder: stillsFolder),
                                 save: { m in
                                     if let data = try? JSONEncoder().encode(m) {
                                         UserDefaults.standard.set(data, forKey: SystemWallpaper.memoryKey)
                                     }
                                 },
                                 log: { Log.write($0) })
    }

    /// Debounced: looks changes come in bursts (sliders, appearance switches).
    func scheduleApply(settings: Settings, systemIsDark: Bool, accent: SIMD3<Float>, delay: TimeInterval = 2) {
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
                    try StillRenderer.writePNG(img, to: url)
                    DispatchQueue.main.async { self?.set(url, key: key, generation: gen) }
                } catch {
                    Log.write("still failed: \(error)")
                }
            }
        }
    }

    private func set(_ url: URL, key: String, generation gen: Int) {
        // A restore may have happened while the still rendered.
        guard gen == generation else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        keeper.commit(url, on: key)
    }

    /// Put each screen's own wallpaper back wherever our still is showing.
    @discardableResult
    func restoreAll() -> RestoreOutcome {
        pending?.cancel()
        generation += 1
        return keeper.restoreAll()
    }

    /// A display came back, the Space changed or the Mac woke.
    func reconcile(matching: Bool) {
        if !matching {
            pending?.cancel()
            generation += 1
        }
        keeper.reconcile(matching: matching)
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

    /// The real desktop: NSWorkspace on the attached screens, and the stills folder on disk. Main thread only.
    private final class Desktop: DesktopImages {
        let stillsFolder: URL
        init(stillsFolder: URL) { self.stillsFolder = stillsFolder }

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

        func stillFiles() -> [URL] {
            (try? FileManager.default.contentsOfDirectory(at: stillsFolder, includingPropertiesForKeys: nil)) ?? []
        }

        func removeFile(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
    }
}
