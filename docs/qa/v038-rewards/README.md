# v0.38 reward metadata optimization

Base: `f074c2614540f0842964ced961b3430871adce57` (published v0.37).

## Production scope

Only `scripts/items/unified_item_catalog.gd` changes. The canonical state, item
store, save rules, main loop, renderer, UI, versions, catalogs and RNG algorithms
are unchanged. A positive-only metadata memo is bounded to 2048 entries. Each
key contains the **complete typed instance bytes**, current equipment vocabulary
and dynamic support-registry membership. Dictionary lookup compares the complete
bytes, not merely a hash, UID or revision. A new exact value still goes through
the original `validate_instance`; rejected values are never added. Stored and
returned metadata containers are detached, including nested footprint arrays.

2048 exceeds the current canonical 1027-item registry limit so a legal inventory
cannot evict itself during one pass. The ordinary timing fixture holds 38 items
initially and 41 after 20 deaths. No memory-in-MiB estimate was measured. Runtime
catalogs/rules are pinned per loaded script; SupportRegistry membership is the
only mutable registry input to item validation and is explicitly in the key.
There is no runtime catalog reload API. Supporting a future reload requires
including its epoch or clearing this memo.

Every original `Rules.reason` call and final `_persist` validation remains in
place. Location legality, currency totals, serial rules, group compatibility,
progress, source-tree allocation, bindings, migration ledger, external disk
change checks, atomic write, signal/reentrancy and batch-flush ordering remain
at their original boundaries. No reward is delayed, coalesced or dropped.

## Short performance evidence

`death-baseline.json` versus `death-optimized.json` uses the **real production
reward admission** (the probe times public calls; it does not override admission).
Same Linux host, Godot 4.6.3, headless, isolated data/config/cache; three short
samples at each root count, with one real batch save. Median total CPU time:

| Root deaths | Original | Final | Reduction |
|---|---:|---:|---:|
| 1 | 3.544 ms | 2.983 ms | 15.8% |
| 8 | 14.424 ms | 12.141 ms | 15.8% |
| 20 | 28.479 ms | 24.153 ms | 15.2% |

These are descriptive same-host CPU measurements, **not Windows FPS**, rendered
frame rates or statistical performance guarantees. Initial 256-entry candidate
measured 24.074 ms for 20 roots against the earlier 27.471 ms baseline; after increasing the fixed bound, final source
measured 24.153 ms. The sample's small item set never approaches either bound.
The final baseline was rerun in a dedicated detached f074c26 worktree after
shared integration began changing the original source directory. Its complete
32-case oracle remained byte-identical.

`admission-baseline.json` and `admission-cache.json` are earlier instrumented
copies of the original admission body, retained only to locate cost. They show
that gear generation is about 0.3–0.4 ms for two items; the dominant repeated work
is instance metadata validation and full candidate validation. The baseline
20-root metadata subtotal is about 3 ms and the early cache subtotal about 1 ms.
Nested timings are inclusive and must not be added. The original source probe
is `admission_paths_probe.gd`; final performance conclusions use the independent
`death_paths_probe.gd` instead.

## Exact equivalence and boundary tests

`tests/reward_batch_equivalence_v38_test.gd` generated its oracle by running
unchanged against the original checkout, then compared the final optimized code
against it. `baseline-equivalence.json` contains 32 complete observable records:

- 1/8/20 root deaths × 3, plus 58→78 and 118→138 kill boundaries
- Exact UID admission/order, all instance payloads, locations, revisions,
  notification order/busy flags, RNG state, XP/talents and flask charges
- Exact final saved text plus typed in-memory state fingerprints
- Busy, serial/revision limits, duplicate UID, unknown definitions, invalid
  equipment requests, same-UID affix mutation and integer→float payload mutation
- Full 240-cell bag, fragmented horizontal versus vertical flask space, recovery
- Illegal final bindings rejected at admission and persistence, with old bytes intact
- Failed batch write remains dirty and retry produces identical memory/RNG/disk

Baseline and optimized records match byte-for-byte; their SHA-256 is in
`summary.json`. Optimized run: **2146 checks, 0 failures**. Additional optimized-only
checks cover deep-copy isolation, invalid-value non-insertion, dynamic support
removal/restoration, 2048-entry eviction and post-eviction revalidation. The golden
contains the identical output once; no duplicate optimized 1.6 MiB file is kept.

Focused unchanged tests:

- Unified item catalog: 145 checks, 0 failures
- Footprint metadata: 5245 checks, 0 failures
- Canonical game state: 27 checks, 0 failures
- Flask reward boundaries: 25 checks, 0 failures
- Canonical build store: 39 checks, **1 pre-existing failure in both versions**;
  test line 61 requires `Rules.VERSION == 18` while current schema is 23. The
  unrelated historical assertion was not edited; both logs are retained.

No full historical suite, 600-second soak or Windows validation was run here.

## Reproduce

Use a fresh directory for every run, to avoid intentionally protected old saves:

```sh
root=$(mktemp -d /tmp/godot-m1-v038-rewards-check-XXXXXX)
mkdir -p "$root/data" "$root/config" "$root/cache"
XDG_DATA_HOME="$root/data" XDG_CONFIG_HOME="$root/config" XDG_CACHE_HOME="$root/cache" \
  godot --headless --path . --script tests/reward_batch_equivalence_v38_test.gd
```

To regenerate the oracle, run this same script by absolute path with `--path`
pointing to the frozen base checkout, set `REWARD_V38_BASELINE=1`, and set
`REWARD_V38_RECORD_OUT` to a disposable output. Never overwrite the committed
oracle with output from the candidate. For timing, use a fresh
`/tmp/godot-m1-v038-death-*` data root and run
`docs/qa/v038-rewards/death_paths_probe.gd` with `REWARD_PROBE_OUT` and
`REWARD_PROBE_SOURCE` set. Final source and trace digests are in `summary.json`.
