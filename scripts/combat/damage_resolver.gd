class_name DamageResolver
extends RefCounted
## A damage event has its own delivery tags. Skill or carrier tags never leak in.
## Values remain unrounded until UI display; all increased values add per component.

const Penetration = preload("res://scripts/combat/hit_penetration_rules.gd")
const TYPES: Array[String] = ["physical", "fire", "cold", "lightning", "chaos"]
const ELEMENTS: Array[String] = ["fire", "cold", "lightning"]
const CONVERSION_FRACTION: float = 0.4

static func resolve(packet: Dictionary, modifiers: Array, mitigation: Dictionary = {}, critical_multiplier: float = 1.0) -> Dictionary:
	if not is_finite(critical_multiplier) or critical_multiplier < 1.0 or critical_multiplier > 1000000.0:
		return {"total":0.0,"components":{},"details":[],"error":"Invalid critical multiplier"}
	if packet.has("conversion"):
		return _resolve_converted(packet, modifiers, mitigation, critical_multiplier)
	if packet.has("penetration"):
		var penetration_reason: String = Penetration.packet_error(packet)
		if not penetration_reason.is_empty():
			return _conversion_failure(penetration_reason)
	var components: Dictionary = {}
	var details: Array[Dictionary] = []
	var total: float = 0.0
	for type: String in TYPES:
		var base: float = maxf(0.0, float(packet.get("base", {}).get(type, 0.0)))
		if base <= 0.0:
			continue
		var increased: float = 0.0
		var more: float = 1.0
		var applied: Array[String] = []
		for modifier: Dictionary in modifiers:
			if not matches(modifier, packet, type):
				continue
			var amount: float = float(modifier.get("value", 0.0))
			if not is_finite(amount):
				continue
			if modifier.get("mode", "") == "increased":
				increased += amount
			elif modifier.get("mode", "") == "more":
				more *= maxf(0.0, 1.0 + amount)
			else:
				continue
			applied.append(str(modifier.get("id", "anonymous")))
		var before_defense: float = base * maxf(0.0, 1.0 + increased) * more
		# Apply to the completed hit before resistance and hit-size-dependent armour.
		# Keep the old arithmetic path exactly when no critical is active.
		if critical_multiplier != 1.0: before_defense *= critical_multiplier
		var resistance: float = clampf(float(mitigation.get(type, 0.0)), -1.0, 0.9)
		var effective_resistance: float = resistance
		var penetration: float = float(packet.get("penetration", {}).get(type, 0.0))
		if penetration > 0.0:
			resistance = maxf(Penetration.MINIMUM_RESISTANCE, resistance - penetration)
		var amount: float = before_defense * (1.0 - resistance)
		components[type] = amount
		total += amount
		details.append({"type": type, "base": base, "increased": increased, "more": more,
			"before_defense": before_defense, "resistance": resistance, "final": amount, "modifiers": applied})
		if penetration > 0.0:
			details[-1].effective_resistance = effective_resistance
			details[-1].penetration = penetration
	return {"total": total, "components": components, "details": details}


## Single authority for the optional frozen split, shared by admission and use.
## Validate exact derived floats; a merely conserved or approximately equal
## total is insufficient provenance for a different conversion fraction.
static func conversion_error(packet: Dictionary) -> String:
	if packet.get("conversion") is Dictionary and packet.conversion.has("version") and not packet.conversion.has("target_type"):
		return _conversion_v2_error(packet)
	var trace: Variant = packet.get("conversion")
	var keys: Array[String] = ["source_type", "target_type", "fraction", "source_base", "remaining_base", "converted_base"]
	if not trace is Dictionary or trace.size() != keys.size() or not trace.has_all(keys):
		return "Invalid physical-to-fire conversion structure"
	for key: Variant in trace:
		if not key is String:
			return "Invalid physical-to-fire conversion key"
	if not trace.source_type is String or trace.source_type != "physical" or not trace.target_type is String or trace.target_type != "fire":
		return "Unsupported damage conversion path"
	for key: String in ["fraction", "source_base", "remaining_base", "converted_base"]:
		if not _conversion_amount(trace[key]):
			return "Invalid physical-to-fire conversion amount"
	if float(trace.fraction) != CONVERSION_FRACTION or float(trace.source_base) <= 0.0:
		return "Unsupported physical-to-fire conversion fraction or source"
	if not packet.get("base") is Dictionary:
		return "Invalid pre-conversion base"
	var raw_total: float = 0.0
	for type: Variant in packet.base:
		if not type is String or not TYPES.has(type) or not _conversion_amount(packet.base[type]):
			return "Invalid pre-conversion base"
		raw_total += float(packet.base[type])
		if not is_finite(raw_total):
			return "Pre-conversion base overflow"
	var source_base: float = float(packet.base.get("physical", 0.0))
	if float(trace.source_base) != source_base or float(trace.remaining_base) != source_base * (1.0 - CONVERSION_FRACTION) or float(trace.converted_base) != source_base * CONVERSION_FRACTION:
		return "Conversion does not match its pre-conversion base"
	if not packet.get("tags") is Array or not packet.tags.has("hit") or packet.tags.has("dot"):
		return "Only hit damage can be converted"
	return ""


## One expression and iteration order for both construction and strict admission.
## The normalized remainder is explicitly zero, not 1 - summed rounded ratios.
static func conversion_split(requested: Dictionary) -> Dictionary:
	var requested_total: float = 0.0
	for type: String in ELEMENTS:
		if requested.has(type):
			requested_total += float(requested[type])
	var normalized: bool = requested_total > 1.0
	var effective: Dictionary = {}
	for type: String in ELEMENTS:
		if requested.has(type):
			effective[type] = float(requested[type]) / requested_total if normalized else float(requested[type])
	return {"effective": effective, "physical_fraction": 0.0 if normalized else 1.0 - requested_total,
		"normalized": normalized}


static func _conversion_v2_error(packet: Dictionary) -> String:
	var trace: Dictionary = packet.conversion
	var keys: Array[String] = ["version", "source_type", "source_base", "requested", "effective", "remaining_base", "converted_base"]
	if trace.size() != keys.size() or not trace.has_all(keys):
		return "Invalid elemental conversion structure"
	for key: Variant in trace:
		if not key is String:
			return "Invalid elemental conversion key"
	if not trace.version is int or trace.version != 2 or not trace.source_type is String or trace.source_type != "physical":
		return "Unsupported elemental conversion version or source"
	if not _conversion_amount(trace.source_base) or float(trace.source_base) <= 0.0 or not _conversion_amount(trace.remaining_base):
		return "Invalid elemental conversion amount"
	if not trace.requested is Dictionary or trace.requested.is_empty() or not trace.effective is Dictionary or not trace.converted_base is Dictionary:
		return "Invalid elemental conversion maps"
	if not trace.requested.has("cold") and not trace.requested.has("lightning"):
		return "Fire-only conversion must retain its original descriptor"
	if trace.effective.size() != trace.requested.size() or trace.converted_base.size() != trace.requested.size():
		return "Elemental conversion map keys disagree"
	for values: Dictionary in [trace.effective, trace.converted_base]:
		for type: Variant in values:
			if not type is String or not trace.requested.has(type):
				return "Elemental conversion map keys disagree"
	for type: Variant in trace.requested:
		if not type is String or not ELEMENTS.has(type) or not _conversion_amount(trace.requested[type]) or float(trace.requested[type]) != CONVERSION_FRACTION:
			return "Unsupported elemental conversion request"
		if not trace.effective.has(type) or not trace.converted_base.has(type) or not _conversion_amount(trace.effective[type]) or not _conversion_amount(trace.converted_base[type]):
			return "Invalid elemental conversion map value"
	if not packet.get("base") is Dictionary:
		return "Invalid pre-conversion base"
	var raw_total: float = 0.0
	for type: Variant in packet.base:
		if not type is String or not TYPES.has(type) or not _conversion_amount(packet.base[type]):
			return "Invalid pre-conversion base"
		raw_total += float(packet.base[type])
		if not is_finite(raw_total):
			return "Pre-conversion base overflow"
	var source_base: float = float(packet.base.get("physical", 0.0))
	var split: Dictionary = conversion_split(trace.requested)
	if float(trace.source_base) != source_base or float(trace.remaining_base) != source_base * float(split.physical_fraction):
		return "Conversion does not match its pre-conversion base"
	var conserved: float = float(trace.remaining_base)
	for type: String in ELEMENTS:
		if not trace.requested.has(type):
			continue
		# No approximate comparison here: even one forged representable step is
		# invalid. Conservation slack below only checks recomputed arithmetic.
		if float(trace.effective[type]) != float(split.effective[type]) or float(trace.converted_base[type]) != source_base * float(split.effective[type]):
			return "Conversion does not match its requested fractions"
		conserved += float(trace.converted_base[type])
	# At most four nonnegative terms are summed. Permit only four source ULPs
	# for multiplication/addition rounding, never a relative gameplay tolerance.
	if not is_finite(conserved) or absf(conserved - source_base) > 4.0 * _positive_ulp(source_base):
		return "Elemental conversion does not conserve its source"
	if not packet.get("tags") is Array or not packet.tags.has("hit") or packet.tags.has("dot"):
		return "Only hit damage can be converted"
	return ""


static func _positive_ulp(value: float) -> float:
	var encoded: PackedByteArray = PackedByteArray()
	encoded.resize(8)
	encoded.encode_double(0, value)
	var exponent: int = (encoded.decode_u64(0) >> 52) & 0x7ff
	return pow(2.0, -1074.0) if exponent == 0 else pow(2.0, float(exponent - 1023 - 52))


static func _resolve_converted(packet: Dictionary, modifiers: Array, mitigation: Dictionary, critical_multiplier: float) -> Dictionary:
	var reason: String = conversion_error(packet)
	if not reason.is_empty():
		return _conversion_failure(reason)
	if packet.has("penetration"):
		var penetration_reason: String = Penetration.packet_error(packet)
		if not penetration_reason.is_empty():
			return _conversion_failure(penetration_reason)
	var components: Dictionary = {}
	var details: Array[Dictionary] = []
	var total: float = 0.0
	for type: String in TYPES:
		var parts: Array[Dictionary] = []
		var native_base: float = float(packet.conversion.remaining_base) if type == "physical" else float(packet.base.get(type, 0.0))
		if native_base > 0.0:
			var lineage: Array[String] = [type]
			var native: Dictionary = _conversion_part(native_base, lineage, packet, modifiers, critical_multiplier)
			if native.is_empty():
				return _conversion_failure("Converted damage overflow or invalid modifier")
			parts.append(native)
		# Native damage precedes its converted part, preserving modifier scopes.
		var converted_base: float = 0.0
		if packet.conversion.get("version") == 2:
			converted_base = float(packet.conversion.converted_base.get(type, 0.0))
		elif type == "fire":
			converted_base = float(packet.conversion.converted_base)
		if converted_base > 0.0:
			var lineage: Array[String] = ["physical", type]
			var converted: Dictionary = _conversion_part(converted_base, lineage, packet, modifiers, critical_multiplier)
			if converted.is_empty():
				return _conversion_failure("Converted damage overflow or invalid modifier")
			parts.append(converted)
		if parts.is_empty():
			continue
		var before_defense: float = 0.0
		for part: Dictionary in parts:
			before_defense += float(part.before_defense)
		if not is_finite(before_defense):
			return _conversion_failure("Converted component overflow")
		var raw_resistance: Variant = mitigation.get(type, 0.0)
		if not (raw_resistance is int or raw_resistance is float) or not is_finite(float(raw_resistance)):
			return _conversion_failure("Invalid converted damage resistance")
		var resistance: float = clampf(float(raw_resistance), -1.0, 0.9)
		var effective_resistance: float = resistance
		var penetration: float = float(packet.get("penetration", {}).get(type, 0.0))
		if penetration > 0.0:
			resistance = maxf(Penetration.MINIMUM_RESISTANCE, resistance - penetration)
		var amount: float = before_defense * (1.0 - resistance)
		if not is_finite(amount):
			return _conversion_failure("Converted damage resistance overflow")
		components[type] = amount
		total += amount
		if not is_finite(total):
			return _conversion_failure("Converted damage total overflow")
		# Exactly one detail per final type keeps downstream defense settlement
		# authoritative. There is no meaningful aggregate increased/more value.
		details.append({"type": type, "before_defense": before_defense, "resistance": resistance,
			"final": amount, "parts": parts})
		if penetration > 0.0:
			details[-1].effective_resistance = effective_resistance
			details[-1].penetration = penetration
	return {"total": total, "components": components, "details": details}


static func _conversion_part(base: float, lineage: Array[String], packet: Dictionary, modifiers: Array, critical_multiplier: float) -> Dictionary:
	var increased: float = 0.0
	var more: float = 1.0
	var applied: Array[String] = []
	var indices: Array[int] = []
	for index: int in range(modifiers.size()):
		var modifier: Variant = modifiers[index]
		if not modifier is Dictionary:
			return {}
		for field: String in ["all_tags", "excluded_tags", "skills", "damage_types"]:
			var scope: Variant = modifier.get(field, [])
			if not scope is Array:
				return {}
			for entry: Variant in scope:
				if not entry is String or (field == "damage_types" and not TYPES.has(entry)):
					return {}
		if not _matches_lineage(modifier, packet, lineage):
			continue
		var amount: Variant = modifier.get("value", 0.0)
		if not (amount is int or amount is float) or not is_finite(float(amount)):
			continue
		if modifier.get("mode", "") == "increased":
			increased += float(amount)
		elif modifier.get("mode", "") == "more":
			more *= maxf(0.0, 1.0 + float(amount))
		else:
			continue
		if not is_finite(increased) or not is_finite(more):
			return {}
		# Array-entry identity, never id identity: separate support clauses may
		# intentionally share an id and must both apply to the converted piece.
		applied.append(str(modifier.get("id", "anonymous")))
		indices.append(index)
	var before_defense: float = base * maxf(0.0, 1.0 + increased) * more
	if critical_multiplier != 1.0:
		before_defense *= critical_multiplier
	if not is_finite(before_defense):
		return {}
	return {"lineage": lineage.duplicate(), "base": base, "increased": increased, "more": more,
		"before_defense": before_defense, "modifiers": applied, "modifier_indices": indices}


static func _matches_lineage(modifier: Dictionary, packet: Dictionary, lineage: Array[String]) -> bool:
	for tag: String in modifier.get("excluded_tags", []):
		if packet.tags.has(tag): return false
	for tag: String in modifier.get("all_tags", []):
		if not packet.tags.has(tag):
			return false
	var skills: Array = modifier.get("skills", [])
	if not skills.is_empty() and not skills.has(packet.get("skill_id", "")):
		return false
	var allowed: Array = modifier.get("damage_types", [])
	if allowed.is_empty():
		return true
	for type: String in lineage:
		if allowed.has(type):
			return true
	return false


static func _conversion_amount(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0


static func _conversion_failure(reason: String) -> Dictionary:
	return {"total": 0.0, "components": {}, "details": [], "error": reason}


static func matches(modifier: Dictionary, packet: Dictionary, type: String) -> bool:
	for tag: String in modifier.get("excluded_tags", []):
		if packet.get("tags", []).has(tag): return false
	var allowed: Array = modifier.get("damage_types", [])
	if not allowed.is_empty() and not allowed.has(type):
		return false
	for tag: String in modifier.get("all_tags", []):
		if not packet.get("tags", []).has(tag):
			return false
	var skills: Array = modifier.get("skills", [])
	return skills.is_empty() or skills.has(packet.get("skill_id", ""))


static func packet(base: Dictionary, tags: Array, skill_id: String) -> Dictionary:
	return {"base": base.duplicate(true), "tags": tags.duplicate(), "skill_id": skill_id}
