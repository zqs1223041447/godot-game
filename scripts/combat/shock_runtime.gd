class_name ShockRuntime
extends RefCounted
## Pure ephemeral shock storage. The caller reads at the original authoritative
## hit timestamp, settles the hit, then applies shock after positive actual
## lightning damage. It owns live-target checks and event ordering. This class
## never advances a damage clock, deals damage, propagates, or consumes RNG.
const Rules = preload("res://scripts/combat/shock_rules.gd")
const MAX_TARGETS: int = 101
const MAX_PROVENANCE_TEXT: int = 128
const PROVENANCE_KEYS: Array[String] = ["skill_id", "cast_id", "projectile_id", "phase"]
var _states: Dictionary = {}
# One previous interval per current target retains legal expiry-crossing ties
# until frame cleanup. The global floor makes discarded history explicit.
var _previous_intervals: Dictionary = {}
var _discarded_until: float = 0.0
var _status_keys: Array[String] = []
var _status_order_dirty: bool = true


func apply(kind: Variant, id: Variant, source_id: Variant, at: Variant,
		policy: Variant, provenance: Variant = {}) -> Dictionary:
	var reason: String = _actor_error(kind, id)
	if reason.is_empty() and not _source_id_valid(source_id):
		reason = "Shock source ID must be a nonnegative integer"
	if reason.is_empty() and not _time_valid(at):
		reason = "Shock time must be finite and nonnegative"
	if reason.is_empty() and float(at) < _discarded_until:
		reason = "Shock time precedes the retained history window"
	if reason.is_empty(): reason = Rules.policy_error(policy)
	if reason.is_empty(): reason = _provenance_error(provenance)
	if not reason.is_empty(): return _application_failure(reason)
	var start: float = float(at)
	var expires: float = start + float(policy.duration)
	if not is_finite(expires) or expires <= start:
		return _application_failure("Shock expiry is not representable at this timestamp")
	var key: String = _key(kind, id)
	var previous: Dictionary = _states.get(key, {})
	# Do not normalize old near-ties onto a newer burn/status clock. An old
	# application may be legal for the caller's batch but cannot rewrite future
	# source attribution, refreshed_at, or expiry. No fuzzy tolerance belongs here.
	if not previous.is_empty() and start < float(previous.refreshed_at):
		return {"ok": true, "reason": "older_application", "applied": false, "refreshed": false}
	if previous.is_empty() and _states.size() >= MAX_TARGETS:
		return _application_failure("Shock target capacity reached")
	var refreshed: bool = not previous.is_empty() and start < float(previous.expires_at)
	# Retain the start of one continuously active interval. A legal older
	# near-tie may still benefit from the shock that preceded this refresh.
	var applied_at: float = float(previous.applied_at) if refreshed else start
	# Every validation and comparison precedes mutation. The frozen policies
	# share one strength; same-time and later active applications simply refresh.
	if previous.is_empty(): _status_order_dirty = true
	if not previous.is_empty() and not refreshed:
		if _previous_intervals.has(key):
			_discarded_until = maxf(_discarded_until, float(_previous_intervals[key].expires_at))
		_previous_intervals[key] = previous
	_states[key] = {"target_kind": kind, "target_id": id, "source_id": source_id,
		"applied_at": applied_at, "refreshed_at": start, "expires_at": expires,
		"hit_damage_taken_increased": float(policy.hit_damage_taken_increased),
		"provenance": provenance.duplicate(true)}
	return {"ok": true, "reason": "refreshed" if refreshed else "new",
		"applied": true, "refreshed": refreshed}


## Read before settling a hit, at its original timestamp. Queries never mutate
## or prune states; an earlier event cannot see a shock applied in its future.
func status_at(kind: Variant, id: Variant, at: Variant) -> Dictionary:
	var reason: String = _actor_error(kind, id)
	if reason.is_empty() and not _time_valid(at):
		reason = "Shock time must be finite and nonnegative"
	if reason.is_empty() and float(at) < _discarded_until:
		reason = "Shock time precedes the retained history window"
	if not reason.is_empty(): return _query_result(false, reason)
	var key: String = _key(kind, id)
	if not _states.has(key): return _query_result(true, "missing")
	var time: float = float(at)
	var state: Dictionary = _interval_at(key, time)
	if state.is_empty(): return _query_result(true, "inactive")
	var status: Dictionary = _detached_status(state, time)
	return {"ok": true, "reason": "", "active": true,
		"hit_damage_taken_increased": float(state.hit_damage_taken_increased), "status": status}


## Detached active entries in lexical kind / numeric ID order. This presentation
## query is bounded by MAX_TARGETS and never replaces per-hit status_at lookups.
func statuses(at: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _time_valid(at): return result
	var time: float = float(at)
	if time < _discarded_until: return result
	_ensure_status_order()
	for key: String in _status_keys:
		var state: Dictionary = _interval_at(key, time)
		if not state.is_empty(): result.append(_detached_status(state, time))
	return result


## Once-per-frame cleanup after the caller finishes that frame's events. No
## full-state scan is hidden in apply or status_at. Historical events must not
## be replayed after their states have been pruned, removed, or reset.
func prune(at: Variant) -> Dictionary:
	if not _time_valid(at):
		return {"ok": false, "reason": "Shock time must be finite and nonnegative", "removed": 0}
	var time: float = float(at)
	if time < _discarded_until:
		return {"ok": false, "reason": "Shock time precedes the retained history window", "removed": 0}
	var expired: Array[String] = []
	for key: String in _states:
		if float(_states[key].expires_at) <= time: expired.append(key)
	for key: String in expired:
		_states.erase(key)
		_previous_intervals.erase(key)
	for key: String in _previous_intervals.keys():
		if float(_previous_intervals[key].expires_at) <= time: _previous_intervals.erase(key)
	_discarded_until = time
	if not expired.is_empty(): _status_order_dirty = true
	return {"ok": true, "reason": "", "removed": expired.size()}


func remove(kind: Variant, id: Variant) -> Dictionary:
	var reason: String = _actor_error(kind, id)
	if not reason.is_empty(): return {"ok": false, "reason": reason, "removed": false}
	var removed: bool = _states.erase(_key(kind, id))
	_previous_intervals.erase(_key(kind, id))
	if removed: _status_order_dirty = true
	return {"ok": true, "reason": "", "removed": removed}


func reset() -> void:
	_states.clear()
	_previous_intervals.clear()
	_discarded_until = 0.0
	_status_keys.clear()
	_status_order_dirty = false


## Reports retained storage, including expired entries awaiting frame cleanup.
func is_empty() -> bool:
	return _states.is_empty()


## The inclusive lower bound of retained event history. The caller validates
## each complete near-tie batch against this before settling any of its hits.
func read_floor() -> float:
	return _discarded_until


func _interval_at(key: String, at: float) -> Dictionary:
	var current: Dictionary = _states[key]
	if float(current.applied_at) <= at and at < float(current.expires_at): return current
	var previous: Dictionary = _previous_intervals.get(key, {})
	if not previous.is_empty() and float(previous.applied_at) <= at and at < float(previous.expires_at):
		return previous
	return {}


func _ensure_status_order() -> void:
	if not _status_order_dirty: return
	_status_keys.assign(_states.keys())
	_status_keys.sort_custom(func(left_key: String, right_key: String) -> bool:
		var left: Dictionary = _states[left_key]
		var right: Dictionary = _states[right_key]
		if left.target_kind != right.target_kind: return left.target_kind < right.target_kind
		return int(left.target_id) < int(right.target_id))
	_status_order_dirty = false


static func _detached_status(state: Dictionary, at: float) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	result["remaining_seconds"] = float(state.expires_at) - at
	return result


static func _actor_error(kind: Variant, id: Variant) -> String:
	if typeof(kind) != TYPE_STRING or kind not in ["player", "monster"]:
		return "Shock target kind must be player or monster"
	if typeof(id) != TYPE_INT or (kind == "player" and id != 0) or (kind == "monster" and id <= 0):
		return "Shock target ID must be player zero or a positive monster integer"
	return ""


static func _source_id_valid(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


static func _time_valid(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


static func _provenance_error(value: Variant) -> String:
	if not value is Dictionary or value.size() > PROVENANCE_KEYS.size():
		return "Shock provenance must be a bounded dictionary"
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in PROVENANCE_KEYS:
			return "Unknown or non-String shock provenance field"
		if key in ["cast_id", "projectile_id"]:
			if not _source_id_valid(value[key]): return "Shock provenance IDs must be nonnegative integers"
		elif typeof(value[key]) != TYPE_STRING or value[key].length() > MAX_PROVENANCE_TEXT:
			return "Shock provenance text must be a String of at most 128 characters"
	return ""


static func _key(kind: String, id: int) -> String:
	return kind + ":" + str(id)


static func _query_result(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason, "active": false,
		"hit_damage_taken_increased": 0.0, "status": {}}


static func _application_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "applied": false, "refreshed": false}
