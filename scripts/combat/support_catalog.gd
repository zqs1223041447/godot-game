class_name SupportCatalog
extends RefCounted
## Bounded original supports. No inventory, drops, levels, quality or gem economy.
const Data = preload("res://scripts/game_data.gd")
const MAX_SUPPORTS: int = 2
const ALLOWED_OPERATIONS: Array[String] = [
	"add_initial_projectiles", "projectile_hit_more", "mana_multiplier",
]
const REQUIRED_CAPABILITIES: Array[String] = ["initial_projectiles", "projectile_hit"]
const SUPPORTS: Dictionary = {
	"volley": {
		"name": "散束辅助",
		"description": "初始投射物 +2；投射物命中伤害总降 20%；魔力消耗 ×1.30。不增加每枚母箭的子箭数，不影响独立爆炸。",
		"requires": ["initial_projectiles", "projectile_hit"],
		"operations": [
			{"op": "add_initial_projectiles", "value": 2},
			{"op": "projectile_hit_more", "value": -0.20},
			{"op": "mana_multiplier", "value": 1.30},
		],
	},
	"focus": {
		"name": "凝束辅助",
		"description": "投射物命中伤害总增 25%；魔力消耗 ×1.20。不影响独立爆炸。",
		"requires": ["projectile_hit"],
		"operations": [
			{"op": "projectile_hit_more", "value": 0.25},
			{"op": "mana_multiplier", "value": 1.20},
		],
	},
}


static func get_definition(id: String) -> Dictionary:
	if not SUPPORTS.has(id) or not definition_error(SUPPORTS[id]).is_empty():
		return {}
	return SUPPORTS[id].duplicate(true)


static func supports_for_skill(skill_id: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in SUPPORTS:
		if compatibility_reason(skill_id, [id]).is_empty():
			result.append(id)
	return result


static func compatibility_reason(skill_id: String, support_ids: Variant) -> String:
	if not Data.SKILLS.has(skill_id):
		return "未知技能"
	if not support_ids is Array:
		return "辅助列表必须是数组"
	if support_ids.size() > MAX_SUPPORTS:
		return "每个技能最多装配两个辅助"
	var capabilities: Variant = Data.SKILLS[skill_id].get("capabilities")
	if not _string_array(capabilities):
		return "技能能力元数据无效"
	var seen: Dictionary = {}
	for value: Variant in support_ids:
		if not value is String or not SUPPORTS.has(value):
			return "未知辅助"
		if seen.has(value):
			return "同一技能不能重复装配辅助"
		seen[value] = true
		var definition: Variant = SUPPORTS[value]
		var error: String = definition_error(definition)
		if not error.is_empty():
			return error
		for capability: String in definition.requires:
			if not capabilities.has(capability):
				return "%s不支持%s" % [Data.SKILLS[skill_id].name, definition.name]
	return ""


## Validate the entire program before the compiler executes any operation.
## Keeping this pure also permits corruption tests without mutating the catalog.
static func definition_error(value: Variant) -> String:
	if not value is Dictionary or value.size() != 4 or not value.has_all(["name", "description", "requires", "operations"]):
		return "辅助元数据结构无效"
	if not value.name is String or value.name.is_empty() or not value.description is String:
		return "辅助说明元数据无效"
	if not _string_array(value.requires) or value.requires.is_empty():
		return "辅助能力元数据无效"
	var seen_capabilities: Dictionary = {}
	for capability: String in value.requires:
		if not REQUIRED_CAPABILITIES.has(capability) or seen_capabilities.has(capability):
			return "辅助能力未受支持或重复"
		seen_capabilities[capability] = true
	if not value.operations is Array or value.operations.is_empty() or value.operations.size() > ALLOWED_OPERATIONS.size():
		return "辅助操作列表无效"
	var seen_operations: Dictionary = {}
	for operation: Variant in value.operations:
		if not operation is Dictionary or operation.size() != 2 or not operation.has_all(["op", "value"]):
			return "辅助操作结构无效"
		if not operation.op is String or not ALLOWED_OPERATIONS.has(operation.op) or seen_operations.has(operation.op):
			return "辅助操作未受支持或重复"
		if not _number(operation.value):
			return "辅助操作数值无效"
		seen_operations[operation.op] = true
		var amount: float = float(operation.value)
		match operation.op:
			"add_initial_projectiles":
				if not seen_capabilities.has("initial_projectiles") or amount != floorf(amount) or amount < 1.0 or amount > 8.0:
					return "初始投射物操作无效"
			"projectile_hit_more":
				if not seen_capabilities.has("projectile_hit") or amount <= -1.0 or amount > 1.0:
					return "投射物命中倍率无效"
			"mana_multiplier":
				if amount <= 0.0 or amount > 10.0:
					return "魔力倍率无效"
	if not seen_operations.has("projectile_hit_more") or not seen_operations.has("mana_multiplier"):
		return "辅助缺少伤害或魔力操作"
	return ""


static func _string_array(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry: Variant in value:
		if not entry is String or entry.is_empty():
			return false
	return true


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
