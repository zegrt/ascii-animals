import Foundation
import OceanKit

func wallpaperChecks() {
    let stills = URL(fileURLWithPath: "/tmp/ascii-animals-check/Stills", isDirectory: true)
    let ours = stills.appendingPathComponent("still-A-1.png")
    let a = WallpaperEntry(url: URL(fileURLWithPath: "/System/Library/Desktop Pictures/A.heic"), scaling: 3, allowClipping: true, fillColor: [0, 0, 0, 1])
    let b = WallpaperEntry(url: URL(fileURLWithPath: "/Users/me/Pictures/B.jpg"), scaling: nil, allowClipping: nil, fillColor: nil)

    check("wallpaperMemoryIgnoresOwnStills") {
        var m = WallpaperMemory()
        try expect(m.decide(screen: "S", current: WallpaperEntry(url: ours), stillsFolder: stills) == .apply, "ours not applied")
        try expect(m.original(for: "S") == nil, "recorded our own still as original")
    }
    check("wallpaperSymlinkedStillIsOurs") {
        // /tmp is a symlink to /private/tmp on macOS.
        var m = WallpaperMemory()
        let viaPrivate = URL(fileURLWithPath: "/private/tmp/ascii-animals-check/Stills/still-A-2.png")
        _ = m.decide(screen: "S", current: WallpaperEntry(url: viaPrivate), stillsFolder: stills)
        try expect(m.original(for: "S") == nil, "symlinked still recorded as original")
    }
    check("wallpaperMemoryKeepsFirstOriginal") {
        var m = WallpaperMemory()
        try expect(m.decide(screen: "S", current: a, stillsFolder: stills) == .apply, "first not applied")
        try expect(m.decide(screen: "S", current: b, stillsFolder: stills) == .leaveAlone, "unknown wallpaper touched")
        try expect(m.original(for: "S") == a, "original replaced")
    }
    check("wallpaperSameOriginalApplies") {
        var m = WallpaperMemory()
        _ = m.decide(screen: "S", current: a, stillsFolder: stills)
        try expect(m.decide(screen: "S", current: a, stillsFolder: stills) == .apply, "same original refused")
    }
    check("wallpaperRestoreOnlyWhereOurs") {
        var m = WallpaperMemory()
        _ = m.decide(screen: "S", current: a, stillsFolder: stills)
        try expect(m.restoreTarget(screen: "S", current: WallpaperEntry(url: ours), stillsFolder: stills) == a, "no restore over our still")
        try expect(m.restoreTarget(screen: "S", current: b, stillsFolder: stills) == nil, "restored over a foreign wallpaper")
    }
    check("wallpaperRestoreForgets") {
        var m = WallpaperMemory()
        _ = m.decide(screen: "S", current: a, stillsFolder: stills)
        m.forget(screen: "S")
        try expect(m.decide(screen: "S", current: b, stillsFolder: stills) == .apply, "new wallpaper refused after restore")
        try expect(m.original(for: "S") == b, "new original not recorded")
    }
    // ASCII Sharks, force-quit, can leave its still up; it's never the user's own wallpaper.
    let sharksStills = URL(fileURLWithPath: "/tmp/ascii-animals-check/Sharks/Stills", isDirectory: true)
    let sharksStill = WallpaperEntry(url: sharksStills.appendingPathComponent("still-S-9.png"))
    check("wallpaperSharksStillIsNotTheUsers") {
        var m = WallpaperMemory()
        let none = ForeignStills(folder: sharksStills)
        try expect(m.decide(screen: "S", current: sharksStill, stillsFolder: stills, foreign: none) == .apply, "Sharks' still not replaced")
        try expect(m.original(for: "S") == nil, "Sharks' still recorded as the user's")
        // Without the foreign folder it would have been taken for the user's (the old behaviour).
        var old = WallpaperMemory()
        _ = old.decide(screen: "S", current: sharksStill, stillsFolder: stills)
        try expect(old.original(for: "S") == sharksStill, "control: plain decide records it")
    }
    check("wallpaperSharksMemoryAdopted") {
        // What Sharks remembered under its still becomes the original, and comes back on restore.
        var sharks = WallpaperMemory()
        _ = sharks.decide(screen: "S", current: a, stillsFolder: sharksStills)
        let foreign = ForeignStills(folder: sharksStills, memory: sharks)
        var m = WallpaperMemory()
        try expect(m.decide(screen: "S", current: sharksStill, stillsFolder: stills, foreign: foreign) == .apply, "not applied")
        try expect(m.original(for: "S") == a, "Sharks' original not adopted")
        try expect(m.restoreTarget(screen: "S", current: WallpaperEntry(url: ours), stillsFolder: stills, foreign: foreign) == a, "no restore")
        // Never over a wallpaper the user chose, and Sharks' memory doesn't override ours.
        var mine = WallpaperMemory()
        _ = mine.decide(screen: "S", current: b, stillsFolder: stills)
        _ = mine.decide(screen: "S", current: sharksStill, stillsFolder: stills, foreign: foreign)
        try expect(mine.original(for: "S") == b, "our own original replaced")
        var fresh = WallpaperMemory()
        try expect(fresh.decide(screen: "T", current: b, stillsFolder: stills, foreign: foreign) == .apply, "first wallpaper refused")
        try expect(fresh.original(for: "T") == b, "the user's wallpaper not recorded")
    }
    check("wallpaperRestoresOverSharksStill") {
        var sharks = WallpaperMemory()
        _ = sharks.decide(screen: "S", current: a, stillsFolder: sharksStills)
        let foreign = ForeignStills(folder: sharksStills, memory: sharks)
        let m = WallpaperMemory()
        try expect(m.restoreTarget(screen: "S", current: sharksStill, stillsFolder: stills, foreign: foreign) == a, "Sharks' still left up")
        try expect(m.restoreTarget(screen: "S", current: b, stillsFolder: stills, foreign: foreign) == nil, "restored over the user's wallpaper")
        try expect(m.restoreTarget(screen: "T", current: sharksStill, stillsFolder: stills, foreign: foreign) == nil, "invented an original")
    }
    check("wallpaperMemoryRoundTrips") {
        var m = WallpaperMemory()
        _ = m.decide(screen: "S", current: a, stillsFolder: stills)
        _ = m.decide(screen: "T", current: b, stillsFolder: stills)
        let back = try JSONDecoder().decode(WallpaperMemory.self, from: JSONEncoder().encode(m))
        try expect(back == m, "round trip changed memory")
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
    var removeFails = false

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
        if setIgnored.contains(display) { return }
        spaces[display]![s] = entry
    }
    func stillFiles() -> [URL] { files.sorted { $0.path < $1.path } }
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
    func applyStill(_ k: WallpaperKeeper, _ desk: FakeDesktop, on display: String, named name: String? = nil) -> URL? {
        guard k.mayApply(on: display) else { return nil }
        let url: URL = name.map { stills.appendingPathComponent($0) } ?? k.newStill(for: display)
        desk.write(url)
        return k.commit(url, on: display) ? url : nil
    }

    // 1. The original is recorded once and never overwritten by our own still: a second restore can't forget it.
    check("wallpaperOriginalSurvivesASecondRestore") {
        let desk = FakeDesktop()
        desk.attach("S", spaces: 2, showing: a)
        let k = keeper(desk)
        applyStill(k, desk, on: "S", named: "still-S-space1.png")
        desk.view(space: 1, on: "S")
        applyStill(k, desk, on: "S", named: "still-S-space2.png")
        k.restoreAll()   // quit, on Space 2
        try expect(desk.picture(on: "S", space: 1) == a, "Space 2 not restored")
        // Next launch, matching on, Space 1 in view: still showing our still from last time.
        desk.view(space: 0, on: "S")
        applyStill(k, desk, on: "S", named: "still-S-space1-again.png")
        let out: RestoreOutcome = k.restoreAll()   // quit again
        let back: WallpaperEntry = desk.picture(on: "S", space: 0)
        try expect(back == a, "Space 1 kept the habitat after the second restore: \(back.url.lastPathComponent); \(out)")
    }

    // 2. A still in use is never deleted: pruning skips stills another Space still shows.
    check("wallpaperStillInUseIsNotDeleted") {
        let desk = FakeDesktop()
        desk.attach("S", spaces: 5, showing: a)
        let k = keeper(desk)
        var put: [URL] = []
        for space in 0..<5 {
            desk.view(space: space, on: "S")
            if let url = applyStill(k, desk, on: "S", named: "still-S-\(space).png") { put.append(url) }
        }
        try expect(put.count == 5, "only \(put.count) of 5 stills went up")
        for space in 0..<5 {
            let shown: WallpaperEntry = desk.picture(on: "S", space: space)
            try expect(desk.exists(shown.url), "Space \(space + 1) shows \(shown.url.lastPathComponent), which was deleted")
        }
        // A failing remove never takes a still's record with it.
        desk.removeFails = true
        desk.view(space: 0, on: "S")
        applyStill(k, desk, on: "S", named: "still-S-0b.png")
        desk.removeFails = false
        let out: RestoreOutcome = k.restoreAll()
        try expect(out.restored == ["S"] && desk.picture(on: "S", space: 0) == a, "Space 1 not restored: \(out)")
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
        let note: String = out.uninstallNote(stillsFolder: stills) ?? ""
        try expect(note.contains("A.heic") && note.contains("Stills"), "uninstall doesn't say what it kept: \(note)")
        try expect(k2.memory.original(for: "S") == a, "the original was forgotten")

        // c. Everything verified: nothing kept, nothing said.
        let desk3 = FakeDesktop()
        desk3.attach("S", showing: a)
        let k3 = keeper(desk3)
        applyStill(k3, desk3, on: "S")
        let clean: RestoreOutcome = k3.restoreAll()
        try expect(clean.restored == ["S"] && !clean.keepsRecovery && clean.uninstallNote(stillsFolder: stills) == nil,
                   "a verified restore still keeps recovery material: \(clean)")
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

    // 5. Still filenames are unique (a1 finding 10, wallpaper part).
    check("wallpaperStillNamesAreUnique") {
        let desk = FakeDesktop()
        desk.attach("S", showing: a)
        let k = keeper(desk)
        var names: Set<String> = []
        for _ in 0..<500 { names.insert(k.newStill(for: "S").lastPathComponent) }
        try expect(names.count == 500, "500 stills got \(names.count) names")
        try expect(names.allSatisfy { $0.hasPrefix("still-S-") && $0.hasSuffix(".png") }, "a name lost the display or the type")
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
}
