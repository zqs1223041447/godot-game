extends RefCounted
## Pure rules for this game's attack-hit life/mana leech prototype.
## The caller owns player admission and runtime pools; no RNG or state lives here.
const STAT_KEYS: Array[String] = [
	"attack_life_leech", "attack_mana_leech",
	"physical_attack_life_leech", "physical_attack_mana_leech",
	"life_leech_rate_increased", "mana_leech_rate_increased",
	"life_leech_max_rate_increased", "mana_leech_max_rate_increased",
]
const AMOUNT_KEYS: Array[String] = [
	"attack_life_leech", "attack_mana_leech",
	"physical_attack_life_leech", "physical_attack_mana_leech",
]
const RESOURCE_KEYS: Array[String] = ["health", "mana"]
const PROFILE_KEYS: Array[String] = [
	"attack_fraction", "physical_attack_fraction", "instance_amount_cap",
	"instance_rate", "total_rate_cap",
]
const DAMAGE_TYPES: Array[String] = ["physical", "fire", "cold", "lightning", "chaos"]


static func profile(stats: Dictionary) -> Dictionary:
	var reason: String = _stats_error(stats)
	if not reason.is_empty():
		return _current({}, reason)
	var result: Dictionary = {}
	for resource: String in RESOURCE_KEYS:
		var scope: String = "life" if resource == "health" else "mana"
		var maximum: float = float(stats["max_" + resource])
		var amount_cap: float = 0.10 * maximum
		var instance_rate: float = 0.02 * maximum * (1.0 + float(stats.get(scope + "_leech_rate_increased", 0.0)))
		var total_rate: float = 0.20 * maximum * (1.0 + float(stats.get(scope + "_leech_max_rate_increased", 0.0)))
		if not is_finite(amount_cap) or not is_finite(instance_rate) or not is_finite(total_rate):
			return _current({}, "Leech profile arithmetic overflow")
		if amount_cap <= 0.0 or instance_rate <= 0.0 or total_rate <= 0.0:
			return _current({}, "Leech profile rate and capacity must remain positive")
		result[resource] = {
			"attack_fraction": float(stats.get("attack_" + scope + "_leech", 0.0)),
			"physical_attack_fraction": float(stats.get("physical_attack_" + scope + "_leech", 0.0)),
			"instance_amount_cap": amount_cap, "instance_rate": instance_rate,
			"total_rate_cap": total_rate,
		}
	return _current(result)


static func from_stats(stats: Dictionary) -> Dictionary:
	var include: bool = false
	for key: String in STAT_KEYS:
		var value: Variant = stats.get(key, 0.0)
		if not _amount(value) or (key in AMOUNT_KEYS and float(value) > 0.0):
			include = true
	for key: String in ["max_health", "max_mana"]:
		if stats.has(key) and (not _amount(stats[key]) or float(stats[key]) <= 0.0):
			include = true
	# A valid rate-only source must not create a snapshot field. Preserve an
	# invalid derived profile, however, so compilation cannot wash out overflow.
	if stats.has_all(["max_health", "max_mana"]) and not profile(stats).ok:
		include = true
	if not include:
		return {}
	var result: Dictionary = {"max_health": stats.get("max_health"), "max_mana": stats.get("max_mana")}
	for key: String in STAT_KEYS:
		result[key] = stats.get(key, 0.0)
	return result.duplicate(true)


static func error(snapshot: Dictionary) -> String:
	if not snapshot.has("leech_modifiers"):
		return ""
	var raw: Variant = snapshot.leech_modifiers
	if not raw is Dictionary or raw.is_empty():
		return "Leech modifiers must be a nonempty dictionary"
	for key: Variant in raw:
		if not key is String or (key not in STAT_KEYS and key not in ["max_health", "max_mana"]):
			return "Unknown or non-string leech modifier field"
	return str(profile(raw).reason)


static func compile(snapshot: Dictionary, primary_tags: Array) -> Dictionary:
	var reason: String = error(snapshot)
	if reason.is_empty():
		reason = _tags_error(primary_tags)
	if not reason.is_empty():
		return _compiled({}, reason)
	if not snapshot.has("leech_modifiers") or not _attack_hit(primary_tags):
		return _compiled({})
	var current: Dictionary = profile(snapshot.leech_modifiers)
	var leech: Dictionary = {"health": current.health, "mana": current.mana}
	for resource: String in RESOURCE_KEYS:
		if float(leech[resource].attack_fraction) > 0.0 or float(leech[resource].physical_attack_fraction) > 0.0:
			return _compiled(leech)
	return _compiled({})


static func profile_error(value: Dictionary) -> String:
	if not _exact_keys(value, RESOURCE_KEYS):
		return "Leech profile must contain exactly health and mana"
	for resource: String in RESOURCE_KEYS:
		var fields: Variant = value[resource]
		if not fields is Dictionary or not _exact_keys(fields, PROFILE_KEYS):
			return "Leech resource profile must contain exactly the five resolved fields"
		for key: String in PROFILE_KEYS:
			if not _amount(fields[key]):
				return "Leech resource profile values must be finite nonnegative numbers"
		for key: String in ["instance_amount_cap", "instance_rate", "total_rate_cap"]:
			if float(fields[key]) <= 0.0:
				return "Leech resource profile rate and capacity must be positive"
	return ""


static func plan_hit(leech: Dictionary, packet: Dictionary, settlement: Dictionary) -> Dictionary:
	var reason: String = profile_error(leech)
	if reason.is_empty():
		reason = _tags_error(packet.get("tags"))
	if reason.is_empty():
		reason = _settlement_error(settlement)
	if not reason.is_empty():
		return _plan({}, reason)
	var amounts: Dictionary = {}
	var actual: float = float(settlement.shield_spent) + float(settlement.health_lost)
	var total: float = float(settlement.damage_total)
	var physical_applied: float = 0.0
	if total > 0.0:
		physical_applied = actual * (float(settlement.components.get("physical", 0.0)) / total)
	if not is_finite(physical_applied):
		return _plan({}, "Applied physical damage overflow")
	for resource: String in RESOURCE_KEYS:
		var fields: Dictionary = leech[resource]
		var amount: float = 0.0
		if _attack_hit(packet.tags):
			var attack_amount: float = actual * float(fields.attack_fraction)
			var physical_amount: float = physical_applied * float(fields.physical_attack_fraction)
			var uncapped: float = attack_amount + physical_amount
			# Validate before minf: a cap must never conceal an arithmetic overflow.
			if not is_finite(attack_amount) or not is_finite(physical_amount) or not is_finite(uncapped):
				return _plan({}, "Leech amount arithmetic overflow")
			amount = minf(float(fields.instance_amount_cap), uncapped)
		amounts[resource] = {"amount": amount, "rate": float(fields.instance_rate)}
	return _plan(amounts)


static func _stats_error(stats: Dictionary) -> String:
	for key: String in ["max_health", "max_mana"]:
		if not _amount(stats.get(key)) or float(stats[key]) <= 0.0:
			return "Maximum health and mana must be finite positive numbers"
	for key: String in STAT_KEYS:
		if not _amount(stats.get(key, 0.0)):
			return "Leech stats must be finite nonnegative numbers: " + key
	return ""


static func _settlement_error(settlement: Dictionary) -> String:
	if settlement.has("ok") and (not settlement.ok is bool or not settlement.ok):
		return "Leech requires a successful damage settlement"
	for key: String in ["damage_total", "shield_spent", "health_lost", "overkill"]:
		if not _amount(settlement.get(key)):
			return "Damage settlement values must be finite nonnegative numbers"
	var components: Variant = settlement.get("components")
	if not components is Dictionary:
		return "Damage settlement components must be a dictionary"
	var sum: float = 0.0
	for key: Variant in components:
		if not key is String or key not in DAMAGE_TYPES or not _amount(components[key]):
			return "Invalid resolved damage component"
	# Sum in a fixed order, independent of the caller's dictionary order.
	for type: String in DAMAGE_TYPES:
		sum += float(components.get(type, 0.0))
		if not is_finite(sum):
			return "Resolved damage component total overflow"
	var total: float = float(settlement.damage_total)
	if not _same_amount(sum, total):
		return "Damage total does not match resolved components"
	var actual: float = float(settlement.shield_spent) + float(settlement.health_lost)
	var accounted: float = actual + float(settlement.overkill)
	if not is_finite(actual) or not is_finite(accounted):
		return "Damage settlement arithmetic overflow"
	if actual > total and not _same_amount(actual, total):
		return "Actual damage exceeds resolved total"
	if not _same_amount(accounted, total):
		return "Actual damage and overkill do not match resolved total"
	return ""


static func _tags_error(value: Variant) -> String:
	if not value is Array:
		return "Damage tags must be an array"
	for tag: Variant in value:
		if not tag is String:
			return "Damage tags must be strings"
	return ""


static func _attack_hit(tags: Array) -> bool:
	return tags.has("attack") and tags.has("hit")


static func _exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in value:
		if not key is String or key not in expected:
			return false
	return true


static func _same_amount(left: float, right: float) -> bool:
	# Allow only roundoff from the existing resolved/settlement arithmetic.
	return left == right or absf(left - right) <= maxf(absf(left), absf(right)) * 1.0e-12


static func _amount(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


static func _current(leech: Dictionary, reason: String = "") -> Dictionary:
	return {"ok": reason.is_empty(), "reason": reason, "health": leech.get("health", {}), "mana": leech.get("mana", {})}


static func _compiled(leech: Dictionary, reason: String = "") -> Dictionary:
	return {"ok": reason.is_empty(), "error": reason, "leech": leech}


static func _plan(amounts: Dictionary, reason: String = "") -> Dictionary:
	return {"ok": reason.is_empty(), "reason": reason,
		"health": amounts.get("health", {"amount": 0.0, "rate": 0.0}),
		"mana": amounts.get("mana", {"amount": 0.0, "rate": 0.0})}
