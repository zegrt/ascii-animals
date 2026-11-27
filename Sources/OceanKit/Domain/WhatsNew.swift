import CoreGraphics
import Foundation

/// The rules behind 3.1's what's-new card (design d1, option C) that don't need a screen: when a waiting card may come
/// up, where it goes, what its preview does as the machine's state changes, and which part of a meadow its still shows.
/// The app's `WhatsNewCard` does the AppKit side; these are kept here so the checks can drive them.
public enum WhatsNew {
    // MARK: When

    /// What the app knows when a waiting card looks again.
    public struct Moment: Equatable, Sendable {
        /// Not locked, the session on the console, no screensaver, and the chosen display awake: read live.
        public var seeable: Bool
        /// Displays attached.
        public var screens: Int
        /// The once-only flag (`Handover.meadowCardKey`) as saved now.
        public var shown: Bool
        public var habitat: HabitatKind
        public var tried: Bool
        /// The welcome (from Help, or the tour) is up.
        public var welcomeUp: Bool
        /// A renderer to draw the Meadow with.
        public var canDraw: Bool

        public init(seeable: Bool, screens: Int, shown: Bool, habitat: HabitatKind, tried: Bool, welcomeUp: Bool,
                    canDraw: Bool) {
            self.seeable = seeable
            self.screens = screens
            self.shown = shown
            self.habitat = habitat
            self.tried = tried
            self.welcomeUp = welcomeUp
            self.canDraw = canDraw
        }
    }

    public enum Verdict: Equatable, Sendable {
        /// Bring it up now.
        case show
        /// Not now: look again later.
        case wait
        /// Never this launch: it has been shown, the Meadow found, or nothing can draw it (a later launch tries).
        case drop
    }

    public static func verdict(_ m: Moment) -> Verdict {
        if m.shown || m.tried || m.habitat == .meadow || !m.canDraw { return .drop }
        if m.welcomeUp || !m.seeable || m.screens == 0 { return .wait }
        return .show
    }

    /// What the app does on a look.
    public enum Step: Equatable, Sendable {
        case keepWaiting
        case open
        case stop
    }

    /// The waiting card, looked at once a second from about a second after launch. Clear at the first look, it opens
    /// at once; after a wait (a locked or sleeping screen after a night-time update) it opens only once the screen has
    /// stayed clear for a full second, so a wake that relocks at once doesn't spend it. Every look reads the live
    /// state, so the look that opens it is the latest word.
    public struct Waiter: Equatable, Sendable {
        private var first = true
        private var clear = 0

        public init() {}

        public mutating func look(_ v: Verdict) -> Step {
            defer { first = false }
            switch v {
            case .drop:
                return .stop
            case .wait:
                clear = 0
                return .keepWaiting
            case .show:
                if first { return .open }
                clear += 1
                return clear >= 2 ? .open : .keepWaiting
            }
        }

        /// The card couldn't be put on a usable display after all: it waits again, unmarked.
        public mutating func openFailed() {
            first = false
            clear = 0
        }
    }

    /// One launch's waiting card, from its first look to its opening or its end. The app looks once a second;
    /// `moment` reads the live state, `open` builds the card and orders it forward (true only once it is on a usable
    /// display, still seeable), and `mark` saves the once-only flag. The flag is saved only after an opening that
    /// reached the screen; a failed one waits again, unmarked.
    public final class Presenter {
        private var waiter = Waiter()
        public private(set) var finished = false
        private let moment: () -> Moment
        private let open: () -> Bool
        private let mark: () -> Void

        public init(moment: @escaping () -> Moment, open: @escaping () -> Bool, mark: @escaping () -> Void) {
            self.moment = moment
            self.open = open
            self.mark = mark
        }

        /// `.open`: it is up and marked. `.stop`: nothing more this launch. Either way the app stops looking.
        public func look() -> Step {
            guard !finished else { return .stop }
            switch waiter.look(verdict(moment())) {
            case .keepWaiting:
                return .keepWaiting
            case .stop:
                finished = true
                return .stop
            case .open:
                if open() {
                    mark()
                    finished = true
                    return .open
                }
                waiter.openFailed()
                return .keepWaiting
            }
        }

        /// Something else took over (the welcome from Help): no more looks.
        public func cancel() { finished = true }
    }

    // MARK: Where

    /// The card's width in the design; narrower only where the screen is.
    public static let width: CGFloat = 460
    static let margin: CGFloat = 8

    /// The card's width on a screen with this visible frame: the design's, or as much as fits with a margin each side.
    public static func width(visible: CGRect) -> CGFloat {
        let room: CGFloat = visible.width - 2 * margin
        return max(1, min(width, room))
    }

    /// The icon's frame, when it is a usable anchor: on a screen, at the top of it (in the menu bar, above the visible
    /// frame), and of a real size. Otherwise nil, and the card goes top right. `screens`: each screen's frame and
    /// visible frame.
    public static func anchor(icon: CGRect?, screens: [(frame: CGRect, visible: CGRect)]) -> (icon: CGRect, visible: CGRect)? {
        guard let icon, icon.width >= 1, icon.height >= 1, icon.minX.isFinite, icon.minY.isFinite else { return nil }
        let mid = CGPoint(x: icon.midX, y: icon.midY)
        for s in screens where s.frame.contains(mid) {
            // In the menu bar: at or above the top of the visible frame (the app menu can push an item off it).
            let inBar: Bool = icon.minY >= s.visible.maxY - 2 && icon.maxY <= s.frame.maxY + 1
            return inBar ? (icon, s.visible) : nil
        }
        return nil
    }

    /// Where the card goes, in screen coordinates (bottom-left origin): its frame, and the arrow's x in the card when
    /// it points at the icon. Under the icon, the arrow toward the card's right; with no usable icon, the top right of
    /// the visible frame. Kept inside `visible` either way (`size.width` should come from `width(visible:)`).
    public static func placement(size: CGSize, icon: CGRect?, visible: CGRect) -> (frame: CGRect, arrowX: CGFloat?) {
        let lo: CGFloat = visible.minX + margin
        let hi: CGFloat = max(lo, visible.maxX - margin - size.width)
        guard let icon else {
            let x: CGFloat = max(lo, visible.maxX - size.width - 12)
            let y: CGFloat = max(visible.minY, visible.maxY - 10 - size.height)
            return (CGRect(x: x, y: y, width: size.width, height: size.height), nil)
        }
        let preferred: CGFloat = icon.midX - size.width * 0.8
        let x: CGFloat = min(max(preferred, lo), hi)
        let top: CGFloat = min(icon.minY - 2, visible.maxY)
        let y: CGFloat = max(visible.minY, top - size.height)
        let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        let arrow: CGFloat = min(max(icon.midX - x, 24), max(24, size.width - 24))
        return (frame, arrow)
    }

    // MARK: The preview

    public enum Preview: Equatable, Sendable {
        /// The Meadow moving.
        case live
        /// One held frame: Low Power Mode (unless the person keeps it animating), or the Mac too hot.
        case still
        /// Nothing drawn: the screen can't be seen (locked, asleep, screensaver, another user's session).
        case stopped
    }

    /// The card's preview for the machine's state: the desktop's own rule (`PowerPolicy.mode`), except that a paused
    /// desktop or covered windows don't stop a card someone is looking at.
    public static func preview(_ i: PowerInputs) -> Preview {
        var c = i
        c.anyWindowVisible = true
        c.userPaused = false
        c.reduceMotion = false
        switch PowerPolicy.mode(c) {
        case .paused: return .stopped
        case .still: return .still
        case .live: return .live
        }
    }

    // MARK: The still's framing

    /// The part of the meadow the card's still shows, in the world's points (top-left origin), and what it holds.
    public struct Frame: Equatable, Sendable {
        public var crop: CGRect
        /// The butterfly it is framed on.
        public var butterfly: Int
        public var kind: ButterflyKind
        /// Whole blooms in it.
        public var flowersInside: Int
        /// Other butterflies the crop's edge cuts through.
        public var cut: Int
        /// Blooms the crop's edge cuts through.
        public var cutBlooms: Int
        /// How much of the butterfly's box blooms cover (0 clear).
        public var covered: Double
        /// Higher reads better (`frame`).
        public var score: Double
    }

    /// How far a butterfly reaches from its centre across and down the screen as drawn now: the painter's half-span
    /// across the wings (as open as their stroke shows them) and half-length along the body (longer with tails, `ButterflyPainter.drawButterfly`), turned
    /// to its heading, and a cell for the outline.
    public static func extent(_ b: Butterfly, in world: MeadowWorld) -> (x: Double, y: Double) {
        let open: Double = openness(b)
        let S: Double = world.breeze.unit
        let k: Double = world.depthScale(b.z) * b.size
        let span: Double = b.sp.span * 13 * S * k
        let hs: Double = span / 2 * open
        let tail: Double = b.sp.tailY > -9 ? 1.5 : 1.1
        let hb: Double = span * b.sp.aspect / 2 * tail
        let c: Double = abs(cos(b.heading)), s: Double = abs(sin(b.heading))
        let pad: Double = Double(world.cell.width)
        return (s * hs + c * hb + pad, c * hs + s * hb + pad)
    }

    /// How open its wings look from above, 0.1…1: each wing reaches out as far as its stroke shows it (`setPose`'s
    /// wl and wr). Half closed or less, it reads as a sliver.
    public static func openness(_ b: Butterfly) -> Double {
        max(0.1, cos(b.stroke - b.bank), cos(b.stroke + b.bank))
    }

    /// How well a kind reads at the card's size: the bold wings first, the pale white last.
    static func readable(_ k: ButterflyKind) -> Double {
        switch k {
        case .monarch: return 60
        case .morpho: return 50
        case .swallowtail: return 35
        case .white: return 0
        }
    }

    /// A crop of `size` inside a laid-out meadow: on one whole butterfly, wings open and clear of the blooms, beside a whole bloom,
    /// cutting as few other butterflies and blooms as it can; a big, bold butterfly wins. nil when no butterfly fits
    /// whole beside a bloom.
    public static func frame(_ world: MeadowWorld, size: CGSize) -> Frame? {
        let W = Double(size.width), H = Double(size.height)
        let area = world.terrain.bounds
        let m = 4.0
        typealias Box = (id: Int, x: Double, y: Double, ex: Double, ey: Double)
        func overlap(_ a: Box, _ b: Box) -> Double {
            let w: Double = min(a.x + a.ex, b.x + b.ex) - max(a.x - a.ex, b.x - b.ex)
            let h: Double = min(a.y + a.ey, b.y + b.ey) - max(a.y - a.ey, b.y - b.ey)
            return w > 0 && h > 0 ? w * h / (4 * a.ex * a.ey) : 0
        }
        let blooms: [Box] = world.flowers.all.compactMap { f in
            guard !f.fading, f.age > 0.5 else { return nil }
            let r: Double = f.radius * 1.12
            return (f.id, f.x + f.ox, f.y + f.oy, r, r)
        }
        let flying: [Butterfly] = world.flies.filter { !$0.leaving && !$0.entering }
        let flies: [Box] = flying.map { b in
            let e = extent(b, in: world)
            return (b.id, b.x, b.y, e.x, e.y)
        }
        func inside(_ o: Box, _ c: CGRect) -> Bool {
            let x0: Double = Double(c.minX), x1: Double = Double(c.maxX), y0: Double = Double(c.minY), y1: Double = Double(c.maxY)
            let across: Bool = o.x - o.ex >= x0 && o.x + o.ex <= x1
            let down: Bool = o.y - o.ey >= y0 && o.y + o.ey <= y1
            return across && down
        }
        func cutBy(_ o: Box, _ c: CGRect) -> Bool {
            let x0: Double = Double(c.minX), x1: Double = Double(c.maxX), y0: Double = Double(c.minY), y1: Double = Double(c.maxY)
            let across: Bool = o.x + o.ex > x0 && o.x - o.ex < x1
            let down: Bool = o.y + o.ey > y0 && o.y - o.ey < y1
            return across && down && !inside(o, c)
        }
        var best: (score: Double, frame: Frame)?
        for (i, b) in flies.enumerated() {
            let kind: ButterflyKind = flying[i].kind
            // Wings open, and clear of the blooms (flying over one, it reads as neither), unless it has landed on one
            // in bold colours: then the two read as one, the meadow's own moment. A white on a bloom never reads.
            let covered: Double = blooms.reduce(0) { n, f in n + overlap(b, f) }
            let onBloom: Bool = flying[i].state == .nectar && kind != .white
            guard openness(flying[i]) >= 0.6, covered <= 0.2 || onBloom else { continue }
            // Centres that keep this butterfly whole and the crop inside the meadow.
            let x0: Double = max(b.x + b.ex + m - W / 2, Double(area.minX) + W / 2)
            let x1: Double = min(b.x - b.ex - m + W / 2, Double(area.maxX) - W / 2)
            let y0: Double = max(b.y + b.ey + m - H / 2, Double(area.minY) + H / 2)
            let y1: Double = min(b.y - b.ey - m + H / 2, Double(area.maxY) - H / 2)
            guard x0 <= x1, y0 <= y1 else { continue }
            for f in blooms {
                // And most of a bloom (its centre well in, at most its outer petals cut): the centres both allow,
                // nearest the point between them.
                let fex: Double = 0.6 * f.ex, fey: Double = 0.6 * f.ey
                let fx0: Double = max(x0, f.x + fex - W / 2), fx1: Double = min(x1, f.x - fex + W / 2)
                let fy0: Double = max(y0, f.y + fey - H / 2), fy1: Double = min(y1, f.y - fey + H / 2)
                guard fx0 <= fx1, fy0 <= fy1 else { continue }
                let cx: Double = min(max((b.x + f.x) / 2, fx0), fx1)
                let cy: Double = min(max((b.y + f.y) / 2, fy0), fy1)
                let crop = CGRect(x: cx - W / 2, y: cy - H / 2, width: W, height: H)
                let whole: Int = blooms.reduce(0) { n, g in n + (inside(g, crop) ? 1 : 0) }
                let cutBlooms: Int = blooms.reduce(0) { n, g in n + (cutBy(g, crop) ? 1 : 0) }
                let cut: Int = flies.reduce(0) { n, o in n + (o.id != b.id && cutBy(o, crop) ? 1 : 0) }
                let big: Double = min(b.ex, b.ey)
                let penalty: Double = 100 * Double(cut) + 25 * Double(cutBlooms) + (onBloom ? 0 : 60 * covered)
                let score: Double = big + readable(kind) + 4 * Double(min(whole, 3)) - penalty
                if best == nil || score > best!.score {
                    best = (score, Frame(crop: crop, butterfly: b.id, kind: kind, flowersInside: whole, cut: cut,
                                         cutBlooms: cutBlooms, covered: covered, score: score))
                }
            }
        }
        return best?.frame
    }

    /// The meadow the card's still is cut from: a few previews' worth, so there's a butterfly to frame, and narrow
    /// enough to keep the preview's own cell (`GridSpec.cell(forWidth:)` reaches 9 pt at 1,054 pt), so the still
    /// looks as the live preview does.
    public static func stillArea(_ preview: CGSize) -> CGSize {
        let w: CGFloat = min((preview.width * 2.4).rounded(), 1040)
        return CGSize(width: max(w, preview.width), height: (preview.height * 4).rounded())
    }

    /// The seeds tried for the still; the best frame among them wins.
    public static let stillSeeds: [UInt64] = Array(1...96)

    /// A meadow at `settings` laid out over `area` with `cell`, settled (the still's frame, as `StillRenderer` makes it).
    public static func stillWorld(_ settings: Settings, seed: UInt64, area: CGSize, cell: CGSize) -> MeadowWorld {
        var s = settings
        s.habitat = .meadow
        let sim = MeadowSim(settings: s, seed: seed)
        sim.layout(terrain: .single(width: area.width, height: area.height), cell: cell, settings: s)
        sim.settle()
        return sim.world
    }

    /// The seed and crop for the card's still: the best-reading frame over `stillSeeds`.
    public static func stillFrame(_ settings: Settings, preview: CGSize, cell: CGSize) -> (seed: UInt64, frame: Frame)? {
        let area = stillArea(preview)
        var best: (seed: UInt64, frame: Frame)?
        for seed in stillSeeds {
            let world = stillWorld(settings, seed: seed, area: area, cell: cell)
            guard let f = frame(world, size: preview) else { continue }
            if best == nil || f.score > best!.frame.score { best = (seed, f) }
        }
        return best
    }
}
