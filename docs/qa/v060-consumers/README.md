# v060 actual equipment, combat and crafting consumers

The focused run `20261005T204053227759Z` passed **613 checks, 0 failures**, process exit **0**, in **16.22 seconds** on Godot 4.6.3. Its raw log contains no ERROR or SCRIPT ERROR. The run manifest records the exact command, isolated XDG directory, harness SHA-256, all production input SHA-256 values before/after, and confirms production inputs were unchanged during execution.

Run after the shared project import:

```sh
python docs/qa/v060-consumers/run-focused.py
```

The runner performs no resource import, historical seed matrix, long combat simulation, export, or screenshot capture. Each invocation creates a fresh `/tmp/godot-m1-v060-consumers-*` directory. Raw failed attempts are retained.

## Verified behavior

- A valid T3 maximum emberhide vest has three prefixes and three suffixes: +32 life, +22 mana, +22 shield, +25 fire/cold/lightning resistance. Including its base, the item supplies +40 life and raw 40%/25%/25%. A fourth suffix is rejected, so mana recovery, movement and damage compete for the same capacity. Magic cold/lightning coexistence is rejected; white retains only 15% fire.
- Real main acquisition/admission, guarded equipment transfers and build-change signals propagate cold/lightning integer rolls through exactly one `/100` conversion. With actual +25% gear, each real incoming 100-damage hit deals 75 health damage. Swapping to white removes cold/lightning while preserving base fire, and unequipping removes the new raw resistances. UID, bag/equipment locations and the complete saved build survive reload.
- Controlled combat stats combine the actual item's 25% raw resistance with another 65% and an explicit maximum-resistance bonus. The shared 83% safety ceiling limits each real hit to 17 damage. This fixture does not claim that the vest alone grants the extra raw or maximum resistance, or that this is an allocated source-tree build.
- The actual C panel reads the model's authoritative resistance profile, displays 25% with the correct raw tooltip and unchanged 75% default maximum. Shared affix/card formatting shows +25%. These reads preserve the model, raw saved bytes, save count and main RNG.
- Actual wave-nine rare ember-guard root deaths retain logical `equipment_pool = defense`, then main routes them to the current `defense_v37` pool. Witness seed 1 produces a rimeward item; seed 2 produces rimeward and stormward together. Each item enters the real bag. Duplicate root death and actual splitter descendants grant no second reward. Explicit `state.award_equipment(..., "defense")` still produces the old fire-only result. Current natural loot is intentionally allowed to differ from old natural loot; this run makes no cross-version same-seed claim.
- All six original crafting actions use real owned item UIDs and bag currency. Exact economics from an initial 200 shards: salvage +21, recalibrate -42, enchant -8, elevate -24, augment -6, rare reforge -28. Calibration retains family/order/tier; augmentation and elevation retain the existing exact cold roll. Lawful crafting-revision witnesses make real enchant and reforge transactions produce a new family. Outputs, locations and full saves are checked against authoritative deterministic plans.
- Cancellation, mismatched selected source, repeat confirmation, insufficient money, changed model revision, external file re-encoding, reload and injected save failures preserve the appropriate complete authoritative memory/disk state and currency. Failed writes emit no change or successful save; retry commits once. Successful crafting uses private randomness and preserves unrelated UIDs and locations.
- Full 240-cell bags reject current, new-defense and legacy-defense awards with exact RNG, currency, serial and state preservation; invalid pool requests also reject unchanged. A full bag still permits same-UID in-place calibration at the exact fee.
- Existing damage-target reforge charges 40 shards and guarantees at least one eligible damage suffix. With at most three suffixes, it cannot also occupy all three resistance suffixes. The ten-operation menu remains six original and four existing targeted operations.

## Evidence and limitations

- `20261005T204053227759Z.log.txt`: complete successful process output
- `20261005T204053227759Z-checks.json`: section counts, actual craft economics/output instances and natural reward witness items
- `20261005T204053227759Z-run.json`: exit status, timing, command, isolated directory and before/after source hashes
- `20261005T204036678617Z.log.txt` and matching run manifest: first attempt failed before running checks because test constant `Panel` shadowed the native class. The test constant was renamed to `CharacterPanel`; no production fix was needed

This is a focused consumer/transaction check. Strict schema36 migration, source policy36, full historical seeded byte compatibility, source-node allocation and presentation layout are owned by separate checks and are not claimed here. No production code, version, UI, artwork, existing test, commit or push was changed by this worker.
