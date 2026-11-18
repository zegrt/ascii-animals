import Foundation
import OceanKit

private func makeWorld(_ sharks: [SharkKind] = [], density: Double = 1, seed: UInt64 = 1) -> World {
    let w = World(sharks: sharks, rng: Rng(seed: seed))
    w.resize(width: 800, height: 500, cell: CGSize(width: 8, height: 12), density: density)
    return w
}

private func run(_ w: World, steps: Int, onEat: (() -> Void)? = nil) {
    for _ in 0..<steps {
        w.step(1.0 / 60)
        if let onEat { for e in w.events where e.kind == .eat { onEat() } }
        w.events.removeAll()
    }
}

func worldChecks() {
    check("seedFishCount") {
        let w = makeWorld()
        try expect(w.fish.count == 91, "fish \(w.fish.count)")
        try expect(w.sharks.count == 4, "sharks \(w.sharks.count)")
    }
    check("seedDensityHalf") {
        try expect(makeWorld(density: 0.5).fish.count == 46, "fish \(makeWorld(density: 0.5).fish.count)")
    }
    check("seedDensityCapsAtMax") {
        let w = World(sharks: [], rng: Rng(seed: 1))
        w.resize(width: 4000, height: 3000, cell: CGSize(width: 13, height: 19), density: 2)
        try expect(w.fish.count == World.maxFish, "fish \(w.fish.count)")
    }
    check("sharkOrderSmallFirst") {
        let w = makeWorld([.greathammer, .classic, .mako, .tiger])
        try expect(w.sharks.first!.kind == .tiger, "first \(w.sharks.first!.kind)")
        try expect(w.sharks.last!.kind == .greathammer, "last \(w.sharks.last!.kind)")
        try expect(w.sharks.last!.kind.index == 4, "kind index")
    }
    check("emptySharksAreFourClassics") {
        let w = makeWorld([])
        try expect(w.sharks.count == 4 && w.sharks.allSatisfy { $0.kind == .classic }, "got \(w.sharks.map(\.kind))")
    }
    check("sharksEatWithin40s") {
        var eats = 0
        run(makeWorld(), steps: 2400) { eats += 1 }
        try expect(eats > 0, "no eats in 40 s")
    }
    check("populationRecovers") {
        let w = makeWorld()
        run(w, steps: 3600)
        let alive = w.fish.filter(\.alive).count
        try expect(Double(alive) > Double(w.fish.count) * 0.7, "alive \(alive)/\(w.fish.count)")
    }
    check("spineStaysConnected") {
        let w = makeWorld([.thresher, .nurse, .zebra, .hammerhead])
        run(w, steps: 1200)
        for sh in w.sharks {
            let seg = sh.length / Double(World.sharkNodes - 1)
            for k in 1..<World.sharkNodes {
                let dx = sh.nodes[k * 2] - sh.nodes[(k - 1) * 2]
                let dy = sh.nodes[k * 2 + 1] - sh.nodes[(k - 1) * 2 + 1]
                try expectClose((dx * dx + dy * dy).squareRoot(), seg, tol: 0.01, "segment \(k) of \(sh.kind)")
            }
        }
    }
    check("deterministicWithSeed") {
        let a = makeWorld(seed: 9), b = makeWorld(seed: 9)
        run(a, steps: 300); run(b, steps: 300)
        try expect(a.fish.map(\.x) == b.fish.map(\.x), "same seed diverged")
    }
    check("splashScattersAndRecordsEvent") {
        let w = makeWorld()
        w.splash(400, 250)
        try expect(w.events.contains { $0.kind == .splash }, "no splash event")
    }
    check("resizeKeepsFishInside") {
        let w = makeWorld()
        run(w, steps: 120)
        w.resize(width: 400, height: 300, cell: CGSize(width: 8, height: 12), density: 1)
        try expect(w.fish.allSatisfy { $0.x >= 0 && $0.x <= 400 && $0.y >= 0 && $0.y <= 300 }, "fish outside after shrink")
        w.step(1.0 / 60)
    }
}
