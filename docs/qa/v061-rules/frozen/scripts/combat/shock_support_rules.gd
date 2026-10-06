extends RefCounted
## Explicit support admission for native lightning primary hits only.
const Program = preload("res://docs/qa/v061-rules/frozen/scripts/combat/support_program.gd")
const Shock = preload("res://docs/qa/v061-rules/frozen/scripts/combat/shock_rules.gd")
const SAVE_VERSION: int = 31
const SKILLS: Array[String] = ["bolt", "nova", "chain"]
const SUPPORTS: Dictionary = {"shock": {
	"name": "感电辅助",
	"description": "主命中伤害 ×0.80，魔力消耗 ×1.20。命中实际造成正值闪电伤害后使目标感电2秒，后续受到的命中伤害提高15%；不影响持续伤害，同强刷新，不叠加。仅适配奥术飞弹、奥能新星与连锁闪电。",
	"skills": SKILLS, "requires": [], "family": "shock",
	"operations": [{"op": "primary_hit_more", "value": -0.20}, {"op": "mana_multiplier", "value": 1.20}],
}}


static func get_definition(id: Variant) -> Dictionary:
	return SUPPORTS[id].duplicate(true) if typeof(id) == TYPE_STRING and SUPPORTS.has(id) else {}


static func definition_error(value: Variant) -> String:
	return "" if value is Dictionary and value == SUPPORTS.shock else "感电辅助定义无效"


static func compile_program(skill_id: Variant, support_ids: Variant, slot_limit: int = 2) -> Dictionary:
	var reason: String = Program.selection_error(skill_id, support_ids, SUPPORTS, slot_limit)
	if not reason.is_empty(): return Program.failure(reason)
	var result: Dictionary = Program.empty()
	if support_ids.is_empty(): return result
	result.modifiers.append(Program.primary_modifier("shock", skill_id, float(Shock.PLAYER_POLICY.hit_multiplier) - 1.0))
	result.mana_multiplier = float(Shock.PLAYER_POLICY.mana_multiplier)
	return result
