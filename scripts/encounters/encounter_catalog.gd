class_name EncounterCatalog
extends RefCounted
## Original, opt-in encounter parameters. No reward, item, spawn or RNG executor.
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const SCHEMA_VERSION: int = 1
const DEFINITION_REVISION: int = 2
const POLICY_VERSION: int = 2
const MAX_MODIFIERS: int = 2
const SOURCE: String = "res://scripts/encounters/encounter_catalog.gd"
const MODIFIERS: Dictionary = {
	"enemy_max_health_120": {"name":"强健","field":"max_health","operation":"multiply","value":1.20,"multiplier":1.20},
	"enemy_move_speed_110": {"name":"迅行","field":"speed","operation":"multiply","value":1.10,"multiplier":1.10},
	"enemy_damage_115": {"name":"凶猛","field":"damage","operation":"multiply","value":1.15,"multiplier":1.15},
	"enemy_attack_speed_110": {"name":"疾攻","field":"attack_speed","operation":"multiply","value":1.10,"multiplier":1.10},
	"enemy_shield_from_health_20": {"name":"护幕","field":"max_shield","operation":"add_base_health_fraction","value":0.20,"multiplier":1.0},
	"enemy_armour_80": {"name":"铁肤","field":"armour","operation":"add_flat","value":80.0,"multiplier":1.0},
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
	var label: String = {"max_health":"怪物最大生命","speed":"怪物移动速度","damage":"接触与预警伤害基底","attack_speed":"怪物攻击速度","max_shield":"额外出生护盾","armour":"怪物护甲"}[definition.field]
	definition["id"] = id
	definition["source_id"] = "encounter:" + id
	if definition.operation=="multiply":
		definition["description"] = "%s ×%.2f" % [label,float(definition.value)]
		if definition.field=="attack_speed":definition.description+="；预警时长保持，仅加快接触与预警后恢复"
	elif definition.operation=="add_base_health_fraction":
		definition["description"]="%s = 未附本轮普通词缀前最大生命的%.0f%%；与强健顺序无关"%[label,float(definition.value)*100.0]
	else:definition["description"]="%s +%.0f；按单次物理命中大小减伤，元素与混沌不变"%[label,float(definition.value)]
	definition["risk"] = {"field": definition.field, "multiplier": definition.multiplier,
		"relative_increase": float(definition.multiplier) - 1.0,"operation":definition.operation,"value":definition.value,"label":definition.description,"assessment": "prototype_budget_not_balance_proof"}
	return definition


static func source_metadata() -> Dictionary:
	return {"catalog": SOURCE, "schema_version": SCHEMA_VERSION,
		"definition_revision": DEFINITION_REVISION, "policy_version": POLICY_VERSION,
		"balance_source": "original_game_balance",
		"monster_catalog": "res://scripts/monsters/monster_catalog.gd",
		"monster_schema_version": Monsters.SCHEMA_VERSION}


static func resource_policy() -> Dictionary:
	return {"health": "preserve_current_to_max_ratio", "max_health": "multiply_canonical_once",
		"shield": "add_same_bonus_preserve_missing_amount", "max_shield": "add_fraction_of_unmodified_canonical_max_health", "shield_regen": "unchanged",
		"speed": "multiply_canonical_once","damage":"multiply_canonical_once","attack_speed":"multiply_contact_rate_and_recovery_only","telegraph_windup":"unchanged","armour":"add_flat_then_existing_hit_size_formula", "rounding": "float_no_integer_rounding"}


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
