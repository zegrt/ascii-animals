import Foundation
import OceanKit

/// The interaction the Task 11 parity recording plays on the Web, step by step (step 1 is the first after the
/// warm-up). The reference page (scratchpad parity.ts) runs the same script on the original, from the same state.
final class WebScript {
    private let w: WebWorld
    private var s = 0
    private var aim = (x: 0.0, y: 0.0)
    private(set) var events: [String] = []

    init(world: WebWorld) { w = world }

    /// engine.ts onPointerMove, by world coordinates.
    private func move(_ x: Double, _ y: Double) { w.pointerMoved(x: x, y: y) }

    func step() {
        s += 1
        let W = w.width
        let near = w.weavers.last
        if s >= 120 && s < 240, let web = near?.web {
            // The pointer drawn through the near web, level with its hub, right to left: the silk rings.
            let k = Double(s - 120) / 120
            move(Double(web.x[web.hub]) + web.outer * (0.7 - 1.4 * k), Double(web.y[web.hub]) + 7)
        }
        if s == 240 { w.pointerLeft() }
        if s == 300, let web = near?.web {
            // A click on the near web's capture spiral (else its hub): a fly drops there, sticks, and the spider comes.
            var p = Vec(x: Double(web.x[web.hub]), y: Double(web.y[web.hub]))
            for l in 0..<web.m where web.isLaid(l) && web.kind[l] == SPIRAL {
                p = web.pos(l, 0.5)
                break
            }
            w.release(x: p.x, y: p.y)
            events.append(String(format: "click %.1f,%.1f", p.x, p.y))
        }
        if s >= 420 && s < 900, let j = w.jumper {
            // The pointer held still 260 px from the jumper: it stalks, crouches and pounces.
            if s == 420 {
                let sp = j.spider
                aim = (min(W - 20, max(20, sp.x + (sp.x < W / 2 ? 260 : -260))), sp.y)
                events.append(String(format: "aim %.1f,%.1f", aim.x, aim.y))
            }
            move(aim.x, aim.y)
        }
        if s == 900 { w.pointerLeft() }
    }
}
