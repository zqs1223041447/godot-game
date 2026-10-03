class_name ElementSupportRules
extends RefCounted
## Native components determine eligibility; equipment never opens new support slots.
## Modifiers apply after raw assembly, including added points and local weapon points.
const Program = preload("res://scripts/combat/support_program.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const NATIVE_SKILLS: Dictionary = {
	"physical": ["tornado"], "fire": ["tornado", "meteor"],
	"cold": ["frost"], "lightning": ["bolt", "nova", "chain"],
}
const OPERATIONS: Array[String] = ["primary_component_more", "other_components_more", "mana_multiplier"]
const SUPPORTS: Dictionary = {
	"physical_focus": {
		"name": "物理专注辅助",
		"description": "龙卷主命中：物理伤害总增 20%，其他类型伤害总降 20%；魔力 ×1.15，冷却不变。普攻与独立爆炸不变。",
		"skills": ["tornado"], "requires": [], "family": "element",
		"operations": [
			{"op": "primary_component_more", "damage_type": "physical", "value": 0.20},
			{"op": "other_components_more", "damage_type": "physical", "value": -0.20},
			{"op": "mana_multiplier", "value": 1.15},
		],
	},
	"fire_focus": {
		"name": "火焰专注辅助",
		"description": "龙卷与陨星主命中：火焰伤害总增 20%，其他类型伤害总降 20%；魔力 ×1.15，冷却不变。普攻与独立爆炸不变。",
		"skills": ["tornado", "meteor"], "requires": [], "family": "element",
		"operations": [
			{"op": "primary_component_more", "damage_type": "fire", "value": 0.20},
			{"op": "other_components_more", "damage_type": "fire", "value": -0.20},
			{"op": "mana_multiplier", "value": 1.15},
		],
	},
	"cold_focus": {
		"name": "冰霜专注辅助",
		"description": "冰霜主命中：冰霜伤害总增 20%，其他类型伤害总降 20%；魔力 ×1.15，冷却不变。普攻与独立爆炸不变。",
		"skills": ["frost"], "requires": [], "family": "element",
		"operations": [
			{"op": "primary_component_more", "damage_type": "cold", "value": 0.20},
			{"op": "other_components_more", "damage_type": "cold", "value": -0.20},
			{"op": "mana_multiplier", "value": 1.15},
		],
	},
	"lightning_focus": {
		"name": "闪电专注辅助",
		"description": "飞弹、新星与连锁闪电主命中：闪电伤害总增 20%，其他类型伤害总降 20%；魔力 ×1.15，冷却不变。普攻与独立爆炸不变。",
		"skills": ["bolt", "nova", "chain"], "requires": [], "family": "element",
		"operations": [
			{"op": "primary_component_more", "damage_type": "lightning", "value": 0.20},
			{"op": "other_components_more", "damage_type": "lightning", "value": -0.20},
			{"op": "mana_multiplier", "value": 1.15},
		],
	},
}


static func get_definition(id: String) -> Dictionary:
	if not SUPPORTS.has(id) or not definition_error(SUPPORTS[id]).is_empty():
		return {}
	return SUPPORTS[id].duplicate(true)


static func compile_program(skill_id: Variant, support_ids: Variant) -> Dictionary:
	var error: String = Program.selection_error(skill_id, support_ids, SUPPORTS)
	if not error.is_empty():
		return Program.failure(error)
	# Validate the complete selection before generating any effects.
	for id: String in support_ids:
		error = definition_error(SUPPORTS[id])
		if not error.is_empty():
			return Program.failure(error)
	var result: Dictionary = Program.empty()
	var canonical: Array = support_ids.duplicate()
	canonical.sort()
	for id: String in canonical:
		for operation: Dictionary in SUPPORTS[id].operations:
			if operation.op == "mana_multiplier":
				result.mana_multiplier *= float(operation.value)
				continue
			var types: Array = [operation.damage_type]
			if operation.op == "other_components_more":
				types = Damage.TYPES.duplicate()
				types.erase(operation.damage_type)
			var modifier: Dictionary = Program.primary_modifier(id, skill_id, float(operation.value), types)
			if modifier.is_empty():
				return Program.failure("专注辅助主命中作用域无效")
			result.modifiers.append(modifier)
	if not Program.number(result.mana_multiplier):
		return Program.failure("专注辅助魔力倍率无效")
	return result


## Detached metadata can be validated without mutating the catalog.
static func definition_error(value: Variant) -> String:
	if not value is Dictionary or value.size() != 6 or not value.has_all(["name", "description", "skills", "requires", "operations", "family"]):
		return "专注辅助元数据结构无效"
	if not value.name is String or value.name.is_empty() or not value.description is String or value.description.is_empty():
		return "专注辅助说明无效"
	if not value.family is String or value.family != "element" or not Program.strings(value.requires) or not value.requires.is_empty():
		return "专注辅助分类或能力无效"
	if not Program.strings(value.skills) or value.skills.is_empty():
		return "专注辅助技能无效"
	if not value.operations is Array or value.operations.size() != OPERATIONS.size():
		return "专注辅助操作列表无效"
	var seen: Dictionary = {}
	var selected_type: String = ""
	var other_type: String = ""
	for operation: Variant in value.operations:
		if not operation is Dictionary or not operation.has_all(["op", "value"]):
			return "专注辅助操作结构无效"
		if not operation.op is String or not OPERATIONS.has(operation.op) or seen.has(operation.op) or not Program.number(operation.value):
			return "专注辅助操作未知、重复或数值无效"
		seen[operation.op] = true
		if operation.op == "mana_multiplier":
			if operation.size() != 2 or float(operation.value) != 1.15:
				return "专注辅助魔力倍率无效"
			continue
		if operation.size() != 3 or not operation.get("damage_type") is String or not NATIVE_SKILLS.has(operation.damage_type):
			return "专注辅助伤害类型无效"
		if operation.op == "primary_component_more":
			if float(operation.value) != 0.20:
				return "专注辅助同类伤害倍率无效"
			selected_type = operation.damage_type
		else:
			if float(operation.value) != -0.20:
				return "专注辅助其他伤害倍率无效"
			other_type = operation.damage_type
	if selected_type.is_empty() or selected_type != other_type or value.skills != NATIVE_SKILLS[selected_type]:
		return "专注辅助类型与原生技能不匹配"
	return ""
