# Brief t5w: a real wingbeat, and butterflies that turn to face where they fly

Size: Content
Board commit: the commit that adds this brief (main)
Branch: meadow-t5w, made from `meadow-t3` (tasks stack; runs after t3 because both change the same files)

## Objective
The director, after watching the first films: "it looks like onyl the left wing is moving and the right wing
dissapears on motion towards close", then: "i have a wing beat referene, look properly. also dont take anything
else from this it doesnt have the life stuff we have. also want the butterflies to like rotatea around when
moving (idk how much is possible)". The reference is https://www.pocketstudio.design/ascii-animals-app/ (its
butterfly). Take exactly two things from it, the wingbeat and the turning; keep everything else ours (behaviours,
flight, flowers, species, colours and markings).

## What the reference does (read by the manager from its script, 2026-11-20)
- **Seen from above, and it turns.** The whole butterfly (wings, body, antennae) is drawn in its own body frame,
  rotated to its heading. The heading turns toward the direction of travel at a limited rate (about 7 rad/s) and
  only while it is moving (speed above about 12 px/s), so it swings round smoothly, all the way round if it needs
  to. A small wobble of about 0.06 rad rides on the wingbeat.
- **Both wings beat together, symmetrically.** One value `open` sets how wide both wings are, measured across the
  body axis: a wing point at distance d from the axis is drawn as if at d / open. So both wings narrow toward the
  body together and open together; they never vanish (`open` never goes below 0.1).
  `open = 0.1 + 0.9 * (pow(0.5 + 0.5 * cos(phase), 0.8) * (1 - glide) + 0.96 * glide)`: the beat dwells a little
  longer open than closed, and a glide holds the wings almost flat open.
- **Light follows the beat:** the wings are drawn at brightness 0.6 + 0.4 × open, so closing wings darken a
  little. The beat rate rises a little with speed and almost stops in a glide.
- Forewing and hindwing are two lobes, each a polar outline (angle range, reach, a peak, a roundness), with darker
  edges and veins; the body is a thin line with two antennae lines.

## What to change in ours
1. **Rotation:** draw each butterfly rotated to a body heading that follows its direction of travel as above
   (smooth, rate-limited, full circle, wobble on the beat). A perched or resting butterfly keeps the heading it
   landed with. Flight itself is not changed.
2. **Wingbeat:** replace the wing narrowing, the one-sided fold at the top of the beat and the in-flight underside
   switch with the reference's symmetric `open` scaling, including its curve, its 0.1 floor, the glide hold and the
   brightness. Keep our species shapes, sizes, colours and markings; they scale with `open` like the reference's
   lobes.
3. **Rest:** a butterfly resting with its wings closed shows them narrow (open near its floor) in the underside
   colour; basking holds them open. The director judges both in the film.
4. **Checks:** checks that test the replaced design (for example `foldedSideNeverFlips`, `clapTurnsOverAtEveryBank`,
   `clapReadsAsAButterfly`, `wingsUseSignedWidth`, `edgeOnIsALine`, and any other that asserts the old fold or
   signed widths) are replaced, on the director's decision, by checks of the new rule: in every flight frame both
   wings are drawn and have the same width within a cell; the drawn wing width follows `open`; the butterfly's
   drawn axis follows its heading within the turn-rate limit; nothing allocates per frame; no flicker beyond the
   beat itself. Name every replaced check in the report. Every other check stays, unloosened.

## Output and done when
Code on `meadow-t5w`; the whole suite passes; a new pose sheet (each species at several `open` values and headings,
dark and light) and two films at 1440 × 900 (`OceanTool meadow-frames`): 30 s real speed and 10 s quarter speed,
watched and described in `reports/t5w.md`, side by side in words with the reference's look. No local folder paths in
commits or files; film paths only in the final message.

## Files
`Sources/OceanKit/Meadow/MeadowPainter.swift`, `Sources/OceanKit/Meadow/Butterfly.swift` (the drawn heading and
`open`, if they live there), `Sources/OceanChecks/MeadowChecks.swift`.

## Out of scope
Anything else from the reference (its flight, steering, trails, flutter, page). Behaviours and flowers. Anything
else you notice goes under Noticed.
