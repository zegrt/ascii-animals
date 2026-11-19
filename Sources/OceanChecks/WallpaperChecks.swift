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
    check("wallpaperMemoryRoundTrips") {
        var m = WallpaperMemory()
        _ = m.decide(screen: "S", current: a, stillsFolder: stills)
        _ = m.decide(screen: "T", current: b, stillsFolder: stills)
        let back = try JSONDecoder().decode(WallpaperMemory.self, from: JSONEncoder().encode(m))
        try expect(back == m, "round trip changed memory")
    }
}
