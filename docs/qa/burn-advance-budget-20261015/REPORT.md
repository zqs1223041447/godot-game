# Burn advancement budget diagnostic, 2026-10-15

## Finding / decision

The largest measured internal boundary is `_settle_burn_segments`: 921.299 ms across 20 ticks, 46.065 ms/tick, 49.70% of global advancement inclusive time and 38.09% of all instrumented tick time. On peak frame 0 it consumes 197.940 ms of the 512.040 ms instrumented tick (global advancement 421.352 ms). This is a justified next *diagnostic boundary*, not a demonstrated safe optimization. It includes defense receipts, exact-death correction, resource mutation, feedback, death/reward handling and trace copying; this pair does not distinguish them. Do not revive the rejected prediction-cache, scalar-feedback or trusted-interface proposals on these numbers.

No new concrete optimization can be justified from this pair alone. Snapshot copying, target-map reconstruction, same-time proof/cleanup, and transfer are smaller than settlement. No optimization was implemented or accepted. Current clean peak remains 543.088 ms; PERF-001 remains open.

## Protocol / provenance

- Frozen HEAD: `b436cd2cf36fcd3f33326e05aa1b46d78ebe3108`
- Only `/tmp/burn-advance-budget-20261015` was written. The production checkout was read-only, with no commit or remote operation
- Entire checkout copied to `repo/`, excluding `.git`; existing cache/assets/resources retained. `frozen-manifest.json` freezes 239 production GDScript/fixture files before instrumentation. Both source checkout and copied files match all hashes after both runs. It is a script/fixture manifest, not a hash of every asset or imported engine file
- `main.gd` is a separate instrumented copy selected by the existing harness main override; all `res://` dependencies resolve to the copied project
- Existing 100-catalog-monster, 180-carrier, seeded Ember-deaths fixture; AI/attack scheduling retained, player protected. One clean run followed by one instrumented run, exactly 20 ticks each, serial, fresh XDG per process, external timeout 90 seconds. No rerun or full suite
- Both processes exited 0 and produced the completion sentinel, without script/parse/error lines
- `setup.py` has a pre-run development assertion failure preserved in tool history: overly broad text matching was corrected before either Godot run. There was no failed or discarded benchmark sample
- The unchanged complete explicit observer is retained; initial setup advancement counters are reset immediately before frame 0. Observation, diagnostic log output and save serialization remain outside timed tick
- No Windows renderer, native FPS, broad workload or statistical optimization acceptance claim

## Nonoverlapping timing regions

These are sequential, nonnested regions within `_advance_proliferating_burns`; settlement and transfer include their own callees. Reentrant calls rejected by the preexisting guard are not separately timed. Counts are region executions, not target/segment counts.

| Region | Total ms | ms/tick | % inclusive advancement | Calls |
|---|---:|---:|---:|---:|
| settlement | 921.299 | 46.065 | 49.70 | 948 |
| death_prediction | 393.076 | 19.654 | 21.20 | 394 |
| advance_assembly | 348.686 | 17.434 | 18.81 | 394 |
| status_snapshot | 76.864 | 3.843 | 4.15 | 394 |
| clock_proof | 39.669 | 1.983 | 2.14 | 948 |
| target_map | 22.624 | 1.131 | 1.22 | 948 |
| same_time_cleanup | 14.391 | 0.720 | 0.78 | 554 |
| death_transfer | 3.578 | 0.179 | 0.19 | 948 |

Region details: target_map builds the current ID→body map; clock_proof calls monster_ids_at_time; same_time_cleanup checks/removes missing/dead bodies on the current-clock path; status_snapshot includes empty collection initialization plus statuses() detached-copy/order work; death_prediction includes filtering/removal, defense rate and earliest-death arithmetic; advance_assembly includes collection initialization, advance_target, result assertions, segment/source/exact-death collection; settlement includes defer flag toggles and `_settle_burn_segments`; death_transfer includes `_flush_ember_deaths`.

## Instrumentation overhead and limits

Global inclusive time 1,853.770 ms, 76.64% of total instrumented tick time. Measured helper bookkeeping is 6.169 ms (0.333% of inclusive). Unattributed inclusive remainder is 27.414 ms (1.479%); it contains outer control flow, loop/call cleanup, timer/helper overhead and object lifetime effects. Do not label this entire remainder as overhead or subtract it as if calibrated.

Phase clocks include helper dispatch until its first timestamp; helper measured bookkeeping excludes some timer calls, counter updates and returns. Therefore overhead cannot be fully excluded. Storing statuses() in one local array to time it separately may alter array lifetime timing; it does not change the observed state. Percentages use inclusive time without falsely claiming overhead-free costs. No phase is summed with nested inclusive totals.

Clean mean/peak: 119.660 / 543.088 ms. Instrumented mean/peak: 120.934 / 512.040 ms. Mean +1.07%, peak -5.72%; one ordered pair cannot separate machine variation, instrumentation, or lifetime effects and is not an optimization result. The previous 79.34% global figure is historical, not a denominator used here.

## Exact behavior verification

All 20 per-frame observation hashes match, and direct byte comparisons match for all three complete artifacts:

- `.bin`: 30889476 bytes, SHA-256 `e3898e8b48f52ab42e4a80c9232bb94271946d908c01fdbdeba82a590e73aaff`
- `-final.bin`: 1491480 bytes, SHA-256 `30347f555598406f413c120209760d72b2b110037f59b47feff4022d049324cc`
- `.save`: 13715 bytes, SHA-256 `c821772f8dc7a1ac5732fca1683f179a70153d42565f0b2b37663001426dd9f4`

This covers all fields explicitly enumerated by the inherited observer, not every property in a Godot scene. No normalization or excluded observer fields. Engine/CPU metadata and per-frame gameplay samples are in clean.json/instrumented.json. Cumulative phase logs are in instrumented.log; exact per-frame timing deltas and hash checks are in verification.json. Main/harness hashes are in instrumentation-manifest.json. Raw binaries/save and the frozen copy are temporary and not published.

## Stopping condition

The permitted one diagnostic pair is exhausted. Report settlement as the next bounded internal breakdown to investigate, while explicitly recording that no new defensible optimization target has yet been isolated within it. Further experiments need a separately scoped investigation; do not rerun this pair to search for favorable results.
