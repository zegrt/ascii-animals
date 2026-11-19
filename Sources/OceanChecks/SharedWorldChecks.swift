import CoreGraphics
import Foundation
import OceanKit
import simd

private func sharedWorld(_ kinds: [SharkKind] = [.greathammer, .classic, .mako, .tiger], seed: UInt64 = 5) -> World {
    let w = World(sharks: kinds, rng: Rng(seed: seed))
    w.resize(terrain: Terrain(rects: [userMonitor, userLaptop]), cell: CGSize(width: 13, height: 19), density: 1)
    return w
}

func sharedWorldChecks() {
    check("sharedFishCountPerRect") {
        try expect(sharedWorld().fish.count == 680, "fish \(sharedWorld().fish.count)")
    }
    check("sharedSharksPerScreen") {
        let w = sharedWorld()
        try expect(w.sharks.count == 8, "sharks \(w.sharks.count)")
        try expect(Set(w.sharks.map(\.home)) == [0, 1], "homes \(w.sharks.map(\.home))")
        try expect(w.sharks.filter { $0.home == 1 }.count == 4, "laptop sharks")
    }
    check("sharedSharksCappedAt16") {
        let w = World(sharks: Array(repeating: .mako, count: 8), rng: Rng(seed: 1))
        let r = { (x: Double) in CGRect(x: x, y: 0, width: 1000, height: 800) }
        w.resize(terrain: Terrain(rects: [r(0), r(1000), r(2000)]), cell: CGSize(width: 8, height: 12), density: 1)
        try expect(w.sharks.count <= 16, "sharks \(w.sharks.count)")
    }
    check("fishCapRaised") {
        let w = World(sharks: [], rng: Rng(seed: 1))
        let r = { (x: Double) in CGRect(x: x, y: 0, width: 2000, height: 2000) }
        w.resize(terrain: Terrain(rects: [r(0), r(2000), r(4000), r(6000)]), cell: CGSize(width: 13, height: 19), density: 2)
        try expect(w.fish.count == World.maxFish && World.maxFish == 1024, "fish \(w.fish.count)")
    }
    check("sharedFishStayInTerrain") {
        let w = sharedWorld()
        for _ in 0..<3600 { w.step(1.0 / 60) }
        let alive = w.fish.filter(\.alive)
        let inside = alive.filter { w.terrain.contains(SIMD2($0.x, $0.y)) || w.terrain.signedOutside(SIMD2($0.x, $0.y)) < 2 }
        try expect(Double(inside.count) >= Double(alive.count) * 0.98, "inside \(inside.count)/\(alive.count)")
    }
    check("sharksMigrate") {
        let w = sharedWorld()
        let first = w.sharks.map(\.home)
        var crossed = false
        for _ in 0..<(180 * 60) {
            w.step(1.0 / 60)
            for (i, sh) in w.sharks.enumerated() where w.terrain.rectIndex(near: SIMD2(sh.nodes[0], sh.nodes[1])) != first[i] {
                if w.terrain.contains(SIMD2(sh.nodes[0], sh.nodes[1])) { crossed = true }
            }
            if crossed { break }
        }
        try expect(crossed, "no shark crossed to another screen in 180 s")
    }
    check("sharksStayInTerrain") {
        let w = sharedWorld()
        var samples = 0, ok = 0
        for s in 0..<3600 {
            w.step(1.0 / 60)
            guard s % 10 == 0 else { continue }
            for sh in w.sharks {
                samples += 1
                if w.terrain.signedOutside(SIMD2(sh.nodes[0], sh.nodes[1])) < sh.length * 0.5 { ok += 1 }
            }
        }
        try expect(Double(ok) >= Double(samples) * 0.99, "in terrain \(ok)/\(samples)")
    }
    check("eventsHaveSeqAndPrune") {
        let w = sharedWorld()
        w.splash(100, 100)
        w.splash(200, 100)
        try expect(w.events.count == 2 && w.events[1].seq > w.events[0].seq, "seq not increasing")
        try expect(w.eventSeq == w.events[1].seq, "eventSeq")
        for _ in 0..<130 { w.step(1.0 / 60) }
        try expect(!w.events.contains { $0.kind == .splash }, "splash not pruned after 2 s")
    }
    check("stepCountCounts") {
        let w = sharedWorld()
        for _ in 0..<7 { w.step(1.0 / 60) }
        try expect(w.stepCount == 7, "stepCount \(w.stepCount)")
    }
    check("singleRectUnchanged") {
        let a = World(sharks: [], rng: Rng(seed: 9)), b = World(sharks: [], rng: Rng(seed: 9))
        a.resize(width: 800, height: 500, cell: CGSize(width: 8, height: 12), density: 1)
        b.resize(terrain: .single(width: 800, height: 500), cell: CGSize(width: 8, height: 12), density: 1)
        for _ in 0..<300 { a.step(1.0 / 60); b.step(1.0 / 60) }
        try expect(a.fish.map(\.x) == b.fish.map(\.x), "single-rect paths diverged")
    }
}
