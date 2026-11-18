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
    let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        s = store.settings
        density = s.fishDensity
        speed = s.speed
    }

    func refresh() {
        s = store.settings
        density = s.fishDensity
        speed = s.speed
        loginEnabled = LoginItem.isEnabled
    }

    func binding<T>(_ path: WritableKeyPath<OceanKit.Settings, T>) -> Binding<T> {
        Binding(get: { self.s[keyPath: path] }, set: { v in self.store.update { $0[keyPath: path] = v } })
    }

    func setLogin(_ on: Bool) {
        do { try LoginItem.set(on); loginError = nil } catch { loginError = error.localizedDescription }
        loginEnabled = LoginItem.isEnabled
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(Array(model.s.sharks.enumerated()), id: \.offset) { i, kind in
                    HStack {
                        Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                        Picker("", selection: Binding(get: { kind }, set: { k in model.store.update { $0.sharks[i] = k } })) {
                            ForEach(SharkKind.allCases, id: \.self) { Text(Presets.title($0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 190, alignment: .leading)
                        Spacer()
                        Button { model.store.update { $0.sharks.swapAt(i, i - 1) } } label: { Image(systemName: "chevron.up") }
                            .disabled(i == 0).buttonStyle(.borderless).help("Make bigger")
                        Button { model.store.update { $0.sharks.swapAt(i, i + 1) } } label: { Image(systemName: "chevron.down") }
                            .disabled(i == model.s.sharks.count - 1).buttonStyle(.borderless).help("Make smaller")
                        Button { model.store.update { $0.sharks.remove(at: i) } } label: { Image(systemName: "minus.circle") }
                            .disabled(model.s.sharks.count == 1).buttonStyle(.borderless).help("Remove")
                    }
                }
                HStack {
                    Button("Add Shark") { model.store.update { $0.sharks.append(.classic) } }
                        .disabled(model.s.sharks.count >= OceanKit.Settings.maxSharks)
                    Spacer()
                    Menu("Presets") {
                        ForEach(Presets.all, id: \.title) { p in Button(p.title) { model.store.update { $0.sharks = p.sharks } } }
                    }
                    .fixedSize()
                }
            } header: {
                Text("Sharks")
            } footer: {
                Text("The first is the biggest; each next one is a little smaller. Up to eight.").foregroundStyle(.secondary)
            }

            Section("Ocean") {
                LabeledContent("Fish") {
                    Slider(value: $model.density, in: 0.5...2) { editing in
                        if !editing { model.store.update { $0.fishDensity = model.density } }
                    }
                }
                LabeledContent("Speed") {
                    Slider(value: $model.speed, in: 0.5...1.5) { editing in
                        if !editing { model.store.update { $0.speed = model.speed } }
                    }
                }
            }

            Section("Look") {
                Picker("Appearance", selection: model.binding(\.appearance)) {
                    Text("Dark").tag(Appearance.dark)
                    Text("Light").tag(Appearance.light)
                    Text("Match System").tag(Appearance.system)
                }
                Picker("Wake colour", selection: model.binding(\.wakeColor)) {
                    Text("Cyan").tag(WakeColor.cyan)
                    Text("Accent colour").tag(WakeColor.accent)
                }
                Toggle("Calm (dimmer, easier on desktop icons)", isOn: model.binding(\.calm))
                Toggle("Grid", isOn: model.binding(\.grid))
            }

            Section {
                Toggle("Wake and splash under the pointer", isOn: model.binding(\.interaction))
                Picker("Frame rate", selection: model.binding(\.fps)) {
                    ForEach(OceanKit.Settings.fpsOptions, id: \.self) { Text("\($0) fps").tag($0) }
                }
                Toggle("Keep animating in Low Power Mode", isOn: model.binding(\.lowPowerAnimates))
                Toggle("Show a matching still as the system wallpaper", isOn: model.binding(\.matchSystemWallpaper))
                Toggle("Open at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                if let e = model.loginError { Text(e).foregroundStyle(.red).font(.caption) }
            } header: {
                Text("Behaviour")
            } footer: {
                Text("On battery, in Low Power Mode and when the Mac is hot, the ocean runs at \(PowerPolicy.economyFPS) fps. It pauses whenever it is covered, locked or asleep.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}

final class SettingsWindowController {
    private var window: NSWindow?
    private let model: SettingsModel

    init(model: SettingsModel) { self.model = model }

    func show() {
        model.refresh()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 760),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "ASCII Sharks Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
