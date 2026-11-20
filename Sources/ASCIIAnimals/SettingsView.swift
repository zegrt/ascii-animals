import AppKit
import OceanKit
import SwiftUI

final class SettingsModel: ObservableObject {
    @Published private(set) var s: OceanKit.Settings
    /// Slider drafts, committed when the drag ends (density reseeds the ocean).
    @Published var density: Double = 1
    @Published var speed: Double = 1
    @Published var loginEnabled = LoginItem.isEnabled
    @Published var loginError: String?
    @Published private(set) var status: OceanStatus
    let store: SettingsStore
    let preview = OceanPreview()
    private var statusTimer: Timer?
    /// The status and preview only update while the window is open.
    private var isVisible = false

    init(store: SettingsStore) {
        self.store = store
        s = store.settings
        status = OceanStatus.current(store.settings)
        density = s.fishDensity
        speed = s.speed
        preview.themeChanged = { [weak self] in
            guard let self, self.isVisible else { return }
            self.preview.request(self.s)
        }
        // The settings snapshot is captured straight away, so render its preview in line.
        // ASCII_ANIMALS_SNAPSHOT_LIGHT=1 snapshots the light appearance.
        if CommandLine.arguments.contains("--snapshot-settings") {
            if ProcessInfo.processInfo.environment["ASCII_ANIMALS_SNAPSHOT_LIGHT"] != nil {
                NSApp.appearance = NSAppearance(named: .aqua)
            }
            preview.request(s, immediately: true)
        }
    }

    func refresh() {
        s = store.settings
        density = s.fishDensity
        speed = s.speed
        loginEnabled = LoginItem.isEnabled
        guard isVisible else { return }
        refreshStatus()
        preview.request(s)
    }

    func refreshStatus() {
        let now = OceanStatus.current(store.settings)
        if now != status { status = now }
    }

    /// Power state changes without a settings change, so poll gently while the window is open.
    func setVisible(_ visible: Bool) {
        statusTimer?.invalidate()
        statusTimer = nil
        isVisible = visible
        guard visible else { return }
        refresh()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refreshStatus() }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        statusTimer = t
    }

    func binding<T>(_ path: WritableKeyPath<OceanKit.Settings, T>) -> Binding<T> {
        Binding(get: { self.s[keyPath: path] }, set: { v in self.store.update { $0[keyPath: path] = v } })
    }

    func update(_ body: (inout OceanKit.Settings) -> Void) { store.update(body) }

    func setLogin(_ on: Bool) {
        do { try LoginItem.set(on); loginError = nil } catch { loginError = error.localizedDescription }
        loginEnabled = LoginItem.isEnabled
    }
}

// MARK: - Window

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(model: model, preview: model.preview)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            Divider()
            Form {
                HabitatSection(model: model)
                switch model.s.habitat {
                case .ocean:
                    SharksSection(model: model)
                    OceanSection(model: model)
                case .web:
                    WebSection(model: model)
                case .meadow:
                    EmptyView()   // Not offered yet (HabitatKind.offered).
                }
                LookSection(model: model)
                BehaviourSection(model: model)
                AppSection(model: model)
            }
            .formStyle(.grouped)
        }
        .frame(width: SettingsWindowController.width)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Preview

private struct PreviewHeader: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var preview: OceanPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    // The habitat's own background, so an empty card already looks like it.
                    Rectangle().fill(background)
                    if let image = preview.image {
                        Image(decorative: image, scale: 2)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                            .id(ObjectIdentifier(image))
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.25), value: preview.image.map(ObjectIdentifier.init))
                .accessibilityLabel(model.s.habitat == .web
                    ? "Preview of the web with your spiders and look"
                    : "Preview of the ocean with your sharks and look")

                if preview.isRendering {
                    ProgressView()
                        .controlSize(.small)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                        .transition(.opacity)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(Color(nsColor: model.status.color))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(model.status.title).fontWeight(.medium)
                    + Text(model.status.detail.isEmpty ? "" : (model.status.tone == .live ? " · " : " — ") + model.status.detail)
                    .foregroundColor(.secondary)
                Spacer(minLength: 8)
                Button {
                    model.update { $0.paused.toggle() }
                } label: {
                    Label(model.s.paused ? "Resume" : "Pause",
                          systemImage: model.s.paused ? "play.fill" : "pause.fill")
                }
                .controlSize(.small)
                .help(model.s.paused ? "Start the wallpaper moving again" : "Hold the wallpaper still")
            }
            .font(.callout)
            .lineLimit(1)
        }
    }

    private var background: Color {
        let light = model.s.appearance == .light
            || (model.s.appearance == .system && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .darkAqua)
        switch model.s.habitat {
        case .ocean: return light ? Color(white: 0.96) : Color(white: 0.02)
        case .web, .meadow: return light ? Color(red: 247 / 255, green: 246 / 255, blue: 243 / 255) : .black
        }
    }
}

// MARK: - Habitat

private struct HabitatSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section {
            LabeledContent("Habitat") {
                Picker("Habitat", selection: model.binding(\.habitat)) {
                    ForEach(HabitatKind.offered, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: LookSection.segmentedWidth)
            }
            Toggle(isOn: model.binding(\.sharedOcean)) {
                Text("One habitat across displays")
                Text("Animals move from one display to the next. Off, each display has its own.")
            }
        }
    }
}

// MARK: - Sharks

private struct SharksSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let sharks = model.s.sharks
        Section {
            ForEach(Array(sharks.enumerated()), id: \.offset) { i, kind in
                SharkRow(model: model, index: i, kind: kind, count: sharks.count)
            }
            HStack {
                Button {
                    model.update { $0.sharks.append(sharks.last ?? .classic) }
                } label: {
                    Label("Add Shark", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .disabled(sharks.count >= OceanKit.Settings.maxSharks)
                .help(sharks.count >= OceanKit.Settings.maxSharks ? "The ocean holds up to eight" : "Add a smaller shark at the end")
                Spacer()
                Text("\(sharks.count) of \(OceanKit.Settings.maxSharks)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("Sharks")
                Spacer()
                Menu {
                    ForEach(Presets.all, id: \.title) { p in
                        Button {
                            model.update { $0.sharks = p.sharks }
                        } label: {
                            if p.sharks == sharks {
                                Label(p.title, systemImage: "checkmark")
                            } else {
                                Text(p.title)
                            }
                        }
                    }
                } label: {
                    Text(Presets.matching(sharks)?.title ?? "Custom")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.callout)
                .help("Start from a ready-made line-up")
            }
        } footer: {
            Text("Biggest first: each shark is a little smaller than the one above it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SharkRow: View {
    @ObservedObject var model: SettingsModel
    let index: Int
    let kind: SharkKind
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.07)))

            Picker("Shark \(index + 1)", selection: Binding(
                get: { kind },
                set: { k in model.update { if index < $0.sharks.count { $0.sharks[index] = k } } }
            )) {
                ForEach(Presets.species, id: \.self) { Text(Presets.title($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: 8)

            SizeBar(fraction: Presets.relativeSize(at: index))
                .help(index == 0 ? "Biggest" : "\(Int((Presets.relativeSize(at: index) * 100).rounded()))% of the biggest")

            HStack(spacing: 2) {
                RowButton(symbol: "chevron.up", help: "Move up (bigger)", enabled: index > 0) {
                    model.update { $0.sharks.swapAt(index, index - 1) }
                }
                RowButton(symbol: "chevron.down", help: "Move down (smaller)", enabled: index < count - 1) {
                    model.update { $0.sharks.swapAt(index, index + 1) }
                }
                RowButton(symbol: "minus.circle", help: "Remove this shark", enabled: count > 1) {
                    model.update { $0.sharks.remove(at: index) }
                }
            }
        }
    }
}

/// A tapering bar: the first shark fills it, each next one a little less.
private struct SizeBar: View {
    let fraction: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.06))
            Capsule().fill(Color.accentColor.opacity(0.45)).frame(width: 64 * fraction)
        }
        .frame(width: 64, height: 5)
        .accessibilityHidden(true)
    }
}

private struct RowButton: View {
    let symbol: String
    let help: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Ocean

private struct OceanSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section("Ocean") {
            LabeledContent("Fish") {
                Slider(value: $model.density, in: 0.5...2) {
                    Text("Fish")
                } minimumValueLabel: {
                    SliderEnd(text: "Fewer", alignment: .trailing)
                } maximumValueLabel: {
                    SliderEnd(text: "More", alignment: .leading)
                } onEditingChanged: { editing in
                    if !editing { model.update { $0.fishDensity = model.density } }
                }
                .labelsHidden()
            }
            SpeedRow(model: model)
        }
    }
}

/// How fast the habitat runs; both habitats have it.
private struct SpeedRow: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        LabeledContent("Speed") {
            Slider(value: $model.speed, in: 0.5...1.5) {
                Text("Speed")
            } minimumValueLabel: {
                SliderEnd(text: "Slower", alignment: .trailing)
            } maximumValueLabel: {
                SliderEnd(text: "Faster", alignment: .leading)
            } onEditingChanged: { editing in
                if !editing { model.update { $0.speed = model.speed } }
            }
            .labelsHidden()
        }
    }
}

// MARK: - Web

private struct WebSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let spiders = model.s.webSpiders
        Section("Web") {
            Picker(selection: Binding(
                get: { Presets.spiderPresets.firstIndex { $0.spiders == spiders } ?? -1 },
                set: { i in
                    guard Presets.spiderPresets.indices.contains(i) else { return }
                    model.update { $0.webSpiders = Presets.spiderPresets[i].spiders }
                }
            )) {
                ForEach(Array(Presets.spiderPresets.enumerated()), id: \.offset) { i, p in Text(p.title).tag(i) }
                if Presets.matching(spiders) == nil { Text("Custom").tag(-1) }
            } label: {
                Text("Spiders")
                Text(Presets.summary(spiders))
            }
            Toggle(isOn: model.binding(\.webFlies)) {
                Text("Flies")
                Text("They wander by, and now and then one blunders into a web.")
            }
            Toggle(isOn: model.binding(\.webJumper)) {
                Text("Jumping spider")
                Text("It hunts between the webs. Hold the pointer still and it may pounce.")
            }
            SpeedRow(model: model)
        }
    }
}

/// Matching end labels, so the two sliders line up.
private struct SliderEnd: View {
    let text: String
    let alignment: Alignment

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).frame(width: 40, alignment: alignment)
    }
}

// MARK: - Look

private struct LookSection: View {
    static let segmentedWidth: CGFloat = 270
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section("Look") {
            LabeledContent("Appearance") {
                Picker("Appearance", selection: model.binding(\.appearance)) {
                    Text("Dark").tag(Appearance.dark)
                    Text("Light").tag(Appearance.light)
                    Text("Match System").tag(Appearance.system)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: Self.segmentedWidth)
            }

            if model.s.habitat == .ocean {
                LabeledContent("Wake colour") {
                    Picker("Wake colour", selection: model.binding(\.wakeColor)) {
                        Text("Cyan").tag(WakeColor.cyan)
                        Text("Accent Colour").tag(WakeColor.accent)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: Self.segmentedWidth)
                }
            }

            Toggle(isOn: model.binding(\.calm)) {
                Text("Calm")
                Text("Dimmer and quieter, so desktop icons stand out.")
            }
            Toggle(isOn: model.binding(\.grid)) {
                Text("Grid")
                Text("Faint lines between the characters.")
            }
        }
    }
}

// MARK: - Behaviour

private struct BehaviourSection: View {
    static let segmentedWidth = LookSection.segmentedWidth
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section {
            Toggle(isOn: model.binding(\.interaction)) {
                Text("Play with the pointer")
                Text(model.s.habitat == .web
                     ? "Moving through a web plucks the silk. Clicking bare desktop drops a fly."
                     : "Fish flee the pointer and leave a wake. Clicking bare desktop makes a splash.")
            }
            LabeledContent("Frame rate") {
                Picker("Frame rate", selection: model.binding(\.fps)) {
                    ForEach(OceanKit.Settings.fpsOptions, id: \.self) { Text("\($0) fps").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: Self.segmentedWidth)
            }
            Toggle(isOn: model.binding(\.lowPowerAnimates)) {
                Text("Keep moving in Low Power Mode")
                Text("Otherwise the wallpaper holds a still frame to save energy.")
            }
            Toggle(isOn: model.binding(\.matchSystemWallpaper)) {
                Text("Match the lock screen")
                Text("Sets a matching still as the system wallpaper. Yours comes back when you quit.")
            }
        } header: {
            Text("Behaviour")
        } footer: {
            Text("On battery, in Low Power Mode and when the Mac is warm, the wallpaper slows to \(PowerPolicy.economyFPS) fps. It pauses whenever it's covered, locked or asleep.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - App

private struct AppSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section {
            Toggle("Open at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
            if let e = model.loginError {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Toggle(isOn: model.binding(\.pauseShortcut)) {
                Text("Pause with \u{2303}\u{2325}\u{2318}P from anywhere")
                Text("Works in any app, without extra permissions.")
            }
            Toggle(isOn: model.binding(\.showMenuBarIcon)) {
                Text("Show in the menu bar")
                Text("When it's hidden, open ASCII Animals again to get back to Settings.")
            }
            Toggle(isOn: model.binding(\.checkForUpdates)) {
                Text("Check for updates daily")
                Text("Only asks GitHub for the latest version number. Nothing about you is sent.")
            }
            Toggle(isOn: model.binding(\.autoInstallUpdates)) {
                Text("Install updates automatically")
                Text("A new version installs itself and the wallpaper is back in a second. It waits while Settings is open.")
            }
            .disabled(!model.s.checkForUpdates)
            LabeledContent {
                Button("Check Now…") { (NSApp.delegate as? AppDelegate)?.updates.checkNow(userInitiated: true) }
            } label: {
                Text("Update manually")
                Text("Checks GitHub now and offers to install anything newer.")
            }
        } header: {
            Text("App")
        } footer: {
            HStack(spacing: 6) {
                Text("ASCII Animals \(AppInfo.version)").foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Button("About") { (NSApp.delegate as? AppDelegate)?.showAbout() }
                Text("·").foregroundStyle(.tertiary)
                Button("Welcome Tour") { (NSApp.delegate as? AppDelegate)?.showWelcome() }
            }
            .buttonStyle(.link)
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        }
    }
}

// MARK: - Window controller

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 540
    private var window: NSWindow?
    private let model: SettingsModel

    init(model: SettingsModel) { self.model = model }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 760),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "ASCII Animals Settings"
            w.isReleasedWhenClosed = false
            w.delegate = self
            let host = NSHostingView(rootView: SettingsView(model: model))
            host.sizingOptions = []
            w.contentView = host
            w.setContentSize(NSSize(width: Self.width, height: min(760, (NSScreen.main?.visibleFrame.height ?? 900) - 80)))
            w.center()
            w.setFrameAutosaveName("ASCIIAnimalsSettings")
            window = w
        }
        model.setVisible(true)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { model.setVisible(false) }
}
