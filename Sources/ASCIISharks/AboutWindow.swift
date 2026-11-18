import AppKit

/// The About window. (Stub — owned by the UI work.)
enum AboutWindow {
    static func show(app: AppDelegate) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
