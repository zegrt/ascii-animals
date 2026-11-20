# Meadow port inventory: the sketch mapped against the Swift code

Status: research r2 (read-only), 2026-11-20, of meadow-sketch @ 3f02cb3 and the Swift task branches. The port plan
(docs/plans/2026-11-20-meadow-port-plan.md) is built from it; where they differ, the plan wins.

**Summary:**
- **Most of the side-view Swift code gets replaced.** The breeze, the flowers, the flight and the painter all assume a ground band, gravity on screen y, or wings seen from the side.
- **Reusable as is:** the family shell (`HabitatSim`/`CellPainter`, `WebSim`'s settle pattern, `Settings`, `ThemeParams`, `OceanClock`, `PowerPolicy`, `Terrain`, `WebMath`).
- **Reusable as patterns:** the finite-guard snapshot in `Butterfly.swift` and the painter's grow-only buffers and Calm tone (`Grow`, `Tone`).
- **One change outside the Meadow files looks needed:** a per-cell ground colour in the shared canvas. Without it, the green ground hints and the shadows on bare ground can't be drawn, and the shadows are what carry depth on paper.
- **Still pending:** the Codex review of the sketch (`review-s1`) hasn't landed; `review-s1` is still at `0b18b64`. Its findings may change numbers below.

References: `html:N` is `meadow-sketch:Tools/meadow-sketch/meadow.html` line N. Swift files on task branches are written as `<branch>:<path>:N`. Files on main have no prefix.

## 1. The sketch's model, section by section

### Director's defaults (CONTROLS, html:186–301)

| Group | Defaults |
|---|---|
| Butterflies | count 7, areaCount off, sizeLow 0.75, sizeHigh 1.4, all four species (html:303) |
| Flight | wingbeat 0.5, lurch 2, zigzag 1.29, glide 0.1, speed 2, turning 1.23, bob 1, height 0.5, ease 1 |
| Visits and wants | visits 0.35, stay 0.25, bask 0.2, hunger 1, warmth 1, sense 12 wingspans, touchGo 0.25 |
| Temperament and the air | boldness 1, airClose 60 pt/s, airFlush 120 pt/s, relay 0.6, spaceByHeight on |
| Your pointer | cursorLand on, holdTime 3 s, clickLimit 12, answerGap 5 s |
| Small life | life 1 |
| Traces | downwash 1, nod 1 |
| Flowers | density 0.85, flowerSize 1.32, leaves 0.9 |
| Air and ground | breeze 1.7, shadow 1, green 0.69, grass 1 |
| Look | depth 1, sparkle 1 |
| View | timeScale 1, theme dark, calm off, grid on |

- `S = cw/13`.
- The cell size uses the app's `GridSpec.cell(forWidth:)` formula (html:604; `Sources/OceanKit/Domain/FramePacker.swift:11-14`).

### Breeze and pointer air (html:668–712)

- **Wind direction** turns slowly: `0.35 + 1.1·n1(t·0.013)` rad.
- **Base speed:** `26·S·breeze·(0.75+0.35·n1(t·0.05))`.
- **Gust bands** (html:681–686): two value-noise octaves, 300·S along the wind by 520·S across it, rolling downwind at 0.42 bands/s, `smooth(0.42, 0.82)`.
- **Speed at a point:** `m = base·(0.2+1.7g)`, peaking at about 95 pt/s at breeze 1.7 (report r3).
- **Pointer stir:** a 48·S pt grid (`PG`). Each event adds `v·(1−d)²·0.16` within 3 grid cells, clamped to ±260 (html:704–712). It decays at `exp(−1.6·dt)`, a half-life of about 0.43 s (html:677–678).
- **Downwash:** a second field. Only under a butterfly with z < 0.35: `520·S·downwash·(1−z/0.35)·sinθ·dt`, radius 1.2 spans, clamped to ±200 (html:1490–1500, 1633). A swallowtail on a flower adds 300·S (html:1762).
- **Three air sums:**
  - `wind.x/y` is all the air (grass, flowers, dust, flight drift).
  - `ax/ay` is what a landed butterfly feels (no downwash).
  - `px/py` is the pointer's stir alone (html:668–703).

### Flowers and planting (html:718–895)

- **Seven kinds** (html:719–727), with radius, patch size, weight, f0 and petal count:

  | Kind | r | n | weight | f0 (Hz) | petals |
  |---|---|---|---|---|---|
  | daisy | 66 | 2–4 | 1.4 | 1.5–2.2 | 10–13 |
  | coneflower | 72 | 1–3 | 1.2 | 0.7–1.1 | 10–12 |
  | milkweed | 52 | 1–3 | 0.9 | 0.8–1.2 | — |
  | fennel | 80 | 1–2 | 0.8 | 0.7–1.0 | 6–9 |
  | clover | 38 | 3–5 | 0.5 | 1.8–2.5 | — |
  | mustard | 52 | 1–3 | 0.5 | 1.2–1.8 | — |
  | dandelion | 50 | 2–4 | 1 | 1.6–2.4 | 30–36 |

- **Size:** R = r·S·flowerSize·U(0.82, 1.18). Each flower has a leaf rosette (html:738–751), and mustard has sub-flowers (html:753–757).
- **Planting** (html:766–799):
  - patches = `round(W·H/(190000·S²)·density)`;
  - each patch is the best of 10 candidates for distance from the others, inside a 20·S margin;
  - n blooms per patch within `r·S·flowerSize·(1.6+0.5n)`;
  - no overlap: centres at least `(R1+R2)·1.05` apart;
  - flowers may sit 10 pt past the screen edge;
  - sorted small first.
- **Head spring** (html:882–891): ζ 0.12, force `wind·|wind|·0.0035·(1+0.6·R/30S)`, offset capped at 0.45 R.
- **Growth:** `age += dt/2.2` with an easeOutBack overshoot of 1.4 (html:880, 806, 1199).
- **Feeding lift** (eases at 1.6/s) and a visited disc that dims ×0.85 for 20–40 s (html:877–881, 903–904, 1410).

### Butterfly flight from above, with height z (html:1502–1694)

**Species table** (html:349–366):
- span 22, 26, 22, 15 cells; aspect 0.6, 0.5, 0.62, 0.68.
- Stroke from top to bottom: monarch 80°/−16°, morpho 82/−18, swallowtail 78/−14, white 80/−12.
- Other columns: realBeat, cruise/forage, surge, thrust, bout, glide seconds, jinkChance and sigma, slip, headingK and ζ, bob, maxBank, bound, nectar and bask ranges, baskPose, flutterOnFlower, flower weights.
- `sp.flush` is defined but never used.

**Speed:** `cruise·S·speed·pace`. With speed 2, a monarch cruises at 340 pt/s at 13-pt cells (html:1555). An approach slows to forage pace within 2.2 spans (html:1557–1558).

**Heading:**
- Spring `k = headingK·turning`, critically damped by ζ, turn rate clamped to ±6√turning (html:1605–1608).
- Jinks decay at `exp(−dt/0.9)` (html:1604).
- Free flight wanders by `0.45·n1(t·0.16)` (html:1578).

**Lurch:**
- Spread over the downstroke as `a = thrust·speed·lurch·π·f·sinθ` (html:1620, 1630–1631).
- Drag of 8 pulls toward `max(0.12·speed, speed − impulse·f/8)` (html:1636–1637).
- Swift's `meadow-t5r:Sources/OceanKit/Meadow/Butterfly.swift:392-397` instead gives the whole push as one kick at the clap.

**Clap** (html:1464–1474):
- Jink chance `min(0.95, chance·zigzag)`, spread `σ·jinkF·min(1.6, 0.4+0.6·zigzag)`, both ×0.45 on an approach.
- A sideways slip of `0.3·speed·zigzag·slip·gauss`.
- The white's surge (σ 0.45).
- The morpho's bounds kick its height speed `zv` by ±0.22·bob.

**Height:**
- Target `zBase = height + 0.3·n1(t·0.045) + 0.375·(boldness−1)`, held to 0.06–0.96 (html:1622).
- An approach lerps the target down to 0 (html:1623); the pointer target is 0.92 (html:1624).
- Spring kz 1.4, critically damped (html:1639–1640).
- A glide sinks toward zv −0.08 (html:1650).
- Bob: `z = zs − 0.045·bob·(sp.bob/0.25)·bobAmp·sinθ` (html:1659–1660).

**Glides:**
- They start as the stroke passes the glide pose on the downstroke, once the bout is over (html:1642–1643).
- Length = `glideS·min(1.6, glide)`; the next bout lasts `bout/max(0.3, glide)` beats (html:1449–1460).
- At glide 0.1, a monarch glides 0.15–0.5 s between bouts of 10–27 beats.

**Ground velocity:** airspeed + 0.55 × wind (html:1667). Swift adds the full wind.

**Edges:**
- They steer back once the body is 0.25 span past an edge, with weight 2 (html:1593–1599).
- Leavers fly out through the nearest edge and are removed once out of sight (html:1278–1282, 1517).
- Newcomers enter from an edge, the best of 6 spots, trickling in one every 0.4–0.9 s (html:1250–1269, 1313).

**Spacing** (html:1580–1591):
- Steer apart within 2.4 mean spans, with weight 2.6.
- Pushed apart on touch, at 260·S·dt.
- The height factor `smooth(0.35, 0.15, |Δz|)` softens both across heights.

### Wingbeat and turning

- **Beat:** `f = realBeat·wingbeat·beatF(±10 %)`, ×1.25 in a boost, ×1.15 in wind over 0.3 × speed, capped at `BEAT_CAP` 7.5 Hz (html:367–368, 1561–1566).
- **Defaults:** monarch 4.75 Hz, morpho 3.0, swallowtail 3.5, white 5.9.
- **Drawn width:** each wing is `max(0.1, cos(stroke ∓ bank))` wide (html:1862–1864).
- **Bank:** target `maxBank·0.35·tanh(turn/1.5)` (html:1663–1664).
- **Yaw** with the beat: 0.05·sinθ (html:1859).
- **Underside colour** shows from `smooth(68°, 86°)` of the stroke (html:1873).
- **Soft transitions:** on take-off the stroke blends in over 0.15 s × ease; on landing it eases into the pose over 0.35 s; a brake halves push and stroke over the last stretch (html:1428–1434, 1445, 1617–1620, 1655, 1759).

### Behaviours and wants (html:1320–1447, 1697–1764, 1800–1826)

- **Waypoints:** the best of 9 candidates for distance, separation from others and being ahead; each lasts 4–9 s (html:1322–1337).
- **On arrival** (html:1363–1383):
  - visit chance = `visits·clamp(0.2+1.6(1−energy), 0.2, 1.8)`;
  - bask chance = `bask·clamp(0.45+1.4(1−warmth))`;
  - a bask goes to an open spot, the best of 6.
- **Energy and warmth:**
  - energy falls 0.01·hunger per second in flight and rises 0.08/s while nectaring;
  - after 60 s airborne, warmth falls 0.012·warmth per second;
  - warmth rises 0.12/s basking and 0.02/s otherwise landed (html:1509–1510, 1727–1729).
- **A hungry one** (energy < 0.3) looks for a flower every 0.7 s (html:1548–1551).
- **Choosing a flower** (`pickFlower`, html:1341–1360): within sense × span, not behind (cos ≥ −0.2), not beside a landed butterfly, weighted by the species' flowers and by separation.
- **Approach:**
  - times out after 18 s;
  - touch-and-go: a circle of 1.0–1.6 s at 1.1 spans, a second try, then another flower (html:1675–1681, 1538–1543);
  - lands within 0.12 span and below z 0.1 (html:1690).
- **Landed:**
  - stay = range × stay × boldness, at least 0.8 s (html:1441);
  - poses for cursor, nectar, open, vee and the morpho's closed-with-flash (html:1697–1719);
  - small life: breathing, a shuffle every 4–9 s, an antenna twitch (html:1749–1754, 2239);
  - in moving air: an alert that closes the wings from airClose, a lean, a flush above airFlush × (0.7+0.3·boldness), and a relay to neighbours within 3 spans, two levels deep (html:1731–1742, 1478–1488).
- **Flying through stirred air:** a startle with a boost and a veer (html:1568–1574).
- **Opening moment:** one nectaring, one basking, one about to land (html:1800–1826).
- **Count kept to the setting** through the edges (html:1288–1316).

### Cursor landing (html:1766–1796, 1385–1390, 1525–1536)

- **Trigger:** the pointer still for holdTime 3 s.
  - Still means within 2.5 pt in the code (html:2529); the hint says 2 pt (html:253).
- **Who comes:** weighted by species (swallowtail and white 2, monarch 1, morpho 0.5) over `1 + d/(0.35·diag)`.
- **Spiral in:** 1.5–2.2 loops at a start radius of 1.3–1.9 spans, or 2.4 s per loop.
- **Lands** at z > 0.8 within 0.15 span. It sits "at the glass", z 0.92.
- **On the pointer:** wings held in a 64° vee, opened flat for 1.6 s every 4–10 s. It stays 25–45 s and then leaves (html:1440, 1763).
- **Any move** sends it off in an escape burst; cooldowns are 2 s and 3 s.
- **Pointer leaves:** it takes off (html:1725).

### Clicks (html:801–871)

- **Hit test:** `max(R·grow, 0.35R) + 0.5·cw`.
- **On a bloom, a touch:**
  - a nod of 0.25·R·2π·f0·nod, scaled down if the head is already swung far;
  - a puff of 8 pollen sparks, or 3 if clicked again within 0.5 s;
  - a butterfly on it takes off.
- **On open ground,** a new bloom only if it has room by the planting rule. Otherwise it touches the bloom in the way.
- **New bloom:** 16 sparks, then the click limit.
- **Limit:** beyond clickLimit, the oldest planted flower closes and fades over 2 s.
- **Answer:** one butterfly at a time (7 in 10), never while one is still on its way, and then not for 5 s.
- **A click counts as a move** (html:2533).

### Depth (html:624–639, 1852, 2029–2038, 2204–2234, 2323–2342)

- **Size:** `sizeLow·(sizeHigh/sizeLow)^z`.
- **Shadow:**
  - offset `z·150·S + 3·S` toward the lower right, away from the top-left light (html:906, 1876–1878);
  - strength `shadow·(0.8 dark / 0.9 paper)·(1−0.55z)`;
  - 9 samples, spread `0.3+0.9z`.
- **Butterfly brightness:** dark 1 → 1.14 with z; paper pigment 1 → 1.1.
- **The meadow sits back** (scaled ×0.8 on paper, ×0.75 in Calm):
  - dims to `1−0.3q` (not below 0.3) and desaturates to `1−0.18q`;
  - glyphs flatten toward their block by `0.3q` (up to 0.5);
  - glyphs without a block fade to `1−0.15q`;
  - a fed flower comes forward by `(1−0.45·lift)`;
  - flower sparkle ×1/(1+depth).
- **Rim:** strength `min(1, 0.85·depth)·smooth(0.18, 0.72, z)`, one cell wide, diagonals at 0.55. Blocks sink toward ink (6, 7, 9) in dark and toward the paper on paper; glyphs lose up to 80 % of their alpha.

### The look

- **Mosaic** (html:2446–2511, 2435):
  - blocks inset 1 device pixel, with the ground showing in the strip;
  - grid lines white 5.5 % on dark, ink 8 % on paper;
  - glyphs in Geist Mono SemiBold at `round(ch·0.74)` px.
- **Coverage edges:**
  - 5 samples per cell (html:1111);
  - a block when the centre and at least 3 of 5 samples are covered;
  - otherwise `: ;` from half covered, else `. ' , \``, at level `70+80·cov`;
  - field edges take the field's hue, black-mark edges ×0.6 (html:2065–2074, 1150–1175).
- **Carved ramp:** `:;t%SX8#@`, index `floor((1−shade)·8.99)` ±1 by key (html:2095).
  - Carved ink: dark (14,15,19)/(27,29,36), paper (35,35,35)/(22,22,22), split at shade 0.55 (html:532–535).
  - Wing shade formula and the morpho's specular glint (html:1866–1872, 2079–2083).
  - A four-step field ramp with the underside blend (html:2087–2089).
- **Shimmer** (html:539–560):
  - roll = `hash3(key, floor(t·2.4 + (key mod 997)/97), 7)`;
  - wings and body: 6 % accent, 10 % fleck;
  - edges: 7 % accent;
  - flowers: 3 %/5 % × 1/(1+depth);
  - Calm ×0.35; on paper no accents, flecks in the paper colour; the white has dark flecks and 30 % bare cells.
- **Eyes:** when the span is at least 15 cells, two eyes 0.85 cw beside the head, block level 12 with an `o` (html:2248, 2267–2274).
- **Legs:** when landed with the stroke over 45°, three pairs at Web's leg levels, hidden under wings (html:2278–2293).
- **Antennae:** 0.42 rad, ±0.06·sinθ in flight, `°` clubs, a 0.3 s twitch (html:2295–2309).
- **Proboscis** when nectaring or on the pointer (html:2311–2320).
- **Silk lines:**
  - `lineGlyph`/`lineRow` (html:573–586);
  - veins per species, extra veins only above 10 and 14 cells (html:1973–2009);
  - also petal strokes, fennel rays, leaf ribs, lying grass, legs and antennae.
- **Ground:**
  - black with value-noise green patches × green × 1.15;
  - tufts at `(0.09+0.22·patch+0.08n)·grass`, lying over in gusts above 0.45;
  - cached (html:2358–2407);
  - gold motes where the stirred air is over 60·S pt/s (html:2412–2428);
  - pollen dust (html:2344–2352, 1828–1835).
- **Paper palette, made for paper (round 6):**
  - PAPER (247,246,243), INK (35,35,35);
  - `paperWash = PAPER·(p/255)^a` (html:458–461);
  - `PAPER_WINGS` (html:467–480), body and eye (html:482), `PAPER_PLANTS` (html:486–497), grass (html:498), ground and gold on paper (html:448);
  - cool shadows (html:660); the rim is the paper (html:2226);
  - paper wing cells (html:2153–2202).
- **Calm:** everything ×0.62 toward black or the paper (html:2458–2466). Depth push ×0.75, sparkle and motes ×0.35.

## 2. What exists in Swift on the task branches

| Area | Swift today | Verdict | Side-view assumptions it carries |
|---|---|---|---|
| Breeze | `Breeze` (t1-2/t5r `Meadow/Breeze.swift`); t3 adds `pointerAir` | **Replace**. Keep the finite guards, the typed lets and the idea of a separate pointer field. | Weather "varies only along x, kept per grid column" (:11, `weather()` :161–196); gusts lift on y (:188); prevailing wind only left or right; 0.8 s half-life with blending writes, where the sketch has 0.43 s and additive per-event stir; no downwash field. |
| Flowers | `FlowerKind`, `Flower`, `Meadowland` (`Meadow/Flowers.swift`) | **Replace**; the kind names can stay | Base "always on the bottom edge of rect" (:72); layout along the bottom of every rect (:126–171); stems in rows; `grass` is a plant kind; `verticalLean` (:111, 254); a click blooms in the ground band of its column (:275–289); index-based dip/bloom (t1-2 finding 11: stale indices). |
| Species | `ButterflyKind`, `ButterflySpecies` (`Meadow/ButterflySpecies.swift`) | **Reuse with changes**. Keep the enum, the measured columns, flower weights, shares and cursor weights. | Separate flight size and drawn size (`span`/`drawnSpan` :26–34); beat fixed at real × 0.28 capped at 3 Hz (:36–41); stroke 20 ± 60° (sketch 80/−16); glide angle on screen (:66); `bobRows` in rows (:82); `lift`/`gravity` (:116–122); pitch swing; escape climb angle; bound as a path tilt; `tailRow`; `host`/`pupa` for the life cycle. |
| Flight | `Butterfly` (`Meadow/Butterfly.swift`) | **Replace**. Keep the heading spring and clap structure as reference, and the snapshot/restore finite guard (:79, 146). | Gravity on screen y and downstroke lift (:13–17, 386–438); 65 % of waypoints in the bottom 40 % (:98, 219–240); climb and descend angles (:90–97); glides only above the waypoint (:367); a hard stop on the terrain (:468–486); `fitDrawing` for the preview (:488); morpho bounds rotate the screen velocity; no z, spacing or states. |
| Painter | `MeadowPainter` (t5r `Meadow/MeadowPainter.swift`, 1591 lines) | **Replace**. Keep `Grow` (:50), `Tone` (:70) with its Calm math (matches the sketch's 0.62/0.35), the `Layer`/sprite buffer pattern, the allocation-free discipline, and `paint(...)` setting background and grid from `WebPainter.background`. | Cached ground band of stems (:26, 870–1086, `stem` :1132, `head` :1178); side-silhouette heads; signed wing width with underside below 0, edge-on line, clap fold profile (:14–19, 371–465); hysteresis on coverage (`CellMemory`); antennae standing above the head (:22); palettes from research §5.4, not the sketch's. **No hide shimmer** (confirmed: only pollen and morpho glints at :1220 and :1409). |
| Atlas | t5r appends `(` `)` to `GlyphAtlas` | **Drop**. The sketch uses only the existing glyphs (html:566; report r1 ruling). | — |
| Tools | `Paths.swift` (t1-2), `MeadowStill.swift` (t5r), `MeadowFrames.swift` (t5v), `ProtoFrames/ProtoMeadow/ProtoPainter` (p1, throwaway) | **Replace** with tools driving the new world. Carry t5v's 4 review fixes: refuse a folder that already holds frames, `--seconds 0`, the fps usage text. | Side-view scenes; flight sizes. |
| Checks | t5r `OceanChecks/MeadowChecks.swift` (40 checks); t3 adds 12, not building | **Retire most; re-aim a few** | See below. |

**Checks to retire** (side view or replaced design), with t5r line numbers:
- flowers and stems: `flowersOnEveryRectBottom` :158, `stemsRingAndSettle` :125 (stems), `stemsLeanWithTheBreeze` :1143, `flowerSeekersReachLowHeads` :712, `lowFlowersKeepTheirReach` :1604;
- flight: `bodyBobsInRange` :489 (rows), `liftOnlyOnDownstroke` :541, `flightPathsMatchMeasurements` :789 (the glide ratio on screen), `butterfliesStayInside` :607 (hard stop), `freeFlightCoversTheField` :657, `freeFlightRoamsATinyScreen` :675;
- ground band: `groundRedrawsOnlyWhatMoved` :1265, `relayoutRedrawsTheGarden` :1290, `plantsStayOnTheirScreen` :1308, `subPixelRelayoutRedraws` :1543;
- wings: `wingsUseSignedWidth` :992, `edgeOnIsALine` :1027, `closedWingsShowTheUnderside` :1481, `clapReadsAsAButterfly` :1651, `clapTurnsOverAtEveryBank` :1749, `foldedSideNeverFlips` :1773;
- preview and placement: `oneButterflyFitsThePreview` :1518, `previewSizeFitsEveryLean` :1873, `bodyDrawnWhereItFlies` :1817.

**Checks to re-aim:**
- air: `breezeHalfLife` :57 (to 0.43 s), `breezeWriteIsLocal` :89;
- determinism and robustness: `meadowlandDeterministic` :213, `badInputStaysFinite` :755, `weatherAndLeanScaleWithCell` :284;
- flight: `wingbeatRates` :471, `monarchCalmerThanWhite` :557;
- look: `wingsDoNotFlicker` :959, `whiteVisibleOnPaper` :1067, `meadowCalmIsDimmer` :1098;
- rendering: `paintAllocatesNothing` :1224, the GPU check `meadowComposeDraws` :1407;
- from t3: `densityAndMix`, `butterfliesFeed`, `mostButterfliesFly`, `butterfliesKeepApart`, `butterfliesRoamTheScreen`, `fastPointerFlushes`, `gustClosesWings`, `landingDipsStem`, `meadowWorldDeterministic`, `pointerLeavesATrail` (`staleFlowerIndex` becomes moot with ids).

## 3. How Ocean and Web are built, and what the Meadow should reuse

- **Habitat shell:**
  - `HabitatSim` (`Sources/OceanKit/Domain/HabitatSim.swift:5-18`) and `Habitats.make`/`needsRebuild` (:20-36).
  - Web is the model to copy: `WebSim: CellPainter` holds a world and a painter, a `fresh` flag, `settle()` that restarts the random stream and steps 120 times, and `stepCount` (`Sources/OceanKit/Web/WebSim.swift`).
  - Ocean uses its own GPU path (`World.swift`, `FramePacker.swift`, `Shaders.swift` `compose_main`). The Meadow should take Web's route: `MeadowSim` (CellPainter) + `MeadowWorld` + `MeadowPainter`.
- **Canvas** (`Sources/OceanKit/Render/CellCanvas.swift`, `Shaders.swift:652-696` `canvas_main`):
  - Blocks are inset 1 pt with the grid drawn underneath, glyphs and overlay glyphs on top; the dissolve's reveal comes for free.
  - **The background is one colour for the whole canvas.**
- **Settings** (`Sources/OceanKit/Domain/Settings.swift`):
  - Decoding is tolerant per field (:64-101) and `sanitized()` clamps (:46-57). The plan's Meadow settings slot in the same way.
  - Already global: `appearance`, `calm`, `grid`, `fps` [15, 30, 60], `sharedOcean`, `interaction`, and `speed` 0.5–1.5, which is the clock's speed (`ASCIIAnimals/OceanDirector.swift:106`). These cover the sketch's theme, Calm, grid and time scale.
- **Theme and Calm:** `ThemeParams.make` gives brightness 0.62 and accent rate 0.35 in Calm (`Domain/Theme.swift`), the same numbers the sketch uses (html:541, 2458). The background and grid come from `WebPainter.background` (`Web/WebPainter.swift:917-923`); the sketch's grid alphas match it.
- **Energy and fps:**
  - `PowerPolicy` runs 30 fps, or 15 fps on battery, Low Power or thermal pressure; a still for Reduce Motion (`Domain/PowerPolicy.swift:49-66`).
  - `OceanClock` always steps 1/60 s with at most 4 catch-up steps and the speed applied (`Domain/OceanClock.swift`). At 15 fps that is exactly 4 steps a frame, so the simulation never depends on the frame rate.
- **Multi-screen:**
  - `SceneLayout.plan`: shared means one `Terrain` of rects with one cell size, the widest screen's; separate means one scene per screen (`Domain/SceneLayout.swift:31-47`).
  - `Terrain` (`Domain/Terrain.swift`) gives only real edges as walls, plus `wallPush`, `contains`, `nearestInside`, `signedOutside`, `rectIndex` and doorways.
  - Web's helpers `screenByArea`, `wallByLength`, `clear`, `inside`, `loose` and `wanderGoal` (`Web/WebWorld.swift:300-373`) are what the sketch's W×H code needs. They are internal methods of `WebWorld`: copy them into the Meadow, or move them to a new Terrain extension file without touching Web.
- **Pointer:**
  - `PointerMonitor` reads mouse moves, drags and left-button downs only; a window, the menu bar or the Dock under the pointer gives "no target", which becomes `pointerLeft()` (`ASCIIAnimals/PointerMonitor.swift`, `Domain/PointerRouter.swift:16-24`, `OceanDirector.swift:261-274`).
  - Web works out the pointer's velocity per step from the position change (`WebWorld.swift:241-256, 283-289`). The Meadow should do the same.
  - The welcome tour drives `sim.pointerMoved` and `pointerDown` (`ASCIIAnimals/OnboardingController.swift:76-78`).
- **Helpers to reuse:** `WebRandom`, `hash3`, `noise1`, `angleDiff`, `clamp`, `lerp`, `smoothstep`, `ease` (`Web/WebMath.swift`); `StrokeAcc` is internal and usable for silk lines (`WebPainter.swift:151`); Web's grow-only buffers, frame stamps and pre-packed inks.
- **Tools:** `OceanTool still|frames|bench [--habitat]` and `bench --digest` (`Sources/OceanTool/main.swift:1-15`) work with any CellPainter habitat once `.meadow` exists.
- **Adding `.meadow`** means updating these switch sites: `OceanStatus.swift:64`, `OnboardingController.swift:513,784,825`, `SettingsView.swift:97,181,195`, `StatusMenu.swift:118,140,312`, `HabitatSim.swift:25`.

## 4. What must change for Swift: frame rate, randomness and web-only parts

1. **Fixed step.** The sketch steps at 60 Hz with up to 8 catch-up steps and a 0.1 s clamp (html:2665–2675). The app's clock does the same with 4 catch-up steps. Every spring and decay is explicit Euler tuned at dt = 1/60, e.g. heading k up to 74, flower ζ 0.12 (html:1606, 887–889). Never step at the frame's dt.
2. **Wingbeat against the drawn frame rate.**
   - The 7.5 Hz cap means 4 frames a beat at 30 fps.
   - At 15 fps the defaults alias: white 2.5 frames a beat, monarch 3.2, swallowtail 4.3, morpho 5.
   - The beat also drives the physics (lurch, clap, jinks). Capping it by fps would make motion and digests depend on fps.
   - The family-details note (§4 item 8) suggests "at most fps/4". Not decided.
3. **Pointer stir is per event.** It adds `v·w` per DOM event, with velocity from the wall-clock gap (html:2518–2525), so the result depends on the event rate. Swift should compute the velocity per step from the position change and write once per step, as Web does.
4. **Pointer input differs.**
   - Still is 2.5 pt per event (html:2529). The still timer runs on simulation time (html:1771), which is fine.
   - A click is a pointer-up after less than 6 pt of movement (html:2531–2533). The app has mouse-down only.
   - Pointer-leave maps to `pointerLeft()`, which also fires over windows.
5. **Unseeded and engine-dependent.**
   - The seed comes from `Math.random` unless `?seed` is given (html:147).
   - `sort(() => rnd() − 0.5)` at html:1309 and 1801 needs a seeded Fisher–Yates shuffle.
   - Global ids (`flowerId`, `flyId`) must live in the world.
   - Replanting on a window resize over 80 pt (html:2714), and a 120 ms debounced replant on a slider change (html:2554).
6. **The hash is not the same.** The sketch's `hash3` (html:158–162) is not Swift's `WebMath.hash3` (`WebMath.swift:34-40`). Glyph, shimmer and grass patterns won't match the sketch pixel for pixel unless the port uses the sketch's hash.
7. **Per-cell ground.**
   - The sketch draws the ground's colour per cell, including in the strip under each block, and shades it for shadows (html:2462–2466, 656–662).
   - `canvas_main` has one background colour. Without a per-cell ground layer, the green hints and all shadows on bare ground are lost, and shadows are central on paper (round 6).
   - Drawing the green as blocks would tile it (round 2 ruling: the ground is the background).
8. **Allocations every frame:** `flies.slice().sort` (html:2449), `filter`/`some`/`map` in step and sync (html:1843, 1289–1316, 834, 860), dust `push`/`splice` (html:830, 1830). Swift needs fixed pools and pre-sized arrays.
9. **Cost:**
   - `windAt` (two value-noise calls) for every grass cell every frame (html:2391);
   - 5 samples × polygon tests plus an edge pass per wing cell;
   - 5 samples per cell over every flower's box every frame.
   - The family-details §3.7 suggestion: sample the air on the 48-pt grid, rasterise each flower once and repaint it only when its head moves 0.25 cell, and mask wings at 2× resolution.
10. **Web-only parts:** the panel, `localStorage`, the URL parameters (`seed`, `warm`, `freeze`, `sheet`, `debug`, `theme`, `s.*`), `performance.now` stats, `devicePixelRatio` capped at 2, `fillText` with a +1 baseline. The `?sheet=flowers|flies` and `?warm/freeze` aids are worth keeping as OceanTool options.
11. **Single-rectangle code.** Everything that reads `W`/`H` assumes one screen:
    - planting (html:766–799), spawn and entry and exit (html:1222–1282), waypoints (html:1322–1337), bask spots (html:1375–1380);
    - `wantedCount` (html:1284), the edge steer (html:1593–1599), the flower bounds in `pickFlower` (html:1347), the opening moment, the cursor's diagonal (html:1774), the ground.
    - All of it must work per terrain rect, with only real edges as walls, no points in gaps, and a shared cell that is the widest screen's.

## 5. Proposed task breakdown

**Base:** I'd build a fresh stack from main (meadow-m1 …). It would supersede t1-2, t5/t5r, t5v, t3, t5w, p1 and p2a, which stay as references and are deleted at the end with the director's OK. This goes against the board's decision to stack from meadow-t1-2 (Decisions, 2026-11-20). It's suggested because every one of t1-2's four model files is replaced, so a stack on t1-2 would review whole-file rewrites.

**Shared registration files:** `OceanChecks/main.swift` and `OceanTool/main.swift` are single registration points. A task that touches them starts only after the previous task that touched them has been reviewed.

1. **M1 Material: air and flowers from above.**
   - Files: `Meadow/Breeze.swift` (replace), `Meadow/Flowers.swift` (replace), `Meadow/MeadowTuning.swift` (new: every sketch default and constant in one place), `OceanChecks/MeadowChecks.swift` (new), `OceanChecks/main.swift` (registration).
   - Supersedes t1-2's Breeze and Flowers and t3's `pointerAir`.
   - Checks:
     - same seed gives the same air and flowers;
     - stir half-life about 0.43 s, and stir stays local;
     - the same pointer path fed at 15, 30, 60 and 120 Hz gives the same air within 5 %;
     - downwash only under z < 0.35;
     - wind at breeze 1.7 peaks at 90–100 pt/s;
     - no flower centre in a gap of the two-rect terrain, and no overlap below 1.05;
     - the spring rings at f0 with ζ 0.12 and stays within 0.45 R;
     - repeated clicks on one spot touch, never stack;
     - at most clickLimit flowers planted, the oldest fading over 2 s;
     - finite on bad input.
2. **M2 Flight from above.**
   - Files: `Meadow/ButterflySpecies.swift` (revise), `Meadow/Butterfly.swift` (replace), `OceanChecks/MeadowFlightChecks.swift`, `OceanTool/Paths.swift` (a top-down track picture), `OceanTool/main.swift`.
   - Checks:
     - beat = real × 0.5 within ±10 %, never over 7.5 Hz;
     - the ground-speed pulse each beat (lurch);
     - the monarch's heading variance below the white's;
     - glide share at glide 0.1;
     - z always in [0, 1] with the bob amplitude;
     - coverage of a 180-pt grid over 3 minutes;
     - the body never more than 0.25 span past a real edge and never in a gap;
     - deterministic and finite.
3. **M3 Per-cell ground in the canvas (only if approved).**
   - Files: `Render/CellCanvas.swift`, `Render/OceanRenderer.swift`, `Render/Shaders.swift`, `OceanChecks/CanvasChecks.swift`.
   - Its files don't overlap M1 or M2, so it can run alongside them.
   - Checks: `oceanStillUnchanged`, the Web cross-checks and the `bench --digest` canvas fingerprints stay identical; a Meadow test canvas shows the ground colour under the block strip and in empty cells.
4. **M4 Painter: meadow and ground.**
   - Files: `Meadow/MeadowPainter.swift` (replace: compositor, buffers, `Tone`, ground, grass, motes, flowers, leaves, flower shadows, dust, depth push, shimmer), `Meadow/MeadowInks.swift` (new: dark and paper palettes and cell writers), `OceanTool/MeadowStill.swift` (replace: flower sheet and still), `OceanTool/main.swift`.
   - Checks: `paintAllocatesNothing`; `meadowCalmIsDimmer`; the GPU check `meadowComposeDraws`; the far push dims flowers against a reference; no accents on paper; flowers cached when still.
   - Films: a flower sheet and stills, dark and light, next to the sketch's `?sheet=flowers`.
5. **M5 Painter: butterflies.**
   - Files: `Meadow/ButterflyPainter.swift` (new: wings, pattern, veins, shimmer, body, eyes, legs, antennae, proboscis, shadow, rim), one call site in `MeadowPainter.swift` (after M4's review), `OceanTool/MeadowStill.swift` (a butterfly sheet at z 0.05, 0.5 and 0.95 and four phases).
   - Checks: `wingsDoNotFlicker` re-aimed; `whiteVisibleOnPaper`; eyes only from 15 cells; the rim only above z 0.18; legs hidden under wings; allocation-free.
   - Films: sheets against `?sheet=flies`.
6. **M6 World and behaviours.**
   - Files: `Meadow/MeadowWorld.swift`, `Meadow/Behaviour.swift`, `OceanChecks/MeadowWorldChecks.swift`, `OceanTool/MeadowFrames.swift` (replace, with t5v's 4 fixes).
   - Covers: wants, waypoints, flower choice, approach and touch-and-go, landed poses and small life, gusts, flush and relay, spacing, count sync through real edges, opening moment, settle, per-rect multi-screen.
   - Checks:
     - `densityAndMix`, `butterfliesFeed`, `mostButterfliesFly` (at least about 70 % flying at the defaults), `butterfliesKeepApart`, `butterfliesRoamTheScreen`;
     - `gustClosesWings` (60 pt/s) and flush at 120 × boldness;
     - newcomers and leavers only through real edges;
     - a relayout from two rects to one and back keeps everyone inside;
     - 30-minute long run finite;
     - deterministic.
   - Films: 60 s, dark and light, at 30 and 15 fps. This is where the wingbeat-at-15-fps question gets decided.
7. **M7 Pointer and clicks.**
   - Files: `Meadow/MeadowPointer.swift` (new), hooks in `MeadowWorld.swift` (after M6's review), `OceanChecks/MeadowPointerChecks.swift`, `OceanTool/MeadowScript.swift` (the `--interact` script).
   - Checks:
     - `cursorLanding` (within about 12 s one sits within a cell at z 0.92; a 3 pt move sends it off next step);
     - `noLandingOutsideTerrain` (plan Review Focus 1);
     - the click pile-up (one answers at a time, the 5 s gap);
     - `fastPointerFlushes`.
   - Film: the `--interact` film.
8. **M8 Habitat, settings and tools (plan T6).**
   - Files: `Meadow/MeadowSim.swift`, `Domain/HabitatKind.swift` (`.meadow` and the `offered` list), `Domain/HabitatSim.swift`, `Domain/Settings.swift`, `OceanChecks/SettingsChecks.swift`, `OceanTool/main.swift`, and minimal `.meadow` cases in `OceanStatus.swift`, `OnboardingController.swift`, `SettingsView.swift` and `StatusMenu.swift`.
   - Checks: plan T6's six checks, including the 340×150 tiny viewport and the two-rect relayout; Ocean and Web unchanged.
   - Films: plan T6 step 3.
   - Plan T7–T10 follow unchanged in shape.

## Open questions for the director

1. **Stack base:** a fresh stack from main, superseding the side-view branches, or keep stacking on meadow-t1-2 as the board says?
2. **Per-cell ground (M3):** a change to the shared render code (Ocean and Web must stay identical), or accept losing the green hints and the shadows on bare ground, especially on paper?
3. **Wingbeat at 15 fps:** accept the aliasing, lower the default, or cap by fps (which makes the motion depend on the frame rate)?
4. **Monarch life cycle** (plan T4): its J-hang chrysalis is a side-view image. Drop it, redesign it from above, or defer it? Courtship chases (plan) and cross-screen travel are also not in the sketch.
5. **Multi-screen:** cross between touching screens, with the monarch's ×3 preference? Is the count per screen or per scene? Shared scenes use the widest screen's cell size.
6. **Edges:** the sketch lets the body go 0.25 span past an edge, and leavers fly fully out. The decision of 2026-11-20 says only the body stays on a screen. Keep the sketch's behaviour on real edges only?
7. **User settings:** species and how many, as count or as density (plan: density 0.5–1.5, cap 16; sketch: count 7 with area scaling off). Does "land on a still pointer" go under the global `interaction` setting? Everything else becomes constants in `MeadowTuning`.
8. **Confirm small rulings:**
   - the pointer-sitter at z 0.92, leaving after 25–45 s;
   - the still threshold: 2 pt in the hint, 2.5 pt in the code;
   - `sp.flush` is unused;
   - match the sketch's hash for pixel parity, or compare by eye?
