class_name AreaSupportRules
extends RefCounted
## One bounded extension. Geometric area is multiplied; radius uses its square root.
## No RNG, saved-state writes, projectiles, independent explosions or enemy attacks.
const Data = preload("res://scripts/game_data.gd")
const Legacy = preload("res://scripts/combat/support_catalog.gd")
const RECIPE_SKILLS: Array[String] = ["nova", "meteor"]
const OPERATIONS: Array[String] = ["area_multiplier", "area_hit_more", "mana_multiplier"]
const MAX_RADIUS: float = 500.0
const SAVE_VERSION: int = 12
const SUPPORTS: Dictionary = {
	"breadth": {
		"name": "广域辅助",
		"description": "新星与陨星：面积 ×1.44（半径 ×1.20），命中伤害总降 15%，魔力 ×1.20；冷却不变。",
		"skills": ["nova", "meteor"], "requires": ["area_hit"],
		"operations": [
			{"op": "area_multiplier", "value": 1.44},
			{"op": "area_hit_more", "value": -0.15},
			{"op": "mana_multiplier", "value": 1.20},
		],
	},
}

static func get_definition(id: String) -> Dictionary:
	if not SUPPORTS.has(id) or not definition_error(SUPPORTS[id]).is_empty():
		return {}
	return SUPPORTS[id].duplicate(true)

static func compile_area(skill_id: Variant, recipe: Variant, support_ids: Variant) -> Dictionary:
	if not skill_id is String or not RECIPE_SKILLS.has(skill_id) or not Data.SKILLS.has(skill_id):
		return _failure("广域仅适配新星与陨星")
	if not recipe is Dictionary or recipe.size() != 1 or not recipe.has("radius") or not _number(recipe.radius) or float(recipe.radius) <= 0.0 or float(recipe.radius) > MAX_RADIUS:
		return _failure("范围配方无效或已经编译")
	if not support_ids is Array or support_ids.size() > Legacy.MAX_SUPPORTS:
		return _failure("辅助列表无效或超过两个槽位")
	var seen: Dictionary = {}
	for id: Variant in support_ids:
		if not id is String or not SUPPORTS.has(id):
			return _failure("此范围技能不支持所选辅助")
		if seen.has(id):
			return _failure("同一技能不能重复装配辅助")
		seen[id] = true
		var error: String = definition_error(SUPPORTS[id])
		if not error.is_empty():
			return _failure(error)
		if not SUPPORTS[id].skills.has(skill_id):
			return _failure("技能不支持此范围辅助")
	if not Data.SKILLS[skill_id].get("capabilities", []).has("area_hit"):
		return _failure("技能缺少范围命中能力")
	var canonical: Array = support_ids.duplicate()
	canonical.sort()
	var multiplier: float = 1.0
	var mana: float = 1.0
	var modifiers: Array[Dictionary] = []
	for id: String in canonical:
		for operation: Dictionary in SUPPORTS[id].operations:
			match operation.op:
				"area_multiplier": multiplier *= float(operation.value)
				"mana_multiplier": mana *= float(operation.value)
				"area_hit_more": modifiers.append({"id": "support:" + id, "mode": "more", "value": float(operation.value),
					"all_tags": ["hit", "spell", "area"], "skills": [skill_id], "damage_types": []})
	var radius: float = float(recipe.radius) * sqrt(multiplier)
	if not is_finite(radius) or radius > MAX_RADIUS or not is_finite(mana):
		return _failure("范围或魔力倍率超出边界")
	var result: Dictionary = recipe.duplicate(true)
	if not canonical.is_empty():
		result.radius = radius
		result.base_radius = float(recipe.radius)
		result.area_multiplier = multiplier
	return {"error": "", "recipe": result, "modifiers": modifiers, "mana_multiplier": mana}

static func definition_error(value: Variant) -> String:
	if not value is Dictionary or value.size() != 5 or not value.has_all(["name", "description", "skills", "requires", "operations"]):
		return "范围辅助元数据结构无效"
	if not value.name is String or value.name.is_empty() or not value.description is String or value.description.is_empty():
		return "范围辅助说明无效"
	if value.skills != RECIPE_SKILLS or value.requires != ["area_hit"]:
		return "范围辅助技能或能力无效"
	if not value.operations is Array or value.operations.size() != OPERATIONS.size():
		return "范围辅助操作列表无效"
	var seen: Dictionary = {}
	for operation: Variant in value.operations:
		if not operation is Dictionary or operation.size() != 2 or not operation.has_all(["op", "value"]):
			return "范围辅助操作结构无效"
		if not operation.op is String or not OPERATIONS.has(operation.op) or seen.has(operation.op) or not _number(operation.value):
			return "范围辅助操作重复、未知或数值无效"
		seen[operation.op] = true
		match operation.op:
			"area_multiplier":
				if float(operation.value) <= 1.0 or float(operation.value) > 4.0:
					return "面积倍率无效"
			"area_hit_more":
				if float(operation.value) <= -1.0 or float(operation.value) >= 0.0:
					return "范围命中代价无效"
			"mana_multiplier":
				if float(operation.value) < 1.0 or float(operation.value) > 10.0:
					return "魔力倍率无效"
	return ""

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _failure(error: String) -> Dictionary:
	return {"error": error, "recipe": {}, "modifiers": [], "mana_multiplier": 1.0}

## Shared circular hit geometry; target body extends the center-distance boundary.
## Spell-specific birth/death eligibility remains in main's settlement loop.
static func contains_target(origin: Vector2, target: Vector2, radius: float, target_radius: float) -> bool:
	return origin.is_finite() and target.is_finite() and is_finite(radius) and is_finite(target_radius) \
		and radius >= 0.0 and target_radius >= 0.0 and origin.distance_to(target) <= radius + target_radius
