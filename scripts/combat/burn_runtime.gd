class_name BurnRuntime
extends RefCounted
## Bounded, pure status storage and raw-time integration. Each target owns its
## active clock. Expiry/removal discards that clock; the caller owns live-target
## causality and advances a target before applying a hit at its event timestamp.
## Sources need not remain alive. Removing a target never removes its outgoing
## burns. No defense, hit modifiers, RNG, persistence, signals, or instant damage.
const Rules = preload("res://scripts/combat/burn_rules.gd")
const MAX_TARGETS: int = 101
const MAX_PROVENANCE_TEXT: int = 128
const PROVENANCE_KEYS: Array[String] = ["skill_id", "cast_id", "projectile_id", "phase", "ember_generation", "ember_expiry"]
var _states: Dictionary = {}
# Identity order only; never cache or expose mutable state dictionaries.
var _status_keys: Array[String] = []
var _status_order_dirty: bool = true


func apply(kind: Variant, id: Variant, source_id: Variant, raw_dps: Variant,
		duration: Variant, at: Variant, provenance: Variant = {}) -> Dictionary:
	var reason: String = _actor_error(kind, id)
	if reason.is_empty() and not _source_id_valid(source_id):
		reason = "Burn source ID must be a nonnegative integer"
	if reason.is_empty(): reason = Rules.rate_duration_error(raw_dps, duration)
	if reason.is_empty() and not _time_valid(at): reason = "Burn time must be finite and nonnegative"
	if reason.is_empty(): reason = _provenance_error(provenance)
	if not reason.is_empty(): return _application_failure(reason)
	var start: float = float(at)
	var lifetime: float = float(duration)
	var expires: float = start + lifetime
	if provenance.has("ember_expiry") and float(provenance.ember_expiry) != expires:
		# Adding a remaining duration can round one ULP away from its original
		# absolute deadline. The declared deadline is authoritative for embers.
		if absf(float(provenance.ember_expiry) - expires) > 0.000000001:
			return _application_failure("Ember duration must preserve its deadline")
		expires = float(provenance.ember_expiry)
	if not is_finite(expires) or expires <= start:
		return _application_failure("Burn expiry is not representable at this timestamp")
	var key: String = _key(kind, id)
	if not _states.has(key) and _states.size() >= MAX_TARGETS:
		return _application_failure("Burn target capacity reached")
	var segments: Array[Dictionary] = []
	var previous: Dictionary = {}
	if _states.has(key):
		var planned: Dictionary = _plan_advance(_states[key], start)
		if not planned.ok: return _application_failure(planned.reason)
		previous = planned.status
		segments = planned.segments
	var applied: bool = previous.is_empty() or float(raw_dps) >= float(previous.raw_dps)
	if previous.is_empty():
		reason = "new"
	elif float(raw_dps) > float(previous.raw_dps):
		reason = "stronger"
	elif float(raw_dps) == float(previous.raw_dps):
		reason = "equal"
	else:
		reason = "weaker"
	# Plan every validation/integration step before committing the target state.
	if not _states.has(key): _status_order_dirty = true
	if applied:
		_states[key] = {"target_kind": kind, "target_id": id, "source_id": source_id,
			"raw_dps": float(raw_dps), "remaining": lifetime, "last_time": start,
			"provenance": provenance.duplicate(true)}
	else:
		_states[key] = previous
	return {"ok": true, "reason": reason, "applied": applied, "segments": segments}


func advance_target(kind: Variant, id: Variant, to_time: Variant) -> Dictionary:
	var reason: String = _actor_error(kind, id)
	if reason.is_empty() and not _time_valid(to_time): reason = "Burn time must be finite and nonnegative"
	if not reason.is_empty(): return _failure(reason)
	var key: String = _key(kind, id)
	if not _states.has(key): return _success([])
	# The original zero-width plan retains remaining/last_time exactly. Inputs
	# are validated above; the fresh empty result exposes no internal alias.
	if float(to_time) == float(_states[key].last_time) and float(_states[key].remaining) > 0.0:
		var empty: Array[Dictionary] = []
		return _success(empty)
	var planned: Dictionary = _plan_advance(_states[key], float(to_time))
	if not planned.ok: return _failure(planned.reason)
	_commit(key, planned.status)
	return _success(planned.segments)


func advance_all(to_time: Variant) -> Dictionary:
	if not _time_valid(to_time): return _failure("Burn time must be finite and nonnegative")
	var plans: Array[Dictionary] = []
	var segments: Array[Dictionary] = []
	# Identity order is deterministic, not a claim about global event chronology.
	for state: Dictionary in statuses():
		var planned: Dictionary = _plan_advance(state, float(to_time))
		if not planned.ok: return _failure(planned.reason)
		plans.append({"key": _key(state.target_kind, state.target_id), "status": planned.status})
		segments.append_array(planned.segments)
	for planned: Dictionary in plans:
		_commit(planned.key, planned.status)
	return _success(segments)


func remove(kind: Variant, id: Variant) -> Dictionary:
	var reason: String = _actor_error(kind, id)
	if not reason.is_empty(): return {"ok": false, "reason": reason, "removed": false}
	var removed: bool = _states.erase(_key(kind, id))
	if removed: _status_order_dirty = true
	return {"ok": true, "reason": "", "removed": removed}


func reset() -> void:
	_states.clear()
	_status_keys.clear()
	_status_order_dirty = false


## Read-only clock for preserving an upstream scheduler's established tie order.
## Negative means no active target; core advancement still rejects any reversal.
func last_time_for(kind:Variant,id:Variant)->float:
	if not _actor_error(kind,id).is_empty():return -1.0
	return float(_states.get(_key(kind,id),{}).get("last_time",-1.0))


func is_empty() -> bool:
	return _states.is_empty()


func status_for(kind: Variant, id: Variant) -> Dictionary:
	if not _actor_error(kind, id).is_empty(): return {}
	return _states.get(_key(kind, id), {}).duplicate(true)


func has_ember_states() -> bool:
	for state: Dictionary in _states.values():
		if state.provenance.has("ember_generation"): return true
	return false


func latest_monster_time() -> float:
	var latest: float = -1.0
	for key: String in _states:
		var state: Dictionary = _states[key]
		if state.target_kind == "monster": latest = maxf(latest, float(state.last_time))
	return latest


## Fresh identities only when every active monster has exactly this clock.
## Not a cached finished-time claim: replacements and new targets are inspected
## each time. The caller still owns live/missing-target cleanup and death flush.
func monster_ids_at_time(to_time: Variant) -> Array[int]:
	var result: Array[int] = []
	if not _time_valid(to_time): return result
	_ensure_status_order()
	for key: String in _status_keys:
		var state: Dictionary = _states[key]
		if state.target_kind != "monster": continue
		if float(state.last_time) != float(to_time) or float(state.remaining) <= 0.0: return []
		result.append(int(state.target_id))
	return result


func _ensure_status_order() -> void:
	if not _status_order_dirty: return
	_status_keys.assign(_states.keys())
	_status_keys.sort_custom(func(left_key: String, right_key: String) -> bool:
		var left: Dictionary = _states[left_key]
		var right: Dictionary = _states[right_key]
		if left.target_kind != right.target_kind: return left.target_kind < right.target_kind
		return int(left.target_id) < int(right.target_id))
	_status_order_dirty = false


func statuses() -> Array[Dictionary]:
	_ensure_status_order()
	var result: Array[Dictionary] = []
	for key: String in _status_keys: result.append(_states[key].duplicate(true))
	return result


func _commit(key: String, state: Dictionary) -> void:
	if state.is_empty():
		if _states.erase(key): _status_order_dirty = true
	else:
		if not _states.has(key): _status_order_dirty = true
		_states[key] = state

static func _plan_advance(state: Dictionary, to_time: float) -> Dictionary:
	var last: float = float(state.last_time)
	if to_time < last: return _failure("Burn time cannot move backwards for an active target")
	# Subtract from the absolute expiry, rather than repeatedly subtracting frame
	# widths from remaining, so common split intervals do not drift past expiry.
	var expires: float = float(state.provenance.get("ember_expiry", last + float(state.remaining)))
	var end: float = minf(to_time, expires)
	var width: float = end - last
	var next: Dictionary = state.duplicate(true)
	var segments: Array[Dictionary] = []
	if width > 0.0:
		var amount: float = float(state.raw_dps) * width
		if not is_finite(amount) or amount <= 0.0 or end <= last:
			return _failure("Burn segment amount or interval is not representable")
		segments.append({"target_kind": state.target_kind, "target_id": state.target_id,
			"source_id": state.source_id, "from_time": last, "to_time": end,
			"raw_dps": state.raw_dps, "raw_amount": amount,
			"provenance": state.provenance.duplicate(true)})
		next.remaining = maxf(0.0, expires - to_time)
		next.last_time = to_time
	if float(next.remaining) <= 0.0: next = {}
	return {"ok": true, "reason": "", "status": next, "segments": segments}


static func _actor_error(kind: Variant, id: Variant) -> String:
	if typeof(kind) != TYPE_STRING or kind not in ["player", "monster"]:
		return "Burn target kind must be player or monster"
	if typeof(id) != TYPE_INT or (kind == "player" and id != 0) or (kind == "monster" and id <= 0):
		return "Burn target ID must be player zero or a positive monster integer"
	return ""


static func _source_id_valid(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


static func _time_valid(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


static func _provenance_error(value: Variant) -> String:
	if not value is Dictionary or value.size() > PROVENANCE_KEYS.size():
		return "Burn provenance must be a bounded dictionary"
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in PROVENANCE_KEYS:
			return "Unknown or non-String burn provenance field"
		if key in ["cast_id", "projectile_id"]:
			if not _source_id_valid(value[key]): return "Burn provenance IDs must be nonnegative integers"
		elif key == "ember_generation":
			if typeof(value[key]) != TYPE_INT or value[key] not in [0, 1]: return "Ember generation must be zero or one"
		elif key == "ember_expiry":
			if not Rules.positive_number(value[key]): return "Ember expiry must be finite and positive"
		elif typeof(value[key]) != TYPE_STRING or value[key].length() > MAX_PROVENANCE_TEXT:
			return "Burn provenance text must be a String of at most 128 characters"
	if value.has("ember_generation") != value.has("ember_expiry"): return "Ember provenance requires generation and expiry"
	return ""


static func _key(kind: String, id: int) -> String:
	return kind + ":" + str(id)


static func _success(segments: Array) -> Dictionary:
	return {"ok": true, "reason": "", "segments": segments}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "segments": []}


static func _application_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "applied": false, "segments": []}
