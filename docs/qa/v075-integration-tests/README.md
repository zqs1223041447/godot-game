# v075 source damage/life integration evidence

Result: **1,217 unique checks, zero failures** across eight bounded sections. The final aggregate is `integration-report.json`; it counts the latest result for each logical section once, not the sum of repeated attempts. All runs used Godot 4.6.3 headless and disposable `/tmp/godot-m1-v075-*` XDG roots after the shared parent import gate. The runner never invokes editor/import.

## Coverage

| Section | Unique checks | Evidence |
| --- | ---: | --- |
| registry | 235 | All 23 historical complete definitions, actor/role results and aliases retain bytes; Gale retains the full v74 success shape; only the two exact new IDs are added; old monster whitelist and rejection of `poe_global_damage` remain; typed life capacity is separate from flat stats; repeated grants add; coefficients 0, 0.5, 1 |
| sampling | 765 | 108 deterministic rolls (3 seeds × 3 waves × 12 rolls); both historical and explicit v1 samplers preserve bytes/RNG; current changes only eligible damage/life IDs; actual factory speed/shields/timers/rewards remain unchanged; numeric life/damage change only when their source affix is selected |
| camps | 56 | All three maps, two seeds each; default/explicit legacy checkpoints retain bytes; explicit v1 matches v74; current camp roster changes only eligible identities; invalid policy is atomic |
| arithmetic_maps | 70 | Three species at waves 1, 6, 15; native capacity/global increases once after species/wave/rarity and historical flat grants; duplicate damage adds; real MapCompiler/admission applies HP ×1.2, damage ×1.15, and shield from 20% of canonical source HP; zero/absent paths preserve float bytes |
| special_lineages | 24 | Complete authored templates and natural special/boss factories retain bytes; real splitter, brood and boss death descendants match the frozen v74 runtime |
| cache_transactions | 23 | Three independent cache entries; damage and life refresh affect only new enemies; existing enemies and other entries stay frozen; malformed source clears complete mixed grants and real map admissions roll back IDs/roots/queue/trace |
| main_adoption | 20 | Actual default and natural Main spawn use both new IDs; forced-position RNG matches; Main camp preparation uses current v2; successful/failed preflight preserves canonical state, runtime, RNG, scene and save bytes; schema 47 and source execution version 45 remain |
| combat_consumers | 24 | Actual contact consumes final damage once; explicit targeted ember fixture preserves element split, warning/recovery/burn policy; packet remains frozen through source refresh and actor mutation; actual burn derives DPS once and applies player fire defense afterward |

The bounded sampler encountered source damage 9 times, source life 5 times, splitter 12 times and brood host 8 times. Camp fixtures contained 24 eligible new-source entries. Actual Main's source damage/life seeds are 12 and 5.

The ember guard is an explicit targeted consumer fixture, **not** a new natural spawn policy. Its damage is 28.38, its post-heavy/upfront fire packet is 9.933, and burn DPS is 3.311. Warning remains 0.7 seconds. Its natural authored template is independently byte-equal to v74.

## Frozen baseline and dependency isolation

`frozen/manifest.json` identifies five originals from commit `f2427f3`: source adapter, registry, catalog, camp state and monster runtime. Their `.original.txt` files preserve exact commit content. Fixture changes only remove global class names and redirect source/registry/catalog preloads to isolated frozen counterparts. Both original and fixture SHA-256 hashes are checked before every attempt. The older v74 suite's existing pre-source registry fixture independently establishes the 23 legacy identities.

Every run hashes `project.godot` and all files under production scripts/data/scenes/assets/fonts/audio/shaders before and after execution. All attempts checked **550 production files with zero changes**. Each attempt's `dependency-evidence.json` contains full hashes, command, test fingerprint, duration and errors.

## Attempts and reproducibility

1. `attempts/01/raw.log.txt`: test-local parse failure before any assertion: an inferred local variable reading `arena.state.snapshot()` required an explicit Dictionary type. Preserved unchanged as `first-failed.log.txt`; production files did not change.
2. `attempts/02/raw.log.txt`: after the type annotation fix, every previously unrun section passed: 996 checks in 2.849 seconds.
3. `attempts/03/raw.log.txt`: added explicit per-roll conditional numeric checks and valid life-cache-refresh coverage. Only the two affected sections were rerun: 788 checks in 1.081 seconds. The aggregate therefore has 1,217 unique checks, not 1,784.

Run the complete bounded suite after import:

```sh
python tools/run_source_damage_life_checks.py
```

Rerun only an affected section when its test or relevant dependency changes:

```sh
python tools/run_source_damage_life_checks.py --section combat_consumers
```

Multiple `--section` options are supported. Every attempt retains its own raw log and dependencies. These focused integration checks are not a full historical suite, performance benchmark, screenshot/UI acceptance or Windows-device validation.
