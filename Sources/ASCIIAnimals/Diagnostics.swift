import AppKit
import OceanKit

/// What Report a Problem and Copy Diagnostics say about this Mac.
enum Diagnostics {
    static func facts(app: AppDelegate) -> DiagnosticFacts {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let sizes: [String] = NSScreen.screens.map {
            "\(Int($0.frame.width))x\(Int($0.frame.height)) @\(Int($0.backingScaleFactor))x \($0.maximumFramesPerSecond) Hz"
        }
        let displays: [String] = zip(NSScreen.screens, sizes).map { "\($0.localizedName) \($1)" }
        let i = app.signals.inputs
        var power = [i.onBattery ? "battery" : "AC power"]
        if i.lowPowerMode { power.append("Low Power Mode") }
        if i.thermal != .nominal { power.append("thermal \(i.thermal)") }
        if i.reduceMotion { power.append("Reduce Motion") }
        let mode = DiagnosticFacts.mode(habitat: app.store.settings.habitat, run: app.director?.mode,
                                        screens: app.director?.screens.count ?? 0, scenes: app.director?.scenes.count ?? 0,
                                        failure: app.startupError)
        return DiagnosticFacts(
            appVersion: "\(AppInfo.version) (\(AppInfo.build))",
            macOS: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            model: String(cString: model),
            displays: displays, power: power.joined(separator: ", "), mode: mode,
            settingsJSON: String(decoding: SettingsCodec.encode(app.store.settings), as: UTF8.self),
            crashedLastTime: app.crashedLastTime, logTail: Log.entries(60),
            displaySizes: sizes)
    }

    static func body(app: AppDelegate) -> String {
        IssueReport.body(facts(app: app), homePath: NSHomeDirectory(), userName: NSUserName(), fullName: NSFullUserName())
    }

    static let reportTitle = "Problem: "

    /// Report a Problem's review, before anything leaves the Mac: shows exactly the text that goes into the GitHub
    /// form (`IssueReport.form`), with a choice to add the recent log. Returns that text when the person goes ahead,
    /// nil when they cancel.
    static func review(app: AppDelegate) -> String? {
        let f: DiagnosticFacts = facts(app: app)
        func form(_ log: Bool) -> String {
            IssueReport.form(f, includeLog: log, homePath: NSHomeDirectory(), userName: NSUserName(),
                             fullName: NSFullUserName(), base: AppInfo.issuesURL, title: reportTitle)
        }
        var text: String = form(false)

        let width: CGFloat = 460
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: 240)
        scroll.borderType = .bezelBorder
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.string = text
        let toggle = ReviewToggle { on in
            text = form(on)
            view.string = text
        }
        let box = NSButton(checkboxWithTitle: "Add the recent log, without your names or folders",
                           target: toggle, action: #selector(ReviewToggle.changed(_:)))
        box.isEnabled = !f.logTail.isEmpty
        let stack = NSStackView(views: [scroll, box])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: width, height: 272)
        scroll.widthAnchor.constraint(equalToConstant: width).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 240).isActive = true

        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Report a Problem"
        a.informativeText = "This is everything that goes into the GitHub form. It leaves your Mac only when the form "
            + "opens in your browser, and GitHub posts nothing until you submit it there."
        a.accessoryView = stack
        a.addButton(withTitle: "Open GitHub Form")
        a.addButton(withTitle: "Cancel")
        let go: Bool = a.runModal() == .alertFirstButtonReturn
        withExtendedLifetime(toggle) {}
        return go ? text : nil
    }
}

/// The review's checkbox.
private final class ReviewToggle: NSObject {
    let onChange: (Bool) -> Void
    init(_ onChange: @escaping (Bool) -> Void) { self.onChange = onChange }
    @objc func changed(_ sender: NSButton) { onChange(sender.state == .on) }
}
