# Settlement internal cost diagnostic, 2026-10-15

## Finding and decision

No new materially large **safe optimization** is justified by this one pair. Feedback (355.167 ms, 27.21% of inclusive settlement) and defense (342.179 ms, 26.21%) are the two largest stages. Their known scalar/trusted-interface and defense-profile shortcuts are already rejected directions, not new candidates. Trace is third (149.571 ms, 11.46% settlement / 5.24% tick), with deep-copy isolation and exact retained-order requirements. The measurement does not isolate which portion of any stage can safely be removed. No candidate was implemented. PERF-001 remains open.

Concrete frozen production boundaries:
- `scripts/main.gd:2337` and `2345–2348`: feedback invocation, dictionary construction, runtime record, and success assertion. Runtime `scripts/combat/combat_feedback_runtime.gd:67–101` validates, computes actual resource loss, accumulates in precise event order, handles finite overflow, windows, capacity, position and sequencing. Skipping checks, introducing trusted/scalar APIs, or aggregating events would revive rejected work or alter observable error/order/math boundaries. This broad timing cannot establish a safe removable allocation inside it.
- `scripts/main.gd:2324`: authoritative `Defense.incoming_burn`; correction at `2326–2335` is separately measured. Removing full profile/receipt work follows the already rejected v095 defense shortcut, so it is not proposed again.
- `scripts/main.gd:2339–2342`: complete detached segment record, attach settlement/raw, append and keep last 32. This measurement includes all trace work, not just copying. Shallow-copying provenance or dropping records based only on final visibility lacks a reviewed alias/reentrant observation proof; no such candidate is claimed safe here.
- `scripts/main.gd:2336` and `2338`: resource mutation and death/reward calls are smaller. Death call cost includes the live-enemy early return; 38,382 calls are not 38,382 deaths. Frame 0 has no kills, so the peak cannot be assigned to rewards.

Consulted rejection context: `docs/ACTIVE_WORK.zh-CN.md:56`, `docs/qa/v095-profile/next-scope.md`, `docs/qa/v095-candidate/README.md`, and `docs/qa/burn-prediction-cache-20261015/README.md` / review. These explicitly prohibit reviving scalar-feedback, trusted-caller, rate-helper/prediction-cache and defense-profile approaches without a genuinely different justified boundary.

## Protocol and frozen provenance

Frozen HEAD: `b436cd2cf36fcd3f33326e05aa1b46d78ebe3108`. No production edits, commit, remote operation or full suite. Existing untracked files were left alone. The production tracked diff remained empty.

The entire previous frozen repo copy was copied to this directory, retaining assets/imports. The prior `frozen-manifest.json` is preserved byte-for-byte, covering 239 production script/fixture files; both current source and new copied files match every hash after execution. It is not a manifest of every asset or every repository file. Instrumentation lives in separate `main.gd` selected by the existing override; `res://` dependencies still resolve to this frozen copied project.

One serial clean/instrumented pair only, 20 Ember ticks each; fresh isolated XDG directories, `timeout 90`, both exit 0, completion sentinel present, no SCRIPT ERROR / Parse Error / ERROR lines. No discarded samples, rerun, Windows rendering or broad workload claim. Existing 100 catalog monsters, protected player, seeded Ember setup and 180 controlled carriers, AI/attack scheduling retained. Initial setup counters reset immediately before frame 0. Observer, log output and serialization remain outside timed tick.

The harness derives from the prior diagnostic harness, which derives from `tools/diagnostics/burn_prediction_cache_20261015.gd`. That source still embeds the historical `4e581e2...` label. The inherited copied harness already correctly records the current frozen `b436cd2...` label; only the diagnostic log prefix changes in this task. This does not retroactively establish source provenance for older cache experiments. `harness-provenance.json` records the production historical harness, parent harness, and executed harness hashes. The explicit observer is unchanged and covers its enumerated properties, not every scene property.

## Nonoverlapping stages

These stages partition sequential code inside `_settle_burn_segments`; no nested phase is added to its inclusive parent. There are 38,382 monster segments; player branches were instrumented but did not execute. Counts are stage executions, not death counts.

| Stage | Total ms | ms/tick | % inclusive settlement | % instrumented tick | Calls |
|---|---:|---:|---:|---:|---:|
| monster_feedback | 355.167 | 17.758 | 27.21% | 12.45% | 38382 |
| monster_defense | 342.179 | 17.109 | 26.21% | 12.00% | 38382 |
| trace | 149.571 | 7.479 | 11.46% | 5.24% | 38382 |
| monster_death | 71.564 | 3.578 | 5.48% | 2.51% | 38382 |
| monster_resources | 67.610 | 3.381 | 5.18% | 2.37% | 38382 |
| monster_target | 31.932 | 1.597 | 2.45% | 1.12% | 38382 |
| monster_exact_death | 17.895 | 0.895 | 1.37% | 0.63% | 38382 |
| segment_setup | 12.870 | 0.643 | 0.99% | 0.45% | 38382 |

`monster_target` includes dispatch, dictionary lookup, fallback scan and invalid/dead cleanup; `monster_defense` includes argument evaluation and full initial receipt call; `monster_exact_death` includes the success check, predicate, and conditional ULP correction/second receipt; `monster_resources` includes resource mutation; `monster_feedback` includes predicate and complete feedback call; `monster_death` includes death call arguments and full handling; trace includes nonempty check, deep copy, append and cap. Segment setup initializes raw and receipt container. Each helper ends its own interval and returns the next clock start.

## Instrumentation limitations

Inclusive settlement: 1305.406 ms, 65.270 ms/tick, 45.76% of total instrumented tick. Measured helper bookkeeping: 203.269 ms (15.57% inclusive). Unattributed remainder: 53.349 ms (4.09%). The remainder contains loop cleanup, calls/timers and object-lifetime work; it is not fully calibrated overhead. Helper bookkeeping excludes some timer/counter/return costs; phase clocks include helper dispatch to its first timestamp. Sub-microsecond quantization also affects small stages. Percentages retain the inclusive denominator rather than pretending instrumentation is free.

Clean mean/peak 113.116 / 511.277 ms; instrumented mean/peak 142.623 / 673.476 ms. Instrumentation is materially intrusive (mean +26.09%, peak +31.72%). This is diagnostic, not an optimization or calibrated production cost estimate. Do not mix prior diagnostic timing denominators with these figures. Prior clean peak 543.088 ms is historical; current clean peak 511.277 ms does not establish improvement.

Instrumented peak frame 0 settlement: 314.182 ms of 673.476 ms tick; defense 87.979 ms, feedback 87.293 ms, trace 33.439 ms. There are 9,263 segments but zero kills on that frame.

## Exact equality

All 20 frame observation hashes match; direct byte comparisons of all complete artifacts match:
- `.bin`: 30889476 bytes; SHA-256 `e3898e8b48f52ab42e4a80c9232bb94271946d908c01fdbdeba82a590e73aaff`; direct bytes equal
- `-final.bin`: 1491480 bytes; SHA-256 `30347f555598406f413c120209760d72b2b110037f59b47feff4022d049324cc`; direct bytes equal
- `.save`: 13715 bytes; SHA-256 `c821772f8dc7a1ac5732fca1683f179a70153d42565f0b2b37663001426dd9f4`; direct bytes equal

Hashes also coincide with the prior frozen diagnostic's artifacts. No observer normalization/exclusions. `verification.json` retains every per-frame stage delta and equality checks; raw logs/JSON, binaries/save, source clone, setup/run/verify scripts and manifests are in this directory. Temporary artifacts are not published.

## Stop condition

The scoped one pair is exhausted and the new partition is established. No new safe materially large removable boundary has been demonstrated; do not repeat measurements to seek favorable timing or resurrect rejected interfaces. Further work requires a distinct, statically defensible candidate contract and appropriately scoped evidence, rather than treating these hotspot proportions as acceptance.
