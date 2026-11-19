import AppKit
import Combine
import Metal
import OceanKit

/// A small still of the ocean for the top of Settings. It re-renders off the
/// main thread, debounced, whenever something that changes the picture changes.
final class OceanPreview: ObservableObject {
    /// Point size of the rendered ocean, the shape of the card in Settings. It's drawn at a
    /// little over half size, so the glyphs read like the desktop seen from a step back.
    static let renderSize = CGSize(width: 900, height: 324)

    @Published private(set) var image: CGImage?
    @Published private(set) var isRendering = false

    private struct Key: Equatable {
        var settings: OceanKit.Settings
        var dark: Bool
        var accent: SIMD3<Float>
    }

    private let work = DispatchQueue(label: "ascii-animals.preview", qos: .userInitiated)
    private var ownRenderer: OceanRenderer?
    private var pending: DispatchWorkItem?
    private var lastKey: Key?
    private var generation = 0
    private var themeObserver: NSObjectProtocol?

    init() {
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            // effectiveAppearance updates on the next run-loop pass.
            DispatchQueue.main.async { self?.themeChanged?() }
        }
    }

    deinit { if let themeObserver { DistributedNotificationCenter.default().removeObserver(themeObserver) } }

    /// Called when the system appearance or accent changes, so the owner can re-request.
    var themeChanged: (() -> Void)?

    /// Ask for a preview of these settings. Cheap to call often.
    func request(_ settings: OceanKit.Settings, immediately: Bool = false) {
        let key = Key(settings: Self.looks(settings), dark: Self.systemIsDark, accent: Self.accent)
        guard key != lastKey else { return }
        lastKey = key
        generation += 1
        let gen = generation
        pending?.cancel()
        if immediately {
            image = render(key, Self.appRenderer)
            return
        }
        let item = DispatchWorkItem { [weak self] in self?.start(key, gen) }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (image == nil ? 0 : 0.2), execute: item)
    }

    private func start(_ key: Key, _ gen: Int) {
        isRendering = true
        let appRenderer = Self.appRenderer
        work.async { [weak self] in
            guard let self else { return }
            let img = self.render(key, appRenderer)
            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                if let img { self.image = img }
                self.isRendering = false
            }
        }
    }

    /// Runs on `work`, or on the main thread for the settings snapshot (which never uses `work`).
    private func render(_ key: Key, _ appRenderer: OceanRenderer?) -> CGImage? {
        do {
            let renderer: OceanRenderer
            if let appRenderer {
                renderer = appRenderer
            } else if let own = ownRenderer {
                renderer = own
            } else {
                guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError(description: "no Metal device") }
                renderer = try OceanRenderer(device: device)
                ownRenderer = renderer
            }
            return try StillRenderer.render(settings: key.settings, size: Self.renderSize, scale: 1, warmup: 5,
                                            systemIsDark: key.dark, accent: key.accent, seed: 3, renderer: renderer)
        } catch {
            NSLog("ASCII Animals preview failed: %@", "\(error)")
            return nil
        }
    }

    /// The running app's renderer, whose shaders are already compiled.
    private static var appRenderer: OceanRenderer? { (NSApp.delegate as? AppDelegate)?.director?.renderer }

    /// Only what changes the picture; everything else is reset so it can't cause a re-render.
    private static func looks(_ s: OceanKit.Settings) -> OceanKit.Settings {
        var l = OceanKit.Settings.defaults
        l.sharks = s.sharks
        l.fishDensity = s.fishDensity
        l.appearance = s.appearance
        l.calm = s.calm
        l.grid = s.grid
        l.wakeColor = s.wakeColor
        return l
    }

    private static var systemIsDark: Bool { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    private static var accent: SIMD3<Float> {
        let a = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        return SIMD3(Float(a.redComponent), Float(a.greenComponent), Float(a.blueComponent))
    }
}
