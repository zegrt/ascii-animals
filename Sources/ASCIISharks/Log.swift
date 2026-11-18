import Foundation

/// A small rolling log at ~/Library/Logs/ASCII Sharks/ascii-sharks.log
/// (512 KB, one backup). It stays on this Mac; Report a Problem includes
/// its last lines only when the user asks.
enum Log {
    static let folder = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/ASCII Sharks", isDirectory: true)
    static let file = folder.appendingPathComponent("ascii-sharks.log")
    private static let queue = DispatchQueue(label: "ascii-sharks.log")
    private static let limit = 512 * 1024
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func write(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > limit {
                let backup = folder.appendingPathComponent("ascii-sharks.1.log")
                try? fm.removeItem(at: backup)
                try? fm.moveItem(at: file, to: backup)
            }
            if let h = try? FileHandle(forWritingTo: file) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: file)
            }
        }
    }

    /// The last `n` lines, oldest first.
    static func tail(_ n: Int) -> [String] {
        queue.sync {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
            return Array(text.split(separator: "\n").suffix(n).map(String.init))
        }
    }
}

/// Knows whether the last session ended without a clean quit.
enum CrashMarker {
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ASCII Sharks", isDirectory: true)
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
