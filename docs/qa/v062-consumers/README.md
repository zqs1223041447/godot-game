# v0.62 real-model/main consumer evidence

Baseline: released v0.61 `d884caea7a2260f4535ba4da2d7e005e6df006d4`. Tests use Godot 4.6.3 headless and isolated `/tmp/godot-m1-v062-consumers-*` user data. No GUI, import, production hook, or long simulation was added. This evidence verifies existing C-page/Presenter metadata, not visual or Windows acceptance.

## Concentrated current run

`tests/defense_rating_gameplay_test.gd`: **329 checks, 0 failures, exit 0**, first run. `main-01.json` and `main-01.log.txt` agree on final counters.

| Section | Checks | Evidence |
|---|---:|---|
| Owned equipment/source | 44 | Valid old four-affix control and new six-affix vest enter the real bag; equip, source allocation, refund, reallocation, unequip and disk reload use actual transactions |
| Actual attacks/nonattacks | 47 | Six sequences of 100 actual incoming attacks, plus physical/cold/lightning nonattack controls |
| Burn/resource order | 19 | Exact burn receipts/resources/duration with and without ratings; actual shield/mana/life receipts after mitigation |
| Actual crafts | 187 | All six operations: selected-UID quote, cancel, mismatched UID, injected save failure, same-authority retry, exact current-plan result/cost, replay rejection, reload; insufficient funds for all five paid operations |
| Full bag/natural supply | 30 | Full 240-cell award rejection preserves state/disk/RNG; in-place craft remains legal; actual rare ember-guard deaths route logical defense to current v39 supply |

The source path is the fully implemented connected Duelist route `50986 → 39725 → 24377 → 35568`, allocated one point at a time through real model transactions. The earned-level root setup passes canonical validation. The terminal node adds 6% armour and evasion. With the new vest the resulting ratings are armour **127.2** and evasion **511.5** at Dexterity23. The delta checks prove flat120 and flat450 enter the aggregate base before the existing increase and Dexterity stage, once. Refund, reallocation and unequip reproduce the corresponding final values.

At source-allocated ratings and enemy accuracy100, the old control admits 100/100 attacks, while the new vest admits 76/100 for physical, cold and lightning. Physical damage over100 attacks changes from4000 to1858.1907090464533; cold/lightning each change from3000 to2280. An admitted cold/lightning hit remains30 after the unchanged25% resistance. Nonattack physical still uses armour; elemental nonattacks do not use armour or evasion. These are deterministic isolated hit controls, not a DPS or survival estimate.

The two actual fire burns have exactly equal settlement, resource and remaining-status dictionaries:20 raw DPS for1 second becomes12 damage through the unchanged40% fire resistance. Neither burn advances evasion entropy or creates an attack admission. Resource ordering explicitly uses **synthetic live resource capacities and40% mana guard**, while keeping the equipment-derived armour/evasion: physical100 becomes79.71938775510205, then shield spends10, mana spends27.88775510204082, life loses41.83163265306123. This is not a claim that the tested vest/source route grants mana guard.

Crafting fixtures settle any pending recovery ownership with `first_bag_position` and actual `move_item` before acquisition. Cancel, insufficient shards and failed writes retain exact snapshot/disk bytes, save accounting and RNG; successful retries commit one revision. The current six-operation results are recorded in `main-01.json`. Natural-drop witnesses are also recorded there and deliberately use the new current pool.

Reproduction (choose a fresh numbered XDG directory and output name):

```sh
XDG_DATA_HOME=/tmp/godot-m1-v062-consumers-main-01 \
DEFENSE_RATING_REPORT="$PWD/docs/qa/v062-consumers/main-01.json" \
/usr/local/bin/godot --headless --path "$PWD" \
--script res://tests/defense_rating_gameplay_test.gd
```

The first main log contains fontconfig cache warnings because XDG_CACHE_HOME was omitted; no GDScript errors or assertion failures occurred. Later paired runs supplied an isolated cache directory. The passed main batch was not rerun.

## Frozen-v61/current-v62 equivalence

The exact same external `legacy-02-harness.gd` ran against each project's own production dependencies, including the independently frozen `/workspace/scratch/a51485f153de/v061-final-source-snapshot`. `legacy-v061-production-inputs.json` inventories495 production files (scripts, scenes, data, assets and project/export configs). The parent independently verified the frozen snapshot against the released commit; all pre-run inventoried files were unchanged afterward.

Both runs: **283 checks, 0 failures, exit 0; 90ticks/1.5seconds**. JSON counters equal their final stdout counters. Both produce2 actual casts,3 root kills,774.8 damage, the same shared RNG and private critical checkpoint, and the same explicitly requested immutable `defense` pool item. All equipment in this control is checked to contain no ironhide/mistweave; the three ordinary kills do not reach the automatic equipment interval. New current-pool output is intentional and is tested separately above.

`legacy-comparison-02.json` proves:

- All90 full observations serialize to identical8,748,660-byte binary streams: SHA256 `49d301ce7d343ea75f3388b1333d4598189e025928098c9f9f4cd443137ef1df`
- Observations include enemies, projectiles, lifecycle queues/roots, full model, derived stats, resources, hit/admission/combat traces, timers/cooldowns, flasks/burns/shock, critical/leech, feedback/particles/text/pickups, saves and saved JSON
- Only schema version38/39 is removed from model/saved JSON observations; **no stat, source-cache, combat or RNG projection**
- Raw save bytes differ only at the version38→39 token; projected save bytes match exactly
- Binary evidence is stored as reproducible gzip (`mtime=0`), with uncompressed size/hash recorded

Reproduction uses one unchanged external script for both project paths:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v062-consumers-legacy-v061-02 \
XDG_CACHE_HOME=/tmp/godot-m1-v062-consumers-cache-v061-02 \
DEFENSE_RATING_LEGACY_OUTPUT="$PWD/docs/qa/v062-consumers/legacy-v061-02" \
/usr/local/bin/godot --headless \
--path /workspace/scratch/a51485f153de/v061-final-source-snapshot \
--script "$PWD/docs/qa/v062-consumers/legacy-02-harness.gd"
```

For the current arm, change the XDG/output suffix to `v062-02` and `--path` to the current project. No frozen production file is copied from the current project or edited.

The first pair failed before simulation because the new harness assumed all equipment payloads have an `affixes` key; fixed starter items use an empty payload. `legacy-01-harness.gd`, both `*-01.log.txt` files and their3-check/1-failure JSON reports preserve that failure. The sole correction was iterating `payload.get("affixes", [])`; only that previously failed pair was rerun. No production fix was needed.
