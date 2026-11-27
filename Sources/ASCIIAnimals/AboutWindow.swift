import AppKit
import Metal
import OceanKit
import SwiftUI

/// The About window: a strip of the live habitat, the icon, the name and version,
/// who made it, and credit to the originals and the font.
enum AboutWindow {
    private static var controller: AboutController?

    static func show(app: AppDelegate) {
        if controller == nil { controller = AboutController(app: app) }
        controller?.show()
    }

    /// The machine's state changed: the strip follows the previews' policy while the window is up.
    static func powerChanged(_ i: PowerInputs) { controller?.powerChanged(i) }

    /// Debug: render to a PNG (no Screen Recording needed). `--snapshot-about <png>`
    /// `ASCII_ANIMALS_SNAPSHOT_LIGHT=1` snapshots the light appearance, `ASCII_ANIMALS_SNAPSHOT_HABITAT=web|meadow`
    /// the Web or the Meadow (default the Ocean). Prints the strip's accessibility label.
    static func snapshot(to url: URL) {
        let env = ProcessInfo.processInfo.environment
        let light = env["ASCII_ANIMALS_SNAPSHOT_LIGHT"] != nil
        NSApp.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        var s = OceanKit.Settings.defaults
        if let h = env["ASCII_ANIMALS_SNAPSHOT_HABITAT"].flatMap(HabitatKind.init(rawValue:)) { s.habitat = h }
        s.appearance = light ? .light : .dark
        let model = AboutModel()
        model.habitat = s.habitat
        do {
            guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError(description: "no Metal device") }
            model.still = try StillRenderer.render(settings: s, size: AboutView.bannerWorld, scale: 2 / AboutView.bannerZoom,
                                                   warmup: 6, systemIsDark: !light, accent: SIMD3(0.2, 0.5, 1), seed: 5,
                                                   renderer: try OceanRenderer(device: device))
        } catch {
            FileHandle.standardError.write(Data("about snapshot: no ocean (\(error))\n".utf8))
        }
        let view = NSHostingView(rootView: AboutView(model: model, ocean: nil))
        view.safeAreaRegions = []
        view.frame.size = view.fittingSize
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.contentView = view
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("strip label: \(AboutView.stripLabel(model.habitat))")
        print("wrote \(url.path)")
    }
}

final class AboutModel: ObservableObject {
    @Published var checking = false
    /// The snapshot's stand-in for the live strip.
    @Published var still: CGImage?
    /// What the strip shows, for its accessibility label.
    @Published var habitat: HabitatKind = .ocean
    var checkForUpdates: () -> Void = {}
}

final class AboutController: NSObject, NSWindowDelegate {
    private unowned let app: AppDelegate
    private let model = AboutModel()
    private var window: NSWindow?
    private var ocean: LiveOceanView?
    private var appearance: NSKeyValueObservation?

    init(app: AppDelegate) {
        self.app = app
        super.init()
        model.checkForUpdates = { [weak app] in app?.updates.checkNow(userInitiated: true) }
        // Follow the check's progress without taking the menu's hook away from it.
        let previous = app.updates.onChange
        app.updates.onChange = { [weak self, weak app] in
            previous?()
            self?.model.checking = app?.updates.state == .checking
        }
    }

    func show() {
        let s = app.store.settings
        if window == nil {
            if let r = app.director?.renderer {
                ocean = LiveOceanView(renderer: r, settings: s, theme: OceanDirector.currentTheme(s), zoom: AboutView.bannerZoom, seed: 5)
            }
            let host = NSHostingView(rootView: AboutView(model: model, ocean: ocean))
            host.safeAreaRegions = [] // the water runs up under the title bar
            host.frame.size = host.fittingSize
            let w = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = "About ASCII Animals"
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = host
            w.center()
            window = w
            // The Mac turning light or dark: the strip follows (effectiveAppearance settles a pass later).
            appearance = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { self?.themeChanged() }
            }
        }
        model.habitat = s.habitat
        if let ocean {
            // The habitat or line-up may have changed since the window was made.
            ocean.setTheme(OceanDirector.currentTheme(s))
            ocean.rebuild(s, reopening: true)
            // Reduce Motion and Low Power Mode hold a still, as on the desktop.
            ocean.run(PowerPolicy.preview(app.signals.inputs))
        }
        model.checking = app.updates.state == .checking
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { ocean?.run(.paused) }

    func powerChanged(_ i: PowerInputs) {
        guard window?.isVisible == true else { return }
        ocean?.run(PowerPolicy.preview(i))
    }

    private func themeChanged() {
        guard window?.isVisible == true else { return }
        ocean?.setTheme(OceanDirector.currentTheme(app.store.settings))
    }
}

// MARK: - View

struct AboutView: View {
    static let width: CGFloat = 340
    static let bannerHeight: CGFloat = 150
    /// The strip shows the ocean from a step back, like the Settings preview.
    static let bannerZoom: CGFloat = 1.5
    static var bannerWorld: CGSize { CGSize(width: width * bannerZoom, height: bannerHeight * bannerZoom) }

    @ObservedObject var model: AboutModel
    let ocean: LiveOceanView?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            banner
            VStack(spacing: 0) {
                Image(nsImage: UIFonts.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                    .padding(.top, -58)
                    .accessibilityHidden(true)

                Text("ASCII Animals")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 10)
                Text("Version \(AppInfo.version) (\(AppInfo.build))")
                    .font(UIFonts.swiftUI(11.5))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 4)

                HStack(spacing: 2) {
                    XeroWorksMark(cell: 3, light: scheme == .light)
                        .padding(6) // two cells of clear space all round
                    (Text("by ") + Text(AppInfo.company).fontWeight(.medium))
                        .font(.callout)
                }
                .onTapGesture { NSWorkspace.shared.open(AppInfo.companyURL) }
                .help(AppInfo.companyURL.absoluteString)
                .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                .accessibilityAddTraits(.isLink)
                .accessibilityLabel("by \(AppInfo.company)")
                .padding(.top, 12)

                Divider().padding(.horizontal, 28).padding(.vertical, 16)

                VStack(spacing: 5) {
                    VStack(spacing: 1) {
                        Text(.init("The Ocean comes from [ascii-sharks](\(AppInfo.sharksURL.absoluteString)),"))
                        Text(.init("the Web from [ascii-spiders](\(AppInfo.spidersURL.absoluteString)), both by [@stackedlol](https://github.com/stackedlol)."))
                        Text("The Meadow is XERO WORKS' own.")
                    }
                    Text("Set in Geist Mono, under the SIL Open Font License.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .tint(Color.accentColor)

                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.open(AppInfo.repoURL)
                    } label: {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Button {
                        model.checkForUpdates()
                    } label: {
                        Text(model.checking ? "Checking…" : "Check for Updates…").frame(minWidth: 120)
                    }
                    .disabled(model.checking)
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.regular)
                .padding(.top, 18)

                Text(AppInfo.copyright)
                    .font(UIFonts.swiftUI(10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: Self.width)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var banner: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(scheme == .light ? Color(white: 0.96) : Color(white: 0.02))
            if let ocean {
                OceanStrip(view: ocean)
            } else if let still = model.still {
                Image(decorative: still, scale: 2).resizable().interpolation(.high)
            }
            // The water fades into the window, under the icon.
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor).opacity(0), Color(nsColor: .windowBackgroundColor)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 64)
                .allowsHitTesting(false)
        }
        .frame(width: Self.width, height: Self.bannerHeight)
        .clipped()
        .accessibilityLabel(Self.stripLabel(model.habitat))
    }

    /// The live strip's accessibility label: what it shows, and what the pointer does there.
    static func stripLabel(_ habitat: HabitatKind) -> String {
        switch habitat {
        case .ocean: return "A live ocean. Move the pointer over it, or click for a splash"
        case .web: return "A live web. Move the pointer over it, or click to drop a fly"
        case .meadow: return "A live meadow. Move the pointer over it, or click to bloom a flower"
        }
    }
}

private struct OceanStrip: NSViewRepresentable {
    let view: LiveOceanView
    func makeNSView(context: Context) -> LiveOceanView { view }
    func updateNSView(_ nsView: LiveOceanView, context: Context) {}
}

/// The XERO WORKS logomark (four birds), drawn from its 6×6 grid: whole points
/// per cell, no smoothing, the official white or black variant.
struct XeroWorksMark: View {
    /// Points per grid cell.
    let cell: CGFloat
    let light: Bool

    /// Filled cells of the mark, row by row (from the brand kit's SVG).
    static let rows = [
        ".##.##",
        "##.##.",
        "#.##.#",
        ".##.##",
        "##.##.",
        "#.##.#",
    ]

    var body: some View {
        Canvas { ctx, _ in
            var p = Path()
            for (y, row) in Self.rows.enumerated() {
                for (x, c) in row.enumerated() where c == "#" {
                    p.addRect(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
                }
            }
            ctx.fill(p, with: .color(light ? .black : Color(red: 0xd9 / 255, green: 0xd9 / 255, blue: 0xd9 / 255)))
        }
        .frame(width: cell * 6, height: cell * 6)
        .accessibilityHidden(true)
    }
}
