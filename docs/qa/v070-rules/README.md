# v070 Precise Technique pure rules

Baseline: `d25717c4485bf36688df36460f2c85ebb11b7623`.

The focused suite is `tests/precise_technique_rules_test.gd`. Run it only after the parent task's shared Godot import with `python3 docs/qa/v070-rules/run_precise_rules.py`. The runner records a new timestamped raw log, exit code, duration, isolated XDG directories, check results, and pre/post recursive preload SHA-256 manifests for every invocation. Earlier failures are retained. It does not import the editor, export builds, run the full history suite, or run stress workloads.

## Contract

- `PreciseTechniqueRules.from_stats` emits no field for absent or numeric zero flags. Numeric one captures exactly the final `accuracy` and `max_health` as detached floats. Invalid flags and invalid final fields survive capture for explicit rejection; a malformed source dictionary cannot impersonate a valid context.
- The raw context requires exactly two String keys, finite nonnegative accuracy, and finite positive maximum life. A valid selected context activates the critical ban regardless of the damage condition.
- The damage condition is the strict floating-point comparison `accuracy > max_health`, without rounding or approximate equality. At equality or below, the attack MORE entry is absent. Above, it is one 40% MORE entry requiring both `hit` and `attack`, unrestricted by skill or damage type.
- Primary and independent secondary critical chances become zero for attacks, spells and all other hits. Valid potential multipliers remain inspectable. The original critical input and derived-profile validation executes first, followed by Resolute validation, then Precise validation. Non-hit skills keep the original empty critical profiles.
- Resolute and Precise form one critical-ban union. Precise does not supply cannot-evade. The unchanged zero-chance runtime clears inherited rolls without consuming a private RNG sample or recording a critical event.

## Evidence covered

The suite checks exact equality and one representable double on either side at small, ordinary and very large values; numeric type/finite/range/key validation; independent copies including nested malformed fields; all damage types; attack, spell, secondary and utility scopes; physical-to-fire lineage counted once; additive increases and independent MORE products; error precedence including derived multiplier overflow; the Resolute union; complete old/zero critical profile bytes; actual private RNG checkpoint/roll byte equality; and Combat/Compiler attachment for every skill without duplicated MORE.

Three independent old critical/runtime/Resolute files come from the baseline commit. Their only transformations remove `class_name` and rewrite their mutual preload paths. `frozen-source-manifest.json` records original and transformed SHA-256 hashes.

This is focused pure and compiler validation. It does not claim source-node allocation, save migration, real-scene admission, UI, Windows, or long-run performance coverage; those belong to the parent batch.

## Result

After the parent's shared import, the first and only focused invocation passed on Godot 4.6.3: **1,642 checks, zero failures, exit 0, no engine/script errors, 0.645 seconds**. All 73 captured preload/project inputs had identical pre/post hashes. No production or test inputs changed after this run.

- `20261006T060953.193740Z-raw.log.txt`: original stdout/stderr
- `20261006T060953.193740Z-checks.json`: 1,641 section checks plus the final report-open check
- `20261006T060953.193740Z-receipt.json`: exact command, isolated paths, exit, duration and error scan
- `20261006T060953.193740Z-inputs-before.json` and `20261006T060953.193740Z-inputs-after.json`: identical tested-input manifests

Section counts: source contract 64; strict floating-point boundaries 62; malformed contexts 78; modifier scope/arithmetic 112; validation precedence 142; unconditional critical/Resolute union 853; legacy and actual private RNG 146; Combat/Compiler attachment 184. Every section has an explicit completion assertion so a script exception cannot silently count as success.

An additional static comparison confirmed that the original critical code from `_compile_profiles` onward, including profile validation, arithmetic and roll helpers, remains byte-identical to the baseline. The production critical change consists only of the Precise preload, validation after Resolute, and the combined active-policy condition.
