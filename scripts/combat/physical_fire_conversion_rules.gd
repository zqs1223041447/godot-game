class_name PhysicalFireConversionRules
extends RefCounted
## Bounded hit conversion, after all raw physical sources are assembled.
## The original base and assembly remain the authoritative pre-conversion trace.
const Base = preload("res://scripts/combat/damage_base_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const STAT: String = "physical_to_fire_conversion"
const FRACTION: float = Damage.CONVERSION_FRACTION
const STATS: Dictionary = {"fire": STAT, "cold": "physical_to_cold_conversion", "lightning": "physical_to_lightning_conversion"}


static func snapshot_error(snapshot: Dictionary) -> String:
	for type: String in Damage.ELEMENTS:
		var field: String = STATS[type]
		if not snapshot.has(field):
			continue
		var value: Variant = snapshot[field]
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) not in [0.0, FRACTION]:
			return "物理转火焰比例必须为有限数字零或40%" if type == "fire" else "物理转元素比例必须为有限数字零或40%：" + type
	return ""


static func from_stats(stats: Dictionary) -> Dictionary:
	# Keep malformed source data for the compiler to reject, without aliasing it.
	var result: Dictionary = {}
	var invalid: bool = not snapshot_error(stats).is_empty()
	for type: String in Damage.ELEMENTS:
		var field: String = STATS[type]
		if stats.has(field) and (invalid or float(stats[field]) == FRACTION):
			result[field] = stats[field] if invalid else FRACTION
	return result.duplicate(true)


static func profile_from_snapshot(snapshot: Dictionary) -> Dictionary:
	if not snapshot_error(snapshot).is_empty():
		return {}
	var requested: Dictionary = {}
	for type: String in Damage.ELEMENTS:
		if float(snapshot.get(STATS[type], 0.0)) == FRACTION:
			requested[type] = FRACTION
	if requested.is_empty():
		return {}
	if requested.size() == 1 and requested.has("fire"):
		return profile(FRACTION)
	var split: Dictionary = Damage.conversion_split(requested)
	return {"enabled": true, "source_type": "physical", "version": 2,
		"requested": requested, "effective": split.effective,
		"physical_fraction": split.physical_fraction, "normalized": split.normalized}


static func apply_snapshot(packet: Variant, snapshot: Dictionary) -> Dictionary:
	if not snapshot_error(snapshot).is_empty():
		return {}
	var conversion_profile: Dictionary = profile_from_snapshot(snapshot)
	if not conversion_profile.is_empty() and not conversion_profile.has("version"):
		return apply(packet, FRACTION)
	if not Base.packet_error(packet).is_empty() or packet.has("conversion"):
		return {}
	if conversion_profile.is_empty():
		return packet.duplicate(true)
	var result: Dictionary = packet.duplicate(true)
	var source_base: float = float(packet.base.get("physical", 0.0))
	if source_base == 0.0:
		return result
	var converted: Dictionary = {}
	for type: String in Damage.ELEMENTS:
		if conversion_profile.effective.has(type):
			converted[type] = source_base * float(conversion_profile.effective[type])
	result.conversion = {"version": 2, "source_type": "physical", "source_base": source_base,
		"requested": conversion_profile.requested.duplicate(true), "effective": conversion_profile.effective.duplicate(true),
		"remaining_base": source_base * float(conversion_profile.physical_fraction), "converted_base": converted}
	return result if Damage.conversion_error(result).is_empty() else {}


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
