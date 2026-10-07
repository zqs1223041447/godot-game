# Four resistance targets over existing crafting

Baseline: `b7d98c5b94c2c39f6f258835b28cfc32c4cd34d9`.

The four new operation IDs are `targeted_reforge_fire_resistance`,
`targeted_reforge_cold_resistance`, `targeted_reforge_lightning_resistance`, and
`targeted_reforge_chaos_resistance`. They append to the existing four targets
without changing their order or seed salt. The planner, weighting algorithm,
transaction code, catalog and economy are reused.

Fire/cold/lightning select existing `emberward/rimeward/stormward` families for
`emberhide_vest`, or their `ring_` variants for `nine_slot_etched_ring`. Chaos
selects only `ring_voidward` on that ring. No slot eligibility is expanded.
Unsupported bases, ordinary/fixed/equipped items and insufficient funds continue
to use existing rejection paths before any fee or random replacement is applied.

Magic costs 16 calibration shards; rare costs 40. The entire original affix set
is replaced, guaranteeing at least one legal selected family, not a high tier.
Existing rarity, prefix/suffix, group and item-level restrictions still apply.
The level 1/8/16 tiers retain their original 8–12 / 13–18 / 19–25 percent ticks;
the catalog performs the existing single /100 conversion. These are raw
resistances, not maximum resistance. The armour's inherent fire resistance is
not a substitute for the guaranteed rolled affix.

New actions use the existing action-specific seed namespace. The old four
target plans and old ordinary craft operations retain their old namespaces.
Historical vocabulary filters still decide which families are available.
No new item fields, save schema, affixes, pools, assets or crafting buttons.
The dynamic metadata dropdown and existing confirmation dialog already support
these targets; only rules declarations change in production.

Focused rules, canonical transactions and real confirmation flow are being
checked before main integration. Resource cache is reused; the CraftingRules
dependency parse passed without repeating the project import.
