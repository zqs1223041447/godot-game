class_name EncirclingCleaveSupportRules
extends RefCounted
## One existing direct cleave becomes a full circle; no new hit or carrier.
const Program = preload("res://scripts/combat/support_program.gd")
const SAVE_VERSION: int = 52
const SKILLS: Array[String] = ["cleave"]
const POLICY: Dictionary = {
	"enabled": true, "arc_degrees": 360.0, "base_arc_degrees": 180.0,
	"hit_multiplier": 0.75, "mana_multiplier": 1.25,
}
const SUPPORTS: Dictionary = {"encircling_cleave": {
	"name": "环斩辅助",
	"description": "仅辅助裂刃斩：180°前方半圆改为360°整圆，半径仍由范围加成决定；主命中伤害×0.75，魔力消耗×1.25，冷却不变。每个目标仍只结算一次，占用1个辅助槽。",
	"skills": SKILLS, "requires": [], "family": "encircling_cleave",
	"operations": [{"op": "primary_hit_more", "value": -0.25}, {"op": "mana_multiplier", "value": 1.25}],
}}


static func get_definition(id: Variant) -> Dictionary:
	return SUPPORTS[id].duplicate(true) if typeof(id) == TYPE_STRING and SUPPORTS.has(id) else {}


static func definition_error(value: Variant) -> String:
	return "" if value is Dictionary and value == SUPPORTS.encircling_cleave else "环斩辅助定义无效"


static func compile_program(skill_id: Variant, support_ids: Variant, slot_limit: int = Program.MAX_SUPPORTS) -> Dictionary:
	var reason: String = Program.selection_error(skill_id, support_ids, SUPPORTS, slot_limit)
	if not reason.is_empty(): return Program.failure(reason)
	var result: Dictionary = Program.empty()
	if support_ids.is_empty(): return result
	result.modifiers.append(Program.primary_modifier("encircling_cleave", skill_id, float(POLICY.hit_multiplier) - 1.0))
	result.mana_multiplier = float(POLICY.mana_multiplier)
	return result
