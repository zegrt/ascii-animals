# WindowServer cost of an animated desktop-level CAMetalLayer: research notes

Date: 2026-11-27. Read-only web research; nothing was run.
Labels: **[D]** documented by Apple; **[O]** observed or measured by others (bug trackers, open-source code, forums, vendor posts);
**[I]** my inference. Apple documents almost nothing about WindowServer internals, so much of what follows is [O] or [I].

## 0. What the owner's numbers already say (inference from the brief)

- WindowServer (WS) adds about 10 points at 15 fps and about 20 points at 30 fps over its 7–9% idle. That is close to linear in
  frames per second. Two displays at about 30 and 33.3 fps make about 63 composites a second, so roughly **3 ms of WS CPU per
  display update**. [I]
- Linear scaling points to a cost paid **per composite**, not a fixed cost or a cost driven by cadence. Fewer composites, or
  cheaper ones (less damaged area, fewer layers touched), are the only levers. Nothing I found suggests that a more regular
  cadence is cheaper beyond being fewer frames. [I]
- Activity Monitor's WS CPU% does not include GPU time. The GPU side of compositing (bandwidth) is a separate power cost, and
  `powermetrics` shows it. [I]

## 1. How WS per-frame cost scales

**Unit of invalidation is the whole layer.**
- Mozilla (Markus Stange): "whenever a CALayer is touched, the window server will recomposite the entire layer to the screen.
  There is no API to mark parts of a layer as damaged." [O] https://bugzilla.mozilla.org/show_bug.cgi?id=1491456
- I found no public dirty-rect or damage API for CAMetalLayer or for `MTLDrawable.present`. The CAMetalLayer docs describe only
  whole-drawable replacement. [D/O] https://developer.apple.com/documentation/quartzcore/cametallayer
- GTK's macOS backend says the same about GL: "the whole buffer is flipped even if you only submitted a small change using a
  scissor rect". [O] (gdk/macos sources, gitlab.gnome.org/GNOME/gtk)
- **So yes: presenting a full-screen drawable makes WS recomposite the whole screen area of that layer every frame**, even when
  1% of cells changed. [O]

**Damaged area matters.**
- Firefox 70 moved from one full-window GL surface to tiled IOSurface CALayers, so only the tiles that changed are
  recomposited. Quartz Debug "Flash screen updates" showed WS's repaint area shrinking. Measured on a 2013 MBP with Intel
  graphics, idle subtracted: spinning square 12.8 W → 2.9 W; Google Docs caret 7.4 W → 1.6 W; complex loading animation
  19.4 W → 1.8 W; scrolling only 16.4 W → 9.4 W. [O]
  https://mozillagfx.wordpress.com/2019/10/22/dramatically-reduced-power-usage-in-firefox-70-on-macos-with-core-animation/
- Same post: compositing one layer reads the source, reads the destination and writes the destination, about 3× the
  screen's bytes. That is about 3 ms per screenful on that machine's 28 GB/s, and the GPU stays at full clock while
  bandwidth-bound. [O] Apple silicon has much more bandwidth, so the GPU part shrinks there, but the WS CPU part does not
  have to. [I]
- Codex desktop app (2026): a tiny "thinking" spinner kept the GPU about 70% active (about 2.3 W). powermetrics charged most
  of it to WindowServer, and it dropped to nearly zero when the window was covered or minimised. [O]
  https://community.openai.com/t/very-high-gpu-usage-when-codex-is-active-window-report-md-and-reproduction-scripts-included/1385270
  A small animation can therefore cost a full-surface composite when it invalidates a big surface. [I]

**Number of layers costs WS CPU.**
- Firefox tile-size tuning while scrolling: 1024×256 tiles → WS about 50% CPU; 1024×1024 tiles → about 37% (Chrome about 30%).
  More, smaller layers cost more WS CPU. [O] https://bugzilla.mozilla.org/show_bug.cgi?id=1491456
- Inference: WS CPU per composite grows with the number of layers in, or intersecting, the damaged region. That includes
  **other apps' layers above ours**: the Finder desktop-icons window, desktop widgets, the menu bar and the Dock. A full-screen
  damage on a desktop-level window makes WS rebuild the whole display's scene. [I]
- **Translucent material above the wallpaper may be a large hidden cost.** The menu bar, the Dock, Sonoma+ desktop widgets and
  Tahoe Liquid Glass sample and blur whatever is behind them. When the pixels underneath change, WS must recompute those
  effects every frame. I found no measurement specific to wallpapers. Tips sites say "Reduce transparency" lowers WS load;
  one vendor claims 30–50% on Liquid Glass-heavy UIs, unverified. [O, weak]
  https://osxdaily.com/2026/04/22/why-windowserver-uses-high-cpu-memory-macos-fix/
  Cheap test: measure WS at 30 fps with Accessibility › Display › Reduce transparency on and off, and with the Dock hidden.
  If the delta is large, keeping the top strip (menu-bar band) and the Dock band static would help. [I]

**Opaque windows stacked above.**
- WS culls work for content hidden behind opaque windows. In the Codex report, usage collapsed when the window was covered. [O]
- Mozilla: transparent layers force blending "for all pixels of the window" on every composite, so mark layers opaque.
  Firefox's tiling also split opaque and transparent tiles. [O] https://bugzilla.mozilla.org/show_bug.cgi?id=1429522
- So an opaque window covering most of the desktop probably cuts the GPU fill cost of our updates. WS still receives every
  commit, though, and still does per-transaction and per-layer bookkeeping, so the CPU part likely does not reach zero.
  Unknown how much; measure it. [I]

**Window level.** I found nothing that says desktop level is cheaper or dearer than a normal level. The difference that
matters is what sits above it (icons, widgets, blur), and the fact that desktop level can never be full screen, so it never
gets the direct path described in section 3. [I]

**Drawable size.** It sets GPU bandwidth for us and for WS (about 34 MB per frame at 3600×2338 BGRA8, about 15 MB at
2560×1440). Whether WS CPU scales with pixel count is not known. Cheap test: run the same 30 fps loop in a 200×200 pt
desktop-level window. If WS CPU stays near +20, the cost is per-composite overhead (layers, effects) and not area. [I]

## 2. Presenting only changed regions

Partial updates on macOS mean **many CALayers, each with its own contents**. Only layers whose contents change are recomposited. [O]

**Pattern A: IOSurface tiles (Firefox, Chromium, GTK).**
- Layer `contents` = an IOSurface. Apple's `CALayer.contents` docs name only CGImage and NSImage. IOSurface contents are
  undocumented but used by every major browser. [D for the gap; O for usage] https://developer.apple.com/documentation/quartzcore/calayer/contents
- Updating an IOSurface in place: setting the same IOSurface object again does not refresh the screen. Chromium, GTK and
  Emacs call the **private** `-[CALayer setContentsChanged]` when the surface object is unchanged, and otherwise call
  `setContents:` with a different surface. [O] Chromium `ui/accelerated_widget_mac/display_ca_layer_tree.mm`;
  GTK `gdk/macos/GdkMacosTile.c`. App Store risk is small but real, because it is a private selector. [I]
- Writing into a surface WS is still reading shows half-drawn frames. Firefox abandoned in-place `setContentsChanged` for
  swap chains of IOSurfaces and checks `IOSurfaceIsInUse` before reuse. [O] (bug 1491456; NativeLayerCA.h)
- GTK's design is the closest match for us. It renders the whole window into one IOSurface and splits it into tile layers
  (max 128 px, with 512 px edge tiles) that show sub-rects through `contentsRect`. On each swap it updates **only the tiles
  that intersect the damage region**, using `setContentsChanged` or `setContents`. [O] gdk/macos/GdkMacosLayer.c
- Chromium partial swap: a small extra CALayer over the damage rect, backed by the existing IOSurface. "The partial damage
  layer can be created, removed, or resized with basically no cost". If the union of damage grows "too big", it falls back
  to a full swap. [O] https://codereview.chromium.org/1271123002/
- Metal can render straight into an IOSurface (`MTLDevice.makeTexture(descriptor:iosurface:plane:)`). No copy is needed. [I, standard API]

**Pattern B: several CAMetalLayers.** It works, but each layer has its own drawable pool: 2–3 full-size textures per layer
(`maximumDrawableCount` accepts only 2 or 3 [D]). Presents are asynchronous to Core Animation transactions unless
`presentsWithTransaction` is set [D], so several layers can tear against each other within one frame. Fine for a few big
regions; poor for dozens of tiles. [I]

**Pattern C: static base plus moving sprite layers.** Butterflies become small layers whose `position` changes, or whose
contents are small IOSurfaces. A moved layer damages old rect ∪ new rect only. Core Animation implicit or explicit
animations are interpolated by the render server without app commits. On macOS that server runs inside WS, so the
composites still happen. [I]

**`presentsWithTransaction`.** Documented as synchronising Metal content with the current CA transaction. It needs
`commit` → `waitUntilScheduled` → `drawable.present()`, and must not use `commandBuffer.present`. [D]
https://developer.apple.com/documentation/quartzcore/cametallayer/presentswithtransaction
It is a sync tool, not a damage hint. Zed turned it on globally, saw problems, and now uses it only at startup and during
resize; Warp does the same for live resize. [O] https://zed.dev/blog/120fps

**`setNeedsDisplayInRect`** applies only to CPU-drawn layer backing stores, not to CAMetalLayer. Developers report AppKit
redrawing whole views regardless of the rect. [O] https://developer.apple.com/forums/thread/663256

**What WS skips:** layers with no contents change in the transaction, and screen regions where nothing changed (Quartz Debug
flash). **Per-layer cost:** real, but only one data point (the Firefox tile sizes). **Per-transaction cost:** no published
number. [O/I]

**Fit to our content (inference).** Meadow changes 1–1.5% of ground cells per frame, scattered across the screen. At about
26×38 px per cell on the 2× display that is about 8k cells, so roughly 100+ changed cells per frame, which touch most
512-px tiles every frame. **Tiling only pays if changes cluster in space or time.** Options: update ground twinkles in
rotating bands or tiles (each tile at a lower rate, phase-offset), and keep only the butterflies (small damage) at full
rate. Ocean, with fish everywhere, damages nearly the whole screen, so it gains little from tiling. Its levers are frame
rate, occlusion pausing, and whatever is found above the wallpaper (blur). [I]

## 3. Hardware overlay or direct-to-display

- Apple: "When a Metal drawable is direct-to-display, the hardware composites it directly to the display at a very low
  performance cost". Requires "full-screen mode, displaying an opaque CAMetalLayer layer and RGB content, and run on a Mac
  with Apple silicon"; "other edge case conditions" may apply. [D]
  https://developer.apple.com/documentation/metal/managing-your-game-window-for-metal-in-macos
- The Metal HUD shows "direct or composited". Composited mode can add buffering "due to system UI elements or your own
  additional layers overlapping the screen". [D] https://developer.apple.com/videos/play/tech-talks/110339
- Video: Chromium's "fullscreen low power" mode uses a single AVSampleBufferDisplayLayer over black in a fullscreen window
  so WS can run it "in detached mode". It only works when the frame is one video over black. [O]
  https://codereview.chromium.org/1920723002
- Display hardware: reverse-engineered DCP drivers expose only 2–3 planes (OpenBSD/Asahi `DCP_MAX_PLANES 2`,
  `MAX_PLANES 3` for one firmware). [O] https://src.rcs.uwaterloo.ca/xref/openbsd-src/sys/dev/pci/drm/apple/dcp-internal.h
- **A desktop-level wallpaper window cannot get this.** It is never the full-screen window, and the icons, menu bar, Dock and
  app windows are composited above it. Nothing I found suggests otherwise. [I, strong]
- **How video wallpaper apps stay cheap.** They do not avoid compositing. They (a) decode on the media engine so the app
  process shows about 0–2% CPU, and (b) **pause** under full-screen apps, when covered, on battery, at display sleep, and
  under load. [O]
  - Backdrop (Cindori): "less than 0.3% CPU" (app process only, vendor claim); pauses for full-screen apps and when the
    desktop isn't visible. https://cindori.com/how-to/live-wallpapers-mac-performance
  - Wallper: app process 1.46% average CPU (one core = 100%) on an M4 Mac mini with a 5K2K display. WindowServer 35.7% while
    playing vs 42.2% after quitting, which is noise, so no WS cost was isolated. It pauses for full screen, on battery,
    above 80% CPU and at display sleep. [O, vendor]
    https://www.wallper.app/blog/2026/07/live-wallpaper-battery-test-mac
  - Phosphene: does not use a window at all. Its extension runs **inside Apple's WallpaperAgent** through the private
    `WallpaperExtensionKit` and draws with AVSampleBufferDisplayLayer into a remote CAContext. That is the same pipeline as
    Apple's Aerials. Its policy is full / reduced / minimal / paused, driven by thermal state, battery and occlusion. [O]
    https://github.com/kageroumado/phosphene (REFERENCE.md)
  - Apple's own Aerials (WallpaperVideoExtension): many user reports of 20–100% CPU and about 1 GB RAM on Sonoma, so it is no
    proof of a cheap path. On macOS 26, Desktop Motion can be set to Still. [O]
    https://discussions.apple.com/thread/255180158
- **No source gives a reliable WindowServer power figure for any live wallpaper.** The numbers above are app-process CPU or
  noisy vendor tests. [O]

## 4. Pacing

- `CADisplayLink.preferredFrameRateRange` (macOS 14+): "The system typically provides a consistent frame rate by choosing one
  that's a factor of the display's maximum refresh rate". [D]
  https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange
  - On a 100 Hz panel the factors are 100, 50, 33.3, **25**, 20. Asking for 30 gives 33.3, which matches what you see. **30
    cannot be even on 100 Hz**: frames could only alternate 3- and 4-refresh holds (judder). **Asking for 25 should give
    exactly 25 (every 4th refresh).** [D rule; I application]
  - On a 120 Hz or ProMotion built-in panel, factors include 30 and **24**, but not 25. A range of about min 24 / max 25 /
    preferred 25 should land on 25 at 100 Hz and 24 at 120 Hz. Going from 33.3 to 25 on the external cuts its composites by
    25%. [I; verify with a frame counter]
- `CAMetalDisplayLink` (macOS 14+) adds `preferredFrameLatency` and is meant for "more control over the timing window". Apple
  DTS: "for frame pacing in particular we strongly advise using CAMetalDisplayLink over CADisplayLink". [D/O]
  https://developer.apple.com/documentation/quartzcore/cametaldisplaylink ; https://developer.apple.com/forums/thread/763426
  Developers report quirks with external monitors and in full screen. [O] It does not lower WS cost by itself. [I]
- `presentDrawable(afterMinimumDuration:)` gives a hard minimum frame interval. Apple: "your app will use less CPU and GPU
  time". On fixed-rate displays the old advice is to target a factor of the refresh rate. [D]
  https://developer.apple.com/videos/play/wwdc2021/10147/
- Timers (`DispatchSourceTimer`) are not vsync-aligned. On fixed panels they give uneven holds and gain nothing. [I]
- Use one link per display (NSScreen/NSView `displayLink`, macOS 14). Shared or global vsync sources cause wrong rates on
  mixed-refresh setups (GTK and Firefox bugs). [O] https://gitlab.gnome.org/GNOME/gtk/-/issues/4732
- **More-than-linear savings from cadence:** no evidence. Your 15/30 fps data is linear. Tahoe's Low Power Mode can cap
  full-screen vsync apps at 30 fps (forum report), so the system itself treats 30 as a power tier. [O]
  https://developer.apple.com/forums/thread/795447
- ProMotion panels can lower their own refresh rate when content updates slowly (Zed notes ProMotion "modulates the
  display's refresh rate to save battery"). That saves panel power, not WS power. [O]

## 5. CAMetalLayer settings that may change compositor cost

| Setting | What is known | Verdict |
|---|---|---|
| `isOpaque = true` | Required for direct-to-display [D]; avoids blending the whole surface [O, Mozilla] | Keep (already set) |
| `framebufferOnly = true` | "Core Animation can then optimize the texture for display purposes" [D] | Keep (already set) |
| `maximumDrawableCount` | Only 2 or 3 accepted, default 3 [D]. 2 saves memory; at 2, WS sometimes holds drawables longer and blocks `nextDrawable` [O, forum 711033] | Little WS effect; 2 is fine at 30 fps [I] |
| `displaySyncEnabled` | `false` allows tearing [D] | No reason to touch; no known power benefit [I] |
| `allowsNextDrawableTimeout` | Only governs `nextDrawable` blocking [D] | No compositor effect [I] |
| `colorspace` | nil = "rendered content isn't color-matched"; when set, CA "performs any necessary color space transformations when compositing" [D] | The conversion is probably folded into the composite shader, so the saving is likely tiny. Setting nil changes colours on P3 panels, a fidelity cost [I] |
| `pixelFormat` | BGRA8 and BGR10A2 are both 32 bpp; RGBA16Float doubles bandwidth [I]. All RGB formats can go direct [D] | Stay on 8-bit; avoid float16 |
| `wantsExtendedDynamicRangeContent` | EDR implies float formats and tone mapping [D, WWDC21 10161] | Keep off; likely raises WS work [I] |
| Lossless compression | Metal compresses private textures automatically on Apple GPUs [D] https://developer.apple.com/documentation/metal/optimizing-texture-data ; Asahi work mentions scanout of "compressed interchange buffers" [O] | Nothing to toggle for drawables; unknown whether drawables are compressed [I] |
| Lower `drawableSize` / `contentsScale` (e.g. 1× on the 2× panel) | Apple: scaling is handled efficiently, at least on the direct path [D] | Cuts bandwidth 4× but softens glyphs. Fails the "no fidelity loss" rule for text-like art [I] |

None of these is documented to give a large WS CPU cut. Damage area, layer count and composite count dominate. [I]

## 6. Occlusion

- Apple's energy guide: use `windowDidChangeOcclusionState` / `occlusionState.visible` to stop work when hidden. [D]
  https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/WorkWhenVisible.html
- **For desktop-level windows it is unreliable, per several wallpaper projects:** [O]
  - "NSWindow.occlusionState never reports desktop-level windows as covered by ordinary app windows". They switched to 1 Hz
    window-list polling, sampling each screen's visible frame on a 32×18 grid; bounds need no Screen Recording permission.
    https://github.com/Solvent-Duck/macOS-wallpaperengine/pull/1
  - wallnetic removed its observer because "desktop-level occlusionState flaps around windowed apps and caused hitching".
    https://github.com/fatihkan/wallnetic/issues/306
  - An e-dream screensaver PR reports the opposite: hosted views reported as occluded while visible.
    https://github.com/e-dream-ai/client/pull/840
  - It may still help as a coarse signal for another Space or a full-screen app; test that before relying on it. [I]
- **What others do:** Phosphene's `OcclusionMonitor` uses `CGWindowListCopyWindowInfo([.excludeDesktopElements,
  .optionOnScreenOnly])`. It counts only windows of `.regular` apps at layer 0 up to the pop-up-menu level, so Dock and
  Notification Center canvases are excluded. It rasterises a coarse grid per display, treats ≥95% of `visibleFrame` covered
  as occluded, and has a separate "fullscreen app owns this display" tier. It re-checks on app activate/deactivate and Space
  change, plus a 10 s poll (NSBackgroundActivityScheduler). [O]
  https://github.com/kageroumado/phosphene (Phosphene/OcclusionMonitor.swift)
  Wallps uses occlusionState plus a 2 s CGWindowList poll. [O] https://github.com/Srimi1/Wallps
- **Cost of CGWindowListCopyWindowInfo:** I found no benchmark. It is a WS round trip that builds CF dictionaries, so it gets
  slower with more windows [O, cocoa-dev anecdotes]. At 0.5–1 Hz plus event triggers it should be far below the cost of the
  frames it saves; measure it once with signposts. [I]
- **Partial occlusion:** the same window list gives the uncovered region. With tiled or sprite layers we could skip updating
  covered tiles. With one full-screen CAMetalLayer, WS probably already culls covered pixels (the Codex observation), but our
  app still renders and commits full frames. [I]
- Other cheap signals: `NSWorkspace.screensDidSleepNotification`, `activeSpaceDidChangeNotification`,
  `sessionDidResignActiveNotification`, the screen-lock distributed notification, thermal state, Low Power Mode, and battery
  (Wallper and Phosphene throttle on battery). [O/I]

## 7. Measurement aids (no dialogs needed)

- Quartz Debug (Additional Tools for Xcode), "Flash screen updates", shows WS's repaint area per frame. Mozilla used it to
  verify partial present. [O]
- Metal HUD (`MTL_HUD_ENABLED=1`) shows the present mode and frame intervals. [D]
- `powermetrics --samplers tasks,gpu_power` gives WS energy and GPU power separately from CPU%. It needs sudo, so the
  owner runs it, not an agent. [O, Firefox docs] https://firefox-source-docs.mozilla.org/performance/powermetrics.html
- Suggested A/B tests, in order of information per minute [I]:
  1. Tiny window vs full screen at 30 fps (is WS cost area-driven or per-composite?).
  2. Reduce transparency on/off, Dock hidden, no desktop widgets (does blur above the wallpaper drive the cost?).
  3. 25 fps vs 33.3 fps on the 100 Hz external.
  4. A maximised opaque app window over the wallpaper (WS cost while fully covered).
