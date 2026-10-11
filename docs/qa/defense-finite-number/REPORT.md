# Defense finite-number candidate: retained, narrowly scoped

HEAD: 0bff9ed580b53f432db392b31d906c31aabfdddb. Godot 4.6.3 stable headless, dot workspace.

## Decision and production change

Retained the single candidate. Only repository file changed: `scripts/mechanics/defense_rules.gd`, lines 418–419. Replaced temporary `[TYPE_INT, TYPE_FLOAT]` membership with a local integer `typeof(value)` and two scalar comparisons, retaining the short-circuited `is_finite(float(value))` check. No arithmetic, validation order, failure strings, accepted types, dictionaries, copying, or other function changed. Boolean remains rejected. No full suite, particle rerun, engine/global configuration change, network action, commit, push or export.

The repeatable evidence is the microbenchmark, not a claimed frame-rate gain. The single tick comparison supports the direction but is noisy and cannot establish robust whole-game improvement.

## Bounded microbenchmark

Eight alternating old/new execution-order rounds in one process. Each side/round makes 100,000 helper calls over 11 mixed numeric/invalid values, then 10,000 representative fire `settle_resolved` calls. Timings include dispatch, looping and result checks equally; no per-call instrumentation. Old and candidate are same-source temporary copies differing only in the helper, with class_name removed identically. No warmup round excluded.

- Helper mean per 100,000: 27.403 → 21.427 ms, −21.81%; medians 27.479 → 21.402 ms; candidate wins 8/8
- Settlement mean per 10,000: 86.910 → 81.235 ms, −6.53%; medians 86.429 → 81.044 ms; candidate wins 8/8

These synthetic call costs do not predict gameplay savings.

## Strict old/new output oracle

5,033 comparisons using exact `var_to_bytes` equality, not approximate floats, passed on both candidate temporary source and final production source against the original helper. 59 input values cover integers including signed limits, positive/negative/zero floats including signed zero, subnormal-scale and very large finite values, NaN, ±infinity, both booleans, null, numeric strings, StringName, vectors, transforms, geometric types, color, NodePath, RID, RefCounted, Callable, Signal, dictionary, array and all packed array kinds represented in the script.

Methods include `_finite_number`, `_amount`, mana guard, recharge, fire/elemental/chaos/source profiles (player/monster/invalid actor), component validation, resolved settlement, mana settlement, hit-taken scaling, incoming hit/source hit, and burn. Mutations cover resource fields, resolved total/components/details and each detail field. Simultaneous-invalid inputs check error precedence as well as exact failure reasons. The helper additionally has expected acceptance assertions. This is broad finite-number-focused coverage, not exhaustive combinatorial defense testing.

## One clean alternating tick comparison

Reused the prior controlled fixture and observer with all profiler code removed. One pair of clean main scripts, one 24-tick sequence, old/new order alternates each tick. Same seeds (500050/500051), 100 real AI catalog actors and 180 artificial near-contact tornado carriers injected before each 1/60 tick. Damage 0.075; no support, burn, deaths or rewards; player protected. Carrier construction, compilation, setup, observer, serialization and process waits excluded from timing.

- Tick mean: 37.532 → 36.735 ms (−2.12%)
- Median: 37.101 → 36.185 ms
- Maximum: 46.042 → 47.622 ms (candidate worse)
- Candidate faster in 16/24 paired ticks
- Baseline-first half mean change −1.10%; candidate-first half −3.14%
- Exact observed-state matches: 24/24

Important scope: the two clean main copies bind their own Defense constant to old/new copies. Other dependencies remain shared original production scripts during this comparison. Thus it isolates the main defense path, not every transitive use after a global production replacement. Public-function equivalence and targeted production checks cover the shared helper separately. The very small observed whole-tick difference is not independently replicated and should not be promised as a user-visible gain.

Observer covers non-object/non-Callable/non-Signal main script properties, RNG state, canonical model snapshot, isolated save bytes, projectile spatial-index fields and projectile/monster/feedback/cue/critical/burn/telegraph/cooldown/trap/chill/shock/freeze/leech/flask/geometry runtime fields. Inherited exclusions: `_flask_owner_identity`, `_previous_auto_accept_quit`, particle_-prefixed fields (none added). Does not compare object graphs, HUD, rendering or noncanonical model caches. No death/reward/save mutation exercised. Headless script CPU only; no GPU/rendering/Windows/FPS claim or formal-map/300-actor evidence.

## Targeted production checks and existing limitation

- Production exact oracle: 5,033 comparisons passed
- Shock settlement boundaries: 47 checks, zero failures
- Shared defense rules: 384 checks, one failure at existing hard-coded `Registry.get_ids().size() == 23` expectation. Same 384-check/one-failure result reproduced with untouched baseline Defense. Unrelated registry assertion left unchanged; this suite is not reported as a pass
- `git diff --check`: passed

## Evidence and setup diagnostics

The complete experiment originally lived in a temporary diagnostic directory. This repository retains REPORT.md, micro.json, tick.json, summary.json, oracle-production.log, targeted.log, defense-baseline-test.log and shock-direct.log. Other scripts/logs listed below describe the original temporary evidence and are not included in this repository snapshot:
- `micro.json`, `micro.log`, `micro.gd`: per-round measurements and exact oracle
- `tick.json`, `tick.log`, `probe.gd`: each paired timing and state result
- `summary.json`: aggregates and source SHA256 hashes
- `old.gd`, `new.gd`, `main-old.gd`, `main-new.gd`, `original-defense_rules.gd`, `build.py`: reproducible source snapshots
- `oracle-production.gd`, `oracle-production.log`: final production exactness verification, no benchmark rerun
- `targeted.log`, `defense-baseline-test.gd`, `defense-baseline-test.log`: candidate/baseline existing registry failure
- `shock-direct.log`: completed 47-check pass; `shock-targeted.log` is an initial wrapper attempt that exited at its required user-directory guard before tests. Retried with the test's required isolated `/tmp/godot-m1-v052-` user-data prefix
- `initial-userdir-failure.log`: initial engine startup failed because default user-data path was unwritable; no benchmark executed. Subsequent runs used per-command temporary XDG directories
- `callv-parse-failure.log`: initial oracle dispatch syntax corrected to instance `callv`; no benchmark executed

Worker handoff status was one modified source file with HEAD unchanged. Parent subsequently committed the minimal production change and the selected evidence listed above on a separate branch based on the cleaned main-equivalent tree; the unrelated Space-dash change is not part of this branch.
