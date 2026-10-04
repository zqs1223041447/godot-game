# v0.45 pure burn contract

The policies in `BurnRules` are this game's original prototype values. They are
not a reproduction of another game's burn formula.

## Resolved basis

- `PLAYER_POLICY`: duration 3 seconds, rate fraction 0.30, upstream hit multiplier
  0.75, and upstream mana multiplier 1.20.
- `ENEMY_POLICY`: duration 3 seconds, rate fraction 1/3, upstream fire multiplier
  0.50.
- `from_fire_hit(fire_before_defense, policy)` multiplies only the already
  resolved, pre-defense fire component by `rate_fraction`. The hit, projectile,
  critical, upfront-fire, and mana multipliers do not run inside this helper.
- The helper returns `{ok, reason, raw_dps, duration}`. Failure returns zero
  numeric fields. Policy dictionaries require `duration` and `rate_fraction` and
  accept only the five declared policy keys, each a finite positive number.

## Runtime API and integration obligations

- `apply(kind, id, source_id, raw_dps, duration, at, provenance = {})` returns
  `{ok, reason, applied, segments}`. Successful reasons are `new`, `stronger`,
  `equal`, and `weaker`. Only exact raw-DPS equality refreshes. A stronger or
  equal application resets duration and takes the new source/provenance.
- Before comparing a replacement, the old status settles up to `at`. Returned
  segments preserve the old source/provenance. Weaker applications settle time
  but retain the previous rate, remaining lifetime, and source. An expired
  status accepts any valid new rate.
- `advance_target(kind, id, to_time)` and `advance_all(to_time)` return
  `{ok, reason, segments}`. A segment has `target_kind`, `target_id`, `source_id`,
  `from_time`, `to_time`, `raw_dps`, `raw_amount`, and detached `provenance`.
  Segments cover only positive-width active intervals. Application at a fresh
  target and zero-time advancement produce no instantaneous damage.
- `remove(kind, id)` returns `{ok, reason, removed}`. `reset()` empties the run;
  `is_empty()` reports active statuses. `statuses()` returns detached entries
  containing `target_kind`, `target_id`, `source_id`, `raw_dps`, `remaining`,
  `last_time`, and `provenance`.
- Statuses and `advance_all` segments sort by lexical kind (`monster`, then
  `player`) and numeric ID. This is a stable identity order, not a global
  chronological event order.
- Each active target has its own `last_time`. The caller advances the affected
  target before its hit at the projectile event time or telegraph deadline,
  then settles the applicable targets at frame end. The caller owns live-target
  causality and defenses. Pausing simply stops advancement.
- Clocks exist only for active statuses and are discarded on expiry, removal,
  or reset. A valid absent-target advancement is a no-op. This bounds storage
  even across arbitrarily many expired target IDs. The caller must not replay
  historical applications onto an expired or removed actor.
- Source death has no runtime effect. Target death removes that target's incoming
  status; it does not remove burns whose source happens to have that actor ID.

## Validation and bounds

- Target kinds are exact Strings: player ID is integer zero; monster ID is a
  positive integer. Source IDs are integer zero (player) or positive (enemy).
  Booleans, float IDs, StringNames, strings containing numbers, and containers
  are not coerced.
- At most 101 targets are active, including the player. Replacing an existing
  status at capacity is valid; adding another target fails atomically.
- DPS and duration are positive finite int/float values; duration is at most
  60 seconds. Time is finite, nonnegative, absolute int/float time. No active
  target may move backward. Arithmetic must represent a positive lifetime
  budget, expiry, and segment; underflow, overflow, or loss of a positive expiry
  at an enormous timestamp are rejected.
- Provenance is an optional dictionary containing only exact String keys
  `skill_id`, `cast_id`, `projectile_id`, `phase`. Text values are exact Strings
  up to 128 characters, including empty strings; IDs are nonnegative integers.
  Nested data, unknown keys, and coercible-but-wrong types are rejected.
- Invalid application/advancement emits no segments and changes no state.
  `advance_all` plans every target before committing any target.
- No damage resolver, defense, hit/projectile/critical/leech multiplier, RNG,
  signal, actor reference, or persistence call is part of this runtime.

## Verification

`tests/burn_rules_runtime_test.gd` covers policy values and once-only basis,
independent player/monster clocks, old-source settlement, exact stronger/equal/
weaker behavior, source death, target removal, expiry, pause/no advancement,
zero time, very large absolute time, split-time equivalence, all malformed
argument families, NaN/infinity, arithmetic overflow/underflow, atomic failure,
stable identity order, 101-target bounds, detached inputs/outputs, and global
RNG preservation.

After the shared-tree unified import, the focused isolated command
`bash tools/validate.sh res://tests/burn_rules_runtime_test.gd` passed on Godot
4.6.3: **776 checks, 0 failures**. See `burn-pure-run-02.log` and the five executed
input hashes in `burn-pure-tested-files.json`.

`burn-pure-run-01.log` retains the first failed attempt. Its failure was in the
test harness: comparing heterogeneous invalid key values directly to a
StringName raised a script exception. The harness now checks `typeof(key)`;
the runtime did not need a behavioral change to resolve that failure. Pure
coverage does not claim gameplay, rendering, save migration, or export coverage.
