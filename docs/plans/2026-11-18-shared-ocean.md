# Shared Ocean — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One ocean that spans every display: sharks and fish swim from one screen to the next, and nothing lives in the gaps between screens.

**Architecture:** Separate *where the ocean lives* from *what a screen shows*.
- A **Habitat** is the union of the screen rectangles, in "ocean space" (global top-left points, shifted so the union's bounding box starts at 0,0).
- A **World** simulates inside a Habitat.
- A **Viewport** is one screen's rectangle in ocean space, rendered by its own ViewportRenderer.
- A **Scene** is one World plus its clock plus its viewports.

The two modes then become the same thing:
- Separate oceans = one single-rect Scene per screen.
- Shared ocean = one multi-rect Scene with a viewport per screen.

A single-rect Habitat must reproduce today's behaviour exactly, so every existing check keeps passing unchanged.

**Tech Stack:** as the native plan (Swift 6.4 CLT, SwiftPM, Metal, AppKit). Checks: `swift run -c release OceanChecks`.

**Spec:** the "Spec" section below.

---

## Spec

1. A setting, **"One ocean across displays"** (`Settings.sharedOcean`, default **on**). With one display, it makes no difference.
2. In shared mode:
   - The ocean spans all displays. A shark crossing the boundary between two touching screens appears on the other screen continuously, with the wake following.
   - Fish and sharks never settle in space that no screen covers. Gaps and the space beside offset screens count as walls.
   - **Sharks per screen:** the line-up is repeated for each screen, so each screen keeps the shark density of a separate ocean. That's at most 8 per screen and 16 in total.
   - **Fish:** the count is summed per screen with each screen's own clamp, giving the same density as separate oceans.
   - **Migration:** sharks have a home screen, patrol it as they do today, and now and then migrate to a touching screen.
   - **Pointer:** wakes and splashes land in the shared ocean at the right place.
3. Power, occlusion, Low Power and stills behave as before:
   - A covered screen stops drawing.
   - The world keeps stepping while any of its screens is drawing.
   - The world pauses when none are.
4. Changing displays:
   - In separate mode, behaviour is unchanged: the ocean keeps swimming.
   - In shared mode, the ocean is rebuilt for the new arrangement. That's a fresh ocean, and acceptable because display changes are rare.
5. System-wallpaper stills stay per screen and unchanged.

## Global Constraints

- **Single rect = today:** every existing check passes unchanged, and the soft-wall push for a single rect equals world.ts's per-axis formula.
- **Limits:**
  - `MAX_SHARKS` per viewport stays at 8 (the shader limit).
  - `World.maxFish` rises to 1024, because fish are summed per screen.
  - Total sharks are capped at 16.
- **Events:** each one gets a sequence number. A viewport packs only events newer than the last one it packed. The world prunes events older than 2 s. The director no longer clears events.
- **Clock:** `OceanClock` ignores timestamps older than the newest it has seen. Two display links at different rates (120 Hz and 100 Hz) drive one clock.
- **Steps:** each viewport counts the steps since it last drew (`world.stepCount`), capped at 4, and runs that many wake passes.

## Review Focus

1. **Your arrangement:** a 2560×1440 monitor directly above an 1800×1169 laptop, offset 375 pt to the left. Sharks must cross the top edge of the laptop, and no fish may live in the 375 pt strip beside the laptop. → checks `userArrangementLayout` and `sharedFishStayInHabitat`.
2. **Screens with a gap:** these are not adjacent, so there's no migration and no crossing. → `habitatGapNotAdjacent`.
3. **Different refresh rates driving one world:** it must not step twice per frame. → `clockTwoLinks`.
4. **A covered screen resuming later:** no burst of stale events or wake. → `packerEventsAfterSeq` and a cap of 4 steps.
5. **More sharks than the shader takes:** packing must not overflow. → `packerCullsToEight`.

---

## File Structure

```
Sources/OceanKit/Domain/Habitat.swift      NEW  union of rects: exposed edges, adjacency, walls, signed distance, spawn edges
Sources/OceanKit/Domain/SceneLayout.swift  NEW  screens + mode -> scene plans (habitat + viewports + cell)
Sources/OceanKit/Domain/World.swift        habitat-aware walls/patrol/turn-back/seed/respawn, migration, stepCount, event seq
Sources/OceanKit/Domain/OceanClock.swift   monotonic
Sources/OceanKit/Domain/FramePacker.swift  viewport offset, shark culling, event seq filter
Sources/OceanKit/Domain/Settings.swift     sharedOcean
Sources/OceanKit/Render/OceanRenderer.swift   encode takes viewport + tracks lastStep / lastEventSeq
Sources/ASCIISharks/OceanDirector.swift    scenes instead of per-screen worlds
Sources/ASCIISharks/DesktopWindows.swift   OceanScreen holds a scene reference + viewport rect
Sources/ASCIISharks/SettingsView.swift, StatusMenu.swift   the toggle
Sources/OceanChecks/HabitatChecks.swift, SceneChecks.swift   NEW
```

---

### Task 1: Habitat

**Interfaces — Produces:**
```swift
public struct Habitat: Equatable {
  public init(rects: [CGRect])            // ocean space; caller normalises
  public static func single(width: Double, height: Double) -> Habitat
  public let rects: [CGRect]; public let bounds: CGRect; public let area: Double
  public struct Edge { a, b: SIMD2<Double>; normal: SIMD2<Double> /* inward */; rect: Int; length: Double }
  public let edges: [Edge]                 // exposed boundary pieces (rect edges minus parts shared with another rect)
  public let neighbours: [[Int]]           // rect adjacency: touching edges overlapping > 1 pt
  public func doorway(_ i: Int, _ j: Int) -> SIMD2<Double>?   // midpoint of the shared edge segment
  public func contains(_ p: SIMD2<Double>) -> Bool
  public func rectIndex(near p: SIMD2<Double>) -> Int          // containing rect, else nearest
  public func signedOutside(_ p: SIMD2<Double>) -> Double      // >0 outside (distance to habitat), <=0 inside (-distance to nearest exposed edge)
  public func wallPush(_ p: SIMD2<Double>, margin: Double) -> SIMD2<Double>
  public func nearestInside(_ p: SIMD2<Double>) -> SIMD2<Double>
}
```
`wallPush` sums `(margin − s) · 7` along each exposed edge's inward normal, where `s` is the signed distance along that normal, for every edge with `s < margin` whose span (± margin) contains the projection. That's world.ts's per-axis soft wall, generalised. If `p` is in no rect and no edge applied, it pushes toward `nearestInside(p)` with magnitude `(dist + margin) · 7`.

- [ ] Checks:
  - `habitatSingleMatchesBox`: at 9 sample points in, near and outside an 800×500 rect, `wallPush` equals the world.ts formula.
  - `habitatStackedAdjacent`: in the user arrangement (ocean space: monitor (0,0,2560,1440), laptop (375,1440,1800,1169)), the rects are neighbours, and the doorway is (1275, 1440).
  - `habitatSharedEdgeNoWall`: a point 5 pt above the doorway gets zero push.
  - `habitatStripIsWall`: a point at (200, 1600), beside the laptop under the monitor, is not contained and is pushed into the habitat.
  - `habitatGapNotAdjacent`: rects 50 pt apart are not neighbours.
  - `habitatSignedOutside`: −10 at 10 pt inside an exposed edge, +20 at 20 pt outside.
  - `habitatEdgesExposedOnly`: in the stacked case, the total exposed length is the perimeter minus 2 × 1800.
- [ ] RED → implement → GREEN → commit.

### Task 2: World in a Habitat

**Interfaces:**
- `World.resize(habitat: Habitat, cell: CGSize, density: Double)`, with `resize(width:height:cell:density:)` kept as `.single`.
- `World.init(sharks:rng:)` is unchanged. In shared mode the line-up repeats per rect; total sharks ≤ 16.
- `Shark` gains `home: Int`, `orbitFrac: Double`, `migrateAt: Double`, `doorway: SIMD2<Double>?`.
- `World` gains `public private(set) var stepCount: Int` and `public private(set) var eventSeq: Int`.
- `WorldEvent` gains `seq: Int` and `time: Double`. Events older than 2 s are pruned in `step`, and `events` stays publicly readable. The tests that call `events.removeAll()` keep working: still settable.

**Generalisations (each is a single-rect identity):**
- **Soft walls:** `habitat.wallPush(p, 36)`.
- **Fish clamp:** to `bounds ± 60`.
- **Patrol and no-swim zone:** around the home rect's centre, with that rect's size. The orbit radius is `orbitFrac × home.minSide`.
- **Turn-back:** `over = habitat.signedOutside(snout)`, steering to the home centre.
- **Seeding:**
  - Sharks are seeded per rect around that rect's centre, exactly as today with W and H of the rect.
  - Fish are seeded per rect with that rect's count, `clamp(round(area_r / 4400), 85, 340)`. The sum is then × density and capped at 1024.
- **Respawn:** a school enters from a random exposed edge, weighted by length. It enters 20 pt outside, at 15–85% along the edge, heading toward that edge's rect centre.
- **Migration:** only when the home rect has neighbours.
  - At `time ≥ migrateAt`, with the shark not hunting: `home = random neighbour`, `doorway = habitat.doorway(old, new)`, and `migrateAt = time + U(35, 80)` s.
  - While `doorway` is set, add a steer of weight 1.4 toward it. Clear it once the snout is inside the new home rect, 0.25 L past the doorway line.
- The spatial hash covers `bounds`.

- [ ] Checks:
  - All existing world checks stay green.
  - `sharedFishCountPerRect`: in the user arrangement, density 1 gives fish = 340 + 340 = 680.
  - `sharedSharksPerScreen`: 4 kinds × 2 rects gives 8 sharks, homes {0, 1}.
  - `sharedFishStayInHabitat`: after 3600 steps, ≥ 98% of live fish are inside the habitat.
  - `sharksMigrate`: with the seed fixed, at least one shark's snout is seen in a different rect from its first home within 180 s.
  - `sharksStayInHabitat`: across 3600 steps, the snout is within `0.5 L` of the habitat in ≥ 99% of samples.
  - `eventsHaveSeqAndPrune`: seq is increasing, and an event older than 2 s is gone after a step.
  - `singleRectUnchanged`: `resize(width:)` and `resize(habitat: .single)` give identical fish x after 300 steps, seed fixed.
- [ ] RED → implement → GREEN → commit.

### Task 3: Clock, packer and scene layout

**Interfaces:**
- **`OceanClock.advance`:** `last = max(last, ts)`, and a timestamp ≤ last adds nothing.
- **`FramePacker.pack`:** gains `viewport: CGRect` (ocean space) and `afterEventSeq: Int`, and returns the highest event seq it packed.
  - Positions become `p − viewport.origin`.
  - Sharks whose bounding box misses the viewport are skipped. If more than 8 remain, the 8 with the largest overlap are kept, preserving small-to-large order.
  - Only events with `seq > afterEventSeq` inside the viewport (± 6 cells) are packed.
  - The fish grid holds fish inside the viewport only.
  - The pointer is converted to local coordinates.
- **`SceneLayout`:**
  - `struct ScreenInfo { id: Int; frame: CGRect /* global, top-left */; scale: CGFloat }`
  - `struct ScenePlan: Equatable { habitat: Habitat; viewports: [(screenID: Int, rect: CGRect)]; cell: CGSize; originInGlobal: CGPoint }`
  - `static func plan(_ screens: [ScreenInfo], shared: Bool) -> [ScenePlan]`
  - In shared mode the cell size comes from the largest screen's width. In separate mode each screen uses its own width (today's behaviour).

- [ ] Checks:
  - `clockIgnoresOlder`.
  - `clockTwoLinks`: interleaved 120 Hz and 100 Hz timestamps over 1 s give 60 ± 1 steps.
  - `packerViewportOffset`.
  - `packerCullsToEight`: 12 sharks inside the viewport → 8 packed.
  - `packerEventsAfterSeq`.
  - `packerFishOutsideViewportAbsent`.
  - `userArrangementLayout`: global laptop (0,0,1800,1169), monitor (−375,−1440,2560,1440), shared → one plan, viewports monitor (0,0,…) and laptop (375,1440,…), origin (−375, −1440).
  - `separateLayoutTwoPlans`.
  - `singleScreenLayoutSameInBothModes`.
- [ ] RED → implement → GREEN → commit.

### Task 4: Renderer and host on scenes

- **`ViewportRenderer.encode`** gains `viewport: CGRect`. It keeps `lastStepCount` and `lastEventSeq`, computes `steps = min(4, world.stepCount − lastStepCount)`, and on the first frame or after a clear runs a clearing pass.
- **`OceanScene`** (host): `world`, `clock`, `plan`, and `advance(ts:speed:)`, which steps the world by the clock's steps. Each screen's tick calls `scene.advance(link.targetTimestamp)` and then renders its viewport.
- **`OceanDirector`:**
  - Holds `[OceanScene]`; each `OceanScreen` references its scene and viewport rect.
  - `screensChanged`: separate mode works as today (fit and keep); shared mode rebuilds the scenes when any plan changed.
  - Pointer: target screen → ocean point = `viewport.origin + local`.
  - Settings: toggling `sharedOcean` rebuilds the scenes.
- **UI:** a toggle in Settings › Behaviour and the menu: "One Ocean Across Displays".
- **Headless check `sharedRenderTwoViewports`:** a shared world over the user arrangement, rendered into two offscreen targets. Both are non-blank, and a shark placed on the doorway shows ink on both sides of the seam.
- [ ] Build, run on the user's two displays, measure CPU (both screens at 15 fps on battery), and check that `OCEAN_DEBUG` logs one step stream.
- [ ] Commit, rebuild the app, reinstall, rebuild the DMG, push, and update the release.
