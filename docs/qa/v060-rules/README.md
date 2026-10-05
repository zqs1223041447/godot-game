# v0.60 elemental defense affix rules

Final focused run: **10,466 checks, zero failures, process exit 0, no Godot error lines**, 4.912 seconds with Godot 4.6.3. This is a pure rules/catalog/Craft check; it does not claim scene, save, UI, Windows or long-run performance coverage.

- Final log: `20261005-204206-rules.log.txt`
- Final test counts and concrete roll witnesses: `20261005-204206-result.json`
- Exact command, process status, elapsed time and tested-file SHA-256 hashes: `20261005-204206-receipt.json`
- Frozen v0.59 fixture origin, transforms and unchanged dependency hashes: `fixture-provenance.json`

The first run failed at test-script parse time because a static script was called through a non-static `call()` interface. The test now uses static method callables. Its failure log and receipt are retained under `20261005-204036-*`. The next run passed; the final run also corrects the report's check-count bookkeeping so the JSON and terminal counts match. Production files did not change between runs.

## Contract covered

Only `rimeward`/护寒 (`cold_resistance`, 冰霜抗性) and `stormward`/护雷 (`lightning_resistance`, 闪电抗性) are added. Both are independent percent suffix groups exclusive to `emberhide_vest`, whose authored armor slot resolves to body armour. T1/T2/T3 integer rolls are 8–12/13–18/19–25, unlocked at item levels 1/8/16, with weights 100/60/30. No base, intrinsic fire resistance, old family, maximum resistance, slot, material or Craft operation is added or altered.

The new `defense_v37` pool appends the two suffixes to the frozen nine-family `defense` order. `canonical_v37` preserves the ordered weights 25/20/10/10/30/5 and changes only the 10% defense entry. Historical pools and all historical loot profiles retain exact records and roll behavior. Explicit `generate_for_pool(..., "defense")` remains historical.

- Admission checks cover item levels 1, 7, 8, 15, 16 and 30; both endpoints of every tier; malformed, out-of-range and fractional rolls; every other base; duplicate groups; and rarity prefix/suffix limits
- Natural rolls reach both families at every level boundary, every new family tier, all rarity counts, the current canonical reward dispatch and a legal six-affix item carrying all three resistance suffixes
- Maximum six-affix witness: three T3 capacity prefixes and three T3 resistance suffixes derive life40/mana22/shield22 and raw fire40%/cold25%/lightning25%. Percent ticks divide by100 once, with exact cold/lightning 0.25 scalars and `+25%` display
- Both source-defense actors consume the derived three-element stats. A100-point hit of each element resolves to60+75+75=210 damage. Historical `supports_stat` and `defense_profile` still reject cold/lightning
- All six ordinary Craft operations and existing damage targeting work through unchanged Craft code and costs. Retention, recalibration identity/tier preservation, salvage21/calibration42, no global RNG use, and source immutability are verified
- On emberhide, damage targeting guarantees an elemental-damage suffix. Therefore it cannot fill all three suffix positions with fire/cold/lightning resistance; the two new families remain reachable alongside the guaranteed damage suffix

## Compatibility evidence

**954 typed item plus post-RNG comparisons** cover all eight old pools, all five old loot profiles, the six level boundaries, all three rarities plus unspecified rarity, seeds0/4927/−817, and the historical generation adapters.

**2,406 complete typed Craft-plan comparisons** cover every existing base, all rarities and operations at explicit vocabulary34; default plans on unchanged current pools and old salvage/recalibration; and every explicit equipment vocabulary1–36 on the defense base. Vocabulary35/36 continue to reject equipment and Craft requests exactly as v0.59 did. Save-schema35/36 adapters are separately responsible for mapping to equipment vocabulary34; this test does not reinterpret those explicit equipment APIs.

The old side loads a four-file frozen Catalog/Craft/Expansion/Targeted dependency closure copied from commit `0816322e4c9a53d264bce9c5223810a93ead2348`. Only `class_name` declarations are removed and those four preload edges are routed to the frozen copies. Shared defense, weapon, nine-slot, build-affix, forgeblade and damage dependencies are hash-checked against that commit. The old comparison never calls the new catalog indirectly.

## Reproduce

After the project's ordinary headless import, run from the repository root with isolated XDG paths:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v060-rules/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v060-rules/config \
XDG_CACHE_HOME=/tmp/godot-m1-v060-rules/cache \
ELEMENTAL_AFFIX_REPORT=/tmp/v060-affix-rules-result.json \
godot --headless --path . --script res://tests/elemental_defense_affix_rules_test.gd
```

Require both exit0 and the absence of `SCRIPT ERROR:`/`ERROR:` lines; a log line saying a check passed alone is insufficient.
