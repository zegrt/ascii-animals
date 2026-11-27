import Foundation
import OceanKit

/// This copy's identity and launch plan, decided once from its bundle ID (`AppIdentity`, `LaunchPlan`). Every side
/// effect that reaches past the app's own domain and folders asks here: the updater, the hand-over, the uninstaller,
/// the system wallpaper and the login item.
enum Launch {
    static let identity = AppIdentity(bundleID: Bundle.main.bundleIdentifier)
    /// A `--snapshot-*` run (a probe or a picture): never a launch energy.sh made, so it never carries a launch id.
    static let snapshotRun: Bool = CommandLine.arguments.contains { (a: String) -> Bool in a.hasPrefix("--snapshot-") }
    static let plan = LaunchPlan(identity: identity, environment: launchEnvironment)

    /// The environment the plan reads; a snapshot run drops the launch id, so its log lines never pass as a live
    /// launch's evidence.
    static var launchEnvironment: [String: String] {
        var env: [String: String] = ProcessInfo.processInfo.environment
        if snapshotRun { env[LaunchPlan.launchFlag] = nil }
        return env
    }

    /// The energy-test copy's one folder (`EnergyTestFolder`): `build/energy-test` next to its bundle. Nil in any other
    /// copy.
    static let testFolder: URL? = identity.isEnergyTest ? EnergyTestFolder.url(bundle: Bundle.main.bundleURL) : nil

    /// Where a `--snapshot-*` output may be written. Any copy but the energy-test copy: the path as given (as
    /// before). The energy-test copy: only a new or plain file strictly inside its folder, judged with symbolic links
    /// resolved (the folder and the output's parent must exist); otherwise nil and nothing is written.
    static func snapshotOutput(_ path: String) -> URL? {
        let url: URL = URL(fileURLWithPath: path)
        guard let folder = testFolder else { return url }
        return confined(url, to: folder)
    }

    /// `url` if it lies strictly inside `folder` (links resolved) and is not itself a link; else nil.
    static func confined(_ url: URL, to folder: URL) -> URL? {
        let name: String = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name != "/" else { return nil }
        guard let realFolder = realPath(folder.path),
              let realParent = realPath(url.deletingLastPathComponent().path) else { return nil }
        let target: String = realParent + "/" + name
        guard EnergyTestFolder.contains(target, in: realFolder) else { return nil }
        // An existing file must be a plain one: a link could point anywhere, and a PNG write follows it.
        if let type = (try? FileManager.default.attributesOfItem(atPath: target))?[.type] as? FileAttributeType,
           type != .typeRegular {
            return nil
        }
        return URL(fileURLWithPath: target)
    }

    /// The path with every symbolic link resolved (realpath(3)); nil when it does not exist.
    static func realPath(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }
}
