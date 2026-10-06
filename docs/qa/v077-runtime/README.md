# v077 pure outcome runtime verification

Scope: `CombatFeedbackRuntime` adds independent outcome history and miss markers. Damage `record()` and `entries()` retain their existing contract, return shape, validation order, floats, and output sequences. Only `evaded` creates a marker; `zero_damage`, `terrain_blocked`, and `spawn_protected` only create individual history receipts.

The history retains the latest 32 observations in call order. The gameplay `at` field is data, never a sorting key or presentation clock. Optional top-level `skill_id` / `phase` fields default to empty Strings; `cast_id` / `projectile_id` default to integer zero. Present optional fields are validated strictly. Chance is required, finite and within [0,1] for `evaded` only, and only those receipts expose it.

Miss markers merge by monster in fixed 0.20-second windows, retain count and latest position, and live for 0.75 seconds after their deadline. There are at most 24 pending and 8 visible markers, independently of the original 303 pending / 48 visible damage limits. Overflow drops the oldest pending marker without publishing it early; every accepted observation still enters history. A new publication replaces the same target's prior marker. Target death first flushes damage, then removes that target's pending and visible miss markers while preserving history. Reset clears both observer stores and history; observer IDs remain unique across resets and never consume damage IDs. Marker IDs are negative integers, disjoint from positive damage IDs in a combined renderer list; their internal publication sequence remains positive and increasing. F6 history has its own positive IDs.

## Frozen damage oracle

`combat_feedback_runtime.baseline.gd.txt` is an unchanged copy from commit `587c195d2a78c2028f1ae781b3aa460426fc898c`, SHA-256 `a22cebcb8a73f705c5c976363c0c328c3b3c349ca8357bbf73708e465585a1df`. The test verifies this digest and loads a copy in memory, stripping only its global `class_name` registration to avoid a duplicate class. It never edits the fixture.

The same damage operation traces run against the frozen baseline and current runtime, both with no observations and with observations interleaved. Every public operation return, `entries()` snapshot, and all original damage state fields must match `var_to_bytes()` exactly, including float representations, invalid-input error precedence, zero drop, 303/48 overflow, reset, death flush, and independently increasing IDs.

Additional checks cover all four outcome schemas, strict metadata types, read-only inputs, detached outputs, full-state atomic rejection, decreasing gameplay times, 24/8/32 limits, exact 0.20/0.75 boundaries, same-target replacement, pause, long advances, huge-clock rejection, and unchanged RNG state.

## Run

After the coordinator's single project import, run only:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v077-runtime/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v077-runtime/config \
XDG_CACHE_HOME=/tmp/godot-m1-v077-runtime/cache \
/usr/local/bin/godot --headless --path . --script res://tests/combat_outcome_runtime_test.gd
```

A pass requires process exit code 0 and `COMBAT_OUTCOME_RUNTIME_TEST_COMPLETE checks=<n> failures=0`. No historical broad suites are part of this runtime check.

Status: implementation prepared; execution awaits the coordinator's project import.
