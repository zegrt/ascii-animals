Team rules: the agent-team skill; read it first.

# ASCII Animals: work board

<!-- Only the manager edits this file. Basis: the director, 9 Nov 2026. History up to 2026-11-25 (Corrections,
Decisions, Review routing, the full task ledger): docs/history/3.1-workboard.md. -->

## Where files go

| File | Branch | Written by |
|---|---|---|
| WORKBOARD.md, briefs/<id>.md, everything merged | main | manager only |
| the work, reports/<id>.md (one page at most) | the task's branch | its builder |
| reviews/<id>.md | review-<id>, made from main | its reviewer |

Last approved state: tag `v3.0.1`.

## Roles

| Role | Who | Where |
|---|---|---|
| Director | the owner | the owner's Mac |
| Manager | Claude (Opus) | the main T3 thread for this project |
| Builder | one Claude agent per task, one at a time | its own worktree |
| Reviewer | one Codex agent (medium) per review | its own worktree |

## Project rules

- The plan: `docs/plans/2026-11-19-meadow-3.1-plan.md` as cut back by `docs/plans/2026-11-20-meadow-port-plan.md`
  and `docs/plans/2026-11-25-cut-the-creep.md`.
- Only the manager pushes, after the private-string scan (the pattern is kept outside the repo). Builders and
  reviewers commit only.
- Safety on the owner's Mac: never launch the app without `ASCII_ANIMALS_NO_HANDOVER=1`; never run the bare binary
  without a `--snapshot-*` flag; never touch `~/Applications` or the app's real defaults domain (only
  `Tools/energy.sh` or the test copy's domain, only with the director); never run the old Sharks uninstaller; no live
  desktop runs and nothing on the owner's display without the director; a test copy never changes the real wallpaper
  (matching off) and never downloads or installs a real update; a test must never raise a real destructive dialog.
- CI's Swift is 6.3.3: give literals and SIMD maths explicit types; long check closures become named local functions.
- Commits use the repo's author identity and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  (Codex reviewers: `Co-Authored-By: Codex <noreply@openai.com>`).
- Plan and prep is not a go. Nothing starts without the director's go.
- In force from 2026-11-25 (the director: "ok to all three"): one review and one fix round per task. A re-check
  only for a crash, data loss, a privacy leak or a broken habitat. A finding is fixed in 3.1 only if a user would hit
  it in normal use; the rest goes to 3.1.1. The board holds only what's pending.

## 3.1 candidate

| Part | Branch @ SHA | State |
|---|---|---|
| Meadow, card, welcome, energy (t11 stack) | meadow-t11 @ 20cdb3c | approved (review-t11-r3 @ b03d17f); live card look at the join |
| Pointer input (r1b) | meadow-r1b @ afa861f | approved (review-r1b-r2 @ d158c7c); banner re-test with the director |
| Updates, settings, diagnostics (r3) | meadow-r3 @ 633a682 | fix round 3 running (go 2026-11-25; briefs/r3.md "Fix round 3": a report reads only entries this version wrote; an unfinished last entry dropped; proof from briefs/r3-recheck2-probe-checks.patch); then one privacy re-check |
| Wallpaper recovery (r2) | meadow-r2 @ bb6df14 | re-check review-r2-r1 @ 1086bf7: changes requested (4 open, all from deleting stills and per-still records); rebuild briefed (briefs/r2.md "Rebuild on the root fix", go 2026-11-25), starts after r3's builder; then one review, a re-check only for data loss |

Trial join (2026-11-25, scratch only, on t11 20cdb3c + r1b afa861f + r3 633a682 + r2 d9e05a0): one conflict
(`Sources/OceanChecks/main.swift`, `greetingChecks()` and `pointerChecks()`, keep both); build passes, 334 checks,
selftest 0 failed.

## Next, in order

Paused after r3's fix round 3 reports in (the director: "after the fix pause"); nothing below starts without a go.
1. r3 fix round 3 (running), then its one re-check (privacy).
2. r2 rebuilt on the root fix: two reused files per display, written alternately, never deleted in normal use; the
   covered wallpaper in the file name; a file in our folder is ours, anything else is the person's; restore each
   Space on its next visit; do nothing when a read fails; uninstall restores the Space in view, keeps the small
   folder and says so; 3.0 and Sharks stills left on disk, restored to their display's saved original. The brief
   checks 3.0's limit of 3 stills per display. Then one review.
Steps 3-5 wait for the director's go.
3. The join: `meadow-3.1` from meadow-t11 plus r1b, r3, r2; a draft PR for CI; one Codex review of the merge only.
4. Copy, with the director's OK: briefs/copy-unslop.patch (the director's /unslop, 29 lines in 10 files, made on the
   trial join; re-apply after r2 and r3 change their files) plus three README/CHANGELOG fixes (the card "once": an
   unanswered card can come back twice; "deletes everything it saved": uninstall can keep the stills folder; the
   battery claim: Meadow's WindowServer 29.7 % vs Web's 26.3 %).
5. Release notes and the 3.1.1 list.

## With the director

- The notification banner re-test on r1b's test copy (`build/ASCII Animals Test.app` in its worktree; say "ready").
- One live session on the joined test copy: the card, the welcome, Report a Problem's text (then Cancel), the
  "couldn't restart" message if it can be shown safely.
- The wallpaper check on a separate macOS account, with "Show on all Spaces" and an upgrade from 3.0.
- The release go, then merge, tag and publish.

## 3.1.1 (from the history file)

- a1, deferred by the director's scope call (2026-11-21): findings 3 (sleep, lock, held frames), 6 (display
  relayout), 7 (GPU backpressure, presented frames), 8 (identity and migration side effects), 9 (pacing), and the
  rest of 10 (login approval, hotkey status, theme refresh, locale).
- a2: desktop eligibility, presented-frame counts and pacing as one owner with a1 6, 7, 9 (a2 findings 1-3);
  Settings and About previews' lifecycle (4-5); renderer resources and the Ocean path (5, 6, 9); Web and Meadow
  painters under byte-equality checks (7, 8); the live attribution of the Meadow's WindowServer gap with the
  director; option A (a deadline-driven display link) trialled after eligibility. Later, the director's product
  calls: B, E, H, G.
- Trimmed from the 3.1 briefs (2026-11-21): the reminder checkpoint write; r2's stale-job stage checks.
- r2 finding 4 (a force quit between saving the original and setting the still), if the rebuild leaves it.
- r3 finding 7 (cleanup on the main thread after the split).
- t11 minor: Reduce Motion turned on during the tour's pointer or splash step leaves that step's words over a still.
- The WhatsNewCard debug probe (about 380 lines) moved out; one copy of `air-flowers.json`; `Tools/energy.sh` cut
  to the modes still used.

## After the release tag (approved 2026-11-25)

- Delete the local branches merged into main or a join head with `git branch -d`, from a list regenerated then.
  The unmerged superseded branches stay; ask the director about them.

## Noticed (still open)

- Source comments and `Sources/OceanChecks/Fixtures/README.md` still point at `meadow-sketch` @ 4e1b869; they can
  point at `Tools/meadow-sketch/` with the next task that touches them.
- The allocation checks' tracker crashes the run instead of reporting a FAIL; fix with the next task in the checks'
  helper.
