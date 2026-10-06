class_name PhysicalFireConversionRules
extends RefCounted
## One bounded hit conversion, after all raw physical sources are assembled.
## The original base and assembly remain the authoritative pre-conversion trace.
const Base = preload("res://scripts/combat/damage_base_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const STAT: String = "physical_to_fire_conversion"
const FRACTION: float = Damage.CONVERSION_FRACTION


static func snapshot_error(snapshot: Dictionary) -> String:
	if not snapshot.has(STAT):
		return ""
	var value: Variant = snapshot[STAT]
	if not (value is int or value is float) or not is_finite(float(value)) or float(value) not in [0.0, FRACTION]:
		return "物理转火焰比例必须为有限数字零或40%"
	return ""


static func from_stats(stats: Dictionary) -> Dictionary:
	# Keep malformed source data for the compiler to reject, without aliasing it.
	if not snapshot_error(stats).is_empty():
		return {STAT: stats[STAT]}.duplicate(true)
	return {STAT: FRACTION} if float(stats.get(STAT, 0.0)) == FRACTION else {}


static func profile(fraction: Variant) -> Dictionary:
	if not snapshot_error({STAT: fraction}).is_empty() or float(fraction) == 0.0:
		return {}
	return {"enabled": true, "source_type": "physical", "target_type": "fire", "fraction": FRACTION}


static func apply(packet: Variant, fraction: Variant) -> Dictionary:
	if not snapshot_error({STAT: fraction}).is_empty() or not Base.packet_error(packet).is_empty():
		return {}
	# Applying a frozen stage again is not another conversion or a second hop.
	if packet.has("conversion"):
		return {}
	var result: Dictionary = packet.duplicate(true)
	var source_base: float = float(packet.base.get("physical", 0.0))
	if float(fraction) == 0.0 or source_base == 0.0:
		return result
	result.conversion = {"source_type": "physical", "target_type": "fire", "fraction": FRACTION,
		"source_base": source_base, "remaining_base": source_base * (1.0 - FRACTION),
		"converted_base": source_base * FRACTION}
	return result if Damage.conversion_error(result).is_empty() else {}
