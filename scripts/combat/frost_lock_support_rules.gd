class_name FrostLockSupportRules
extends RefCounted
## Frost Lock uses the existing frost projectile carrier and one support slot.
const Program = preload("res://scripts/combat/support_program.gd")
const FrostLock = preload("res://scripts/combat/frost_lock_rules.gd")
const SAVE_VERSION: int = 47
const SKILLS: Array[String] = ["frost"]
const SUPPORTS: Dictionary = {"frost_lock": {
	"name": "霜锁辅助",
	"description": "仅辅助冰霜脉冲：主命中伤害×0.75，魔力消耗×1.20。正值冰霜命中冻结普通与魔法敌人0.60秒、稀有敌人0.35秒、首领0.20秒；结束后免疫冻结1.50秒。保留原有3秒减速，与寒意延长辅助互斥，占用1个辅助槽。",
	"skills": SKILLS, "requires": [], "family": "frost_lock",
	"operations": [{"op": "primary_hit_more", "value": -0.25}, {"op": "mana_multiplier", "value": 1.20}],
}}


static func get_definition(id: Variant) -> Dictionary:
	return SUPPORTS[id].duplicate(true) if typeof(id) == TYPE_STRING and SUPPORTS.has(id) else {}


static func definition_error(value: Variant) -> String:
	return "" if value is Dictionary and value == SUPPORTS.frost_lock else "霜锁辅助定义无效"


static func compile_program(skill_id: Variant, support_ids: Variant, slot_limit: int = 2) -> Dictionary:
	var reason: String = Program.selection_error(skill_id, support_ids, SUPPORTS, slot_limit)
	if not reason.is_empty(): return Program.failure(reason)
	var result: Dictionary = Program.empty()
	if support_ids.is_empty(): return result
	result.modifiers.append(Program.primary_modifier("frost_lock", skill_id, float(FrostLock.PLAYER_POLICY.hit_multiplier) - 1.0))
	result.mana_multiplier = float(FrostLock.PLAYER_POLICY.mana_multiplier)
	return result
