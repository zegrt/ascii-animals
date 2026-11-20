# The family look: what makes Ocean and Web feel alive, and the Meadow's gaps

Research, 2026-11-20 (read-only, by a research agent for the manager). Reference for the Meadow sketch and its Swift port.


Read-only research. Sources:
- **Ocean:** `Sources/OceanKit/Domain/World.swift`, `FramePacker.swift`, `Species.swift`, `Theme.swift`, `Dissolve.swift`, `OceanClock.swift`, `Terrain.swift`, `PowerPolicy.swift`, `Render/Shaders.swift`, `GlyphAtlas.swift`.
- **Web:** `Sources/OceanKit/Web/*.swift`.
- **Meadow sketch:** `git show meadow-sketch:Tools/meadow-sketch/meadow.html`, cited below as `meadow.html:N`.
- **Plans:** `docs/plans/2026-11-19-ascii-animals-design.md`, `docs/plans/2026-11-19-meadow-3.1-plan.md`, `docs/plans/2026-11-20-meadow-top-down-direction.md`.

All paths are relative to the repo. Distances are in points (pt). "Cell" is the grid cell, 8–13 × 12–19 pt.

---

## 1. What "alive" means, and how each habitat meets it

The seven principles come from the design doc, section "What 'alive' means" (lines 37–47).

| # | Principle | Ocean | Web | Meadow sketch |
|---|---|---|---|---|
| 1 | **Wants something**, readable in its motion, including hesitation before a lunge | Hunger rises 0.03/s and drops 0.16 per fish eaten (World.swift:492, 622). Sharks hunt only when hunger > 0.3 (:525) and look for prey every 0.45 s (:519–522). As a shark closes in, its speed rises to cruise × (1.45 + 1.5 × closing) (:593) and it turns harder, up to 1.7 + closing rad/s (:586). When not hunting it patrols a lazy loop (:536–546). | Weaver life: build → idle → hunt → wrap → carry → eat the web → move (Weaver.swift:6–15). The jumper watches the target for 0.9 s (0.45 s for a fly), crouches for 0.26 s, then leaps (Jumper.swift:168–174, 127–132). Hunger 0.02/s gates fly stalking (:81, 97). | Waypoints, flower visits (35 %) and basking (meadow.html:953–968). An approach slows to forage speed inside 2.2 wingspans (:1041). There are **no drives** (hunger, warmth), **no hesitation** and no touch-and-go landings. |
| 2 | **Has weight**: nothing changes instantly | Heading is rate-limited by agility (World.swift:585–590). Speed eases at 1.1/s (:594). The spine allows at most 0.16 rad of bend per joint (:600–611). Fish turn smoothing runs at 8/s (:445). | Heading is a spring, k = 34–160 with damping 2√k × 0.92, capped at ±6 rad/s (Spider.swift:317–322). Speed eases at 4.5/s and brakes into corners (Weaver.swift:136–151). Strides ease in and out (Spider.swift:426–436). | Heading spring k = 30–60 with ζ 0.8–0.9 (meadow.html:1071–1074). Height uses a critically damped spring kz = 1.4 (:1096–1097). Bank eases at 6/s (:1119). **But several things snap**; see §3.2. |
| 3 | **Touches the world** | The tail's last 6 nodes stir the wake by 0.05 + speed × 0.0012 per step (Shaders.swift:83–95). Each fish adds 0.012 + 0.03 × alarm to its cell (FramePacker.swift:169). | Feet land on threads and jolt them by 0.1 × scale (Weaver.swift:83). Body weight loads each planted foot's thread by (B/90) × 0.05 px (:384–390). Struggling flies shake the silk (Flies.swift:168–173). | Taking off from a flower kicks up 7 pollen motes (meadow.html:976–979). Wings **do not move the air**, landing does not move the flower, and gusts do not touch landed butterflies. |
| 4 | **Senses, doesn't know** | Fish see a 360° field minus a blind spot behind them (cos < −0.6, World.swift:61, 336). Alarm passes fish to fish (:416–419). Sharks consider only prey in a forward cone (cos ≥ 0.2) within 0.9 L + 160 (:457–468). | A spider learns a fly's position only through tugs on the silk (Weaver.swift:108–113, Flies.swift:171). The jumper's interest has a range: 440 pt for the cursor, 480 pt for flies (Jumper.swift:79, 86). | `pickFlower` scans every flower on screen, discounting those beyond 0.6 × the diagonal (meadow.html:936–951). Flushing reads the pointer directly (:1626–1634). **Nothing is sensed through the air.** |
| 5 | **Rests** | Patrol is a slow cruise (30 + 0.04 L pt/s). Sardines mill (mill 70, Species.swift:12). | A weaver hangs head-down at the hub; at rest, feet re-grip; the abdomen breathes (Spider.swift:344, 452–461). The jumper pauses for 0.7–2.6 s (Jumper.swift:164). | Nectaring and basking poses with slow wing motion (meadow.html:1137–1165). The default stay is 0.25 × real time (2.5–10 s for a monarch, :213), so rests are short. |
| 6 | **Leaves traces** that fade | Wake: decays at 1.5/s and blurs (Shaders.swift:76). Eat heat: decays at 2.2/s (:77, 562–572). | Ringing silk, dew, torn threads, wrapped flies, a digest that takes 18 s, heat sparks, the jumper's dragline (sections below). | Pollen dust lasts 2.5–4.5 s and bloom sparks 1.2–2.2 s (:609, 978). The pointer's stirring of the grass decays at 1.6/s (:485). **No trace of a butterfly's passage or of a visit.** |
| 7 | **No two alike, nothing loops** | Sharks: size line-up, orbit radius 0.28–0.4, orbit direction, hunger 0.25–0.75, first migration at 25–70 s. Fish: depth 0.55–1, phase, mill direction per school (World.swift:197–262). | Web sizes vary 0.92–1.08; webs are placed by clearance; weavers live 150–260 s; start states are staggered; fly seed, speed and depth vary (WebWorld.swift:135–213). | Size ±12 %, wingbeat ±10 %, jink ±30 %, base height 0.35–0.75, own noise seed (meadow.html:889–894). Flowers vary in R ±18 %, petal count and natural frequency f0. **No individual temperament.** |

---

## 2. Catalogue of Ocean and Web details

### 2.1 Look

#### Grid and cell
- **Cell size:** width = clamp(round(screen width / 124), 8, 13) pt, height = round(width × 1.45) (FramePacker.swift:11–14).
- **Font:** Geist Mono SemiBold (variable font, wght 600) (GlyphAtlas.swift:39–44). The atlas has 28 glyphs; the first 17 are Ocean's: `: ; t % S X 8 # @ . ' , \` o - * ·`. Then `¯ _ / \ | + x O ° v 0` (:11–12).
- **Grid lines:** one device pixel at each cell's top and left edge. Dark theme: white at 5.5 % (Shaders.swift:535–537). Web: dark `(1,1,1, 0.055)`, light ink `(35,35,35)` at 8 % (WebPainter.swift:917–922).
- **Blocks are inset one point from the top-left grid lines.** A cell's block fills only where the local x and y are both ≥ 1 pt (Shaders.swift:617–618 Ocean, :680–682 canvas). So every block sits in its own tile, with a 1 pt strip of background and grid line showing. This is the "mosaic" look.
- **Glyph over block:** the block is the body's colour and the glyph is drawn on top of it in a separate ink.

#### Coverage, edges and glyph choice (identical in Ocean and Web)
- **Five samples per cell:** the centre plus (0.25, 0.3), (0.75, 0.3), (0.25, 0.72), (0.75, 0.72) (Shaders.swift:387–395; WebPainter.swift:44, 737–741). Coverage = hits / 5.
- **Interior cell** (centre hit and coverage ≥ 0.6): a block plus a carved glyph.
- **Edge cell** (otherwise): **no block**, only a light glyph.
  - Heavy set `: ;` when coverage ≥ 0.5, light set `. ' , \`` below that.
  - Brightness (70 + 80 × coverage) × dim, tinted per species.
  - Sources: Ocean Shaders.swift:589–595 (+6 on blue); Web WebPainter.swift:745–748.
- **Skin ramp:** `: ; t % S X 8 # @`. Index = floor((1 − shade) × 8.99) ± 1 random step from the key (Shaders.swift:612–614; WebPainter.swift:786–789). A brighter block gets a sparser glyph.
- **Carved glyph ink is dark on a lit block:** (14,15,19) when shade > 0.55, else (27,29,36) (Shaders.swift:630–634; Web `glyphLit`/`glyphShadow`, WebPainter.swift:61, 793).
- **Block brightness:** Ocean body 46 + 160 × shade; fin 40 + 120 × shade; ridge 226; mark 24 + 22 × shade; eye 12 (Shaders.swift:599–616). Web body: 30 + 96 × shade for the jumper, 48 + 150 × shade otherwise (WebPainter.swift:787).
- **Light from the top-left:** shade = 0.58 − across² × 0.42 + facing × 0.26, where facing = (n · (−0.6, −0.8)) × across (Shaders.swift:309–311; WebPainter.swift:881–888, "as the sharks are").
- **Body-anchored glyph key:** each cell's random choices come from a hash of its position on the body, so glyphs ride with the skin instead of the screen.
  - Ocean: `hash3(round(s × 52), round(v / (cw × 0.9)), id)` (Shaders.swift:399).
  - Web: `hash3(round(u / (cw × 0.9)), round(v / (cw × 0.9)), id)` (WebPainter.swift:824).

#### The hide shimmer
- **Re-roll clock:** each cell re-rolls about 2.4 times a second, each on its own staggered phase.
  - Ocean: `tick = floor(time × 2.4 + (K % 997) / 97)`, `roll = hash2(K, tick)` (Shaders.swift:585–587).
  - Web: `roll = hash3(key, int(floor(t × 2.4) + (key % 97) / 41), 7)` (WebPainter.swift:725, 750).
- **Rates:**

  | | Accent colour | White fleck | Edge accent |
  |---|---|---|---|
  | Ocean | roll < 0.09 → 9 % | 0.09–0.13 → 4 % | roll < 0.07 → 7 % (Shaders.swift:594) |
  | Web | roll < 0.06 → 6 % | 0.06–0.10 → 4 % | none |

  All rates are multiplied by `accentRate`, which Calm lowers (Shaders.swift:626–629; WebPainter.swift:790–792).
- **The seven accent colours** (Shaders.swift:476–486; WebPainter.swift:49):

  | Orange | Red | Purple | Cyan | Green | Blue | Gold |
  |---|---|---|---|---|---|---|
  | (224,137,44) | (224,58,50) | (180,74,224) | (51,200,204) | (60,181,74) | (49,80,232) | (217,193,74) |

  The cell's key picks which one (`K % 7`).
- **Brightness flicker (sharks only):** ±3 % of shade at 6 Hz, keyed to the screen cell rather than the body: `(hash3(c, r, floor(time × 6)) − 0.5) × 0.06` (Shaders.swift:404–405).

#### Depth and near/far
- **Sharks:** depth = line-up size (1, 0.9, 0.8 … or 1/0.7/0.84/0.77 for the classic four) (Species.swift:34–39).
  - Small sharks draw first, so big ones pass over them (World.swift:229–230).
  - Dim factor 0.7 + 0.3 × depth (Shaders.swift:584).
- **Fish:**
  - Depth 0.55–1 (World.swift:259).
  - Brightness v = 0.3 + 0.4 × (depth − 0.55) / 0.45 + 0.3 × max(glint, alarm), where glint = |turn| / 3.5. A turning fish catches the light (FramePacker.swift:174–175).
  - A near fish (depth > 0.78) takes a shared cell first (:170–173).
  - The dash glyph has 5 brightness buckets: 0.28, 0.42, 0.58, 0.74, 0.9 (Shaders.swift:574–580).
- **Webs:**
  - Webs with a spider: depth 0.78–1. Empty webs: 0.5–0.6, "old and faint" (WebWorld.swift:190).
  - Silk alpha (0.04 + 0.36 × depth^1.6) × gain (WebPainter.swift:557–559).
  - Webs are layered far to near: a thread 1.35× brighter hides a fainter one in the same cell (:241–245).
- **Spiders and flies:**
  - Spider dim 0.72 + 0.28 × web depth; the jumper is always 1, the nearest (WebPainter.swift:503–504).
  - Fly alpha 0.5 + 0.45 × depth (:667).
  - The jumper grows by 1 + 0.3 × sin(πt) mid-air, "as if nearer" (Jumper.swift:111).

#### Eyes, marks, fins and legs
- **Sharks:**
  - Eyes: glyph `o`, block level 12, ink (154,160,173), where across > 0.6 within the eye band (Shaders.swift:320–322, 602–604, 622–623). On hammerheads the eyes sit at the tips of the head (:295–297).
  - Dorsal ridge: glyph `8 6 %` at 226. Second dorsal: shade ≥ 0.82. Five gill slits as alternating ×0.45 shade. Snout tip ≥ 0.7 (:315–327).
  - Tiger bars and zebra spots (`marked`, :201–221): glyph `# % @`, ink 70 × tint.
  - Fins: glyphs `% : ; S` at 40 + 120 × shade (:608–610).
- **Pectoral fins bank into turns:** bank = clamp(turn × 0.45, ±0.35). The inside tip shortens and the outside one spreads (× (1 ∓ bank)). Fins also flex by 1 + 0.06 × sin(phase × 0.5) (FramePacker.swift:214–219).
- **Per-species skin tint**, as an RGB multiplier (Shaders.swift:488–500).
- **Spider eyes and marks:**
  - Jumper eyes `O` in eye ink. Fangs `v` in cyan (51,200,204); on paper the fang ink is paper colour.
  - Patterns: araneus cross `+`, argiope bands warm yellow, nephila spots `o ° o`, Phidippus spots (WebPainter.swift:758–785, 858–876).
- **Legs:** stroke glyphs (`- _ ¯ / \ |`).
  - Each segment is drawn in two halves, so banded legs alternate shade along their length.
  - Glyph level × 1.12 on a dim block (× 0.34). On paper: glyph 250 − l × 1.25, block 250 − l × 0.5 (WebPainter.swift:70–71, 696–710, 801–806).
  - Knees bend away from the body's midline (Spider.swift:509–519).
  - Femur 0.46 L, tibia 0.56 L (:227).

#### Silk drawing
- **One glyph per step** along a thread's major axis, with cells claimed half-open so threads meeting end to end don't double up (WebPainter.swift:179–229).
- **Glyph choice:** `- _ ¯` by where a level thread runs in its cell (top < 0.3 < middle < 0.7 < bottom); `|` beyond 1.12 rad; otherwise `/ \` (:89–95).
- **Crossings:** where two or three threads cross, the strongest runs on through. Only the hub, with ≥ 4 threads and low coherence (< 0.6), gets a `*` knot (:102–109).
- **Per-kind brightness** `SILK_ALPHA` (mooring, frame, radial, hub, spiral, stabilimentum): 0, 0.75, 0.95, 1, 1, 0.8, 1.8 (OrbWeb.swift:35). Ink is quantised to 24 levels (WebPainter.swift:21).
- **Ringing:** ringing energy e = node speed.
  - When e > 0.45 the silk switches to the cyan ring ink (110,230,255).
  - Brightness gains up to +0.5 via (e − 0.12) × 0.4.
  - Cells with ≥ 4 threads draw × 1.25 (:527–530).
- **Dew:** 8.5 % of spiral threads carry a bead, at 0.2–0.8 along the thread (OrbWeb.swift:430).
  - Twinkle tw = 0.5 + 0.5 × sin(t × (0.8 + 1.4h) + l × 1.37); `+` when tw > 0.94, else `·`.
  - Brightness (0.3 + 0.6 tw) × (0.45 + 0.55 depth).
  - Drawn as a second glyph over the silk (WebPainter.swift:627–659).

#### Flies
- In flight `x` and `+` alternate (`floor(phase × 12 + seed) mod 2`). At rest `x`.
- Stuck: `* x` thrash on a 15 Hz phase clock (every third tick shows `x`). While wrapped `%` then `@`; carried `@`.
- Eaten: `@ → 0 → o → ·` at 35 %, 65 % and 88 % digested (WebPainter.swift:668–683).

#### Fish and the wake (Ocean)
- **Fish:** one `-` dash per cell, never drawn on a shark (Shaders.swift:412–419).
- **Wake dots:** small squares at the lower right of empty cells when wake energy e > 0.45.
  - Size max(2, round(cw × 0.19)) + 1.
  - Six alpha levels.
  - Colour cyan (110,230,255) or the system accent, per the Wake colour setting (Shaders.swift:552–560; Theme.swift:9, 18).

#### Theme, Calm, dissolve
- **Ocean light theme:** lightness is inverted with hue kept, `col + (1 − 2Y)` (Shaders.swift:457–464). Accents survive, slightly shifted.
- **Web light theme:** "graphite on paper". Paper (247,246,243), ink (35,35,35), silk gain 0.85. **The accent list is empty**, and flecks, eyes, spots and fangs become paper colour (WebPainter.swift:63–66). Tones mix ink toward paper (:73–82).
- **Calm:** brightness 0.62, accentRate 0.35 (Theme.swift:15–16). Web Calm dims dark ink toward black and light ink toward the paper (WebPainter.swift:365–377).
- **Dissolve between habitats:** a cell shows when `revealHash(cell) < reveal`. Out 0.35 s, in 0.45 s. All habitats use the same per-cell pattern (Shaders.swift:449–454, 533, 673; Dissolve.swift:8–9).

### 2.2 Motion

#### Ocean sharks
| Detail | Value | Source (World.swift unless noted) |
|---|---|---|
| Spine | 20 nodes, follow-the-leader, max bend 0.16 rad per joint | :600–611 |
| Cruise speed | 30 + 0.04 L pt/s | :592 |
| Speed easing | rate 1.1/s | :594 |
| Turning (agility) | min(hunting ? 1.7 + closing : 0.8, speed / (0.22 L)) rad/s, so slow sharks can't turn sharply | :586 |
| Turn smoothing (drives fin bank) | 3/s | :590 |
| Wander | random walk of ±1.1 rad at rate 3.2, weight 0.45 | :495–497 |
| Swim undulation (drawn) | amplitude 0.05 L × (0.1 + 0.9 t^1.8) × clamp(speed/60, 0.4, 1.4); wave sin(phase − 5.2 t) | FramePacker.swift:193–206 |
| Wave phase speed | 2 + speed/24 rad/s | :595 |

#### Ocean fish
- **Boids in zones:** elliptical separation per species, spacing in cells (Species.swift:10–24), × 420.
  - Alignment 1.4 × species value. Cohesion 1.0 × species value, reduced by up to 80 % in alarm.
  - Milling (sardines) (World.swift:364–378).
- **Speed:** preferred cruise × (1 + 1.3 alarm), steered at 1.6 (:431–433). Max × (1 + 1.8 alarm), with a minimum (:438–444).
- **Current:** a divergence-free curl field, frequencies 1/260, 1/310, 1/190, drifting at 0.07, 0.05, 0.11 rad/s, × 0.5 (:69–77, 426).
- **Per-species jitter** (25–110) and vertical drag (:427–429).

#### Web spiders
| Detail | Value | Source (Spider.swift unless noted) |
|---|---|---|
| Heading spring | k = 70 default; idle 34, moving 64; jumper 110 at interest, 45 wandering, 160 crouched. Damping 2√k × 0.92, cap ±6 rad/s | :317–322; Weaver.swift:341; Jumper.swift:131, 153 |
| Gait | tetrapod: each foot waits for same-side neighbours and its opposite number; never more than 4 feet stepping | :231–238, 398 |
| Step threshold | 0.34 L moving, 0.15 L at rest, 0 when raised; "desperate" at 0.85 L | :391, 395 |
| Stride time | clamp(L / (speed × 1.3 + L × 2.8), 0.14, 0.34), then at least distance / (3 L), up to 0.5 s ("a reach, not a flick") | :400, 410 |
| Foot lead | dur × 1.1 + 0.26 L / max(speed, 40) | :404 |
| Foot path | eased 0.5 − 0.5 cos(πt), arcing outward by sin(πt) × 0.1 L | :428–436 |
| Weight shift | body leans 0.22 toward the planted feet, capped at 0.07 B, eased 1 − e^(−9dt) | :463–489 |
| Abdomen breathing | 1 + 0.035 sin(1.9 t + id % 7); length × breath, width × (2 − breath) | :344; WebPainter.swift:413–414 |
| Idle foot re-grip | after 1.4 s still, with no step under way, chance 0.35/s: one foot moves 0.07 L, step time 0.2 s | :452–461 |
| Foreleg toward a tug | when alert > 0.25, the front leg on that side reaches 0.92 L toward the tug (0.22 s) | :350–386 |

#### Web weaver pace
- **Laying speeds** per thread kind: 70, 66, 72, 42, 46, 38 px/s. Walk 80, hunt 85, carry 60 (Weaver.swift:26–30).
- Everything × scale = clamp(R/300, 0.5, 1.25) (:85). Eating the web (walking the route back) runs ×1.4 (:191).
- **Corner braking:** target speed = vmax × lerp(0.2 + 0.8 × through, 1, clamp(d / 1.2 B)), where through = 1 − min(1, turn / 2.2) (:136–145).
- **Pace easing:** rate 4.5/s, minimum 6 % of vmax (:148–151).
- **Tap:** a 0.1 s slow-down to 0.35× at each radial while the sticky spiral goes down (:191, 210).
- **Wrap:** 3.6 s. The circle speeds up and slows down as 1.3 × sin(πk)^0.6; radius 0.28 B grows in over the first quarter; the web is jolted 4 times a second at 0.25 (:302–316).
- **Tow:** a parcel trails the spinnerets 0.16 B behind, following at 12/s (:346–356).

#### Web jumper
- **Bursts:** speed = bv × sin(πk)^1.4.
  - With a target: bv 55 × s, lasting 0.45–0.8 s, then a pause of 0.35–0.9 s.
  - Wandering: bv 62 × s, lasting 0.7–1.4 s, then a pause of 0.7–2.6 s (Jumper.swift:155–180).
- **Leap:** duration 0.32 + d/700, ease 1 − (1 − t)^2.4, scale 1 + 0.3 sin(πt). It lands low at 0.9 and springs back up at rate 14 (:105–116, 183, 205).

#### Web flies
- **Heading:** noise1 wander × 3.4 plus ±2.5 rad/s random. Darts happen 0.5 times a second: ±2.2 rad and 180–250 px/s (Flies.swift:193–198).
- **Speed:** target 80 + 55 × noise, eased at 2.2/s (:194, 218).

#### Web silk
- **Verlet mesh:** damping 0.962 per step; gravity 0.012 × (R/300); wind noise1(t × 0.12) × 0.0026 (OrbWeb.swift:504–517).
- **Constraint:** one-sided (slack silk pushes nothing), 6 iterations (:518–540).
- **Pre-tension** 0.965–0.99 (:31). Threads break at 2.0–2.4× their rest length (:33, 541–546).

#### Clock
- Fixed 60 Hz, at most 4 catch-up steps, frame time clamped to 0.1 s (OceanClock.swift:5–6, 19).
- The Speed setting scales simulated time, 0.5–1.5 (Settings.swift:50).

### 2.3 Behaviour and life

#### Ocean
- **Prey choice:** prey must be in a forward cone (cos ≥ 0.2) within 0.9 L + 160.
  - Score = d × (1 + (1 − cos) × 0.8) × (1 + crowd × 0.07). Crowd = fish in the prey's hash bucket, so **stragglers** in sparse spots score better.
  - Hysteresis: the current target is kept unless a new one beats it by 1.3× (World.swift:455–476).
  - Sharks aim 0.35 s ahead of the fish (:527–528).
- **Feeding:** only when hunger > 0.15. Mouth radius 0.05 L + 8 (:614–626).
- **Fountain effect:** fear comes from the nearest of nodes 0, 3, 6, 9, 12 (the front half), within 0.6 L + 60. Flight = (0.7 × away + 0.9 × sideways across the shark's heading) × 1100 × weight² (:380–402).
- **Alarm:** decays as e^(−0.7 dt). It relays at 0.86 × the neighbour's alarm, at rate min(1, 6 dt) (:302–303, 416–419). Alarmed schools spread out by 1 + 1.8 × alarm (:309).
- **Sharks give each other room** within (L + L') × 0.45 (:548–560).
- **A clear middle:** a soft elliptical no-swim zone of 0.3 W × 0.16 H, weight 2.5 on patrol and 1 when hunting (:562–572).
- **Patrol:** orbit radius 0.28–0.4 × the screen's short side, breathing ±15 % at 0.05 rad/s. Directions alternate (:209–212, 542).
- **Migration:** the first wander to another screen comes at 25–70 s, then every 35–80 s, through the middle of the shared edge with weight 1.4 (:226, 499–517).
- **Respawn:**
  - An eaten fish returns after 3–8 s, but schools are batched: they wait for ≥ 6 due or 9 s since the last spawn.
  - A new school enters from a real edge, picked by length, 0.15–0.85 along it and 20 pt outside, heading inward ±0.5 rad at 1.4× cruise (:631–666).
- **Density:**
  - Fish per screen: area / 4400, clamped to 85–340, × the density setting (0.5–2), capped at 1024 (:233–234).
  - Species weights: sardine 3, anchovy 3, silverside 3, mackerel 2, goby 1. School sizes 5–32 (Species.swift).
  - Shark base length clamp(min side × 0.44, 170, 430) (:205).

#### Web
- **Web count:** clamp(round(area / 215 000), 2, 10), plus the bottom-left one (WebWorld.swift:128).
- **Sizes:** base × lerp(1.3, 0.72) × 0.92–1.08 (:135–139).
- **Placement:** each web is the best of 300 candidates by clearance (:158–183).
- **Staggered start:** one weaver is 30 % through its spiral, one 35 % through its scaffold, the rest finished (:204–213).
- **Opening catch:** within seconds, a fly heads straight for the nearest web (:223–237).
- **Weaver life:**
  - It reads tugs as alert += 0.08 × amount, decaying at 0.7/s. At the hub it leans 0.14 B × alert toward the tug and turns up to 1 rad toward it (Weaver.swift:108–113, 236–246).
  - It eats the web when catches ≥ 3, damage > 22 % or age > life (150–260 s), then rebuilds within ±0.18 R × ±0.14 R of home (:254–259, 359–381).
- **Flies:**
  - Count clamp(area / 140 000, 5, 12) (WebWorld.swift:222).
  - They rest with a chance of 0.045/s, for 2.5–7 s (Flies.swift:238–241).
  - Crossing capture silk sticks a fly with chance 0.07 × (0.4 + 0.6 × depth) (:14, 231).
  - A stuck fly struggles every 0.06–0.45 s and tears free after 16–26 s unless hunted, breaking the thread (:85, 168–178).
  - Respawn after 2–6 s (eaten at the hub) or 3–7 s (by the jumper), drifting in from an edge (:245–274).
- **Jumper:** stalks resting flies only when hunger ≥ 0.35. A catch resets hunger to 0 and holds a 1.8 s pause (Jumper.swift:81, 119–125).

### 2.4 Interaction

| | Move | Click | Hold still |
|---|---|---|---|
| **Ocean** | Fish flee within 130 pt, at force 1100 × weight², fear 0.8 (World.swift:404–414). The cursor leaves a faint wake: radius 1 cell, 0.08 per step (Shaders.swift:112–114). | **Splash:** radius 240 pt, push (1 − d/r) × 260, alarm 1 (World.swift:154–167). Wake stamp radius 6 cells, 1.4 (Shaders.swift:106–107). | Nothing yet ("later: curious fish gather"). |
| **Web** | **Pluck:** threads within cw × 1.15 of the pointer's path are pushed min(0.12 R, 2.2) plus 0.2 × the pointer's velocity, then spring back and ring (OrbWeb.swift:554–583). If touched > 0.2 the spider feels it, leans, turns and raises a foreleg (WebWorld.swift:244–252). Flying flies shy within 120 pt (turn 9 rad/s, speed 230); resting ones flee within 90 pt (Flies.swift:159, 201–204). | **A fly:** it sticks if within 0.9 cw of capture silk, else flies off at 140–200 (Flies.swift:118–146). | **The jumper** turns toward a cursor within 440 pt and moves in bursts to within 4.2 B. If the cursor moves < 10 pt for 0.9 s while the jumper faces it (< 0.22 rad), it crouches for 0.26 s and pounces, landing 0.2 B short. Cooldown 2.6 s (Jumper.swift:73–80, 136–174, 199–211). |

Both habitats ignore the pointer over windows, the menu bar or the Dock (PointerRouter.swift:19–23).

### 2.5 Traces that fade

| Trace | Fade | Source |
|---|---|---|
| Wake | blur, then e^(−1.5 dt) | Shaders.swift:68–77 |
| Eat heat | red `·`, turning orange `*` above 0.5 and 0.6; decays e^(−2.2 dt) | Shaders.swift:77, 562–572 |
| Ringing silk | Verlet velocity × 0.962 per step | OrbWeb.swift:511 |
| Torn threads | stay broken until the spider eats the web | OrbWeb.swift:476–490, Weaver.swift:255 |
| Wrapped fly | carried, then digested over 18 s, shrinking `@ 0 o ·` | Weaver.swift:331 |
| Jumper's dragline | fades at 0.35/s after landing; alpha 0.5 × life | Jumper.swift:99–102; WebPainter.swift:511–514 |
| Heat sparks from a jumper's catch | 6 sparks, life 0.8–1.3, decaying 1.4/s | WebWorld.swift:261, 273–278 |
| Empty webs | a permanent "old" trace: depth 0.5–0.6 | WebWorld.swift:190 |

### 2.6 Edges and screens

- **Ocean fish:**
  - Soft walls only on real edges (not shared between screens): margin 36, push (m − s) × 7 (Terrain.swift:145–159; World.swift:421–424).
  - Fish are clamped to 60 pt beyond the bounds (:447–448).
- **Ocean sharks:** turn back once the snout is past −0.05 L, with weight up to 3.5 reached at 0.3 L outside (:574–583).
- **Web:**
  - Webs stay within one screen, with the frame inside it, but mooring lines run off the edges (WebWorld.swift:170–177; OrbWeb.swift:283–292).
  - Flies may go 20 pt off a screen; within 36 pt of a wall they head for the middle at 4 rad/s (Flies.swift:206–225).
  - The jumper stays 0.8 B from walls and slides along them; it wanders to another screen only if the straight path stays on the screens (WebWorld.swift:342–373; Jumper.swift:185–193).

### 2.7 Performance tricks that shape the look

- **Ocean:**
  - Shark cells are classified on the GPU, skipping anything outside each shark's bounding box or beyond 0.36 L + one cell diagonal from the spine (Shaders.swift:383–388).
  - At most 8 sharks per viewport, the most visible first (FramePacker.swift:102–112).
  - Only events new to the viewport and within 6 cells of it are packed (:117–125).
  - The wake runs once per sim step. Shader time wraps at 3600 s.
- **Web:**
  - Buffers only grow, and cells are cleared lazily by a frame stamp (WebPainter.swift:119–135, 168–176).
  - Whole webs off the grid are skipped (:594–606). Plucks skip webs beyond outer + R (OrbWeb.swift:555).
  - Inks are pre-packed per theme at 24 levels (WebPainter.swift:342–362).
  - Hot loops run on value copies, not class properties (:112–117).
- **Fidelity is fixed; only cost tricks give** (design doc, Performance).
- **Power:** 30 fps live, 15 fps on battery, Low Power or thermal pressure. A still for Reduce Motion (PowerPolicy.swift:49–56).

---

## 3. Gap list: the Meadow sketch against the family

Status: **Has**, **Differs** or **Lacks**. Each row ends with a suggestion for the Meadow, seen from above.

### 3.1 Look

| Detail | Family | Sketch | Status | Suggestion |
|---|---|---|---|---|
| Cell size, font, grid | as §2.1 | Same cell formula (:449); Geist Mono 600 at ch × 0.74 (:1593); grid 5.5 % / 8 % (:1553) | Has | Draw grid lines at c = 0 and r = 0 as well (the sketch starts at 1, :1555). Trivial. |
| **Block inset 1 pt from the grid** | every block tiled (Shaders.swift:617–618, 680–682) | Blocks are drawn as one image scaled to whole cells, then the grid is drawn over them (:1589–1591). No inset, so blocks butt together. | **Differs** | Inset blocks by 1 pt at top and left, as `canvas_main` does. This alone gives the wings, flowers and leaves the family's mosaic tiles. The app gets it for free on the cell canvas; the sketch should match so the director judges the real look. |
| Coverage samples | 5 (centre + 4) | 9 (3 × 3) for wings (:1329–1356); 4 + centre for flowers (:830, 843–849) | Differs | Keep 9 if it reads better, but use the family's thresholds. See the next row. |
| **Edge cells have no block** | coverage < 0.6 or centre miss → no block; `: ;` at ≥ 0.5, else `. ' , \``; level (70 + 80 cov) × dim | Wings: below 0.3 coverage a light glyph only. Between 0.3 and 0.62 the "rim" **keeps a block** at 0.75 tone plus `% ; # :` glyphs (:1371–1375, 1418–1424). Flowers follow the family rule (:856–860). | **Differs** | Wing cells below 0.6 coverage (≤ 5 of 9) drop the block: heavy `: ;` at ≥ 0.5, light set below, in ramp[1] × (0.55 + 0.3 cov). The silhouette then softens into glyphs like a shark's flank or a spider's abdomen. |
| **Glyph ramp by shade, carved in dark ink** | `: ; t % S X 8 # @` by (1 − shade) × 8.99 ± 1; dark ink (14,15,19) / (27,29,36) on lit blocks | Four per-step glyph sets, busier on bright steps, in ink **one step brighter** than the block, and 30–65 % of field cells left without a glyph (:1333, 1425–1429) | **Differs** | Draw field glyphs in dark carved ink. On dark: ramp[0] × 0.35 when L ≥ 2, else (27,29,36) mixed 30 % toward ramp[0]. Use the skin ramp by shade ± 1. Keep the empty-cell share at 0, or 30 % for the cabbage white, so wings read as textured skin like the sharks. Keep the black marks' `# % @ 8 X` (already family). |
| Body-anchored keys | position on the body, × 0.9 cell | Wing-local `hash3(round(X × sx / cw × 1.2), …, id × 8 + part + 3 × side)` (:1362–1363) | Has | — |
| **Hide shimmer** (re-roll ~2.4/s staggered; 7 accents ~6–9 %; white ~4 %; edge accents 7 %) | Ocean and Web | **None.** Keys never change with time. The only sparkle is the morpho glint (:1423) and dust (:1499). Director's note, 2026-11-20 (WORKBOARD, commit 3da6bf6). | **Lacks** | Port Web's rule as is: `tick = floor(t × 2.4)`, `roll = hash3(key, tick + (key % 97) / 41, 7)`. Accent < 0.06 × accentRate (the 7 family colours, by `key % 7`); white fleck < 0.10. Edge cells: accent < 0.07. Apply it to wing field and body cells, not to marks, the eyespot or veins, so species still read at a glance. Cabbage white: use dark ink (27,29,36) for flecks, since white on white is invisible. Light theme: accents off and flecks paper-coloured, as in Web. Flowers: shimmer petals and discs at half the rate (3 % / 2 %) so blooms twinkle quietly. |
| Brightness flicker ±3 % at 6 Hz | sharks | none | Lacks | Optional. Add it to wings at ±3 %, `hash3(c, r, floor(t × 6))`. Skip it on flowers so the ground stays calm. |
| **Depth: brightness** | 0.7 + 0.3 depth (sharks); 0.72 + 0.28 (spiders) | `nearK` = 0.94 + 0.12 z (:1344) | Differs | Widen to 0.78 + 0.28 z: a butterfly on a flower ×0.78, one at the glass ×1.06. Near and far should read in brightness as well as size, as in the family. |
| Depth: size, shadow, order | size by line-up; drawn small to large | Size 0.75 → 1.4 exponential in z (:1189). Shadow offset z × 150 + 3 pt down-right, fainter by (1 − 0.55 z), softer by spread 0.3 + 0.9 z (:1213–1216, 1474–1490). Sorted by z (:1568). | Has (richer than the family) | Keep. |
| Glint when turning | fish brighten by \|turn\| / 3.5 | Per-wing light from its tilt, plus a morpho glint at spec^18 (:1203–1209) | Has | — |
| **Eyes** | Shark `o` at level 12, ink (154,160,173); jumper `O` | Head is a single `o` cell (t > 0.86) in body ink (:1453) | Differs | At ≥ 15-cell spans, draw two eye cells beside the head in `°`, ink (154,160,173) dark / ink colour on paper, so the head reads as a face like the shark's. |
| Fins and legs bank | Inside fin shortens by (1 ∓ bank), bank ≤ 0.35; flex 1 + 0.06 sin | Wing widths cos(stroke ∓ bank); bank 0.35 × maxBank × tanh(turn / 1.5) (:1118, 1199–1201) | Has | — |
| Antennae | (spider legs: two-bone IK) | Clubbed, swaying 0.06 × sin(phase) (:1456–1470) | Has | Add an idle twitch; see §3.2. |
| Legs | spider legs stroke-drawn | none | Lacks | When landed with wings closed or in a vee, show 2–3 leg cells each side (`/ \` at 0.6 alpha, leg level as Web). On basking wings they are hidden. |
| Silk-style line drawing | `- _ ¯` by position in the cell; strongest line runs through | `lineGlyph` has only 4 directions (:426–432); grass and veins ignore where the line sits in its cell | Differs | For veins, petal rays and fennel rays, reuse Web's `lineGlyph(nc, ns, m)` with `¯ _ -` placement (WebPainter.swift:89–95). Thin lines then sit on their real row, as the silk does. |
| Light theme | Ocean inverts lightness; Web is graphite on paper, accents off | Graphite on paper with species hues (owner's decision); flowers via onPaper (:325–398) | Has | With the shimmer, turn accents off on paper (Web rule). |
| Calm | brightness 0.62, accentRate 0.35 | 0.62 toward black or paper; 0.35 only on shine and dust (:1436, 1577–1584) | Has | Apply 0.35 to the new shimmer rates. |
| Dissolve | per-cell revealHash, 0.35 s out, 0.45 s in | n/a (app-side) | Has (inherited) | — |

### 3.2 Motion

| Detail | Family | Sketch | Status | Suggestion |
|---|---|---|---|---|
| Sprung heading | k 34–160, ζ ≈ 0.92, ±6 rad/s | k 30–60 × turning, ζ 0.8–0.9, ±6√turning (:1071–1074) | Has | — |
| Eased speed | 1.1/s (sharks), 4.5/s (weaver) | Per-beat thrust plus drag 8 (:1082–1094) | Has | — |
| **Nothing snaps: take-off** | every change eased | `takeOff` sets `heading = a` instantly when flushed (:984), and `phase = 0` (:985). That throws the stroke to the top (80°) in one frame, from a bask pose of 4–10°. | **Lacks** | Don't set heading; add the away direction to `jink` (the spring turns the body in ~0.2 s at k = 45). Blend the stroke from the landed pose into the beat over 0.15 s: stroke = lerp(landed, beat, ease(t / 0.15)). |
| **Nothing snaps: landing** | — | `land` sets airspeed to 0 at once (:994). `stepLanded` replaces the stroke with the pose formula on the next frame (:1146–1163), a jump of up to 60°. | **Lacks** | Ease the stroke toward the landed pose at rate 8/s (a first-order lag). Fold the last 2 beats into a "brake": impulse × 0.3 and stroke amplitude halved, so it settles. |
| **Spawning** | fish schools swim in from a real edge; flies drift in from an edge | `syncFlies` creates butterflies anywhere on screen, in mid-flight (:889, 912) | **Lacks** | New butterflies enter from a real edge 20 pt outside, 0.15–0.85 along it, heading inward ±0.6 rad (Flies.swift:245–270). Removed ones fly out through the nearest real edge. |
| Swim undulation, gait | body wave; tetrapod gait, ≤ 4 feet stepping | wingbeat with per-beat lurch, bob 0.045 z, 0.05 rad yaw rock (:1114–1115, 1196) | Has (butterfly-native) | — |
| **Wingbeat at 15 fps** | the fastest family motion is slow: shark wave < 1 Hz, spider stride ≥ 0.14 s, fly glyph toggle 6 Hz | Up to 7.5 Hz (monarch 4.75 Hz at the default 0.5×) (:310–311). At 15 fps that is 2–3 frames per beat. | **Differs (risk)** | The design requires the ten-minute watch at 15 fps. Cap the drawn beat at fps / 4 (3.75 Hz at 15 fps), or default wingbeat to 0.35 (monarch 3.3 Hz, white 4.1 Hz). Keep the lurch in sync. |
| **Breathing** | abdomen 1 + 0.035 sin(1.9 t + id % 7) | none | Lacks | Landed: abdomen length × (1 + 0.04 sin(1.6 t + seed)), in the 2–3 abdomen cells. In flight it is hidden by the beat. |
| **Idle fidget** | foot re-grip: after 1.4 s still, chance 0.35/s, offset 0.07 L, step time 0.2 s | Wings open and close slowly (:1150–1151); morpho flash every 5–14 s (:1158–1161) | Partly | Add a landed antenna twitch: after 1.5 s still, chance 0.3/s, one antenna swings ±0.25 rad and back over 0.3 s (eased). Add a small heading shuffle on the flower: ±0.15 rad every 4–9 s, through the spring. |
| Sway | silk wind noise 0.12 Hz × 0.0026 | Flower head on a damped spring: f0 0.7–2.5 Hz, ζ 0.12, drag k = 0.0035, cap 0.45 R (:617–631) | Has | At 15 fps, a 2.5 Hz clover with ζ 0.12 may buzz. Cap f0 at 1.6 Hz and raise ζ to 0.18. |
| Lean toward a pull | spider leans 0.14 B × alert toward a tug | — | Lacks | A landed butterfly in a gust leans its body 0.1 span downwind (eased at 6/s) and closes its wings partly. See §3.4. |
| Hesitation before the lunge | jumper watches 0.9 s, crouches 0.26 s | Approach slows inside 2.2 spans (:1041) | Partly | Add touch-and-go: on an approach inside 0.6 span, abort 25 % of the time. Rise (zv + 0.4), circle 1–2 beats around the bloom at 1 span, retry once, else pick another flower (plan line 183). |

### 3.3 Behaviour and life

| Detail | Family | Sketch | Status | Suggestion |
|---|---|---|---|---|
| **Wants (drives)** | shark hunger 0.03/s; jumper hunger 0.02/s | Fixed probabilities: visits 0.35, bask 0.1 (:211, 216, 953–967) | **Lacks** | Per the plan: hunger falls 1 %/s in flight and refills while nectaring; warmth falls in flight longer than 60 s and refills by basking. Then visit chance ∝ hunger and bask chance ∝ 1 − warmth, so a long-flying butterfly visibly heads down. |
| **Senses, not knows** | forward cone and range for prey; tugs through silk | `pickFlower` sees every flower on screen (:936–951) | **Lacks** | Sensing radius of 8–15 wingspans (plan line 190), with a forward bias of cos ≥ −0.2. Pointer flush through the air (§3.4). |
| Prey choice / "stragglers" | crowd penalty 0.07 per fish; hysteresis 1.3× | Weights by species plus a separation term (:943–946); busy flowers locked (:940) | Has (analogue) | Add flower constancy (plan): × 1.5 weight for the last kind visited, and a shorter dwell on it. |
| **Alarm spreading** | fish contagion min(1, 6 dt), relay 0.86 | Each butterfly reacts alone | Lacks | A flushed butterfly startles landed ones within 3 wingspans after a 0.15–0.4 s delay, with chance 0.6 × (1 − boldness). A small relay, never a whole-screen scatter (the design says "a busy desktop" is an anti-goal). |
| Spacing | sharks' room (L + L') × 0.45; fish elliptical separation | 2.4 × average span at any height, plus a push at touch (:1053–1060) | Differs | Per the top-down direction doc: apply spacing among similar heights only (\|Δz\| < 0.25), so a high and a low butterfly can cross. |
| Patrol / territory | shark orbit 0.28–0.4 short side, breathing ±15 % | Correlated random walk, best of 9 waypoints (:920–934) | Has (analogue) | Species habits from the plan: the white patrols low loops; the monarch perches on tall flowers and sallies out. |
| Clear middle | Ocean only (0.3 W × 0.16 H); Web dropped it | none | Not needed | The director asked for the whole screen. Leave it out, as Web did. |
| Migration between screens | sharks every 35–80 s; flies and jumper cross touching screens | single screen | **Lacks** | Butterflies cross through doorways on touching screens; the monarch weights the crossing ×3 (plan line 233). Waypoints are picked on any screen when the straight line stays on the terrain (Web's `wanderGoal`, WebWorld.swift:362–373). |
| Rest | weaver idles at the hub; jumper pauses | Nectar 0.25 × real (monarch 2.5–10 s), bask 10 % share (:213–216) | Partly | Start the stay multiplier at 0.5 (monarch 5–20 s) and add the plan's Rest state: wings closed 15–60 s, a slow open-close every 6–15 s. Stillness gives motion its meaning. |
| **Opening moment** | Web: one fly aimed at the near web; weavers in mid-build | All butterflies start in flight at random spots | **Lacks** | At launch: one butterfly already nectaring, one basking (plan: "~30 s of brief basking"), and one flying straight to a flower within 5–10 s. |
| Density by area | fish area / 4400; flies area / 140 000 (5–12) | `count` slider, default 4, any screen size (:182) | **Differs** | count = clamp(round(area / 400 000 × density), 2, 16) per screen: a 1512 × 982 laptop gets 4, a 2560 × 1440 monitor 9 (plan and direction doc). Flower patches already scale as area / 190 000 × density (:573). |
| **No two alike (temperament)** | sizes, life spans, hunger, orbit, staggered states | size, beat, jink, seed | Partly | Add boldness 0.6–1.4 per butterfly: flush radius × (2 − boldness), stay × boldness, preferred height ± 0.15. |
| Life cycle | (weaver: build → eat the web → rebuild) | none | Lacks (owner to decide) | The plan's monarch story (munch 60–120 s … dry 20–40 s) is the Meadow's "build a web". From above, the chewed leaf notches and fading frass `·` read well even without the J-hang. |

### 3.4 Interaction

| | Family | Sketch | Status | Suggestion |
|---|---|---|---|---|
| **Move** | Ocean: fish flee within 130 pt, plus a cursor wake of 0.08 per step. Web: plucks silk within 1.15 cw; the spider turns, leans and raises a leg. | Stirs the air: 48 pt grid, radius 3, weight 0.16, ±260, decaying 1.6/s (:508–516). Grass lies over in the flow (:1539–1545). Fast pointer > 380 pt/s flushes within flush × cw × (1 + speed / 1500), flush 3.5–5 (:1626–1634). | Has, differs | Route the flush through the air. A landed butterfly reads the stirred wind in its cell: wings close above 60 pt/s, flush above 120 pt/s (plan lines 186, 198). A flying one veers by the local stir (it already drifts 0.55 × wind) and beats +15 % (:1046). Then the pointer and natural gusts act alike, which is "senses, not knows". |
| **Click** | Ocean splash; Web drops a fly | Blooms a flower where clicked: easeOutBack over 2.2 s, 16 gold sparks, and the nearest flying butterfly comes with chance 0.7 (:604–615) | Has | — |
| **Hold still** | Web jumper: still < 10 pt for 0.9 s → crouch 0.26 s → pounce; cooldown 2.6 s | **none** | **Lacks** | The design table and plan: pointer still ≥ 3 s (jitter < 2 pt) inside the terrain. The choice is weighted (swallowtail and white 2, monarch 1, morpho 0.5). It spirals in over 2–3 loose circles, sits, opens and closes every 4–10 s, and puts its proboscis to the cursor. A move > 2–3 pt sends it off in an escape burst: × 2 speed, beat × 1.25, 0.6–1.2 s. Use the jumper's "watch" counter pattern. |
| Pointer over windows | ignored | n/a | (app) | — |

### 3.5 Traces that fade

| Family | Sketch | Status | Suggestion |
|---|---|---|---|
| Wake behind sharks, fish and cursor (decays 1.5/s) | none behind butterflies | **Lacks** | **Wing downwash:** each downstroke while z < 0.35 stirs the air below by 40 × (1 − z / 0.35) pt/s outward. The grass under a low butterfly then flickers and lies over, fading with the air field (1.6/s). It also makes "wings beat air" (principle 3) visible. |
| Ocean cursor wake dots (cyan / accent) | Pointer stir colours grass "stirred" green (:1544) | Differs | The design names pollen gold as the habitat accent for the pointer breeze. Where stir > 60 pt/s, put gold `·` motes in empty grass cells at 0.35 alpha, fading over 0.8 s. Honour the Wake colour setting (gold by default, the system accent when chosen). |
| Eat heat (2.2/s); jumper's catch sparks | Bloom sparks 1.2–2.2 s; take-off dust 2.5–4.5 s (:609, 978) | Has | — |
| Wrapped and digested fly (18 s); torn threads | — | **Lacks** | **A visited flower shows it:** for 20–40 s after a visit, the disc's glyphs drop one step and the disc block dims × 0.85, recovering eased. Pollen visibly taken. |
| Ringing silk when touched | — | **Lacks** | **Landing nods the flower:** add an impulse to the head spring along the butterfly's heading, 0.12 R × size (the plan's `landingDipsStem`). Take-off gives half that backward. From above the bloom shifts and its shadow moves, which reads as weight. |
| Empty old webs (depth 0.5–0.6) | — | Optional | A few spent flowers: 10 % of blooms at 0.6 brightness with drooping petals. A permanent quiet trace. |

### 3.6 Edges and screens

| Family | Sketch | Status | Suggestion |
|---|---|---|---|
| Soft walls only on real edges (margin 36, push 7 × depth); shared edges are not walls | Turns back at 0.25 span off screen, heading weight 2 (:1061–1065) | Differs | Keep the director's "may flutter off" behaviour, but only on real edges (`Terrain.signedOutside`). Shared edges are open doorways. |
| Waypoints and flies within slack 20 pt | Waypoints at 7 % margin (:921); flowers may sit 10 pt over the edge (:592) | Has | Let flower patches straddle real edges (a bloom cut by the screen edge is natural) but never a shared edge. Plant each screen rect separately. |
| Pointer never draws a creature into gaps | — | (app) | Plan review focus 1: no landing outside the terrain. |

### 3.7 Performance that shapes the look

| Family | Sketch | Suggestion |
|---|---|---|
| Ocean culls by bounding box and skip-beyond, 8 sharks max | Per-flower and per-butterfly cell boxes (:835–836, 1342–1343) | Keep. Also cull flowers and butterflies whose box misses the viewport before sampling. |
| Web: grow-only buffers, frame stamps, off-grid skip, pre-packed inks | Ground cached (`buildGround`, :1509–1527) | Also cache each flower's raster in local cells; re-sample only when the head offset moves more than 0.25 cell or the age changes (like "cache settled silk"). Most flowers barely move. |
| — | `windAt` (2 value-noise calls) for **every grass cell every frame** (:1534–1546) | Sample gust and stir on the 48 pt PG grid once per frame and interpolate per cell. The look is identical and a large cost goes away. |
| — | 9 polygon tests plus an edge-distance pass per wing cell (:1353–1358, 1246–1259) | Rasterise each wing outline once per frame into a small local mask at 2× cell resolution, then read coverage from it. |

---

## 4. Ten gaps to close first

1. **Hide shimmer on the wings** (director's note): Web's rule, 2.4/s staggered, 6 % accents in the 7 family colours, 4 % white flecks; off on paper; ×0.35 in Calm (§3.1).
2. **Carved dark glyphs on lit blocks, with blocks inset 1 pt**: the family's two strongest visual signatures (§3.1).
3. **Edge cells without blocks** (`: ;` / `. ' , \``), so silhouettes soften like sharks and spiders (§3.1).
4. **Hold still → a butterfly lands on the cursor**, with an escape burst on any move (§3.4).
5. **Nothing snaps:** ease the take-off and landing stroke, turn through the spring when flushed, and enter from edges instead of popping in (§3.2).
6. **Drives and senses:** hunger and warmth, an 8–15 wingspan flower radius, gusts felt in the air by landed butterflies, and flush through the stirred air (§3.3, §3.4).
7. **Traces:** wing downwash on the grass, gold pointer motes, flowers that nod on landing and dim after a visit (§3.5).
8. **Wingbeat safe at 15 fps:** at most fps / 4 drawn, or a default of 0.35 × real (§3.2).
9. **Density by area** (about 4 on a laptop, 9 on a large monitor), plus individual boldness (§3.3).
10. **Rest:** a longer default stay (0.5×), a Rest state, landed breathing and antenna twitches (§3.2, §3.3).