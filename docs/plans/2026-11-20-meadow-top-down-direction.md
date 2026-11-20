# Meadow: a new direction, seen from above (proposal, 2026-11-20)

Status: proposal for the director. Nothing is built from it until the director approves it.

## The director's feedback in this set, and what it points at

| # | The director said | What it really asks for |
|---|---|---|
| 1 | Flight paths "clustered at the center of the screen" | use the whole screen |
| 2 | "bigger butterflies and better flowers" | butterflies you can see in detail; a richer meadow |
| 3 | Closed wings drawn as outlines: "why are some just outlines?" | a butterfly is always a solid shape |
| 4 | "butterflies can flutter a bit off screen, in between screens it was neveer a iusse" | don't fight the edges |
| 5 | Learn from how the sharks and spiders were built | simple wants; one body for motion and drawing |
| 6 | Keep the physics "if it makes it look better"; realism is "a line drawn in sand", set after seeing motion | judge by eye, in motion |
| 7 | First film: "to many", "they gather around to mcuh", "roam around the same places", "not enough movevemt" | few, spread out, always travelling, everywhere |
| 8 | "only the left wing is moving and the right wing dissapears" | both wings beat together |
| 9 | The wingbeat reference: learn from it, don't copy; "a bit more detail and not just one flat color" | a designed beat; shaded, detailed wings |
| 10 | "rotatea around when moving" | butterflies turn to face where they fly |
| 11 | "a top down view into the scene", "can come closer and further away from the viewpoint" | a view from above, with depth |

Read together, these are one picture, not eleven fixes: **a meadow seen from above, a few richly drawn butterflies
wandering the whole screen, turning freely, rising toward you and sinking to the flowers.** The side view we built
from the research is what most of the notes are pushing against: it puts the flowers in a strip at the bottom
(1, 7), pulls butterflies down with gravity (1, 7), and can't turn a butterfly to face where it flies (10). Its
wings were already drawn from above (8, 9). The two shipped habitats are both flat, seen-from-above worlds (5).

## The direction

**One meadow seen from above, with depth.** Each butterfly has a position on the screen (x, y) and a height above
the meadow (z, from 0 on a flower to 1 just under the glass).

- **Height is size.** Drawn size grows with height (for example 0.6 × on a flower to 1.6 × near the viewer), so
  butterflies vary in size all the time, the near ones show their wing detail, and "bigger" (2) comes for free.
- **A shadow** on the meadow, offset by height and fainter the higher it flies, meets the butterfly when it lands.
- **Depth order:** nearer butterflies draw over farther ones, and spacing (7) applies among butterflies at similar
  heights, so two at different heights can cross without looking like a clump.
- **The physics moves to the height axis.** Lift on the downstroke, gravity, glides that sink and flapping that
  climbs now act on z: a glide drifts down toward the flowers, a flapping bout rises toward you (6). The wingbeat
  rhythm, zig-zag jinks, gusts and the heading spring carry over unchanged.
- **Turning:** the whole butterfly turns to face where it flies (10), all the way round, smoothly.
- **Wings:** both beat together, never vanish, have a designed rhythm, and are shaded and detailed (8, 9). A
  basking butterfly shows its wings open flat, the most beautiful view of a butterfly; a resting one closes them
  to a narrow blade.
- **Flowers everywhere, sparse:** blooms seen from above (petal rings round a centre, umbels, clover heads) in loose
  patches across the whole screen, not a strip at the bottom (1, 7). Grass is a faint texture that ripples as the
  breeze passes. Kept sparse and dim, like the sharks' sea, so the desktop stays calm.
- **Edges:** butterflies fly off an edge and come back (4), as the reference does; the body stays on a screen most
  of the time.
- **Fewer, always moving (7):** about 3 on a laptop, 9 on a big monitor; most flying at any moment; short stays.

## What carries over, what changes

- **Carries over:** the breeze field (already a flat x, y field), the flight's heading, beat, jinks and glides, the
  behaviours being built in t3 (wants, feeding, basking, scattering, spacing, roaming), the painter's cell canvas,
  sizes and species markings, the energy budget and every Ocean and Web guarantee.
- **Changes:** flower layout and drawing (blooms from above, anywhere), the painter's ground band (gone; grass
  texture instead), the flight's vertical axis (becomes height), the checks built on the side view (bob in rows,
  glide angle on screen, the bottom-row coverage, low-flower reach): replaced with checks of the new rules.
- **Plan decisions this revisits:** "flowers along the bottom edge of each screen rect" (Global Constraints and
  "Several displays"), "a click blooms a flower in the ground band below the click's column" (a click now blooms
  where you click), and the monarch life cycle's hanging chrysalis (a side-view image: drawn from above it reads
  less clearly; the director decides whether to keep the life cycle in 3.1).

## How to decide: a prototype first

Before rewriting the plan, one builder makes a **throwaway prototype film** on a scratch branch: the top-down meadow
with depth, scattered flowers, shadows, turning and a first designed wingbeat, about 4 butterflies, 30 s at real
speed. The director watches it next to the current side-view film and picks. Only then is the plan rewritten
(tasks t3, t4, t5w, t6 and the life cycle), and that rewrite comes back to the director before any build.
