class_name PlayerChillRuntime
extends RefCounted
## One player-only status, with no monster scan, signals, RNG, or persistence.
## Apply at the current settlement boundary AFTER this tick's player movement.
## Queries support the latest apply/prune boundary and subsequent simulation;
## arbitrary historical windows are deliberately unsupported after refresh.
const Rules = preload("res://scripts/combat/chill_rules.gd")
var _state: Dictionary = {}
var _last_settlement_at: float = 0.0


## Read-only admission lets the caller reject malformed hit context before
## committing Defense resources or any other combat state.
func application_error(source_id: Variant, at: Variant, policy: Variant) -> String:
	if typeof(source_id) != TYPE_INT or source_id <= 0:
		return "Chill source ID must be a positive monster integer"
	if not _time_valid(at):
		return "Chill time must be finite and nonnegative"
	var start: float = float(at)
	if start < _last_settlement_at:
		return "Chill time cannot precede the latest settlement boundary"
	var reason: String = Rules.policy_error(policy)
	if not reason.is_empty():
		return reason
	var expires: float = start + float(policy.duration)
	if not is_finite(expires) or expires <= start:
		return "Chill expiry is not representable at this timestamp"
	return ""


func apply(source_id: Variant, at: Variant, policy: Variant) -> Dictionary:
	var reason: String = application_error(source_id, at, policy)
	if not reason.is_empty():
		return _application_failure(reason)
	var start: float = float(at)
	var expires: float = start + float(policy.duration)
	var refreshed: bool = not _state.is_empty() and start < float(_state.expires_at)
	if refreshed:
		expires = maxf(float(_state.expires_at), expires)
	# Keep only scalar values; never retain a caller-owned dictionary. Equal
	# strength refreshes expiry from this hit, never adds duration to old expiry.
	_state = {"source_id": source_id, "applied_at": start, "expires_at": expires,
		"movement_speed_reduced": float(policy.movement_speed_reduced)}
	_last_settlement_at = start
	return {"ok": true, "reason": "refreshed" if refreshed else "new", "applied": true}


func is_empty() -> bool:
	return _state.is_empty()


func reset() -> void:
	_state.clear()
	_last_settlement_at = 0.0


## Call after consuming this tick's movement interval. Even an empty prune
## advances the write floor so delayed old events cannot resurrect a status.
func prune(at: Variant) -> Dictionary:
	if not _time_valid(at) or float(at) < _last_settlement_at:
		return {"ok": false, "reason": "Chill prune time must be finite, nonnegative, and current", "removed": false}
	var removed: bool = not _state.is_empty() and float(at) >= float(_state.expires_at)
	if removed:
		_state.clear()
	_last_settlement_at = float(at)
	return {"ok": true, "reason": "", "removed": removed}


## Detached current-time presentation data. A read never prunes or advances
## the clock; exact expiry and unsupported historical queries are inactive.
func status(at: Variant) -> Dictionary:
	if not _time_valid(at) or float(at) < _last_settlement_at or _state.is_empty():
		return {}
	if float(at) < float(_state.applied_at) or float(at) >= float(_state.expires_at):
		return {}
	var result: Dictionary = _state.duplicate(true)
	result["remaining_seconds"] = float(_state.expires_at) - float(at)
	result["movement_multiplier"] = 1.0 - float(_state.movement_speed_reduced)
	return result


## Integrate the slow portion of a CURRENT/FUTURE movement interval. The caller
## uses speed * factor * delta; crossing expiry preserves the unchilled suffix.
## Reads never change state, including rejected and zero-width intervals.
func movement_factor(from_time: Variant, to_time: Variant) -> Dictionary:
	if not _time_valid(from_time) or not _time_valid(to_time):
		return _movement_failure("Chill movement times must be finite and nonnegative")
	var start: float = float(from_time)
	var end: float = float(to_time)
	if end < start or start < _last_settlement_at:
		return _movement_failure("Chill movement interval must be ordered and current")
	var delta: float = end - start
	if delta == 0.0 or _state.is_empty():
		return {"ok": true, "reason": "", "factor": 1.0}
	var slow_seconds: float = maxf(0.0, minf(end, float(_state.expires_at)) - start)
	var factor: float = 1.0 - float(_state.movement_speed_reduced) * (slow_seconds / delta)
	return {"ok": true, "reason": "", "factor": factor}


static func _time_valid(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


static func _application_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "applied": false}


static func _movement_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "factor": 1.0}
