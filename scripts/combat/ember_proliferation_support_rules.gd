class_name EmberProliferationSupportRules
extends RefCounted
## A distinct burning trade-off. Only primary hits pay the damage penalty.
const Program = preload("res://scripts/combat/support_program.gd")
const SAVE_VERSION: int = 29
const POLICY: Dictionary = {
	"duration": 3.0, "rate_fraction": 0.20,
	"hit_multiplier": 0.75, "mana_multiplier": 1.30,
}
const SKILLS: Array[String] = ["meteor", "tornado"]
const SUPPORTS: Dictionary = {"ember_proliferation": {
	"name": "余烬扩散辅助",
	"description": "主命中伤害 ×0.75，魔力消耗 ×1.30。火焰命中附燃3秒，每秒按该次防御前火焰伤害的20%；燃烧目标死亡时向120范围内最多8个目标扩散，保留剩余时长，最多一跳。与点燃辅助互斥，仅适配陨星与龙卷。",
	"skills": SKILLS, "requires": [], "family": "burning",
	"operations": [{"op": "primary_hit_more", "value": -0.25}, {"op": "mana_multiplier", "value": 1.30}],
}}


static func get_definition(id: Variant) -> Dictionary:
	return SUPPORTS[id].duplicate(true) if typeof(id) == TYPE_STRING and SUPPORTS.has(id) else {}


static func definition_error(value: Variant) -> String:
	return "" if value is Dictionary and value == SUPPORTS.ember_proliferation else "余烬扩散辅助定义无效"


static func compile_program(skill_id: Variant, support_ids: Variant, slot_limit: int = 2) -> Dictionary:
	var reason: String = Program.selection_error(skill_id, support_ids, SUPPORTS, slot_limit)
	if not reason.is_empty(): return Program.failure(reason)
	var result: Dictionary = Program.empty()
	if support_ids.is_empty(): return result
	result.modifiers.append(Program.primary_modifier("ember_proliferation", skill_id, float(POLICY.hit_multiplier) - 1.0))
	result.mana_multiplier = float(POLICY.mana_multiplier)
	return result
