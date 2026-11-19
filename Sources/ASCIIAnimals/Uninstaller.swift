import AppKit

/// Removes ASCII Animals completely: puts the user's wallpaper back first,
/// then the login item, files, preferences and the app itself.
enum Uninstaller {
    static func confirm() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Uninstall ASCII Animals?"
        a.informativeText = "Your own wallpaper comes back, and ASCII Animals removes its settings, saved stills, logs and login item, then moves itself to the Trash."
        a.alertStyle = .warning
        a.addButton(withTitle: "Uninstall")
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    /// Returns what it couldn't do (empty when everything went).
    @discardableResult
    static func run(app: AppDelegate?) -> [String] {
        var problems: [String] = []
        app?.isUninstalling = true
        app?.wallpaper?.restoreAll()
        do { try LoginItem.set(false) } catch { if LoginItem.isEnabled { problems.append("login item: \(error.localizedDescription)") } }
        let fm = FileManager.default
        for url in [CrashMarker.folder, Log.folder] where fm.fileExists(atPath: url.path) {
            do { try fm.removeItem(at: url) } catch { problems.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
            UserDefaults.standard.synchronize()
            CFPreferencesAppSynchronize(id as CFString)
        }
        // Synchronous, so it's done before the process exits.
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            do { try fm.trashItem(at: bundle, resultingItemURL: nil) } catch {
                problems.append("moving the app to the Trash: \(error.localizedDescription)")
            }
        }
        return problems
    }
}
