import OceanKit

enum Presets {
    static let all: [(title: String, sharks: [SharkKind])] = [
        ("Mixed", [.greathammer, .classic, .mako, .tiger]),
        ("Four classics", [.classic, .classic, .classic, .classic]),
        ("Hammerheads", [.greathammer, .hammerhead, .hammerhead]),
        ("Thresher and nurses", [.thresher, .nurse, .nurse]),
        ("All eight", [.greathammer, .thresher, .tiger, .mako, .zebra, .classic, .nurse, .hammerhead]),
    ]

    static func title(_ k: SharkKind) -> String {
        switch k {
        case .classic: return "Classic"
        case .hammerhead: return "Hammerhead"
        case .tiger: return "Tiger"
        case .zebra: return "Zebra"
        case .greathammer: return "Great hammerhead"
        case .mako: return "Mako"
        case .thresher: return "Thresher"
        case .nurse: return "Nurse"
        }
    }
}
