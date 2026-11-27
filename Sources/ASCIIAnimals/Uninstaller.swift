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
        a.informativeText = "Your own wallpaper comes back, and ASCII Animals removes its settings, logs and login item, then moves itself to the Trash."
        a.alertStyle = .warning
        a.addButton(withTitle: "Uninstall")
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    /// Returns what it couldn't do (empty when everything went). The person's wallpaper comes back on each display's
    /// Space in view; a Space not in view may still show a still, so the Stills folder stays while it holds any file,
    /// and the first line says so.
    @discardableResult
    static func run(app: AppDelegate?, wallpaper: SystemWallpaper? = nil) -> [String] {
        guard Launch.plan.offersUninstall else { return ["the energy-test copy has no uninstaller"] }
        var problems: [String] = []
        app?.isUninstalling = true
        let wp: SystemWallpaper? = wallpaper ?? app?.wallpaper
        wp?.beginUninstall()   // no still goes up and nothing reconciles from here on, even under an alert
        wp?.restoreAll()
        let fm = FileManager.default
        let folder: URL = wp?.stillsFolder ?? CrashMarker.folder.appendingPathComponent("Stills", isDirectory: true)
        let data: RestoreData = SystemWallpaper.restoreData(stillsFolder: folder)
        let kept: RestoreData.Kept = data.keepOnUninstall(stillsFolder: folder, sharksStills: SystemWallpaper.sharksStillsFolder)
        let stills: URL? = kept.folder ? folder : nil
        if let stills { problems.append(WallpaperKeeper.uninstallNote(stillsFolder: stills)) }
        do { try LoginItem.set(false) } catch { if LoginItem.isEnabled { problems.append("login item: \(error.localizedDescription)") } }
        for url in [CrashMarker.folder, Log.folder] where fm.fileExists(atPath: url.path) {
            if let stills, url == CrashMarker.folder {
                // Everything but the Stills folder.
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
            UserDefaults.standard.synchronize()
            CFPreferencesAppSynchronize(id as CFString)
        }
        if kept.keepsSettings {
            // The restore data couldn't go into the Stills folder: the settings keep it for a reinstall.
            let e = JSONEncoder()
            if let m = try? e.encode(data.memory) { UserDefaults.standard.set(m, forKey: SystemWallpaper.memoryKey) }
            if let s = data.sharks, let m = try? e.encode(s) { UserDefaults.standard.set(m, forKey: SystemWallpaper.sharksMemoryCopyKey) }
            UserDefaults.standard.synchronize()
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
