# v0.39 pure critical profile rules

`CriticalStrikeRules` is an independent `RefCounted` module. It reads stat
dictionaries, validates optional snapshot data, compiles resolved profiles, and
compares a supplied sample with a profile's chance. It does not create random
samples, inspect game state, mutate damage packets, or resolve damage.

## Input and compatibility

`from_stats(stats)` returns a detached modifier dictionary. Either explicit
`crit_base_chance` or `crit_base_multiplier` opts into the profile, including an
explicit zero chance. A nonzero known modifier also opts in. Missing base values
default to chance `0.0` and multiplier `1.5`; the canonical player integration
must explicitly provide its intended `0.05` / `1.5` baseline.

Absent bases with absent or numeric-zero known modifiers return `{}`. The caller
must then omit `snapshot.critical_modifiers`; a present empty dictionary is
invalid. Unknown unrelated player stats are ignored. Invalid known stat values
are preserved, including nested arrays/dictionaries, so validation can reject
them. All returned nested data is copied.

`error(snapshot)` accepts an absent `critical_modifiers` field. When present, the
field must be a nonempty dictionary containing `base_chance`, `base_multiplier`,
and only the nine fields declared in `STAT_KEYS`. Keys must be actual `String`
values, not `StringName` or values coerced into text. Numbers must be finite
`int` / `float` values, never booleans or numeric strings:

- Base chance: `0..1`, inclusive
- Base multiplier: `1..1000`, inclusive
- Every modifier: `0..1000000`, inclusive

Use string bracket assignment when introducing fields into a dictionary. Godot
dot assignment of a new field creates a `StringName` key, which this exact-key
contract intentionally rejects.

## Compilation

`compile(snapshot, primary_tags, has_secondary)` always returns the exact shape
`{ok, error, critical}`. Errors return `ok = false`, a nonempty explanation, and
an empty `critical` dictionary. Missing optional data and valid no-hit utility
actions return `ok = true` with an empty `critical` dictionary. Source validation
still runs for utility actions, preventing malformed data from being hidden.

A hit produces `critical.primary = {chance, multiplier}`. With
`has_secondary = true`, it also produces a separate `critical.secondary` profile.

Primary chance is `clamp(base_chance * (1 + sum_of_applicable_increases), 0, 1)`.
Primary multiplier is `base_multiplier + sum_of_applicable_additions`.

| Scope | Required primary tags | Chance field | Multiplier field |
| --- | --- | --- | --- |
| Global | `hit` | `crit_chance_increased` | `crit_multiplier_add` |
| Attack | `hit`, `attack` | `attack_crit_chance_increased` | None |
| Spell | `hit`, `spell` | `spell_crit_chance_increased` | `spell_crit_multiplier_add` |
| Melee | `hit`, `melee` | `melee_crit_chance_increased` | `melee_crit_multiplier_add` |
| Projectile attack | `hit`, `projectile`, `attack` | `projectile_attack_crit_chance_increased` | `projectile_attack_crit_multiplier_add` |

All matching scopes add once, including mixed-tag inputs. Repeated tags and input
dictionary order do not change arithmetic. A projectile spell does not receive
projectile-attack modifiers. Secondary hits use the same bases and only the two
global fields, regardless of the primary tags.

Example: base chance `0.05`, global increase `0.2`, and spell increase `0.3`
produce `0.075`. Base multiplier `1.5`, global addition `0.1`, and spell addition
`0.2` produce `1.8`. Thus `+0.10` multiplier means ten percentage points. The
secondary in this example has chance `0.06` and multiplier `1.6`.

Arithmetic is checked for nonfinite results before chance clamping. Resolved
multipliers above `1000000` fail atomically, even when individual input fields
are within their own bounds.

## Profile validation and supplied rolls

`profile_error(value)` requires exactly `{chance, multiplier}` with actual String
keys and finite int/float values. Chance is `0..1`; multiplier is `1..1000000`.

`roll(profile, sample)` returns `{ok, error, critical, multiplier, chance}`.
The supplied float sample must be finite and `0 <= sample < 1`. An event is
critical exactly when `sample < chance`; an ordinary result has multiplier
`1.0`. Invalid profiles/samples return `ok = false`, a nonempty error,
`critical = false`, `multiplier = 1.0`, and `chance = 0.0`.

The runtime owns its dedicated critical random stream. It should avoid drawing
when chance is exactly zero or one; it can pass `0.0` to this pure comparison for
either deterministic endpoint. Lucky rolls, local weapon critical modifiers,
triggers, damage-over-time behavior, and packet/runtime integration are outside
this module.

## Focused verification

- Engine: Godot `4.6.3.stable.official.7d41c59c4`
- Command: `bash tools/validate.sh res://tests/critical_profile_rules_test.gd`
- Isolation: the existing runner creates fresh XDG data/config/cache paths under
  `/tmp`; no normal player save path is used
- Result: **757 checks, zero failures**, with strict log error scanning
- Coverage: legacy omission, explicit zero bases, malformed-value preservation,
  exact schemas, all nine modifiers, finite/bounded numbers, additive semantics,
  scopes and mixed tags, secondary isolation, strict roll boundaries, detached
  inputs/results, stable ordering, and unchanged global RNG sequence
- The initial run reported two failures after a fixture introduced new dictionary
  fields using dot assignment. Switching those two fixture writes to String
  bracket keys resolved the issue; production validation was not relaxed. The
  initial evidence is retained in `critical-rules-first-fixture.log.txt`
- Final passing evidence: `critical-rules-test.log.txt`
- Direct module parser check also passed with isolated XDG paths:
  `godot --headless --path . --check-only --script res://scripts/combat/critical_strike_rules.gd`
  (`critical-rules-parser.log.txt`)

This is focused module evidence. It does not claim gameplay/UI integration,
performance validation, or a full-suite run. No 600-second simulation was run.
