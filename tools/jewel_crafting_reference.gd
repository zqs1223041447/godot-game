extends RefCounted
const JewelCraft = preload("res://scripts/items/jewel_craft_rules.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Canonical = preload("res://scripts/canonical_game_state.gd")

## Detached ordinary-jewel metadata only. No Main, save, drops or full export.
static func build_snapshot() -> Dictionary:
	var operations := {}
	for operation: String in JewelCraft.operation_ids():
		operations[operation] = JewelCraft.operation_metadata(operation)
	return {"rules_version": JewelCraft.RULES_VERSION, "material_id": JewelCraft.MATERIAL_ID,
		"base_ids": Jewels.BASES.keys(), "rarities": Jewels.RARITIES.keys(),
		"salvage_units": JewelCraft.SALVAGE_UNITS.duplicate(), "reforge_costs": JewelCraft.REFORGE_COSTS.duplicate(),
		"affix_counts": {"magic": {"min_prefixes": 1, "max_prefixes": 1, "suffixes": 1},
			"rare": {"min_prefixes": 1, "max_prefixes": 2, "suffixes": 2}},
		"operations": operations, "quote_seconds": Canonical.JEWEL_QUOTE_LIFETIME_MSEC / 1000,
		"preserves": ["id", "base", "rarity", "location"], "save_version": Canonical.Rules.VERSION,
		"source": "scripts/items/jewel_craft_rules.gd", "natural_generator_unchanged": true,
		"equipment_crafting_unchanged": true, "new_currency_or_grants": false}
