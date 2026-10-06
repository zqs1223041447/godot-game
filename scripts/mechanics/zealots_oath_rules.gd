class_name ZealotsOathRules
extends RefCounted
## This game's explicit regeneration conversion: flat Life regeneration keeps
## its point rate, percentage regeneration uses final maximum Energy Shield.
## Neither the precomputed Life rate nor recharge/flask/leech enters this rule.


static func profile(flat_regeneration: float, life_fraction: float, maximum_shield: float) -> Dictionary:
	for value: float in [flat_regeneration, life_fraction, maximum_shield]:
		if not is_finite(value) or value < 0.0:
			return {"ok": false, "reason": "Regeneration inputs must be finite and nonnegative"}
	var rate := flat_regeneration + life_fraction * maximum_shield
	if not is_finite(rate):
		return {"ok": false, "reason": "Regeneration redirection overflow"}
	return {"ok": true, "reason": "", "life_rate": 0.0, "shield_rate": rate}
