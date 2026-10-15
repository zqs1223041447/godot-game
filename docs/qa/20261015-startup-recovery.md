# Startup recovery failure acceptance — 2026-10-15

Baseline: `e9a0c95`; Godot `4.6.3.stable.official.7d41c59c4` (Linux headless).
Scope: regression coverage only. No production defect reproduced and no production source modified.

## Fixture and exercised paths

`tests/startup_recovery_failure_test.gd` uses the real canonical model, save receipt and `scenes/main.tscn` startup. Two supported free-map admission/completion/claim sequences fund eight physical shards and unlock tier II. A supported paid admission spends four shards, leaving four. Sixty supported root-kill reward updates produce two pending gems and one pending flask, then save them. No journey fields, world flags or balances are directly fabricated.

A fresh instrumented model loads that persisted receipt inside Main's `_ready()`. Its `_write_bytes` rejects writes, while `normal_abandon_map` delegates to the real transaction and merely counts attempts/commits. The test asserts exact snapshot, disk bytes, revision, successful-save count, original run ID, fee and reward retention. It then exercises each transition separately, with both wrong revision and continued IO failure, before restoring writes:

- `start`: real paid town draft and `start_map`; abandons the old receipt once, charges exactly one new four-shard fee, allocates exactly one new run ID and enters the actual map
- `leave`: `leave_normal_town`; clears the old receipt once and reaches normal practice without refund or extra reward
- `test`: `enter_town_test`; clears the old normal receipt once and replaces the profile with the independent test save, preserving the normal on-disk state

The `completed_` counterparts first complete the paid run through the supported model transaction, leaving an existing unclaimed map reward. Startup must not even attempt abandonment. A new map remains blocked; leaving town and entering the test profile preserve all pending rewards and unlocks. All six scenarios verify exact normal-save reload and rejection of old-receipt completion/abandonment; repeated transitions cannot create extra changes.

## Results

| Scenario | Checks | Failures | Exit |
| --- | ---: | ---: | ---: |
| start | 27 | 0 | 0 |
| leave | 26 | 0 | 0 |
| test | 26 | 0 | 0 |
| completed_start | 25 | 0 | 0 |
| completed_leave | 24 | 0 | 0 |
| completed_test | 24 | 0 | 0 |
| Total positive coverage | 152 | 0 | |

Negative control: `STARTUP_RED_CONTROL=skip_recovery STARTUP_CASE=start` substitutes only Main's recovery hook with an intentional no-op. The unchanged startup assertions detect the missing real abandon attempt: 13 checks, 1 failure, exit 1. This opt-in deliberately broken test subclass is not a production fix or a positive acceptance path. It exits after startup assertions to avoid cascading scenario errors. No script/parse/runtime errors occurred in positive runs.

## Reproduce

Run sequentially from the repository root, with a fresh isolated directory per scenario. Do not run a shared editor import alongside these tests.

```bash
set -eu
unset STARTUP_RED_CONTROL
for scenario in start leave test completed_start completed_leave completed_test; do
  base=$(mktemp -d /tmp/godot-startup-recovery.XXXXXX)
  mkdir -p "$base/data" "$base/config" "$base/cache"
  STARTUP_CASE="$scenario" \
    XDG_DATA_HOME="$base/data" XDG_CONFIG_HOME="$base/config" \
    XDG_CACHE_HOME="$base/cache" \
    timeout 90 godot --headless --path . \
      --script tests/startup_recovery_failure_test.gd
  rm -rf "$base"
done
```

The test rejects missing/unknown scenario names, an incorrect `/tmp/godot-startup-recovery.` prefix, a user-data directory outside the isolated root, or an existing normal save, with exit 78 before writing a fixture. The negative control uses the same isolated command, adds `STARTUP_RED_CONTROL=skip_recovery` and selects `STARTUP_CASE=start`; expect exit 1 and the `STARTUP_RECOVERY_RED 13 checks, 1 failures` summary. Each process is independently limited to 90 seconds.

Limitations: this is deterministic headless transaction/transition coverage, not a visual review or a simulation of every OS-level save failure. The injected write error uses the existing atomic-save failure path. The fixture deliberately uses supported model completion transactions rather than combat kills to prepare history; actual Main startup and transition handlers are exercised for the recovery under test.
