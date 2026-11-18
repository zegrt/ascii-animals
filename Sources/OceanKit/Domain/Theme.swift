/// Numbers the compose shader needs to colour the ocean.
public struct ThemeParams: Equatable, Sendable {
    public var light: Bool
    public var brightness: Float
    public var accentRate: Float
    public var grid: Bool
    public var wake: SIMD3<Float>

    public static let cyan = SIMD3<Float>(110, 230, 255) / 255

    public static func make(_ s: Settings, systemIsDark: Bool, accent: SIMD3<Float>) -> ThemeParams {
        let light = s.appearance == .light || (s.appearance == .system && !systemIsDark)
        return ThemeParams(
            light: light,
            brightness: s.calm ? 0.62 : 1,
            accentRate: s.calm ? 0.35 : 1,
            grid: s.grid,
            wake: s.wakeColor == .accent ? accent : cyan)
    }
}
