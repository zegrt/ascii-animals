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
        .executableTarget(name: "OceanChecks", dependencies: ["OceanKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        // Tooling: stills and the app icon.
        .executableTarget(name: "OceanTool", dependencies: ["OceanKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
