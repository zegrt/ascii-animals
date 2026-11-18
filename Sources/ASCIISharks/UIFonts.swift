import AppKit
import CoreText
import SwiftUI

/// Geist Mono for the UI surfaces (the welcome, About), at any weight of the
/// variable font. It's read from the app bundle's Resources/GeistMono.ttf, or
/// from the source checkout in development builds; failing both, SF Mono.
enum UIFonts {
    private static let base: CGFont? = {
        var candidates: [URL] = []
        if let u = Bundle.main.url(forResource: "GeistMono", withExtension: "ttf") { candidates.append(u) }
        // Development builds (and the --snapshot-* flags) run from .build-*, next to the source.
        candidates.append(sourceRoot.appendingPathComponent("Resources/GeistMono.ttf"))
        for url in candidates {
            if let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider) { return font }
        }
        return nil
    }()

    /// The repository root, as seen at compile time.
    static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static var hasGeist: Bool { base != nil }

    /// `weight` on the font's own 100–900 axis (400 regular, 500 medium, 600 semibold).
    static func mono(_ size: CGFloat, weight: CGFloat = 400) -> NSFont {
        if let cg = base {
            let wght = 0x7767_6874
            let desc = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: [wght: weight]] as CFDictionary)
            return CTFontCreateWithGraphicsFont(cg, size, nil, desc) as NSFont
        }
        let w: NSFont.Weight = weight >= 650 ? .bold : weight >= 550 ? .semibold : weight >= 450 ? .medium : weight <= 300 ? .light : .regular
        return .monospacedSystemFont(ofSize: size, weight: w)
    }

    static func swiftUI(_ size: CGFloat, weight: CGFloat = 400) -> Font { Font(mono(size, weight: weight) as CTFont) }

    /// The app icon: the bundle's, or the README's copy in development builds.
    static var appIcon: NSImage {
        if Bundle.main.bundleURL.pathExtension == "app" { return NSApp.applicationIconImage }
        return NSImage(contentsOf: sourceRoot.appendingPathComponent("docs/media/icon.png")) ?? NSApp.applicationIconImage
    }
}
