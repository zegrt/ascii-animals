import Foundation
import OceanKit

func wallpaperChecks() {
    let stills = URL(fileURLWithPath: "/tmp/ascii-animals-check/Stills", isDirectory: true)
    let a = WallpaperEntry(url: URL(fileURLWithPath: "/System/Library/Desktop Pictures/A.heic"), scaling: 3, allowClipping: true, fillColor: [0, 0, 0, 1])
    let b = WallpaperEntry(url: URL(fileURLWithPath: "/Users/me/Pictures/B.jpg"), scaling: nil, allowClipping: nil, fillColor: nil)
    /// Our file over A on display S.
    let ours = stills.appendingPathComponent(WallpaperMemory.fileName(display: "S", code: WallpaperMemory.code(for: a), slot: "A"))
    /// A memory as 3.0 (or ASCII Sharks) wrote it: the original it saved for each display.
    func saved(_ originals: [String: WallpaperEntry]) throws -> WallpaperMemory {
        try JSONDecoder().decode(WallpaperMemory.self, from: JSONEncoder().encode(["originals": originals]))
    }

    check("wallpaperMemoryIgnoresOwnStills") {
        var m = WallpaperMemory()
        try expect(m.nextStill(on: "S", over: WallpaperEntry(url: ours), stillsFolder: stills) != nil, "ours not applied")
        try expect(m.original(for: "S") == nil && m.covered.isEmpty, "recorded our own still as the person's")
    }
    check("wallpaperSymlinkedStillIsOurs") {
        // /tmp is a symlink to /private/tmp on macOS.
        var m = WallpaperMemory()
        let viaPrivate = URL(fileURLWithPath: "/private/tmp/ascii-animals-check/Stills").appendingPathComponent(ours.lastPathComponent)
        _ = m.nextStill(on: "S", over: WallpaperEntry(url: viaPrivate), stillsFolder: stills)
        try expect(m.original(for: "S") == nil && m.covered.isEmpty, "symlinked still recorded as the person's")
    }
    // Replaces wallpaperMemoryKeepsFirstOriginal (3.0 kept the first original and left any other picture alone).
    check("wallpaperEachOwnWallpaperGoesBack") {
        var m = WallpaperMemory()
        let overA: URL? = m.nextStill(on: "S", over: a, stillsFolder: stills)
        let overB: URL? = m.nextStill(on: "S", over: b, stillsFolder: stills)   // another Space, or the person's new pick
        guard let overA, let overB else { throw CheckFailure(detail: "a wallpaper of the person's got no still") }
        try expect(m.original(for: "S") == b, "B, seen last, isn't the display's wallpaper")
        try expect(m.under(WallpaperEntry(url: overA), on: "S", stillsFolder: stills) == a
                   && m.under(WallpaperEntry(url: overB), on: "S", stillsFolder: stills) == b,
                   "a still doesn't go back to the wallpaper it covers")
    }
    check("wallpaperSameOriginalApplies") {
        var m = WallpaperMemory()
        let first: URL? = m.nextStill(on: "S", over: a, stillsFolder: stills)
        try expect(first != nil && m.nextStill(on: "S", over: a, stillsFolder: stills) == first, "same original refused or given another file")
    }
    check("wallpaperRestoreOnlyWhereOurs") {
        var m = WallpaperMemory()
        _ = m.nextStill(on: "S", over: a, stillsFolder: stills)
        try expect(m.under(WallpaperEntry(url: ours), on: "S", stillsFolder: stills) == a, "no restore over our still")
        try expect(WallpaperMemory.showing(b, stillsFolder: stills) == .own(b) && m.under(b, on: "S", stillsFolder: stills) == nil,
                   "restored over a wallpaper of the person's")
    }
    // Replaces wallpaperRestoreForgets (a restore no longer forgets anything: each file names what it covers).
    check("wallpaperNewChoiceAfterRestoreIsTheirs") {
        var m = WallpaperMemory()
        guard let overA = m.nextStill(on: "S", over: a, stillsFolder: stills) else { throw CheckFailure(detail: "no still over A") }
        // Put back, then the person picks B.
        try expect(m.nextStill(on: "S", over: b, stillsFolder: stills) != nil, "new wallpaper refused after restore")
        try expect(m.original(for: "S") == b, "new wallpaper not taken as the person's")
        try expect(m.under(WallpaperEntry(url: overA), on: "S", stillsFolder: stills) == a, "a still left on another Space lost A")
    }
    // ASCII Sharks, force-quit, can leave its still up; it's never the user's own wallpaper.
    let sharksStills = URL(fileURLWithPath: "/tmp/ascii-animals-check/Sharks/Stills", isDirectory: true)
    let sharksStill = WallpaperEntry(url: sharksStills.appendingPathComponent("still-S-9.png"))
    check("wallpaperSharksStillIsNotTheUsers") {
        var m = WallpaperMemory()
        let none = ForeignStills(folder: sharksStills)
        // Nothing known under it: left alone (it can't be put back), never taken for the person's.
        try expect(m.nextStill(on: "S", over: sharksStill, stillsFolder: stills, foreign: none) == nil, "a still went over an unknown Sharks still")
        try expect(m.original(for: "S") == nil && m.covered.isEmpty, "Sharks' still recorded as the user's")
        // Without the foreign folder it would have been taken for the user's (the old behaviour).
        var old = WallpaperMemory()
        _ = old.nextStill(on: "S", over: sharksStill, stillsFolder: stills)
        try expect(old.original(for: "S") == sharksStill, "control: without Sharks' folder it is taken for the person's")
    }
    check("wallpaperSharksMemoryAdopted") {
        // What Sharks remembered under its still is what our still over it covers, and comes back on restore.
        let foreign = ForeignStills(folder: sharksStills, memory: try saved(["S": a]))
        var m = WallpaperMemory()
        guard let over = m.nextStill(on: "S", over: sharksStill, stillsFolder: stills, foreign: foreign) else {
            throw CheckFailure(detail: "not applied")
        }
        try expect(m.under(WallpaperEntry(url: over), on: "S", stillsFolder: stills, foreign: foreign) == a, "no restore to Sharks' original")
        // Never over a wallpaper the user chose, and Sharks' memory doesn't override ours.
        var mine = WallpaperMemory()
        _ = mine.nextStill(on: "S", over: b, stillsFolder: stills, foreign: foreign)
        _ = mine.nextStill(on: "S", over: sharksStill, stillsFolder: stills, foreign: foreign)
        try expect(mine.original(for: "S") == b, "our own original replaced")
        var fresh = WallpaperMemory()
        try expect(fresh.nextStill(on: "T", over: b, stillsFolder: stills, foreign: foreign) != nil, "first wallpaper refused")
        try expect(fresh.original(for: "T") == b, "the user's wallpaper not recorded")
    }
    check("wallpaperRestoresOverSharksStill") {
        let foreign = ForeignStills(folder: sharksStills, memory: try saved(["S": a]))
        let m = WallpaperMemory()
        try expect(m.under(sharksStill, on: "S", stillsFolder: stills, foreign: foreign) == a, "Sharks' still left up")
        try expect(m.under(b, on: "S", stillsFolder: stills, foreign: foreign) == nil, "restored over the user's wallpaper")
        try expect(m.under(sharksStill, on: "T", stillsFolder: stills, foreign: foreign) == nil, "invented an original")
    }
    check("wallpaperMemoryRoundTrips") {
        var m = WallpaperMemory()
        _ = m.nextStill(on: "S", over: a, stillsFolder: stills)
        _ = m.nextStill(on: "T", over: b, stillsFolder: stills)
        let back = try JSONDecoder().decode(WallpaperMemory.self, from: JSONEncoder().encode(m))
        try expect(back == m, "round trip changed memory")
        // A memory 3.0 wrote reads as its saved originals, and keeps them through a round trip.
        let old: WallpaperMemory = try saved(["S": a])
        let again = try JSONDecoder().decode(WallpaperMemory.self, from: JSONEncoder().encode(old))
        try expect(old.original(for: "S") == a && again == old, "3.0's original lost: \(String(describing: again.original(for: "S")))")
    }
}

// MARK: - r2: the person's own wallpaper always comes back (audit a1 finding 2; finding 10, wallpaper part)

/// A desktop with Spaces: each display has its own Spaces, one in view; reads and sets act on the Space in view.
/// Displays come and go (their Spaces keep their pictures), and read, set and remove can fail on demand.
final class FakeDesktop: DesktopImages {
    struct Failure: Error {}
    private var order: [String] = []
    private var spaces: [String: [WallpaperEntry]] = [:]
    private var inView: [String: Int] = [:]
    private(set) var attached: Set<String> = []
    private(set) var files: Set<URL> = []
    /// Displays whose picture can't be read.
    var unreadable: Set<String> = []
    /// Displays where setting a picture throws.
    var setFails: Set<String> = []
    /// Displays where setting a picture says yes but nothing changes.
    var setIgnored: Set<String> = []
    /// Displays where setting a picture throws after it took effect (or, with `setIgnored`, after doing nothing).
    var setThrowsAfter: Set<String> = []
    /// Runs inside each set that gets as far as the picture (before `setThrowsAfter` throws).
    var onSet: ((String) -> Void)?
    var removeFails = false
    /// Listing a stills folder throws.
    var listFails = false

    /// A display with `spaces` Spaces, each showing `picture`, the first in view.
    func attach(_ display: String, spaces count: Int = 1, showing picture: WallpaperEntry) {
        if spaces[display] == nil {
            order.append(display)
            spaces[display] = [WallpaperEntry](repeating: picture, count: count)
            inView[display] = 0
        }
        attached.insert(display)
    }
    func detach(_ display: String) { attached.remove(display) }
    func reattach(_ display: String) { attached.insert(display) }
    func view(space: Int, on display: String) { inView[display] = space }
    func picture(on display: String, space: Int) -> WallpaperEntry { spaces[display]![space] }
    /// The renderer wrote a still.
    func write(_ url: URL) { files.insert(url.standardizedFileURL) }
    func exists(_ url: URL) -> Bool { files.contains(url.standardizedFileURL) }

    var displays: [String] { order.filter { attached.contains($0) } }
    func current(on display: String) -> WallpaperEntry? {
        guard attached.contains(display), !unreadable.contains(display), let s = inView[display] else { return nil }
        return spaces[display]?[s]
    }
    func set(_ entry: WallpaperEntry, on display: String) throws {
        guard attached.contains(display), !setFails.contains(display), let s = inView[display] else { throw Failure() }
        if !setIgnored.contains(display) { spaces[display]![s] = entry }
        onSet?(display)
        if setThrowsAfter.contains(display) { throw Failure() }
    }
    func stillFiles(in folder: URL) throws -> [URL] {
        if listFails { throw Failure() }
        return files.filter { WallpaperMemory.isOurs($0, stillsFolder: folder) }.sorted { $0.path < $1.path }
    }
    func removeFile(_ url: URL) throws {
        if removeFails { throw Failure() }
        files.remove(url.standardizedFileURL)
    }
}

func wallpaperKeeperChecks() {
    let stills = URL(fileURLWithPath: "/tmp/ascii-animals-check/Stills", isDirectory: true)
    let a = WallpaperEntry(url: URL(fileURLWithPath: "/System/Library/Desktop Pictures/A.heic"), scaling: 3, allowClipping: true, fillColor: [0, 0, 0, 1])
    let b = WallpaperEntry(url: URL(fileURLWithPath: "/Users/me/Pictures/B.jpg"), scaling: nil, allowClipping: nil, fillColor: nil)

    func keeper(_ desk: FakeDesktop, _ memory: WallpaperMemory = WallpaperMemory()) -> WallpaperKeeper {
        WallpaperKeeper(memory: memory, stillsFolder: stills, desktop: desk)
    }
    func isStill(_ e: WallpaperEntry) -> Bool { WallpaperMemory.isOurs(e.url, stillsFolder: stills) }
    /// What the app does when a look changes: render (here: write) a still and put it up.
    @discardableResult
    func applyStill(_ k: WallpaperKeeper, _ desk: FakeDesktop, on display: String) -> URL? {
        guard k.mayApply(on: display) else { return nil }
        let url: URL = k.newStill(for: display)
        desk.write(url)
        return k.commit(url, on: display) ? url : nil
    }
    /// A memory as 3.0 wrote it: the original it saved for each display, no more.
    func legacy(_ originals: [String: WallpaperEntry]) throws -> WallpaperMemory {
        try JSONDecoder().decode(WallpaperMemory.self, from: JSONEncoder().encode(["originals": originals]))
    }
    /// A 3.0 still (`still-<display>-<milliseconds>.png`) left up on a Space.
    func legacyStill(_ desk: FakeDesktop, on display: String, space: Int, millis: Int) throws -> URL {
        let url: URL = stills.appendingPathComponent("still-\(display)-\(millis).png")
        desk.write(url)
        desk.view(space: space, on: display)
        try desk.set(WallpaperKeeper.stillEntry(url), on: display)
        return url
    }

    // 1. The original is never overwritten by our own still: a second restore can't forget it.
    // (Rebuilt: the keeper names the files, `<display>-<code>-<A|B>.png`.)
    check("wallpaperOriginalSurvivesASecondRestore") {
        let desk = FakeDesktop()
        desk.attach("S", spaces: 2, showing: a)
        let k = keeper(desk)
        applyStill(k, desk, on: "S")
        desk.view(space: 1, on: "S")
        applyStill(k, desk, on: "S")   // a look change on Space 2
        k.restoreAll()   // quit, on Space 2
        try expect(desk.picture(on: "S", space: 1) == a, "Space 2 not restored")
        // Next launch, matching on, Space 1 in view: still showing our still from last time.
        desk.view(space: 0, on: "S")
        applyStill(k, desk, on: "S")
        let out: RestoreOutcome = k.restoreAll()   // quit again
        let back: WallpaperEntry = desk.picture(on: "S", space: 0)
        try expect(back == a, "Space 1 kept the habitat after the second restore: \(back.url.lastPathComponent); \(out)")
    }

    // 2. A still on show is never deleted. (Rebuilt: no file is ever deleted; no per-still records.)
    check("wallpaperStillInUseIsNotDeleted") {
        let desk = FakeDesktop()
        desk.attach("S", spaces: 5, showing: a)
        let k = keeper(desk)
        var put: [URL] = []
        for space in 0..<5 {
            desk.view(space: space, on: "S")
            if let url = applyStill(k, desk, on: "S") { put.append(url) }
        }
        try expect(put.count == 5, "only \(put.count) of 5 stills went up")
        desk.view(space: 0, on: "S")
        applyStill(k, desk, on: "S")   // a look change on Space 1 writes the other file
        for space in 0..<5 {
            let shown: WallpaperEntry = desk.picture(on: "S", space: space)
            try expect(desk.exists(shown.url), "Space \(space + 1) shows \(shown.url.lastPathComponent), which was deleted")
        }
        let out: RestoreOutcome = k.restoreAll()
        try expect(out.restored == ["S"] && desk.picture(on: "S", space: 0) == a, "Space 1 not restored: \(out)")

        // Upgrading from 3.0: its stills may be up on other Spaces.
        let old = FakeDesktop()
        old.attach("S", spaces: 5, showing: a)
        for space in 0..<5 { _ = try legacyStill(old, on: "S", space: space, millis: 1_700_000_000_000 + space) }
        let k2 = keeper(old, try legacy(["S": a]))
        old.view(space: 0, on: "S")
        applyStill(k2, old, on: "S")
        for space in 1..<5 {
            let shown: WallpaperEntry = old.picture(on: "S", space: space)
            try expect(old.exists(shown.url), "after the upgrade, Space \(space + 1)'s still \(shown.url.lastPathComponent) was deleted")
        }
        old.view(space: 3, on: "S")
        let up: RestoreOutcome = k2.restoreAll()
        try expect(up.restored == ["S"] && old.picture(on: "S", space: 3) == a, "a 3.0 still not restored: \(up)")
    }

    // 3. Recovery material stays until a restore is verified; uninstall keeps it and says so when a restore failed.
    check("wallpaperRecoveryKeptUntilRestoreVerified") {
        // a. Setting says yes but nothing changes: not restored, original and still kept.
        let desk = FakeDesktop()
        desk.attach("S", showing: a)
        let k = keeper(desk)
        guard let still = applyStill(k, desk, on: "S") else { throw CheckFailure(detail: "no still went up") }
        desk.setIgnored = ["S"]
        let ignored: RestoreOutcome = k.restoreAll()
        try expect(ignored.failed == ["S"] && ignored.restored.isEmpty, "an unchanged picture counted as restored: \(ignored)")
        try expect(desk.exists(still), "the still in use was deleted after a failed restore")
        desk.setIgnored = []
        let retry: RestoreOutcome = k.restoreAll()
        try expect(retry.restored == ["S"] && desk.picture(on: "S", space: 0) == a, "the original was forgotten after a failed restore: \(retry)")

        // b. Uninstall with one display failing (set throws) and one unreadable: keep the material, say so.
        let desk2 = FakeDesktop()
        desk2.attach("S", showing: a)
        desk2.attach("T", showing: b)
        desk2.attach("U", showing: a)
        let k2 = keeper(desk2)
        applyStill(k2, desk2, on: "S")
        applyStill(k2, desk2, on: "T")
        applyStill(k2, desk2, on: "U")
        desk2.setFails = ["S"]
        desk2.unreadable = ["U"]
        let out: RestoreOutcome = k2.restoreAll()
        try expect(out.restored == ["T"], "restored: \(out.restored)")
        try expect(Set(out.failed) == ["S", "U"], "a failed or unreadable display not reported: \(out.failed)")
        try expect(out.keepsRecovery, "uninstall would delete the stills and the memory after a failed restore")
        // (Rebuilt: uninstall says the brief's sentence; it no longer names the picture.)
        let note: String = WallpaperKeeper.uninstallNote(stillsFolder: stills)
        try expect(note == "If a desktop still shows the animals, choose your wallpaper in System Settings, then delete this folder: \(stills.path).",
                   "uninstall says: \(note)")
        try expect(k2.memory.original(for: "S") == a, "the original was forgotten")

        // c. Everything verified on the Space in view: nothing failed, and the still stays for a Space not in view.
        // (Rebuilt: a clean restore no longer deletes the stills.)
        let desk3 = FakeDesktop()
        desk3.attach("S", spaces: 2, showing: a)
        let k3 = keeper(desk3)
        guard let shown = applyStill(k3, desk3, on: "S") else { throw CheckFailure(detail: "no still went up") }
        desk3.view(space: 1, on: "S")
        try desk3.set(WallpaperKeeper.stillEntry(shown), on: "S")   // a Space not in view shows it too
        desk3.view(space: 0, on: "S")
        let clean: RestoreOutcome = k3.restoreAll()
        try expect(clean.restored == ["S"] && clean.failed.isEmpty && !clean.keepsRecovery, "a verified restore failed: \(clean)")
        try expect(desk3.exists(shown), "a clean restore deleted the still a Space not in view shows")
        desk3.view(space: 1, on: "S")
        k3.reconcile(matching: false)
        try expect(desk3.picture(on: "S", space: 1) == a, "the Space not in view didn't get A back on its visit")
    }

    // 4. A display that comes back gets its picture back.
    check("wallpaperDisplayBackGetsItsPicture") {
        let desk = FakeDesktop()
        desk.attach("S", showing: a)
        desk.attach("T", showing: b)
        let k = keeper(desk)
        applyStill(k, desk, on: "S")
        applyStill(k, desk, on: "T")
        desk.detach("T")
        k.restoreAll()   // matching turned off with T unplugged
        try expect(desk.picture(on: "S", space: 0) == a, "S not restored")
        try expect(isStill(desk.picture(on: "T", space: 0)), "control: T kept the still while unplugged")
        desk.reattach("T")
        k.reconcile(matching: false)   // the display comes back
        let back: WallpaperEntry = desk.picture(on: "T", space: 0)
        try expect(back == b, "T came back still showing \(back.url.lastPathComponent)")
        // And after a restart: a fresh keeper on the saved memory, matching off.
        let desk2 = FakeDesktop()
        desk2.attach("T", showing: b)
        let k2 = keeper(desk2)
        applyStill(k2, desk2, on: "T")
        let saved: WallpaperMemory = k2.memory   // killed here: no restore
        let k3 = keeper(desk2, saved)
        k3.reconcile(matching: false)   // launch
        try expect(desk2.picture(on: "T", space: 0) == b, "a restart with matching off left the still up")
    }

    // 5. Still files are unique per display and covered wallpaper, and a refresh never writes the file in view.
    // (Replaces wallpaperStillNamesAreUnique: a new name per still is what the rebuild reverses.)
    check("wallpaperStillFilesAreUniquePerDisplay") {
        let desk = FakeDesktop()
        desk.attach("S", spaces: 2, showing: a)
        desk.view(space: 1, on: "S")
        try desk.set(b, on: "S")
        desk.attach("T", showing: a)
        let k = keeper(desk)
        var names: Set<String> = []
        for i in 0..<10 {
            desk.view(space: i % 2, on: "S")
            for display in ["S", "T"] {
                let before: WallpaperEntry? = desk.current(on: display)
                guard let url = applyStill(k, desk, on: display) else { throw CheckFailure(detail: "no still on \(display)") }
                try expect(before.map { !WallpaperMemory.same($0.url, url) } ?? true, "a refresh rewrote the file in view: \(url.lastPathComponent)")
                names.insert(url.lastPathComponent)
            }
        }
        try expect(names.count == 6, "\(names.count) files for 3 covered wallpapers (S: A and B; T: A)")
        try expect(names.allSatisfy { ($0.hasPrefix("S-") || $0.hasPrefix("T-")) && $0.hasSuffix(".png") }, "a name lost the display or the type")
    }

    // Control: the everyday path (apply, look change, quit) puts the picture back with its options.
    check("wallpaperEverydayRoundTrip") {
        let desk = FakeDesktop()
        desk.attach("S", showing: b)
        let k = keeper(desk)
        applyStill(k, desk, on: "S")
        applyStill(k, desk, on: "S")
        try expect(isStill(desk.picture(on: "S", space: 0)), "no still up")
        let out: RestoreOutcome = k.restoreAll()
        try expect(out.restored == ["S"] && out.failed.isEmpty && desk.picture(on: "S", space: 0) == b, "not restored: \(out)")
        // The user's own picture is never touched by a restore.
        let again: RestoreOutcome = k.restoreAll()
        try expect(again.restored.isEmpty && again.failed.isEmpty, "restored over the user's own picture: \(again)")
    }

    // MARK: fix round 1 (review-r2 @ e004c95)

    // F1 (finding 1). An adopted 3.0 still puts back the picture saved for its display when it was adopted, never
    // what the display's original became later.
    check("wallpaperAdoptedStillKeepsItsOriginal") {
        let desk = FakeDesktop()
        desk.attach("S", spaces: 3, showing: a)
        _ = try legacyStill(desk, on: "S", space: 0, millis: 1_700_000_000_000)
        _ = try legacyStill(desk, on: "S", space: 1, millis: 1_700_000_000_001)
        desk.view(space: 2, on: "S")
        try desk.set(b, on: "S")   // the person's own B on Space 3
        let k = keeper(desk, try legacy(["S": a]))
        desk.view(space: 0, on: "S")
        k.restoreAll()
        try expect(desk.picture(on: "S", space: 0) == a, "Space 1 not restored")
        desk.view(space: 2, on: "S")
        try expect(applyStill(k, desk, on: "S") != nil, "no still went up over B")
        desk.view(space: 1, on: "S")
        k.restoreAll()
        let back: WallpaperEntry = desk.picture(on: "S", space: 1)
        try expect(back == a, "Space 2's 3.0 still was put back to \(back.url.lastPathComponent), not A")
        // No original known for its display (3.0 forgot it): the still stays, and the restore says it failed.
        let lost = FakeDesktop()
        lost.attach("S", showing: a)
        let kept: URL = try legacyStill(lost, on: "S", space: 0, millis: 1_700_000_000_002)
        let k2 = keeper(lost, try legacy([:]))
        let out: RestoreOutcome = k2.restoreAll()
        try expect(out.failed == ["S"] && out.keepsRecovery && lost.exists(kept), "a still with no known original: \(out)")
    }

    // F2 (finding 2). A stills folder that can't be read isn't empty: adoption waits, is retried before anything is
    // deleted, and uninstall keeps recovery while it waits.
    // (Rebuilt: the keeper never lists or deletes; its adoption record, `predatesStillRecords`, is gone.)
    check("wallpaperFailedFolderReadIsNotEmpty") {
        let desk = FakeDesktop()
        desk.attach("S", spaces: 2, showing: a)
        let hidden: URL = try legacyStill(desk, on: "S", space: 1, millis: 1_700_000_000_000)
        desk.view(space: 0, on: "S")
        desk.listFails = true
        let k = keeper(desk, try legacy(["S": a]))
        applyStill(k, desk, on: "S")
        desk.listFails = false
        applyStill(k, desk, on: "S")
        try expect(desk.exists(hidden), "Space 2's 3.0 still was deleted after the folder failed to read once")
        // A restore while the folder still can't be read: Space 2's still stays and goes back to A on its visit.
        desk.listFails = true
        k.restoreAll()
        try expect(desk.exists(hidden), "a restore with the stills folder unread deleted Space 2's 3.0 still")
        desk.view(space: 1, on: "S")
        k.reconcile(matching: false)
        try expect(desk.picture(on: "S", space: 1) == a, "Space 2's 3.0 still didn't go back to A")
        // (Fix round, review-r2-r2 finding 3: the unread-folder uninstall assertion, back in the new model.)
        // Uninstall while the Stills folder can't be read: the folder stays, and the restore data with it, so a
        // reinstall still puts A back under Space 2's 3.0 still.
        try unreadFolderKeepsRestoreData()
    }
    func unreadFolderKeepsRestoreData() throws {
        let fm: FileManager = .default
        let root: URL = wallpaperScratch("unread")
        defer { try? fm.removeItem(at: root) }
        let folder: URL = root.appendingPathComponent("Stills", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let hidden: URL = folder.appendingPathComponent("still-S-1700000000000.png")
        try wallpaperTouch(hidden)
        let settings: Data = try JSONEncoder().encode(try legacy(["S": a]))
        let data: RestoreData = RestoreData.resolve(settings: settings, sharksOwn: nil, sharksCopy: nil, stillsFolder: folder)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        let kept: RestoreData.Kept = data.keepOnUninstall(stillsFolder: folder, sharksStills: root.appendingPathComponent("Sharks"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try expect(kept.folder, "uninstall would delete a Stills folder it couldn't read")
        let left: Data? = kept.keepsSettings ? settings : nil   // the settings are gone unless uninstall kept them
        let again: RestoreData = RestoreData.resolve(settings: left, sharksOwn: nil, sharksCopy: nil, stillsFolder: folder)
        let under: WallpaperEntry? = again.memory.under(WallpaperKeeper.stillEntry(hidden), on: "S", stillsFolder: folder)
        try expect(under == a, "after uninstall with the Stills folder unread, a reinstall can't put A back: \(kept)")
    }

    // F3 (finding 3). Under an ASCII Sharks still, Sharks' own original comes back, not an Animals original from
    // another Space; and its copied memory stays while a Sharks still is unresolved.
    let sharksStills = URL(fileURLWithPath: "/tmp/ascii-animals-check/Sharks/Stills", isDirectory: true)
    // (Rebuilt: no direct `restoreTarget`; the controls on uninstall's keep-or-discard decision go, since uninstall
    // keeps the Stills folder whenever it holds a file.)
    check("wallpaperSharksUpgraderKeepsSharksOriginal") {
        let copy = ForeignStills(folder: sharksStills, memory: try legacy(["S": a]))
        let sharksStill: URL = sharksStills.appendingPathComponent("still-S-1690000000000.png")
        let desk = FakeDesktop()
        desk.attach("S", spaces: 2, showing: b)   // B: the person's own on Space 1
        desk.write(sharksStill)
        desk.view(space: 1, on: "S")
        try desk.set(WallpaperKeeper.stillEntry(sharksStill), on: "S")   // Sharks, force-quit, left it on Space 2
        let k = WallpaperKeeper(memory: WallpaperMemory(), stillsFolder: stills, foreign: copy, desktop: desk)
        desk.view(space: 0, on: "S")
        applyStill(k, desk, on: "S")   // Animals covers B on Space 1
        desk.view(space: 1, on: "S")
        try expect(applyStill(k, desk, on: "S") != nil, "no still over the Sharks still")
        k.restoreAll()
        let back: WallpaperEntry = desk.picture(on: "S", space: 1)
        try expect(back == a, "Space 2 got \(back.url.lastPathComponent) instead of Sharks' original A")

        // A Sharks still on a Space not in view, no Animals memory: it stays, and goes back to A on its visit.
        let desk2 = FakeDesktop()
        desk2.attach("S", spaces: 2, showing: b)
        desk2.write(sharksStill)
        desk2.view(space: 1, on: "S")
        try desk2.set(WallpaperKeeper.stillEntry(sharksStill), on: "S")
        desk2.view(space: 0, on: "S")
        let k2 = WallpaperKeeper(memory: WallpaperMemory(), stillsFolder: stills, foreign: copy, desktop: desk2)
        let out: RestoreOutcome = k2.restoreAll()
        try expect(out.restored.isEmpty && out.failed.isEmpty && desk2.picture(on: "S", space: 0) == b, "the person's B was touched: \(out)")
        try expect(desk2.exists(sharksStill), "the Sharks still was deleted")
        let k3 = WallpaperKeeper(memory: k2.memory, stillsFolder: stills, foreign: copy, desktop: desk2)   // next launch
        desk2.view(space: 1, on: "S")
        k3.reconcile(matching: false)
        try expect(desk2.picture(on: "S", space: 1) == a, "the hidden Sharks still didn't go back to Sharks' A")
        // (Fix round, review-r2-r2 finding 3: the sole-copy retention assertion, back in the new model.)
        // Uninstall with a Sharks still on a Space not in view, no stills of ours and only the hand-over's copy of
        // Sharks' memory: the copy stays with the Stills folder, and a reinstall puts A back on the visit.
        try soleSharksCopyKept(try JSONEncoder().encode(copy.memory))
    }
    func soleSharksCopyKept(_ copy: Data) throws {
        let fm: FileManager = .default
        let root: URL = wallpaperScratch("sole-copy")
        defer { try? fm.removeItem(at: root) }
        let ours: URL = root.appendingPathComponent("Animals/Stills", isDirectory: true)
        let theirs: URL = root.appendingPathComponent("Sharks/Stills", isDirectory: true)
        try fm.createDirectory(at: ours, withIntermediateDirectories: true)
        try fm.createDirectory(at: theirs, withIntermediateDirectories: true)
        let still: URL = theirs.appendingPathComponent("still-S-1690000000000.png")
        try wallpaperTouch(still)
        let data: RestoreData = RestoreData.resolve(settings: nil, sharksOwn: nil, sharksCopy: copy, stillsFolder: ours)
        let kept: RestoreData.Kept = data.keepOnUninstall(stillsFolder: ours, sharksStills: theirs)
        try expect(kept.folder, "uninstall would discard the only copy of Sharks' original: \(kept)")
        let desk = FakeDesktop()
        desk.attach("S", spaces: 2, showing: b)
        desk.view(space: 1, on: "S")
        try desk.set(WallpaperKeeper.stillEntry(still), on: "S")
        let again: RestoreData = RestoreData.resolve(settings: nil, sharksOwn: nil, sharksCopy: kept.keepsSettings ? copy : nil,
                                                     stillsFolder: ours)   // the reinstall: the settings are gone
        let k = WallpaperKeeper(memory: again.memory, stillsFolder: ours,
                                foreign: ForeignStills(folder: theirs, memory: again.sharks ?? WallpaperMemory()), desktop: desk)
        k.reconcile(matching: false)   // the visit
        let back: WallpaperEntry = desk.picture(on: "S", space: 1)
        try expect(back == a, "after uninstall and a reinstall, the hidden Sharks still went to \(back.url.lastPathComponent), not A")
        // Control: no Sharks still left and no stills of ours: nothing to keep, the folder goes.
        try fm.removeItem(at: still)
        let empty: URL = root.appendingPathComponent("Empty/Stills", isDirectory: true)
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        try expect(!data.keepOnUninstall(stillsFolder: empty, sharksStills: theirs).folder, "kept an empty Stills folder with no Sharks still left")
    }

    // F4 (finding 5). A set that throws is read back before anything is deleted.
    // (Rebuilt: no per-still records to keep; the control no longer expects the unselected file deleted.)
    check("wallpaperSetThatThrowsIsReadBack") {
        // It threw after selecting the still: the still is up, so its file stays, and the picture comes back.
        let desk = FakeDesktop()
        desk.attach("S", showing: a)
        desk.setThrowsAfter = ["S"]
        let k = keeper(desk)
        try expect(k.mayApply(on: "S"), "not applied")
        let still: URL = k.newStill(for: "S")
        desk.write(still)
        k.commit(still, on: "S")
        let shown: WallpaperEntry = desk.picture(on: "S", space: 0)
        try expect(WallpaperMemory.same(shown.url, still), "control: the fake shows the still")
        try expect(desk.exists(still), "the still a throwing set selected was deleted")
        desk.setThrowsAfter = []
        k.restoreAll()
        try expect(desk.picture(on: "S", space: 0) == a, "not restored after a set that threw")
        // It threw and the result can't be read: the file stays, and the picture comes back once readable.
        let desk2 = FakeDesktop()
        desk2.attach("S", showing: a)
        desk2.setThrowsAfter = ["S"]
        desk2.onSet = { desk2.unreadable.insert($0) }
        let k2 = keeper(desk2)
        _ = k2.mayApply(on: "S")
        let still2: URL = k2.newStill(for: "S")
        desk2.write(still2)
        k2.commit(still2, on: "S")
        try expect(desk2.exists(still2), "a still whose set threw and can't be read back was dropped")
        desk2.onSet = nil
        desk2.setThrowsAfter = []
        desk2.unreadable = []
        k2.restoreAll()
        try expect(desk2.picture(on: "S", space: 0) == a, "not restored after a set that threw and couldn't be read back")
        // Control: it threw before selecting anything: not up, the person's picture untouched.
        let desk3 = FakeDesktop()
        desk3.attach("S", showing: a)
        desk3.setFails = ["S"]
        let k3 = keeper(desk3)
        _ = k3.mayApply(on: "S")
        let still3: URL = k3.newStill(for: "S")
        desk3.write(still3)
        try expect(!k3.commit(still3, on: "S") && desk3.picture(on: "S", space: 0) == a, "a still that was never selected counted as up")
    }

    // F5 (finding 6). Once uninstall begins, no still goes up and nothing reconciles.
    check("wallpaperNothingChangesOnceUninstallBegins") {
        let desk = FakeDesktop()
        desk.attach("S", showing: a)
        desk.attach("T", showing: b)
        let k = keeper(desk)
        applyStill(k, desk, on: "S")
        _ = k.mayApply(on: "T")
        let rendering: URL = k.newStill(for: "T")   // still rendering when uninstall starts
        desk.write(rendering)
        k.beginUninstall()
        let out: RestoreOutcome = k.restoreAll()
        try expect(out.restored == ["S"], "uninstall's restore: \(out)")
        let late: URL? = applyStill(k, desk, on: "S")
        try expect(late == nil && desk.picture(on: "S", space: 0) == a, "a look change during uninstall put a still up")
        let committed: Bool = k.commit(rendering, on: "T")
        try expect(!committed && desk.picture(on: "T", space: 0) == b, "a still rendered before uninstall went up after it")
        try expect(k.reconcile(matching: false) == nil, "a reconcile ran during uninstall")
    }

    // "Show on all Spaces" is unproven: a still's file stays after a replacement or a restore, even a clean one.
    // (Rebuilt: a clean restore no longer deletes the files.)
    check("wallpaperReplacedStillFileKept") {
        let desk = FakeDesktop()
        desk.attach("S", showing: a)
        let k = keeper(desk)
        guard let first = applyStill(k, desk, on: "S") else { throw CheckFailure(detail: "no still went up") }
        guard let second = applyStill(k, desk, on: "S") else { throw CheckFailure(detail: "no second still") }
        try expect(desk.exists(first), "the replaced still's file was deleted; another Space may show it")
        desk.attach("T", showing: b)
        guard let third = applyStill(k, desk, on: "T") else { throw CheckFailure(detail: "no still on T") }
        desk.setFails = ["T"]
        let partial: RestoreOutcome = k.restoreAll()
        try expect(partial.restored == ["S"] && desk.exists(second) && desk.exists(third), "a file went before everything was back: \(partial)")
        desk.setFails = []
        let clean: RestoreOutcome = k.restoreAll()
        try expect(clean.restored == ["T"] && !clean.keepsRecovery, "not all back: \(clean)")
        let left: [URL] = try desk.stillFiles(in: stills)
        try expect(left.count == 3, "a clean restore left \(left.count) of the 3 stills")
    }

    // MARK: rebuild on the root fix (briefs/r2.md "Rebuild on the root fix", go 2026-11-27)

    /// A refresh as the app runs it: plan, render (here: write), put up. Returns the file written, if any.
    func refresh(_ k: WallpaperKeeper, _ desk: FakeDesktop, on display: String) -> URL? {
        guard k.mayApply(on: display) else { return nil }
        let url: URL = k.newStill(for: display)
        desk.write(url)
        k.commit(url, on: display)
        return url
    }
    func gone(_ desk: FakeDesktop, _ written: [URL]) -> [String] {
        written.filter { !desk.exists($0) }.map { $0.lastPathComponent }
    }

    // R1. No file is deleted by a refresh, a restore, a failed read or uninstall.
    func noFileIsDeleted() throws {
        let desk = FakeDesktop()
        desk.attach("S", spaces: 2, showing: a)
        let k = keeper(desk)
        var written: [URL] = []
        for _ in 0..<3 { if let u = refresh(k, desk, on: "S") { written.append(u) } }
        try expect(gone(desk, written).isEmpty, "a refresh deleted \(gone(desk, written))")
        desk.setIgnored = ["S"]   // a set that says yes and changes nothing
        if let u = refresh(k, desk, on: "S") { written.append(u) }
        desk.setIgnored = []
        try expect(gone(desk, written).isEmpty, "a refresh whose set didn't take deleted \(gone(desk, written))")
        k.restoreAll()   // quit
        try expect(gone(desk, written).isEmpty, "a restore deleted \(gone(desk, written))")
        if let u = refresh(k, desk, on: "S") { written.append(u) }
        desk.unreadable = ["S"]
        _ = refresh(k, desk, on: "S")
        k.restoreAll()
        desk.unreadable = []
        desk.listFails = true
        if let u = refresh(k, desk, on: "S") { written.append(u) }
        desk.listFails = false
        try expect(gone(desk, written).isEmpty, "a failed read deleted \(gone(desk, written))")
        k.beginUninstall()
        k.restoreAll()
        try expect(gone(desk, written).isEmpty, "uninstall deleted \(gone(desk, written))")
        try expect(desk.picture(on: "S", space: 0) == a, "uninstall didn't put A back on the Space in view")
    }
    check("wallpaperNoFileIsDeleted", noFileIsDeleted)

    // R2. The folder holds at most two files per display per covered wallpaper after 100 refreshes.
    func atMostTwoFilesPerCoveredWallpaper() throws {
        let desk = FakeDesktop()
        desk.attach("S", spaces: 2, showing: a)
        desk.view(space: 1, on: "S")
        try desk.set(b, on: "S")   // S covers A on Space 1 and B on Space 2
        desk.attach("T", showing: b)   // T covers B
        let k = keeper(desk)
        for i in 0..<100 {
            desk.view(space: i % 2, on: "S")
            _ = refresh(k, desk, on: "S")
            _ = refresh(k, desk, on: "T")
        }
        let files: [URL] = try desk.stillFiles(in: stills)
        try expect(files.count <= 6, "100 refreshes left \(files.count) files for 3 covered wallpapers")
        try expect(isStill(desk.picture(on: "S", space: 0)) && isStill(desk.picture(on: "S", space: 1))
                   && isStill(desk.picture(on: "T", space: 0)), "a Space didn't get the habitat")
    }
    check("wallpaperAtMostTwoFilesPerCoveredWallpaper", atMostTwoFilesPerCoveredWallpaper)

    // R3. A hidden Space's still restores to its own covered wallpaper on visit.
    func hiddenSpaceRestoresOnVisit() throws {
        let c = WallpaperEntry(url: URL(fileURLWithPath: "/Users/me/Pictures/C.png"), scaling: 1, allowClipping: false, fillColor: nil)
        // The same still on two Spaces (a still on show elsewhere, or "Show on all Spaces"), both over A.
        let desk = FakeDesktop()
        desk.attach("S", spaces: 2, showing: a)
        let k = keeper(desk)
        guard let x = refresh(k, desk, on: "S") else { throw CheckFailure(detail: "no still went up") }
        desk.view(space: 1, on: "S")
        try desk.set(WallpaperKeeper.stillEntry(x), on: "S")
        desk.view(space: 0, on: "S")
        k.restoreAll()   // matching off on Space 1
        try desk.set(c, on: "S")   // the person picks C there
        _ = refresh(k, desk, on: "S")   // matching on again
        k.restoreAll()   // and off
        try expect(desk.picture(on: "S", space: 0) == c, "Space 1 didn't get C back")
        desk.view(space: 1, on: "S")
        k.reconcile(matching: false)   // a visit
        let back: WallpaperEntry = desk.picture(on: "S", space: 1)
        try expect(back == a, "Space 2 got \(back.url.lastPathComponent) on its visit, not its own A")
        // Two Spaces with different pictures each get the habitat, then their own picture back on a visit.
        let desk2 = FakeDesktop()
        desk2.attach("S", spaces: 2, showing: a)
        desk2.view(space: 1, on: "S")
        try desk2.set(b, on: "S")
        let k2 = keeper(desk2)
        desk2.view(space: 0, on: "S")
        _ = refresh(k2, desk2, on: "S")
        desk2.view(space: 1, on: "S")
        _ = refresh(k2, desk2, on: "S")   // a look change on Space 2
        try expect(isStill(desk2.picture(on: "S", space: 1)), "Space 2's own B got no still")
        desk2.view(space: 0, on: "S")
        _ = refresh(k2, desk2, on: "S")
        k2.restoreAll()   // quit on Space 1
        let k3 = keeper(desk2, k2.memory)   // the next launch, matching off
        desk2.view(space: 1, on: "S")
        k3.reconcile(matching: false)
        try expect(desk2.picture(on: "S", space: 0) == a && desk2.picture(on: "S", space: 1) == b,
                   "after a visit: \(desk2.picture(on: "S", space: 0).url.lastPathComponent), \(desk2.picture(on: "S", space: 1).url.lastPathComponent)")
    }
    check("wallpaperHiddenSpaceRestoresOnVisit", hiddenSpaceRestoresOnVisit)

    // R4. A failed read changes nothing: no set, no restore, no forgetting, no file gone; tried again at the next event.
    func failedReadChangesNothing() throws {
        let desk = FakeDesktop()
        desk.attach("S", showing: a)
        let k = keeper(desk)
        guard let first = refresh(k, desk, on: "S") else { throw CheckFailure(detail: "no still went up") }
        let before: WallpaperMemory = k.memory
        desk.unreadable = ["S"]
        try expect(!k.mayApply(on: "S"), "a still was planned over a picture that couldn't be read")
        let out: RestoreOutcome = k.restoreAll()
        desk.unreadable = []
        try expect(out.restored.isEmpty && WallpaperMemory.same(desk.picture(on: "S", space: 0).url, first),
                   "something was set while the picture couldn't be read: \(out)")
        try expect(k.memory == before, "the memory changed on a failed read")
        // The stills folder can't be listed: the still being put up is not lost.
        desk.listFails = true
        let second: URL? = refresh(k, desk, on: "S")
        desk.listFails = false
        try expect(second.map { desk.exists($0) } ?? true, "a still was deleted when the folder couldn't be listed")
        // The read-back fails after a set: the still stays.
        desk.onSet = { desk.unreadable.insert($0) }
        let third: URL? = refresh(k, desk, on: "S")
        desk.onSet = nil
        desk.unreadable = []
        try expect(third.map { desk.exists($0) } ?? true, "a still was deleted when its set couldn't be read back")
        let again: RestoreOutcome = k.restoreAll()   // the next event
        try expect(again.restored == ["S"] && desk.picture(on: "S", space: 0) == a, "not put back once readable: \(again)")
    }
    check("wallpaperFailedReadChangesNothing", failedReadChangesNothing)

    // R5. Upgrades from 3.0 and ASCII Sharks restore their originals; their stills stay on disk.
    func upgradesRestoreTheirOriginals() throws {
        let desk = FakeDesktop()
        desk.attach("S", spaces: 3, showing: a)
        let old0: URL = try legacyStill(desk, on: "S", space: 0, millis: 1_700_000_000_000)
        let old1: URL = try legacyStill(desk, on: "S", space: 1, millis: 1_700_000_000_001)
        desk.view(space: 2, on: "S")
        try desk.set(b, on: "S")   // the person's own B on Space 3
        let k = keeper(desk, try legacy(["S": a]))   // launch, matching on
        _ = refresh(k, desk, on: "S")
        desk.view(space: 0, on: "S")
        _ = refresh(k, desk, on: "S")   // a look change over a 3.0 still
        k.restoreAll()   // matching off
        for space in [1, 2] {
            desk.view(space: space, on: "S")
            k.reconcile(matching: false)
        }
        let shown: [String] = (0..<3).map { desk.picture(on: "S", space: $0).url.lastPathComponent }
        try expect(shown == ["A.heic", "A.heic", "B.jpg"], "after the upgrade, the Spaces show \(shown)")
        try expect(desk.exists(old0) && desk.exists(old1), "a 3.0 still was deleted")
        // ASCII Sharks: its still on Space 2 goes back to what Sharks saved; the person's own B on Space 1 stays theirs.
        let sharksStill: URL = sharksStills.appendingPathComponent("still-S-1690000000000.png")
        let desk2 = FakeDesktop()
        desk2.attach("S", spaces: 2, showing: b)
        desk2.write(sharksStill)
        desk2.view(space: 1, on: "S")
        try desk2.set(WallpaperKeeper.stillEntry(sharksStill), on: "S")
        let sharks = ForeignStills(folder: sharksStills, memory: try legacy(["S": a]))
        let k2 = WallpaperKeeper(memory: WallpaperMemory(), stillsFolder: stills, foreign: sharks, desktop: desk2)
        desk2.view(space: 0, on: "S")
        _ = refresh(k2, desk2, on: "S")
        desk2.view(space: 1, on: "S")
        _ = refresh(k2, desk2, on: "S")
        k2.restoreAll()   // quit on Space 2
        let k3 = WallpaperKeeper(memory: k2.memory, stillsFolder: stills, foreign: sharks, desktop: desk2)
        desk2.view(space: 0, on: "S")
        k3.reconcile(matching: false)   // the next launch, matching off
        let both: [String] = (0..<2).map { desk2.picture(on: "S", space: $0).url.lastPathComponent }
        try expect(both == ["B.jpg", "A.heic"], "after the Sharks upgrade, the Spaces show \(both)")
        try expect(desk2.exists(sharksStill), "the Sharks still was deleted")
    }
    check("wallpaperUpgradesRestoreTheirOriginals", upgradesRestoreTheirOriginals)

    // MARK: fix round (review-r2-r2 @ 08884b3)

    // FR1 (findings 1, 3). Restore data stays with the stills it describes: uninstall with a hidden Space on our still
    // and one on a Sharks still known only from the hand-over's copy, the restore in view failing; reinstall and visit:
    // each Space gets its own wallpaper back.
    func reinstallRestoresKeptStills() throws {
        let fm: FileManager = .default
        let c = WallpaperEntry(url: URL(fileURLWithPath: "/Users/me/Pictures/C.png"), scaling: 1, allowClipping: false, fillColor: nil)
        let root: URL = wallpaperScratch("reinstall")
        defer { try? fm.removeItem(at: root) }
        let ours: URL = root.appendingPathComponent("Animals/Stills", isDirectory: true)
        let theirs: URL = root.appendingPathComponent("Sharks/Stills", isDirectory: true)
        try fm.createDirectory(at: ours, withIntermediateDirectories: true)
        try fm.createDirectory(at: theirs, withIntermediateDirectories: true)
        let sharksStill: URL = theirs.appendingPathComponent("still-S-1690000000000.png")
        try wallpaperTouch(sharksStill)
        let copy: Data = try JSONEncoder().encode(try legacy(["S": c]))   // the hand-over's copy: Sharks saved C
        let desk = FakeDesktop()
        desk.attach("S", spaces: 3, showing: a)
        desk.view(space: 1, on: "S")
        try desk.set(b, on: "S")
        desk.view(space: 2, on: "S")
        try desk.set(WallpaperKeeper.stillEntry(sharksStill), on: "S")
        func launch(settings: Data?, sharksCopy: Data?) -> WallpaperKeeper {
            let data: RestoreData = RestoreData.resolve(settings: settings, sharksOwn: nil, sharksCopy: sharksCopy, stillsFolder: ours)
            return WallpaperKeeper(memory: data.memory, stillsFolder: ours,
                                   foreign: ForeignStills(folder: theirs, memory: data.sharks ?? WallpaperMemory()), desktop: desk)
        }
        let k: WallpaperKeeper = launch(settings: nil, sharksCopy: copy)   // matching on
        for space in [0, 1] {
            desk.view(space: space, on: "S")
            guard let url = applyStill(k, desk, on: "S") else { throw CheckFailure(detail: "no still on Space \(space + 1)") }
            try wallpaperTouch(url)
        }
        // Uninstall on Space 1, its restore failing.
        desk.view(space: 0, on: "S")
        desk.setFails = ["S"]
        k.beginUninstall()
        let out: RestoreOutcome = k.restoreAll()
        try expect(out.failed == ["S"], "control: the restore in view failed: \(out)")
        let settings: Data = try JSONEncoder().encode(k.memory)
        let data: RestoreData = RestoreData.resolve(settings: settings, sharksOwn: nil, sharksCopy: copy, stillsFolder: ours)
        let kept: RestoreData.Kept = data.keepOnUninstall(stillsFolder: ours, sharksStills: theirs)
        try expect(kept.folder, "uninstall didn't keep the Stills folder: \(kept)")
        // The reinstall, matching off: the settings are gone unless uninstall had to keep them.
        desk.setFails = []
        let k2: WallpaperKeeper = launch(settings: kept.keepsSettings ? settings : nil, sharksCopy: kept.keepsSettings ? copy : nil)
        var back: [String] = []
        for space in [0, 1, 2] {
            desk.view(space: space, on: "S")
            k2.reconcile(matching: false)
            back.append(desk.picture(on: "S", space: space).url.lastPathComponent)
        }
        try expect(back == ["A.heic", "B.jpg", "C.png"], "after uninstall and a reinstall, the visits show \(back)")
    }
    check("wallpaperReinstallRestoresKeptStills", reinstallRestoresKeptStills)

    // FR2 (finding 2). Accepting the offer to trash ASCII Sharks never removes a Sharks still a Space may show: its
    // uninstaller deletes its whole support folder (here a fake, on a scratch folder), the still is back at its old
    // path, and the visit restores Sharks' saved original.
    func sharksRemovalKeepsItsStills() throws {
        let fm: FileManager = .default
        let root: URL = wallpaperScratch("handover")
        defer { try? fm.removeItem(at: root) }
        let support: URL = root.appendingPathComponent("ASCII Sharks", isDirectory: true)
        let theirs: URL = support.appendingPathComponent("Stills", isDirectory: true)
        let ours: URL = root.appendingPathComponent("ASCII Animals/Stills", isDirectory: true)
        try fm.createDirectory(at: theirs, withIntermediateDirectories: true)
        try fm.createDirectory(at: ours, withIntermediateDirectories: true)
        let inView: URL = theirs.appendingPathComponent("still-S-1690000000001.png")
        let hidden: URL = theirs.appendingPathComponent("still-S-1690000000000.png")
        let picture: Data = Data("the hidden Space's picture".utf8)
        try wallpaperTouch(inView)
        try picture.write(to: hidden)
        let desk = FakeDesktop()
        desk.attach("S", spaces: 2, showing: WallpaperKeeper.stillEntry(inView))
        desk.view(space: 1, on: "S")
        try desk.set(WallpaperKeeper.stillEntry(hidden), on: "S")
        desk.view(space: 0, on: "S")
        let sharksMemory: Data = try JSONEncoder().encode(try legacy(["S": a]))
        var copied: Data? = nil
        let aside: URL = ours.appendingPathComponent(".sharks-handover", isDirectory: true)
        let finished: Bool = SharksRemoval.run(sharksMemory: sharksMemory, sharksStills: theirs, aside: aside,
                                               keepCopy: { copied = $0 }) {
            // Sharks' own uninstaller: A back on the Space in view, then its whole support folder goes.
            try? desk.set(a, on: "S")
            try? fm.removeItem(at: support)
            return true
        }
        try expect(finished && desk.picture(on: "S", space: 0) == a, "control: the fake uninstaller ran")
        try expect(fm.fileExists(atPath: hidden.path), "the Sharks still a hidden Space shows is gone with Sharks' folder")
        try expect((try? Data(contentsOf: hidden)) == picture, "the Sharks still came back changed")
        try expect(!fm.fileExists(atPath: aside.path), "the copy set aside was left behind")
        guard let copied else { throw CheckFailure(detail: "Sharks' memory wasn't copied") }
        let data: RestoreData = RestoreData.resolve(settings: nil, sharksOwn: nil, sharksCopy: copied, stillsFolder: ours)
        let k = WallpaperKeeper(memory: data.memory, stillsFolder: ours,
                                foreign: ForeignStills(folder: theirs, memory: data.sharks ?? WallpaperMemory()), desktop: desk)
        desk.view(space: 1, on: "S")
        k.reconcile(matching: false)   // the visit, matching off
        let back: WallpaperEntry = desk.picture(on: "S", space: 1)
        try expect(back == a, "the hidden Sharks still went to \(back.url.lastPathComponent), not Sharks' A")
    }
    check("wallpaperSharksRemovalKeepsItsStills", sharksRemovalKeepsItsStills)
}

/// A fresh scratch folder for checks that need real files: under the temporary directory, never the person's folders.
func wallpaperScratch(_ name: String) -> URL {
    let url: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ascii-animals-check-\(getpid())", isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A real file where a still is.
func wallpaperTouch(_ url: URL) throws { try Data("still".utf8).write(to: url) }
