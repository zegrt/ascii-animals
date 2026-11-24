import AppKit
import CryptoKit
import OceanKit
import Security

/// Installs a release over the running copy in three steps: `stage` downloads
/// the zipped app and checks it (GitHub's SHA-256, the bundle identifier and
/// version, the code signature) without touching the installed app; `commit`
/// swaps it in with one atomic rename; `scheduleRelaunch` opens the new copy
/// once this one has quit. If any step fails, the installed app is left exactly
/// as it was.
enum SelfUpdater {
    typealias Failure = UpdateFailure

    static let repoPath = "zegrt/ascii-animals"
    private static let work = DispatchQueue(label: "SelfUpdater")

    /// Why this copy can't replace itself, or nil when it can.
    static func blocker() -> String? {
        guard Launch.plan.startsUpdates else { return "The energy-test copy never updates itself." }
        let bundle = Bundle.main.bundleURL
        if let why = SelfUpdate.blocker(bundlePath: bundle.path) { return why }
        let folder = bundle.deletingLastPathComponent()
        if (try? folder.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true {
            return "ASCII Animals is running from a disk image. Drag it into Applications, open it from there, and try again."
        }
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: folder.path), fm.isWritableFile(atPath: bundle.path) else {
            return "ASCII Animals can't replace itself in “\(folder.lastPathComponent)” with your account's permissions."
        }
        return nil
    }

    /// Downloads and checks `r` next to the installed app (same volume, so the swap is a rename). `done` runs on the
    /// main thread with the checked copy.
    static func stage(_ r: LatestRelease, done: @escaping (Result<StagedUpdate, Failure>) -> Void) {
        let finish: (Result<StagedUpdate, Failure>) -> Void = { result in DispatchQueue.main.async { done(result) } }
        guard Launch.plan.startsUpdates else { return finish(.failure(Failure("The energy-test copy never updates itself."))) }
        guard let url = r.zipURL, SelfUpdate.isTrustedDownload(url, repoPath: repoPath) else {
            return finish(.failure(Failure("This release can't be installed from inside the app.")))
        }
        guard let sha = r.zipSHA256 else {
            return finish(.failure(Failure("GitHub didn't give a checksum for this download, so it can't be verified.")))
        }
        let temp: URL
        do {
            temp = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                               appropriateFor: Bundle.main.bundleURL, create: true)
        } catch {
            return finish(.failure(Failure("Couldn't make a folder for the download: \(error.localizedDescription)",
                                           log: "Couldn't make a folder for the download: \(Failure.code(of: error))")))
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        req.setValue("ASCIIAnimals/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.downloadTask(with: req) { file, response, error in
            // `file` is deleted when this returns, so keep it first.
            let zip = temp.appendingPathComponent("update.zip")
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let file, status == 200, (try? FileManager.default.moveItem(at: file, to: zip)) != nil else {
                try? FileManager.default.removeItem(at: temp)
                let why = error?.localizedDescription ?? "GitHub answered \(status)."
                let logged = error.map { Failure.code(of: $0) } ?? why
                return finish(.failure(Failure("The download failed: \(why)", log: "The download failed: \(logged)")))
            }
            work.async {
                let result = Result { try checkDownloaded(zip, sha256: sha, release: r, in: temp) }
                    .map { StagedUpdate(release: r, app: $0, folder: temp) }
                    .mapError { $0 as? Failure ?? Failure($0.localizedDescription, log: Failure.code(of: $0)) }
                if case .failure = result { try? FileManager.default.removeItem(at: temp) }
                finish(result)
            }
        }.resume()
    }

    /// Stages `r` and swaps it in at once (the identity probe's way in; the updater decides between the two steps).
    static func install(_ r: LatestRelease, done: @escaping (Result<URL, Failure>) -> Void) {
        stage(r) { staged in done(staged.flatMap { commit($0) }) }
    }

    /// Swaps the staged copy in for the installed app (one rename) and returns where it went.
    static func commit(_ staged: StagedUpdate) -> Result<URL, Failure> {
        defer { discard(staged) }
        do {
            guard let installed = try FileManager.default.replaceItemAt(Bundle.main.bundleURL, withItemAt: staged.app) else {
                return .failure(Failure("macOS didn't say where the new version went."))
            }
            return .success(installed)
        } catch {
            return .failure(Failure("Couldn't replace the app: \(error.localizedDescription)",
                                    log: "Couldn't replace the app: \(Failure.code(of: error))"))
        }
    }

    /// Removes a staged download.
    static func discard(_ staged: StagedUpdate) {
        try? FileManager.default.removeItem(at: staged.folder)
    }

    /// Checks the downloaded zip and unpacks it; returns the checked app, ready to swap in.
    private static func checkDownloaded(_ zip: URL, sha256: String, release r: LatestRelease, in temp: URL) throws -> URL {
        let fm = FileManager.default
        let data = try Data(contentsOf: zip, options: .mappedIfSafe)
        let got = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard got == sha256 else { throw Failure("The download doesn't match GitHub's checksum.") }

        // Unpacked next to the installed app (same volume), so the swap is a rename.
        let unpacked = temp.appendingPathComponent("unpacked")
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])

        // Read Info.plist directly: Bundle caches by path and can answer stale.
        func info(_ app: URL) -> [String: Any]? {
            NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        }
        let expectedID = Bundle.main.bundleIdentifier ?? ""
        let items = try fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
        let apps = items.filter { $0.pathExtension == "app" }
        guard let found = apps.first(where: { info($0)?["CFBundleIdentifier"] as? String == expectedID }) ?? apps.first else {
            throw Failure("The download doesn't contain an app (found \(items.map(\.lastPathComponent).joined(separator: ", "))).")
        }
        let plist = info(found)
        if let why = SelfUpdate.candidateProblem(bundleID: plist?["CFBundleIdentifier"] as? String,
                                                 version: plist?["CFBundleShortVersionString"] as? String,
                                                 expectedID: expectedID, expectedVersion: r.version) {
            throw Failure(why)
        }

        try checkSignature(found, identifier: expectedID)
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", found.path])
        return found
    }

    /// The bundle's signature is intact (every file, every architecture) and
    /// it's signed as this app.
    private static func checkSignature(_ app: URL, identifier: String) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw Failure("The new version's signature can't be read.")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        var err: Unmanaged<CFError>?
        guard SecStaticCodeCheckValidityWithErrors(code, flags, nil, &err) == errSecSuccess else {
            let cf: CFError? = err?.takeRetainedValue()
            let why = cf.map { CFErrorCopyDescription($0) as String } ?? "invalid"
            let logged = cf.map { Failure.code(of: $0) } ?? "invalid"
            throw Failure("The new version's signature doesn't check out (\(why)).",
                          log: "The new version's signature doesn't check out (\(logged)).")
        }
        var info: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let signedAs = (info as? [String: Any])?[kSecCodeInfoIdentifier as String] as? String
        guard signedAs == identifier else { throw Failure("The new version is signed as a different app.") }
    }

    /// Opens `app` once this process has gone. Waiting matters: a second copy that starts while this one runs quits
    /// straight away. False when the waiting helper couldn't be started (then nothing should quit).
    static func scheduleRelaunch(_ app: URL) -> Bool {
        guard Launch.plan.startsUpdates else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", #"i=0; while /bin/kill -0 "$1" 2>/dev/null && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done; exec /usr/bin/open "$2""#,
                       "relaunch", String(getpid()), app.path]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            return true
        } catch {
            Log.write("couldn't schedule the restart: \(error)")
            return false
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard p.terminationStatus == 0 else {
            throw Failure("\(URL(fileURLWithPath: tool).lastPathComponent) failed: \(text.prefix(200))")
        }
        return text
    }
}
