# Meadow — research

Status: research for the Meadow plan (ASCII Animals 3.1) · 2026-11-19

The Meadow has no original to port, so this is its foundation: what real butterflies do, in numbers, and how
those numbers become a 60 Hz simulation drawn as cells in the Web's hand (block-and-glyph cells, `SKIN_RAMP`,
the line glyphs `- _ ¯ / \ |`, Dark/Light/Calm). Values marked **(est.)** are this document's estimates where
no source gave a number; everything else cites a source (list at the end). The design's owner decisions are
taken as given: always daytime; monarch, blue morpho, swallowtail, cabbage white in toned-down real colours;
flowers along the bottom plus scattered flowers swaying in a breeze field the pointer writes into; click blooms a
flower; hold still and a butterfly lands on the cursor; a life cycle within minutes; nothing saved; butterflies
cross touching screens, monarchs preferring to; never simpler motion; CPU ≤ the Ocean's.

**Reading the grid.** Canvas habitats use `cw = clamp(round(W / 124), 8, 13)`, `ch = round(cw · 1.45)`: 13 × 19 pt
on screens ≥ ~1550 pt wide, 12 × 17 on a 1440-pt laptop. Spider bodies are ~3–4 cells, their legs span
~12–15 cells. Size butterflies **in cells** (they then read the same on every screen) and speeds in pt/s.

---

## 0. The five findings that shape the design

1. **Real butterflies are too fast for a wallpaper; the Meadow must be shown in slow motion, with two time
   scales.** Real cruising: 1–5 m/s at ~10 Hz, i.e. 2–4 wingspans *per wingbeat*. At our size (a monarch ≈
   13 cells ≈ 170 pt) that is >1,500 pt/s. Recommended: wingbeats at **~0.28× real** (≈ 1.7–3 Hz on screen:
   ≥ 5 frames per beat even at 15 fps, so no strobing) and travel at **~0.4–0.7 wingspan per beat**
   (≈ 70–260 pt/s), about a fifth of the real advance per beat. It reads as "close-up, slowed down", not as
   slow animals.
2. **Lift comes in on the downstroke, thrust on the upstroke clap.** Butterflies support their weight on the
   downstroke and get forward thrust from a clap of cupped, flexible wings at the top of the upstroke
   (Johansson & Henningsson 2021). Body pitch swings in step with the beat (≤ ~25° per half-stroke) and the body
   bobs (Bode-Oke & Dong 2020; Tejaswi et al.). Drive the sim with per-beat forces, not a sine added to a path.
   The bobbing and lurching path then falls out of the physics.
3. **Erratic is a species trait, not a constant.** Palatable butterflies fly fast and erratically; distasteful
   ones (the **monarch**) fly slowly and regularly and glide (Chai & Srygley 1990; Srygley & Dudley 1993;
   Kassarov 2004). Cabbage white: almost continuous flapping, sharp jinks (mean turning acceleration about the same as
   its forward acceleration, 7.6 vs 8.5 m/s², Jantzen & Eisner 2008). Monarch: bouts of flaps then glides at
   ~3.6:1 (Gibo). The blue morpho (*M. peleides/helenor*, an understory species) bounds with powerful flaps and
   short glides, its blue upper side and brown underside flashing in turn. Swallowtails beat strongly and glide often.
4. **The blue morpho doesn't visit flowers.** Adults feed on rotting fruit and tree sap, sit with wings closed
   (brown, eyespotted underside), and show the blue mostly in flight (UF/EDIS IN1101; Florida Museum). To be
   true to it, give morphos fallen fruit or a sap spot to sip, and rest them wings-closed. (Open question for the owner.)
5. **Pupae differ by family, which gives each species its own chrysalis scene.** Monarch and morpho
   (Nymphalidae) hang head-down from a silk pad after a J-hang. Swallowtail and cabbage white (Papilionidae,
   Pieridae) are girdled: tail pad plus a silk belt, held at an angle on a stem. Monarch J-hang lasts 12–48 h,
   the skin is shed in minutes, the chrysalis (jade, gold dots) lasts ~8–15 days and darkens to show the wings
   before eclosion. A new adult pumps its wings and hangs to dry for an hour or more before first flight.

---

## 1. Flight mechanics

### 1.1 Measured numbers

| | Monarch *Danaus plexippus* | Blue morpho *Morpho peleides / helenor* | Swallowtail *Papilio* (machaon / glaucus) | Cabbage white *Pieris rapae* |
|---|---|---|---|---|
| Wingspan | 8.9–10.2 cm | ~9.5–12+ cm (genus to 20 cm) | 7–10 (machaon), 8–14 cm (glaucus) | 4.5–6.5 cm (ADW) |
| Wingbeat | **~9–10 Hz**; 10.2 Hz measured (Tejaswi et al.); 7.4–13.6 Hz across sequences, ~9 typical (Bode-Oke & Dong 2020) | **≈5–7 Hz** (est.: Le Roy 2021 Fig. 1 plots 0–8 Hz and reports "little variation" between species; check the Dryad data) | **≈5–8 Hz** (est.): *P. machaon* is claimed as the slowest insect wingbeat, ~5 Hz (Guinness, unverified); neotropical butterflies average 11 Hz (Dudley 1990) | **11.8 ± 2.1 Hz** (Jantzen & Eisner 2008); 12.8 Hz (secondary) |
| Stroke amplitude | ~130° (Bode-Oke & Dong) | — | — | — ; butterflies average 103° (Dudley 1990) |
| Speed | forward 0.9–1.75 m/s in the lab (Bode-Oke & Dong); up to ~5 m/s near the ground (secondary); ~5 knots (2.6 m/s) gliding (Gibo) | understory species fly faster, straighter, at higher advance ratio than canopy ones (Le Roy 2021) | strong, fast; "often gliding with only occasional beats" (UC ANR) | **2.37 ± 0.44 m/s** free flight (Jantzen & Eisner); migrants 1–4 m up at ~8 km/h |
| Flap vs glide | flaps near the ground, glides/soars higher; glide ratio **3.6:1** (≈15.5°), 7:1+ in weak lift; flap-glide-soar switching within one flight (Gibo) | canopy species glide ~half the time; understory (incl. *helenor*) much less; **glide angle 11° ± 1° understory, 7° ± 2° canopy**; climb angle 13° vs 22° (Le Roy 2021) | frequent gliding (est. 20–40 % of time) | almost continuous flapping (est. < 5 % gliding) |
| Turning | regular, few jinks (unpalatable) | bounding, abrupt changes of height | strong, wide turns, some jinks | normal acceleration **7.6 ± 2.1 m/s²** (horizontal 5.2), radius of curvature 1.17 ± 1.58 m (log-normal); zig-zag needs the hindwings |
| Body | pitch swings ≤ ~25° per half-stroke, nose down on the downstroke and up on the upstroke; abdomen lags the body pitch by ~90° (Tejaswi et al.; Bode-Oke & Dong) | climbs steeper with higher body pitch (Le Roy 2022) | — | — |

### 1.2 What makes the flight "fluttery" and erratic

- **Big slow wings move the body.** The wings carry a large share of the inertia, so the body bobs
  vertically every beat and pitches in step with it, giving the "bumpy" path (Tejaswi et al.). The monarch's abdomen undulates
  a quarter-cycle behind the thorax and steadies it.
- **Downstroke for weight, upstroke clap for thrust.** The wings cup on the upstroke and clap together, pushing a
  backward jet; flexible wings give +22 % impulse and +28 % efficiency over rigid ones (Johansson &
  Henningsson 2021). On screen this is a rise during the downstroke and a small forward lurch at the top of the
  upstroke, once per beat.
- **Deliberate unpredictability.** Palatable species fly fast with irregular paths. Distasteful ones fly slowly
  and regularly in straight lines, with a long abdomen and the centre of mass behind the wing base (Chai &
  Srygley 1990; Srygley & Dudley 1993; Kassarov 2004 review). The link between palatability and path
  irregularity is weaker than the link with speed (Horisawa et al.), so vary it by species and individual.
- **The hindwings do the jinking.** Without hindwings *P. rapae* still flies and zig-zags, but more slowly
  (speed 2.37 → 1.77 m/s, normal acceleration 7.6 → 5.4 m/s²) (Jantzen & Eisner 2008). The jinks are
  per-beat events.
- **Height and habitat.** Gliding is "seldom circular": gliders keep straight and turn toward flowers or trees
  near the ground. Monarchs switch back to flapping 1–3 m above the ground and soar in small thermals 10–30 m
  up (Gibo). In a meadow close-up, expect flapping, short glides and turns toward flowers.
- **Preferred direction.** Egg-laying *P. rapae* females keep a preferred direction for the day, and their
  moves fit a correlated random walk with turning angles peaked at 0 (Kareiva & Shigesada 1983; Root &
  Kareiva 1984). Migrating monarchs hold a heading for hours. This supports "monarchs prefer to cross screens".

### 1.3 Species flight signatures (what must read at a glance)

| | Signature | On screen |
|---|---|---|
| Monarch | sails: 3–8 flaps then a flat glide (wings slightly up in a shallow V), long straight legs, gentle turns | the "calm" one; most screen crossings |
| Blue morpho | slow, deep, bounding beats; height changes every few beats; **blue/brown flash** as the upper and lower faces alternate; short shallow glides | biggest, slowest beat, a flicker of colour, not of position |
| Swallowtail | strong, deliberate beats with floating glides; the tails trail; **keeps fluttering its forewings while nectaring** (UC ANR) | powerful, then hangs in the air |
| Cabbage white | small, low, fast-beating, never still in the air, zig-zags every beat or two, short hops between flowers | the restless one; the most "flutter" |

### 1.4 Turning the numbers into a 60 Hz sim at screen scale

**Two time scales** (the key decision, see §0.1):

| Quantity | Real | Screen (recommended) | Why |
|---|---|---|---|
| Wingbeat | 5–12 Hz | **real × 0.28, capped at 3 Hz** → monarch 2.6, morpho 1.7, swallowtail 2.0, white 3.0 Hz | ≥ 5 frames per beat at 15 fps, ≥ 10 at 30 fps; nothing strobes |
| Advance per beat | 2–4 wingspans (cruise), ~0.7 (foraging, est.) | **0.4–0.7 wingspan** (cruise), **0.15–0.3** (foraging) | crossing a 2560-pt screen takes ~10–20 s, like the flies (60–120 pt/s) and sharks |
| Escape burst | — | beat × 1.25, speed × 2 for 0.6–1.2 s, climb 13–22° (Le Roy 2021 ascent angles) | a flush reads as a startle |
| Glide sink | 3.6:1 monarch (15.5°), 7–11° morpho | the same angles | angles don't depend on time scale |
| Body bob | "considerable" (no number) | **± 0.2–0.35 row** (4–7 pt) per beat (est.) | visible through edge-glyph coverage, rarely a whole row |
| Body pitch | ≤ ~25° per half-stroke | **± 12–20°** about the path angle, nose down on the downstroke | |
| Turning | white: a_n ≈ a_t; mean radius ~20 wingspans, sharp jinks far tighter | heading on a spring (spider `steer`, k ≈ 30–60, ζ ≈ 0.9); jinks as per-beat kicks to the target heading | per-beat kicks are what the hindwing result says |

**A per-beat force model** (est.; tuned by eye against the numbers above):

```
phase θ += 2π f dt                          // f per individual (±10 %), × 1.25 in escape, × 0.9 tired
stroke φ(θ) = φ_mid + A·cos θ               // A ≈ 60° (120° total), φ_mid ≈ +20°; wings up at θ = 0 (clap)
downstroke (sin θ > 0):  a_up   += L · sin θ        // weight support; L set so lift averages ≈ g_eff
clap (θ crossing 0):     v_fwd  += T                // one forward lurch per beat
always:                  a_y    -= g_eff;  v ← v − c·(v − v_target)·dt  (air drag toward the wanted airspeed)
jink (at each clap, p_jink): heading_target += N(0, σ_jink) (± vertical kick for the morpho)
glide: φ held at +8°…+15° (shallow V), no lift impulses, sink along the species glide angle
wind: ground velocity = air velocity (breeze field) + airspeed vector
```

`g_eff` and `L` are screen-scale, chosen so the bob is ± 4–7 pt at the displayed beat: amplitude ≈ a_osc / (2πf)²,
so at 2.6 Hz a ±5 pt bob needs a_osc ≈ 1,300 pt/s². Jink and glide parameters per species are in the
Recommended parameters table.

**View and wing foreshortening.** Model each wing as a plane hinged on the body axis, with the bank ρ (how the
stroke plane is rolled toward the viewer) as a per-butterfly state that follows turns. The two wings sit at
angles ρ + φ and ρ − φ, so each has its own **projected width** `s = cos(angle)` and its own **visible face**
(`sign`: upper or under). Two cosines per butterfly per frame give:
- the flap as width: wide (wings level) → narrow (edge-on at the clap) → wide;
- asymmetry in banked turns (one wing wide, the other a sliver);
- **the morpho flash for free:** the faces alternate, so the blue upper side and brown underside swap
  through the beat and in turns (the "appearing and disappearing" described by Florida Museum/Saint Louis Zoo
  sources).

---

## 2. Behaviours and timings

Real durations are compressed to **sim seconds** that feel natural on a desktop. Behaviour time isn't slowed like
the wingbeat: a 30 s bask reads as a bask.

| Behaviour | Real biology | Screen (sim s) |
|---|---|---|
| **Nectaring: approach** | decelerates, extends legs, a few short beats, lands; often a touch-and-go | slows to foraging speed within ~2 wingspans; 1–3 short beats; **abort and retry ~25 %** (est.) — the "hesitation before a lunge" |
| **Nectaring: on the flower** | uncoils the proboscis, probes florets across the head; dwell from **2 s** (field records) to minutes (a lycaenid averaged 390 s); handling time drops with experience, so *P. rapae* gets faster on a familiar flower species (Kandori & Ohsaki 1996) | proboscis glyph appears after 0.4–0.8 s; **dwell 6–40 s**, shorter on flowers it knows; shuffles 0–2 times within the head; monarch/white wings closed or slowly fanning, **swallowtail forewings keep fluttering** (small 1–2 Hz width wobble) |
| **Flower choice** | monarch: milkweeds, then composites (coneflower, goldenrod, blazing star), red clover, lantana (BAMONA); white: mustards, dandelion, red clover, asters, mints (ADW); swallowtail: umbellifers, thistles, milkweed (est.); morpho: **rotting fruit, sap, not flowers** (EDIS IN1101) | species weights per flower type (Recommended table); each individual favours what it has fed on (flower constancy) |
| **Dorsal basking** | wings open flat to the sun; monarch tilts wings toward the sun; flight muscles must reach ~13 °C (Journey North); butterflies fly at 28–42 °C thorax, vigorous flight 33–38 °C | monarch & swallowtail: wings fully open, still, **10–40 s**; after emerging; after long flights; in morning-like starts (first ~30 s after launch everyone basks briefly) |
| **Reflectance basking** | *Pieris* hold the wings in a V and bounce sunlight onto the body (Kingsolver 1985); need thorax 29–40 °C to take off | cabbage white basks with wings at **~40–60° V** (s ≈ 0.5), 8–25 s |
| **Lateral basking / wings closed** | morphos sit with wings closed, the brown eyespotted underside cryptic | morpho rests wings-closed **20–90 s**, opening briefly (0.5 s flash) every 10–30 s (est.) |
| **Resting / roosting** | wings closed, still | any species, 15–60 s, wings closed, a slow "breathing" open-close every 6–15 s (est.) |
| **Puddling** | mostly **males**, especially swallowtails and pierids, at damp soil, dung or sweat, for sodium | males of swallowtail & white sip at a damp patch (or the cursor) |
| **Landing on people** | puddling on sweaty skin; swallowtails and brush-foots most often | the cursor-landing gesture: swallowtail & white weighted ×2, monarch ×1, morpho ×0.5 |
| **Patrolling vs perching** | *P. rapae* males patrol all day round host plants; male search activity tracks sunlight; males bask first in the morning (Hirota et al. 2000) | whites patrol low loops over the mustards; monarchs perch on a tall flower and sally out; swallowtails patrol wider |
| **Courtship** | male pursues female; a mated female *Pieris* adopts the **mate-refusal posture** (wings spread, abdomen raised perpendicular) and he leaves; females can shake males off with an **ascending flight** up to ~20 m; monarch males pursue and take females down | two butterflies of one species meet (~1 per 2–4 min per screen): a **chase of 2–6 s**, sometimes **a rising spiral of 3–8 s** (two bodies circling about a common rising centre, radius 1–2 wingspans), then they part; a landed white may refuse with the posture (wings flat, abdomen glyph raised) |
| **Flush (approach)** | flight initiation distance is species-specific and grows with starting distance (Harbour et al. 2019); typically ~1–3 m for a walking person (est.) | landed butterflies flush when the pointer comes within **2–3 cells (slow pointer < 150 pt/s)** to **5–8 cells (fast > 600 pt/s)**, scaled by the individual's boldness ×0.6–1.6 |
| **Gusts** | weak fliers; most displacement is simply wind; insects recover attitude within ~9 beats after big perturbations (soldier fly) | airborne: drift with the breeze, bank toward it, beat +20 %, heading spring pulls back over ~1–2 s. Landed: wings close and the body flattens above a threshold; flush above 2× it |

---

## 3. Life cycle (compressed into minutes)

### 3.1 Per species

| | Monarch | Blue morpho | Swallowtail (*P. machaon* recommended, see §8) | Cabbage white |
|---|---|---|---|---|
| Host plant | milkweed (*Asclepias*) | legumes (Fabaceae, e.g. *Machaerium*) | umbellifers: fennel, wild carrot, dill (machaon/black swallowtail); trees for the tiger | mustards, cabbage family, wild radish |
| Caterpillar | white, black and yellow bands; a pair of black filaments at front and back; ~5 cm | reddish-brown markings, white side hair tufts; turns light green just before pupating | young: black-and-white "bird dropping"; mature: green with black bands and orange dots; **forked orange osmeterium** everted when touched | velvety green, faint yellow dorsal line; ~25–35 mm; copious frass |
| Feeding | chews from the leaf edge; **trenches** veins to drain the latex first (Craig & Agrawal 2024); a big larva clears a milkweed leaf in ~20 min (Journey North) | eats leaf edges | edge-feeding on fine leaves | eats holes and edges; frass pellets drop below |
| Pupation | **J-hang 12–48 h**; skin split and shed in under a minute to a few minutes | hangs (Nymphalidae) | **girdled**: tail pad plus a silk belt, held at an angle on a stem | **girdled**, 19–20 mm, angular |
| Chrysalis | **jade green, gold dots, a black-and-gold band**; ~8–15 days; goes clear and dark before eclosion, the orange wings show through | smooth, plump, pale green (est. from the green pre-pupa) | angular, two "horns", green or brown | angular, pointed, green/grey/brown |
| Eclosion | splits, emerges in a few minutes, swallows air, pumps fluid into the wings, hangs to dry; most emerge in the morning (Brower via Boise State IBO) | same pattern | same | same |

General eclosion: emergence takes minutes; drying before the first flight takes about two hours or more
(ButterflyCircle field notes). The mechanism is known from cicadas: wings expand within ~40 min as haemolymph
flows in, then over ~80 min most of the fluid is pumped back out, leaving a stiff, light wing (Sci. Rep. 2023).
The expansion trigger must fire within ~40 min (Drosophila).

**Caterpillar locomotion.** Crawling is a wave of steps that runs **from the tail forward**. The terminal prolegs
lift first, then the four abdominal proleg pairs one after another; the thoracic legs follow less regularly
(Trimmer lab). A fifth-instar *Manduca* step takes **1.28 ± 0.36 s** on the flat and 1.02 s climbing (SICB
abstract). A stride moves the body about one segment length (est. ~8–12 % of body length). Climbing and flat
crawling use the same gait (van Griethuijsen & Trimmer 2009).

### 3.2 Compressed timeline (est., one story per screen at a time)

| Stage | Screen time | What's drawn |
|---|---|---|
| Caterpillar munches | 60–120 s | 4–7-cell body on a leaf. A gait wave runs tail to head every ~1.2 s, with a raised hump cell travelling forward. The head dips every 0.4–0.6 s; **the leaf loses cells in arcs from its edge** (monarch: first a trench line across a vein). Frass `·` drops below and fades over ~30 s |
| Wanders to a site | 10–20 s | crawls along stem/leaf underside, pauses, head sweeps |
| J-hang / girdle | 15–30 s | monarch/morpho: hangs from a leaf in a `J`, a slow sway with the breeze. Swallowtail/white: lies along the stem at an angle, then the silk belt (`-`) appears |
| Pupation | 3–5 s | skin wriggles upward (cells shrink from the top), the chrysalis glyphs fade in |
| Chrysalis | 60–120 s | still; sways only with the wind (it's on a stem). Monarch: gold dots twinkle in pollen gold. Last ~15 s: darkens, wing colour shows through (glyphs shift toward the species colour) |
| Eclosion | 4–8 s | case splits (`/` crack), body drops out and grips the empty case |
| Wing pumping | 20–40 s | wings grow from **~30 % to full size** with ease-out; crumpled at first (supersample the wing shape with a wrinkle mask that relaxes), abdomen shrinks |
| Drying | 20–40 s | hangs; 2–3 slow open-close cycles; the empty case stays as a pale trace and fades over ~60 s |
| First flight | — | low, short, a little unsteady (beat amplitude ramps up over ~10 s); lands on the nearest flower; **bask on first landing** |

Total ≈ 3.5–6 min. A new story starts every ~3–5 min per screen at most, near a host plant of its species. Every
stage leaves a trace: notched leaves, frass, an empty case.

---

## 4. Flowers

### 4.1 Which flowers, and how they read

| Flower | Why | Glyph sketch (head over stem) | Colour (dark theme, toned down) |
|---|---|---|---|
| Common milkweed | monarch host + nectar; dusky pink ball umbels, broad opposite leaves | `°o°` over `(|)` | dusty pink (186, 128, 140), leaves sage |
| Purple coneflower | monarch, swallowtail nectar; drooping mauve petals round a rust cone | `-@-` over `/|\` (petals droop) | cone rust (170, 98, 56), petals mauve (168, 120, 160) |
| Wild carrot / fennel | swallowtail host (machaon); flat umbels | `·:·:·` over `\|/` | off-white / pale yellow umbel (220, 214, 170) |
| Wild mustard | cabbage white host + nectar; small four-petalled crosses in a spike (crucifers) | `+` `+ +` up the stem | mustard yellow (206, 184, 76) |
| Red clover | low; monarch & white nectar | `@` on a short stem | clover pink (178, 110, 130) |
| Oxeye daisy / dandelion | fills the meadow; generic nectar | `*` (daisy, white with a gold over-glyph `·` centre), `*` yellow (dandelion) | |
| Grass tufts | the ground line, carries the breeze | `,` `'` `/` `|` `\` chosen by lean, as silk picks `/ \ |` by direction | sage (110, 130, 96) at low intensity |
| Fallen fruit (morpho) | morpho's food | `@` dark wine with a pollen-gold `·` sparkle | (120, 60, 70) |

Termflix's garden uses the same conventions (`(@)` rose, `o*o` daisy, `{a}` tulip, `*@*` sunflower, `|` stems, `~`
leaves, `Y` branches), so these will read as flowers.

### 4.2 Sway

Flower motion frequency depends mostly on the stem, varies by species, and isn't constant across wind speeds
(SICB floral motion abstract). Wind gusts mostly at **~0.2–2 Hz**. Flowers shed wakes at 2–5 Hz, and hawkmoths
track flower motion up to 14 Hz, well above what nature presents (Matthews & Sponberg 2018). No sourced figure
was found for a flower stem's own frequency, so:

- Each stem is a damped spring at its tip (est.): **f₀ ≈ 0.7–1.2 Hz** for tall stems (coneflower, fennel,
  4–7 rows), **1.5–2.5 Hz** for short ones (clover, daisy, 1–3 rows), with f ∝ 1/height. Damping ratio
  **ζ ≈ 0.08–0.15**, so a gust makes it ring for a few cycles.
- The lean is distributed along the stem (bend ∝ (y/h)²) and each stem cell picks `/ | \` by local slope, the
  silk `lineGlyph` rule. The head moves by the tip displacement and leaves stay on their stem cells.
- Forcing is the breeze at the head (drag ∝ |v|·v) plus a per-stem phase offset, so neighbours never sway in
  lockstep.

### 4.3 Blooming (click)

Real flowers open over hours. On screen (est.): the stem grows 1–3 cells in **0.6–0.9 s** (ease-out), a bud `.`
→ `o` swells for **0.5 s**, the petals unfurl over **1.5–2.5 s** (`o` → `*` → the full head, petals added
outward, intensity rising), and a **pollen-gold sparkle** (`·` `+`) lingers 1–2 s. A fresh bloom attracts
nearby butterflies: it is the "offer".

---

## 5. ASCII representation

### 5.1 Survey

- **Classic ASCII butterflies** are built from bracket wings round a body glyph: `(\o/)` over `(/|\)`, and
  `(\ o /)` / `))¥((` / `(/ ^ \)` (asciiart.eu). Text emoticons use `εїз` and `Ƹ̵̡Ӝ̵̨̄Ʒ`, which need combining marks
  our atlas doesn't have. Takeaway: **wings read as a symmetric pair of shapes either side of a 1-cell body**.
  The shape matters more than any glyph.
- **Terminal gardens** (termflix `garden.rs`) grow flowers by stage from `.` and colour only the top row. No sway
  and no butterflies. Nothing open-source surveyed does fluttering butterflies in a terminal, so we design our own.
- **Our own hand:** the spiders are supersampled ellipses (5 samples per cell), carved glyphs from `SKIN_RAMP`,
  `:;` / `.',`` edge glyphs by coverage, marks `#%@`, spots `o°`, tinted by species, shaded from the top-left,
  with 6 % accent and 10 % fleck glyphs. Butterflies should be **the same machinery**: no sprites.

### 5.2 Proposed drawing

- **Shapes:** each wing is a forewing and a hindwing, each an ellipse or a two-ellipse lobe in wing-local
  coordinates (u along the body, v outward). The swallowtail's hindwing gets a tail capsule and the morpho broad
  rounded lobes. A cell sample at (u, v) tests against the shape at **(u, v / s)**, where s is the projected
  width (§1.4). That gives foreshortening with no extra shapes.
- **Body:** 1 cell wide, 3 cells long (head, thorax, abdomen) on the spiders' blocks, `SKIN_RAMP` glyphs, dark
  tints. Antennae: one or two line glyphs above the head (`\ /`, with `'` clubs) that sway with the bob.
- **Wing interior:** block in the face colour (upper or under), glyph from a wing ramp keyed by **wing-local
  position** (hash of quantised u, v). Glyphs then ride with the wing as it narrows, as the spiders key theirs to the
  body, instead of boiling cell by cell. Shimmer at the spiders' `tick` rate (2.4 Hz) only on accent cells.
- **Pattern cells** (like `MARK` / `SPOT`): veins and borders as marks (`#%@`) on darker blocks; white
  margin dots as `°`/`·`; eyespots `o` `O` `@`. Monarch: black veins, black border with white dots.
  Morpho: blue field, black margin, white dots; underside brown with ringed eyespots. Swallowtail: black
  bands and veins on yellow, a blue row and an orange-red eyespot near the tail. Cabbage white: black forewing
  tip, 1–2 black spots, plain underside.
- **Edge-on (|s| < 0.18):** the wing doesn't vanish. Draw a line glyph along the wing's long axis (`|` when the
  body is upright, `/` `\` when pitched) in the underside colour: the "closed" pose and the clap in one rule.
  This, plus position-keyed glyphs, is the anti-flicker design. A cell never alternates between empty and full
  between frames because a threshold was crossed.
- **Hysteresis:** a cell's coverage class (empty / edge / full) changes only when coverage moves 0.1 past the
  threshold (est.). That costs one byte per cell in the butterfly's box.
- **Vertical cue:** add a small tip offset with the stroke (`dy = −0.4 row · sin φ` at the wing tips), so a
  raised wing climbs a row and a lowered one drops. It reads as the beat even when s barely changes.

### 5.3 Mock frames — monarch wingbeat (dark theme, dorsal view, flying upward-right)

Each character is one cell (13 × 19 pt): letters and symbols in wing cells sit on dim orange blocks, `#%`
are black vein/border marks, `°` white margin dots, `8 :` the body, `\ /` antennae. The box is fixed so you
can see the width and the bob. About 2.6 Hz on screen: 11–12 frames per beat at 30 fps.

```
   A · downstroke, wings level      B · upstroke, s ≈ 0.5, tips up   C · clap, edge-on (underside)
   s ≈ 1.0, body high (lift)        body dropping                    small forward lurch
 ┌───────────────┐               ┌───────────────┐               ┌───────────────┐
 │     \   /     │               │    ;%\ /%;    │               │     \|/       │
 │ ,;%#%\8/%#%;, │               │    #S%8%S#    │               │     |8|       │
 │°#tS%#%8%#%St#°│               │    °%#8#%°    │               │     |8|       │
 │ °;%S%%:%%S%;° │               │     `%:%´     │               │      :        │
 │   `°;%:%;°´   │               │      ° °      │               │               │
 │               │               │               │               │               │
 └───────────────┘               └───────────────┘               └───────────────┘
```

```
   D · start of downstroke, s ≈ 0.8, tips dropping, body ⅓ row lower (edge glyphs carry the offset)
 ┌───────────────┐
 │      \ /      │
 │  .;%#\8/#%;.  │
 │ °#tS%#8#%St#° │
 │ °;%S%%:%%S%;°'│
 │  `°;%#:#%;°´  │
 └───────────────┘
```

Glide is pose A held, with a shallow V (s ≈ 0.95, tips a quarter row up) and the body pitched along the path.

Other species, one frame each (est. sizes):

```
Morpho, banked: left wing upper (blue),        Swallowtail, open (tails trail)      Cabbage white, open, 9 cells
right wing underside (brown, eyespots)          13 cells + tail row
 ┌─────────────────┐                         ┌───────────────┐                  ┌───────────┐
 │  .;%SS%\ /      │                         │  .#%;\ /;%#.  │                  │ #;:. .:;# │
 │ °%SXXS%8|O;     │                         │ #S#t#%8%#t#S# │                  │ ;:·:8:·:; │
 │ °%SX%%#8|o%     │                         │  #%S°%8%°S%#  │                  │  `::8::´  │
 │  `°;%S%:|;´     │                         │   `o%#:#%o´   │                  │   `: :´   │
 │     `°  ´       │                         │    |     |    │                  └───────────┘
 └─────────────────┘                         └───────────────┘
```

### 5.4 Palettes (toned down; the spider tint approach: species tint × shade level)

| | Dark: wing block / glyph | Dark: pattern | Light (graphite on paper) | Calm |
|---|---|---|---|---|
| Monarch | block (64, 36, 16), glyph (196, 120, 52) | veins (20, 16, 14), dots (225, 220, 205) | ink (168, 96, 42) on paper-tinted blocks; veins ink | brightness × 0.62, accents × 0.35 (`ThemeParams`) |
| Morpho upper | block (22, 38, 62), glyph (84, 132, 190) | margin (14, 16, 22), dots (210, 215, 225) | ink (54, 92, 146) | same |
| Morpho under | block (40, 30, 20), glyph (128, 98, 66) | eyespot ring (186, 160, 92), centre (30, 24, 18) | ink (110, 84, 58) | same |
| Swallowtail | block (60, 54, 24), glyph (212, 190, 96) | bands (24, 22, 18), blue (92, 120, 170), red-orange (196, 104, 60) | ochre ink (150, 124, 40); bands ink | same |
| Cabbage white | block (58, 58, 54), glyph (222, 220, 206) | tips/spots (36, 36, 36); under (200, 202, 160) | **white on paper vanishes**: pale graphite block (214, 212, 204), ink glyphs (96, 96, 90), tips ink | same |
| Pollen gold (accent) | (217, 193, 74), the existing `ACCENTS` gold | breeze trail, nectar sparkle, chrysalis dots | paper-safe ochre (150, 124, 40) | × 0.35 rate |

As in the Web's light theme, keep species hues to saturation ≤ ~0.4 on paper, and keep accents graphite there,
except species identity, which is the point of the Meadow (owner's decision).

---

## 6. "Alive" checklist

| Principle | Concrete behaviours and parameters |
|---|---|
| **Wants something** | Every butterfly has a drive state: hunger (falls 1 %/s in flight, refills by nectaring), warmth (falls in long flight or shade, refills by basking), mate search (males), salt (males: cursor, damp patch). The target flower is chosen with **visible hesitation**: a slowing approach, ~25 % touch-and-go aborts, a circle before landing on the cursor. Monarchs keep a preferred direction for minutes and prefer screen crossings |
| **Has weight** | Per-beat lift and thrust (§1.4), drag toward airspeed, gravity in glides; heading on a spring (k 30–60); bank follows the turn rate; landing decelerates over ~2 wingspans; take-off needs 2–3 strong beats; stems are damped springs; a heavy morpho beats slower and bounds higher than a white |
| **Touches the world** | Lift only on downstrokes, so no wingbeat, no climb; feet grip a flower, which **dips under the landing** (an impulse to the stem spring proportional to mass) and sways with the butterfly on it; the proboscis glyph reaches into the head; a caterpillar's prolegs plant on the leaf; leaves lose cells to chewing |
| **Senses, doesn't know** | Butterflies read the breeze field (gusts push them, they bank into it), see flowers only within a sensing radius (~8–15 wingspans, est.; *P. rapae* is drawn to hosts from ~1 m, Root & Kareiva), smell fallen fruit downwind (morpho), flush from pointer *speed and distance* (not the pointer's existence), find the cursor only after it has been still for a few seconds |
| **Rests** | Dorsal basks 10–40 s (monarch, swallowtail), V-basks (white), wings-closed rests 20–90 s (morpho, any tired one), slow "breathing" open-close every 6–15 s while resting, nectaring 6–40 s; flowers settle after gusts; the chrysalis is still for a minute or two |
| **Leaves traces** | Pollen-gold dust drifting from a visited flower (fades 3–6 s), the pointer's breeze shown as briefly brighter, leaning grass, notched leaves, frass dots, the empty chrysalis case (fades ~60 s), a just-bloomed flower that stays |
| **No two alike, nothing loops** | Per individual: size ±12 %, beat ±10 %, boldness ×0.6–1.6, jink rate ±30 %, preferred direction, flower constancy, **wing wear** (1–3 random notches from the wing shape, as wild morphos carry natural wing damage, Le Roy 2019), sex (white: one vs two forewing spots); seeded value noise for wander; species mix and life-cycle stories never in phase; no fixed paths, all motion from forces and drives |

---

## 7. Performance

**Density (est.).** Butterflies ≈ **1 per 0.4 Mpt²** of screen, so ~3–4 on a 1440 × 900 laptop and ~9 on a
2560 × 1440 display, with a density setting ×0.5–×1.5. Hard cap 16 per screen. Default species mix: white 35 %,
monarch 25 %, swallowtail 20 %, morpho 20 %. Bottom flowers: one plant per **3–5 columns** (~40–60 across a large
screen) plus grass in the bottom 1–2 rows; scattered flowers 6–14 per screen. At most one life-cycle story per
screen at a time (two on very large screens).

| Cheap (do freely) | Costs (budget it) | Avoid |
|---|---|---|
| Butterfly sim: a few dozen floats each, per-beat forces at 60 Hz | Supersampling butterflies: bounding box ~15 × 7 cells × 5 samples × ~4 shape tests ≈ 2k tests each, ~20k a frame for 10 butterflies (the spiders do more) | Evaluating noise or the breeze **per cell over the whole screen** (80k cells × 30 fps): sample the breeze only at stems, butterflies and visible trail cells |
| Stems as single damped springs (60 × 2 floats) | **The breeze grid**: a coarse field (1 sample per ~4 × 3 cells: ~50 × 25 on a large screen), decay (half-life ~0.8 s) and a 5-point diffusion at 60 Hz ≈ 75k ops/s. Could step at 30 Hz | Per-cell alpha overlays across the screen; drawing grass in every cell of the screen |
| Glyph choice by position-keyed hash (as the spiders) | Painting the bottom band of flowers every frame (~1–2k cells); cache the still part and repaint only stems whose tip moved more than 0.05 cell | Allocating per frame (the Web painter's `Grow` buffers are the pattern) |
| Life-cycle stages (a handful of cells) | Light-theme blending, the same as the Web's | Heavy per-frame trigonometry per cell: two cosines per butterfly is enough for the wing model |

The Meadow should come in well under the Web (no Verlet cloth, no per-thread resampling). The largest fixed
cost is canvas upload and compose, which every canvas habitat shares. Add the Meadow's `OceanTool bench` case
before tuning.

---

## 8. Open questions for the owner

1. **Morpho's food.** Real morphos sip rotting fruit and sap, not flowers, and rest wings-closed. Add fallen
   fruit (and maybe a sap spot) for them, or let them nectar like the others?
2. **Which swallowtail.** The Old World swallowtail (*P. machaon*: yellow with black veins and bands, blue row,
   red eyespot, tails; host fennel or wild carrot, a meadow plant) fits a meadow better than the eastern tiger
   swallowtail (*P. glaucus*: yellow with bold black stripes; host trees). Recommendation: machaon.
3. **Slow motion.** Real speed is unusable on a desktop. OK with wingbeats at ~0.28× real and travel at about a
   fifth of the real distance per beat?
4. **Life cycle for all four species, or monarch first?** Each needs its own caterpillar, host and chrysalis
   (hanging vs girdled).
5. **Where "scattered flowers" live.** On stems from the ground up to ~40 % of screen height (a side view stays
   consistent), or loose blossoms anywhere? And does a click high on the screen grow a tall stem from the ground
   to it?
6. **Courtship.** Chases and rising spirals, and the white's refusal posture: fine to show? (Mating pairs are
   left out.)
7. **Swallowtail caterpillar defence.** Clicking near one makes it flash its orange forked osmeterium for a
   second: welcome as a small extra, or beyond the gesture table?

---

## Recommended parameters

Screen values are estimates derived from the sourced real values above. Sizes in cells (13 × 19 pt at full
size), speeds in pt/s at that size (scale with `cw / 13` on smaller grids).

| Parameter | Monarch | Blue morpho | Swallowtail | Cabbage white |
|---|---|---|---|---|
| Wingspan / height (cells) | 13 × 5 | 15 × 5 | 13 × 5 + tail row | 9 × 4 |
| Individual size spread | ±12 % | ±12 % | ±12 % | ±12 % |
| Real wingbeat (Hz) | 9.5 | ~6 (est.) | ~7 (est.) | 11.8 |
| Screen wingbeat (Hz) = real × 0.28, ≤ 3 | 2.6 | 1.7 | 2.0 | 3.0 |
| Stroke: φ_mid / amplitude | +20° / ±60° | +15° / ±65° (deep) | +20° / ±55° | +25° / ±55° |
| Cruise speed (pt/s) | 170 | 150 | 170 | 140 |
| Foraging speed (pt/s) | 80 | 70 | 80 | 70 |
| Escape burst | ×2 speed, beat ×1.25, 0.6–1.2 s, climb 15° | climb 13–22° | climb 15° | climb 20°, plus 2 jinks |
| Flap bout → glide | 3–8 beats → glide 1.5–5 s | 4–10 beats → glide 0.6–2 s | 3–6 beats → glide 1–3 s | continuous; glide < 0.4 s, rare |
| Glide angle | 15.5° (3.6:1) | 11° | 12° (est.) | — |
| Glide pose | V, s ≈ 0.95 | flat, s ≈ 1 | flat, s ≈ 1 | — |
| Jink chance per beat / σ heading | 0.12 / 12° | 0.30 / 30°, plus vertical ±0.5 wingspan bounds every 2–4 beats | 0.25 / 25° | 0.40 / 40° |
| Heading spring k / ζ | 30 / 0.9 | 35 / 0.85 | 45 / 0.9 | 60 / 0.8 |
| Body bob (rows) | ±0.25 | ±0.35 | ±0.25 | ±0.2 |
| Body pitch swing | ±15° | ±20° | ±15° | ±12° |
| Bank in turns (max) | 35° | 50° | 40° | 45° |
| Preferred-direction persistence | 3–8 min, prefers crossing screens (×3 weight) | 30–90 s | 1–3 min | 1–2 min |
| Nectar dwell (s) | 10–40 | fruit 20–60 | 6–25, forewings flutter | 6–20 |
| Bask (s) / pose | 10–40, open flat | 20–90 wings closed, 0.5 s flash every 10–30 s | 10–30, open flat | 8–25, V (s ≈ 0.5) |
| Flower weights | milkweed 3, coneflower 2, clover 1, daisy 1 | fruit only (or all 0.5 if Q1 says flowers) | coneflower 2, fennel 2, milkweed 1, daisy 1 | mustard 3, clover 2, daisy 2, dandelion 2 |
| Lands on cursor (weight) | 1 | 0.5 | 2 | 2 |
| Flush distance (cells, slow → fast pointer) | 3 → 6 | 2 → 5 | 3 → 7 | 2 → 6 |
| Host plant (life cycle) | milkweed | legume shrub | fennel / wild carrot | mustard |
| Pupa | hanging, jade, gold dots | hanging, plump green | girdled, angular, green/brown | girdled, angular, small |

Shared:

| Parameter | Value |
|---|---|
| Sim step | fixed 1/60 s, ≤ 4 catch-up steps (as Ocean/Web) |
| Cursor landing | pointer still ≥ 3 s (jitter < 2 pt); the chosen butterfly spirals in over 2–3 loose circles; sits, opens and closes every 4–10 s, proboscis to the "skin"; any move > 2–3 pt → escape burst |
| Breeze grid | ~4 × 3 cells per sample; pointer writes velocity × 0.6, Gaussian radius ~2–3 samples; half-life 0.8 s; ambient value noise at 0.03–0.12 Hz, 10–40 pt/s; a natural gust of 60–120 pt/s every 20–60 s |
| Gust reaction | airborne: drift + bank + beat +20 % when wind > 0.3 × airspeed; landed: wings close above ~60 pt/s, flush above ~120 pt/s |
| Stem spring | f₀ 0.7–1.2 Hz (tall) / 1.5–2.5 Hz (short), ζ 0.08–0.15, landing dips the stem |
| Bloom on click | stem 0.6–0.9 s, bud 0.5 s, petals 1.5–2.5 s, pollen sparkle 1–2 s |
| Courtship | ~1 encounter per 2–4 min per screen; chase 2–6 s or rising spiral 3–8 s, radius 1–2 wingspans |
| Life cycle | one story per screen, every 3–5 min; total 3.5–6 min (§3.2) |
| Density | 1 butterfly / 0.4 Mpt², cap 16; bottom plant every 3–5 cols; 6–14 scattered flowers |
| Anti-flicker | wing glyphs keyed to wing-local position; coverage hysteresis 0.1; edge-on wings as line glyphs; beat ≤ 3 Hz |

---

## Sources

Flight mechanics
- Bode-Oke, A. T. & Dong, H. (2020). The reverse flight of a monarch butterfly (*Danaus plexippus*) is characterized by a weight-supporting upstroke and postural changes. *J. R. Soc. Interface* 17: 20200268. https://pmc.ncbi.nlm.nih.gov/articles/PMC7328400
- Tejaswi K. C., Sridhar, M. K., Kang, C.-k. & Lee, T. Effects of abdomen undulation in energy consumption and stability for monarch butterfly. *Bioinspir. Biomim.* https://par.nsf.gov/servlets/purl/10232642
- Kang, C.-k. et al. (2023). Power benefits of high-altitude flapping wing flight at the monarch butterfly scale. *Biomimetics* 8: 352. https://pmc.ncbi.nlm.nih.gov/articles/PMC10452477
- Jantzen, B. & Eisner, T. (2008). Hindwings are unnecessary for flight but essential for execution of normal evasive flight in Lepidoptera. *PNAS* 105: 16636. https://pmc.ncbi.nlm.nih.gov/articles/PMC2575472
- Dudley, R. (1990). Biomechanics of flight in neotropical butterflies: morphometrics and kinematics. *J. Exp. Biol.* 150: 37–53. https://cob.silverchair.com/jeb/article-pdf/150/1/37/2640156/jexbio_150_1_37.pdf
- Le Roy, C. et al. (2021). Adaptive evolution of flight in *Morpho* butterflies. *Science* 374: 1158–1162. Preprint: https://www.biorxiv.org/content/10.1101/2021.03.22.436469 · overview: https://camille-le-roy.github.io/research/morpho_flight · data: https://datadryad.org/dataset/doi:10.5061/dryad.cz8w9gj44
- Le Roy, C. et al. (2022). Climbing escape flight in *Morpho*. *J. Exp. Biol.* https://pmc.ncbi.nlm.nih.gov/articles/PMC9440751
- Le Roy, C. et al. (2019). Effects of natural wing damage on flight performance in *Morpho* butterflies. *J. Exp. Biol.* https://cob.silverchair.com/jeb/article-pdf/doi/10.1242/jeb.204057/1976048/jeb204057.pdf
- Johansson, L. C. & Henningsson, P. (2021). Butterflies fly using efficient propulsive clap mechanism owing to flexible wings. *J. R. Soc. Interface* 18: 20200854. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7879755/
- Srygley, R. B. & Dudley, R. (1993). Correlations of the position of center of body mass with butterfly escape tactics. *J. Exp. Biol.* 174: 155. https://www.sciencegate.app/document/10.1242/jeb.174.1.155
- Kassarov, L. (2004). Review citing Chai & Srygley (1990, *Oecologia*) on palatability and flight. *J. Lepid. Soc.* 58: 169. https://images.peabody.yale.edu/lepsoc/jls/2000s/2004/2004-58(3)169-Kassarov.pdf
- Horisawa, Byrnes & Dudley. Characterization of erratic flight trajectories in free-flying butterflies (SICB abstract). https://sicb.org/?p=34324
- Gibo, D. L. Flight behaviour field notes (flapping, gliding, soaring; monarch glide ratio). https://w3.utm.utoronto.ca/~w3gibo/How%20to%20do%20field%20studies/flight_behavior_ii.htm
- Guinness World Records: slowest insect wing beat (*Papilio machaon*). https://www.guinnessworldrecords.com/world-records/70605-slowest-insect-wing-beat
- Physics Today, microscopic scales and monarch flight (secondary; near-ground speed). https://physicstoday.aip.org/quick-study/microscopic-scales-enhance-a-butterflys-flying-efficiency
- Seasonal *Pieris* flight morphology, *Ecology and Evolution* (2024). https://doaj.org/article/106cd718ab3440209f7908c3abe8f0f3
- Kareiva, P. & Shigesada, N. (1983). Analyzing insect movement as a correlated random walk. *Oecologia*. https://www.doi.org/10.1007/BF00379695
- Gust recovery in black soldier flies (thesis, IISc, 2020). https://mecheng.iisc.ac.in/cnuiisc/StudentsTheses/MTech(Res)/JHA/2020_DipendraGupta.pdf

Behaviour
- Kingsolver, J. G. (1985). Thermal ecology of *Pieris* butterflies: a new mechanism of behavioral thermoregulation. *Oecologia*. https://link.springer.com/article/10.1007/BF00379348
- Journey North. How does basking warm a butterfly? (13 °C flight threshold). https://journeynorth.org/tm/monarch/FallTempsBask_3.html
- Hirota et al. (2000). Air temperature and sunlight intensity on mate-locating in *Pieris rapae*. *Zool. Sci.* 17: 1081. https://bioone.org/journals/zoological-science/volume-17/issue-8/zsj.17.1081/The-Influence-of-Air-Temperature-and-Sunlight-Intensity-on-Mate/10.2108/zsj.17.1081.full
- Kandori, I. & Ohsaki, N. (1996). Learning of flower handling in *Pieris rapae*. *Popul. Ecol.* https://zendy.io/title/10.1007/bf02514977
- Harbour et al. (2019). Flight initiation distance in Lepidopterans is species-specific and positively related to starting distance. https://deakin.figshare.com/articles/journal_contribution/Flight_initiation_distance_in_Lepidopterans_is_species-specific_and_positively_related_to_starting_distance/20783164
- Female abdomen position signals receptivity during courtship (*J. Lepid. Soc.* 65(4)). https://bioone.org/journals/the-journal-of-the-lepidopterists-society/volume-65/issue-4/lepi.v65i4.a6/Female-Abdomen-Position-Signals-Receptivity-During-Courtship-in-the-Japanese/10.18473/lepi.v65i4.a6.full
- Courtship with a female-initiated ascending flight (up to ~20 m) that curtails male courtship (species not confirmed from the abstract; verify before quoting). https://link.springer.com/article/10.1007/BF00294987
- Puddling (behaviour). https://en.wikipedia.org/wiki/Puddling_(behavior) · Bug of the Week, salt of the human (swallowtails, brush-foots). https://bugoftheweek.com/blog/2019/8/2/salt-of-the-earth-salt-of-the-human-swallowtails-and-brush-footed-butterflies-papilionidae-and-nymphalidae
- UC ANR, swallowtails fluttering while nectaring. https://ucanr.edu/node/115421
- Butterflies and Moths of North America, *Danaus plexippus* (adult food plants). https://www.butterfliesandmoths.org/species/Danaus-plexippus
- Butterfly nectaring visit durations (field study, Bangladesh). https://banglajol.info/index.php/DUJBS/article/view/88405/57483

Species and life cycle
- UF/IFAS EDIS IN1101, blue morpho *Morpho peleides*. https://edis.ifas.ufl.edu/publication/IN1101 · Florida Museum, blue morphos in exhibit. https://floridamuseum.ufl.edu/exhibits/blog/blue-morpho-butterflies-in-exhibit · Wikipedia, *Morpho peleides*. https://en.wikipedia.org/wiki/Morpho_peleides
- UF/IFAS EDIS IN218, eastern tiger swallowtail. https://edis.ifas.ufl.edu/publication/IN218 · USDA Forest Service, tiger swallowtail. https://www.fs.usda.gov/wildflowers/pollinators/pollinator-of-the-month/TigerSwallowtail.shtml
- Animal Diversity Web, *Pieris rapae*. https://animaldiversity.org/accounts/Pieris_rapae · UF/IFAS EDIS IN283, imported cabbageworm. https://edis.ifas.ufl.edu/publication/IN283
- Britannica, girdle pupa. https://www.britannica.com/science/girdle-pupa · Learn Butterflies, pupa. https://learnbutterflies.com/?p=728
- Espace pour la vie, monarch chrysalis (J-hang 12–48 h). https://espacepourlavie.ca/en/monarch-chrysalis-or-pupa · UMD Extension FS-1144, monarch life stages. https://extension.umd.edu/resource/metamorphosis-life-stages-monarch-butterfly-milkweed-north-east-maryland · Florida Museum, a monarch metamorphosis. https://www.floridamuseum.ufl.edu/science/a-monarch-metamorphosis/ · Boise State IBO, suspense in the monarch meadow. https://boisestate.edu/ibo/2022/11/01/suspense-in-the-monarch-meadow
- Craig, S. & Agrawal, A. (2024). Complementary effects of two plant defence traits (monarch trenching, shaving). *Ecol. Entomol.* https://agrawal.eeb.cornell.edu/wp-content/uploads/2025/02/Craig-and-Agrawal-2024-Ecological-Entomology-2024-Complementary-effects-of-two-plant-defence-traits.pdf · Journey North, caterpillar feast. https://journeynorth.org/tm/monarch/CaterpillarFeast.html
- van Griethuijsen, L. I. & Trimmer, B. A. (2009). Kinematics of horizontal and vertical caterpillar crawling. *J. Exp. Biol.* 212: 1455. https://cob.silverchair.com/jeb/article-pdf/212/10/1455/1265852/1455.pdf · Step durations (SICB abstract). https://sicb.org/?p=29344 · van Griethuijsen & Trimmer (2014) review, *Biol. Rev.* https://treo.tufts.edu/sites/default/files/publications/2025-02/Final%20Reprint%20van%20Griethuijsen%20and%20Trimmer%202014%20brv12073.pdf
- Transient use of haemolymph for hydraulic wing expansion in cicadas (2023). *Sci. Rep.* https://www.nature.com/articles/s41598-023-32533-4 · ButterflyCircle, eclosion field notes. https://butterflycircle.blogspot.com/2008_02_02_archive.html

Flowers and ASCII
- Effects of wind speed on floral motion characteristics (SICB abstract). https://sicb.org/?p=20984
- Matthews, M. & Sponberg, S. (2018). Hawkmoth flower tracking. *J. Exp. Biol.* https://sponberg.gatech.edu/wp-content/uploads/2019/04/Matthews_Sponberg_2018-JEB.pdf
- Jackson et al. (2019). Natural sway frequencies in trees. https://discovery.ucl.ac.uk/10078184/1/Jackson%20et%20al%20%282019%29%20An%20architectural%20understanding%20of%20natural%20sway%20frequencies%20in%20trees%20-%20accepted.pdf
- termflix `garden.rs`. https://docs.rs/crate/termflix/0.7.2/source/src/animations/garden.rs
- ASCII Art Archive, butterflies. https://www.asciiart.eu/animals/insects/butterflies
