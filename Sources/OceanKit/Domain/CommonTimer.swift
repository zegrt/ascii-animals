import Foundation

/// A repeating timer on the main run loop in its common modes, so it keeps firing while a menu is open or a window is
/// dragged (AppKit runs the loop in its event-tracking mode then, and a timer in the default mode waits). The
/// energy-test copy's readings use it: a reading that stalls while the director has a menu open reads as a gap.
public enum CommonTimer {
    @discardableResult
    public static func repeating(every interval: TimeInterval, on runLoop: RunLoop = .main,
                                 _ body: @escaping (Timer) -> Void) -> Timer {
        let t = Timer(timeInterval: interval, repeats: true, block: body)
        runLoop.add(t, forMode: .common)
        return t
    }
}
