# v0.82 cold ailment duration pure rules

Result: **276 checks passed, 0 failures**, first focused run, **0.932 seconds**.
Exit 0; no script or engine errors; all five captured inputs stayed unchanged.

- `20261006T141745560080Z-run.log.txt` preserves the original engine output
- `20261006T141745560080Z-receipt.json` records the command, exit, duration,
  isolated user directory, and before/after SHA-256 inputs
- `run-focused.py` runs only `tests/cold_ailment_duration_rules_test.gd`, after
  the shared Godot import, with a 30-second watchdog

Scope: `cold_ailment_duration_rules.gd`, derived `frost_lock_rules.gd` policy,
and the unchanged `FreezeRuntime` boundary contract. No historical suite,
Main scene, compiler, save flow, or live AI scheduler is loaded by this proof.

The current source budget is at most 20%. Missing or zero increases preserve
the absent snapshot and original four-field frost policy. Invalid values are
kept detached for compilation to reject, never clamped or silently dropped.
Positive durations are computed once from their original bases. Derived frost
policies are accepted only when each rarity exactly matches that formula;
immunity remains 1.50s, hit multiplier 0.75, and mana multiplier 1.20.

Verified checks cover normal/magic 0.72s, rare 0.42s, boss 0.24s; the legacy
rejection order; absent/zero shape; malformed and over-budget snapshots;
detached nested snapshots; rejected partial results; unchanged immunity;
same-target hits from two groups; exact boundaries; partial-frame and
large-delta thaw; and the unchanged 100-ID storage limit.

Reproduction after import: `python3 docs/qa/v082-rules/run-focused.py`.
The runner preserves each original log and records exit status, elapsed time,
input SHA-256 hashes, script/engine errors, and the isolated user directory.
