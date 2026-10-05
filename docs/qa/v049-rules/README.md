# v0.49 targeted reforge rules verification

## Result

Godot 4.6.3 headless test completed with exit code 0:

```text
Weighted target tier sample: { 1: 961, 2: 618, 3: 321 }
Targeted reforge rules: 17920 checks, 0 failures; 672 quotes, 504 bounded matrix plans
```

The focused test is `tests/targeted_reforge_rules_test.gd`; the captured engine log is `rules.log` beside this report. This verifies the pure helper, not the transaction or UI integration.

## Contract

`scripts/items/targeted_reforge_rules.gd` exposes `operation_ids()`, `metadata(operation)`, `quote(instance, operation, vocabulary)`, and `plan(instance, operation, seed_value, vocabulary)`. Vocabulary defaults to the existing catalog's current value, 27. `COSTS` is the single fee source: magic 16 and rare 40 calibration shards.

Four operation IDs are frozen for this release:

- `targeted_reforge_critical`: `global_critical_chance`, `global_critical_multiplier`
- `targeted_reforge_life_leech`: `attack_life_leech`
- `targeted_reforge_mana_leech`: `attack_mana_leech`
- `targeted_reforge_damage`: `runesong`, `prismedge`, `farweave`, `coalglow`, `rimeecho`, `sparkthread`, `attack_added_physical`, `attack_added_fire`, `spell_added_cold`, `spell_added_lightning`, `whetstone_edge`, `tempered_edge`

These allowlists only filter the selected base's existing versioned pool. They do not add eligibility. In vocabulary 27, critical and both leech targets are available on `wayglass_token`, `pulse_seed`, `nine_slot_etched_ring`, and `nine_slot_threaded_gloves`. Damage is available on the nine non-nine-slot bases and unavailable on all five nine-slot bases.

Quote validates the entire source instance and supported rarity before checking target availability and completion feasibility. Its result contains economics, display metadata and reachable counts, without a rolled instance, seed or definition. Failure carries an empty cost and no partial output. A missing target returns `no_legal_target`; target choices that cannot complete return `no_legal_result`.

Plan calls quote and rejects a non-integer seed before constructing a local RNG. Therefore every absent-target or invalid-instance rejection occurs before RNG construction. Quote has no RNG path. Successful plans also leave the global RNG untouched.

The final count is uniform among feasible counts. The first affix is selected by original positive catalog family-tier weights from target candidates whose remaining group and prefix/suffix capacity can complete that count. Subsequent affixes use the same weighted viability rule over the ordinary pool. Original inclusive roll ranges and level gates remain authoritative. No maximum-tier guarantee is introduced.

The source ID, base, item level, rarity and five-field instance shape are preserved. The full affix list is replaced, with results permitted to coincidentally match or be worse. Final validation and derived definition both delegate to EquipmentCatalog. There are no wallet, save or schema changes in this helper.

## Coverage

- All 14 current bases, magic and rare, and all four operations
- Actual tier unlock interval boundaries: item levels 1, 7, 8, 15, 16 and 30
- 672 availability quotes; 504 bounded matrix plans with seeds 0 and -49049, each repeated to check determinism
- Independent final catalog, group uniqueness, rarity count, prefix/suffix, level, roll-range and base-pool checks
- Full eligible target family-tier membership, exact catalog weights and inclusive ranges at every matrix boundary
- Synthetic shared-group dead end: a target that removes the only available suffix is excluded before selection; both feasible tiers retain their original weights
- Unknown and non-string operation, malformed instance, extra fields, illegal affix/value/tier/base, duplicate group, normal rarity, malformed seed and invalid vocabulary rejection
- One vocabulary-26 probe: damage remains legal in its historical pool; build-affix targets are absent; a v27-only source affix is rejected
- A bounded 1,900-draw weighted target sample distinguishes original 100:60:30 tier weights from uniform or best-tier selection
- A bounded 32-seed sample reaches all magic/rare counts and all three target tiers at high item level
- Detached metadata and plan payloads; unchanged source bytes; global RNG isolation

No exhaustive historical generation, extra GUI, or long-running soak was run.

## Reproduce

After the parent's single shared resource import:

```sh
env XDG_DATA_HOME=/tmp/godot-m1-v049-rules/data \
    XDG_CONFIG_HOME=/tmp/godot-m1-v049-rules/config \
    XDG_CACHE_HOME=/tmp/godot-m1-v049-rules/cache \
    /usr/local/bin/godot --headless --path . \
    --script res://tests/targeted_reforge_rules_test.gd \
    --log-file docs/qa/v049-rules/rules.log
```

The XDG directories and log directory must exist. The test rejects an XDG data path outside `/tmp/godot-m1-*`.
