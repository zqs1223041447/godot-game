# v0.59 actual main/model consumer evidence

The focused suite passed on 2026-10-05 at 20:09 UTC. These are new v0.59
observations, not a claim based on a previous version's tests passing.

- Actual gameplay/model/panel: **277 checks, zero failures, exit 0**, 3.99 s.
- Frozen v0.58 actual main: **342 checks, zero failures, exit 0**, 3.02 s.
- Current v0.59 actual main: **612 checks, zero failures, exit 0**, 3.12 s.
- Both old-path runs: **90 ticks / 1.5 s**, same seed, no new nodes.
- Entire collected typed observations and projected final save JSON: **equal**.
- No production input changed during any invocation. No production source,
  release metadata, UI source or export was edited by this consumer work.

Run with `/usr/local/bin/godot` through:

```sh
python docs/qa/v059-consumers/run_consumers.py
```

Each process uses its own freshly created `/tmp/godot-m1-v059-consumers-*`
XDG data/config/cache root. The runner never opens the GUI. Run manifests retain
the actual command, process exit code, duration, test hash and every source-input
hash before and after execution. The initial shared import was completed before
this suite ran. The observed application version was still `0.58.0` during the
pre-release integration check; the current save schema was 36.

## Real source and consumers

The harness loads `scenes/main.tscn` and uses its actual `CanonicalGameState`.
It commits a legal level-69 Marauder with 73 earned points, then performs all 73
normal allocation transactions using the shared
[`allocation-witness.json`](../v059-source/allocation-witness.json). All 12 newly
supported maximum-resistance nodes coexist in the resulting legal allocation.

The actual model derives raw fire/cold/lightning 91%/83%/83%, maximum 83% each,
and effective 83% each. A real C panel is instantiated with that model and
completes its refresh; detailed label/tooltip presentation is tested separately.
Nested profile results are detached, and model/panel reads preserve the model,
disk bytes, save count and combat RNG. A new model reloads the same saved build
and derives the same profile.

Focused consumer assertions cover:

- Actual 100-damage incoming hits in each element lose exactly 17 life
- With only 40% raw resistance, adding maximum resistance leaves the same
  60 damage for all three hit elements and player burning
- Player `burn_statuses()` reports 17 effective DPS from a 100 raw DPS burn;
  its one-second real settlement also deals 17, with the raw snapshot unchanged
- Legal reverse-order refunds lower the live fire cap during an admitted burn;
  the display, next burn interval and next incoming hit all use current defense
- Real reallocation restores the 83% behavior for the next hit and burn interval
- Controlled composition with 40% mana guard and 15% Shock: elemental hit total
  is `51 × 1.15 = 58.65`, then 10 shield, 19.46 mana and 29.19 life; feedback
  records only the 39.19 shield-plus-life loss
- Burning ignores hit-only Shock/armour, then settles 17 damage as 5 shield,
  4.8 mana and 7.2 life; feedback is 12.2. The combined-stat test is explicitly
  controlled and does not claim mana guard fits the same 73-point allocation
- All nine actual natural monster templates retain their own defenses while
  the player has all maximum nodes. `elemental_aegis` still adds 20 raw points
  with its original 75% cap; ember guard remains 25% fire naturally and
  45%/20%/20% under aegis

## Independently frozen old-path proof

The runner uses the existing `v058-final-source-snapshot` directory, verified
against released commit `71f4863`. **484 production input files** across scripts,
data, scenes, assets and `project.godot` match byte for byte. It runs the same
external harness against that directory's own frozen main, model, rules and
resources, without replacing any frozen production file or copying a new tree.
The frozen production inputs still match after the run.

The short scenario executes incoming player damage, admitted player burning,
actual compiled casts, projectiles, monster burns, three rewarded root deaths
and loot. It also captures every natural monster and aegis-derived actor before
the scenario. Each tick captures all selected observations, including actor and
projectile dictionaries, lifecycle queues/roots, resources, combat/hit/burn
traces, incoming receipts, burn display, cooldowns, flasks, Shock, critical RNG,
leech, feedback, particles/text/pickups, event counters, save counters, model,
derived stats and parsed disk JSON.

Both runs produce 2 admitted casts, 3 kills/rewarded kills, damage
909.187500000015, player burn life loss 11.8, monster burn life loss
188.662500000001, and final RNG state -2646058150872950320. Events match:
9 spawned, 2 hit, 9 flight-ended, 12 range-reached, 3 split, 12 terminated.

The **only projections** are:

1. Save/model `version` (validated to be schema 35 or 36)
2. The three new derived `maximum_*_resistance_add` keys, each validated to be
   floating-point zero before removal from the observed stat dictionary

No event, other stat, resource, RNG, model field or saved JSON value is removed.
Raw cross-version save bytes are intentionally not compared. Same-version raw
disk-byte preservation is independently asserted around read-only consumers and
nonlethal hit/burn operations.

The typed observation stream SHA-256 is
`7242baef0b1aa43c1fc52b8ce07363796fba5325294f4b439d6c2beb63d17d56` in both runs.
The final projected save JSON SHA-256 is
`06b1135dfcb57c7337e50e0c6060ea597ea4641f9cc053abeb17b3a64cf3f26a` in both runs.
The `.bin.gz` archives are verified lossless compressions of those streams.

## Evidence files

- [Combined result and commands](20261005T200917792922Z-summary.json)
- [Actual gameplay report](20261005T200917792922Z-gameplay.json)
- [Actual gameplay log](20261005T200917792922Z-gameplay.log.txt)
- [Frozen input verification](20261005T200917792922Z-frozen-inputs.json)
- [Frozen v58 report](20261005T200917792922Z-v058.json)
- [Current v59 report](20261005T200917792922Z-v059.json)
- [Frozen observation archive](20261005T200917792922Z-v058.bin.gz)
- [Current observation archive](20261005T200917792922Z-v059.bin.gz)

This is a focused consumer and bounded old-path regression suite, not a long
simulation or a rerun of historical test suites. No failing invocation occurred.
