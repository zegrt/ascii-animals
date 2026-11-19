import Foundation

/// The switch between habitats: the old picture dissolves out cell by cell
/// (the shaders' revealHash), the scenes are rebuilt, and the new one
/// dissolves in. Only while animating: a still or a pause swaps at once.
public enum Dissolve {
    /// Seconds to dissolve the old habitat out, then the new one in.
    public static let out = 0.35
    public static let into = 0.45

    /// `reveal` for the shaders `elapsed` seconds into a switch; `swapNow`
    /// from the moment the old picture is gone (the caller swaps once);
    /// `done` once the new picture is whole.
    public static func reveal(elapsed: Double) -> (reveal: Float, swapNow: Bool, done: Bool) {
        if elapsed < out {
            return (Float(1 - max(0, elapsed) / out), false, false)
        }
        let t = (elapsed - out) / into
        if t >= 1 - 1e-9 { return (1, true, true) }
        return (Float(t), true, false)
    }

    /// Only a live wallpaper dissolves; `.still` and `.paused` swap at once.
    public static func shouldAnimate(_ mode: RunMode) -> Bool {
        if case .live = mode { return true }
        return false
    }

    /// After a change to the picture (a habitat switch, a setting, the theme)
    /// while not animating: whether to draw one settled still of it now. A
    /// Low Power / Reduce Motion still and a user pause hold a frame that
    /// must show the change; a covered or locked desktop shows it on its next
    /// visible frame anyway, so it only rebuilds.
    public static func drawsStillNow(_ mode: RunMode, userPaused: Bool) -> Bool {
        switch mode {
        case .live: return false
        case .still: return true
        case .paused: return userPaused
        }
    }
}

/// One habitat switch in progress, timed by the display link's clock.
public struct DissolveRun: Equatable, Sendable {
    public private(set) var start: Double
    /// The scenes have been rebuilt (the swap was reported).
    public private(set) var swapped = false

    public init(start: Double) { self.start = start }

    /// The reveal for a frame at `t`. `swap` is true exactly once: on the
    /// first frame at or past the moment the old picture is gone.
    public mutating func frame(at t: Double) -> (reveal: Float, swap: Bool, done: Bool) {
        let f = Dissolve.reveal(elapsed: t - start)
        let swap = f.swapNow && !swapped
        if f.swapNow { swapped = true }
        return (f.reveal, swap, f.done)
    }

    /// Another switch at `t`. Before the swap nothing changes (the swap
    /// builds whatever is chosen by then); after it, dissolve out again from
    /// the current level and swap again.
    public mutating func restart(at t: Double) {
        guard swapped else { return }
        let level = Double(Dissolve.reveal(elapsed: t - start).reveal)
        start = t - (1 - level) * Dissolve.out
        swapped = false
    }
}
