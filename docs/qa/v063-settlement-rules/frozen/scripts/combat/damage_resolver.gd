extends RefCounted
## A damage event has its own delivery tags. Skill or carrier tags never leak in.
## Values remain unrounded until UI display; all increased values add per component.

const TYPES: Array[String] = ["physical", "fire", "cold", "lightning", "chaos"]
const ELEMENTS: Array[String] = ["fire", "cold", "lightning"]

static func resolve(packet: Dictionary, modifiers: Array, mitigation: Dictionary = {}, critical_multiplier: float = 1.0) -> Dictionary:
	if not is_finite(critical_multiplier) or critical_multiplier < 1.0 or critical_multiplier > 1000000.0:
		return {"total":0.0,"components":{},"details":[],"error":"Invalid critical multiplier"}
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
		var amount: float = before_defense * (1.0 - resistance)
		components[type] = amount
		total += amount
		details.append({"type": type, "base": base, "increased": increased, "more": more,
			"before_defense": before_defense, "resistance": resistance, "final": amount, "modifiers": applied})
	return {"total": total, "components": components, "details": details}


static func matches(modifier: Dictionary, packet: Dictionary, type: String) -> bool:
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
