import AppKit
import OceanKit

/// Shows a still of the ocean as the system wallpaper (lock screen, Mission
/// Control, menu-bar tint) and puts the user's own wallpaper back on quit.
/// The rules live in WallpaperMemory.
final class SystemWallpaper {
    static let memoryKey = "wallpaperMemory.v1"
    static let keepStills = 3

    let stillsFolder: URL
    private let renderer: OceanRenderer
    private var memory: WallpaperMemory
    private var pending: DispatchWorkItem?
    /// Bumped by restoreAll(); a still that finishes rendering after a restore is dropped.
    private var generation = 0
    private let work = DispatchQueue(label: "ascii-sharks.stills", qos: .utility)

    init(renderer: OceanRenderer) {
        self.renderer = renderer
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        stillsFolder = support.appendingPathComponent("ASCII Sharks/Stills", isDirectory: true)
        try? FileManager.default.createDirectory(at: stillsFolder, withIntermediateDirectories: true)
        if let data = UserDefaults.standard.data(forKey: SystemWallpaper.memoryKey),
           let m = try? JSONDecoder().decode(WallpaperMemory.self, from: data) {
            memory = m
        } else {
            memory = WallpaperMemory()
        }
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
            guard let current = SystemWallpaper.entry(for: screen) else { continue }
            guard memory.decide(screen: key, current: current, stillsFolder: stillsFolder) == .apply else { continue }
            save() // the original is on disk before anything changes
            let size = screen.frame.size, scale = screen.backingScaleFactor
            let url = stillsFolder.appendingPathComponent("still-\(key)-\(Int(Date().timeIntervalSince1970 * 1000)).png")
            let gen = generation
            work.async { [weak self, renderer] in
                do {
                    let img = try StillRenderer.render(settings: settings, size: size, scale: scale, warmup: 6,
                                                       systemIsDark: systemIsDark, accent: accent,
                                                       seed: UInt64.random(in: 1...UInt64.max), renderer: renderer)
                    try StillRenderer.writePNG(img, to: url)
                    DispatchQueue.main.async { self?.set(url, on: screen, key: key, generation: gen) }
                } catch {
                    Log.write("still failed: \(error)")
                }
            }
        }
    }

    private func set(_ url: URL, on screen: NSScreen, key: String, generation gen: Int) {
        // Re-check: a restore may have happened, or the wallpaper changed, while the still rendered.
        guard gen == generation, NSScreen.screens.contains(screen), let current = SystemWallpaper.entry(for: screen),
              memory.decide(screen: key, current: current, stillsFolder: stillsFolder) == .apply else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
                .fillColor: NSColor.black,
            ])
        } catch {
            Log.write("could not set wallpaper: \(error)")
        }
        prune(key: key, keep: url)
    }

    /// Keep the newest few stills per screen; never the one in use.
    private func prune(key: String, keep: URL) {
        let fm = FileManager.default
        let mine = ((try? fm.contentsOfDirectory(at: stillsFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("still-\(key)-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in mine.dropFirst(SystemWallpaper.keepStills) where old != keep {
            try? fm.removeItem(at: old)
        }
    }

    /// Put each screen's own wallpaper back wherever our still is showing.
    func restoreAll() {
        pending?.cancel()
        generation += 1
        for screen in NSScreen.screens {
            let key = SystemWallpaper.key(for: screen)
            guard let current = SystemWallpaper.entry(for: screen),
                  let target = memory.restoreTarget(screen: key, current: current, stillsFolder: stillsFolder) else { continue }
            var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
            if let s = target.scaling { options[.imageScaling] = s }
            if let c = target.allowClipping { options[.allowClipping] = c }
            if let f = target.fillColor, f.count == 4 {
                options[.fillColor] = NSColor(srgbRed: f[0], green: f[1], blue: f[2], alpha: f[3])
            }
            do {
                try NSWorkspace.shared.setDesktopImageURL(target.url, for: screen, options: options)
                memory.forget(screen: key)
            } catch {
                Log.write("could not restore wallpaper: \(error)")
            }
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(memory) { UserDefaults.standard.set(data, forKey: SystemWallpaper.memoryKey) }
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
}
