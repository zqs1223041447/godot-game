class_name LeechRuntime
extends RefCounted
## Per-run, non-instant recovery. Each hit has a frozen expiry; a capped portion
## is discarded rather than queued. Only expiry events are visited each tick.
const Rules = preload("res://scripts/combat/leech_rules.gd")
const RESOURCES: Array[String] = ["health", "mana"]
var _time: float = 0.0
var _heaps: Dictionary = {"health": [], "mana": []}
var _rates: Dictionary = {"health": 0.0, "mana": 0.0}


func clear() -> void:
	_time = 0.0
	for resource: String in RESOURCES: _clear_resource(resource)


func is_empty() -> bool:
	return _heaps.health.is_empty() and _heaps.mana.is_empty()


func snapshot() -> Dictionary:
	return {"time": _time, "health": {"rate": _rates.health, "expiries": _heaps.health.duplicate(true)},
		"mana": {"rate": _rates.mana, "expiries": _heaps.mana.duplicate(true)}}


func clear_full(current: Dictionary, maxima: Dictionary) -> bool:
	if not _resources_valid(current, maxima): return false
	for resource: String in RESOURCES:
		if float(current[resource]) >= float(maxima[resource]): _clear_resource(resource)
	return true


func admit(packet: Dictionary, frozen: Dictionary, settlement: Dictionary,
		current: Dictionary, maxima: Dictionary) -> Dictionary:
	if not _resources_valid(current, maxima): return _failure("Invalid current leech resources")
	if not frozen.has("leech"):
		clear_full(current, maxima)
		return _empty_gain()
	if not frozen.leech is Dictionary: return _failure("Invalid frozen leech profile")
	var reason: String = Rules.profile_error(frozen.leech)
	if not reason.is_empty(): return _failure(reason)
	var planned: Dictionary = Rules.plan_hit(frozen.leech, packet, settlement)
	if not planned.ok: return _failure(str(planned.reason))
	var additions: Dictionary = {}
	for resource: String in RESOURCES:
		var amount: float = float(planned[resource].amount)
		var rate: float = float(planned[resource].rate)
		if amount <= 0.0 or float(current[resource]) >= float(maxima[resource]): continue
		var expires: float = _time + amount / rate
		if not is_finite(expires) or expires <= _time or not is_finite(float(_rates[resource]) + rate):
			return _failure("Leech expiry or aggregate rate overflow")
		additions[resource] = {"expires": expires, "rate": rate, "amount": amount}
	# Every input is admitted before either resource changes.
	clear_full(current, maxima)
	var result: Dictionary = _empty_gain()
	for resource: String in additions:
		var entry: Dictionary = additions[resource]
		_push(resource, {"expires": entry.expires, "rate": entry.rate})
		_rates[resource] = float(_rates[resource]) + float(entry.rate)
		result[resource] = float(entry.amount)
	return result


func advance(delta: float, current: Dictionary, maxima: Dictionary, caps: Dictionary) -> Dictionary:
	if not is_finite(delta) or delta < 0.0 or not _resources_valid(current, maxima):
		return _failure("Invalid leech advance resources or delta")
	if not _exact_keys(caps, RESOURCES): return _failure("Invalid leech rate caps")
	for resource: String in RESOURCES:
		if not _amount(caps[resource]): return _failure("Invalid leech rate cap")
	var until: float = _time + delta
	if not is_finite(until): return _failure("Leech time overflow")
	clear_full(current, maxima)
	var result: Dictionary = _empty_gain()
	for resource: String in RESOURCES:
		var remaining: float = float(maxima[resource]) - float(current[resource])
		var cursor: float = _time
		var gain: float = 0.0
		while not _heaps[resource].is_empty() and cursor < until:
			var next: float = minf(until, float(_heaps[resource][0].expires))
			var rate: float = minf(float(_rates[resource]), float(caps[resource]))
			var width: float = maxf(0.0, next - cursor)
			# Compare against the missing amount before multiplying large rates.
			if rate > 0.0 and width >= (remaining - gain) / rate:
				gain = remaining
				_clear_resource(resource)
				break
			gain += rate * width
			cursor = next
			while not _heaps[resource].is_empty() and float(_heaps[resource][0].expires) <= cursor:
				var expired: Dictionary = _pop(resource)
				_rates[resource] = maxf(0.0, float(_rates[resource]) - float(expired.rate))
			if _heaps[resource].is_empty(): _rates[resource] = 0.0
		result[resource] = gain
	_time = until
	return result


func _clear_resource(resource: String) -> void:
	_heaps[resource].clear()
	_rates[resource] = 0.0


func _push(resource: String, entry: Dictionary) -> void:
	var heap: Array = _heaps[resource]
	heap.append(entry)
	var index: int = heap.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if float(heap[parent].expires) <= float(entry.expires): break
		heap[index] = heap[parent]
		index = parent
	heap[index] = entry


func _pop(resource: String) -> Dictionary:
	var heap: Array = _heaps[resource]
	var result: Dictionary = heap[0]
	var last: Dictionary = heap.pop_back()
	if heap.is_empty(): return result
	var index: int = 0
	while index * 2 + 1 < heap.size():
		var child: int = index * 2 + 1
		if child + 1 < heap.size() and float(heap[child + 1].expires) < float(heap[child].expires): child += 1
		if float(last.expires) <= float(heap[child].expires): break
		heap[index] = heap[child]
		index = child
	heap[index] = last
	return result


static func _resources_valid(current: Dictionary, maxima: Dictionary) -> bool:
	if not _exact_keys(current, RESOURCES) or not _exact_keys(maxima, RESOURCES): return false
	for resource: String in RESOURCES:
		if not _amount(current[resource]) or not _amount(maxima[resource]) or float(maxima[resource]) <= 0.0: return false
		if float(current[resource]) > float(maxima[resource]): return false
	return true


static func _exact_keys(value: Dictionary, keys: Array[String]) -> bool:
	if value.size() != keys.size(): return false
	for key: Variant in value:
		if not key is String or not keys.has(key): return false
	return true


static func _amount(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


static func _empty_gain() -> Dictionary:
	return {"ok": true, "reason": "", "health": 0.0, "mana": 0.0}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "health": 0.0, "mana": 0.0}
