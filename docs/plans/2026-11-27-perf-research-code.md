# Performance research: code facts at meadow-3.1 @ 0dfbb9a

Read-only study. The worktree `scratchpad/join` HEAD is `0dfbb9a9e2e1` (verified). Prior audit: `origin/review-a2:reviews/a2.md`
(reviewed `meadow-t11` @ 971a216); not redone here. Paths are relative to `Sources/` unless they start with `Tools/` or `docs/`.
Nothing was built or run, so every "fraction" below is either a2's measurement or read from the code. Where neither
gives a number, this report says "not measured" or "not found".

## 0. What changed since a2 (971a216..0dfbb9a, 44 commits)

`git diff --stat 971a216 0dfbb9a` shows **no change** to any frame-path file: `ASCIIAnimals/DesktopWindows.swift`,
`ASCIIAnimals/OceanDirector.swift`, `ASCIIAnimals/SystemSignals.swift`, `OceanKit/Render/{OceanRenderer,CellCanvas,Shaders}.swift`,
`OceanKit/Meadow/MeadowPainter.swift`, `OceanKit/Domain/{OceanClock,HabitatScene,Dissolve}.swift`, `OceanTool/{Bench,main}.swift`
and `Tools/energy.sh`. a2's line references for these files are still valid. The changes are elsewhere:
- **Pointer routing (r1):** `ASCIIAnimals/PointerMonitor.swift` (+90/−10) and `OceanKit/Domain/PointerRouter.swift` (+131). Events now
  route by the event's own window number. `EventWindowVerdicts` (PointerRouter.swift:73–128) caches each window number's
  layer, so a move over a known window costs one map lookup. The window list is read again only for an unknown number, at
  most once a second per missed number. Verdicts clear on Space or display change (PointerMonitor.swift:41–42,58–61). The
  rectangle fallback `occluders` (PointerMonitor.swift:91–105) runs only for events with no window number. It is cached
  for 50 ms, with a fresh read on click. **a2's "~20 window-list reads/s on a moving mouse" no longer holds.**
  The other per-event work is unchanged. `viewports()` builds an array and reads `NSScreen.screens` on every event
  (OceanDirector.swift:40, DesktopWindows.swift:140–143). `pointerMoved` calls `pointerLeft()` on every scene that is not hit
  (OceanDirector.swift:280–289).
- **PowerPolicy (t11):** adds `PowerPolicy.preview` and `Tour.mode`, used only by the previews (PowerPolicy.swift:60–68,82–112).
  The desktop's `PowerPolicy.mode` (51–58) is unchanged.
- **main.swift:** adds wallpaper reconcile on `activeSpaceDidChange` and `didWake` (main.swift:68–73), at launch (55) and on display
  change (65). **These observers call only `reconcileWallpaper()`, never the director.** The energy logger
  (`startFrameMeter`, main.swift:104–132) is unchanged apart from moved lines. It runs only when `plan.reportsFrameRate`
  (main.swift:94), which is set only in the test copy (OceanKit/Domain/AppIdentity.swift:100).
- **LiveOceanView (t11):** previews now follow `PowerPolicy.preview` (`run`/`resume`/`startLink`, LiveOceanView.swift:150–184). The
  `warm` loop still commits 60 command buffers that are empty for Web and Meadow (99–108).

## A. Per-frame path today: display-link callback to present

**Setup per display** (DesktopWindows.swift:45–89). There is one borderless window at desktop level that joins all Spaces
(55–56), is opaque, has a black background and no shadow (58–60). Its backing layer is a full-screen `CAMetalLayer` (13–24):
BGRA8 (`OceanRenderer.outputFormat`, OceanRenderer.swift:23), `framebufferOnly`, `maximumDrawableCount = 2`, sRGB, native backing
scale, drawable = screen frame × scale, opaque (66–76). Each display has its own `CADisplayLink` from `NSView.displayLink(target:selector:)`
(85), on `.main` in `.common` modes (87), created paused (86). Each display also gets a `ViewportRenderer`: an inFlight
ring of 3 (OceanRenderer.swift:82–83), Ocean wake/cells/fish textures and the glyph atlas, all created eagerly (150–165).

**Rate request:** `setFrameRate` sets `CAFrameRateRange(min: f, max: f, preferred: f)` (DesktopWindows.swift:102–105). `apply`
calls it for `.live(fps)` and for `.still` (at 15) (OceanDirector.swift:69–73).

**Tick** (`OceanDirector.tick`, OceanDirector.swift:95–135), the same for every habitat:
1. Dissolve: if one is running, `d.frame(at: link.targetTimestamp)`; at the swap point, `rebuildScenes()` builds new sims for
   **every** scene inside this callback (96–102, Dissolve.swift:53–58).
2. Live: `s.scene.advance(to: targetTimestamp, speed:)`. The fixed 1/60 s clock clamps dt to 0.1 s and runs at most 4 steps
   (OceanClock.swift:15–28). A shared scene ignores timestamps it has already counted, so stepping happens once across screens
   (HabitatScene.swift:58–61). The step runs **before** the drawable is acquired (OceanDirector.swift:114–115). A nil drawable has
   already spent sim time.
   Still: `nextDrawable()` first, then `sim.settle()` (110–112).
3. `metalLayer.nextDrawable()` runs on the main thread. It can block, because `allowsNextDrawableTimeout` is left at its
   default (no other setting found).
4. `renderer.queue.makeCommandBuffer()`, then `viewport.encode(habitat:…target: drawable.texture…)` (118–122), dispatched by type
   (OceanRenderer.swift:186–197):
   - **Ocean** (303–361): `semaphore.wait()` on main (316). `FramePacker.pack` writes the uniform ring slot and the 4 B/cell fish grid
     (325–327). `fishTex.replace` uploads the whole grid (328–329). Then 0–4 full-grid wake passes (`max(1,steps)` on clear)
     (333–346), one cells pass (349–353), and one **full-drawable** `compose_main` pass (355–360). Every pass uses `.dontCare` load and
     `.store` (167–179).
   - **Web / Meadow** (`CellPainter`, 202–285): `canvas.clear()` zeroes 5 arrays plus the ground (208, CellCanvas.swift:52–63).
     `painter.paint` (213). `semaphore.wait()` (215). Five **whole-grid** `replace` uploads (235–239), plus a sixth for the ground
     when `hasGround`, which is Meadow only (241–258). A 64 B uniform (261–265). One **full-drawable** `canvas_main` pass (275–284).
     - Meadow paint (`MeadowPainter.paint`, MeadowPainter.swift:379–403): `buildGround` (a cached early return, 720–723),
       `readAir` (shared across screens per world step, 765–791), `drawGround` (touches **every grass tuft every frame**,
       793–869), `drawMotes`, `drawFlowers`, `drawButterflies`, `drawDust`, then `blit`. The blit copies the whole cached packed ground
       into `canvas.ground` and writes only the cells in the frame's `touched` list (943–970).
     - Web paint (`WebPainter.paint`, WebPainter.swift:926–960). The stroke accumulator keeps a per-frame touched-cell list
       (308–309).
5. `cb.present(drawable)`. `addScheduledHandler` on **every** commit, although only the first frame uses it (123–127).
   `cb.commit()`.
6. `framesDrawn += 1` (never read anywhere) and `framesByDisplay[id, default: 0] += 1`. That is a dictionary write per commit,
   read only by the test copy's 5 s meter (129–130, main.swift:108,117).

**Where each lever cuts in:**
- (1) Eligibility: before step 1. `OceanScreen.setRunning` (DesktopWindows.swift:108–111) and `OceanDirector.apply`/`visibilityChanged`
  (OceanDirector.swift:55–91). A paused link means no callback, no sim step (the sim advances only from `tick`) and no submit.
  Pointer: `updatePointer` runs only in `.live` (79–85).
- (2) Pacing: `setFrameRate` (DesktopWindows.swift:102–105) or a guard at the top of `tick`. Step 2's acquire-before-advance order.
- (3) Changed regions: the layer setup (DesktopWindows.swift:13–24,64–77), `encode(painter:)`'s single full pass (OceanRenderer.swift:275),
  and `px = in.clip.xy` in `canvas_main` and `compose_main` (Shaders.swift:667, 524).
- (4) Cheap wins: steps 4–6 (see F).

## B. Lever 1: eligibility

**Signals that exist now:**
- Per window: `NSWindow.didChangeOcclusionStateNotification` → `visible = occlusionState.contains(.visible)` (DesktopWindows.swift:82–83,
  127–130). The bit means *partly* visible. It is ignored until that screen's first frame (`visible || !presented`, 109).
- Global (SystemSignals.swift:25–35): `screensDidSleep` and `screensDidWake` (all displays together), session resign and become active,
  `com.apple.screenIsLocked`/`Unlocked`, screensaver start and stop, Low Power, thermal, battery through IOPS (38–45), and a
  30 s `Timer` with no tolerance that re-reads `CGSessionCopyCurrentDictionary` and scans running apps (47–49, 76–84).
  The timer runs whether or not anything is drawing.
- `PowerPolicy.mode` gives `.paused` if `!anyWindowVisible || displaysAsleep || locked || saver || !sessionActive || userPaused`
  (PowerPolicy.swift:51–53). `anyWindowVisible = screens.contains { visible || !presented }` (OceanDirector.swift:88).
- `activeSpaceDidChange` and `didWake` are observed, but only for the wallpaper still (main.swift:68–73) and for pointer
  verdicts (PointerMonitor.swift:41).
- Per-display sleep `CGDisplayIsAsleep` is used only by the what's-new card (WhatsNewCard.swift:164, 788). **Not on the desktop
  path.** Mirror detection (`CGDisplayMirrorsDisplay` or similar): **not found anywhere.**

**a2 finding-1 gaps, status at 0dfbb9a.** All remain open, because the files are unchanged:
1. **Partial exposure keeps the whole display live.** One visible strip (for example a translucent or transparent menu bar
   over a maximized window) keeps the full drawable and painter at full rate. No exposed-area logic was found.
2. **Never-presented exception, worse than a2 stated.** `firstFrame` (OceanDirector.swift:137–141) calls `markPresented()`
   but **never re-runs `visibilityChanged()` or `apply`**. Take a screen that received "occluded" before its first frame,
   for example one launched under a full-screen app. Once that screen presents, its link keeps running at full rate until
   some unrelated event calls `apply`. `signals.anyWindowVisible` also stays stale (true) until the next occlusion
   notification. This is a concrete way to keep submitting while nothing is visible.
3. **No explicit active-Space or full-screen decision.** The code relies on AppKit occlusion only. The window joins all Spaces
   without `.fullScreenAuxiliary` (DesktopWindows.swift:56). Whether it reports occluded inside a full-screen Space cannot be
   verified from code.
4. **Sleep is global only.** One external display asleep on its own is not detected unless AppKit reports occlusion.
5. **Mirror sets are not normalized.** `drawnScreens` filters nothing except built-in-only mode (OceanDirector.swift:196–199).
6. **A held still can be owed while hidden.** `showChangeIfHeld` sets `stillPending` and `setRunning(true)` for a user pause
   whatever the hidden state (OceanDirector.swift:252–255). `HeldFrame.link(.paused)` keeps a pending still for a user pause
   (Dissolve.swift:76–84). The run is still gated by `visible || !presented`, so the exposure is bounded by gap 2.
7. **The resume jump.** The desktop never resets a scene's clock on pause. Only `rebuild` resets it (HabitatScene.swift:36–40).
   LiveOceanView resets on `stop` (LiveOceanView.swift:188–191). The first tick after resume adds `min(0.1, dt)` and runs the
   4-step cap (OceanClock.swift:19–26): a one-frame sim jump of 66.7 ms, against 33 ms normally.

**Already true today:** once every window reports not visible after its first frame, the mode becomes `.paused`. Every link
pauses (`HeldFrame.link`), so no callbacks, no `advance`, no submits. The pointer monitor is removed (`updatePointer`),
and the layer keeps its last presented contents (nothing clears or hides it). Remaining wake-ups are the 30 s timer, plus the
test copy's 5 s meter.

**The smallest safe design that reaches zero submissions:**
1. In `firstFrame`, after `markPresented()`, call `visibilityChanged()`. That re-derives `anyWindowVisible` and re-applies
   `setRunning`. One line, and it closes gap 2.
2. Add a per-screen `eligible = visible && CGDisplayIsAsleep(id) == 0` and use it in `setRunning` and in `anyWindowVisible`.
   Re-evaluate on `screensDidSleep`/`Wake`, `didChangeScreenParameters` and `activeSpaceDidChange`. On those events, re-read
   `window.occlusionState` synchronously rather than waiting for a notification. This is event-driven, with no polling.
3. In `drawnScreens`, drop any screen whose `CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay`, so a mirror member that
   is not the leader is never drawn. The cost is nothing if AppKit already lists only the leader.
4. Keep the last frame: do nothing to the layer on pause. Keep the 2 drawables, opacity 1 and `presented = true`.
5. Resume without a jump: add `HabitatScene.resetClock()`. Call it when a scene goes from no running screen to at least one,
   so the first tick runs 0 steps and the next tick steps normally. Leave shared scenes alone while another of their screens
   still runs.
6. Keep the pointer monitor tied to `.live`, which it already is. The sim stops by itself, since `advance` runs only from `tick`.
7. Give the 30 s reconcile timer a tolerance, or arm it only while `.paused` for lock, saver or session reasons. This is
   pixel-neutral.
8. Deferred as a product decision, as a2 said: partial exposure, meaning a lower rate or tile-limited drawing when only a
   strip shows. Computing it needs window-list geometry on events, never per frame.

Proof needed: a pure eligibility table in OceanKit, built like `HeldFrame` and covered by PolicyChecks.swift:6–75 style checks,
plus per-display presented counts (see E).

## C. Lever 2: exact pacing

**How the rate is requested:** `min = max = preferred = fps` on a `CADisplayLink` (DesktopWindows.swift:102–105).
`Settings.fps` is one of 15, 30 or 60 (OceanKit/Domain/Settings.swift:50,60–61). The economy rate is 15 (PowerPolicy.swift:49).
A `CADisplayLink` can fire only on vsync multiples. On a 100 Hz panel the achievable uniform rates are 100/n: 100, 50,
33.3, 25, 20, 16.7, 14.3. A request for 30 lands on 33.3, every 3rd vsync. 15 lands on 16.7, every 6th. That matches the logged
33.3 and 16.7 (docs/DEVELOPING.md:95). It is about 11% above the request on each rate. The count is commits, not
presents (OceanDirector.swift:129–130).

**Smallest change for an exact even rate (25 on 100 Hz):** in `setFrameRate`, request the largest `max/n` not above the
setting, using `NSScreen.maximumFramesPerSecond` (already read in Diagnostics.swift:13). Results: 100 Hz gives 25 or 14.3;
60 or 120 Hz gives 30 or 15; 75 Hz gives 25 or 15. That is one function and a pure check. **Side effect:**
`Tools/energy.sh:413` rejects any display outside 0.85–1.15 × the requested rate, so 25 against 30 fails. The script must
learn the expected per-display rate first.

**Exact average 30 on 100 Hz:** this needs uneven intervals, 3+3+4 vsyncs = 30/30/40 ms. Run the link at the native maximum
and add a guard at the top of `tick`, before any work: `if targetTimestamp < nextDue - ε { return }; nextDue += 1/30`
(re-seed `nextDue` after any gap). The cost is 100 main-thread wake-ups/s per display, each returning early. That cost is not
measured, and it trades the even cadence for judder.

**CAMetalDisplayLink** is available (Package.swift:6 sets the floor at macOS 14). It hands over the drawable and the target
presentation time, and can run off the main thread, which removes the blocking `nextDrawable` on main. It does **not** change
which rates a 100 Hz panel can deliver, so it is a latency and robustness change, not the 30-vs-33.3 fix.

**Risks:**
- Sim time is owned by the fixed-step clock (OceanClock.swift:15–28), so the motion speed does not depend on the rate. At 25 fps,
  2.4 steps per frame; at 1.5× speed, 3.6, still under the 4-step cap.
- At economy 14.3 or 16.7 fps and speed 1.5 (Settings.swift:58), the needed 5.4–6.3 steps exceed the cap. `acc` is then zeroed
  (OceanClock.swift:26) and **the sim runs slow**. This is already true today at 16.7.
- Pixels at a given sim state stay identical, because shader time is `world.time` (FramePacker.swift:128) and Meadow uses
  `simT = world.time` (MeadowPainter.swift:553).
- The dissolve is timed by `targetTimestamp` against `CACurrentMediaTime()` (OceanDirector.swift:98,219–220), so it stays exact
  in time at any rate. It gets fewer frames at 25 fps (0.8 s ≈ 20 frames).
- No wall clock is drawn: not found.
- Shared scenes on mixed-rate screens already accept the newest timestamp (HabitatScene.swift:56–61).
- Moving `advance` after a successful acquire is safe for timing, because the clock accumulates up to the 0.1 s clamp.

## D. Lever 3: presenting only what changed

**Each pixel depends on its own cell only.** Both full-screen shaders derive everything from the absolute device pixel
`px = in.clip.xy`. `cellF = min(floor(px/res/cwh), grid-1)`, and the 1-device-pixel grid test is
`floor(px) == round(cellF*slot)`. Atlas reads are integer `read()`, with no filtering (Shaders.swift:503–510). The dissolve
uses `revealHash(cell) >= reveal` (449–454). Meadow's ground is one texel per cell (canvas_main 655–706). So each output
pixel is a pure function of its own cell's texels, the uniforms and the atlas. **A tile is dirty exactly when one of its cells
changed, or a uniform changed** (reveal, theme, grid colour, background). The right and bottom remainder pixels belong to
the clamped last cell.

**Change per frame, per habitat:**
- **Meadow:** a2 measured the **ground plane** at 1.02% (external) and 1.48% (built-in) changed cells per frame. Block, ink and
  glyph churn: **not measured.** From the code, every grass tuft is rewritten every frame (`drawGround`, MeadowPainter.swift:841–866).
  Its ink index (65 steps) and alpha depend on the live air magnitude, so tufts change whenever the wind does. Tuft density is
  `(0.09 + 0.22·patch + 0.08·noise)·grass` with grass = 1.0 (739–760, dens at 753; MeadowTuning.swift:96), so roughly 9–39% of cells
  carry a tuft. Flowers replay until their head moves a quarter cell (MeadowPainter.swift:10). Butterflies, shadows, dust and
  motes move every frame. **Meadow's dirty fraction may therefore be large and wind-dependent. Measure it before building tiles.**
  What the painter knows: the per-frame `touched` list (stamp == frame, 413–425,943–970), a **superset** of the drawn cells, not
  of the changed cells. Because tufts are always touched, `touched(prev) ∪ touched(now)` is a poor dirty set.
- **Web:** **not measured.** The black background is static. The painter knows the per-frame touched cells
  (WebPainter.swift:308–309). Silk is mostly static, but spiders, flies, plucks and dew move.
- **Ocean:** **not measured.** Empty water is black plus the grid (compose_main 531–540). Changes are fish cells (340 at stock),
  shark sprites with a time shimmer (586–587), wake dots where e > 0.45 (552–559) and heat. Cells are classified **on the GPU**
  (cells_main), so the CPU only has the fish grid (`fishBytes`) and shark geometry. Exact dirt needs a GPU compare. a2: "Ocean
  wakes have a larger and changing footprint." Meadow first, as planned.

**Tile design that keeps output byte-identical (Meadow first, then Web):**
- **Layers:** the `OceanView` backing becomes a plain opaque `CALayer` (DesktopWindows.swift:13–24) with a fixed grid of
  `CAMetalLayer` sublayers. Example: 16×16-cell tiles. The external display (197×76 cells, per a2) gets 13×5 = 65 tiles of
  208×304 px at 1×. The built-in (139×62) gets 9×4 = 36 tiles of 416×608 px at 2×. Tile edges sit on integer device pixels;
  the frame is in points with `contentsScale = scale`. Each tile is opaque, BGRA8, `framebufferOnly`, `maximumDrawableCount` 2.
  The total drawable area equals today's. The fade-in moves to the root layer (116–122). `fit` re-lays out the tiles (92–100).
  No separate static base layer is needed: a tile that does not present keeps its last image.
- **Shader:** add a device-pixel origin to the uniforms and use `px = in.clip.xy + origin`. `CanvasUniforms.misc.zw` is unused today
  (OceanRenderer.swift:69, Shaders.swift:652), so the struct does not grow. With integer origins, `x + 0.5 + origin` is exact in
  float32. Every later expression (cellF, grid line, `lp`/`lpt`, atlas index, revealHash, ground read) then sees the same values,
  which gives byte-identical output. The Ocean `compose_main` would need the same field in its `hd` buffer
  (FramePacker layout).
- **Uploads:** unchanged. The whole-grid textures are uploaded once per frame (0.018–0.023 ms per pair, a2). Each dirty tile is one
  render pass of `canvas_main` into its own drawable, all in one command buffer.
- **Dirt:** keep last frame's six canvas arrays per viewport and `memcmp` each tile's row spans (about 425 KB per pair in total).
  That is exact and needs no painter changes. Any change to reveal, theme, background or grid colour marks every tile dirty.
  a2's "row spans were 5× slower" result was about **upload** (0.025 vs 0.005 ms per pair), and it is irrelevant when the saving
  is compositor work.
- **Ring slots:** tiles are independent drawables, so there is no stale-slot problem inside a tile. Each dirty tile redraws fully.
- **Tearing risk (fidelity):** a butterfly crossing a tile edge can show halves from different frames if tiles land on
  different vsyncs. Atomic presents need `presentsWithTransaction = true`, then commit, `waitUntilScheduled` and
  `drawable.present()` inside one `CATransaction`. That is a main-thread wait. Measure it.
- **Unknowns, not answerable from code:** whether WindowServer's cost scales with the damaged sublayer area. DEVELOPING.md:84 says
  WS "redraws everything above it on every frame", which suggests damage size matters. Also the per-layer and per-transaction
  overhead for 36–65 layers. Prototype with 1, 4, 16 and 64 tiles at equal presented counts, as a2 Architecture B advised.
- **Cheaper variant to test first:** skip `present` entirely when every tile is clean, which is the same compare at whole-frame
  granularity. It costs almost nothing, but it fires only when nothing moves.

## E. Tooling now, and what is missing

**Exists:**
- `Tools/energy.sh` (1126 lines): `top -l` samples of the app and WindowServer CPU and memory for exact pids (274–300, 976–997),
  baseline mode, and validation that the test copy's 5 s readings put each display within ±15% of the requested rate (356–432,
  413). It counts **commits** (`framesByDisplay`). It does not use powermetrics, GPU counters or presented frames.
- `OceanTool bench` (OceanTool/main.swift:181–200): CPU sim and paint per habitat; `--desk` gives the two-target offscreen model.
  `--digest` **forces Web** (194–197) and hashes the canvas arrays, **not pixels and not the ground** (Bench.swift:117–126).
- OceanChecks:
  - A pinned Ocean still SHA-256 (RenderChecks.swift:121–125).
  - `renderFrame` GPU readback of a `ViewportRenderer` frame into a managed BGRA texture (CanvasChecks.swift:408–428), used for
    byte-equality across ring slots and for ground and no-ground frames (495–530).
  - Policy and clock tables (PolicyChecks.swift:6–116).
  - `HeldFrame` desk checks (MeadowDeskChecks.swift, MeadowFix4Checks.swift).
- Snapshot flags: `--snapshot-settings`, `-about`, `-onboarding`, `-whatsnew` and `-menu`, for UI PNGs and text
  (SettingsView.swift:31, AboutWindow.swift:19–22, OnboardingController.swift:92–98, StatusMenu.swift:41–44). None covers the
  desktop path.

**Missing, to prove "same pixels, less work" and to count presents:**
1. **A presented-frame ledger** per display: `drawable.addPresentedHandler`, counting `presentedTime > 0` against dropped frames,
   with an interval histogram. Also counts of callbacks, early returns, nil drawables and commits. Today there are commits only.
2. **A multi-habitat output-pixel digest** over N consecutive frames × all ring slots, with Ocean, Web and Meadow at 1× and 2×,
   dark and paper, Calm, mid-dissolve and pointer scripts. It should be built on `renderFrame`, so any pacing, tile or
   cheap-win change can be shown byte-identical at equal sim steps.
3. **A tile-composition check:** render each tile with an origin, stitch the tiles, and `==` the full-frame bytes.
4. **A churn bench:** per frame, the fraction of changed cells and of dirty tiles (16×16 and 8×8) per habitat, over a scripted wind
   and pointer minute. Meadow and Web can use the CPU canvases. Ocean needs a readback of consecutive compose outputs.
   **This number decides lever 3.**
5. energy.sh: per-display expected rates for divisor pacing (413), test-copy flags to select pacing or tile mode, and
   interleaved A/B blocks (a2).
6. Eligibility proofs: no app-level harness drives `OceanScreen` and `OceanDirector` (ASCIIAnimals is not imported by
   OceanChecks). Move the eligibility decision into OceanKit so it can be checked as a table.

## F. Cheap, byte-identical wins visible now

1. `addScheduledHandler` on every commit; it is needed only when `first` (OceanDirector.swift:123–127). Wrap it in `if first`.
2. `framesDrawn` is written but never read, and `framesByDisplay` takes a dictionary write per commit, read only by the test copy
   (OceanDirector.swift:26–28,129–130; main.swift:108–117). Use a stored per-`OceanScreen` counter, or gate it on
   `Launch.plan.reportsFrameRate`.
3. Acquire the drawable before `advance` (OceanDirector.swift:114–116), so a nil drawable spends no sim. Steps stay equal within the
   0.1 s clamp.
4. `CellCanvas.clear` zeroes the ground (CellCanvas.swift:54–57), and Meadow's blit then overwrites all of it from the cache
   (MeadowPainter.swift:948). That clear is redundant for Meadow (a2 also noted).
5. Meadow never writes the overlay (no `overGlyph`/`putOver` in OceanKit/Meadow). It still clears and uploads `overInk` and
   `overGlyph` every frame, about 5 B/cell (OceanRenderer.swift:238–239). Add a `hasOverlay` flag like `hasGround`, with a shader
   flag in `misc.z` that skips the overlay reads when the flag is false. This is identical only if the flag false means all 255.
6. `revealHash` is evaluated for every pixel even at reveal == 1, where it can never fail (Shaders.swift:533, 677, hash < 1
   by construction, 449–454). Guard it with `reveal < 1`. That saves GPU ALU with the same output.
7. `LiveOceanView.warm` commits 60 empty command buffers for Web and Meadow (LiveOceanView.swift:103–106; `encode` with
   `target: nil` does nothing for painters, OceanRenderer.swift:190–196). Skip them unless the sim is an `OceanSim`.
8. The SystemSignals 30 s timer has no tolerance and runs while hidden (SystemSignals.swift:47–49). Set a tolerance.
9. Pointer: cache `viewports` (rebuilt on `screensChanged`) instead of rebuilding it and reading `NSScreen.screens` per event
   (OceanDirector.swift:40, DesktopWindows.swift:140–143). Call `pointerLeft` only on a hit change (OceanDirector.swift:280–289).
   That is identical only if `pointerLeft` is idempotent per sim, which was not checked here.
10. Not byte-related but cheap: `firstFrame` should re-apply visibility (B, gap 2). It is a one-liner that can save whole
    full-rate frames on a covered launch.

Out of scope for "cheap": Ocean pack allocations (about 20 per draw) and the GPU tail-wake search, covered by a2 #6.
