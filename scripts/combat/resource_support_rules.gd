class_name ResourceSupportRules
extends RefCounted
## Pure cost/cooldown programs. Effects never enter damage or carrier recipes.
const Program = preload("res://scripts/combat/support_program.gd")
## Deliberately fixed: adding a future active skill requires explicit admission.
const SKILL_IDS: Array[String] = ["tornado", "bolt", "frost", "nova", "dash", "ward", "meteor", "chain", "cleave", "shade_bolt"]
const OPERATIONS: Array[String] = ["mana_multiplier", "cooldown_multiplier"]
const MAX_MULTIPLIER: float = 10.0
const SUPPORTS: Dictionary = {
	"efficiency": {
		"name": "节能辅助",
		"description": "魔力消耗 ×0.80，冷却时间 ×1.15；技能伤害与其他效果不变。",
		"skills": SKILL_IDS, "requires": [], "family": "resource",
		"operations": [
			{"op": "mana_multiplier", "value": 0.80},
			{"op": "cooldown_multiplier", "value": 1.15},
		],
	},
	"quickcast": {
		"name": "疾咏辅助",
		"description": "魔力消耗 ×1.40，冷却时间 ×0.80；技能伤害与其他效果不变。",
		"skills": SKILL_IDS, "requires": [], "family": "resource",
		"operations": [
			{"op": "mana_multiplier", "value": 1.40},
			{"op": "cooldown_multiplier", "value": 0.80},
		],
	},
}


static func get_definition(id: Variant) -> Dictionary:
	if not id is String or not SUPPORTS.has(id) or not definition_error(SUPPORTS[id]).is_empty():
		return {}
	return SUPPORTS[id].duplicate(true)


## Validate the whole selection before producing any effect, then sort a copy.
## Failure has the same five fields as success, with neutral multipliers.
static func compile_program(skill_id: Variant, support_ids: Variant, slot_limit: int = Program.MAX_SUPPORTS) -> Dictionary:
	if not skill_id is String or not SKILL_IDS.has(skill_id):
		return Program.failure("资源辅助仅适配已声明的主动技能")
	var error: String = Program.selection_error(skill_id, support_ids, SUPPORTS, slot_limit)
	if not error.is_empty():
		return Program.failure(error)
	for id: String in support_ids:
		error = definition_error(SUPPORTS[id])
		if not error.is_empty():
			return Program.failure(error)
	var canonical: Array = support_ids.duplicate()
	canonical.sort()
	var result: Dictionary = Program.empty()
	for id: String in canonical:
		for operation: Dictionary in SUPPORTS[id].operations:
			result[operation.op] *= float(operation.value)
	if not Program.number(result.mana_multiplier) or not Program.number(result.cooldown_multiplier):
		return Program.failure("资源倍率超出有限数值边界")
	return result


## Detached definitions can be validated without modifying the constant catalog.
## Only two bounded, opposed resource factors are admitted; other effects fail.
static func definition_error(value: Variant) -> String:
	if not value is Dictionary or value.size() != 6 or not value.has_all(["name", "description", "skills", "requires", "operations", "family"]):
		return "资源辅助元数据结构无效"
	if not value.name is String or value.name.is_empty() or not value.description is String or value.description.is_empty():
		return "资源辅助说明无效"
	if not value.family is String or value.family != "resource":
		return "资源辅助分类无效"
	if not Program.strings(value.skills) or value.skills != SKILL_IDS or not value.requires is Array or not value.requires.is_empty():
		return "资源辅助技能或能力无效"
	if not value.operations is Array or value.operations.size() != OPERATIONS.size():
		return "资源辅助操作列表无效"
	var factors: Dictionary = {}
	for operation: Variant in value.operations:
		if not operation is Dictionary or operation.size() != 2 or not operation.has_all(["op", "value"]):
			return "资源辅助操作结构无效"
		if not operation.op is String or not OPERATIONS.has(operation.op) or factors.has(operation.op) or not Program.number(operation.value):
			return "资源辅助操作重复、未知或数值无效"
		var factor: float = float(operation.value)
		if factor <= 0.0 or factor > MAX_MULTIPLIER:
			return "资源倍率必须大于零且不超过十倍"
		factors[operation.op] = factor
	if (float(factors.mana_multiplier) - 1.0) * (float(factors.cooldown_multiplier) - 1.0) >= 0.0:
		return "魔力消耗与冷却时间必须有相反取舍"
	return ""
