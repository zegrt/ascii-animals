import OceanKit

/// Ready-made shark line-ups, and the names people see for each species.
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
}
