import AppKit
import OceanKit

/// Removes ASCII Animals completely: puts the user's wallpaper back first,
/// then the login item, files, preferences and the app itself.
enum Uninstaller {
    /// The energy-test copy has no uninstaller (`LaunchPlan.offersUninstall`): no question, no answer but no.
    static func confirm() -> Bool {
        guard Launch.plan.offersUninstall else { return false }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Uninstall ASCII Animals?"
        a.informativeText = "Your own wallpaper comes back, and ASCII Animals removes its settings, saved stills, logs and login item, then moves itself to the Trash."
        a.alertStyle = .warning
        a.addButton(withTitle: "Uninstall")
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    /// Returns what it couldn't do (empty when everything went). When the wallpaper didn't all come back (or
    /// couldn't be tried), the stills and the memory of the user's wallpaper stay, and the first line says so.
    @discardableResult
    static func run(app: AppDelegate?, wallpaper: SystemWallpaper? = nil) -> [String] {
        guard Launch.plan.offersUninstall else { return ["the energy-test copy has no uninstaller"] }
        var problems: [String] = []
        app?.isUninstalling = true
        let wp: SystemWallpaper? = wallpaper ?? app?.wallpaper
        wp?.beginUninstall()   // no still goes up and nothing reconciles from here on, even under an alert
        let outcome: RestoreOutcome? = wp?.restoreAll()
        let memory: Data? = UserDefaults.standard.data(forKey: SystemWallpaper.memoryKey)
        // ASCII Sharks' memory, copied at the hand-over: the only record of what a Sharks still left up covers.
        let sharksMemory: Data? = UserDefaults.standard.data(forKey: SystemWallpaper.sharksMemoryCopyKey)
        // Not restored, or not tried (no wallpaper object) with a memory saved: keep what puts it back.
        let keep: Bool = outcome?.keepsRecovery ?? (memory != nil || sharksMemory != nil)
        let stills: URL? = keep ? wp?.stillsFolder ?? CrashMarker.folder.appendingPathComponent("Stills", isDirectory: true) : nil
        if let stills {
            let folder: String = (stills.path as NSString).abbreviatingWithTildeInPath
            let unchecked: String = "ASCII Animals couldn't check your wallpaper. Its pictures are kept in \(folder), so "
                + "nothing goes blank. Choose your wallpaper in System Settings > Wallpaper, then you can delete that folder."
            problems.append(outcome?.uninstallNote(stillsFolder: stills) ?? unchecked)
        }
        do { try LoginItem.set(false) } catch { if LoginItem.isEnabled { problems.append("login item: \(error.localizedDescription)") } }
        let fm = FileManager.default
        for url in [CrashMarker.folder, Log.folder] where fm.fileExists(atPath: url.path) {
            if let stills, url == CrashMarker.folder {
                // Everything but the stills still in use.
                let items: [URL] = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                for item in items where item.standardizedFileURL.path != stills.standardizedFileURL.path {
                    do { try fm.removeItem(at: item) } catch { problems.append("\(item.lastPathComponent): \(error.localizedDescription)") }
                }
                continue
            }
            do { try fm.removeItem(at: url) } catch { problems.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
            // Kept with the stills: a reinstall reads them and puts the wallpaper back.
            if stills != nil, let memory { UserDefaults.standard.set(memory, forKey: SystemWallpaper.memoryKey) }
            if stills != nil, let sharksMemory {
                UserDefaults.standard.set(sharksMemory, forKey: SystemWallpaper.sharksMemoryCopyKey)
            }
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
