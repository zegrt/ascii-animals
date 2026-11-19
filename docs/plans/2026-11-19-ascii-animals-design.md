# ASCII Animals — Design

Status: draft for approval · 2026-11-19

## Intent

ASCII Sharks grows into **ASCII Animals**: a live macOS wallpaper with several **habitats**, one at a time, each with animals that feel as alive as the sharks do today. The bar comes from the owner, plainly: **a new habitat must not be worse than the existing sharks and spiders**, in how the animals move and behave, and **must not cost more** than the sharks do.

The first release adds a port of **[ascii-spiders](https://github.com/stackedlol/ascii-spiders)** (same author as ascii-sharks, MIT, drawn deliberately in the same grid/font/palette). The next adds **Meadow**, our own butterflies.

## Goals

- Habitats, chosen one at a time from the menu and Settings: **Ocean** (today's sharks, unchanged), **Web** (the spiders port), **Meadow** (butterflies, ours).
- Every habitat shares: the grid, Geist Mono, Dark/Light/Calm themes, the power policy (pause when covered/locked/asleep, 15 fps economy, still in Low Power Mode), multiple displays, the menu-bar status, the lock-screen still, self-updating.
- One gesture vocabulary across habitats: **move** disturbs the material, **click** offers something, **holding still** invites trust (see table below).
- **ASCII Animals is a new app in a new repo** (`zegrt/ascii-animals`, started from this repo's history). ASCII Sharks stays frozen at 2.3 in `zegrt/ascii-sharks-wallpaper`. People moving over keep their settings, and the two apps never run at once.

## Non-goals (this project)

- Habitats sharing the desktop at the same time.
- Anything that builds up across launches (webs, colonies, life cycles saved between runs). Each launch is a fresh habitat; life cycles happen within minutes while it runs.
- Using window edges as terrain (webs anchored to windows, flowers on window tops). Habitats frame themselves on the screen edges. Later list.
- Switching habitat by time of day, and anything in a habitat that follows the real clock. Later list (including Meadow moths at night).
- More habitats (ants in sand, fireflies and bats, pond, starling murmuration). Later list.
- A new app icon. The shark icon stays.

## Anti-goals (failure even if it works)

- A habitat that looks like a loop, or animals that move like sprites on rails.
- A port that drifts from the original's behaviour or look.
- Any regression in the Ocean: look, behaviour, or energy.
- A busy desktop: big moments stay rare; it's ambient.
- Spiders shown to someone who didn't choose them.

## The quality bar

### What "alive" means (every habitat, judged on these)

1. **Wants something.** Each creature is always after something (food, home, rest), readable from its motion, including hesitation before a lunge.
2. **Has weight.** Nothing changes instantly: sprung headings, eased speeds, bodies that swing into turns.
3. **Touches the world.** Motion comes from contact: feet grip silk, tails push water, wings beat air.
4. **Senses, doesn't know.** Creatures react to signals in the material (a tug through silk, a ripple, a breeze), not to perfect knowledge.
5. **Rests.** Breathing, idling, basking. Stillness gives motion meaning.
6. **Leaves traces** that fade: wakes, wrapped flies, pollen.
7. **No two alike, nothing loops.** Size, timing and temperament vary.

**Ten-minute watch:** before a habitat ships, watch it for ten minutes at 30 fps and at 15 fps. Every principle above must be visible; nothing may look repeated. The owner signs off on a recording.

### Fidelity

- **Web** must look and behave the same as the original, side by side. The bar is the owner's "not worse", not cell-for-cell identity *(builder's call)*: port structure, states, timings, constants, gait, springs and glyph choices faithfully, as idiomatic Swift with a seeded RNG. Verify like the sharks port (`docs/reference/`): render the original headless from a scratch copy patched to use a seeded RNG (the original calls `Math.random()` directly, so it has no seed; the patched copy is a reference tool, not committed to the checks) and ours at the same size, compare stills side by side, and record both running side by side for the owner. Differences are bugs unless forced by the platform and written down. Where a principle in "alive" isn't met by the original, Web ships as the original; improvements go on the later list.
- **Meadow** has no original, so it's held against Ocean and Web: side-by-side recordings for the owner, and the ten-minute watch.

### Performance

Measured the way the README's Energy table was (M5 Pro MacBook Pro, Activity Monitor/`top` averages over a minute, one display):

| | Budget per habitat |
|---|---|
| 30 fps on AC | app CPU ≤ Ocean's (~4–5.5%); WindowServer cost no higher than Ocean's |
| 15 fps on battery | app CPU ≤ Ocean's (~2.5%) |
| Memory | ≤ ~100 MB |
| Ocean itself | unchanged within noise, before vs after the refactor |

**Fidelity and the budget are both fixed; approach A is what gives** *(builder's call, from the owner's two bars)*. The original's costs are CPU-heavy: each web is a Verlet cloth stepped at 60 Hz (up to ~11 webs), every thread is resampled into cells every frame, and spider bodies are supersampled per cell. Measure early (end of step 3's first slice). If over budget, in order: cache settled silk and repaint only ringing/changed threads; step webs nobody is touching at a lower rate only if it's visually identical; move silk rasterisation and/or body supersampling to the GPU. Never fewer webs or simpler motion than the original.

`OceanTool bench` gains a per-habitat simulation benchmark, and the numbers go in the README/DEVELOPING tables.

## Gestures

| | Move (disturb) | Click (offer) | Hold still (trust) |
|---|---|---|---|
| Ocean | wake through the fish (today) | splash (today) | *later:* curious fish gather near the cursor |
| Web | plucks the silk; it rings and the spider turns toward it (original) | drops a fly (original) | the jumping spider watches the cursor, edges closer, and pounces if it stays still (original, `jumper.ts`) |
| Meadow | breeze sways the flowers, butterflies veer | a flower blooms where you click | a butterfly lands on the cursor; move and it flutters off |

Ocean's behaviour doesn't change in this project. Web's column is all the original's; Web adds nothing beyond it in this project.

## Approaches considered (for drawing habitats)

Today the engine is one World (Swift, fixed 60 Hz) packed by `FramePacker` into a GPU pipeline whose **cells** pass classifies each cell analytically as shark part or fish, then **compose** draws glyphs from the atlas. Silk lines and jointed legs don't fit that classification.

- **A. Shared cell canvas — chosen.** New habitats paint a CPU grid of cells themselves (glyph, brightness, colour/accent, flags), uploaded as a texture; one generic GPU compose pass (grid, glyphs, theme) draws it. Ocean keeps its own GPU path behind the same habitat interface. Chosen because the spiders' renderer already works exactly this way (samples silk into cells, picks a glyph per cell, supersampled bodies with carved glyphs), so the port stays faithful; each future animal is behaviour work, not shader work. Cost: CPU per-cell painting (~80k cells on a large display at 30 fps), budgeted above.
- **B. Custom GPU passes per habitat.** Lightest at runtime, but silk and legs are awkward per-cell shaders, every animal becomes a graphics project, and a faithful port gets much harder.
- **C. Run the original TypeScript in a web view.** Nearly free to port, but measured at ~14% CPU / 355 MB vs ~4% / 84 MB native, and a two-language app. Rejected.

The owner handed the "how" over; A is the builder's-call recommendation they didn't object to.

## Design

### Shape of a habitat

Every habitat is three parts:
- **Material** — a field the pointer writes into and creatures read from: water (Ocean's wake), silk (thread tension/ringing), air (Meadow's breeze).
- **Creatures** — the simulation, stepped at a fixed 60 Hz (both originals use 60 Hz with at most 4 catch-up steps, same as `OceanClock`).
- **Painter** — turns material + creatures into cells.

A habitat implements a small interface (names are the builder's): lay out for a set of screen rects (`Habitat`, the existing multi-display geometry type — consider renaming it to avoid the clash with the product term), step, pointer moved/down/still, paint or encode a viewport, render a still, and its own settings. `OceanDirector`/`OceanScene` become habitat-agnostic: they own screens, clocks, power policy and pointer routing, and hold whichever habitat is selected.

Shared motion kit (Swift, in OceanKit Domain, checked): springs (sprung heading), eased speed toward a target with braking into corners, boids, planted-foot legged gait with alternating step groups and two-bone IK, wing-beat oscillator, value noise. Ported code should use the kit only where it reproduces the original exactly; parity beats reuse.

### Rendering

- A **cell canvas** per viewport: cols × rows of {glyph index, intensity, colour index/accent, flags}. Habitats paint it on the CPU each frame; it's uploaded to a texture (ring of 3, like the fish grid today) and drawn by a generic **compose** pass sharing the atlas, grid lines and theme with Ocean.
- The glyph atlas grows to cover every glyph the habitats use (spider silk `- _ ¯ / \ | *`, blocks, carved body glyphs, fly glyphs `x + @ ·`, butterfly wing glyphs).
- Ocean's three passes stay as they are.
- Stills (lock-screen matching, README media, checks) render through the same habitat interface.

### Multiple displays

"One ocean across displays" becomes **"One habitat across displays"** (same setting, `sharedOcean`, kept as the key). Web: webs are placed within a single screen rect (never across a gap); flies and the jumping spider may cross between touching screens. Meadow: flowers along the bottom edge of each screen; butterflies cross between touching screens, monarchs preferring to. With the setting off, each display gets its own habitat instance.

### Web (port of ascii-spiders)

Port of `src/` (world, web, weaver, spider, jumper, flies, renderer; ~3,200 lines of TypeScript) to Swift:
- Cast: European garden spider, wasp spider, golden orb weaver (orb weavers), the jumping spider, flies. Webs of mixed sizes placed by clearance, the first in the bottom-left; empty webs old and faint.
- Target configuration: the original's **demo page** (`/`: the default cast, no clear centre) *(builder's call)*. Web-page specifics are dropped: no clear centre (a desktop has no headline) and no nav-bar gap (the wallpaper sits below the menu bar already). Parity stills compare against this configuration.
- Weaver life: build → idle (head-down at the hub, turns toward tugs) → hunt → wrap → carry → eat; eats an old/torn web and rebuilds nearby.
- Pointer: moving through a web plucks it (silk rings, brightens); click drops a fly that sticks to silk.
- Settings for Web: which orb weavers (roster), flies on/off, jumping spider on/off. Keep it to what the original exposes and the owner would plausibly want; don't invent.
- Credits: README Thanks and the About window credit ascii-spiders and its author the same way as ascii-sharks; LICENSE keeps its MIT notice.

### Meadow (ours)

Material is a meadow of flowers along the bottom of each screen plus scattered flowers; air carries a breeze field the pointer writes into.
- **Always daytime** *(owner's decision)*: flowers stay open and butterflies fly at any hour, so the Meadow is alive whenever it's seen. Moths at night are on the later list.
- **Flowers** sway with the breeze; a click blooms one.
- **Butterflies** — monarch, blue morpho, swallowtail, cabbage white. Flight is erratic and fluttery (evasive zig-zag, the way real butterflies fly), wings drawn opening/closing in ASCII with a beat that drives lift; they visit flowers to sip, bask with wings flat, veer from gusts.
- **Life cycle within minutes:** a caterpillar munches along a leaf, hangs a chrysalis, and a butterfly emerges a few minutes later. Not saved between launches.
- **Landing:** hold the pointer still for a few seconds and a butterfly may land on it; any movement and it takes off.
- **Colour** *(owner's decision)*: butterflies in their real colours, toned down to sit in the same quiet palette as the others (muted monarch orange, muted morpho blue, swallowtail yellow-and-black, cabbage-white off-white), so the species read at a glance. Light theme gets matching muted ink colours. Pollen gold is the habitat accent (pointer breeze, nectar sparkle).
- Builder researches real butterfly flight and behaviour first (wing-beat rates, flight paths, basking, nectaring) and writes the findings into the Meadow plan; the "alive" principles above are the acceptance test.

### Product

- **Name:** ASCII Animals everywhere (`CFBundleName`/`CFBundleDisplayName`, the `.app` file, the DMG and zip, menus, windows, About, README, onboarding, log folder). **New bundle ID `local.ascii-animals.wallpaper`** *(owner's decision)*. Company naming as today (XERO WORKS). Version **3.0**, carrying on from Sharks' numbering.
- **New repo `zegrt/ascii-animals`; the old one is frozen at 2.3** *(owner's decision)*. The new repo starts from this repo's full history. `AppInfo` URLs, `SelfUpdater.repoPath`, the README, badges and the Release workflow point at the new repo from the first release. The old repo gets one README line pointing to ASCII Animals and no new release; installed 2.3 apps keep working and stop finding updates.
- **Hand-over from ASCII Sharks** (first launch of ASCII Animals, and any launch while Sharks is still around): if ASCII Sharks (`local.ascii-sharks.wallpaper`) is running, ask it to quit (SIGTERM, as `Tools/install.sh` does), which puts the user's own wallpaper back; then copy its settings (`settings.v2` in its defaults domain) into ASCII Animals once, keeping the habitat on Ocean; if it was set to open at login, turn Animals' login item on. Then offer, once, to move ASCII Sharks to the Trash (it can't remove its own login item from here; say so if it was on). Nothing happens when Sharks isn't installed.
- **Menu:** a Habitat section (Ocean, Web, Meadow) near the top; per-habitat items (shark line-up / spider roster / butterfly species) show only for the current habitat. The menu-bar glyph stays the fish.
- **Settings:** a Habitat picker at the top; the live preview shows the current habitat; sections that belong to one habitat show only there.
- **Welcome tour:** new users pick their habitat; Web is never preselected. People coming from ASCII Sharks skip the tour and stay on Ocean.
- **Switching:** a short dissolve, glyphs scattering and re-forming, rather than a cut.
- **Lock-screen still, power policy, Calm, Light/Dark, Report a Problem diagnostics:** work for every habitat; diagnostics include the habitat.

### Settings model

`Settings` gains `habitat` (default `ocean`) and per-habitat fields (Web roster, flies, jumper; Meadow species, density). Settings imported from ASCII Sharks decode with today's defaults for the new fields; Ocean fields unchanged.

## Order of work

1. **Habitat host refactor** — no visible change. Ocean renders pixel-identical stills for the same seed (check), all existing checks pass, energy unchanged.
2. **Cell canvas + generic compose** — with a trivial test habitat in checks.
3. **Web port** — parity checks against the original, side-by-side recording for the owner, energy within budget.
4. **Product** — habitat menu/settings/welcome, switching dissolve, the new identity (name, bundle ID, repo, URLs), the hand-over from ASCII Sharks, README/About/credits, the old repo's pointer line. Release **3.0** (Ocean + Web) from the new repo.
5. **Meadow** — research, prototype as recorded frames (`OceanTool frames`) for owner review before wiring into the app, ten-minute watch, energy within budget. Release **3.1**.

## Left to the builder

Type and file names; the habitat interface's exact shape; the cell format; how the dissolve looks; Web settings beyond the roster/flies/jumper; Meadow's numbers (counts, timings, sizes) within the principles; whether the updater renames the app bundle; how the per-habitat benchmark is structured.
