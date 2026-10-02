class_name EncounterCatalog
extends RefCounted
## Original, opt-in encounter parameters. No reward, item, spawn or RNG executor.
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const SCHEMA_VERSION: int = 1
const DEFINITION_REVISION: int = 1
const POLICY_VERSION: int = 1
const MAX_MODIFIERS: int = 2
const SOURCE: String = "res://scripts/encounters/encounter_catalog.gd"
const MODIFIERS: Dictionary = {
	"enemy_max_health_120": {"name": "强健", "field": "max_health", "multiplier": 1.20},
	"enemy_move_speed_110": {"name": "迅行", "field": "speed", "multiplier": 1.10},
}


static func get_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(MODIFIERS.keys())
	ids.sort()
	return ids


## Every description, operation and risk parameter comes from the same definition.
static func get_definition(id: String) -> Dictionary:
	if not MODIFIERS.has(id):
		return {}
	var definition: Dictionary = MODIFIERS[id].duplicate(true)
	var label: String = "怪物最大生命" if definition.field == "max_health" else "怪物移动速度"
	definition["id"] = id
	definition["source_id"] = "encounter:" + id
	definition["description"] = "%s ×%.2f" % [label, float(definition.multiplier)]
	definition["risk"] = {"field": definition.field, "multiplier": definition.multiplier,
		"relative_increase": float(definition.multiplier) - 1.0, "assessment": "parameter_only"}
	return definition


static func source_metadata() -> Dictionary:
	return {"catalog": SOURCE, "schema_version": SCHEMA_VERSION,
		"definition_revision": DEFINITION_REVISION, "policy_version": POLICY_VERSION,
		"balance_source": "original_game_balance",
		"monster_catalog": "res://scripts/monsters/monster_catalog.gd",
		"monster_schema_version": Monsters.SCHEMA_VERSION}


static func resource_policy() -> Dictionary:
	return {"health": "preserve_current_to_max_ratio", "max_health": "multiply_canonical_once",
		"shield": "unchanged", "max_shield": "unchanged", "shield_regen": "unchanged",
		"speed": "multiply_canonical_once", "rounding": "float_no_integer_rounding"}


## null means no budget has been proposed or balanced. It is not a loot modifier.
static func reward_budget_metadata() -> Dictionary:
	return {"status": "metadata_only", "enabled": false, "proposed_bonus_fraction": null,
		"grants_rewards": false, "creates_map_items": false}


## Future UI/reference consumers may use this detached metadata without a second table.
static func metadata() -> Dictionary:
	var definitions: Array[Dictionary] = []
	for id: String in get_ids():
		definitions.append(get_definition(id))
	return {"source": source_metadata(), "max_modifiers": MAX_MODIFIERS,
		"definitions": definitions, "resource_policy": resource_policy(),
		"reward_budget": reward_budget_metadata()}


static func selection_error(ids: Variant) -> String:
	if not ids is Array:
		return "挑战 ID 必须为数组"
	if ids.size() > MAX_MODIFIERS:
		return "每个遭遇最多两个挑战"
	var seen: Dictionary = {}
	for id: Variant in ids:
		if not id is String or not MODIFIERS.has(id):
			return "未知挑战 ID"
		if seen.has(id):
			return "不能重复选择同一挑战"
		seen[id] = true
	return ""
