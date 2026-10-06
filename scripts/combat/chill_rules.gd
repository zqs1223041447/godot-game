class_name ChillRules
extends RefCounted
## Enemy chill is admission-only: it never changes the authoritative Defense
## receipt, damage total, or combat log. The caller admits only an actual
## avoidable frost-guard hit whose target is still alive after settlement.
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const ENEMY_POLICY: Dictionary = {"duration": 1.2, "movement_speed_reduced": 0.25}
const POLICY_KEYS: Array[String] = ["duration", "movement_speed_reduced"]


static func policy_error(policy: Variant) -> String:
	if not policy is Dictionary or policy.size() != POLICY_KEYS.size():
		return "Chill policy must have the exact frozen enemy shape"
	for key: Variant in policy:
		if typeof(key) != TYPE_STRING or key not in POLICY_KEYS:
			return "Unknown or non-String chill policy field"
		if not _nonnegative_number(policy[key]) or float(policy[key]) != float(ENEMY_POLICY[key]):
			return "Chill policy must match the frozen enemy budget"
	return ""


## Attribute only damage actually spent from shield, optional mana, and life.
## Components are the authoritative post-defense shares; overkill is excluded
## because it spent none of these pools. Unrelated receipt metadata is opaque.
static func actual_cold_loss(receipt: Variant) -> Dictionary:
	if not receipt is Dictionary or typeof(receipt.get("ok")) != TYPE_BOOL or not receipt.ok:
		return _failure("Chill requires a successful Defense receipt")
	var checked: Dictionary = Defense.validate_components(receipt.get("components"))
	if not checked.ok:
		return _failure(str(checked.reason))
	for field: String in ["damage_total", "shield_spent", "health_lost"]:
		if not _nonnegative_number(receipt.get(field)):
			return _failure("Chill receipt needs a finite nonnegative " + field)
	var mana: Variant = receipt.get("mana_spent", 0.0)
	if not _nonnegative_number(mana):
		return _failure("Chill receipt mana_spent must be finite and nonnegative")
	var total: float = float(receipt.damage_total)
	if not _same_amount(total, float(checked.total)):
		return _failure("Chill receipt damage_total does not match its components")
	var spent: float = float(receipt.shield_spent) + float(mana) + float(receipt.health_lost)
	if not is_finite(spent) or (spent > total and not _same_amount(spent, total)):
		return _failure("Chill receipt actual resource loss exceeds its damage total")
	var cold: float = float(checked.components.get("cold", 0.0))
	# A zero total must be exactly empty damage, not a tolerance-sized nonzero
	# component or loss hidden by the Defense consistency comparison.
	if total == 0.0:
		if float(checked.total) != 0.0 or spent != 0.0:
			return _failure("Zero-damage chill receipt cannot contain damage or loss")
		return {"ok": true, "reason": "", "actual_cold": 0.0}
	if cold == 0.0 or spent == 0.0:
		return {"ok": true, "reason": "", "actual_cold": 0.0}
	# Divide before multiplying to avoid overflow on large valid receipts. Clamp
	# only rounding-level pool excess already admitted by the consistency check.
	var actual: float = cold * (minf(spent, total) / total)
	return {"ok": true, "reason": "", "actual_cold": actual}


static func _nonnegative_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


static func _same_amount(first: float, second: float) -> bool:
	return absf(first - second) <= maxf(0.000001, maxf(absf(first), absf(second)) * 0.000000001)


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "actual_cold": 0.0}
