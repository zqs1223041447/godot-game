# Private burn-state copy experiment, 2026-10-15

## Decision and bounded scope

Candidate passes the predeclared semantic and timing gates; retain only the private `_plan_advance` outer-dictionary shallow copy, independently reviewed (see review.md). This is a small headless script-CPU experiment, not Windows/native rendering acceptance or a general FPS guarantee. No gameplay/schema/content changes.

Published baseline: `461824776e500ea868f72aea58a4f54db40b4423`, tree `db433a89cd94c36f0c803272346fa82339a9f795`. Local baseline tree matches it. `baseline-provenance.json` records equivalence; main/runtime/rules hashes were independently checked against the published commit. `baseline-source-manifest.json` froze every production GDScript before the edit. The frozen runtime and its only dependency, burn_rules, were copied before editing; only class_name removal and the rules preload relocation avoid global-name collisions.

## Hypothesis and ownership audit

State has seven fields, with provenance the only nested mutable value. Validation limits provenance to six known scalar fields. Planning only changes `remaining` and `last_time` in a fresh outer dictionary. The redundant private provenance deep copy can therefore be removed while retaining every public/status/input/segment deep copy.

All production planner callers are inside BurnRuntime:
- apply stages integration before committing; stronger/equal replacements deep-copy the caller's new provenance, weaker replacements retain private planned state; returned segments own their provenance
- advance_target privately commits the plan and returns detached segments
- advance_all reads detached statuses, stages all plans, then commits only after all succeed; later-target reverse-clock or underflow failure cannot mutate earlier source states
- Expiry discards next state; remove/reset discard references without editing provenance
- status_for and statuses retain deep copies; main death-source snapshots and EmberRules.transfer retain their own detached copies

No production caller outside BurnRuntime invokes `_plan_advance` or accesses `_states`. A future private provenance mutation or escaping private planner status would invalidate the assumption; the production comment explicitly warns about this.

## Gate declared before timings

See `gate.json`. Two counterbalanced pairs per mode, exactly 20 ticks each; baseline→candidate then candidate→baseline, 90-second process timeout. All 12 runs were sequential. Require both ember pairs to improve mean and peak, and at least 3% pooled mean and mean-of-paired-peaks improvement. Reject a control if mean or peak regresses >3% in both pairs, or >5% pooled. Require exact full-frame/final/save bytes plus semantic and ownership tests. No additional variants or favorable reruns.

## Results

Times are microseconds; peaks are maximum tick time within each 20-tick run.

| Mode | Pair | Baseline mean | Candidate mean | Baseline peak | Candidate peak |
|---|---:|---:|---:|---:|---:|
| Ember deaths | 1 | 139301.45 | 122709.20 | 712989 | 562692 |
| Ember deaths | 2 | 130206.65 | 126579.85 | 584094 | 552879 |
| No burn | 1 | 48751.25 | 47128.95 | 67849 | 53979 |
| No burn | 2 | 45016.70 | 46998.40 | 58610 | 60510 |
| Ordinary ignite | 1 | 93854.25 | 79243.75 | 114506 | 103984 |
| Ordinary ignite | 2 | 85786.00 | 98008.95 | 109012 | 128854 |

Pooled ember mean improves 7.50%, mean of paired peaks 13.99%. No-burn pooled mean changes +0.38%, peaks -9.47%. Ignite pooled mean -1.33%, peaks +4.17%. Controls show material order/run noise: ignite pair 2 regresses 14.25% mean and 18.20% peak, while pair 1 improves. The predefined gate passes, but two pairs do not establish a broad reliable speedup; do not hide these regressions or infer renderer/FPS benefit. No instrumented timing is used for the decision.

All 18 direct paired candidate-vs-baseline comparisons match exactly (six run pairs × full serialized frame observations, final observation and saved bytes). The additional comparison against each mode’s first baseline has 36 artifact receipts: nine baseline self-checks and 27 non-self comparisons (18 candidate checks plus nine second-baseline checks). No fields removed, rounded, or normalized. Full observer inherited from the archived prediction-cache diagnostic, with only environment naming, baseline metadata and frozen-vs-production runtime selection changed. Monster AI/attack scheduling remain enabled, player protected, 100 catalog enemies, controlled 180-projectile volleys. Initial random discarded-actor effects are cleared consistently before all observations.

Each run records complete production/frozen/harness hashes before and after execution and asserts no change. JSON sample data, logs and SHA256/length receipts are retained. Large raw binary/save files remain in `/tmp/burn-state-copy-20261015-observations`; they are reproducible, not committed. `summary.json` records exact comparisons and file digests.

## Semantic verification

- New production-vs-frozen runtime test: 892 checks, zero failures, exact typed result/state/status bytes
- Existing burn rules/runtime: 776 checks
- Existing allocation equivalence: 797 checks
- Same-time cleanup: 19 checks
- Settlement equivalence: 58,593 checks (its historical microbenchmark is unrelated to this candidate and is not evidence of this change's benefit)
- Burn presentation: 21 checks
- Ember event clock: 45 checks
- Ember precision/ULP boundary: 16 checks
- Ember projectile/death rewards: 97 checks
- Ember transfer rules: 1,655 checks, nine cases
- Ember gameplay: 91 checks

All suites passed. New test covers input/status/segment ownership; retained snapshots across advance/replacement; stronger/equal/weaker replacement; zero advance and signed zero; expiry; reverse/nonfinite failures; target/batch rollback; underflow and capacity. Production integration tests cover event clocks, ULP, death and transfer lineage. Historical settlement output emitted by its existing test was copied here and the old tracked result restored without overwriting the historical record.

## Reproduce without overwriting evidence

Use this candidate revision with Godot 4.6.3; verify the published baseline source manifest before interpreting a different revision. Fresh isolated user data is created per benchmark process.

```sh
export STATE20261015_EVIDENCE_DIR="$(mktemp -d /tmp/burn-state-reproduce-XXXXXX)"
export STATE20261015_ARCHIVE_DIR="$(mktemp -d /tmp/burn-state-raw-XXXXXX)"
python3 tools/diagnostics/run_burn_state_copy_20261015.py
python3 tools/diagnostics/summarize_burn_state_copy_20261015.py
case_root=$(mktemp -d /tmp/godot-m1-v050-state-recheck.XXXXXX)
XDG_DATA_HOME="$case_root/data" XDG_CONFIG_HOME="$case_root/config" XDG_CACHE_HOME="$case_root/cache" timeout 90 godot --headless --path . --script res://tests/burn_state_copy_20261015_test.gd
```

Benchmark runner verifies all 238 baseline dependency hashes against the reachable published commit and requires current production bytes to differ only by the declared candidate; it also verifies the frozen-source transforms. It refuses to overwrite existing evidence. Exact frozen baseline comparison is available from this revision; no unpublished SHA, alternate candidate, historical result overwrite, timing normalization or private game-source omission is required.
