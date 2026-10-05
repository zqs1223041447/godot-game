# Combat feedback runtime contract

`CombatFeedbackRuntime` is a pure `RefCounted` runtime at
`res://scripts/combat/combat_feedback_runtime.gd`. It does not read statistics,
saves, wall time, scene state, or RNG. Its clock advances only through `advance`.

- `record(event: Variant)`, `advance(delta: Variant)`, and
  `flush_target(kind: Variant, id: Variant)` return dictionaries containing `ok`
  and `reason`. Invalid input and non-finite arithmetic fail atomically.
- `reset()` clears the clock, pending buckets, and visible entries, and starts a
  new epoch. Output IDs remain unique and increase across resets.
- `entries()` returns detached `Array[Dictionary]` snapshots with `id`,
  `target_kind`, `target_id`, `kind`, `amount`, `shield_spent`, `health_lost`,
  `hit_count`, `position`, `age`, and `lifetime`.

An event requires strict String `target_kind` (`player` or `monster`), integer
`target_id` (player `0`, monster positive), strict String `kind` (`hit`,
`critical`, or `burn`), finite nonnegative numeric `shield_spent` and
`health_lost`, and finite `Vector2` `position`. Booleans are not numbers or IDs;
float IDs and StringName categories are invalid. Extra metadata is ignored.
The finite sum of actual shield spent and health lost is the displayed amount;
nominal damage, overkill, and critical multipliers are never inferred. A valid
zero-total event succeeds without changing any state.

Positive events merge only within `(epoch, target_kind, target_id, kind)` and a
fixed 0.20-second window beginning with its first positive event. They sum
actual spends, retain the latest positive position, and add one hit per hit or
critical event; burn contributes no hits. Later events never extend a window.

`advance` accepts finite nonnegative numeric deltas, excluding bool. Due buckets
publish in deterministic deadline/creation order and are born at their deadline,
even after a long delta. Visible entries live 0.75 seconds and expire at the
absolute deadline `born + 0.75`, including the `0.4 + 0.75` rounding case. A new
window for the same key replaces the prior visible entry with a fresh output ID.
Zero delta models pause and leaves the simulation unchanged.

`flush_target` immediately publishes only that target's pending categories in
creation order, with birth at current simulated time. Death handling must call
it after recording final actual positive spends. Unknown valid targets and
repeated flushes are harmless.

There are at most 303 pending buckets. A new positive key at capacity publishes
the oldest pending bucket at current time before admitting the new one. Zero
events, merges, and rejected inputs cannot trigger this overflow publication.
There are at most 48 visible entries, evicting the oldest output sequence first.

## Focused verification

Run `godot --headless --path <project> --script
res://tests/test_combat_feedback_runtime.gd` after restoring the runtime. The
isolated SceneTree script preloads only this runtime. It prints
`COMBAT_FEEDBACK_RUNTIME_TEST_COMPLETE checks=<n> failures=<n>` and exits zero
only when all checks pass. Capture both the completion marker and exit status;
an engine startup or parse failure is not a test pass.

Coverage includes boundaries and absolute expiry, fixed-window aggregation,
actual spends, categories and player/monster separation, tiny fractions, source
and result copy isolation, death flush ordering, reset and pause, pending and
visible limits, same-key replacement, deterministic split/large delta behavior,
invalid types and non-finite values, and atomic rejection of arithmetic overflow.

This recovery draft has not been executed. Historical results from the lost
workspace do not verify this restored test or any newly restored runtime.
