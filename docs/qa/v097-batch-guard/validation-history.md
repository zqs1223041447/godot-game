# Guard validation history

These are overlapping full runs, not additive test counts.

1. Initial suite: **77 checks / 1 failure**. The intended accepted fixture used
   fire 249, overlooking the stronger burn budget. The guard correctly rejected
   it. The overwritten original log is preserved only as an accurately labelled
   tool-output transcription in `initial-failure-transcription.txt`, together
   with the exact original and corrected fixture lines.
2. Corrected suite with fire 248: **77 checks / 0 failures**. A standalone Godot
   invocation returned process exit zero; observed runtime was 0.724 seconds.
   This run's log/results were replaced by the subsequent full run.
3. Focused source-audit change: reject zero resolved positive-base
   components, because distinguishing complete intentional reduction from
   underflow would require reconstructing damage modifier arithmetic. Added one
   underflow regression. The final suite produced **78 checks / 0 failures** and
   standalone process exit zero in 0.500 seconds. `run.log`, `results.json`,
   `full-run-receipt.json`, and `full-run-sha256sums.txt` refer to this version.
   Exact guard/test source copies are `pre-critical-metadata-guard.gd.txt` and
   `pre-critical-metadata-test.gd.txt`; their hashes match the retained receipt.
4. Coordinator's actual Main candidate identified one overly narrow whitelist
   rejection: existing `critical_modifiers` compiler metadata. Added the exact
   `Combat.snapshot({damage:0.1,crit_base_chance:0.0},[])` then tornado/ember fixture
   in focused-only mode. Before the one-key fix: **4 checks / 1 failure**, process
   exit one, 0.512 seconds. After admitting this metadata: **4 checks / 0
   failures**, process exit zero, 0.473 seconds. Genuine separate logs and JSON
   are retained as `critical-metadata-before.*` and
   `critical-metadata-whitelist-only.*`. This version's source snapshots and
   receipt are named `whitelist-only-*`. No full suite was rerun for this change.
5. On the coordinator's additional requirement, the guard now invokes original
   `CriticalStrikeRules.error` and `CriticalStrikeRuntime.snapshot_error`.
   The same focused group includes invalid metadata/profile cases, frozen
   multiplier direct/burn bounds, and excluded secondary-roll explosions.
   It passed **11 checks / 0 failures**, exit zero in 0.494 seconds. The burn
   assertion was then tightened to ensure the new authoritative DPS wins over
   the existing burn, rather than being masked by the existing maximum. The
   final overlapping focused rerun passed **11 checks / 0 failures**, process
   exit zero in 0.492 seconds. Only this final eleven-check run's log/JSON are
   retained as `critical-metadata-after.log` / `critical-metadata-results.json`.
   `receipt.json` and `sha256sums.txt` describe this final source state. No full
   suite was rerun after either metadata change, and counts are not summed.

No subset count is added to these full-suite results. No Main simulation,
performance test, editor import, production file change, commit, or push was
performed by this guard worker. The coordinator owns any integration experiment
and repository publication.

78-check full test command, from the repository root:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v097-guard-data \
XDG_CONFIG_HOME=/tmp/godot-m1-v097-guard-config \
XDG_CACHE_HOME=/tmp/godot-m1-v097-guard-cache \
godot --headless --path . --script tests/burn_batch_guard_test.gd \
> docs/qa/v097-batch-guard/run.log 2>&1
```

Final eleven-check focused test command (same XDG variables):

```sh
V097_GUARD_CRITICAL_ONLY=1 \
XDG_DATA_HOME=/tmp/godot-m1-v097-guard-data \
XDG_CONFIG_HOME=/tmp/godot-m1-v097-guard-config \
XDG_CACHE_HOME=/tmp/godot-m1-v097-guard-cache \
godot --headless --path . --script tests/burn_batch_guard_test.gd \
> docs/qa/v097-batch-guard/critical-metadata-after.log 2>&1
```

Receipt/hash generation command, after the confirmed exit-zero focused run:

```sh
python3 docs/qa/v097-batch-guard/generate_receipt.py
```

The receipt generator records observed process metadata supplied in its source;
it does not rerun tests or infer the exit code from log contents. It verifies
the final structured check result and hashes the final inputs and evidence.
