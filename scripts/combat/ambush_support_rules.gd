class_name AmbushSupportRules
extends RefCounted
## Explicit delivery conversion for two existing spell/area hits. Damage keeps
## its original tags; this support does not enable unimplemented trap stats.
const Program = preload("res://scripts/combat/support_program.gd")
const SAVE_VERSION: int = 42
const SKILLS: Array[String] = ["nova", "meteor"]
const POLICY: Dictionary = {
	"arming_seconds": 0.35, "trigger_radius": 70.0, "lifetime_seconds": 12.0,
	"maximum_traps": 3, "hit_multiplier": 0.85, "mana_multiplier": 1.25,
}
const SUPPORTS: Dictionary = {"ambush": {
	"name": "符印伏击辅助",
	"description": "奥能新星与陨星坠落改为在脚下放置陷阱：0.35秒后布防，70范围内有活敌时触发原范围命中，12秒后消失。所有技能组共享最多3个；命中伤害×0.85，魔力×1.25，冷却不变。保留法术、范围与命中标签；陷阱专属天赋仍未实装。",
	"skills": SKILLS, "requires": [], "family": "ambush",
	"operations": [{"op": "primary_hit_more", "value": -0.15}, {"op": "mana_multiplier", "value": 1.25}],
}}


static func get_definition(id: Variant) -> Dictionary:
	return SUPPORTS[id].duplicate(true) if typeof(id) == TYPE_STRING and SUPPORTS.has(id) else {}


static func definition_error(value: Variant) -> String:
	return "" if value is Dictionary and value == SUPPORTS.ambush else "伏击辅助定义无效"


static func compile_program(skill_id: Variant, support_ids: Variant, slot_limit: int = 2) -> Dictionary:
	var reason: String = Program.selection_error(skill_id, support_ids, SUPPORTS, slot_limit)
	if not reason.is_empty(): return Program.failure(reason)
	var result: Dictionary = Program.empty()
	if support_ids.is_empty(): return result
	result.modifiers.append(Program.primary_modifier("ambush", skill_id, -0.15))
	result.mana_multiplier = float(POLICY.mana_multiplier)
	return result


## Compiler/runtime boundary is an exact policy, never a tuning input.
static func profile_error(value: Variant) -> String:
	if not value is Dictionary or value.size() != POLICY.size() + 1 or not value.has("enabled") or typeof(value.enabled) != TYPE_BOOL or not value.enabled:
		return "伏击配置必须为已启用的固定策略"
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or (key != "enabled" and not POLICY.has(key)):
			return "伏击配置含未知字段"
	for key: String in POLICY:
		if not value.has(key) or not Program.number(value[key]) or value[key] != POLICY[key]:
			return "伏击配置数值无效"
	if typeof(value.maximum_traps) != TYPE_INT:
		return "伏击数量上限必须为整数"
	return ""
