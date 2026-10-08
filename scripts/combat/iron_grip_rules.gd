class_name IronGripRules
extends RefCounted
## The pinned Strength benefit stays 1% per five final Strength. Its native
## melee contribution remains in melee_physical_increased; only this independent
## source is extended, never equipment or other melee INC. Absence is inert.
const STAT := "iron_grip"


static func strength_increased(strength: float) -> float:
	return floorf(strength / 5.0) * 0.01


static func from_stats(stats: Dictionary) -> Dictionary:
	if not stats.has(STAT): return {}
	var flag: Variant = stats[STAT]
	if not _number(flag) or float(flag) not in [0.0, 1.0]:
		return {STAT:{"invalid_source_flag":flag}}.duplicate(true)
	if float(flag) == 0.0: return {}
	var strength: Variant = stats.get("strength")
	return {STAT:{"strength":strength,
		"strength_physical_increased":strength_increased(float(strength)) if _number(strength) else null}}


static func snapshot_error(snapshot: Dictionary) -> String:
	if not snapshot.has(STAT): return ""
	var source: Variant = snapshot[STAT]
	if not source is Dictionary or source.size() != 2 or not source.has_all(["strength", "strength_physical_increased"]):
		return "铁握持快照必须恰含最终力量及其原生物理伤害提高"
	if not _number(source.strength) or float(source.strength) < 0.0 or float(source.strength) != roundf(float(source.strength)):
		return "铁握持需要有效的最终整数力量"
	if not _number(source.strength_physical_increased) or float(source.strength_physical_increased) != strength_increased(float(source.strength)):
		return "铁握持只能扩展力量自身的原生伤害加成"
	return ""


static func projectile_modifier(snapshot: Dictionary) -> Dictionary:
	if not snapshot.has(STAT) or not snapshot_error(snapshot).is_empty(): return {}
	var increased: float = float(snapshot[STAT].strength_physical_increased)
	if is_zero_approx(increased): return {}
	# A hybrid melee/projectile hit already gets the native melee source once.
	# Physical ancestry is handled by the same conversion resolver as native INC.
	return {"id":"iron_grip_strength_physical_increased","mode":"increased","value":increased,
		"all_tags":["attack","projectile"],"excluded_tags":["melee"],"skills":[],"damage_types":["physical"]}


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
