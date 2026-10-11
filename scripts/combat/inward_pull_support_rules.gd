class_name InwardPullSupportRules
extends RefCounted
## Area spells reverse their impulse; cleave, frost and shade primary hits pull toward
## the retained cast origin. Reuses existing carriers and enemy movement.
const Program = preload("res://scripts/combat/support_program.gd")
const SAVE_VERSION: int = 43
const SKILLS: Array[String] = ["nova", "meteor", "cleave", "frost", "shade_bolt"]
const POLICY: Dictionary = {
	"impulse_speed": 190.0, "mana_multiplier": 1.20, "direction": "toward_origin",
}
const SUPPORTS: Dictionary = {"inward_pull": {
	"name": "牵引辅助",
	"description": "新星、陨星与裂刃成功命中后拉向本次技能中心；冰霜脉冲与蚀影飞弹成功命中后拉向发射时角色位置，替换原投射物向外冲量。初速190，沿原衰减、地形与分离规则。魔力×1.20，伤害、弹数、穿透、减速、范围与冷却不变。",
	"skills": SKILLS, "requires": [], "family": "inward_pull",
	"operations": [{"op": "mana_multiplier", "value": 1.20}],
}}


static func get_definition(id: Variant) -> Dictionary:
	return SUPPORTS[id].duplicate(true) if typeof(id) == TYPE_STRING and SUPPORTS.has(id) else {}


static func definition_error(value: Variant) -> String:
	return "" if value is Dictionary and value == SUPPORTS.inward_pull else "牵引辅助定义无效"


static func compile_program(skill_id: Variant, support_ids: Variant, slot_limit: int = 2) -> Dictionary:
	var reason: String = Program.selection_error(skill_id, support_ids, SUPPORTS, slot_limit)
	if not reason.is_empty(): return Program.failure(reason)
	var result: Dictionary = Program.empty()
	if support_ids.is_empty(): return result
	result.mana_multiplier = float(POLICY.mana_multiplier)
	return result


## The preview and frozen cast share one exact, enabled four-field contract.
## Check primitive types before examining values; arbitrary objects never run.
static func policy_error(value: Variant) -> String:
	if not value is Dictionary or value.size() != POLICY.size() + 1 or not value.has_all(["enabled", "impulse_speed", "mana_multiplier", "direction"]):
		return "牵引配置必须为已启用的固定策略"
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or (key != "enabled" and not POLICY.has(key)):
			return "牵引配置含未知字段"
	if typeof(value.enabled) != TYPE_BOOL or not value.enabled:
		return "牵引配置必须启用"
	if typeof(value.direction) != TYPE_STRING or value.direction != POLICY.direction:
		return "牵引配置方向无效"
	for key: String in ["impulse_speed", "mana_multiplier"]:
		if not Program.number(value[key]) or value[key] != POLICY[key]:
			return "牵引配置数值无效"
	return ""


static func profile_error(value: Variant) -> String:
	return policy_error(value)


## Same normalized magnitude as the old outward impulse, toward the actual
## blast origin. Zero-distance and malformed input return no impulse.
static func impulse(origin: Variant, target: Variant, policy: Variant) -> Vector2:
	if not policy_error(policy).is_empty() or typeof(origin) != TYPE_VECTOR2 or typeof(target) != TYPE_VECTOR2:
		return Vector2.ZERO
	if not origin.is_finite() or not target.is_finite(): return Vector2.ZERO
	var offset: Vector2 = origin - target
	if not offset.is_finite(): return Vector2.ZERO
	var result: Vector2 = offset.normalized() * float(policy.impulse_speed)
	return result if result.is_finite() else Vector2.ZERO
