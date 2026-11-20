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

## Tasks

| Id | Task | Size | Files | Branch | Builder | Reviewer | Rounds | State | Brief |
|---|---|---|---|---|---|---|---|---|---|
| t1-2 | Breeze, flowers and butterfly flight (plan T1 + T2), with the director's path fix | Content | Sources/OceanKit/Meadow/{Breeze,Flowers,ButterflySpecies,Butterfly}.swift, Sources/OceanChecks/MeadowChecks.swift, Sources/OceanTool/{Paths,main}.swift | meadow-t1-2 | builder-t1-2 (Claude Opus, T3 child thread; fix round 1) | reviewer-t1-2 (Claude Opus, T3 child thread) | 1 | reviewed, waits for the end of the stack (director: no merge yet): reviewed (review-t1-2 @ 68288c7), CI passed on 1e11a1b (PR #1), merge rehearsed 2026-11-20 (200 passed, app builds) | briefs/t1-2.md |
| t5 | Meadow painter and `OceanTool meadow-still` (plan T5, as reordered); fix round 1 adds the director's bigger butterflies and better flowers | Content (grown: now also t1-2's sizes and flower shapes; the director set the look, so no separate plan) | Meadow/MeadowPainter.swift (new), OceanTool/{MeadowStill,main}.swift, OceanChecks/MeadowChecks.swift, Render/GlyphAtlas.swift (append only); fix round 1 adds Meadow/ButterflySpecies.swift (sizes) and Meadow/Flowers.swift (heads, leaves, clumps) | meadow-t5 (from meadow-t1-2); restart on meadow-t5r | builder-t5 (Claude Opus, T3 child thread) | reviewer-t5 (Codex) | 2 before the restart; 2 after it; restart 2: 0 | reviewed (review-t5r2 @ 57f880a); clap findings to Noticed after the director's watch | briefs/t5.md |
| t5v | A 30 s film of the butterflies flying, for the director to judge the motion | Content (small) | OceanTool/MeadowFrames.swift (new), OceanTool/main.swift | meadow-t5v (from meadow-t5r) | builder-t5v (Claude Opus, T3 child thread) | Codex | 0 | reviewed (review-t5v @ 94d9d2b); its 4 tool fixes moved into t3 (which rewrites meadow-frames) | briefs/t5v.md |
| p1 | Throwaway prototype film of the Meadow seen from above, with depth | Prototype (never merged, no review) | new OceanTool files, OceanTool/main.swift | proto-top-down (from meadow-t5v) | builder-p1 (Claude Opus, T3 child thread) | none | 0 | built (proto-top-down @ de1f728); director's notes in Corrections | briefs/p1.md |
| t5w | A new wingbeat (both wings together), wing shading and detail, and butterflies that turn to face where they fly, learning from the director's reference | Content | Meadow/MeadowPainter.swift, Meadow/Butterfly.swift (drawn heading, open), OceanChecks/MeadowChecks.swift | meadow-t5w (from meadow-t3) | | Codex | 0 | open (waits on t3: same files) | briefs/t5w.md |
| t3 | Meadow world and behaviours (plan T3), with the director's film verdict | Content | Meadow/{MeadowWorld,Behaviour}.swift (new), OceanChecks/MeadowChecks.swift, Meadow/MeadowPainter.swift (convenience paint, breeze trail), Meadow/Breeze.swift (pointer field), Meadow/{Butterfly,ButterflySpecies}.swift (roaming, spacing, stays), OceanTool/{MeadowStill,MeadowFrames,main}.swift | meadow-t3 (from meadow-t5v) | builder-t3 (Claude Opus, T3 child thread) | Codex | 0 | held (2026-11-20: the view may change to top-down); WIP saved at meadow-t3 @ 11394be (does not build yet; checks written, world not started) | briefs/t3.md |
| t4 | Cursor landing, courtship, crossings, monarch life cycle (plan T4) | Content | to brief | meadow-t4 | | | 0 | open (waits on t3) | |
| t6 | Meadow habitat, settings and tools (plan T6) | Content | to brief | meadow-t6 | | | 0 | open (waits on t4) | |
| t7 | Director reviews the prototype films (plan T7, a gate) | Content | none | none | | | 0 | open (waits on t6) | |
| t8 | Energy, measured with the director (plan T8) | Content | to brief | meadow-t8 | | | 0 | open (waits on t7) | |
| t9 | Choosing the Meadow: menu, Settings, welcome (plan T9) | Content | to brief | meadow-t9 | | | 0 | open (waits on t8) | |
| t10 | Words, watch and release 3.1 (plan T10; outward-facing, the director approves the release) | Content | to brief | meadow-t10 | | | 0 | open (waits on t9) | |

## Review routing

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
