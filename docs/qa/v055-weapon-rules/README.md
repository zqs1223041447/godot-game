# v0.55 forgeblade local physical hit rules

`WeaponLocalRules.consumes_hit(base_id, skill_id, role, tags)` is the shared boundary for raw assembly and frozen-packet admission. The historical bow expression is unchanged. `forgeblade` admits only `cleave/direct` with exactly the four authored `hit`, `attack`, `melee`, `area` tags, in any order. It contributes `(4 + local_flat) * (1 + local_increased) * base_coefficient` as physical points. Ordinary B and external additions retain their original arithmetic. No critical, resource, modifier, skill-coefficient or save-system production path was changed here.

The profile remains the existing seven-field object, with the two existing local source families. Unknown bases, forged base points, malformed types, unknown/local-global source substitutions, missing fields, nonfinite values, provenance mismatches and arithmetic overflow fail closed. The frozen trace retains its existing four fields. Selecting the new event gate requires a String base ID; complete profile validation still precedes all local arithmetic. All historical trace error precedence in the frozen oracle remains identical.

## Independent frozen reference

`capture_v054.gd` runs against the complete already-imported v0.54 project at published commit `5e442d98e82b248efc3a553fdf9bf95733929096`. The runner verifies all 158 original production GDScript files/project configuration against the release source manifest before using that project, and checks their hashes again afterward. No old source is edited, renamed, transformed, extracted into a partial implementation, or redirected to new production dependencies.

The resulting `v54FrozenOracle.bin` contains all 1,244 complete returned Variants. The new suite compares each result with `var_to_bytes`, then compares the entire output file. Integer/float types, dictionary ordering, all nested fields and error strings are retained. Values are not reconstructed from v0.55 output or compared through derived summaries. The 1,399,880-byte reference has SHA-256 `fe8a4d716943c5da8c799c230c8d791f0abf6968319cc5940e1f38bec26da3d8`.

The oracle includes raw/no-weapon and bow profiles across all eleven active/basic consumers, mixed external additions, support compilation, critical/leech/resource inputs, typed zero arithmetic, invalid old profiles, invalid frozen traces, and combined-invalid-input precedence.

## Final verification

`20261005T170555784252Z-results.json`: all three processes exited 0, with no engine/script errors and unchanged before/after hashes for 164 current inputs and 158 baseline inputs. Reused shared imports; no full history suite, scene test, visual gate or long benchmark was run.

- Independent v0.54 capture: 1,244 complete rows, 0.737 seconds
- `tests/forgeblade_hit_rules_test.gd`: 3,351 checks, 0 failures, 0.529 seconds
- Unchanged `tests/local_weapon_compiler_test.gd`: 524 checks, 0 failures, 0.338 seconds

The new suite covers the base/skill/role/tag cross-product; white/T1/T3 actual assembly budgets of 61.6, 65.8–69.72 and 86.8; local versus intrinsic/external arithmetic; ordinary global/attack/melee/physical/area increased; actual compiler and runtime frozen getters; post-cast weapon swaps and nested detachment; actual sword-equipped tornado mother/children without W; bow cleave without W; spell/secondary/basic/tornado exclusions; global critical scope including independent explosions; unchanged attack leech scope; and forged profile/trace rejection without fallback reassembly.

The first run is retained in `20261005T170520020613Z-*`. It found one missing type guard in new frozen-base selection and one invalid cross-type comparison in the test matrix. Both were corrected before the final successful run; no failed evidence was discarded.

Reproduce after shared imports are ready:

```sh
python3 docs/qa/v055-weapon-rules/run_rules.py \
  --baseline /path/to/complete/imported/v054 \
  --manifest /path/to/v054/source-manifest.json
```

The runner creates isolated `/tmp/godot-m1-v055-weapon-*` XDG storage and retains logs, complete binary reference, commands, durations, exit codes and source hashes. This package verifies pure rules and real compiler/carrier consumers; actual equipment acquisition, saves and live melee target settlement are covered by the separately owned integration work.
