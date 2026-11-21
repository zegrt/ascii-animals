import CoreGraphics
import Foundation

/// OceanTool's numbers, checked before anything is converted to an integer, allocated or written (mp's review,
/// finding 6: `--scale nan`, `--seconds 1e300`, `--fps 0` or a `nanx150` size trapped). Each returns nil for a value
/// out of range, so the tool can refuse it with a message. Here rather than in the tool so `OceanChecks` can hold them.
public enum ToolInput {
    /// The largest image side the renderer makes (Metal's texture limit), in pixels; sizes in points are held to it too.
    public static let maxSide = 16384.0
    /// The longest run or warm-up a command takes, simulated seconds.
    public static let maxSeconds = 3600.0

    /// `WxH` in points, each finite and 1…`maxSide`.
    public static func size(_ text: String) -> CGSize? {
        let parts = text.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) else { return nil }
        guard w.isFinite && h.isFinite && w >= 1 && h >= 1 && w <= maxSide && h <= maxSide else { return nil }
        return CGSize(width: w, height: h)
    }

    /// A scale for an image of `points`: finite, above 0, and the image 1…`maxSide` pixels each way.
    public static func scale(_ text: String, for points: CGSize) -> CGFloat? {
        guard let v = Double(text), v.isFinite, v > 0 else { return nil }
        let w: Double = Double(points.width) * v, h: Double = Double(points.height) * v
        guard w.isFinite && h.isFinite && w.rounded() >= 1 && h.rounded() >= 1 && w <= maxSide && h <= maxSide else { return nil }
        return CGFloat(v)
    }

    /// Seconds (a run or a warm-up): finite, 0…`maxSeconds`.
    public static func seconds(_ text: String) -> Double? {
        guard let v = Double(text), v.isFinite, v >= 0, v <= maxSeconds else { return nil }
        return v
    }

    /// Frames per second: a whole number dividing the 60 steps a second (1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60).
    public static func fps(_ text: String) -> Int? {
        guard let v = Int(text), v > 0, 60 % v == 0 else { return nil }
        return v
    }

    /// A count of frames (`bench --digest --frames`): 1…1,000,000.
    public static func count(_ text: String) -> Int? {
        guard let v = Int(text), v >= 1, v <= 1_000_000 else { return nil }
        return v
    }

    /// A height for the butterfly sheet, 0…1.
    public static func unit(_ text: String) -> Double? {
        guard let v = Double(text), v.isFinite, v >= 0, v <= 1 else { return nil }
        return v
    }
}
