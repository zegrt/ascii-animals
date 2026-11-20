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

## Tasks

| Id | Task | Size | Files | Branch | Builder | Reviewer | Rounds | State | Brief |
|---|---|---|---|---|---|---|---|---|---|
| t1-2 | Breeze, flowers and butterfly flight (plan T1 + T2), with the director's path fix | Content | Sources/OceanKit/Meadow/{Breeze,Flowers,ButterflySpecies,Butterfly}.swift, Sources/OceanChecks/MeadowChecks.swift, Sources/OceanTool/{Paths,main}.swift | meadow-t1-2 | builder-t1-2 (Claude Opus, T3 child thread; fix round 1) | reviewer-t1-2 (Claude Opus, T3 child thread) | 1 | reviewed, waits for the end of the stack (director: no merge yet): reviewed (review-t1-2 @ 68288c7), CI passed on 1e11a1b (PR #1), merge rehearsed 2026-11-20 (200 passed, app builds) | briefs/t1-2.md |
| t5 | Meadow painter and `OceanTool meadow-still` (plan T5, as reordered); fix round 1 adds the director's bigger butterflies and better flowers | Content (grown: now also t1-2's sizes and flower shapes; the director set the look, so no separate plan) | Meadow/MeadowPainter.swift (new), OceanTool/{MeadowStill,main}.swift, OceanChecks/MeadowChecks.swift, Render/GlyphAtlas.swift (append only); fix round 1 adds Meadow/ButterflySpecies.swift (sizes) and Meadow/Flowers.swift (heads, leaves, clumps) | meadow-t5 (from meadow-t1-2) | builder-t5 (Claude Opus, T3 child thread) | reviewer-t5 (Codex) | 1 | building (fix round 1) | briefs/t5.md |
| t3 | Meadow world and behaviours (plan T3) | Content | Meadow/{MeadowWorld,Behaviour}.swift (new), OceanChecks/MeadowChecks.swift, Meadow/MeadowPainter.swift (convenience paint, breeze trail), Meadow/Breeze.swift (pointer field), OceanTool/MeadowStill.swift | meadow-t3 (from meadow-t5) | | Codex | 0 | open (waits on t5 reviewed: its Files overlap t5's) | briefs/t3.md |
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
  - Rewrite t3's brief: 8 (the pointer's breeze trail needs the pointer's air apart from the weather; t3 owns the
    pointer input).
  - The director on the stills, 2026-11-20: "would like bigger butterflies and better flowrs". In t5's fix round 1.

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
