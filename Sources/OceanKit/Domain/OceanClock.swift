/// Fixed-timestep clock: turns display timestamps into whole 1/60 s simulation
/// steps. Frame time is clamped to 0.1 s (sleep, stalls) and at most 4 steps
/// run per frame; `speed` scales simulated time.
public struct OceanClock: Sendable {
    public static let step = 1.0 / 60
    public static let maxSteps = 4

    private var last: Double? = nil
    private var acc = 0.0

    public init() {}

    /// Several display links (screens at different refresh rates) may drive
    /// one clock; a timestamp no newer than the newest seen adds nothing.
    public mutating func advance(to timestamp: Double, speed: Double) -> Int {
        guard let prev = last else { last = timestamp; return 0 }
        guard timestamp > prev else { return 0 }
        last = timestamp
        acc += min(0.1, timestamp - prev) * speed
        var steps = 0
        // A little slack so 1/60 s frames don't lose a step to rounding.
        while acc >= OceanClock.step - 1e-9 && steps < OceanClock.maxSteps {
            acc -= OceanClock.step
            steps += 1
        }
        if steps == OceanClock.maxSteps { acc = 0 }
        return steps
    }

    /// Forget the last timestamp (after a pause) so the next frame starts fresh.
    public mutating func reset() { last = nil; acc = 0 }
}
