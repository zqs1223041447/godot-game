class_name CombatFeedbackRuntime
extends RefCounted
## Presentation receipts consume actual resource loss, never resolve damage.
const WINDOW_SECONDS: float = 0.20
const VISIBLE_LIFETIME: float = 0.75
const MAX_PENDING: int = 303
const MAX_VISIBLE: int = 48
var _time: float = 0.0
var _epoch: int = 0
var _next_sequence: int = 0
var _next_id: int = 0
var _pending: Dictionary = {}
var _visible: Dictionary = {}

func record(event: Variant) -> Dictionary:
	var reason: String = _event_error(event)
	if not reason.is_empty(): return _failure(reason)
	var shield: float = float(event.shield_spent)
	var health: float = float(event.health_lost)
	var amount: float = shield + health
	if not is_finite(amount): return _failure("Feedback event amount overflow")
	if amount == 0.0: return _success()
	var key: String = _key(event.target_kind, event.target_id, event.kind)
	if _pending.has(key):
		var pending: Dictionary = _pending[key]
		var next_amount: float = float(pending.amount) + amount
		var next_shield: float = float(pending.shield_spent) + shield
		var next_health: float = float(pending.health_lost) + health
		if not is_finite(next_amount) or not is_finite(next_shield) or not is_finite(next_health):
			return _failure("Feedback window amount overflow")
		pending.amount = next_amount
		pending.shield_spent = next_shield
		pending.health_lost = next_health
		pending.hit_count += 0 if event.kind == "burn" else 1
		pending.position = event.position
		return _success()
	var deadline: float = _time + WINDOW_SECONDS
	if not is_finite(deadline) or deadline <= _time:
		return _failure("Feedback window deadline is not representable")
	if _pending.size() >= MAX_PENDING: _publish(_oldest_key(_pending), _time)
	_next_sequence += 1
	_pending[key] = {"target_kind":event.target_kind, "target_id":event.target_id,
		"kind":event.kind, "amount":amount, "shield_spent":shield, "health_lost":health,
		"hit_count":0 if event.kind == "burn" else 1, "position":event.position,
		"deadline":deadline, "sequence":_next_sequence}
	return _success()

func advance(delta: Variant) -> Dictionary:
	if not _nonnegative_number(delta): return _failure("Feedback delta must be finite and nonnegative")
	var until: float = _time + float(delta)
	if not is_finite(until): return _failure("Feedback clock overflow")
	if until == _time: return _success()
	for key: String in _ordered_keys(_pending):
		var deadline: float = float(_pending[key].deadline)
		if deadline > until: break
		_expire_at(deadline)
		_publish(key, deadline)
	_time = until
	_expire_at(_time)
	return _success()

func flush_target(target_kind: Variant, target_id: Variant) -> Dictionary:
	var reason: String = _target_error(target_kind, target_id)
	if not reason.is_empty(): return _failure(reason)
	for key: String in _ordered_keys(_pending):
		var pending: Dictionary = _pending[key]
		if pending.target_kind == target_kind and pending.target_id == target_id:
			_publish(key, _time)
	return _success()

func reset() -> void:
	_time = 0.0
	_epoch += 1
	_next_sequence = 0
	_pending.clear()
	_visible.clear()
	# Output IDs stay unique after a reset even when gameplay target IDs repeat.

func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in _ordered_keys(_visible):
		var value: Dictionary = _visible[key]
		result.append({"id":value.id, "target_kind":value.target_kind,
			"target_id":value.target_id, "kind":value.kind, "amount":value.amount,
			"shield_spent":value.shield_spent, "health_lost":value.health_lost,
			"hit_count":value.hit_count, "position":value.position,
			"age":_time-float(value.born), "lifetime":VISIBLE_LIFETIME})
	return result

func _publish(key: String, born: float) -> void:
	var value: Dictionary = _pending[key]
	_pending.erase(key)
	_next_id += 1
	value.id = _next_id
	value.born = born
	value.sequence = _next_id
	_visible[key] = value
	if _visible.size() > MAX_VISIBLE: _visible.erase(_oldest_key(_visible))

func _expire_at(at: float) -> void:
	for key: String in _visible.keys():
		if at >= float(_visible[key].born) + VISIBLE_LIFETIME: _visible.erase(key)

func _key(target_kind: String, target_id: int, kind: String) -> String:
	return "%d:%s:%d:%s" % [_epoch, target_kind, target_id, kind]

static func _ordered_keys(store: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: String in store: keys.append(key)
	keys.sort_custom(func(a: String, b: String) -> bool: return int(store[a].sequence) < int(store[b].sequence))
	return keys

static func _oldest_key(store: Dictionary) -> String:
	var oldest: String = ""
	for key: String in store:
		if oldest.is_empty() or int(store[key].sequence) < int(store[oldest].sequence): oldest = key
	return oldest

static func _event_error(event: Variant) -> String:
	if not event is Dictionary: return "Feedback event must be a dictionary"
	for field: String in ["target_kind", "target_id", "kind", "shield_spent", "health_lost", "position"]:
		if not event.has(field): return "Feedback event is missing " + field
	var reason: String = _target_error(event.target_kind, event.target_id)
	if not reason.is_empty(): return reason
	if typeof(event.kind) != TYPE_STRING or event.kind not in ["hit", "critical", "burn"]:
		return "Feedback kind must be hit, critical, or burn"
	if not _nonnegative_number(event.shield_spent) or not _nonnegative_number(event.health_lost):
		return "Feedback resource loss must be finite and nonnegative"
	if typeof(event.position) != TYPE_VECTOR2 or not event.position.is_finite(): return "Feedback position must be a finite Vector2"
	return ""

static func _target_error(target_kind: Variant, target_id: Variant) -> String:
	if typeof(target_kind) != TYPE_STRING or target_kind not in ["player", "monster"]: return "Feedback target kind must be player or monster"
	if typeof(target_id) != TYPE_INT or (target_kind == "player" and target_id != 0) or (target_kind == "monster" and target_id <= 0):
		return "Feedback target ID must be player zero or a positive monster integer"
	return ""

static func _nonnegative_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0

static func _success() -> Dictionary: return {"ok":true, "reason":""}
static func _failure(reason: String) -> Dictionary: return {"ok":false, "reason":reason}
