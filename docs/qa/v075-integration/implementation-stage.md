# v75 typed source damage and life — implementation stage

Based on f2427f3. This stage admits only source_ember_power (13219:0, current10% increased Damage) and source_grove_vitality (52282:0, current5% increased maximum Life). Source values come from the player parser; Life retains increased mode in a separate capacity accumulator. No other node effects execute. The cache has at most three independently validated source entries, including existing source_gale_stride.

Legacy monster stat admission remains unchanged: old poe_global_damage still cannot be granted to monsters. Legacy IDs/results and the v74 source_stride_v1 sampler remain available. Current source_damage_life_v2 substitutes only the ordinary three-species pool; special splitter/brood/boss templates and descendants retain explicit old bundles. Sampling calls/count/order stay identical.

Damage and maximum life increases each apply once after authored species/wave/rarity/flat bases, before existing map multipliers. Contact/telegraph use that damage snapshot; derived enemy burn is not scaled again. Map shield-from-health continues to use the resulting canonical maximum life. This intentionally changes selected monster budgets; it is not old-damage equivalence or proof of long-term balance.

First shared import:14.361s, exit0, no ERROR lines. Focused source and Main validation is in progress. Schema47/gear46/source45 remain; no UI, art or Windows export/package/Release.
