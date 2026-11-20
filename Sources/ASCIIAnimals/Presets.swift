import OceanKit

/// Ready-made shark, spider and butterfly line-ups, and the names people see for each species.
enum Presets {
    struct Preset {
        let title: String
        let sharks: [SharkKind]
    }

    static let all: [Preset] = [
        Preset(title: "Mixed", sharks: [.greathammer, .classic, .mako, .tiger]),
        Preset(title: "Four Classics", sharks: [.classic, .classic, .classic, .classic]),
        Preset(title: "Hammerheads", sharks: [.greathammer, .hammerhead, .hammerhead]),
        Preset(title: "Thresher and Nurses", sharks: [.thresher, .nurse, .nurse]),
        Preset(title: "All Eight", sharks: [.greathammer, .thresher, .tiger, .mako, .zebra, .classic, .nurse, .hammerhead]),
    ]

    /// The preset that matches this line-up exactly, if any.
    static func matching(_ sharks: [SharkKind]) -> Preset? { all.first { $0.sharks == sharks } }

    static func title(_ k: SharkKind) -> String {
        switch k {
        case .classic: return "Classic"
        case .hammerhead: return "Hammerhead"
        case .tiger: return "Tiger"
        case .zebra: return "Zebra"
        case .greathammer: return "Great Hammerhead"
        case .mako: return "Mako"
        case .thresher: return "Thresher"
        case .nurse: return "Nurse"
        }
    }

    /// Species in the order people expect to browse them: the familiar ones first.
    static let species: [SharkKind] = [.classic, .greathammer, .hammerhead, .tiger, .mako, .thresher, .zebra, .nurse]

    /// Relative length of the shark at `index` in a line-up (first is biggest), as the ocean draws it.
    static func relativeSize(at index: Int) -> Double { max(0.3, 1 - Double(index) * 0.1) }

    // MARK: Spiders

    struct SpiderPreset {
        let title: String
        let spiders: [SpiderKind]
    }

    /// The original's cast first (as many webs as there's room for, spiders on six of them), then six of one kind.
    static let spiderPresets: [SpiderPreset] = [
        SpiderPreset(title: "Classic Six", spiders: SpiderKind.defaultCast),
        SpiderPreset(title: "Garden Spiders", spiders: Array(repeating: .araneus, count: 6)),
        SpiderPreset(title: "Wasp Spiders", spiders: Array(repeating: .argiope, count: 6)),
        SpiderPreset(title: "Golden Orb Weavers", spiders: Array(repeating: .nephila, count: 6)),
    ]

    static func matching(_ spiders: [SpiderKind]) -> SpiderPreset? { spiderPresets.first { $0.spiders == spiders } }

    static func title(_ k: SpiderKind) -> String {
        switch k {
        case .araneus: return "Garden Spider"
        case .argiope: return "Wasp Spider"
        case .nephila: return "Golden Orb Weaver"
        }
    }

    /// "2 Garden Spiders, 2 Golden Orb Weavers, 2 Wasp Spiders": each kind once, in the order they first appear.
    static func summary(_ spiders: [SpiderKind], separator: String = ", ") -> String {
        var order: [SpiderKind] = []
        var counts: [SpiderKind: Int] = [:]
        for k in spiders {
            if counts[k] == nil { order.append(k) }
            counts[k, default: 0] += 1
        }
        return order.map { k in
            let n = counts[k] ?? 0
            return n == 1 ? "1 \(title(k))" : "\(n) \(title(k))s"
        }.joined(separator: separator)
    }

    // MARK: Butterflies

    /// The Meadow's line-ups live with the settings (`MeadowLineUp.all`), where the checks can see them.
    static var meadowPresets: [MeadowLineUp] { MeadowLineUp.all }

    static func title(_ k: ButterflyKind) -> String {
        switch k {
        case .monarch: return "Monarch"
        case .morpho: return "Blue Morpho"
        case .swallowtail: return "Swallowtail"
        case .white: return "Cabbage White"
        }
    }

    /// "Monarchs", "Blue Morphos": the switches' names.
    static func plural(_ k: ButterflyKind) -> String { title(k) + "s" }

    /// "2 Monarchs, 2 Blue Morphos, 2 Swallowtails, 1 Cabbage White": a laptop screen's share of each species on.
    static func summary(butterflies: [ButterflyKind], count: Int, separator: String = ", ") -> String {
        MeadowLineUp.shares(butterflies, count: count).map { share in
            share.count == 1 ? "1 \(title(share.kind))" : "\(share.count) \(plural(share.kind))"
        }.joined(separator: separator)
    }

    static func summary(_ lineUp: MeadowLineUp) -> String { summary(butterflies: lineUp.butterflies, count: lineUp.count) }

    static func meadowSummary(_ s: OceanKit.Settings) -> String { summary(butterflies: s.meadowButterflies, count: s.meadowCount) }
}
