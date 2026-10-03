class_name ProjectileSupportRules
extends RefCounted
## Pure extension registered through SupportRegistry; no state or save writes.
## Pass a fresh legacy-compiled bolt/frost recipe and the COMPLETE link list once.
## Legacy links are validated here, but only extension effects are returned.
const Data = preload("res://scripts/game_data.gd")
const Legacy = preload("res://scripts/combat/support_catalog.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const MAX_INITIAL_PROJECTILES: int = 9
const MAX_PIERCE: int = 100
const APPLIED_KEY: String = "_projectile_support_ids"
const RECIPE_SKILLS: Array[String] = ["bolt", "frost", "shade_bolt"]
const OPERATIONS: Array[String] = ["add_pierce", "projectile_hit_more", "mana_multiplier"]
const CAPABILITIES: Array[String] = ["finite_projectile_pierce", "projectile_hit"]
const SUPPORTS: Dictionary = {
	"pierce": {
		"name": "贯穿辅助",
		"description": "飞弹、冰霜与蚀影飞弹穿透 +2；投射物命中伤害总降 15%；魔力消耗 ×1.20。龙卷无限穿透不适配；普攻与独立爆炸不变。",
		"skills": ["bolt", "frost", "shade_bolt"],
		"requires": ["finite_projectile_pierce", "projectile_hit"],
		"operations": [
			{"op": "add_pierce", "value": 2},
			{"op": "projectile_hit_more", "value": -0.15},
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
	if not RECIPE_SKILLS.has(skill_id) or not Data.SKILLS.has(skill_id):
		return result
	for id: String in SUPPORTS:
		if compile_extension(skill_id, Data.SKILLS[skill_id].get("projectile_recipe"), [id]).error.is_empty():
			result.append(id)
	return result


## Stable four-field result, including failure: no partial recipe or modifiers.
## Variant inputs intentionally turn malformed data into errors, not coercions.
static func compile_extension(skill_id: Variant, recipe: Variant, support_ids: Variant) -> Dictionary:
	if not skill_id is String or not Data.SKILLS.has(skill_id):
		return _failure("未知技能")
	if not RECIPE_SKILLS.has(skill_id):
		return _failure("贯穿扩展仅接受飞弹、冰霜或蚀影飞弹配方；龙卷无限穿透不适配")
	var error: String = _recipe_error(recipe)
	if not error.is_empty():
		return _failure(error)
	if not support_ids is Array:
		return _failure("辅助列表必须是数组")
	if support_ids.size() > Legacy.MAX_SUPPORTS:
		return _failure("每个技能最多装配两个辅助（含已有辅助）")
	var legacy_ids: Array = []
	var extensions: Array[String] = []
	var seen: Dictionary = {}
	# Validate the complete selection and every program before producing effects.
	for value: Variant in support_ids:
		if not value is String or value.is_empty():
			return _failure("未知辅助")
		if seen.has(value):
			return _failure("同一技能不能重复装配辅助")
		seen[value] = true
		if SUPPORTS.has(value):
			var definition: Variant = SUPPORTS[value]
			error = definition_error(definition)
			if not error.is_empty():
				return _failure(error)
			if not definition.skills.has(skill_id):
				return _failure("技能不支持此投射物辅助")
			if definition.requires.has("finite_projectile_pierce") and int(recipe.pierce) < 0:
				return _failure("无限穿透配方不适配贯穿辅助")
			extensions.append(value)
		elif Legacy.SUPPORTS.has(value):
			legacy_ids.append(value)
		else:
			return _failure("未知辅助")
	error = Legacy.compatibility_reason(skill_id, legacy_ids)
	if not error.is_empty():
		return _failure(error)
	var capabilities: Variant = Data.SKILLS[skill_id].get("capabilities")
	if not _strings(capabilities) or not capabilities.has("projectile_hit"):
		return _failure("技能缺少投射物命中能力")
	# Preflight aggregate bounds too: never clamp away part of an admitted effect.
	var pierce: int = int(recipe.pierce)
	var mana_multiplier: float = 1.0
	extensions.sort()
	for id: String in extensions:
		for operation: Dictionary in SUPPORTS[id].operations:
			if operation.op == "add_pierce":
				pierce += int(operation.value)
			elif operation.op == "mana_multiplier":
				mana_multiplier *= float(operation.value)
	if pierce > MAX_PIERCE or not is_finite(mana_multiplier):
		return _failure("扩展后的穿透或魔力倍率超出边界")
	var compiled_recipe: Dictionary = recipe.duplicate(true)
	var modifiers: Array[Dictionary] = []
	if not extensions.is_empty():
		compiled_recipe.pierce = pierce
		compiled_recipe[APPLIED_KEY] = extensions.duplicate()
	for id: String in extensions:
		for operation: Dictionary in SUPPORTS[id].operations:
			if operation.op == "projectile_hit_more":
				modifiers.append({"id": "support:" + id, "mode": "more", "value": float(operation.value),
					"all_tags": ["hit", "projectile"], "skills": [skill_id], "damage_types": []})
	return {"recipe": compiled_recipe, "modifiers": modifiers, "mana_multiplier": mana_multiplier, "error": ""}


## Detached metadata for future UI/reference consumers is the executable source.
## This validator also permits corruption tests without modifying catalog constants.
static func definition_error(value: Variant) -> String:
	if not value is Dictionary or value.size() != 5 or not value.has_all(["name", "description", "skills", "requires", "operations"]):
		return "扩展辅助元数据结构无效"
	if not value.name is String or value.name.is_empty() or not value.description is String or value.description.is_empty():
		return "扩展辅助说明无效"
	if not _strings(value.skills) or value.skills.is_empty() or not _strings(value.requires) or value.requires.size() != CAPABILITIES.size():
		return "扩展辅助技能或能力无效"
	var seen: Dictionary = {}
	for id: String in value.skills:
		if not RECIPE_SKILLS.has(id) or seen.has(id):
			return "扩展辅助技能未受支持或重复"
		seen[id] = true
	seen.clear()
	for capability: String in value.requires:
		if not CAPABILITIES.has(capability) or seen.has(capability):
			return "扩展辅助能力未受支持或重复"
		seen[capability] = true
	if not value.operations is Array or value.operations.size() != OPERATIONS.size():
		return "扩展辅助操作列表无效"
	seen.clear()
	for operation: Variant in value.operations:
		if not operation is Dictionary or operation.size() != 2 or not operation.has_all(["op", "value"]):
			return "扩展辅助操作结构无效"
		if not operation.op is String or not OPERATIONS.has(operation.op) or seen.has(operation.op) or not _number(operation.value):
			return "扩展辅助操作未受支持、重复或数值无效"
		seen[operation.op] = true
		match operation.op:
			"add_pierce":
				if not _integer(operation.value, 1, MAX_PIERCE):
					return "穿透增量无效"
			"projectile_hit_more":
				if float(operation.value) <= -1.0 or float(operation.value) > 1.0:
					return "投射物命中倍率无效"
			"mana_multiplier":
				if float(operation.value) <= 0.0 or float(operation.value) > 10.0:
					return "魔力倍率无效"
	return ""


static func _recipe_error(recipe: Variant) -> String:
	# Keep the v0.12/v0.13 flat launch schema; do not accept runtime shot dictionaries.
	if recipe is Dictionary and recipe.has(APPLIED_KEY):
		return "配方已应用扩展；必须从基础构筑重新编译，不能重复应用"
	if not recipe is Dictionary or recipe.size() != 8 or not recipe.has_all(["initial_count", "spread", "coefficient", "added_effectiveness", "pierce", "slow", "speed", "damage_type"]):
		return "投射物配方结构无效"
	if not _integer(recipe.initial_count, 1, MAX_INITIAL_PROJECTILES) or not _integer(recipe.pierce, -1, MAX_PIERCE):
		return "投射物数量或穿透无效"
	for key: String in ["spread", "coefficient", "added_effectiveness", "slow", "speed"]:
		if not _number(recipe[key]) or float(recipe[key]) < 0.0:
			return "投射物配方数值无效"
	if float(recipe.speed) <= 0.0 or not recipe.damage_type is String or not Damage.TYPES.has(recipe.damage_type):
		return "投射物速度或伤害类型无效"
	return ""


static func _failure(error: String) -> Dictionary:
	return {"recipe": {}, "modifiers": [], "mana_multiplier": 1.0, "error": error}


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _strings(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry: Variant in value:
		if not entry is String or entry.is_empty():
			return false
	return true
