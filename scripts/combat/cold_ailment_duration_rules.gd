class_name ColdAilmentDurationRules
extends RefCounted
## Current cold-ailment budget comes only from source node 14209. Callers select
## cold effects; this rule never turns a generic slow into a cold ailment.
const STAT: String = "cold_ailment_duration_increased"
const MAX_INCREASED: float = 0.20


static func snapshot_error(snapshot: Dictionary) -> String:
	if not snapshot.has(STAT):
		return ""
	var value: Variant = snapshot[STAT]
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) \
			or float(value) < 0.0 or float(value) > MAX_INCREASED:
		return "Cold ailment duration increase must be a finite number from zero through the current 20% budget"
	return ""


static func from_stats(stats: Dictionary) -> Dictionary:
	if not stats.has(STAT):
		return {}
	# Preserve malformed source values for atomic rejection at compilation.
	# A malformed nested value must never alias the caller's stats dictionary.
	if not snapshot_error(stats).is_empty():
		return {STAT: stats[STAT]}.duplicate(true)
	var increased: float = float(stats[STAT])
	return {} if increased == 0.0 else {STAT: increased}


static func duration(base: Variant, increased: Variant) -> Dictionary:
	var reason: String = snapshot_error({STAT: increased})
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	if typeof(base) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(base)) or float(base) < 0.0:
		return {"ok": false, "reason": "Cold ailment base duration must be finite and nonnegative"}
	var result: float = float(base) if float(increased) == 0.0 else float(base) * (1.0 + float(increased))
	if not is_finite(result):
		return {"ok": false, "reason": "Cold ailment duration exceeds the finite duration budget"}
	return {"ok": true, "reason": "", "duration": result}
