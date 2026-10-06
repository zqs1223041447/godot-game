class_name PreciseTechniqueRules
extends RefCounted
## Accuracy and maximum life are already final when the cast is captured.
## The strict comparison gates attack damage only; the critical ban is unconditional.
const STAT: String = "precise_technique"
const ATTACK_MORE: float = 0.4


static func from_stats(stats: Dictionary) -> Dictionary:
	if not stats.has(STAT):
		return {}
	var flag: Variant = stats[STAT]
	if not _number(flag) or float(flag) not in [0.0, 1.0]:
		# A malformed flag that happens to look like a valid context must not
		# become enabled. Preserve it inside a deliberately invalid context.
		return {STAT: {"invalid_source_flag": flag}}.duplicate(true)
	if float(flag) == 0.0:
		return {}
	var accuracy: Variant = stats.get("accuracy")
	var max_health: Variant = stats.get("max_health")
	return {STAT: {
		"accuracy": float(accuracy) if _number(accuracy) else accuracy,
		"max_health": float(max_health) if _number(max_health) else max_health,
	}}.duplicate(true)


static func snapshot_error(snapshot: Dictionary) -> String:
	if not snapshot.has(STAT):
		return ""
	var context: Variant = snapshot[STAT]
	if not context is Dictionary or context.size() != 2 or not context.has_all(["accuracy", "max_health"]):
		return "精准技艺快照必须恰含最终命中值与最大生命"
	for key: Variant in context:
		if not key is String or key not in ["accuracy", "max_health"] or not _number(context[key]):
			return "精准技艺快照字段与数值必须有效且有限"
	if float(context.accuracy) < 0.0 or float(context.max_health) <= 0.0:
		return "精准技艺需要非负命中值与正数最大生命"
	return ""


static func active(snapshot: Dictionary) -> bool:
	return snapshot.has(STAT) and snapshot_error(snapshot).is_empty()


static func profile(snapshot: Dictionary) -> Dictionary:
	if not active(snapshot):
		return {}
	var context: Dictionary = snapshot[STAT]
	var condition_met: bool = float(context.accuracy) > float(context.max_health)
	return {"enabled": true, "accuracy": float(context.accuracy), "max_health": float(context.max_health),
		"condition_met": condition_met, "attack_more": ATTACK_MORE if condition_met else 0.0,
		"cannot_deal_critical_strikes": true}


static func attack_modifier(snapshot: Dictionary) -> Dictionary:
	var policy: Dictionary = profile(snapshot)
	if policy.is_empty() or not policy.condition_met:
		return {}
	return {"id": "precise_technique_attack_more", "mode": "more", "value": ATTACK_MORE,
		"all_tags": ["hit", "attack"], "skills": [], "damage_types": []}


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
