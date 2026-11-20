# Brief p2a: look development, part 1: butterfly motion seen from above, and wingbeat speed

Size: Design, approved by the director as a look-development step ("ok", 2026-11-20). Look development: it is not
reviewed now; whatever of it the plan keeps gets built and reviewed in the rewritten plan's tasks.
Board commit: the commit that adds this brief (main)
Branch: look-top-down, made from `proto-top-down` (the p1 prototype)

## Objective
The director chose the view from above and, watching the p1 prototype, said: "the wing beat loosk too infreent and
slow", "it doenst move like a butterfly anomore", and that fidelity and quality are missing. The prototype used a
quick smooth stand-in flight; smooth curving paths are how birds and fish move. This part makes the butterflies move
like butterflies again, seen from above, and finds the wingbeat speed the director wants.

## What to build
1. **The measured flight, turned on its side.** Port the per-beat force model of `Butterfly.fly` (research §1.4;
   t1-2) to the top-down view instead of the stand-in: the forward lurch at each downstroke and the zig-zag jinks
   at the clap act in the screen plane; lift on the downstroke and gravity act on height z (flapping climbs toward
   the viewer, gliding sinks toward the meadow); the heading spring, flap bouts and glides per species, gusts in the
   plane. The body's bob becomes a small per-beat pulse in drawn size and shadow. Keep each species' signature (the
   monarch's long glides, the swallowtail's floating, the white's restless zig-zag, the morpho's deep slow bounds).
   Build it so the side-view flight and its checks keep working (a separate mode or file is fine); the whole suite
   must pass.
2. **Wingbeat speed.** Make the beat rate a parameter: today screen beat = real × 0.28 capped at 3 Hz. Offer three
   faster settings for the director to compare, for example real × 0.45, × 0.65 and × 0.85 (monarch about 4, 6 and
   8 Hz), with less gliding at the faster ones if it reads better. At 30 fps keep at least 4 frames per beat.
3. **Keep from p1:** the drawing seen from above, turning to face where they fly, size from height, shadows, the
   ground mainly black with hints of green, the flowers as they are (flowers are a later part).

## Output
Films at 1440 × 900 with ffmpeg (/opt/homebrew/bin/ffmpeg), about 4 butterflies, same seed:
- one 20 s film per beat setting (current, and the three faster), real speed;
- one composite of the four side by side (scaled down, labelled with the setting) for direct comparison;
- 10 s at quarter speed of the middle setting.
Watch them and say in `reports/p2a.md`, honestly, whether each species now moves like a butterfly, and how the
speeds compare. Film paths only in the final message.

## Files
Free within new files under `Sources/OceanTool/` and `Sources/OceanKit/Meadow/` (prototype or new flight mode),
plus `Sources/OceanTool/main.swift` and additive changes to `Butterfly.swift`/`ButterflySpecies.swift` that don't
change side-view behaviour. Never edit or loosen a check.

## Out of scope
Flowers, wing art and the species sheets (later parts), behaviours, settings, the app.
