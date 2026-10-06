extends RefCounted
## Frozen prototype policies. A positive actual lightning hit attaches shock
## after settlement; only later hits benefit, and damage over time never does.
const EmberClock = preload("res://docs/qa/v061-rules/frozen/scripts/combat/ember_event_clock.gd")
const MIN_POLICY_DURATION: float = 1.0
const PLAYER_POLICY: Dictionary = {
	"duration": 2.0, "hit_damage_taken_increased": 0.15,
	"hit_multiplier": 0.80, "mana_multiplier": 1.20,
}
const ENEMY_POLICY: Dictionary = {
	"duration": 1.0, "hit_damage_taken_increased": 0.15,
}
const POLICY_KEYS: Array[String] = [
	"duration", "hit_damage_taken_increased", "hit_multiplier", "mana_multiplier",
]


static func policy_error(policy: Variant) -> String:
	if not policy is Dictionary:
		return "Shock policy must be a dictionary"
	for key: Variant in policy:
		if typeof(key) != TYPE_STRING or key not in POLICY_KEYS:
			return "Unknown or non-String shock policy field"
		if not positive_number(policy[key]):
			return "Shock policy values must be finite positive numbers"
	if not _matches_frozen_policy(policy, PLAYER_POLICY) and not _matches_frozen_policy(policy, ENEMY_POLICY):
		return "Shock policy must match the frozen player or enemy prototype"
	return ""


static func _matches_frozen_policy(policy: Dictionary, frozen: Dictionary) -> bool:
	if policy.size() != frozen.size(): return false
	for key: String in frozen:
		if not policy.has(key) or float(policy[key]) != float(frozen[key]): return false
	return true


static func from_lightning_hit(actual_lightning: Variant, policy: Variant) -> Dictionary:
	var reason: String = policy_error(policy)
	if reason.is_empty() and not positive_number(actual_lightning):
		reason = "Actual lightning hit must be a finite positive number"
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "duration": 0.0, "hit_damage_taken_increased": 0.0}
	return {"ok": true, "reason": "", "duration": float(policy.duration),
		"hit_damage_taken_increased": float(policy.hit_damage_taken_increased)}


static func positive_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0


## Validate the complete original batch before the caller settles any hit.
## Reuse the established adjacent raw-offset tie policy without reordering or
## rewriting events. Absolute elapsed time never supplies approximate equality.
static func projectile_batch_error(events: Variant, step_start: Variant,
		step_end: Variant, read_floor: Variant, original_delta: Variant = null) -> String:
	for value: Variant in [step_start, step_end, read_floor]:
		if not _nonnegative_number(value): return "Shock batch window times must be finite and nonnegative"
	if typeof(original_delta) != TYPE_NIL and not _nonnegative_number(original_delta):
		return "Shock original step delta must be finite and nonnegative"
	var start: float = float(step_start)
	var end: float = float(step_end)
	var floor_time: float = float(read_floor)
	if end < start: return "Shock batch window cannot end before it starts"
	var prepared: Dictionary = EmberClock.offsets(events)
	if not prepared.ok: return str(prepared.reason)
	# Preserve the original simulation width when supplied. Subtracting two
	# accumulated timestamps can round below delta and reject a legal end hit.
	var width: float = end - start if typeof(original_delta) == TYPE_NIL else float(original_delta)
	for i: int in range(events.size()):
		var raw: float = float(events[i].time)
		if raw > width: return "Shock event offset exceeds its original step window"
		var absolute: float = start + raw
		if not is_finite(absolute): return "Shock absolute event timestamp is not representable"
		absolute = clampf(absolute, start, end)
		if absolute < floor_time: return "Shock event precedes the retained history window"
		if float(prepared.offsets[i]) - raw >= MIN_POLICY_DURATION:
			return "Shock event reversal spans more than the retained single prior interval"
	return ""


static func _nonnegative_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0
