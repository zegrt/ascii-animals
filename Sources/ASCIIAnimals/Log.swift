import Foundation
import OceanKit

/// A small rolling log at ~/Library/Logs/ASCII Animals/ascii-animals.log
/// (512 KB, one backup). It stays on this Mac; Report a Problem includes
/// its last entries only when the user asks, and only entries this version wrote: its first start deletes an older
/// log and begins a fresh one (`LogFile.start`), once. The energy-test copy keeps its log in its own folder under the
/// checkout's `build/energy-test/app` (`Launch.testFolder`), where Tools/energy.sh reads it.
enum Log {
    static let folder: URL = Launch.testFolder?.appendingPathComponent(EnergyTestFolder.appFolder, isDirectory: true)
        ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(Launch.identity.folderName, isDirectory: true)
    static let file = folder.appendingPathComponent("ascii-animals.log")
    static let backup = folder.appendingPathComponent("ascii-animals.1.log")
    private static let queue = DispatchQueue(label: "ascii-animals.log")
    private static let limit = 512 * 1024
    /// The run's first use of the log (on `queue`) starts it: `LogFile.start`, once per run.
    private static let started: Bool = LogFile.start(file: file, backup: backup)
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func write(_ message: String) {
        let line = LogEntries.entry(stamp: stamp.string(from: Date()), message: message)
        queue.async {
            _ = started
            LogFile.append(line, file: file, backup: backup, limit: limit)
        }
    }

    /// The last `n` entries, oldest first, each whole: its stamped line and the lines its message ran on to
    /// (`LogEntries`). Report a Problem takes the log this way, never by lines.
    static func entries(_ n: Int) -> [String] {
        queue.sync {
            _ = started
            guard let data = try? Data(contentsOf: file) else { return [] }
            return LogEntries.last(n, in: String(decoding: data, as: UTF8.self))
        }
    }

    /// The last `n` lines, oldest first.
    static func tail(_ n: Int) -> [String] {
        queue.sync {
            _ = started
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
            return Array(text.split(separator: "\n").suffix(n).map(String.init))
        }
    }
}

/// Knows whether the last session ended without a clean quit. The energy-test copy keeps its marker beside its log
/// (`build/energy-test/app`).
enum CrashMarker {
    static let folder: URL = Launch.testFolder?.appendingPathComponent(EnergyTestFolder.appFolder, isDirectory: true)
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Launch.identity.folderName, isDirectory: true)
    static let file = folder.appendingPathComponent("running")

    /// Call at launch: true if the previous run didn't quit cleanly.
    static func launch() -> Bool {
        let fm = FileManager.default
        let crashed = fm.fileExists(atPath: file.path)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data("\(getpid())".utf8).write(to: file)
        return crashed
    }

    static func cleanQuit() { try? FileManager.default.removeItem(at: file) }
}
