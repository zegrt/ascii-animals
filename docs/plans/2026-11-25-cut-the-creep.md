# Cut the creep, ship 3.1

Status: draft, waiting for the director's go. Nothing in it has started.

Basis: the manager's audit and a blind Codex audit (2026-11-25), which agree: the worst creep is process
(reviews, re-checks, reports, the board), then quality checks enforcing invented rules, then complexity in
supporting tools. The scope growth since 2026-11-21 ("users first") was the director's decision and stays.

## Rules from the go onward

1. One review and one fix round per task. A re-check only for a crash, data loss, a privacy leak, or a broken
   habitat. Anything else a review finds goes to 3.1.1.
2. A finding is fixed in 3.1 only if a user would hit it in normal use. Fake-desktop corner cases go to 3.1.1, or
   get settled by the live session.
3. Reports are at most one page: what changed, what was checked, what's open.
4. The board holds only what's pending: candidate SHAs, open decisions, release gates. History lives in git.

## Steps (one builder at a time, as now)

1. **r2: the manager's root-fix proposal replaces this plan's r2 step.** In the main thread (2026-11-25), the
   manager proposed rebuilding r2: two reused files per display (A/B), so nothing is deleted in normal use; the file
   name carries the wallpaper it covers; and the app does nothing when it can't read something. That removes all
   four open findings and the pile-up of stills (3.0 keeps 3 per display; r2 as built keeps every still until a
   clean restore). The director decides on that proposal there. Rule 1 still applies: one review, plus one re-check
   only for data loss.
2. **r3 fix round 3 as already routed:** an opted-in report reads only whole entries this version wrote. This is a
   privacy item, so it gets one re-check.
3. **The join:** `meadow-3.1` from meadow-t11 plus meadow-r1b, meadow-r3 and meadow-r2 (the trial found one
   conflict and 334 passing checks). Then a draft PR so CI runs on Swift 6.3.3, and one Codex review of the merge
   only.
4. **Copy, with the director's OK:** apply the unslop patch (29 lines), plus three accuracy fixes the blind audit
   found:
   - The changelog says the card shows "once", but an unanswered card can come back twice.
   - "Deletes everything it saved" vs r2 keeping unresolved recovery data.
   - "Easy on your battery" / "costs no more": Meadow's WindowServer cost was higher on the measured desk (29.7 %
     vs Web's 26.3 %).
5. **Live session with the director (one sitting):** the notification banner re-test, the card and welcome on the
   joined copy, Report a Problem's text (then Cancel), and r2's separate-account proof including "Show on all
   Spaces".
6. **Release:** the director's go, then merge, tag and publish.

## Housekeeping (no app changes; can run beside step 1)

- **Slim the board:** move Corrections, Decisions history and Review routing to `docs/history/3.1-workboard.md`.
  The new WORKBOARD.md keeps Roles, Project rules, the rules above, pending items, candidate SHAs and gates. Drop
  the superseded task rows (t1-2, t5, t5v, t5w, p1, p2a, t3, t4, t6, t7, and m2, m4–m7, which mp replaced).
- **Branches:** 102 of 138 local branches are already contained in main or a join head; delete them after the
  release tag. Keep `meadow-sketch` (the director's reference) and the join heads until the release.
- **Worktrees:** 113 besides the main folder, 40 of them with uncommitted edits (mostly `Sources/` and
  `reports/`). Check each one. Save anything that isn't already on a branch to a `wip-<name>` branch, then remove
  it. Never a blind `git worktree prune --force`.

- **Keep until the release (the manager's list, 2026-11-25):**
  - Worktrees of the join heads: t3-477768ad… (meadow-t11), t3-27df3392… (meadow-r1b, which holds the test copy
    for the banner re-test), t3-5272efb9… (meadow-r3), t3-84f209de… (meadow-r2).
  - The jointrial worktree in the manager's scratchpad, until the real join.
  - Branches review-r3-r2 and review-r2-r1. Their worktrees (t3-7f318dea…, t3-1ebb8cdd…) are clean and can go.
  - All remote review-* branches, because the board's history cites their SHAs.

## Prep done (read-only, 2026-11-25; drafts in the session scratchpad, nothing run)

Drafts were kept in the housekeeping thread's session scratchpad (not in the repo). The board was adopted and
the probe patch saved as `briefs/r3-recheck2-probe-checks.patch` (2026-11-25).

- `wt-inventory.tsv`: all 113 worktrees with their branch, state and whether HEAD is on a branch.
  - 72 are clean, 41 have uncommitted edits.
  - Only the jointrial worktree has a HEAD on no branch (keep until the join).
- `wt-dirty.tsv`: for 38 of the 41 dirty worktrees, every edited file's content already exists in git. The
  other 3 are:
  - `tmp.n57GoiJrom/fixed` and `/proof`: logs only.
  - `tmp.pBI7uehTEV/probe`: the r3 re-check-2 reviewer's two reproducing checks, saved as
    `r3-recheck2-probe-checks.patch` for r3's fix round 3.
- `housekeeping-worktrees.sh` (draft): removes 67 clean and 38 already-saved dirty worktrees, holds the 3 above,
  and keeps the join heads' and jointrial. Re-run the inventory just before running it.
- `housekeeping-branches.sh` (draft, after the release tag only): `git branch -d` for 97 branches already in main
  or a join head. It lists 33 superseded branches that aren't merged anywhere, kept for the director's decision.
- `WORKBOARD.slim.md`: a draft of the slim board (85 lines, down from 872), for the manager to adopt.

## 3.1.1 (after the release, each one asked first)

- Move the roughly 380-line debug probe out of `WhatsNewCard.swift`.
- Keep one copy of the 588-line `air-flowers.json` fixture.
- Cut `Tools/energy.sh` (192 lines at 3.0 → 1,126) down to the modes still in use.
- The r2/r3 items deferred above, and the a1/a2 items already listed for 3.1.1.
- The card's showing rules (20 s, return after 3 h, at most three showings) were the director's asks. They change
  only if the director wants them simpler.
