class_name FreezeRuntime
extends RefCounted
## Pure bounded status storage. Apply only at the current settlement boundary,
## never at historical projectile offsets. The caller owns actor liveness,
## enemy-clock advancement, removal on death, and immediate scene resets.
const Rules = preload("res://scripts/combat/frost_lock_rules.gd")
const MAX_TARGETS: int = 100
const MAX_PROVENANCE_TEXT: int = 128
const PROVENANCE_KEYS: Array[String] = ["skill_id", "cast_id", "projectile_id", "phase"]
var _states: Dictionary = {}
var _last_settlement_at: float = 0.0


func apply(target_id: Variant, rarity: Variant, at: Variant, policy: Variant,
		provenance: Variant = {}) -> Dictionary:
	var reason: String = _target_error(target_id)
	if reason.is_empty() and (typeof(rarity) != TYPE_STRING or rarity not in Rules.RARITY_KEYS):
		reason = "Freeze rarity must be normal, magic, rare, or boss"
	if reason.is_empty() and not _time_valid(at):
		reason = "Freeze time must be finite and nonnegative"
	if reason.is_empty() and float(at) < _last_settlement_at:
		reason = "Freeze time cannot precede the latest settlement boundary"
	if reason.is_empty(): reason = Rules.policy_error(policy)
	if reason.is_empty(): reason = _provenance_error(provenance)
	if not reason.is_empty(): return _application_failure(reason)
	var start: float = float(at)
	var until: float = start + float(policy.duration_by_rarity[rarity])
	var immune_until: float = until + float(policy.immunity_seconds)
	if not is_finite(until) or until <= start or not is_finite(immune_until) or immune_until <= until:
		return _application_failure("Freeze expiry or immunity is not representable at this timestamp")
	var previous: Dictionary = _states.get(target_id, {})
	if not previous.is_empty() and start < float(previous.immune_until):
		_last_settlement_at = start
		return {"ok": true, "reason": "frozen" if start < float(previous.frozen_until) else "immune", "applied": false}
	if previous.is_empty() and _states.size() >= MAX_TARGETS:
		return _application_failure("Freeze target capacity reached")
	# Validate everything before changing state. Existing status never refreshes,
	# stacks, extends, or changes provenance, including exact-time repeat hits.
	_states[target_id] = {"target_id": target_id, "rarity": rarity,
		"frozen_from": start, "frozen_until": until, "immune_until": immune_until,
		"provenance": provenance.duplicate(true)}
	_last_settlement_at = start
	return {"ok": true, "reason": "new", "applied": true}


func remove(target_id: Variant) -> Dictionary:
	var reason: String = _target_error(target_id)
	if not reason.is_empty(): return {"ok": false, "reason": reason, "removed": false}
	return {"ok": true, "reason": "", "removed": _states.erase(target_id)}


func reset() -> void:
	_states.clear()
	_last_settlement_at = 0.0


func is_empty() -> bool:
	return _states.is_empty()


## Total retained states, including thawed targets whose immunity still runs.
func active_count() -> int:
	return _states.size()


func is_frozen(target_id: Variant, at: Variant) -> bool:
	return remaining_seconds(target_id, at) > 0.0


## Queries are O(1), detached, and never advance or prune any status clock.
func remaining_seconds(target_id: Variant, at: Variant) -> float:
	if not _target_error(target_id).is_empty() or not _time_valid(at): return 0.0
	var state: Dictionary = _states.get(target_id, {})
	if state.is_empty() or float(at) < float(state.frozen_from) or float(at) >= float(state.frozen_until):
		return 0.0
	return float(state.frozen_until) - float(at)


func state_for(target_id: Variant) -> Dictionary:
	if not _target_error(target_id).is_empty(): return {}
	return _states.get(target_id, {}).duplicate(true)


## Read once before the enemy phase. Each value is the frozen prefix of this
## frame, so the caller advances that enemy by delta - prefix. A status that
## starts inside the frame cannot be represented as a prefix and rejects the
## whole query. Future starts at/after the end contribute nothing.
func frame_prefixes(step_start: Variant, delta: Variant) -> Dictionary:
	if not _time_valid(step_start) or not _time_valid(delta):
		return _prefix_failure("Freeze frame start and delta must be finite and nonnegative")
	var start: float = float(step_start)
	var width: float = float(delta)
	var end: float = start + width
	if not is_finite(end) or (width > 0.0 and end <= start):
		return _prefix_failure("Freeze frame end is not representable")
	var by_id: Dictionary = {}
	if width == 0.0: return {"ok": true, "reason": "", "by_id": by_id}
	for id: int in _states:
		var state: Dictionary = _states[id]
		var frozen_from: float = float(state.frozen_from)
		if frozen_from > start and frozen_from < end:
			return _prefix_failure("Freeze starts inside the requested frame instead of at a settlement boundary")
		if frozen_from > start or float(state.frozen_until) <= start: continue
		var blocked: float = minf(width, float(state.frozen_until) - start)
		if blocked > 0.0: by_id[id] = blocked
	return {"ok": true, "reason": "", "by_id": by_id}


## Call only AFTER the enemy phase so a large delta retains its thaw prefix.
## Immunity remains in storage until its exact expiry. No per-hit scan/prune.
func prune(now: Variant) -> Dictionary:
	if not _time_valid(now):
		return {"ok": false, "reason": "Freeze prune time must be finite and nonnegative", "removed": 0}
	var at: float = float(now)
	if at < _last_settlement_at:
		return {"ok": false, "reason": "Freeze prune time cannot precede the latest settlement boundary", "removed": 0}
	var expired: Array[int] = []
	for id: int in _states:
		if float(_states[id].immune_until) <= at: expired.append(id)
	for id: int in expired: _states.erase(id)
	_last_settlement_at = at
	return {"ok": true, "reason": "", "removed": expired.size()}


static func _target_error(value: Variant) -> String:
	if typeof(value) != TYPE_INT or value <= 0:
		return "Freeze target ID must be a positive monster integer"
	return ""


static func _time_valid(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


static func _provenance_error(value: Variant) -> String:
	if not value is Dictionary or value.size() > PROVENANCE_KEYS.size():
		return "Freeze provenance must be a bounded dictionary"
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in PROVENANCE_KEYS:
			return "Unknown or non-String freeze provenance field"
		if key in ["cast_id", "projectile_id"]:
			if typeof(value[key]) != TYPE_INT or value[key] < 0:
				return "Freeze provenance IDs must be nonnegative integers"
		elif typeof(value[key]) != TYPE_STRING or value[key].length() > MAX_PROVENANCE_TEXT:
			return "Freeze provenance text must be a String of at most 128 characters"
	return ""


static func _application_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "applied": false}


static func _prefix_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "by_id": {}}
