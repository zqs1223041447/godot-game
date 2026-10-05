# v0.54 faster burning: pure rules and runtime consumption

`tests/faster_burn_rules_test.gd` checks the faster factor and consumes its results through the unchanged `BurnRuntime`. It does not run a scene, modify saves, or test main's death/transfer scheduler.

The fixed oracle is published v0.53 commit `e3a5f7559ecbcb2cb56a9c192d75899fdcf43b3a`. `v053_burn_rules.gd` removes only its global class declaration. `oracle-manifest.json` records the original and fixture hashes and the transformation. The old behavior is never synthesized from the new result.

Coverage includes:

- Complete result bytes and old error precedence for absent, integer-zero, floating-zero and negative-zero faster factors, including invalid old arguments and combined Fire DoT inputs
- Exact zero-path helper arithmetic, policy bytes and source projection bytes
- Additive faster contributions, independent Fire DoT multiplication, and the quarter-faster contract of 1.25 times DPS over 2.4 seconds
- Theoretical lifetime preservation with the agreed bound `max(1e-9, 1e-12 * abs(old_total))`
- Invalid booleans, strings, containers, negative values, NaN and infinity, and explicit snapshot-zero rejection
- Raw rate underflow, Fire DoT overflow, faster-DPS overflow, duration underflow, lifetime overflow/underflow and representable extreme factors
- Existing runtime expiry, split integration, no immediate damage, final-DPS replacement and equal refresh
- Input isolation, fixed policy isolation, default enemy profile and RNG preservation

Production authorities are `BurnRules.raw_fire_dps(fire, rate, multiplier = 0.0, faster = 0.0)` and `BurnRules.burn_duration(base_duration, faster = 0.0)`. Validation remains at the `from_fire_hit` and snapshot/compiler boundaries; the typed arithmetic helpers assume validated inputs.

## Verified result

Final run `20261005T161718733866Z-results.json`: **22,860 checks, 0 failures**, exit 0, 0.553 seconds. All seven captured inputs had identical before/after SHA-256 values, and no engine/script error was logged. This package reused the completed shared import and did not perform another import.

The fixed-oracle section accounts for 20,386 checks, the faster arithmetic section for 2,169, source/snapshot validation for 175, invalid/extreme arithmetic for 65, unchanged runtime consumers for 58, and input isolation for 6; the final RNG check is additional.

The first run (`20261005T161521895448Z-*`) is retained with two failed assertions about an extreme fixture. On the target Godot build, `1e-308` fire is rejected as nonpositive before the rate multiplication. The focused diagnostic in `extreme-probe-*` records that rejection and the accepted normal-range alternative. Its ordinary number-to-string formatting prints tiny numbers as `0.0`; the returned `ok` and `reason` fields, rather than those formatted values, establish acceptance/rejection. Production arithmetic was unchanged. The accepted extreme uses `1e-300` fire and `1e300` faster; the original extreme is now explicitly asserted to reject. The intermediate successful run (`20261005T161634353346Z-*`) is retained as well.

Reproduce after the shared import is ready with `python3 docs/qa/v054-rules/run_rules.py`. The runner creates fresh isolated XDG directories and retains complete logs, exit code and input hashes. It runs only this focused suite; main/compiler coverage belongs to the integration package.
