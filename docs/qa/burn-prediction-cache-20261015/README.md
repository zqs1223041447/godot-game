# 2026-10-15 burn prediction cache experiment: REJECTED

Tested local baseline: `4e581e223bf012c04c94ec1f1a558021feeea03a`. The equivalent published, reachable source commit is `125112823ddf88784e2399c565e974ad04afdc49`; reconstruction uses that commit and requires the exact frozen main.gd SHA-256 below. The local commit ID is retained only as historical provenance and is not required in a fresh clone. Production `scripts/main.gd` was frozen before editing and has been restored byte-for-byte (SHA-256 `98c1f36ce2d09bdf25d285a3e8a0ad6eec76221a8af94a02d1f27c4c85994252`). No production optimization is retained.

Provenance limitation: the baseline source and SHA-256 were frozen before editing, but the original per-run JSON records did not capture main/harness source hashes. `source-manifest.json` records retrospective hashes of the preserved baseline/candidate/instrumented files. The runner was subsequently improved to record source hashes for future runs; those fields must not be inferred to exist in the historical run records. Harness-only selection support changed during this experiment; clean runs kept the production selection and identical observer/timed call.

## Candidate and decision

The archived patch adds a call-local dictionary only within `_advance_proliferating_burns`, bounded by `BurnRuntime.MAX_TARGETS` (101). Successful finite scalar prediction results can be reused; the miss still calls authoritative `Defense.incoming_burn` and asserts its success. Current health/shield and death arithmetic remain live. Actual settlement receipts, transfer, deaths, rewards, traces and RNG are unchanged.

**Correction to the candidate's premise/comment:** `var_to_bytes([raw_float, original_resistance])` preserves the integer/float distinction but does **not** preserve signed-zero distinctions on this engine. The archived patch is the exact tested source and retains its historically incorrect comment for auditability; that comment is not a current claim or a reusable implementation recommendation. Full observation equality below is equality of complete Godot serialization, not proof that the key preserves every IEEE-754 bit or every possible input.

Reject: the no-burn control was slower in both planned pairs. No further timing variants were run to obtain a favorable result. The ember result is promising in isolation but fails the overall acceptance gate. This is Linux headless script CPU evidence, not Windows FPS or rendering evidence.

## Bounded clean measurements

Each run used fresh XDG data/config/cache directories, a fresh save, a 90-second external watchdog, 100 catalog monsters with AI enabled, a protected player, 180 controlled projectile carriers, and exactly 20 ticks. Normal world geometry and alive-state assertions validate the current fixture entry. Ember uses the first volley and death/transfer workload; no-burn and ordinary ignite use a volley each tick. Timed calls are unwrapped production `arena.tick` only; observation, serialization and saves are outside timing.

| Pair | Mode | Baseline mean µs | Candidate mean µs | Change |
|---|---|---:|---:|---:|
| 1 | Ember | 156276.95 | 122122.95 | -21.85% |
| 1 | No burn | 45474.75 | 48047.30 | +5.66% |
| 1 | Ordinary ignite | 92067.45 | 88143.55 | -4.26% |
| 2 | Ember | 123233.10 | 102799.60 | -16.58% |
| 2 | No burn | 37059.40 | 41269.20 | +11.36% |
| 2 | Ordinary ignite | 89656.90 | 90249.00 | +0.66% |

Order: baseline ember/no-burn/ignite; candidate ember/no-burn/ignite; candidate ignite/no-burn/ember; baseline ignite/no-burn/ember. Large run-to-run variation and the first candidate no-burn outlier are disclosed in per-frame JSON/logs. The bounded two-pair result does not isolate a causal control regression from environmental noise; it does not meet the acceptance criterion either way.

## Exact observations and diagnostics

The complete observer from `burn_profile_allocation_audit.gd` was retained, including expanded runtime/feedback/queue/progress/world fields. No fields were omitted or rounded. All 39 serialized artifacts were verified (30 nontrivial cross-run comparisons plus 9 baseline self-checks): every 20-frame array, final post-save observation and save file, across both baseline/candidate pairs plus the separate ember diagnostic. This covers the observer's explicit fields, not every possible property of a Godot scene node. Hashes and sizes are in `summary.json`; raw observations are preserved outside the repository at its `raw_archive` path. This /tmp archive is ephemeral and is not part of published evidence: readers can inspect committed hashes and regenerate cases, but cannot independently recompare these historical raw bytes after that archive is gone.

A separate instrumented run, excluded from performance conclusions, counted 37,160 hits, 1,222 misses/stores, maximum 4 entries in one call. Its complete observations also matched baseline. The current reproduction harness can select a frozen main via `CACHE20261015_MAIN`; set `CACHE20261015_DIAGNOSTIC=1` only for the instrumented copy.

## Tests and limits

Candidate-era existing tests passed: same-time cleanup/one-hop transfer (19), ember event clock (45), allocation equivalence (797), burn settlement equivalence (full frozen-rule suite), and burn presentation (21).

The focused scalar cache model initially failed two **test assumptions**, recorded in `burn_prediction_cache_20261015_test.log`: signed-zero serialization was assumed distinct, and extremely negative resistance was assumed to cause nonfinite output. In fact resistance is clamped. Corrected expectations passed 497 checks, zero failures (`edges-corrected.log`). The original first-failure log and `tests.json` are retained rather than rewritten. The final test includes repeat hits, unique/capacity bypass, integer/float resistance types, signed zero, invalid/nonfinite input rejection, clamped extreme inputs, changed rates/resistances, and death-time ULP arithmetic. It is a scalar model, not a separately extracted production implementation. Existing cleanup and the full-frame workload cover live transfer. No exhaustive full-scene Cartesian boundary sweep or Windows playtest was run.

## Reproduction

From the repository root:

1. Run `python tools/diagnostics/prepare_burn_prediction_cache_20261015.py`. This reconstructs the exact candidate and an instrumented copy in a new temporary directory using the reachable published baseline (validated against the frozen source hash) plus `candidate.patch`, without touching production.
2. Run `python tools/diagnostics/run_burn_prediction_cache_20261015.py UNIQUE_LABEL ember_deaths` for clean current production. For the archived candidate, set `CACHE20261015_MAIN` to the printed candidate path. Modes are `ember_deaths`, `no_burn`, and `ignite`; each process has its own isolated directories. Existing labels are refused to prevent overwrite.
3. For counts only, select the printed diagnostic path and set `CACHE20261015_DIAGNOSTIC=1`. Do not use that run's timing as clean performance evidence.
4. Run the focused edge test headlessly using an isolated XDG directory. Inspect process output as well as exit status; the corrected test returns failure status when checks fail.

Historical hardcoded generators were not run. The existing burn-settlement test did overwrite its historical results.json with this run's timings; this side effect was detected, its new output preserved as `burn-settlement-rules-current-run.json` here, and the historical file restored byte-for-byte from HEAD. Final tracked-diff inspection confirmed no historical or production changes remain. The new harness was derived from the existing clean stress fixture and full observer. No git staging, commit, branch switch or publication was performed by this worker.
