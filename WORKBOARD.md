Team rules: the agent-team skill; read it first.

# ASCII Animals: work board

<!-- Only the manager edits this file. Why: one writer per file, the board included. Basis: the director, 9 Nov 2026. -->

## Where files go

| File | Branch | Written by |
|---|---|---|
| WORKBOARD.md, briefs/<id>.md, everything merged | main | manager only |
| the work, reports/<id>.md | the task's branch | its builder |
| reviews/<id>.md | review-<id>, made from main | its reviewer |
| workers/<name>.md (handoff) | worker-<name>, never deleted | that worker |

Approved state: branch `approved` (to be created at the first approved merge; until then the last approved state is
tag `v3.0.1`).

## Roles

| Role | Who | Where (machine, thread) |
|---|---|---|
| Director | the owner | the owner's Mac |
| Manager | Claude (Opus) | the owner's Mac, the main T3 thread for this project |
| Builder | Claude agents, one per task | the owner's Mac, each in its own worktree next to the main folder |
| Reviewer | Codex agents (from 2026-11-20), one per review or re-check | the owner's Mac, each in its own worktree |

Director's profile: none

## Project rules

- 2026-11-20: The work follows `docs/plans/2026-11-19-meadow-3.1-plan.md` (the approved plan). Its Global
  Constraints and Review Focus bind every task. A brief points to its plan task instead of copying it.
- 2026-11-20: Only the manager pushes to main, and only after running the private-string scan over what is pushed
  (the pattern is kept outside the repo). Builders and reviewers push only their own branches.
- 2026-11-20: Safety on the owner's Mac (carried over from 3.0): never launch the app without
  `ASCII_ANIMALS_NO_HANDOVER=1`; never run the bare app binary without a `--snapshot-*` flag; never touch
  `~/Applications` or the app's real defaults domain (only `Tools/energy.sh` may, and only with the director);
  never run the old Sharks uninstaller; no live desktop runs without the director. The director answers any dialog
  that pops up, so a test must never raise a real destructive one.
- 2026-11-20: CI builds with an older Swift (6.3.3) than the local 6.4 and times out on long untyped expressions.
  Give literals and SIMD maths explicit types, split long mixed expressions into typed lets, and turn long check
  closures into named local functions.
- 2026-11-20: Commits use the repo's existing author identity and end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Corrections
- 2026-11-20: "pause after m1". Applies: new (m1 finishes its fix round and Codex re-check, and its CI; then all
  work stops; m2 does not start until the director resumes).
- 2026-11-20: "continue also whats new doesnt need a full screen thing i think". Applies: new (t9: the 3.1
  what's-new for existing users is not the full-screen welcome window the Web card uses today; the manager
  proposes a small card under the menu bar icon, shown once, with "Try the Meadow" and "Not now", and a "New" tag
  on Meadow in the Habitat menu; the first-run welcome tour for new users stays as it is; t9's brief brings the
  design back to the director).
- 2026-11-20, asked whether the sketch is ready to port: "dbbl check shit then go". Applies: new (the sketch gets
  one independent Codex review before the port; meanwhile a read-only research task maps the sketch against the
  Swift code for the port plan; the manager then writes the port plan for the director's approval, Design size).
- 2026-11-20, on sketch round 6 (light mode for paper): "ok for now". Applies: new (round 6 accepted for now).
- 2026-11-20, during s1 round 5: "also to be clear is the colors in light mode not beign correct intended?". The
  manager's answer: only partly. The muted look and no colour sparkle on paper follow Web, but the rest is wrong:
  solid near-black blocks for the black markings (heavy, muddy on paper), olive and brown wings, white flowers that
  go grey and vanish, and pale mint leaves as the loudest colour. The family on paper uses pale tinted blocks with
  dark ink glyphs and no solid black. Round 2 converted the dark palette by a formula instead of designing a paper
  palette. Applies: task.change (round 5 is building on the same file; a light-mode round 6 follows it, designing
  the paper palette from Ocean's and Web's light stills).
- 2026-11-20, on sketch round 4: "looks good one last thing rn there is no seperation between the close butterfies
  and the stuff far away especially the flowers.. what do we do, discuss no edits yet"; the manager proposed
  pushing the meadow back with light (family depth dimming) plus a dark rim around high butterflies, with less
  detail in the distance as a stronger step, all on one Depth slider; the director: "ok". Applies: new (s1 round 5).
- 2026-11-20, during sketch round 4: "leaves param at .9". Applies: task.change (round 4 is building on the same
  file and its brief is frozen, so this waited until round 4 landed; the manager set the Leaves default from
  1.24 to 0.9 as a Small change, meadow-sketch @ f8811f6).
- 2026-11-20, after playing with sketch round 3: "umm what happens when i keep clicking at the same point?" and new
  settings, the same as before except glide 0.44 → 0.1 (the new round-3 controls left at their defaults).
  Applies: new (the sketch's round 4: glide 0.1 is the default; what the manager found in the code: every click
  stacks another flower of a random kind on the same spot, with no limit, kept even by "New meadow", and each click
  may call the nearest butterfly, so repeated clicks pile butterflies onto one point, the gathering the director
  asked to avoid. Round 4: a click on a bloom touches that bloom instead of stacking a new one).
- 2026-11-20, after playing with sketch round 2, the director sent their settings "for now": count 7, sizeLow 0.75,
  sizeHigh 1.4, wingbeat 0.5, lurch 2, zigzag 1.29, glide 0.44, speed 2, turning 1.23, bob 1, height 0.5, visits
  0.35, stay 0.25, bask 0.2, density 0.85, flowerSize 1.32, leaves 1.24, breeze 1.7, shadow 1, green 0.69, grass 1,
  sparkle 1, all four species. Applies: new (these become the sketch's defaults; the round-2 look is accepted for
  now; the sketch's next round, motion and behaviour, starts from them).
- 2026-11-20, on the sketch: "aslo colors in light mode doesnt look right". Applies: new (the sketch's next round:
  light mode redone to match how Ocean and Web do light, from the research).
- 2026-11-20, on the sketch: "aslo need reset button seperately for each tweak". Applies: new (the sketch's next
  round: a reset beside every slider and choice, back to its default).
- 2026-11-20: "no viual detail i meant about this: yeah figure all all the small devil in the edtails type stuff from
  those scnees to this one can sfeel like the same family". Applies: the family-details round is about the LOOK
  (visual details); motion and behaviour notes from the research are kept for later, not acted on now.
- 2026-11-20, on the sketch: "yeah figure all all the small devil in the edtails type stuff from those scnees to this
  one can sfeel like the same family", then "aslo the artefact foesnt work / not just visual detail / just local
  host bro why artefact". Applies: new (the sketch is served on localhost, not as a published page; a researcher
  catalogues every detail of Ocean and Web, look, motion, behaviour, interaction, traces, edges, for the sketch's
  next round).
- 2026-11-20: "aslo we are missing some of that random gplyh color noise thing that the other animals bodies had,
  first figure out what that is? its not a erro ir issue". Applies: task.change (s1 is building: it goes into the
  sketch's next round). What it is (manager, from Shaders.swift and WebPainter.swift): the hide shimmer. Each body
  cell has a key hashed from its body-local position, so its glyph rides with the body; interior glyphs come from
  a density ramp by shade with a ±1 random step; every cell re-rolls a random number about 2.4 times a second on its
  own staggered phase; on a roll about 9 % of cells show their glyph in one of seven accent colours (orange, red,
  purple, cyan, green, blue, gold), about 4 % in white, the rest in dark ink; edge cells use light glyphs with 7 %
  accents; the sharks add a ±3 % brightness flicker per cell at 6 Hz. Accents are off on paper and scaled down in
  Calm. The Meadow painter has the body-anchored glyphs but none of the coloured re-rolling flecks.
- 2026-11-20: "take a step back". Applies: decide.escalate (p2a held; the manager reviews the whole approach with the
  director before more building).
- 2026-11-20, on the p1 prototype: "also it doenst move like a butterfly anomore". Applies: new (p1 used a quick
  stand-in flight; the measured flight's beat-coupled lurch, bob and zig-zag must carry into the top-down view;
  part of the proposed p2).
- 2026-11-20, on the p1 top-down prototype: "the wing beat loosk too infreent and slow, the flowers need a lot of
  work and some findelity and quality we are missing". Applies: new (revisits the plan's "slow motion" decision,
  wingbeat = real × 0.28 capped at 3 Hz; proposed: a look-development step p2 before the plan is rewritten).
- 2026-11-20, sent by the director straight to p1's builder mid-task: "keep the screen mainly black with hints of
  green and need way better flowers". Applies: new (applied in p1; it carries into the top-down plan if chosen).
- 2026-11-20: "mm also what if its a top down view into the scene instead of the side view we have now? exercis
  abstract thinking", then "then can come closer and further away from the viewpoint / take all the feed back in
  this set ive given and exercise abstract tthinking". Applies: task.size (a Design change: written direction to
  the director first, docs/plans/2026-11-20-meadow-top-down-direction.md); t3 held meanwhile (task.change).
- 2026-11-20: "not replace but learn from it and make a whole new one/ modify ours also their wings have a bit more
  detail and not just one flat color like ours (we dont want full realistic colors but yeah)". Applies: new (t5w:
  our own wingbeat, turning and wing shading, learning from the reference rather than copying it).
- 2026-11-20: "i have a wing beat referene, look properly. also dont take anything else from this it doesnt have the
  life stuff we have. also want the butterflies to like rotatea around when moving (idk how much is possible)",
  with https://www.pocketstudio.design/ascii-animals-app/. Applies: new (t5w rewritten before it started: the
  reference's symmetric wingbeat and turning only; the checks of the replaced wing design are replaced on this
  decision).
- 2026-11-20, on the first films: "also it looks like onyl the left wing is moving and the right wing dissapears on
  motion towards close". Applies: task.change (t3 is building and lists MeadowPainter.swift, so this becomes a new
  task t5w after t3, not a change to t3).
- 2026-11-20, after watching the first films: "1. to many 2. they gather around to mcuh and look like they roam
  around the same places and not enough movevemt". Applies: new (t3's brief; it sets the realism line: movement
  and spread first).
- 2026-11-20, asked what the issue was, then "think more exercise abstract thinking": the manager had kept a rule
  nobody asked for (nothing drawn off screen) and patched around it for two rounds. Applies: decide.escalate /
  review.restart (step back to the director's actual asks before rewriting a brief).
- 2026-11-20, on the first Meadow stills: "would like bigger butterflies and better flowrs". Applies: new (t5 fix
  round 1).

- 2026-11-19, on the T2 flight-path picture: "did you see the flight paths? they seem clusted at the center of the
  screen". Applies: new (sent to the T2 builder mid-task, before this board existed; now part of brief t1-2).
- 2026-11-19: "pause work". Applies: new. All work stopped; resumed by the director's "be the pm" on 2026-11-20.

## Decisions

- 2026-11-20: The port plan is approved: the director said "dbbl check shit then go" and answered its three
  questions. Ground colour per cell: "Yes, change it" (m3). The monarch life cycle and courtship chases: "Leave out
  of 3.1" (t4's life cycle and courtship are dropped from 3.1; crossings move into m6). What users can change:
  "presets like the other two animas" (m8: named butterfly line-ups like Ocean's and Web's presets, with Custom; the
  manager proposes the names in m8's brief). The side-view tasks are superseded by m1–m8 on a fresh stack from main;
  the no-merge rule stands. Draft PR #1 (t1-2's CI) is closed at the end with the side-view branches, with the
  director's OK.

- 2026-11-20: The port plan is written (docs/plans/2026-11-20-meadow-port-plan.md, from research r2 and the sketch
  review) and sent to the director with three questions; nothing is built from it until approved (Design size).
  Proposed in it, by the manager: a fresh stack from main (m1–m8), superseding the side-view branches, instead of
  stacking on meadow-t1-2 (every t1-2 file is replaced); this supersedes the 2026-11-20 stacking base once
  approved, not the no-merge rule.

- 2026-11-19: Meadow 3.1 plan approved ("ok"); species, slow motion, monarch-only life cycle, courtship chases,
  caterpillar horn deferred, morphos sip flowers (the director, via the plan's questions).
- 2026-11-19: Order: T1, T2, T5 (painter and a first still), T3, T4, T6, then the T7 gate, T8, T9, T10, so the
  director sees a still early (manager).
- 2026-11-20: The director made Claude the manager ("be the pm for this project"). This board replaces the earlier
  private progress ledger. The unreviewed Meadow commits (5496bbf breeze and flowers, 0cce823 butterfly flight) moved
  off main onto task branch `meadow-t1-2`; main is back at 3043eed (the plan) (manager).

- 2026-11-20: The board files (WORKBOARD.md, briefs/, reviews/, reports/) may live in the public repo for now; to be
  revisited later ("yesh fr now its fine we will deal with taht later", the director).
- 2026-11-20: t1-2 gets its CI run through a draft pull request (CI runs only on main and on pull requests), so a
  red build never lands on main (manager).

- 2026-11-20: Reviews and re-checks are done by Codex from now on ("use codex for reviewing", the director).
  t1-2's review and re-check, already done by Claude, stand.
- 2026-11-20: t5 is briefed ahead (briefs/t5.md) (manager).

- 2026-11-20: Nothing merges into main until the whole Meadow is built ("bro fnish the work first / dont merge now",
  the director). Tasks stack: each task's branch is made from the previous task's branch, starting from
  `meadow-t1-2`. The director approves the stack at the end; each task still gets its own review and CI run. A later
  fix to an earlier task's files goes through that task's own branch and is then merged up the stack (manager).

- 2026-11-20: A later task may change an earlier stacked task's file when the change is that later task's own
  purpose (the director's bigger butterflies and better flowers in t5); its row names the file. Other fixes to an
  earlier task go through that task's branch (manager).

- 2026-11-20: t5 restarts with the rewritten brief: closed wings as the solid underside, the flight at the drawn
  size, starting with a design exercise ("ok after some exercise abnstract thinking", the director; read as yes
  plus think it through first).

- 2026-11-20: Butterflies may flutter partly off screen and into the gap between displays; only the body stays on
  a screen, like the sharks ("yeah butterflies can flutter a bit off screen, in between screens it was neveer a
  iusse", the director). t5 restarts simplified (briefs/t5.md, "Restart 2, simplified"). Dropped, against this
  decision: the checks `nothingDrawnLeavesTheScreen` and `drawingStaysOnScreen`, and review findings 1–3 of the
  t5 restart review as far as they demand no off-screen cells (manager, on the director's decision).

- 2026-11-20: After t5, a short film of the butterflies flying before t3 starts (the director: "yes"). Also: keep
  the physics where it makes them look better, and decide how realistic we want them ("its a line drawn in sand on
  a spectrum", the director). The line is decided after the director sees the film ("we can only decied afteri see it in motion"). Set on
  2026-11-20 by the director's verdict on the film: movement and spread across the whole screen first, real
  behaviours tuned to keep the meadow moving. The clap snap and the morpho's flash drew no comment from the
  director, so t5's two clap findings go to Noticed (manager).

- 2026-11-20: A throwaway top-down prototype film (p1) before the plan is rewritten; the director picks the view by
  watching it next to the side-view film ("ok", the director). No review for p1: it is never merged (manager).

- 2026-11-20: The view from above is chosen (the director's notes on p1 treated it as the pick; not objected to).
  Look development (p2) comes before the plan is rewritten: first motion and wingbeat speed (p2a), then the
  butterfly sheets, then the flowers ("ok", the director). t3 and t5w stay held until the plan is rewritten.

- 2026-11-20: Make the Meadow's original first: a live web sketch with sliders the director plays with; port it to
  the app once the director says it's right ("ok", the director, to the proposal; earlier "uhhh" to the long
  version). Look development: no reviews or checks while exploring; the team process resumes for the Swift port.
  The manager delegates the sketch to a builder (team.manager: the manager does not build) and publishes it.

- 2026-11-20: Sketch round 3 is motion and behaviour, from the research's gap list (§3.2–3.6), built on the
  director's settings. The settings read as: more travel, more lurch and zig-zag, less gliding, more breeze, more
  butterflies. So nothing added this round may make them sit more or move less by default; every new behaviour gets
  its own slider or switch with a reset, so the director tunes it (manager).

## Tasks

| Id | Task | Size | Files | Branch | Builder | Reviewer | Rounds | State | Brief |
|---|---|---|---|---|---|---|---|---|---|
| t1-2 | Breeze, flowers and butterfly flight (plan T1 + T2), with the director's path fix | Content | Sources/OceanKit/Meadow/{Breeze,Flowers,ButterflySpecies,Butterfly}.swift, Sources/OceanChecks/MeadowChecks.swift, Sources/OceanTool/{Paths,main}.swift | meadow-t1-2 | builder-t1-2 (Claude Opus, T3 child thread; fix round 1) | reviewer-t1-2 (Claude Opus, T3 child thread) | 1 | reviewed, waits for the end of the stack (director: no merge yet): reviewed (review-t1-2 @ 68288c7), CI passed on 1e11a1b (PR #1), merge rehearsed 2026-11-20 (200 passed, app builds); superseded by the port plan (m1–m8), kept as a reference until the end | briefs/t1-2.md |
| t5 | Meadow painter and `OceanTool meadow-still` (plan T5, as reordered); fix round 1 adds the director's bigger butterflies and better flowers | Content (grown: now also t1-2's sizes and flower shapes; the director set the look, so no separate plan) | Meadow/MeadowPainter.swift (new), OceanTool/{MeadowStill,main}.swift, OceanChecks/MeadowChecks.swift, Render/GlyphAtlas.swift (append only); fix round 1 adds Meadow/ButterflySpecies.swift (sizes) and Meadow/Flowers.swift (heads, leaves, clumps) | meadow-t5 (from meadow-t1-2); restart on meadow-t5r | builder-t5 (Claude Opus, T3 child thread) | reviewer-t5 (Codex) | 2 before the restart; 2 after it; restart 2: 0 | reviewed (review-t5r2 @ 57f880a); clap findings to Noticed after the director's watch; superseded by the port plan (m1–m8), kept as a reference until the end | briefs/t5.md |
| t5v | A 30 s film of the butterflies flying, for the director to judge the motion | Content (small) | OceanTool/MeadowFrames.swift (new), OceanTool/main.swift | meadow-t5v (from meadow-t5r) | builder-t5v (Claude Opus, T3 child thread) | Codex | 0 | reviewed (review-t5v @ 94d9d2b); its 4 tool fixes moved into t3 (which rewrites meadow-frames); superseded by the port plan (m1–m8), kept as a reference until the end | briefs/t5v.md |
| p1 | Throwaway prototype film of the Meadow seen from above, with depth | Prototype (never merged, no review) | new OceanTool files, OceanTool/main.swift | proto-top-down (from meadow-t5v) | builder-p1 (Claude Opus, T3 child thread) | none | 0 | built (proto-top-down @ de1f728); director's notes in Corrections; superseded by the port plan (m1–m8), kept as a reference until the end | briefs/p1.md |
| p2a | Look development 1: butterfly motion from above (the measured flight turned on its side) and wingbeat speed | Design (look development; approved; reviewed later in the plan's tasks) | new Meadow/OceanTool files, OceanTool/main.swift, additive Butterfly/ButterflySpecies | look-top-down (from proto-top-down) | builder-p2a (Claude Opus, T3 child thread) | later | 0 | held (the director: "take a step back"); notes only at look-top-down @ adc632f, no code changed; superseded by the port plan (m1–m8), kept as a reference until the end | briefs/p2a.md |
| s1 | The Meadow sketch: a live web original with sliders (published for the director) | Design (look development; approved; one review before the port, the director asked) | Tools/meadow-sketch/meadow.html (new) | meadow-sketch (from main) | builder-s1 (Claude Opus, T3 child thread) | Codex | 0 | built (meadow-sketch @ 0e2ecf7); round 2 built (meadow-sketch @ d893c50, done with concerns); round 3 built (meadow-sketch @ caca692, done with concerns); round 4 built (meadow-sketch @ ee6009b, done with concerns); leaves 0.9 set by the manager (f8811f6); round 5 built (meadow-sketch @ b01db3f, done); round 6 built (meadow-sketch @ 3f02cb3, done); the director: "ok for now", then "dbbl check shit then go": Codex review a8f02d4 in (15 findings, routed below); fix round 1 done with concerns (meadow-sketch @ f20b833); re-check 1f9e985 routed below; fix round 2 done (meadow-sketch @ 4bcf693), re-check 2 436917c: fixed, three small fixture findings; fix rounds 1–3 done, re-checks passed (review-s1 @ 66f4462); R3-1 fixed by the manager (meadow-sketch @ 4e1b869). The original for the port is meadow-sketch @ 4e1b869; open edge cases are carried into m1, m6, m7, m8 | briefs/s1.md, briefs/s1r2.md … briefs/s1r6.md |
| r1 | Research: what makes Ocean and Web look and feel alive, and the Meadow's gaps | Small (read-only research) | docs/plans/2026-11-20-family-details.md | main | research agent | none | 0 | done (saved on main) | none |
| r2 | Research for the port: the sketch's model, numbers and behaviours mapped against the Swift Meadow code on the task branches | Small (read-only research) | docs/plans/2026-11-20-meadow-port-inventory.md (saved by the manager) | main | research agent (Claude Opus, T3 child thread) | none | 0 | done (saved on main) | none |
| t5w | A new wingbeat (both wings together), wing shading and detail, and butterflies that turn to face where they fly, learning from the director's reference | Content | Meadow/MeadowPainter.swift, Meadow/Butterfly.swift (drawn heading, open), OceanChecks/MeadowChecks.swift | meadow-t5w (from meadow-t3) | | Codex | 0 | held (the view changed; replaced by look development); superseded by the port plan (m1–m8) | briefs/t5w.md |
| t3 | Meadow world and behaviours (plan T3), with the director's film verdict | Content | Meadow/{MeadowWorld,Behaviour}.swift (new), OceanChecks/MeadowChecks.swift, Meadow/MeadowPainter.swift (convenience paint, breeze trail), Meadow/Breeze.swift (pointer field), Meadow/{Butterfly,ButterflySpecies}.swift (roaming, spacing, stays), OceanTool/{MeadowStill,MeadowFrames,main}.swift | meadow-t3 (from meadow-t5v) | builder-t3 (Claude Opus, T3 child thread) | Codex | 0 | held (2026-11-20: the view may change to top-down); WIP saved at meadow-t3 @ 11394be (does not build yet; checks written, world not started); superseded by the port plan (m1–m8), kept as a reference until the end | briefs/t3.md |
| t4 | Cursor landing, courtship, crossings, monarch life cycle (plan T4) | Content | to brief | meadow-t4 | | | 0 | open (waits on t3); superseded by the port plan (m1–m8) | |
| t6 | Meadow habitat, settings and tools (plan T6) | Content | to brief | meadow-t6 | | | 0 | open (waits on t4); superseded by the port plan (m1–m8) | |
| t7 | Director reviews the prototype films (plan T7, a gate) | Content | none | none | | | 0 | open (waits on t6) | |
| t8 | Energy, measured with the director (plan T8) | Content | to brief | meadow-t8 | | | 0 | open (waits on t7) | |
| t9 | Choosing the Meadow: menu, Settings, welcome (plan T9) | Content | to brief | meadow-t9 | | | 0 | open (waits on t8); the what's-new is not full screen (Corrections, 2026-11-20) | |
| t10 | Words, watch and release 3.1 (plan T10; outward-facing, the director approves the release) | Content | to brief | meadow-t10 | | | 0 | open (waits on t9) | |
| m1 | Air and flowers from above (breeze, pointer air, downwash, flowers, planting, clicks on flowers, the tuning file) | Content | Sources/OceanKit/Meadow/{MeadowTuning,MeadowMath,Breeze,Flowers}.swift (new), Sources/OceanChecks/MeadowChecks.swift (new), Sources/OceanChecks/main.swift, Sources/OceanTool/{MeadowAir,main}.swift (optional), a copy of the sketch fixture in the checks' resources, Package.swift (grown: bundles the fixtures as the checks' resources; for the review to judge) | meadow-m1 (from main) | builder-m1 (Claude Opus, T3 child thread) | 0 | open (waits for the sketch's fix round 1 and its re-check) | built (meadow-m1 @ 5965216, done with concerns); Codex review af7dbb1 in (7 findings, routed below); CI green on 5965216 (draft PR #3); fix round 1 building
| m2 | Flight from above | Content | Sources/OceanKit/Meadow/{ButterflySpecies,Butterfly}.swift (new), Meadow/MeadowTuning.swift (additions), Sources/OceanChecks/{MeadowFlightChecks,main}.swift, Sources/OceanTool/{MeadowPaths,main}.swift | meadow-m2 (from meadow-m1) | | Codex | 0 | open (waits on m1) | briefs/m2.md |
| m3 | A ground colour per cell in the shared canvas | Content | Sources/OceanKit/Render/{CellCanvas,OceanRenderer,Shaders}.swift, Sources/OceanChecks/CanvasChecks.swift, Sources/OceanChecks/main.swift (only if a new check group needs registering) | meadow-m3 (from main) | builder-m3 (Claude Opus, T3 child thread) | Codex | 1 | reviewed (meadow-m3 @ 796d61e: review 3f52b22, fix round 1 5d12bea, re-check e811cc2 passed, CI green on 796d61e); waits for the end of the stack | briefs/m3.md |
| m4 | Painter: the meadow | Content | to brief (port plan m4) | meadow-m4 (from meadow-m2, with m3 merged up the stack) | | Codex | 0 | open (waits on m2, m3) | |
| m5 | Painter: the butterflies | Content | to brief (port plan m5) | meadow-m5 | | Codex | 0 | open (waits on m4) | |
| m6 | World and behaviours, several screens | Content | to brief (port plan m6) | meadow-m6 | | Codex | 0 | open (waits on m5) | |
| m7 | Pointer and clicks | Content | to brief (port plan m7) | meadow-m7 | | Codex | 0 | open (waits on m6) | |; carries m1 finding 1's host side (each pointer event's own time and position)
| m8 | The Meadow habitat, its presets and settings, OceanTool | Content | to brief (port plan m8) | meadow-m8 | | Codex | 0 | open (waits on m7) | |

## Review routing

- m1, Codex review af7dbb1 (review-m1, 2026-11-20, of meadow-m1 @ 5965216), routed by the manager. Faithful at the
  director's settings on one screen (weather, flowers, seven kinds, RNG and hash, feeding, clicks, replant matched
  the sketch run headless; format-2 fixture replays unchanged; CI green). Rulings judged: Package.swift bundling
  accepted (scope recorded); supplemental probes kept; clicks off the screens ignored (fits m7's rule); pollen
  inside Flowers accepted (document the spark buffer); wind-peak check 88-100 over an hour accepted; the 0.1 s
  pointer lag stays open until finding 1's matrix passes; the planted-flower fade is kept as a port extension but
  must work (finding 2).
  - Fix (all caused by m1, in its Files): 1 (timestamped 15 Hz bursts miss 5 %; re-entry drops a queued move:
    keep queued segments, test paired and jittered delivery at 15/30/60/120 Hz, define the timestamped input
    contract the host must meet), 2 (planted-flower fade fails for small and big resizes; a cell-only change
    skips the sizing transition), 3 (bad input: subnormal cell width hangs layout, huge coordinates give NaN,
    non-tick step lengths accepted), 4 (fixture to format 2, validated; replay from viewport-derived points),
    5 (shared-edge corner leak), 6 (regressions the checks miss: add the checks the review lists), 7 (constants
    into the tuning file; document the repeat-touch rule and the sketch citations at 4e1b869), and the review's
    "What is missing". The fix list is at the end of briefs/m1.md.
  - Rewrite the brief: finding 1's host side (PointerMonitor and OceanDirector supplying each event's own time and
    position) goes into m7's brief.
  - Dropped: none. Asked of the director: none.

- m3, Codex review 3f52b22 (review-m3, 2026-11-20, of meadow-m3 @ 2640dc6), routed by the manager. Ocean and Web
  verified byte for byte (checks, digests, 8 stills, 60 Ocean frames); the dissolve ruling upheld (unrevealed cells
  show the plain background).
  - Fix (small, in m3's Files, caused by m3): 1 (Web keeps uploading an empty ground after a ground painter used
    the viewport: track ground use per paint, fall back when none), 2 (a failed ground texture retries the whole
    ring every frame: bound it, log once), 3 (the 77-line check closure into a named function, CI rule),
    4 (the texture layout comment), and the review's "What is missing" (the GPU check covers ring-slot reuse, a
    resize, and that ground-free frames skip the upload).
  - Dropped: none. Asked of the director: none.

  - Re-check e811cc2 (2026-11-20): all four and "What is missing" fixed; Ocean and Web byte for byte (checks,
    digests, 8 stills, 60 Ocean frames); CI green on 5d12bea. New: two comments wrong (fixed by the manager as a
    Small change, 796d61e: the atlas is r8Unorm; the upload counter's wording). Coverage note: the checked-in GPU
    check waits for each frame, so it can't see two frames in flight sharing a ring slot (the reviewer's own probe
    passed); routed to m4's brief: a check that encodes several ground frames before any completes.

- s1, Codex review a8f02d4 (review-s1, 2026-11-20, of meadow-sketch @ 3f02cb3), routed by the manager. The sketch
  is the reference the port copies, so a wrong rule here becomes a wrong rule in Swift: everything the sketch
  caused is fixed in it (fix round 1, briefs/s1f1.md), none put off.
  - Fix: 1 (count can fail to settle at the edges), 2 (pause bypasses lifetimes; clicks pile up while paused),
    3 (stored and URL settings not validated), 4 (one replant transition: orphaned visitors, limit not applied),
    5 (cursor approach outlives leave, Off and resize; body off the edge), 6 (re-enabled species stay absent),
    7 (pointer wind depends on the event rate: integrate in simulation time), 9 (size sliders crossed: one size
    rule for panel, clipboard and drawing; clicked flowers follow Flower size), 10 (non-primary and lost pointer
    releases click), 11 (hints that overstate: make the hints describe the approved rules, keep the behaviour),
    12 (click-answer gap and hold threshold wording; nearest blocking bloom), 13 (the stored settings key moves on,
    so every browser shows the true defaults; the port takes its defaults from a fresh profile), 14 (Space on a
    focused control), 15's sketch part (seeded shuffles; UI draws on their own random stream).
  - Rewrite the brief (the port plan, written next): 8 (frame budget at extreme legal settings: the port profiles
    shadows, flower scans and glyph drawing separately and keeps the step apart from the draw; the paused backlog
    part is fixed with 2), 15's port part (the clock and tick policy, slow motion as its own mode), 7's port part
    (pointer impulses in simulation time), and the review's "What is missing": a replay fixture (seed, settings,
    viewport, cell size, pointer trace, expected samples), the unit and clock mapping, the 7.5 Hz wingbeat cap and
    catch-up policy against the app's frame rate, and display-terrain edges (entering small, leaving large,
    landing while displays change).
  - Dropped: none. Asked of the director: none (no finding goes against a decision; 11 keeps the approved
    behaviour and fixes the words).
  - Re-check 1f9e985 (2026-11-20, of f20b833): fixed 2, 6, 8 (paused part), 9, 12, 13, 14, 15 (sketch part); default
    look and motion match round 6 apart from the seeded shuffles (judged faithful). Not fully fixed, each now down
    to a narrower edge case: 1 (an entrant that perches before clearing the inset waits long), 3 (a typo in a
    `s.species=` URL list becomes a preset), 4 (a resize under 80 px keeps a clicked bloom just off screen), 5 (at
    a tiny viewport's corner the body can still be clipped), 7 (30 Hz input still alternates empty and doubled
    stirs), 10 (a touch dragged off the canvas edge can plant outside; another pointer's release cancels a press),
    11 (three hints still overstate slightly). New, high: paused species toggles grow the butterfly array.
  - Routed by the manager (2026-11-20), stepping back rather than a second round of sketch patches: the sketch's
    job is the director's playground and the reference for the RULES; the app re-implements input, settings and
    edges in Swift with its own checks. So:
    - Fix in the sketch (s1 fix round 2, briefs/s1f2.md): the new finding (the director can hit it), and the
      review's "What is missing" replay fixture export, which the port needs.
    - Rewrite the briefs (carried into the port as rules with Swift checks): 1 → m6 (entering ends when it lands
      or perches; no newcomer perches outside the screen), 4 → m1 (clicked flowers off screen after any resize
      fade), 5 → m7 (the sitter's whole body stays on a screen at any corner), 7 → m1 (same air at 15–120 Hz input,
      regular or bursty), 10 → m7 (a click is only ever inside the terrain; the app's pointer path), 11 → m1 and m6
      (the tuning file states each rule as it is), the new finding → m8 (switching presets reconciles without
      growth, checked over many switches).
    - Not ported, not fixed: 3 (URL parameters are web-only; the app's settings go through `Settings.sanitized`).
      The sketch's hints for 11 stay as they are (web-only words).
    - Asked of the director: none (no finding goes against a decision).
  - Re-check 2 436917c (2026-11-20, of 4bcf693): the paused-toggle growth fixed (bounded and settling over six
    1,000-action runs); the fixtures reproduce byte for byte and replay correctly; default frames unchanged. New,
    routed to fix (s1 fix round 3, small, sketch only, briefs/s1f3.md): R2-1 (the fixtures say dt 0.016667, not
    exactly 1/60: encode the integer tick rate as the replay clock), R2-2 (unknown fixture names such as
    `constructor` accepted), R2-3 (pin the scenario viewport, or report when a planting click can't plant). m1's
    review also checks that the Swift replay uses exactly 1/60 s, never the JSON's rounded dt.
  - Re-check 3 66f4462 (2026-11-20, of 92149b3): R2-1, R2-2, R2-3 fixed (both fixtures replay exactly at 1/60 s;
    unknown names refused; the planting-click report works; default frames unchanged). New, low: R3-1 (an empty
    `fixture=` was silently ignored): fixed by the manager as a Small one-line change, 4e1b869 (an empty name is
    refused like any unknown one). The s1 review is closed: everything is fixed, carried into the port, or
    not ported (finding 3).

- t1-2, review 61e1f6e (2026-11-20), routed by the manager:
  - Fix (in the task's Files, this task caused or carries them): 1 (finite guards), 2 (tiny-viewport walls),
    3 (flower seekers reach the flowers: the plan's foraging needs it, so no director call), 4 (weak checks),
    5 (coverage check over seeds), 6 (CI-risk expressions), 7 (breeze and lean scale with the cell),
    8 (bloom keeps the land's clock), 10 (paths default 60 s, as the plan says).
  - Rewrite t3's brief: 11 (stale flower indices) and 7's second half (the world sets `Butterfly.scale`).
  - Later, for the director at t5's first still: 9 (tall stems sway at one rate and lean far; the plan allows it).
  - Earlier Noticed items 1–5 are covered by findings 6, 1, 8, 11 and 4(c).
  - Fix round 1 reported 2026-11-20 (1e11a1b, done with concerns): CI not yet run; a new per-beat speed surge for
    the white (0.45) to meet the strengthened 4(b); the morpho exempt from the frozen-wings sink part of 4(a). The
    re-check judges both.
  - Re-check 68288c7 (2026-11-20): all nine fixed. The white's surge judged faithful to the research; the morpho's
    exemption judged a model fact, nothing loosened. Two leftovers routed later (Noticed): a tighter morpho sink
    form, and a code comment's citation.
  - Before approval: t1-2 must pass CI (Swift 6.3.3), not only local checks.

- t5 report (bbab77d, 2026-11-20), concerns for the review to judge: `wingsDoNotFlicker` was rewritten before its
  first commit; wing width is stylised (tips drop) rather than the physical width; the breeze trail can't tell the
  pointer's air from the weather; the ground-band cache repaints most frames in a breeze. Also: reports/t5.md holds
  local folder paths, so meadow-t5 can't be pushed until the report drops them (fix round).

- t5, Codex review f09abc6 (2026-11-20), routed by the manager:
  - Rewrite t5's brief, then fix round 1 (the cause is the drawing approach, not one line), after the director says
    how the butterflies should look: 1 (butterflies don't read as butterflies: one slab, body lost in the wing
    letters, antennae inside the wing, swallowtail tails detached) and 3 (the painter drops the model's signed wing
    width; it belongs to the same wing drawing).
  - Fix: 2 (the flicker check passes a real violation; fix the raster and check true beat windows), 4 (the ground
    buffers allocate when the band grows), 5 (any moving plant redraws the whole ground band), 6 (plants above a
    lower display leak glyphs into its top row), 7 (a same-size relayout can keep the old garden), 9 (light + Calm
    check), 10 (meadow-still validates its numbers), and the report's local folder paths.
  - Fix round 1 reported 2026-11-20 (d6abff1, done with concerns): the bigger size is drawn only (flight still at
    the old size, because a monarch of 19+ cells fails t1-2's coverage check, whose wall margins are in
    wingspans); painter 0.36 ms a frame at 2560 x 1440 with 8 butterflies (was 0.14); closed wings drawn wider than
    true; round 0's report commit bbab77d still holds local paths, so meadow-t5's history needs rewriting before it
    is pushed. Routed after the re-check, together with its findings.
  - Re-check f79ba98 (2026-11-20): fixed 2, 3, 4, 5, 6, 9, 10; NOT fixed 1 (closed and clap poses lose the
    butterfly: outlines) and 7 (relayout cache misses a base-row shift). Also: drawn size outruns the flight's wall
    margins (a morpho's drawing leaves the screen at an edge); adding a butterfly allocates; malformed sizes
    accepted; old report commits still hold local paths. Second failed round on the look, so review.restart: the
    brief is rewritten ("Restart" in briefs/t5.md) keeping the open poses, flowers and fixes, on a fresh branch
    without the old history. Pending the director (closed wings as the solid underside; the flight using the drawn
    size).
  - Restart reported 2026-11-20 (87483a1, done with concerns): t1-2's free flight adjusted so coverage passes at
    the bigger margins (0.732 of the width against 0.7: narrow); the white's turning ratio at seed 92 now 1.24
    against 1.25; flowers within about 143–189 pt of a side edge can't be reached; butterflies at low flowers hang
    below the screen edge (both for t3); painter not re-timed. Fresh Codex review of the restart.
  - Restart review c9ddad3 (Codex, 2026-11-20), routed: fix 1, 2, 3 (drawing leaves the screen at the bottom on
    low-flower pursuits, on the 340 x 150 preview, and at tilted edges; add a check on real painted cells) and 5
    (clap: fold and face change reach real flight strokes, blended); rewrite t3's brief: 4 (edge flowers
    unreachable). The open, banked and closed poses now read (the look that failed twice passes). Noticed: the
    white's turning ratio exceeds its tolerance on 1 of 128 unchecked seeds.
  - Restart fix round 1 reported 2026-11-20 (a59f71f, done with concerns): the flight's point is now the mouth at
    a low flower, body drawn above (t3's landing must use it); on the 340 x 150 preview the drawing is placed up to
    about 72 pt from the flight's point and drawn smaller (0.58–0.88) for the three big species; the body's lean
    eases upright near walls so coverage passes (closest 0.713 width); painter not re-timed. Codex re-checks.
  - Restart re-check 3e4b76f (Codex, 2026-11-20): single-screen clipping fixed, but NOT fixed 1 (the drawn
    proboscis sits 7–8 rows above the flower; the flight's point and the drawing part ways), 2 (preview drawing
    moved up to 85 pt from the flight's point), 3 (wings reach into the gap of offset displays), 5 (banked claps
    still flip colour in one step). Second failed round, so review.restart: "Restart 2" in briefs/t5.md, one
    shared butterfly geometry for flight and drawing. It changes the design, so it waits for the director.
  - Restart 2 (simplified) reported 2026-11-20 (56d339e, done with concerns): workarounds removed, two checks
    retired as decided, four new checks; the builder set `foldedSideNeverFlips` at a third of the blocks per step;
    margins read as the earlier flight's (about 0.6 of the drawn wingspan); painter not re-timed. Fresh Codex
    review.
  - Restart 2 review 57f880a (Codex, 2026-11-20): workarounds really removed, body stays on screen (194,400 steps
    over offset layouts), preview whole, nothing loosened beyond the two retired checks, no allocation, painter
    0.38–0.40 ms at 8 and 0.72–0.74 ms at 16. Two findings, routed "ask the director" via the film: 1 (at the clap
    the folded wing can swap sides in one 60 Hz step when the bank crosses level) and 2 (the top-to-underside colour
    change can turn most of a wing in one frame). Both are 1–2-frame events inside a wingbeat; whether they show,
    and whether the morpho's flash should be that sudden, is the realism line the director sets after watching
    (decision of 2026-11-20). Not fixed blind.
  - Rewrite t3's brief: 8 (the pointer's breeze trail needs the pointer's air apart from the weather; t3 owns the
    pointer input).
  - The director on the stills, 2026-11-20: "would like bigger butterflies and better flowrs". In t5's fix round 1.

- t5v report (b8d4725, 2026-11-20), for the director's watch: the clap is a one-step snap every beat (a blink at
  real speed); the colour flips in 1–2 steps at most claps (the morpho's brown flash shows every few seconds); the
  folded wing jumps sides 78 times in 6 minutes of flight; butterflies pile up at the low flowers from about 8 s
  (the test scene; nothing keeps them apart yet); whites spend 18 % of the time within 60 pt of the bottom; the
  morpho's far wing shows as faint dots while opening; the white is faint on paper.

- t5v, Codex review 94d9d2b (2026-11-20), routed fix (small, in t5v's Files; batched with whatever the director's
  watch brings): 1 (a held frame can delete a directory named like the frame) and 2 (a shorter rerun leaves old
  frames): refuse an output folder that already holds frames; 3 (`--seconds 0` refused unlike the still) and 4
  (fps usage text lists six values, any divisor of 60 works): align.

## Noticed
- 2026-11-20, s1 fix round 3's builder: m1 (building) may have copied fixture format 1 (`step.dt` 0.016667). Format
  2 (meadow-sketch @ 92149b3) has `step.rate` 60 and no dt; the replay must step exactly 1/60 s and derive the wind
  sample points from the viewport, not the rounded ones in the file. Routed to m1's review (and its fix round if
  needed), not to the building task (task.change: its brief is frozen).
- 2026-11-20, m3's builder: when the Meadow joins `OceanTool bench --digest` (m8), the per-cell ground must be added
  to the digest in `Sources/OceanTool/Bench.swift`. Also m3's ruling: during a habitat dissolve, cells not yet
  revealed show the plain background, not their ground (the family's rule; the green fades in with the rest);
  the review judges it.
- 2026-11-20, s1 round 4's builder: "New meadow" removes the flowers the director planted (only density and flower
  size changes keep them); round 3's finished worktree still has `meadow-sketch` checked out with staged changes
  that would put the sketch back to an older state (not to be committed; clean up with the stale worktrees).

- From t1-2 (earlier review of plan T1, 2026-11-19), routed above on 2026-11-20:
  1. Long mixed-literal expressions at `Breeze.swift:328,329,382,412,421` and `Flowers.swift:646,653` may time out
     on CI's Swift 6.3.3.
  2. `Breeze.sample` can crash on a non-finite position; it needs a finite guard.
  3. `Meadowland.bloom(time:)` overwrites the land's own clock.
  4. A clicked flower's index can be reused after it is replaced, so T3 must tolerate stale indices.
  5. The check `breezeWriteIsLocal` passes mostly because of truncation; it is weak.
- From t1-2's re-check (2026-11-20): the morpho could be held to "sinks at least 0 pt" with frozen wings instead of
  skipping that part; the white's surge comment cites a between-flight speed spread, not a beat-to-beat one.
- From t5's restart review (2026-11-20): over 128 seeds the white's turning ratio passes on all but seed 54 (1.28
  against 1.25); the check's pinned seeds pass with room.
- From t5's restart 2 (2026-11-20): an earlier finished worktree (t3-988a7193…) still has `meadow-t5r` checked out
  with uncommitted edits in 4 files; left alone. Clean it up only after checking nothing there is wanted.
- From t5 and t5v (2026-11-20): at the top of a wingbeat the wings snap shut in one step, the colour flips in 1–2
  steps (the morpho's brown flash), and the folded wing can jump sides; the director watched and did not raise it.
