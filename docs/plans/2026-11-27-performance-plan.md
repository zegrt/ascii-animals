# Performance before 3.1: plan for the director

Asked for: "before we push 3.1 we need to massively improve performance and reduce cost without sacrificing the
motion and quality and fidelity" and "research and think and plan and getback to me" (the director, 2026-11-27).
Basis: audit a2 (`origin/review-a2:reviews/a2.md`), a code read of `meadow-3.1` @ 0dfbb9a and a macOS
compositor survey (2026-11-27). Nothing in this plan has been built or run.

## Where the cost is

- On two exposed displays at 30 fps the app uses 11–14% CPU and WindowServer rises from 7–9% idle to 26–30%.
  At 15 fps WindowServer is 17–19%. So most of the cost is macOS redrawing the screen for each of our frames,
  about 0.25 WindowServer points per frame per second, not our own drawing.
- Our own work can drop by about 1 point at most, even with a full rewrite (a2).
- macOS has no way to tell WindowServer "only this part changed" for our kind of surface. Each frame redraws the
  whole screen, including whatever sits above the wallpaper: desktop icons, widgets, the menu bar, the Dock and their
  glass blur, which must be recomputed when the picture under them moves.

## What saves the most without touching the motion

1. **Draw nothing when the desktop can't be seen.** The app trusts macOS's "covered" signal. Other wallpaper projects
   report that this signal never fires for a desktop-level window covered by ordinary app windows. If that holds for
   us, the app spends the full 26–30% all day behind your windows. This is likely the largest saving, and it changes
   nothing you can see. There is also a sure bug: a display covered before its first frame (for example, the app
   starting under a full-screen app) keeps drawing at full rate (`OceanDirector.swift:137–141`).
2. **Small savings that keep every pixel the same:** a handler attached to every frame instead of only the first,
   a per-frame tally nobody reads, a ground clear and an overlay upload the Meadow never uses, 60 empty warm-up
   frames in the previews, a 30-second timer without tolerance. Together under 1 point; low risk.

## What would cut the cost of a visible desktop

Only fewer full-screen frames, or less work above the wallpaper, will cut it a lot. Each of these is your call:

- **An even rate on the 100 Hz external.** 30 can't be shown evenly at 100 Hz, so today it runs at 33.3. Asking for
  the nearest even rate gives 25 there: about 25% fewer frames on that screen, about 2 WindowServer points. The
  built-in (120 Hz) keeps exactly 30. That is a motion change you'd judge by eye.
- **Only redraw the parts that changed** (a still base plus small updated tiles). Firefox cut power several-fold
  this way, but our changes are spread out: the Meadow's grass sways across 9–39% of cells every frame, and the
  Ocean changes everywhere. Tiles would only pay if the swaying grass updated less often, which is a motion change.
  This is large work, and whether it pays depends on one measurement (below).
- **Lower resolution or a video loop**: these lose fidelity or interaction. Not recommended.

## Next step: one measured session with you (about 30 minutes)

Two questions decide the design. Only your Mac can answer them, so this needs you at the desk with the test copy
(`ASCII_ANIMALS_NO_HANDOVER=1`, the test settings, your real wallpaper untouched), and `powermetrics` run by you
(it needs your password):

- a. Cover the desktop with a maximized window, then a full-screen app. Does the app stop drawing? (Frame counts in
  the log.)
- b. At 30 fps: is WindowServer's cost about the size of what we draw, or about each frame? We'd show the same
  habitat in a small window vs full screen. Also measure with Reduce Transparency on and off and the Dock hidden.
- c. 25 vs 33.3 on the external, so you can see the motion and we can measure the saving.

Before the session (with your go): a builder adds a count of frames actually shown on screen to the energy log,
lets `Tools/energy.sh` accept 25 when 30 is asked, and builds the test copy. No visible change.

## Proposed order

1. Your go on this plan and the session.
2. Instrumentation (above), one builder, one review.
3. The session: a, b, c.
4. For 3.1:
   - the first-frame fix and the small identical-pixel savings;
   - if (a) shows the app keeps drawing when covered: a cheap check of what's on screen (the window list, a few
     times a minute and on app or Space changes), so a covered display stops drawing;
   - the even rate if you approve it after (c).
5. Later, only if (b) says the cost follows the area drawn: the tiled design, Meadow first, in 3.1.1 or 3.2.

What we can't promise yet: a big cut on a fully visible desktop without changing the motion. If (b) shows the glass
above the wallpaper drives the cost, that is a macOS setting we can mention, not something the app controls.

Research notes, beside this plan:
- `2026-11-27-perf-research-macos.md`: compositor costs, other wallpaper apps, pacing and occlusion, with sources.
- `2026-11-27-perf-research-code.md`: the frame path at 0dfbb9a, the visibility gaps, the pacing fix and the tile
  sketch.
