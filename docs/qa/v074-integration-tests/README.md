# v074 source stride integration

Final result: **766 unique checks, zero failures**, Godot 4.6.3, 3.041 seconds. The isolated runner compared hashes of **550 production files before and after**; none changed. No editor/import or full historical suite is part of this gate.

Run after the project import gate:

```sh
python3 tools/run_source_stride_checks.py
```

The runner uses disposable `/tmp/godot-m1-v074-*` XDG data/config/cache roots, a 150-second timeout, process-exit and Godot error-log checks, a completed JSON report, and production dependency hashes. It fails if the test exits with errors, fails to finish, changes a production dependency, or changes a frozen baseline fixture.

## Covered contracts

- All 23 historical registry identities: exact `var_to_bytes` results for player and monster at coefficients 0, 0.5, 1, and 2; complete definitions; all aliases; full-bundle tuning and revision behavior
- Three seeds × five waves × six sampler calls: frozen legacy roll and RNG bytes; current selection differs only by the in-place `gale_stride` → `source_gale_stride` replacement; sampled legacy enemy bytes and explicit three-species/three-rarity boundary fixtures
- Current source node 63417/index 1: the current parser emits exactly 4% increased movement, both actors receive identical source provenance, and a whole-node grant containing armour is rejected
- All three species at waves 1, 6, 10, 15 and 100: `(species + capped wave + historical flat) × (1 + source increase)`; unchanged HP, damage, shielding, attack timers, rewards and other non-source fields; actual map admission applies ×1.10 afterward
- All three maps and three seeds: default and explicit historical camp checkpoints match the frozen original byte for byte; current checkpoints change only the stride ID; invalid policy leaves the existing roster unchanged
- Narrow process-local source fixture: a valid 4% → 8% edit refreshes new spawns without mutating existing monsters; original source is restored; invalid source cannot reuse a cached value or partially retain mixed grants; actual map admission restores its ID/root/trace/queue checkpoint
- Actual Main: ordinary spawn selects the new ID with the same sampler RNG; `_prepare_camp_run` uses current policy; successful and rejected preflights leave scene/runtime/RNG/save snapshots unchanged
- Actual Main movement with old and new grants: ordinary pursuit, existing ×0.36 slow, full freeze, thaw prefix, external impulse, and attack clock formula; no save/RNG mutation
- Save schema remains 47 and source execution version remains 45

## Evidence and baseline

- `integration-report.json`: final counts, bounded inputs, per-section results and movement examples
- `integration.log.txt`: final Godot output
- `dependency-evidence.json`: command, exit code, timing, test hash and complete before/after production hashes
- `frozen/manifest.json`: original and transformed hashes from authoritative commit `a1dd1acf`
- `frozen/*.original.txt`: exact `git show a1dd1acf:<path>` bytes for Registry, Catalog and CampState
- `frozen/*.gd`: executable counterparts with only `class_name` removal and Catalog→frozen Registry / CampState→frozen Catalog preload rewiring

The first run exposed a test-fixture type mismatch: `old_ids + [new_id]` produced an untyped Array, while the production API deliberately preserves `Array[String]`. The captured initial engine output is retained in `initial-fixture-failure.log.txt`. Only the expected fixture was changed to a typed array. The same bounded suite was then rerun because this runner has no section selector. **766 is the unique final check count, not the sum of attempts.** No production fix was needed.

This gate establishes compatibility and source-binding behavior. It is not a full v073 regression run or a balance claim.
