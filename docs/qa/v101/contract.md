# Ginkgo inner-circle / outer-ring contract

Source baseline: `bdea0872bc3542aa784cb616dfbf43fb4b1b984d`.
This is a new Ginkgo boss behavior, not an equivalent damage-path optimization.

The existing self-at-start attack locks one world-space center. It warns for
1.4 seconds, then strikes a radius-130 circle for 0.6 times frozen contact
components. A full additional 1.0-second warning precedes an annulus with inner
radius 130 and outer radius 240, also at 0.6 times the same frozen components.
Only after the second event does the existing attack-speed-scaled recovery run
(base 1.9 seconds). Nominal combined multiplier is 1.2; existing avoidance,
immunity, shield, mana sharing, armour and resistances still govern actual loss.

Circle-body contact with either ring edge counts as intersection. For the real
player radius 15, a center distance below 115 is fully inside the safe hole;
above 255 is fully outside. Both attacks also require existing terrain LOS.
This is not a navigation/path promise. Freeze pauses the same local action
clock; source displacement does not move the locked center. Cancellation and
event ordering reuse the existing bounded two-pulse scheduler.

No map geometry, route, entrance clearance, initial actor budget, identity,
reward or descendant policy changes. The boss local layout anchor remains
(3180, 320), giving world spawn (3222, 424) after the existing bounds offset.
No persistent ground damage, new entities, source-stat consumers, or save schema.

Only Ginkgo receives the new `ginkgo_inner_outer` receipt policy and
`original-ginkgo-inner-outer-v1` balance identity. Other bosses retain their
old circle receipts and formulas. The second event is `annulus_attack`, with
an explicit `inner_radius`; snapshots expose current-stage warning geometry.

Stage backup status: shared import passed; targeted runtime, Main and renderer
checks are in progress. No Windows export or release is part of this batch.
