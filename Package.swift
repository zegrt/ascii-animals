// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AsciiAnimals",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure domain + Metal rendering. No AppKit.
        .target(name: "OceanKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        // The wallpaper app (AppKit host).
        .executableTarget(name: "ASCIIAnimals", dependencies: ["OceanKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        // Checks: `swift run -c release OceanChecks` exits non-zero on failure.
        // Fixtures: replays recorded from the Meadow sketch (Sources/OceanChecks/Fixtures/README.md).
        .executableTarget(name: "OceanChecks", dependencies: ["OceanKit"], resources: [.copy("Fixtures")],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        // Tooling: stills and the app icon.
        .executableTarget(name: "OceanTool", dependencies: ["OceanKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
