# v0.93 chaos resistance pure rules

Passed on Godot 4.6.3: **1,188 checks, zero failures**, including **325 full typed-byte comparisons** with the v0.92 frozen oracle. The single focused run exited 0 in 1.9 seconds with no engine errors. See `chaos-rules.log`, `chaos-rules.json`, and `run-record.json` for raw output, result counts, exact command, dependency hashes, and exit status.

The new `chaos_resistance_profile` validates a finite signed raw value and clamps its effective value to 0–75% for either actor. `source_profile` only appends chaos to the raw/effective maps when the input has `chaos_resistance`, after the original validation sequence. The legacy fire-only API, elemental maps/caps, DamageResolver, penetration, burn/DOT, and settlement expressions are unchanged. Independent chaos metadata describes this as an original hit defense and does not claim that source talents grant it.

Coverage: legal boundaries and adjacent floating-point values, invalid types/nonfinite values, signed zero, atomic rejection and existing error precedence, elemental/physical component isolation, shield → optional mana guard → health conservation, and bounded full typed-byte comparisons against the v0.92 baseline. The frozen oracle is the single unedited `defense_rules.gd` from `897dbfc16c1308b2b6916fa9ba52792d9d82c293`; only its global class name is removed in memory. The two unchanged damage dependencies are checked by SHA-256. No historical suite is run.

Reproduce only this focused script after the coordinator finishes the shared import:

```sh
python3 docs/qa/v093-chaos-rules/run.py
```

The runner creates independent disposable `/tmp/godot-m1-v093-chaos-rules-*` XDG roots, rejects a missing shared import, and never invokes import itself. It runs only `res://tests/chaos_resistance_rules_test.gd`; the existing historical test suite is not invoked.

No-key profiles and hit receipts retain the complete baseline typed bytes, including error precedence and signed zero. With an explicit numeric zero, source maps intentionally append the new chaos entry; removing only that newly introduced map entry retains all tested existing profile and unrelated-hit receipt bytes. The standalone raw value retains signed zero and effective values use the specified `clampf` expression.

No Main/UI, equipment/model, encounter, save, Windows/export, or long-running result is claimed by this batch.
