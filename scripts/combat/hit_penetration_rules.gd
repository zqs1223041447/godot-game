class_name HitPenetrationRules
extends RefCounted
## One authority for optional hit-only penetration. No Base preload: Base and
## Damage both validate this stage, and attach loads Base only when called.
const STAT_FIELDS: Dictionary = {"cold": "cold_penetration", "lightning": "lightning_penetration"}
const FRACTION: float = 0.06
const MINIMUM_RESISTANCE: float = -1.0
const SNAPSHOT_FIELD: String = "hit_penetration"


static func from_stats(stats: Dictionary) -> Dictionary:
	var fractions: Dictionary = {}
	for type: String in STAT_FIELDS:
		var field: String = STAT_FIELDS[type]
		if not stats.has(field):
			continue
		var value: Variant = stats[field]
		# Do not coerce invalid values; the frozen snapshot must reject them.
		if not _number(value) or float(value) != 0.0:
			fractions[type] = value
	return {SNAPSHOT_FIELD: fractions}.duplicate(true) if not fractions.is_empty() else {}


static func snapshot_error(snapshot: Dictionary) -> String:
	return fractions_error(snapshot[SNAPSHOT_FIELD]) if snapshot.has(SNAPSHOT_FIELD) else ""


static func fractions_error(fractions: Variant) -> String:
	if not fractions is Dictionary or fractions.is_empty():
		return "命中穿透必须为非空元素表"
	for type: Variant in fractions:
		if not type is String or not STAT_FIELDS.has(type):
			return "命中穿透只支持冰冷与闪电"
		if not _number(fractions[type]) or float(fractions[type]) != FRACTION:
			return "命中穿透比例必须为有限数字6%"
	return ""


static func profile_from_snapshot(snapshot: Dictionary) -> Dictionary:
	if not snapshot_error(snapshot).is_empty() or not snapshot.has(SNAPSHOT_FIELD):
		return {}
	var fractions: Dictionary = {}
	for type: String in STAT_FIELDS:
		if snapshot[SNAPSHOT_FIELD].has(type):
			fractions[type] = FRACTION
	return {"enabled": true, "fractions": fractions, "minimum_resistance": MINIMUM_RESISTANCE}


static func packet_error(packet: Dictionary) -> String:
	if not packet.has("penetration"):
		return ""
	var reason: String = fractions_error(packet.penetration)
	if not reason.is_empty():
		return reason
	if not packet.get("tags") is Array or not packet.tags.has("hit") or packet.tags.has("dot"):
		return "只有真实命中可以穿透抗性"
	return ""


static func attach(packet: Variant, snapshot: Dictionary) -> Dictionary:
	if not snapshot_error(snapshot).is_empty():
		return {}
	var base_rules: Script = load("res://scripts/combat/damage_base_compiler.gd")
	if not base_rules.packet_error(packet).is_empty():
		return {}
	var profile: Dictionary = profile_from_snapshot(snapshot)
	var result: Dictionary = packet.duplicate(true)
	if profile.is_empty():
		return result
	if packet.has("penetration"):
		return {}
	var applicable: Dictionary = {}
	for type: String in STAT_FIELDS:
		if not profile.fractions.has(type):
			continue
		var converted_base: float = 0.0
		if packet.has("conversion") and packet.conversion.get("version") == 2:
			converted_base = float(packet.conversion.converted_base.get(type, 0.0))
		if float(packet.base.get(type, 0.0)) > 0.0 or converted_base > 0.0:
			applicable[type] = FRACTION
	if applicable.is_empty():
		return result
	result.penetration = applicable
	return result if packet_error(result).is_empty() else {}


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
