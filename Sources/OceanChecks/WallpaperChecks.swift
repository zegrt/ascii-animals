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
