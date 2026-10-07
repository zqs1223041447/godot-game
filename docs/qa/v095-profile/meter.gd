extends RefCounted
## Side-channel data only. No production result or simulation state is stored.
static var enabled: bool = false
static var phase: int = 0
static var incoming_depth: int = 0
static var totals: Array[int] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
static var calls: Array[int] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
static var eligible_calls: Array[int] = [0,0,0]
static func add(metric: int, duration: int, location: int = 0) -> void:
	var index: int = metric * 3 + location
	totals[index] += duration
	calls[index] += 1
static func reset() -> void:
	assert(incoming_depth == 0 and phase == 0)
	totals.fill(0); calls.fill(0); eligible_calls.fill(0)
static func snapshot() -> Dictionary:
	var result: Dictionary = {}
	var metrics: Array[String] = ["incoming_burn", "defense_profile_body", "defense_profile_call_envelope", "advance_total", "settlement_total", "trace_build"]
	var phases: Array[String] = ["other", "planning", "settlement"]
	for metric: int in range(metrics.size()):
		for location: int in range(3):
			var index: int = metric * 3 + location
			result[metrics[metric] + "/" + phases[location]] = {"us": totals[index], "calls": calls[index]}
	result["eligible_monster_numeric_zero_calls"] = eligible_calls.duplicate()
	return result
