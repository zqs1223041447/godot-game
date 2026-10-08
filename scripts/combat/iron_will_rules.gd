class_name IronWillRules
extends RefCounted
## The pinned wording says ALL Spell Damage. Extend only the native Strength
## amount, with no physical restriction and no transfer of the melee INC bucket.
const StrengthBenefit = preload("res://scripts/combat/iron_grip_rules.gd")
const STAT := "iron_will"


static func from_stats(stats: Dictionary) -> Dictionary:
	if not stats.has(STAT): return {}
	var flag: Variant = stats[STAT]
	if not _number(flag) or float(flag) not in [0.0, 1.0]:
		return {STAT:{"invalid_source_flag":flag}}.duplicate(true)
	if float(flag) == 0.0: return {}
	var strength: Variant = stats.get("strength")
	return {STAT:{"strength":strength,
		"strength_increased":StrengthBenefit.strength_increased(float(strength)) if _number(strength) else null}}


static func snapshot_error(snapshot: Dictionary) -> String:
	if not snapshot.has(STAT): return ""
	var source: Variant = snapshot[STAT]
	if not source is Dictionary or source.size() != 2 or not source.has_all(["strength","strength_increased"]):
		return "铁意志快照必须恰含最终力量及其原生伤害提高"
	if not _number(source.strength) or float(source.strength) < 0.0 or float(source.strength) != roundf(float(source.strength)):
		return "铁意志需要有效的最终整数力量"
	if not _number(source.strength_increased) or float(source.strength_increased) != StrengthBenefit.strength_increased(float(source.strength)):
		return "铁意志只能扩展力量自身的原生伤害加成"
	return ""


static func spell_modifier(snapshot: Dictionary) -> Dictionary:
	if not snapshot.has(STAT) or not snapshot_error(snapshot).is_empty(): return {}
	var increased: float = float(snapshot[STAT].strength_increased)
	if is_zero_approx(increased): return {}
	# One array entry applies once to each native/added/converted spell portion.
	# Independent secondary explosions have no spell tag and inherit no eligibility.
	return {"id":"iron_will_strength_increased","mode":"increased","value":increased,
		"all_tags":["spell"],"skills":[],"damage_types":[]}


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
