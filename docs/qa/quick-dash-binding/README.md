# Space quick-dash binding regression

2026-10-11 UTC. Baseline local 7667799, tree equivalent to main 2c563b2.

Space previously searched only the legacy 1–5 compatibility hotbar. An active equipped dash bound to E, 6 or F1, or without a direct binding, was omitted. Main now obtains the canonical active dash group through get_skill_cast and uses cast_group, retaining shared payment and group/main-gem cooldown. Legacy fixtures retain their previous route.

Before: 66 checks, 15 failures. After: same 66 checks, 0 failures; raw logs retained. Parent separately ran the isolated runner with 66/0. Coverage includes both orders of Space/direct-key shared cooldown, one mana payment, numeric and nonnumeric keys, unbound active dash, inactive/unequipped rejection, dead/menu/pause/safe-area/mana guards, echo/release and legacy compatibility.

With multiple active equipped dash gems, Space uses the first canonical active row rather than numeric hotbar order. This matches get_skill_cast selection.

Unmodified canonical_group_cast_test starts in town and fails before indexing an empty projectile list; its bounded run exited124. It was not changed or claimed passing. A temporary normal-mode adaptation reported27/0 in tool output only; no raw log persisted, so this is supplemental evidence, not the primary gate.

Headless targeted testing only, no full suite, visual/FPS validation, Windows export or deployment.
