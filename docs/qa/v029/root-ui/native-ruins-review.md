# Native map geometry review
2026-10-04 04:31–04:34 UTC, dot cloud Linux desktop, isolated root-ruins-native profile. Actual CUA mouse and keyboard, no input simulation from model methods.

Clicked town, map device, selected Broken Ruins, crafted and launched. Observed two staggered pale stone walls on warm paving; visible feet match the authoritative rectangular wall footprints. Normal mode retained the prior cool green paving and no walls.

Held A 1800ms from the center: character stopped at the right edge of the left wall, not through it. Initial attempt to route around was interrupted by character death; it is not recorded as a successful route. Clicked the real Restart button, then held A 1500ms, S 900ms, A 800ms: character reached the lower-left side beyond the first wall (observed client position approx313,510 vs wall x387–419 and lower end469), demonstrating an open route around its lower end. Live enemies visibly use the open ends rather than filling wall interiors.

Death revealed no accessible town-return action in the full-screen death menu. Added a map-only Return to Town button and reset the death route latch only after successful authoritative return. A focused wiring test covers this change separately.

This is not a hardware FPS measurement or Windows-native verification. Tool-returned native screenshots were inspected but not saved as local PNG assets.
