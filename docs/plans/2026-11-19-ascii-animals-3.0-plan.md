# ASCII Animals 3.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship ASCII Animals 3.0 from a new repo: the Ocean (today's sharks, unchanged) and Web (a faithful port of ascii-spiders), chosen one at a time, with a clean hand-over from ASCII Sharks.

**Architecture:** A habitat is a simulation (`HabitatSim`) laid out on a `Terrain` (today's `Habitat`, the union of screen rects). Ocean keeps its GPU passes behind an `OceanSim` wrapper; new habitats paint a CPU `CellCanvas` (block colour, ink colour, glyph per cell) that one generic Metal compose pass draws. The host (`HabitatScene`, the director, stills, previews) only talks to `HabitatSim`.

**Tech Stack:** Swift 6 toolchain (Command Line Tools), SwiftPM, Metal (MSL compiled at runtime), AppKit/SwiftUI. Checks: `swift run -c release OceanChecks` (`--only <name>` filters). Reference capture of the original: Node + Chrome (both installed).

**Spec:** `docs/plans/2026-11-19-ascii-animals-design.md`. Meadow (3.1) gets its own plan after this ships.

## Global Constraints

- Name **ASCII Animals** everywhere user-visible; bundle ID **`local.ascii-animals.wallpaper`**; repo **`zegrt/ascii-animals`**; company **XERO WORKS** (legal: XERO WORKS PRIVATE LIMITED).
- `zegrt/ascii-sharks-wallpaper` is frozen at 2.3: its only new commit is one README line pointing to ASCII Animals. Never push this work there.
- Ocean must not change: same look, behaviour and energy (pixel-identical stills for a fixed seed on this Mac).
- Web must look and behave the same as the original side by side; port structure, states, timings, constants, gait, springs and glyph choices faithfully. Deviations only when forced by the platform, listed in `docs/reference/web-port-notes.md`.
- Budget per habitat (M5 Pro MacBook Pro, one display): app CPU ≤ Ocean's (~4–5.5% at 30 fps on AC, ~2.5% at 15 fps), WindowServer no higher than Ocean's, memory ≤ ~100 MB. Fidelity and budget are fixed; if over budget, apply the design's ladder (cache settled silk → slower stepping of untouched webs only if visually identical → GPU silk/body rasterisation). Never fewer webs or simpler motion.
- Spiders are never preselected for a new user; people coming from ASCII Sharks stay on Ocean.
- Commits: identity `Cyril <69159627+zegrt@users.noreply.github.com>`, message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Before any push, the owner's private-string scan over tracked files must print nothing (the controller runs it; the strings are kept out of the repo). Push with `git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push`.
- Every task ends with `swift run -c release OceanChecks` → `N passed, 0 failed`, and `swift build -c release --product ASCIIAnimals` clean.

## Review Focus

1. **Switching habitat while paused or in a Low Power still** — the new habitat's still appears at once (no dissolve, no stale ocean). Pinned in Task 7.
2. **Displays change while on Web** (plug/unplug, the offset monitor-above-laptop layout) — webs re-laid inside screens, none in the gaps, no crash. Pinned in Task 10.
3. **ASCII Sharks won't quit** (an alert open, it ignores SIGTERM) — Animals never runs alongside it: it asks the user to quit Sharks and waits. Pinned in Task 2.
4. **Light theme and Calm on Web** — paper background, graphite ink, no accent colours in Light; Calm dims. Pinned in Task 11.
5. **Tiny viewports** (Settings preview, About banner, welcome tour) on Web — layout completes with at least one web and stays finite. Pinned in Task 10.

---

### Task 1: New repo and identity

**Files:**
- Modify: `Package.swift` (package `AsciiAnimals`; executable target/product `ASCIIAnimals`), move `Sources/ASCIISharks/` → `Sources/ASCIIAnimals/`
- Modify: `Info.plist` (`CFBundleName`/`CFBundleDisplayName` "ASCII Animals", `CFBundleExecutable` "ASCIIAnimals", `CFBundleIdentifier` "local.ascii-animals.wallpaper", `NSHumanReadableCopyright` adds "Web from ascii-spiders by @stackedlol (MIT)")
- Modify: `Sources/ASCIIAnimals/AppInfo.swift` (all URLs → `github.com/zegrt/ascii-animals`, `latestAPI` → `api.github.com/repos/zegrt/ascii-animals/releases/latest`), `SelfUpdater.swift` (`repoPath = "zegrt/ascii-animals"`), `Log.swift` (`Logs/ASCII Animals`, `ascii-animals.log`), every other user-visible "ASCII Sharks" string in `Sources/ASCIIAnimals/`
- Modify: `Tools/build.sh`, `Tools/package.sh`, `Tools/install.sh`, `Tools/uninstall.sh`, `Tools/dmg-settings.py`, `.github/workflows/release.yml` (app `ASCII Animals.app`, assets `ASCII-Animals.dmg` / `ASCII-Animals.zip`, title "ASCII Animals …", process `ASCIIAnimals`)
- Test: `Sources/OceanChecks/AppChecks.swift`

**Interfaces:**
- Produces: product `ASCIIAnimals`; `SelfUpdater.repoPath == "zegrt/ascii-animals"`; build output `build/ASCII Animals.app`.

- [ ] **Step 1: Create the repo and remotes.** `gh repo create zegrt/ascii-animals --private --description "Live ASCII animal wallpapers for macOS"`; `git remote rename origin sharks`; `git remote add origin https://github.com/zegrt/ascii-animals.git`; push `main` to `origin`. Expected: `git remote -v` shows `origin` → ascii-animals, `sharks` → ascii-sharks-wallpaper.
- [ ] **Step 2: Update the self-update check to the new repo.** In `selfUpdateTrustsOnlyThisRepo`, `repo = "zegrt/ascii-animals"`, the trusted URL is `https://github.com/zegrt/ascii-animals/releases/download/v3.0/ASCII-Animals.zip`, and add `https://github.com/zegrt/ascii-sharks-wallpaper/releases/download/v2.3/ASCII-Sharks.zip` to the rejected list.
- [ ] **Step 3: Run it to see it fail** (`--only selfUpdate`), then make the renames and moves listed under Files.
- [ ] **Step 4: Verify.** Checks pass; `Tools/build.sh` builds `build/ASCII Animals.app`; `codesign -dv` shows `Identifier=local.ascii-animals.wallpaper`; `grep -rn "ASCII Sharks\|ascii-sharks-wallpaper\|ASCIISharks" Sources Tools Info.plist .github` prints only the hand-over constants added in Task 2 (none yet) and the ascii-sharks credit URL.
- [ ] **Step 5: Commit** "feat: ASCII Animals identity (new app ID, repo, names)" and push to `origin`.

### Task 2: Hand-over from ASCII Sharks

**Files:**
- Create: `Sources/OceanKit/Domain/Handover.swift`, `Sources/ASCIIAnimals/SharksHandover.swift`
- Modify: `Sources/ASCIIAnimals/main.swift` (run the hand-over at the top of `applicationDidFinishLaunching`, before the renderer starts)
- Test: `Sources/OceanChecks/AppChecks.swift`

**Interfaces:**
- Produces (OceanKit):
  ```swift
  public struct HandoverFacts: Equatable { public var sharksApp: URL?; public var sharksRunning: Bool; public var alreadyImported: Bool; public var sharksSettings: Data? }
  public enum HandoverStep: Equatable { case quitSharks, importSettings, skipWelcome, offerTrash(URL) }
  public enum Handover { public static let sharksBundleID = "local.ascii-sharks.wallpaper"; public static func plan(_ f: HandoverFacts) -> [HandoverStep] }
  ```
- Produces (app): `SharksHandover.run(app: AppDelegate)` — synchronous, returns once Sharks has quit (or there was nothing to do).

- [ ] **Step 1: Write the failing checks** `handoverNothingWithoutSharks` (`sharksApp: nil, sharksRunning: false` → `[]`), `handoverQuitsFirst` (running + installed + settings + not imported → `[.quitSharks, .importSettings, .skipWelcome, .offerTrash(url)]` in that order), `handoverImportsOnce` (`alreadyImported: true`, installed, not running → `[.offerTrash(url)]`), `handoverRunningButNotFound` (running, `sharksApp: nil` → starts with `.quitSharks`).
- [ ] **Step 2: Run to see them fail.**
- [ ] **Step 3: Implement `Handover.plan`, then `SharksHandover.run`.** Facts from `NSWorkspace.urlForApplication(withBundleIdentifier:)`, `NSRunningApplication.runningApplications(withBundleIdentifier:)`, `UserDefaults(suiteName: Handover.sharksBundleID)?.data(forKey: "settings.v2")`, and an Animals defaults flag `handover.imported`. Quitting: `terminate()` then wait up to 5 s; if still running, a modal alert "ASCII Sharks is still running — quit it from its 🐟 menu, then click Continue" that loops until it's gone (Review Focus 3). Import writes the data under `SettingsStore.key` before `SettingsStore` loads. Trash offer: one alert "ASCII Animals takes over from ASCII Sharks", buttons "Move ASCII Sharks to the Trash" / "Keep It", checkbox "Open ASCII Animals at login" (on) → `LoginItem.set(true)`; offered once (`handover.offered`).
- [ ] **Step 4: Verify.** Checks pass. Manual: with ASCII Sharks 2.3 running from `~/Applications`, launch `build/ASCII Animals.app` → Sharks quits (the user's wallpaper is restored by Sharks), Animals starts on Ocean with Sharks' settings, the alert appears once; relaunching shows nothing.
- [ ] **Step 5: Commit** "feat: hand-over from ASCII Sharks".

### Task 3: Rename the geometry type `Habitat` → `Terrain`

**Files:** Modify `Sources/OceanKit/Domain/Habitat.swift` → `Terrain.swift`, `SceneLayout.swift` (`ScenePlan.habitat` → `.terrain`), `World.swift` (`habitat` → `terrain`, `resize(habitat:…)` → `resize(terrain:…)`), every use in `Sources/` and `Sources/OceanChecks/` (`HabitatChecks.swift` → `TerrainChecks.swift`, `habitatChecks()` → `terrainChecks()`).

**Interfaces:** Produces `public struct Terrain` (same API as today's `Habitat`), `ScenePlan.terrain`, `World.resize(terrain:cell:density:)`.

- [ ] **Step 1: Rename mechanically** (no behaviour change; "habitat" now means the product concept only).
- [ ] **Step 2: Verify** checks pass with the same count as before, and `grep -rn "Habitat" Sources` prints nothing.
- [ ] **Step 3: Commit** "refactor: Habitat geometry is now Terrain".

### Task 4: Habitat settings

**Files:**
- Create: `Sources/OceanKit/Domain/HabitatKind.swift`
- Modify: `Sources/OceanKit/Domain/Settings.swift`
- Test: `Sources/OceanChecks/SettingsChecks.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum HabitatKind: String, Codable, CaseIterable, Sendable { case ocean, web }
  public enum SpiderKind: String, Codable, CaseIterable, Sendable { case araneus, argiope, nephila; public static let defaultCast: [SpiderKind] }
  // Settings: habitat = .ocean, webSpiders = SpiderKind.defaultCast, webFlies = true, webJumper = true
  ```
  `defaultCast = [.araneus, .nephila, .argiope, .nephila, .araneus, .argiope]` (the original's `DEFAULT_SPIDERS`, bottom-left first). `sanitized()` caps `webSpiders` at 8 and refills an empty list with `defaultCast`.

- [ ] **Step 1: Write failing checks** `settingsHabitatDefaultsToOcean` (defaults: `.ocean`, `defaultCast`, flies and jumper on), `settingsFromSharksKeepOcean` (decoding `{"sharks":["mako"],"checkForUpdates":true}` → `.ocean`, sharks `[.mako]`), `settingsHabitatRoundTrips` (encode/decode with `.web`, `[.nephila]`, flies off), `settingsUnknownSpiderDropped` (`{"webSpiders":["araneus","tarantula"]}` → `[.araneus]`).
- [ ] **Step 2: Run to see them fail; implement; run to see them pass.**
- [ ] **Step 3: Commit** "feat: habitat settings".

### Task 5: `HabitatSim` and the Ocean behind it

**Files:**
- Create: `Sources/OceanKit/Domain/HabitatSim.swift`, `Sources/OceanKit/Domain/OceanSim.swift`
- Test: `Sources/OceanChecks/SceneChecks.swift`

**Interfaces:**
- Produces:
  ```swift
  public protocol HabitatSim: AnyObject {
      var kind: HabitatKind { get }
      var time: Double { get }
      var stepCount: Int { get }
      func layout(terrain: Terrain, cell: CGSize, settings: Settings)   // ocean space, bounds from 0,0
      func step(_ dt: Double)
      func pointerMoved(_ x: Double, _ y: Double)
      func pointerLeft()
      func pointerDown(_ x: Double, _ y: Double)
      func update(settings: Settings)        // in-place changes (Ocean: fish density)
      func settle()                          // advance to a representative state for a still
  }
  public final class OceanSim: HabitatSim { public let world: World; public init(settings: Settings, seed: UInt64) }
  public enum Habitats {
      public static func make(_ s: Settings, seed: UInt64) -> HabitatSim
      public static func needsRebuild(old: Settings, new: Settings) -> Bool
  }
  ```
  `needsRebuild`: habitat changed; Ocean: `sharks` changed; Web: `webSpiders`, `webFlies` or `webJumper` changed. `OceanSim.settle()` steps 240 times when `time < 4` (today's still behaviour). Until Task 10 `make` returns `OceanSim` for `.web` too, behind a `// Task 10` note.

- [ ] **Step 1: Write failing checks** `oceanSimMatchesWorld` (an `OceanSim` and a bare `World` with the same seed, terrain and steps have identical shark nodes and fish positions), `habitatsRebuildRules` (sharks change → true for ocean; density change → false; habitat change → true; `webFlies` change while on ocean → false).
- [ ] **Step 2: Run to fail; implement; run to pass.**
- [ ] **Step 3: Commit** "feat: HabitatSim, with the Ocean behind it".

### Task 6: Host refactor (no visible change)

**Files:**
- Modify: `Sources/ASCIIAnimals/OceanScene.swift` → `HabitatScene.swift` (holds `sim: HabitatSim`), `OceanDirector.swift` (pointer → `sim.pointerMoved/pointerLeft/pointerDown`; settings → `Habitats.needsRebuild` then rebuild or `sim.update`), `DesktopWindows.swift` (`OceanScreen.scene: HabitatScene`), `LiveOceanView.swift`, `OceanPreview.swift`, `OnboardingController.swift`, `AboutWindow.swift`, `SystemWallpaper.swift`
- Modify: `Sources/OceanKit/Render/OceanRenderer.swift` (add `encode(habitat:viewport:theme:reveal:target:commandBuffer:)`), `StillRenderer.swift` (`render(settings:…)`, `FrameRecorder`, `SceneRecorder` build via `Habitats.make` and draw via `encode(habitat:)`)
- Test: `Sources/OceanChecks/RenderChecks.swift`

**Interfaces:**
- Consumes: Task 5.
- Produces: `ViewportRenderer.encode(habitat: HabitatSim, viewport: CGRect? = nil, theme: ThemeParams, reveal: Float = 1, target: MTLTexture?, commandBuffer: MTLCommandBuffer)`; Ocean path unchanged (`reveal` goes in uniform slot `hd6.w`; compose draws background where `hash(cell) ≥ reveal`; at 1 nothing changes). `HabitatScene(plan:settings:)`, `.sim`, `.rebuild(_:)`, `.update(_:settings:)`, `.advance(to:speed:)`.

- [ ] **Step 1: Record the Ocean's fingerprint before touching anything.** Add check `oceanStillUnchanged`: `StillRenderer.render(settings: .defaults, size: 800x500, scale: 2, warmup: 6, systemIsDark: true, accent: (0.2,0.5,1), seed: 7)` → SHA-256 of the pixel bytes equals a constant; run it once on the current code and paste the printed hash in as the constant.
- [ ] **Step 2: Refactor** the files above so nothing outside `OceanSim`/`StillRenderer`/`OceanRenderer` touches `World` directly (checks and `OceanTool` may).
- [ ] **Step 3: Verify.** All checks pass, including `oceanStillUnchanged`; the app runs, sharks swim, splashes and pointer wakes work, multi-display crossing still works (`OceanTool crossing` frames look the same as `docs/media/crossing.gif`).
- [ ] **Step 4: Commit** "refactor: the host runs a HabitatSim".

### Task 7: Cell canvas, generic compose, dissolve

**Files:**
- Create: `Sources/OceanKit/Render/CellCanvas.swift`, `Sources/OceanKit/Domain/Dissolve.swift`
- Modify: `Sources/OceanKit/Render/GlyphAtlas.swift`, `Shaders.swift` (add `canvas_main`), `OceanRenderer.swift` (canvas pipeline + textures per viewport; dispatch in `encode(habitat:)`), `Sources/ASCIIAnimals/OceanDirector.swift` (dissolve on habitat change)
- Test: `Sources/OceanChecks/CanvasChecks.swift` (new; call `canvasChecks()` from `main.swift`, GPU part inside the GPU block)

**Interfaces:**
- Produces:
  ```swift
  public final class CellCanvas {
      public static let noGlyph: UInt8 = 255
      public let cols: Int, rows: Int
      public var block: [UInt32]   // RGBA8 r|g<<8|b<<16|a<<24, a == 0: no block
      public var ink: [UInt32]     // RGBA8, a = glyph opacity
      public var glyph: [UInt8]    // GlyphAtlas index or noGlyph
      public var background: SIMD3<Float>
      public var gridColor: SIMD4<Float>   // a == 0: no grid
      public init(cols: Int, rows: Int)
      public func clear()
      public func put(_ col: Int, _ row: Int, glyph: Character, ink: SIMD4<Float>, block: SIMD3<Float>? = nil)
  }
  public protocol CellPainter: HabitatSim { func paint(viewport: CGRect, grid: GridSpec, theme: ThemeParams, into canvas: CellCanvas) }
  extension GlyphAtlas { public static func index(_ g: Character) -> UInt8? }
  public enum Dissolve { public static let out = 0.35; public static let into = 0.45
      public static func reveal(elapsed: Double) -> (reveal: Float, swapNow: Bool, done: Bool)
      public static func shouldAnimate(_ mode: RunMode) -> Bool }   // only .live
  ```
  Atlas: append `"¯", "_", "/", "\\", "|", "+", "x", "O", "°", "v", "0"` after today's 17 (Ocean indices unchanged). `canvas_main`: grid line as the Ocean draws it but in `gridColor`; block inset one point from the cell's top-left (as the sharks and the original do); glyph coverage mixes `ink.rgb` by `coverage * ink.a`; cells with `hash(cell) ≥ reveal` show background only. No light-theme inversion here: painters write final colours.

- [ ] **Step 1: Write failing checks** `atlasKeepsOceanIndices` (first 17 glyphs unchanged; `index("¯")` non-nil), `canvasPut` (put "x" at (2,1) → glyph index, ink, block packed as specified), `dissolveTiming` (elapsed 0 → reveal 1; 0.35 → reveal 0 and `swapNow`; 0.8 → reveal 1 and `done`), `dissolveOnlyWhenLive` (Review Focus 1: `.still` and `.paused` → false), and GPU `canvasComposeDraws` (a 4×3 test painter: block cell centre pixel equals the block colour; a glyph cell has ink-coloured pixels; an empty cell's centre equals background; a grid-line pixel equals `gridColor` over background; `reveal: 0` → every pixel is background).
- [ ] **Step 2: Run to fail; implement; run to pass** (`oceanStillUnchanged` still passes).
- [ ] **Step 3: Wire the dissolve.** On a habitat change while live: animate reveal down, rebuild scenes at `swapNow`, animate up. Not live: swap at once and draw one still (existing "paused: show the change once" path).
- [ ] **Step 4: Commit** "feat: cell canvas and the habitat dissolve".

### Task 8: Port — maths and the orb web

**Files:**
- Create: `Sources/OceanKit/Web/WebMath.swift` (← `math.ts`), `Sources/OceanKit/Web/OrbWeb.swift` (← `web.ts`), `docs/reference/web-port-notes.md`
- Test: `Sources/OceanChecks/WebChecks.swift` (new; `webChecks()` in `main.swift`)

Source: `stackedlol/ascii-spiders` at commit `89a7721` (clone to the scratchpad; never vendor it). Port line by line: same names (camelCase), constants, comments; `Math.random()`/`rand` → a shared `WebRandom`.

**Interfaces:**
- Produces: `public final class WebRandom { public init(seed: UInt64); public func unit() -> Double; public func range(_ lo: Double, _ hi: Double) -> Double; public func int(_ lo: Int, _ hi: Int) -> Int }` (wraps `Rng`); free functions `clamp, lerp, ease, easeOut, smoothstep, angleDiff, hash3, noise1, closestT, crossAlong` with the original's signatures; `OrbWeb` with the original's fields and methods (`MOOR…STAB`, `SILK_ALPHA`, route, Verlet step, `pos`, pluck/tension), taking `WebRandom` in `init`.

- [ ] **Step 1: Write failing checks** `webMathMatchesOriginal` (`hash3(1,2,3)`, `noise1(0.5)`, `angleDiff(3, -3)`, `closestT` on a known segment equal values computed by running the original's `math.ts` under Node, pasted as constants), `orbWebRouteComplete` (radius 200, cell 12×17, seed 1: laying every route step leaves every link laid), `orbWebStaysFinite` (finished web, plucked at the hub every second for 60 s of steps: every node finite and within `radius * 1.5` of the hub), `orbWebDeterministic` (same seed → identical node positions after 10 s).
- [ ] **Step 2: Run to fail; port; run to pass.**
- [ ] **Step 3: Commit** "feat(web): port maths and orb webs".

### Task 9: Port — spiders, weavers, jumper, flies, world

**Files:**
- Create: `Sources/OceanKit/Web/Spider.swift` (← `spider.ts`, `SpiderKind` moves here from Task 4's file), `Weaver.swift` (← `weaver.ts`), `Jumper.swift` (← `jumper.ts`), `Flies.swift` (← `flies.ts`), `WebWorld.swift` (← `world.ts`, minus web-page options)
- Test: `Sources/OceanChecks/WebChecks.swift`

**Interfaces:**
- Produces: `public final class WebWorld` with `init(spiders: [SpiderKind], flies: Bool, jumper: Bool, random: WebRandom)`, `layout(terrain: Terrain, cell: CGSize, settled: Bool)`, `step(_ dt: Double)`, `pointer` (x, y, lx, ly, active), `release(x:y:)`, `burst(x:y:)`, `webs`, `weavers`, `jumper`, `swarm`, `heat`, `time`. `Weaver.state: WeaverState` (`build, idle, hunt, wrap, carry, return, eat, move`), `Jumper.state: JumperState` (`pause, burst, crouch, jump`), `Fly.mode: FlyMode`.
  Configuration: the demo page's (no clear centre, no nav gap, first web bottom-left). Multi-rect terrain: candidate web sites are drawn inside a single rect and must fit inside it; flies and the jumper stay inside the terrain (outside every rect counts as a wall).

- [ ] **Step 1: Write failing checks** `weaverLifeCycle` (one web + weaver, `release` a fly at the hub: within 30 s of steps the states seen include `hunt`, `wrap`, `carry`, and the fly reaches `wrapped` or later), `weaverFeelsAPluck` (pointer crossing the web → the weaver turns toward it within 0.5 s, as the original's alert), `jumperPounces` (pointer held still 300 pt from the jumper for 10 s → state reaches `jump`), `legsStayOnSilk` (an idle weaver for 20 s: every planted foot within one cell of its web's silk), `flyFromEmptyClick` (`release` far from any web → a new fly in mode `fly` near that point), `webWorldDeterministic`.
- [ ] **Step 2: Run to fail; port; run to pass.**
- [ ] **Step 3: Commit** "feat(web): port spiders, weavers, jumper, flies and the wall".

### Task 10: Web habitat and painter

**Files:**
- Create: `Sources/OceanKit/Web/WebPainter.swift` (← `renderer.ts`: `Strokes`, silk sampling, `lineGlyph`/`strokeGlyph`, dew, flies, heat, supersampled bodies with `SKIN_RAMP`, markings, palettes), `Sources/OceanKit/Web/WebSim.swift`
- Modify: `Sources/OceanKit/Domain/HabitatSim.swift` (`Habitats.make` returns `WebSim` for `.web`)
- Modify: `Sources/OceanTool/main.swift` (`--habitat web` on `still`, `frames`, `bench`)
- Test: `Sources/OceanChecks/WebChecks.swift`

**Interfaces:**
- Consumes: Tasks 7, 9.
- Produces: `public final class WebSim: CellPainter` (`kind == .web`; pointer → `WebWorld.pointer`, `pointerDown` → `release`; `settle()` lays out settled like the original's `still`). Palettes: dark = original `PALETTES.dark` (background black, grid white 5.5%, ring cyan 110,230,255); light = `PALETTES.light` (paper 247,246,243, ink 35,35,35, grid 35,35,35 at 8%, no accents). Calm: dark multiplies ink and block by `theme.brightness`; light mixes toward paper by `1 - brightness`. Accents limited to the original's rates scaled by `theme.accentRate`.

- [ ] **Step 1: Write failing checks** `webPainterLevelThread` (one level thread across a 20-cell row → those cells hold glyphs from `-_¯`), `webPainterHubKnot` (a finished web's hub cell holds `*`), `webLayoutRespectsTerrain` (Review Focus 2: terrain `[0,0,2560,1440]` + `[375,1440,1800,1169]` → every web frame point inside one rect; relayout to one rect → still inside, no crash), `webTinyViewport` (Review Focus 5: 340×150 → ≥ 1 web, 5 s of steps finite), `webSimFromSettings` (`Habitats.make` with `.web` and `[.nephila]` → one nephila weaver, flies and jumper per settings).
- [ ] **Step 2: Run to fail; port; run to pass.**
- [ ] **Step 3: Verify in the app.** Set `habitat` to `.web` via `defaults write local.ascii-animals.wallpaper settings.v2 -data …` (or the menu once Task 12 lands): webs, spiders, flies and the jumper show; moving through silk rings it; clicking drops a fly.
- [ ] **Step 4: Commit** "feat(web): the Web habitat".

### Task 11: Parity with the original (owner gate)

**Files:**
- Create: `docs/reference/web-original.png`, `docs/reference/web-native.png`, `docs/reference/web-original-light.png`, `docs/reference/web-native-light.png`; update `docs/reference/web-port-notes.md`
- Test: `Sources/OceanChecks/WebChecks.swift`

- [ ] **Step 1: Capture the original.** In the scratchpad clone: `npm install`, add a module that replaces `Math.random` with a seeded generator before the engine loads (reference tool only), `npm run dev`, then Chrome headless `--screenshot --window-size=1440,900` of `/?still=1` and `/?still=1` with the light theme (the `light` route's palette on the demo cast). Record a 20 s run of `/` as frames with `puppeteer-core` driving the installed Chrome.
- [ ] **Step 2: Render ours** with `OceanTool still … 1440x900 --habitat web [--light]` and `OceanTool frames … --habitat web --seconds 20`.
- [ ] **Step 3: Compare side by side** (glyph choice for silk at each angle, hub knots, dew, fly glyphs, body blocks and markings, colours, density of webs, spider sizes; in motion: build speed, gait, sway, hunt/wrap/carry timing, jumper behaviour). Fix every difference or write it into `web-port-notes.md` with the platform reason.
- [ ] **Step 4: Add check `webLightHasNoAccents`** (Review Focus 4: light theme still → background pixels equal paper; no pixel with HSV saturation > 0.15) and `webCalmIsDimmer` (dark, calm → mean ink luminance < non-calm's).
- [ ] **Step 5: Owner review.** Send the owner the side-by-side stills and a side-by-side recording; continue only on their OK.
- [ ] **Step 6: Commit** "docs: Web parity references".

### Task 12: Energy

**Files:**
- Create: `Tools/energy.sh`
- Modify: `Sources/OceanTool/main.swift` (`bench --habitat web`: simulation ms per simulated second, paint ms per frame at 1800×1169), `docs/DEVELOPING.md` (Energy table gains Web rows)

- [ ] **Step 1: Write `Tools/energy.sh <habitat> <fps> [seconds]`**: sets the habitat and fps in the app's settings, launches `build/ASCII Animals.app`, samples `top -l` once a second for the app and WindowServer (after 10 s settling), prints mean CPU% and the app's memory, restores the previous settings. Baseline WindowServer is measured with the app quit.
- [ ] **Step 2: Measure** Ocean and Web at 30 and 15 fps. Expected: Ocean within noise of the DEVELOPING table; Web ≤ Ocean on every line.
- [ ] **Step 3: If Web is over budget**, apply the ladder from Global Constraints one rung at a time, re-running Task 11's comparison after each; never fewer webs or simpler motion.
- [ ] **Step 4: Commit** "perf: Web within the Ocean's budget" with the numbers in DEVELOPING.

### Task 13: Choosing a habitat (menu, Settings, welcome, stills)

**Files:**
- Modify: `Sources/ASCIIAnimals/StatusMenu.swift` (a "Habitat" section near the top: Ocean, Web, radio; the Sharks submenu shows only on Ocean; a "Spiders" submenu on Web with the roster presets, Flies, Jumping Spider), `SettingsView.swift` (Habitat picker at the top; the shark line-up section on Ocean only; a Web section with roster, flies and jumping spider; preview follows the habitat), `OnboardingController.swift` (the look/preset beat gains an Ocean/Web choice, Ocean selected; the live scene follows it), `OceanStatus.swift` and `Diagnostics.swift` (include the habitat), `SystemWallpaper.swift` (the lock-screen still uses the habitat; already true through `StillRenderer` after Task 6 — verify)
- Test: `Sources/OceanChecks/SettingsChecks.swift`, snapshots via `--snapshot-settings` / `--snapshot-onboarding`

- [ ] **Step 1: Write failing check** `diagnosticsNameTheHabitat` (`DiagnosticFacts.mode` text for a Web session contains "Web").
- [ ] **Step 2: Implement the UI.** Copy: menu header "Habitat", items "Ocean" and "Web"; Settings picker "Habitat"; Web section rows "Spiders", "Flies", "Jumping spider". The display toggle becomes "One habitat across displays" (setting key `sharedOcean` unchanged), with the subtitle "Animals move from one display to the next. Off, each display has its own."
- [ ] **Step 3: Verify.** Checks pass; settings and onboarding snapshots for both habitats look right; switching in the menu dissolves; switching while paused shows the new still at once; the lock-screen still matches the habitat.
- [ ] **Step 4: Commit** "feat: choose a habitat".

### Task 14: Words and credits

**Files:** Modify `README.md` (ASCII Animals: habitats, the gestures, new links `zegrt/ascii-animals`, Thanks credits ascii-sharks and ascii-spiders), `docs/DEVELOPING.md`, `Sources/ASCIIAnimals/AboutWindow.swift` (credits both originals), `LICENSE` (add the ascii-spiders MIT copyright notice beside the ascii-sharks one), `CHANGELOG.md` (`## 3.0`: new app and name, Web habitat, how ASCII Sharks hands over), `docs/media/` (Web stills and a hero GIF from `OceanTool frames --habitat web`).

- [ ] **Step 1: Write and render.** README stays as short and plain as the current one.
- [ ] **Step 2: Verify** every README link resolves once the repo is public (Task 15 Step 4) and `--snapshot-about` shows both credits.
- [ ] **Step 3: Commit** "docs: ASCII Animals".

### Task 15: Release 3.0

- [ ] **Step 1: Ten-minute watch.** Record ten minutes of Web at 30 fps and at 15 fps; check each "alive" principle against the original's behaviour; owner signs off on the recording.
- [ ] **Step 2: Version.** `Info.plist` `CFBundleShortVersionString` 3.0, `CFBundleVersion` 7; CHANGELOG section `## 3.0` exists.
- [ ] **Step 3: Private-string scan** (Global Constraints) prints nothing; push `main` to `origin`.
- [ ] **Step 4: Make the repo public** (`gh repo edit zegrt/ascii-animals --visibility public --accept-visibility-change-consequences`), tag `v3.0`, push the tag, watch the Release workflow; the release has `ASCII-Animals.dmg` and `ASCII-Animals.zip` with digests.
- [ ] **Step 5: Install on the owner's Mac from the DMG.** The hand-over runs: Sharks quits, settings carry over, Ocean shows, the Trash offer appears.
- [ ] **Step 6: Self-update smoke test.** A local build labelled 2.9 in `~/Applications` updates itself to the published 3.0 (as done for 2.3).
- [ ] **Step 7: Freeze the old repo.** On a branch from `sharks/main`, add under the README's title: "**ASCII Sharks continues as [ASCII Animals](https://github.com/zegrt/ascii-animals)** — sharks, spiders and more." Push to `sharks` `main`. No tag, no release.
