# ASCII Sharks Native Wallpaper — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the WebKit prototype with a native Swift + Metal live wallpaper that costs a few percent of CPU, behaves like a real wallpaper (power-aware, matches the lock screen, survives display changes), and is configurable.

**Architecture:** Three layers with one-way dependencies. *Domain* (pure Swift, no AppKit, fully checked): the ocean simulation, habitat geometry, frame packing, power policy, pointer routing, settings. *Render* (Metal): turns a packed frame into pixels for one viewport, on screen or offscreen. *Host* (AppKit): windows, clocks, system signals, menus; it only translates OS facts into domain inputs and domain outputs into OS calls. Every decision lives in the domain layer, where it can be checked without a screen.

**Tech Stack:** Swift 6.4 (Command Line Tools only, no Xcode), SwiftPM, Metal with runtime-compiled MSL, CoreText, AppKit, SwiftUI for the settings window, IOKit power sources, ServiceManagement.

**Spec:** the "Spec" section below (this plan carries its own spec).

---

## Spec

What the user asked for: improve every aspect of the prototype (`Sources/main.swift` + `web/`). Measured baseline on an M5 Pro MacBook on battery: ~14% CPU (WebContent 8.6 + WebKit GPU 4.6 + app 0.9), ~355 MB across three processes, WebKit-throttled to 30 fps on a 120 Hz screen.

1. **Native renderer.** No WebKit. Simulation in Swift (port of `../ascii-sharks/src/world.ts`, `species.ts`, `math.ts`; `../ascii-sharks-rive/ocean_world.luau` is an already-verified port to mirror). Drawing on the GPU with the three-pass design proven in the Rive port (`../ascii-sharks-rive/ocean_wake.wgsl`, `ocean_cells.wgsl`, `ocean_compose.wgsl`; packing in `AsciiOcean.luau`), translated to MSL. Visual parity with the web original (reference frame: `docs/reference/web-frame.png`).
2. **Power.** Pause rendering when nothing is visible (all windows occluded, displays asleep, screen locked, screensaver running, session inactive). Frame-rate cap: 60 default, 30 on battery, still frame in Low Power Mode, 30 fps at thermal `serious`, still at `critical`. Reduce Motion shows a settled still. A user pause is separate from automatic pauses.
3. **Real-wallpaper behaviour.** Set the system wallpaper of each screen to a matching still (lock screen, Mission Control, menu-bar tint, launch, after quit); remember each screen's original wallpaper and restore it on quit and from the menu. Fade in on launch. Display changes (plug, unplug, resolution, arrangement) keep the ocean alive.
4. **Shared ocean (optional).** One world spanning all displays; sharks swim between screens; nothing lives in gaps between screens.
5. **Interaction.** Wake under the cursor and splash on click only over bare desktop (not over windows, menu bar or Dock). Toggle in settings.
6. **Settings.** Shark line-up (1–8 sharks from the 8 species, first is biggest), fish density 0.5–2.0, speed 0.5–1.5, appearance dark / light / follow system, calm mode (dimmer, fewer accent flickers, for icon legibility), grid on/off, wake colour cyan / system accent, interaction on/off, shared ocean on/off, frame-rate cap 30/60/120, match system wallpaper on/off, open at login. Persisted; corrupt or partial stored values fall back to defaults.
7. **Packaging.** Universal (arm64 + x86_64) app bundle, app icon rendered from the ocean, ad-hoc signed, `install.sh` into `~/Applications`. A screensaver bundle sharing the same renderer.
8. **Robustness.** No WebKit process to crash; Metal device loss or a failed shader compile shows a black wallpaper and a menu error, never a crash loop. Long uptime: shader time wraps so shimmer timing never degrades.

## Global Constraints

- Build with Command Line Tools only: no `xcodebuild`, no `xcrun metal`, no XCTest, no Swift Testing (both unavailable; probed). MSL is compiled at runtime with `MTLDevice.makeLibrary(source:options:)`.
- Checks are an executable target: `swift run -c release OceanChecks` exits 0 when all pass, non-zero otherwise, printing `PASS <name>` / `FAIL <name>: <detail>`.
- Minimum macOS 14.0 (for `NSView.displayLink(target:selector:)`).
- Bundle id `local.ascii-sharks.wallpaper`; app name `ASCII Sharks`; executable `ASCIISharks`.
- Limits: `MAX_SHARKS = 8`, `MAX_FISH = 512`, `SHARK_NODES = 20`, `MAX_EVENTS = 16`.
- Species names (wire format, settings, presets): `classic, hammerhead, tiger, zebra, greathammer, mako, thresher, nurse`; shader kind index = position in that list.
- Simulation: fixed step `1/60`, at most 4 steps per frame, `dt` clamped to 0.1 s; speed setting scales simulated time.
- Fish count: `clamp(round(area / 4400), 85, 340)`, then `× density`, rounded, capped at `MAX_FISH` (800×500, density 1 → 91).
- Cell size: `cw = clamp(round(primaryWidthPoints / 124), 8, 13)`, `ch = round(cw * 1.45)`.
- No network at runtime. Font: bundled Geist Mono (OFL), weight 600.
- Never write a path inside our own stills folder as a screen's "original wallpaper".

## Review Focus

1. **Display changes mid-run** (unplug external monitor, clamshell, resolution change): no crash, no stretched frame, fish stay inside the new habitat. → Task 2 check `habitatShrinkKeepsFishInside`, Task 6 manual step.
2. **Original wallpaper safety** (crash then relaunch, two screens, our own still already set): the user's original is never lost or replaced by our still. → Task 7 checks `wallpaperMemoryIgnoresOwnStills`, `wallpaperMemoryKeepsFirstOriginal`.
3. **Long uptime / sleep-wake**: huge `dt` after wake and float time after days. → Task 4 check `packerWrapsTime`, Task 3 policy `wakeResumes`.
4. **Auto-pause never sticks**: lock → unlock, sleep → wake, screensaver start → stop must resume; user pause survives all of them. → Task 3 checks.
5. **Hostile settings**: zero sharks, nine sharks, unknown species, density 99, corrupt JSON. → Task 1 checks.

---

## File Structure

```
Package.swift                      targets: OceanKit (lib), ASCIISharks (exe), OceanChecks (exe), OceanSaver (dylib for .saver)
Sources/OceanKit/
  Domain/Rng.swift                 SplitMix64 seeded RNG
  Domain/Species.swift             SharkKind, Species table, shark shapes (from species.ts + SHAPES in AsciiOcean.luau)
  Domain/World.swift               simulation (port of world.ts / ocean_world.luau)
  Domain/Habitat.swift             union-of-rects geometry, soft-wall push
  Domain/Settings.swift            Settings value, tolerant decoding, sanitizing
  Domain/Theme.swift               Appearance, ThemeParams (pure numbers for the shader)
  Domain/PowerPolicy.swift         PowerInputs -> RunMode
  Domain/PointerRouter.swift       cursor + occluders + viewports -> PointerTarget?
  Domain/FramePacker.swift         World + Viewport + ThemeParams -> FrameData (GPU layout)
  Domain/WallpaperMemory.swift     original-wallpaper bookkeeping (pure, Codable)
  Render/Shaders.swift             MSL source as a Swift string (wake, cells, compose)
  Render/GlyphAtlas.swift          CoreText glyph strip -> MTLTexture
  Render/OceanRenderer.swift       shared device, pipelines; ViewportRenderer per viewport
  Render/StillRenderer.swift       offscreen render of a warmed-up world -> CGImage / PNG
  Resources/GeistMono.ttf, OFL.txt
Sources/ASCIISharks/               host (AppKit)
  main.swift                       composition root
  DesktopWindows.swift             one desktop-level window + Metal view per screen, fade-in, display link
  OceanDirector.swift              owns worlds/viewports, steps sims, applies RunMode
  SystemSignals.swift              battery/low-power/thermal/lock/sleep/screensaver/occlusion/reduce-motion -> PowerInputs
  PointerMonitor.swift             global mouse monitor + CGWindowList occluders -> PointerRouter
  SystemWallpaper.swift            set stills, remember/restore originals via WallpaperMemory
  StatusMenu.swift, SettingsView.swift, SettingsStore.swift, LoginItem.swift
Sources/OceanChecks/main.swift     check runner + all checks (domain + headless render)
Sources/OceanSaver/OceanSaverView.swift   ScreenSaverView using OceanKit
Tools/build.sh                     universal build, bundle assembly, icon, saver, sign
Tools/install.sh                   copy app (and saver) into ~/Applications and ~/Library/Screen Savers
Info.plist, Saver-Info.plist, README.md
```

The `web/` prototype and old `Sources/main.swift`/`build.sh` are deleted in Task 8.

---

### Task 1: Package skeleton, check runner, RNG, Settings

**Files:** Create `Package.swift`, `Sources/OceanKit/Domain/{Rng,Settings,Species}.swift` (Species: only `SharkKind` enum in this task), `Sources/OceanChecks/main.swift`.

**Interfaces — Produces:**
- `struct Rng { init(seed: UInt64); mutating func next() -> UInt64; mutating func unit() -> Double /* [0,1) */; mutating func range(_ a: Double, _ b: Double) -> Double; mutating func chance(_ p: Double) -> Bool }`
- `enum SharkKind: String, CaseIterable, Codable { case classic, hammerhead, tiger, zebra, greathammer, mako, thresher, nurse; var index: Int }`
- `enum Appearance: String, Codable, CaseIterable { case dark, light, system }`, `enum WakeColor: String, Codable, CaseIterable { case cyan, accent }`
- `struct Settings: Codable, Equatable { sharks: [SharkKind] = [.greathammer,.classic,.mako,.tiger]; fishDensity = 1.0; speed = 1.0; appearance = .dark; calm = false; grid = true; wakeColor = .cyan; interaction = true; sharedOcean = false; fps = 60; matchSystemWallpaper = true; paused = false; func sanitized() -> Settings; static let defaults }` — `init(from:)` uses `decodeIfPresent` per key and drops unknown species strings; `sanitized()` clamps density to 0.5…2.0, speed to 0.5…1.5, fps to nearest of {30,60,120}, trims sharks to 8, empty → defaults' sharks.
- Check runner: `func check(_ name: String, _ body: () throws -> Void)`, `func expect(_ cond: Bool, _ detail: @autoclosure () -> String)`, `func expectClose(_ a: Double, _ b: Double, tol: Double, _ detail: String)`; exits 1 if any failed.

- [ ] Write checks: `rngDeterministic` (two `Rng(seed: 7)` give identical first 100 values; `unit()` always in [0,1)), `settingsDecodeEmptyIsDefaults` (`{}` → `Settings.defaults`), `settingsDropsUnknownSpecies` (`{"sharks":["whale","mako"]}` → `[.mako]`), `settingsSanitizeClamps` (density 99 → 2.0, speed 0 → 0.5, fps 45 → 60, nine sharks → 8, zero sharks → default four), `settingsCorruptJSONFallsBack` (`SettingsCodec.decode(Data("nope".utf8))` → defaults).
- [ ] Run `swift run -c release OceanChecks` → fails to compile (types missing).
- [ ] Implement; add `enum SettingsCodec { static func decode(_ data: Data?) -> Settings; static func encode(_ s: Settings) -> Data }` (decode = tolerant decode then `sanitized()`; nil/garbage → defaults).
- [ ] Run checks → all PASS. Commit `feat: OceanKit skeleton, RNG, settings`.

### Task 2: Species, World, Habitat

**Files:** Create `Domain/Species.swift` (complete), `Domain/World.swift`, `Domain/Habitat.swift`; add checks.

**Interfaces — Produces:**
- `struct Habitat { var rects: [CGRect] /* world coords, top-left origin */; var bounds: CGRect; var area: Double; func contains(_ p: CGPoint) -> Bool; func push(_ p: CGPoint, margin: Double) -> CGVector }` — `push` returns the soft-wall acceleration: zero deep inside any rect; inside a rect but within `margin` of an edge that is *not* shared with another rect → `(depth into margin) * 7` away from that edge (world.ts soft-wall constant); outside every rect → toward the nearest point of the nearest rect, magnitude `(distance + margin) * 7`.
- `final class World { init(sharks: [SharkKind], rng: Rng); private(set) var fish: [Fish]; private(set) var sharks: [Shark]; var events: [WorldEvent]; var pointer: (x: Double, y: Double, active: Bool); var time: Double; func resize(habitat: Habitat, cell: CGSize, sizeSide: Double, density: Double); func step(_ dt: Double); func splash(_ x: Double, _ y: Double) }` — `Fish`, `Shark`, `WorldEvent` mirror `ocean_world.luau` field-for-field (`WorldEvent.kind`: 0 eat, 1 splash). `sizeSide` replaces `min(W,H)` in shark sizing (shared ocean passes the primary screen's short side). Soft walls call `habitat.push`; respawning schools enter from an edge of a random habitat rect. All randomness through the injected `Rng` (replaces `Math.random`). Shark sizes: first spec 1.0, each next −0.1 (sorted small first in `sharks`), as in `ocean_world.luau parseSharks`.

- [ ] Write checks (seeded `Rng(seed: 1)`, single rect 800×500, cell 8×12, sizeSide 500, density 1): `seedFishCount` (91), `seedDensityHalf` (density 0.5 → 46), `sharkOrderSmallFirst` (`[.greathammer,.classic,.mako,.tiger]` → `sharks.first!.kind == .tiger`, `sharks.last!.kind == .greathammer`), `sharksEatWithin40s` (≥1 eat event over 2400 steps), `populationRecovers` (>70% alive after 3600 steps), `spineStaysConnected` (`[.thresher,.nurse,.zebra,.hammerhead]`, 1200 steps, every node gap within 0.01 of `length/19`), `habitatPushZeroInside`, `habitatPushTowardNearest` (point right of a lone rect → push.dx < 0), `habitatSharedEdgeNoWall` (two rects side by side, point near the shared edge → push.dx == 0), `sharedOceanFishStayInHabitat` (habitat = 800×500 at (0,0) + 600×400 at (800,100); after 1800 steps ≥ 98% of alive fish inside), `habitatShrinkKeepsFishInside` (after resize to a smaller single rect, every fish inside within 1 step).
- [ ] Run → fail. Implement by porting `ocean_world.luau` (structure) checked against `world.ts` (semantics). Run → PASS. Commit `feat: native ocean simulation with habitat`.

### Task 3: PowerPolicy and PointerRouter

**Files:** Create `Domain/PowerPolicy.swift`, `Domain/PointerRouter.swift`; add checks.

**Interfaces — Produces:**
- `struct PowerInputs: Equatable { var anyWindowVisible = true; var displaysAsleep = false; var screenLocked = false; var screensaverRunning = false; var sessionActive = true; var onBattery = false; var lowPowerMode = false; var thermal: Thermal = .nominal; var reduceMotion = false; var userPaused = false; var fpsSetting = 60 }`, `enum Thermal { case nominal, fair, serious, critical }`
- `enum RunMode: Equatable { case live(fps: Int), still, paused }` — `still` = render one settled frame then stop the clock; `paused` = keep the last frame, no work.
- `enum PowerPolicy { static func mode(_ i: PowerInputs) -> RunMode }`, order: hidden (`!anyWindowVisible || displaysAsleep || screenLocked || screensaverRunning || !sessionActive`) → `.paused`; `userPaused` → `.paused`; `reduceMotion || lowPowerMode || thermal == .critical` → `.still`; fps = `fpsSetting`, capped at 30 if `onBattery || thermal == .serious`.
- `struct Viewport: Equatable { var id: Int; var rect: CGRect /* global, top-left origin, points */ }`, `struct PointerTarget: Equatable { var viewportID: Int; var local: CGPoint }`
- `enum PointerRouter { static func route(_ p: CGPoint, occluders: [CGRect], viewports: [Viewport]) -> PointerTarget? }` — nil when any occluder contains `p` or no viewport does.

- [ ] Checks: `policyDefaultLive60`, `policyBattery30`, `policyBatteryRespects30Setting` (fps 30 → 30), `policyLowPowerStill`, `policyHiddenBeatsEverything` (locked + userPaused → paused), `wakeResumes` (locked → paused; same inputs unlocked → live), `userPauseSurvivesUnlock`, `policyThermalSerious30`, `policyThermalCriticalStill`, `policyReduceMotionStill`; `routerOccluded` (nil), `routerSecondScreen` (viewport 2 at x 1800 → local x = p.x − 1800), `routerGap` (point in no viewport → nil).
- [ ] Run → fail; implement; run → PASS. Commit `feat: power policy and pointer routing`.

### Task 4: Theme and FramePacker

**Files:** Create `Domain/Theme.swift`, `Domain/FramePacker.swift`; add checks.

**Interfaces — Produces:**
- `struct ThemeParams: Equatable { var light: Bool; var brightness: Float /* 1, calm 0.62 */; var accentRate: Float /* 1, calm 0.35 */; var grid: Bool; var wake: SIMD3<Float> /* cyan (110,230,255)/255 or accent */ ; static func make(_ s: Settings, systemIsDark: Bool, accent: SIMD3<Float>) -> ThemeParams }`
- `struct FrameData { var header: [SIMD4<Float>] /* 7 */; var sharks: [SIMD4<Float>] /* MAX_SHARKS*28 */; var fish: [SIMD4<Float>] /* fishCount */; var events: [SIMD4<Float>] /* MAX_EVENTS */ }`
- `struct GridSpec: Equatable { var cell: CGSize; var cols: Int; var rows: Int; static func make(viewportSize: CGSize, cell: CGSize) -> GridSpec }`
- `enum FramePacker { static func pack(world: World, viewport: CGRect /* world coords */, grid: GridSpec, scale: Float, theme: ThemeParams, frameDt: Float) -> FrameData }` — layout copied from `AsciiOcean.luau` (header hd0..hd4 as there, plus **hd5 = (light, brightness, accentRate, grid)** and **hd6 = (wake.r, wake.g, wake.b, 0)**, so the header has 7 entries); positions are made viewport-local (`x - viewport.minX`); fish/sharks/events entirely outside the viewport expanded by the longest shark length are skipped; time written as `world.time.truncatingRemainder(dividingBy: 3600)`. `packShark` (spine undulation, arc lengths, fin tips) ported from `AsciiOcean.luau`. Packing does **not** clear `world.events`; the director clears after all viewports packed.

- [ ] Checks: `gridSpec1800` (1800×1169, cell 13×19 → cols 139, rows 62 — `ceil`), `packerHeader` (cols/rows/fishCount/sharkCount in header), `packerDeadFishMarked` (killed fish → `.z == -1`), `packerViewportLocal` (viewport at x 800 → a fish at world x 900 packs x 100), `packerSkipsFarFish`, `packerWrapsTime` (`world.time = 7200.5` → header time 0.5), `themeCalmDims` (calm → brightness 0.62), `themeSystemFollowsAppearance` (`.system`, systemIsDark false → light true).
- [ ] Run → fail; implement; run → PASS. Commit `feat: theme and frame packing`.

### Task 5: Metal renderer, glyph atlas, still renderer

**Files:** Create `Render/Shaders.swift`, `Render/GlyphAtlas.swift`, `Render/OceanRenderer.swift`, `Render/StillRenderer.swift`, `Resources/GeistMono.ttf`, `Resources/OFL.txt` (from `web/`); add checks; save `docs/reference/web-frame.png` (the WebKit snapshot from the session scratchpad).

**Interfaces — Produces:**
- `final class OceanRenderer { init(device: MTLDevice) throws /* compiles MSL once, builds 3 pipelines */; let device: MTLDevice; func makeViewport(size: CGSize, scale: CGFloat, grid: GridSpec) throws -> ViewportRenderer }`
- `final class ViewportRenderer { func resize(size: CGSize, scale: CGFloat, grid: GridSpec) throws; func encode(_ frame: FrameData, into target: MTLTexture, commandBuffer: MTLCommandBuffer); func clearWake() }` — owns wake ping-pong (`rgba8Unorm`, cols×rows, render targets), cells texture, atlas, uniform `MTLBuffer`s (triple-buffered by frame index to avoid CPU/GPU races). Pass order per frame: wake(prev→next) → cells → compose into `target`.
- `enum GlyphAtlas { static func make(device: MTLDevice, cell: CGSize, scale: CGFloat) throws -> MTLTexture }` — glyph order `: ; t % S X 8 # @ . ' , \` o - * ·` (17), each centred in its slot at `round(ch * 0.74) * scale` px, Geist Mono via `CTFontCreateWithGraphicsFont` + variation `wght = 600`, R8 alpha.
- `enum StillRenderer { static func render(settings: Settings, size: CGSize, scale: CGFloat, warmup: Double, systemIsDark: Bool, accent: SIMD3<Float>, seed: UInt64) throws -> CGImage; static func writePNG(_ image: CGImage, to url: URL) throws }`
- Shaders: translate the three WGSL files to MSL as one source string; uniforms become `constant float4* header [[buffer(0)]]`, `constant float4* sharks [[buffer(1)]]`, `constant float4* fish [[buffer(2)]]`, `constant float4* events [[buffer(3)]]` (fish loop bounded by header count, not an array size). Compose adds: grid only if `grid`; colours × `brightness`; accent probability × `accentRate`; wake colour from hd6; light mode = luminance inversion `c + (1 − 2·luma(c))` applied last (keeps hue).

- [ ] Checks (headless, `MTLCreateSystemDefaultDevice()`): `shadersCompile`, `atlasHasInk` (each of 17 slots has max alpha > 0.5), `stillNotBlank` (800×500 @2, warmup 4 s, seed 1: > 1% of pixels with luma > 0.15), `stillAnimates` (two stills 0.5 s apart differ in > 0.5% of pixels), `stillLightBackground` (appearance light: corner pixel luma > 0.8), `stillCalmDimmer` (mean luma of calm < 0.75 × default), `stillPNGSize` (written PNG is 1600×1000).
- [ ] Run → fail; implement; run → PASS.
- [ ] Visual parity: `swift run -c release OceanChecks --still /tmp-scratch/native.png 1440x900` (runner flag) and compare side by side with `docs/reference/web-frame.png`: same grid, glyph size, shark colouring, fish dashes. Fix differences before committing. Commit `feat: Metal renderer and stills`.

### Task 6: Host — windows, clock, director, signals, pointer

**Files:** Create `Sources/ASCIISharks/{main,DesktopWindows,OceanDirector,SystemSignals,PointerMonitor,SettingsStore}.swift`, `Info.plist` (min 14.0).

**Interfaces:**
- Consumes: Tasks 1–5.
- `final class SettingsStore { var settings: Settings { get set } /* UserDefaults key "settings.v2", SettingsCodec */; var onChange: ((Settings, Settings) -> Void)? }`
- `final class SystemSignals { private(set) var inputs: PowerInputs; var onChange: ((PowerInputs) -> Void)?; func setWindowVisibility(_ anyVisible: Bool); func setUserPaused(_ p: Bool); func setFPS(_ fps: Int) }` — sources: `NSWorkspace` screensDidSleep/Wake + sessionDidResignActive/BecomeActive; `DistributedNotificationCenter` `com.apple.screenIsLocked/Unlocked`, `com.apple.screensaver.didstart/didstop`; `IOPSNotificationCreateRunLoopSource` + `IOPSGetProvidingPowerSourceType`; `ProcessInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange`; `ProcessInfo.thermalState` + notification; `NSWorkspace.accessibilityDisplayShouldReduceMotion` + its notification.
- `final class DesktopWindows { var onFrame: ((Int /* viewport id */, CAMetalDrawable) -> Void)?; var onVisibilityChange: ((Bool) -> Void)?; func rebuild(screens: [NSScreen]); func setFrameRate(_ mode: RunMode); var viewports: [Viewport] }` — per screen: borderless window at `CGWindowLevelForKey(.desktopWindow)`, `[.canJoinAllSpaces, .stationary, .ignoresCycle]`, ignores mouse, black, `alphaValue` 0 until first frame then 0.8 s fade to 1; content view is a layer-backed `NSView` with `CAMetalLayer` (`bgra8Unorm`, `framebufferOnly = true`, `contentsScale` = screen scale); its `displayLink(target:selector:)` drives `onFrame`, `preferredFrameRateRange` from `RunMode`, link paused for `.paused` and after the first frame of `.still`. Occlusion via `NSWindow.didChangeOcclusionStateNotification`.
- `final class OceanDirector { init(renderer: OceanRenderer, windows: DesktopWindows, store: SettingsStore, signals: SystemSignals); func pointer(_ t: PointerTarget?); func pointerDown(_ t: PointerTarget); func screensChanged() }` — owns `[World]` (one shared, or one per viewport) and their habitats; on each frame for viewport *v*: if *v* is the lead viewport of its world, advance the world (fixed-step accumulator, `dt × speed`); pack for *v*; encode; present; after all viewports of a world have packed this tick, clear its events. Applies `PowerPolicy.mode(signals.inputs)` on every input change. Settings changes: sharks/density/shared → rebuild worlds (new `Rng(seed: random)`); appearance/calm/grid/wake → theme only; fps → signals. `screensChanged`: same screen count and shared off → `world.resize` per viewport (keeps fish); otherwise rebuild habitats and resize the shared world.
- `final class PointerMonitor { init(viewports: @escaping () -> [Viewport], onMove: @escaping (PointerTarget?) -> Void, onDown: @escaping (PointerTarget) -> Void) }` — global monitor `[.mouseMoved, .leftMouseDragged, .leftMouseDown]`; occluders from `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])` skipping own pid, layer < 0, alpha < 0.01; occluder list cached for 50 ms except on clicks.

- [ ] Build `swift build -c release`; run the bare executable from `.build` and verify manually: one window per screen at layer −2147483623 (CGWindowList), fade-in, sharks visible, CPU measured with `top -l 3 -s 5 -stats pid,command,cpu,mem` < 5% on battery at 30 fps; `pmset displaysleepnow` → CPU ~0 while asleep; lock (ctrl-cmd-Q) → paused; unlock → live.
- [ ] Commit `feat: native host with power-aware clock and pointer`.

### Task 7: System wallpaper, menu, settings window, login item

**Files:** Create `Domain/WallpaperMemory.swift` (+checks), `Sources/ASCIISharks/{SystemWallpaper,StatusMenu,SettingsView,LoginItem}.swift`.

**Interfaces — Produces:**
- `struct WallpaperMemory: Codable, Equatable { var originals: [String /* screen key */: URL]; mutating func record(screen: String, current: URL, stillsFolder: URL); func original(for screen: String) -> URL? }` — `record` stores only if no entry exists and `current` is not inside `stillsFolder`. Screen key = `CGDisplayCreateUUIDFromDisplayID` string.
- `final class SystemWallpaper { func apply(settings: Settings, screens: [NSScreen], theme: …) ; func restoreAll() }` — stills folder `~/Library/Application Support/ASCII Sharks/Stills/`, file name `still-<screenKey>-<unix ms>.png` (fresh name each time; delete older stills for that screen after setting), rendered by `StillRenderer` at the screen's pixel size, warmup 6 s. Applied at launch (after first frame), on settings changes that affect looks (debounced 2 s), on screen changes. `restoreAll()` on quit and from the menu; memory persisted in UserDefaults `wallpaperMemory.v1`. Off when `matchSystemWallpaper == false` (and restores).
- Status menu: Pause (user pause), Sharks submenu (presets from the prototype + "Custom…" opens settings), Appearance submenu, Settings… (⌘,), Restore Original Wallpaper, Open at Login, Quit (restores wallpaper first). Last renderer error shown as a disabled item when present.
- `SettingsView` (SwiftUI in an `NSWindow`, activates app while open): shark line-up editor (ordered list, add up to 8, remove, reorder by drag, species picker per row), sliders for density and speed, pickers for appearance, wake colour, fps, toggles for calm, grid, interaction, shared ocean, match system wallpaper, open at login. Writes through `SettingsStore`.
- `enum LoginItem { static var isEnabled: Bool; static func set(_ on: Bool) throws }` via `SMAppService.mainApp`.

- [ ] Checks: `wallpaperMemoryIgnoresOwnStills`, `wallpaperMemoryKeepsFirstOriginal` (second record with a different URL keeps the first), `wallpaperMemoryRoundTrips` (encode/decode equal).
- [ ] Run checks → fail; implement; run → PASS.
- [ ] Manual: launch → system wallpaper becomes the still (System Settings › Wallpaper shows it); quit → original restored; menu-bar tint matches ocean. Commit `feat: system wallpaper, settings, menu`.

### Task 8: Packaging, icon, screensaver, cleanup

**Files:** Create `Tools/build.sh`, `Tools/install.sh`, `Sources/OceanSaver/OceanSaverView.swift`, `Saver-Info.plist`, `README.md`; delete `web/`, old `Sources/main.swift`, old `build.sh`.

- `Tools/build.sh`: `swift build -c release --arch arm64` and `--arch x86_64` for `ASCIISharks` and `OceanSaver`; `lipo -create`; assemble `build/ASCII Sharks.app` (copy `AsciiSharks_OceanKit.bundle` into `Contents/Resources` so `Bundle.module` resolves); icon: `OceanChecks --icon build/AppIcon.iconset` renders 1024×1024 still crops at the iconset sizes → `iconutil -c icns`; assemble `build/ASCII Sharks.saver` (principal class `OceanSaverView`); ad-hoc `codesign --force --deep --sign -` both; run `OceanChecks` first and abort on failure.
- `OceanSaverView: ScreenSaverView` — `CAMetalLayer` backed, one `World` + `ViewportRenderer`, `animateOneFrame` at 30 fps, no pointer, no wallpaper changes, settings read from the app's defaults suite (`UserDefaults(suiteName: "local.ascii-sharks.wallpaper")`) read-only.
- `Tools/install.sh`: quits a running instance, copies app to `~/Applications`, saver to `~/Library/Screen Savers`, launches the app.
- [ ] Run `Tools/build.sh` → `lipo -archs` shows `x86_64 arm64`; `codesign -v` passes for both bundles.
- [ ] Run `Tools/install.sh`; verify app launches from `~/Applications`; saver appears in System Settings › Screen Saver (manual).
- [ ] Commit `build: universal app, icon, screensaver; remove WebKit prototype`.

### Task 9: Final verification

- [ ] `swift run -c release OceanChecks` → all PASS (paste output).
- [ ] Measure with the app installed, on battery, desktop visible, 30 s: `top -l 7 -s 5 -stats pid,command,cpu,mem,power -pid <app>` → report mean CPU and memory against the 14% / 355 MB baseline.
- [ ] Toggle each setting once from the settings window and confirm the live wallpaper changes (manual, by the user where the screen can't be captured).
- [ ] Commit any fixes; write the measured numbers into `README.md`.

---

## Revision 1 — after plan review (supersedes the tasks above where they conflict)

1. **Shared ocean → v2.** Spec item 4 is deferred. One `World` per display. `Habitat` is deleted; `World.resize(width:height:cell:density:)` keeps world.ts semantics (single W×H box, origin 0,0). Checks `habitat*` and `sharedOceanFishStayInHabitat` are dropped; `resizeKeepsFishInside` replaces `habitatShrinkKeepsFishInside`. Each viewport's cell size comes from its own width, as in the web original.
2. **Wake runs per simulation step**, not per rendered frame (renderer.ts/WGSL did it per frame, so trail length depended on fps). `ViewportRenderer.encode` takes `steps: Int` (0–4) and runs the wake pass that many times with dt = 1/60; 0 steps → wake untouched. `StillRenderer` runs a wake pass per warmup step. Check `stillHasWake`: after warmup, some pixels match the wake colour (hue within 20° of cyan).
3. **Fish grid on the CPU.** `FramePacker` writes a `cols×rows` RGBA8 fish texture (per cell: present, brightness bucket, alarm, depth) instead of a fish array; cells and wake shaders sample it instead of looping fish. Sharks carry a world-space bounding box (`slot+7.zw` and node `.w`) and the cells shader skips sharks whose box (plus one cell) misses the cell. `MAX_FISH` stays 512 (CPU-side only). Frame-rate options are **30 / 60** only (no 120: the sim steps at 1/60 without interpolation); `fps 45` rounds to 60.
4. **Domain clock and geometry.** New `Domain/OceanClock.swift`: `struct OceanClock { mutating func advance(to timestamp: Double, speed: Double) -> Int /* steps 0…4 */ }` (first call returns 0; dt clamped to 0.1; accumulator reset when 4 steps hit). New `Domain/ScreenGeometry.swift`: `static func flip(_ r: CGRect, primaryHeight: CGFloat) -> CGRect` and point variant (bottom-left ↔ top-left). Checks: `clockFirstCallZero`, `clockSixtyHz` (16.7 ms → 1 step), `clockClampsAfterSleep` (+3600 s → 4 steps then steady), `clockSpeedHalf`, `flipRoundTrips`.
5. **`FramePacker.pack` gets every per-frame input:** `pack(world:, grid:, scale:, theme:, frameDt:, pointer: CGPoint?, clearWake: Bool, into: UnsafeMutableRawPointer)` — packs directly into the `MTLBuffer`'s contents (no per-frame Swift arrays); `FrameData` survives only as a test-side reader. `ViewportRenderer.clearWake()` is removed (the header's clear flag does it).
6. **Rendering resources:** `CAMetalLayer.maximumDrawableCount = 2`, `colorspace = sRGB`, stills tagged sRGB; uniform/fish buffers triple-buffered with a `DispatchSemaphore(value: 3)` signalled in `addCompletedHandler`.
7. **Per-window gating.** Each window's display link is paused while that window is occluded (and after first frame in `.still`), independent of the global `RunMode`; `anyWindowVisible` = OR over windows. Fade-in animates the Metal layer's `opacity` 0→1 (window alpha stays 1, so occlusion state is honest); occlusion is ignored until the first frame is presented.
8. **Auto-pause can't stick.** On `screensDidWake`, `sessionDidBecomeActive`, unlock and every 30 s while auto-paused, `SystemSignals` re-reads the truth: `CGSessionCopyCurrentDictionary()` (`CGSSessionScreenIsLocked`, `kCGSessionOnConsoleKey`) and `screensaverRunning = false` whenever the screen is unlocked and on console. Pure part in `PowerPolicy.reconcile(_ inputs: PowerInputs, session: SessionTruth) -> PowerInputs` with checks `reconcileClearsStaleScreensaver`, `reconcileUnlocks`.
9. **System wallpaper.** Decision: the still is shown while the app runs; on quit the originals come back (Spec 3's "after quit" is dropped). `WallpaperMemory` stores `{url, options}` per screen (options = `desktopImageOptions(for:)` serialised: scaling, allowClipping, fill colour RGBA); paths compared after `resolvingSymlinksInPath()`. Re-apply the still on `NSWorkspace.activeSpaceDidChangeNotification` (setDesktopImageURL is per-Space). Keep the last 3 stills per screen, never delete the one in use. Known limit, documented in README: aerial/dynamic system wallpapers are restored as the image macOS reports, which may be a still of them.
10. **Pointer:** the global monitor is installed only while `RunMode` is live and `interaction` is on; removed otherwise. During manual testing, log the owner of any window blocking the cursor over bare desktop.
11. **Font embedded in code** (`Render/GeistMonoData.swift`, base64, generated by `Tools/embed-font.sh`) — no SwiftPM resources, so no `Bundle.module` in the hand-assembled bundle. OFL text ships in the app's `Contents/Resources` via build.sh. Atlas check gains `atlasUpright`: `.` has ink in its bottom half only, `` ` `` in its top half only.
12. **Screensaver → v2** (sandboxed legacyScreenSaver can't read the app's defaults; lifecycle quirks). Task 8 drops `OceanSaver` and `Saver-Info.plist`.
13. **Tools split:** a separate `OceanTool` executable (`still <path> <WxH> [--light|--calm]`, `iconset <dir>`); `OceanChecks` only checks.
14. **Measurement** (Tasks 6/9) sums the app plus the WindowServer delta against an app-quit baseline, since the 14% baseline included WebKit's GPU process.
