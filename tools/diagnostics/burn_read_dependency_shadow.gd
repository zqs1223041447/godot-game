extends RefCounted
## Pure design executable. No production callers, actor writes, resource writes,
## feedback reservations, RNG, wall-clock advancement or scheduler switch.
const Clock = preload("res://scripts/combat/ember_event_clock.gd")
const MAX_TARGETS := 100
const OPERATIONS: Array[String] = ["contact", "refresh", "expiry", "burn_death", "direct_lethal", "observation", "batch_exit", "phase_exit", "reset"]
const BARRIERS: Array[String] = ["burn_death", "direct_lethal", "observation", "batch_exit", "phase_exit", "reset"]


## Only a clock plan; the original events and admission order are untouched.
## Shock keeps the raw timestamp while burns use the original adjacent tie rule.
static func prepare_events(events: Variant, start: Variant, end: Variant, initial_clock: Variant) -> Dictionary:
	if not _time(start) or not _time(end) or float(end) < float(start) or not _time(initial_clock) or float(initial_clock) > float(end):
		return _failure("Invalid finite batch clock bounds")
	var offsets: Dictionary = Clock.offsets(events)
	if not offsets.ok: return _failure(offsets.reason)
	var records: Array[Dictionary] = []
	var watermark: float = float(initial_clock)
	for index: int in range(events.size()):
		var raw: float = float(events[index].time)
		var at: float = clampf(float(start) + float(offsets.offsets[index]), float(start), float(end))
		if watermark > at:
			# The relative raw offset, never cumulative elapsed, defines this tie.
			if not is_equal_approx(raw, watermark - float(start)):
				return _failure("Batch clock would reverse outside the original relative tie")
			at = watermark
		watermark = at
		records.append({"index":index, "sequence":events[index].get("sequence", index),
			"raw_offset":raw, "normalized_offset":float(offsets.offsets[index]),
			"shock_at":clampf(float(start) + raw, float(start), float(end)), "burn_at":at})
	return {"ok":true, "reason":"", "records":records, "watermark":watermark}


## rows are detached materialization facts, not approximate live resource data.
## The caller must first drain the deadline queue. This method only declares
## which reads/records require materialization; it does not settle their damage.
static func read_plan(rows: Variant, operation: Variant, at: Variant, targets: Variant,
		pending_burn_ids: Variant, uncertain_boundary: bool = false) -> Dictionary:
	if not rows is Array or rows.size() > MAX_TARGETS: return _failure("Burn rows exceed the 100-target shadow bound")
	if typeof(operation) != TYPE_STRING or operation not in OPERATIONS: return _failure("Unknown materialization operation")
	if not _time(at): return _failure("Read time must be finite and nonnegative")
	var target_error: String = _ids_error(targets)
	if not target_error.is_empty(): return _failure(target_error)
	var pending_error: String = _ids_error(pending_burn_ids)
	if not pending_error.is_empty(): return _failure(pending_error)
	var by_id: Dictionary = {}
	for row: Variant in rows:
		if not row is Dictionary or row.size() != 4 or not row.has_all(["target_id", "last_time", "expires_at", "raw_dps"]):
			return _failure("Read row requires only target_id, last_time, expires_at and raw_dps")
		for key: Variant in row:
			if typeof(key) != TYPE_STRING: return _failure("Read row keys must be Strings")
		if typeof(row.target_id) != TYPE_INT or int(row.target_id) <= 0 or by_id.has(row.target_id):
			return _failure("Read rows require unique positive integer IDs")
		if not _time(row.last_time) or not _time(row.expires_at) or float(row.expires_at) <= float(row.last_time) or not _positive(row.raw_dps):
			return _failure("Read row contains an invalid burn interval")
		if float(row.last_time) > float(at): return _failure("Read precedes a materialized target clock")
		by_id[row.target_id] = row
	var ordered: Array = by_id.keys(); ordered.sort()
	var first_positive: Array[int] = []
	for id: int in ordered:
		if pending_burn_ids.has(id): continue
		var row: Dictionary = by_id[id]
		var width: float = minf(float(at), float(row.expires_at)) - float(row.last_time)
		if width <= 0.0: continue
		var raw: float = float(row.raw_dps) * width
		if not is_finite(raw) or raw <= 0.0:
			return _failure("Unrepresentable positive segment requires the original path")
		first_positive.append(id)
	var whole: bool = operation in BARRIERS or uncertain_boundary
	var required: Array[int] = []
	for id: int in ordered:
		if whole or targets.has(id) or first_positive.has(id): required.append(id)
	return {"ok":true, "reason":"", "operation":operation, "at":float(at),
		"mode":"eager_replay" if uncertain_boundary else "full_barrier" if whole else "target_lazy",
		"materialize_ids":required, "first_positive_feedback_ids":first_positive,
		"feedback_order":"original target ID before the hit", "feedback_clock_unchanged":true,
		"drain_due_before_reads":true, "uses_original_damage_rules":true,
		"numerical_equivalence_proven":false, "shadow_only":true}


static func _ids_error(value: Variant) -> String:
	if not value is Array or value.size() > MAX_TARGETS: return "Read ID list exceeds the 100-target bound"
	var seen: Dictionary = {}
	for id: Variant in value:
		if typeof(id) != TYPE_INT or int(id) <= 0 or seen.has(id): return "Read IDs must be unique positive integers"
		seen[id] = true
	return ""


static func _time(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


static func _positive(value: Variant) -> bool:
	return _time(value) and float(value) > 0.0


static func _failure(reason: String) -> Dictionary:
	return {"ok":false, "reason":reason, "records":[], "materialize_ids":[], "requires_original_path":true, "shadow_only":true}
