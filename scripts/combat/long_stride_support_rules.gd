class_name LongStrideSupportRules
extends RefCounted
## More requested travel in exchange for this dash's own protection grant.
## Existing protection is untouched; geometry owns the actual reached position.
const Program = preload("res://scripts/combat/support_program.gd")
const SAVE_VERSION: int = 53
const SKILLS: Array[String] = ["dash"]
const POLICY: Dictionary = {
	"enabled":true, "requested_distance":280.0, "base_distance":175.0,
	"immunity_grant":0.0, "base_immunity_grant":0.6, "mana_multiplier":1.20,
}
const SUPPORTS: Dictionary = {"long_stride": {
	"name":"长跃辅助",
	"description":"仅辅助冲刺：请求距离由175提高到280，实际距离仍受墙体与边界限制；本次冲刺不再授予保护，已有保护不受影响。魔力消耗×1.20，冷却不变，占用1个辅助槽。",
	"skills":SKILLS, "requires":[], "family":"long_stride",
	"operations":[{"op":"mana_multiplier", "value":1.20}],
}}

static func get_definition(id: Variant) -> Dictionary:
	return SUPPORTS[id].duplicate(true) if typeof(id)==TYPE_STRING and SUPPORTS.has(id) else {}

static func definition_error(value: Variant) -> String:
	return "" if value is Dictionary and value==SUPPORTS.long_stride else "长跃辅助定义无效"

static func profile_error(value: Variant) -> String:
	if not value is Dictionary or value.size()!=POLICY.size(): return "长跃辅助配置无效"
	for key: Variant in value:
		if typeof(key)!=TYPE_STRING or not POLICY.has(key) or typeof(value[key])!=typeof(POLICY[key]) or value[key]!=POLICY[key]:
			return "长跃辅助配置无效"
	return ""

static func compile_program(skill_id: Variant, support_ids: Variant, slot_limit: int = Program.MAX_SUPPORTS) -> Dictionary:
	var reason: String = Program.selection_error(skill_id,support_ids,SUPPORTS,slot_limit)
	if not reason.is_empty(): return Program.failure(reason)
	var result: Dictionary = Program.empty()
	if not support_ids.is_empty(): result.mana_multiplier=float(POLICY.mana_multiplier)
	return result
