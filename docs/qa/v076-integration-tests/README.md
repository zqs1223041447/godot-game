# v076 source shield integration

Result: **2,031 unique checks, zero failures, all nine sections complete**. Latest successful evidence is assembled per section, without adding repeated checks. No script errors occurred. Every attempt hashed **552 production dependencies** before and after; all hashes remained unchanged. This worker made no production/UI edits, git writes, or import calls.

The runner uses Godot 4.6.3 headlessly after the shared import gate. Each section gets disposable `/tmp/godot-m1-v076-*` XDG directories. The runner stops immediately on `SCRIPT ERROR`, retains the raw log, and exposes `--section` for focused retries. Each attempt records the runner/test hashes, engine command, complete dependency hashes, section exits, and elapsed time.

## Evidence

- `integration-report.json`: latest result per section, unique counts, observations, attempt history
- `attempts/*/dependency-evidence.json`: before/after hashes and execution details
- `attempts/*/*.log.txt`: raw section logs
- `frozen/manifest.json`: SHA-256 hashes of exact baseline `76c9cab` originals and isolated runnable fixtures
- `first-failed.log.txt` and `first-failed.json`: the original test-fixture failure, retained

| Section | Checks | Latest attempt |
|---|---:|---:|
| registry | 259 | 01 |
| sampling | 658 | 02 |
| camps | 74 | 02 |
| factory_maps | 827 | 02 |
| snapshot_transactions | 98 | 02 |
| cache_atomicity | 29 | 02 |
| special_lineages | 27 | 04 |
| main_adoption | 25 | 03 |
| recharge_lifecycle | 34 | 02 |

The first `main_adoption` fixture inherited a sampler seed whose map roster contained neither new shield identity. Four assertions exposed that fixture problem. The corrected fixture finds a seed containing both IDs within 32 deterministic candidates; seed **2** is selected. Only `main_adoption` was rerun. A subsequent three-assertion expansion checked complete special-lineage snapshots; only `special_lineages` was rerun. No production change was needed for either retry. Raw failure evidence is intentionally not rewritten.

## Covered behavior

- Exact definition and actor-result bytes for all 23 prior flat identities, all aliases, and the prior three source identities at coefficients 0, 0.5, and 1; exact old source return shapes
- Exact legacy/v1/v2 pools, samplers, RNG states and camp snapshots; current v3 remaps only the remaining two Aegis selections for eligible ordinary rolls
- Exact native entries: capacity `58218:0`, recovery capacity `21929:1`, recovery rate `6949:1`; player and monster grants contain percentages without monster flat supplies
- Factory arithmetic for crawler/skitter/brute at waves 1, 6 and 15, including single, paired, repeated-capacity, mixed historical flat shield and mixed historical recharge grants
- Complete independent budget profile with selected supplies, historical bases, base totals, summed capacity increase and frozen multiplier
- Real MapCompiler/MapAdmission shield plus Strong in both selection orders; current and maximum shield gain equal amounts, existing shield is not multiplied again, missing shield is preserved, and duplicate application rejects
- Old actors with no new shield identity preserve their complete original dictionary bytes and exact original map output
- Zero native increases preserve the independent authored bases; invalid scalars and finite overflow fail closed
- Forty-four frozen-profile corruption fixtures plus post-transform overflow; selected source identities with a missing profile reject; consumed frozen scalars, source IDs and mechanism stats are checked without looking up live source definitions
- Source lines changed before map admission cannot change the old actor's frozen multiplier or cause any source-cache lookup
- Rejected actual root/descendant transactions restore IDs, roots, FIFO queue and trace; either invalid recovery source entry fails its bundle atomically
- Shared source cache stays bounded at five entries through alternating source failures; old source cache return bytes and existing actors remain unchanged
- Main natural spawn seeds **8** (capacity) and **12** (recovery), real current camp preflight, source-member rejection, and complete runtime/RNG/canonical/save preservation
- Actual Main hit and burn resource settlement reset the four-second wait; zero and evaded hits do not; partial-frame crossing uses only residual time, recovery clamps at max, and dead actors do not recover
- Capacity-only and map-only shields never acquire a recharge rate; the existing freeze runtime pauses movement/attack while recharge uses global time
- Authored splitter, brood host, boss, elemental and mist templates keep exact baseline bytes; death children and full lineage snapshots remain exact

## Recorded arithmetic

| Selected source IDs | Independent base ES | Capacity increase | Final ES | Final recharge/s |
|---|---:|---:|---:|---:|
| Capacity | 3.12 | 8% | 3.3696 | 0 |
| Recovery | 1.56 | 4% | 1.6224 | 0.46475 |
| Capacity + recovery | 4.68 | 12% | 5.2416 | 0.46475 |
| Capacity + capacity | 6.24 | 16% | 7.2384 | 0 |

For a paired-source rare crawler at wave 1, canonical HP is 95. Strong produces 114 HP; map shield adds `95 × 0.20 × 1.12 = 21.28`, for 26.5216 final ES. At wave 15, canonical HP is 307.8, Strong produces 369.36 HP, and final ES is 74.1888. The test computes these formulas across all three ordinary species and all three selected waves.

The underlying recovery supply is 0.4225/s; the exact native 10% increased recharge rate yields 0.46475/s. The delay remains 4 seconds. No new Life, Mana, leech, or faster-start grant is introduced.

## Reproduce after import

Run `python3 tools/run_source_shield_checks.py` for the nine bounded sections. To retry one section, use e.g. `python3 tools/run_source_shield_checks.py --section recharge_lifecycle`. The runner intentionally never starts editor import. This is a focused integration suite, not a 10k fixture run, benchmark, or complete historical suite.
