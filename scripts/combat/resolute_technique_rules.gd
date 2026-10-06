class_name ResoluteTechniqueRules
extends RefCounted
## One indivisible keystone flag. Never infer it from separately equipped effects.
## Compilation retains validated potential critical multipliers, but sets every
## hit profile's chance to zero; a roll therefore always returns multiplier 1.
const STAT: String = "resolute_technique"
const POLICY: Dictionary = {
	"id": "resolute_technique",
	"hits_cannot_be_evaded": true,
	"cannot_deal_critical_strikes": true,
}


static func snapshot_error(snapshot: Dictionary) -> String:
	if not snapshot.has(STAT):
		return ""
	var value: Variant = snapshot[STAT]
	if not (value is int or value is float) or not is_finite(float(value)) or float(value) not in [0.0, 1.0]:
		return "坚决技艺开关必须为有限数字零或一"
	return ""


static func active(snapshot: Dictionary) -> bool:
	return snapshot_error(snapshot).is_empty() and snapshot.has(STAT) and float(snapshot[STAT]) == 1.0


static func from_stats(stats: Dictionary) -> Dictionary:
	# Preserve invalid source values for compiler rejection; absence and zero
	# produce no new field, keeping the legacy snapshot byte-for-byte intact.
	if not snapshot_error(stats).is_empty():
		return {STAT: stats[STAT]}.duplicate(true)
	return {STAT: 1.0} if active(stats) else {}


static func compiled_profile(snapshot: Dictionary) -> Dictionary:
	return POLICY.duplicate(true) if active(snapshot) else {}
