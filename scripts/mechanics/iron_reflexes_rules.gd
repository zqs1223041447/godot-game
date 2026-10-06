class_name IronReflexesRules
extends RefCounted
## Convert raw evasion, excluding Dexterity's evasion increase. The same source
## modifier that affects both ratings counts once on the converted portion.
## Independent armour/evasion modifiers both apply. No RNG or resource changes.


static func profile(base_armour: float, base_evasion: float, armour_increased: float,
		evasion_increased: float, shared_increased: float) -> Dictionary:
	for value: float in [base_armour, base_evasion, armour_increased, evasion_increased, shared_increased]:
		if not is_finite(value) or value < 0.0:
			return {"ok": false, "reason": "Defence conversion inputs must be finite and nonnegative"}
	if shared_increased > minf(armour_increased, evasion_increased):
		return {"ok": false, "reason": "Shared increases must belong to both rating totals"}
	var converted := base_evasion * (1.0 + armour_increased + evasion_increased - shared_increased)
	var armour := base_armour * (1.0 + armour_increased) + converted
	if not is_finite(converted) or not is_finite(armour):
		return {"ok": false, "reason": "Defence conversion overflow"}
	return {"ok": true, "reason": "", "armour": armour, "evasion": 0.0, "converted_armour": converted}
