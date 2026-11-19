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
| Builder / reviewer | Claude agents, one per task or review | the owner's Mac, each in its own worktree next to the main folder |

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

## Tasks

| Id | Task | Size | Files | Branch | Builder | Reviewer | Rounds | State | Brief |
|---|---|---|---|---|---|---|---|---|---|
| t1-2 | Breeze, flowers and butterfly flight (plan T1 + T2), with the director's path fix | Content | Sources/OceanKit/Meadow/{Breeze,Flowers,ButterflySpecies,Butterfly}.swift, Sources/OceanChecks/MeadowChecks.swift, Sources/OceanTool/{Paths,main}.swift | meadow-t1-2 | earlier agents (5496bbf, 0cce823) | to assign | 0 | built | briefs/t1-2.md |
| t5 | Meadow painter and `OceanTool meadow-still` (plan T5, as reordered) | Content | to brief | meadow-t5 | | | 0 | open (waits on t1-2 merged) | |
| t3 | Meadow world and behaviours (plan T3) | Content | to brief | meadow-t3 | | | 0 | open (waits on t5) | |
| t4 | Cursor landing, courtship, crossings, monarch life cycle (plan T4) | Content | to brief | meadow-t4 | | | 0 | open (waits on t3) | |
| t6 | Meadow habitat, settings and tools (plan T6) | Content | to brief | meadow-t6 | | | 0 | open (waits on t4) | |
| t7 | Director reviews the prototype films (plan T7, a gate) | Content | none | none | | | 0 | open (waits on t6) | |
| t8 | Energy, measured with the director (plan T8) | Content | to brief | meadow-t8 | | | 0 | open (waits on t7) | |
| t9 | Choosing the Meadow: menu, Settings, welcome (plan T9) | Content | to brief | meadow-t9 | | | 0 | open (waits on t8) | |
| t10 | Words, watch and release 3.1 (plan T10; outward-facing, the director approves the release) | Content | to brief | meadow-t10 | | | 0 | open (waits on t9) | |

## Noticed

- From t1-2 (earlier review of plan T1, 2026-11-19), to route when t1-2's review lands:
  1. Long mixed-literal expressions at `Breeze.swift:328,329,382,412,421` and `Flowers.swift:646,653` may time out
     on CI's Swift 6.3.3.
  2. `Breeze.sample` can crash on a non-finite position; it needs a finite guard.
  3. `Meadowland.bloom(time:)` overwrites the land's own clock.
  4. A clicked flower's index can be reused after it is replaced, so T3 must tolerate stale indices.
  5. The check `breezeWriteIsLocal` passes mostly because of truncation; it is weak.
