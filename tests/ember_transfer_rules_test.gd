extends SceneTree
## Focused pure Ember selection/transfer and BurnRuntime lineage contracts.
## Does not boot main, load saves, or repeat the historical burn suite.
const Ember = preload("res://scripts/combat/ember_proliferation_rules.gd")
const Runtime = preload("res://scripts/combat/burn_runtime.gd")
const RUN_MARKER: String = "EMBER_TRANSFER_RULES_MAIN"
var checks: int = 0
var failures: int = 0
var completed: bool = false
var cases: int = 0
var los_calls: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print(RUN_MARKER + " BEGIN")
	seed(470047)
	var expected_random: Array = [randi(), randi(), randi()]
	seed(470047)
	_case(_test_selection_geometry, "center radius, exclusions and deterministic cap")
	_case(_test_callable_visibility, "real Callable visibility filters before cap")
	_case(_test_invalid_selection, "invalid selection is atomic and detached")
	_case(_test_transfer_contract, "one-hop rate and absolute expiry transfer")
	_case(_test_invalid_transfer, "malformed lineage cannot transfer")
	_case(_test_runtime_lineage, "paired bounded lineage and deadline validation")
	_case(_test_runtime_expiry, "split integration preserves absolute deadlines")
	_case(_test_runtime_replacement, "winning attribution follows strong weak equal rules")
	_case(_test_legacy_shape_and_copies, "legacy shape and detached state/segments")
	_expect([randi(), randi(), randi()] == expected_random, "Pure rules and storage leave global RNG untouched")
	print("Ember transfer rules: %d checks, %d failures; %d completed cases" % [checks, failures, cases])
	print(RUN_MARKER + " END")
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	completed = false
	test.call()
	_expect(completed, "Case reaches completion without script exception: " + label)
	if completed: cases += 1


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(absf(actual - expected) <= maxf(1.0e-11, absf(expected) * 1.0e-12),
		"%s (actual %.14f, expected %.14f)" % [label, actual, expected])


func _candidate(id: int, pos: Vector2, health: float = 100.0, spawn: float = 0.0) -> Dictionary:
	return {"id": id, "pos": pos, "health": health, "spawn": spawn}


func _lineage(generation: int, expiry: float, cast_id: int = 41) -> Dictionary:
	return {"skill_id": "meteor", "cast_id": cast_id, "projectile_id": 42,
		"phase": "direct", "ember_generation": generation, "ember_expiry": expiry}


func _amount(result: Dictionary) -> float:
	var amount: float = 0.0
	for segment: Dictionary in result.segments: amount += float(segment.raw_amount)
	return amount


func _test_selection_geometry() -> void:
	_expect(Ember.POLICY == {"enabled": true, "radius": 120.0, "max_targets": 8,
		"max_hops": 1, "preserves_expiry": true}, "Published transfer policy is exact")
	var origin := Vector2(-310.0, 470.0)
	var candidates: Array = [_candidate(90, origin), _candidate(6, origin + Vector2(120.01, 0)),
		_candidate(4, origin + Vector2(0, -120)), _candidate(2, origin + Vector2(120, 0)),
		_candidate(5, origin + Vector2(85, 85)), _candidate(3, origin + Vector2(-120, 0)),
		_candidate(1, origin + Vector2(0, 120)), _candidate(7, origin + Vector2.ONE, 0),
		_candidate(8, origin + Vector2.ONE, -1), _candidate(9, origin + Vector2.ONE, 100, 0.000001)]
	var before: PackedByteArray = var_to_bytes(candidates)
	var result: Dictionary = Ember.select_targets(origin, 90, candidates)
	_expect(result.ok and result.target_ids == [1, 2, 3, 4], "120 inclusive center distance excludes diagonal, outside, source, dead and spawning")
	_expect(var_to_bytes(candidates) == before, "Selection does not mutate candidate order or values")
	var crowded: Array = []
	for id: int in range(12, 0, -1):
		crowded.append(_candidate(id, origin + Vector2(float((id + 1) / 2) * 10.0, 0)))
	var expected: Array = [1, 2, 3, 4, 5, 6, 7, 8]
	for shift: int in range(12):
		var rotated: Array = crowded.slice(shift) + crowded.slice(0, shift)
		var ranked: Dictionary = Ember.select_targets(origin, 90, rotated)
		_expect(ranked.ok and ranked.target_ids == expected, "Distance then ID cap is stable for rotated input %d" % shift)
		rotated.reverse()
		_expect(Ember.select_targets(origin, 90, rotated).target_ids == expected, "Distance then ID cap is stable for reversed rotation %d" % shift)
	result.target_ids.clear()
	_expect(Ember.select_targets(origin, 90, candidates).target_ids == [1, 2, 3, 4], "Caller edits to IDs cannot contaminate later selection")
	_expect(Ember.select_targets(origin, 90, []).target_ids.is_empty(), "An empty valid neighborhood produces no targets")
	var same_center: Array = [_candidate(2, origin), _candidate(1, origin)]
	_expect(Ember.select_targets(origin, 90, same_center).target_ids == [1, 2], "Distinct live targets at the source center remain eligible")
	completed = true


func _visible_across_wall(origin: Vector2, target: Vector2) -> bool:
	los_calls.append({"origin": origin, "target": target})
	# A vertical solid segment at origin.x + 30, y in [origin.y - 10, origin.y + 10].
	var delta: Vector2 = target - origin
	if delta.x < 30.0: return true
	var wall_y: float = origin.y + delta.y * (30.0 / delta.x)
	return wall_y < origin.y - 10.0 or wall_y > origin.y + 10.0


func _test_callable_visibility() -> void:
	var origin := Vector2(17, -23)
	var candidates: Array = [_candidate(90, origin), _candidate(91, origin, 0),
		_candidate(92, origin, 10, 1), _candidate(93, origin + Vector2(121, 0))]
	for id: int in range(1, 11): candidates.append(_candidate(id, origin + Vector2(30 + id, 0)))
	for id: int in range(20, 30): candidates.append(_candidate(id, origin + Vector2(0, 70 + id)))
	los_calls.clear()
	var predicate: Callable = Callable(self, "_visible_across_wall")
	_expect(predicate.is_valid(), "LOS fixture uses a valid real Callable")
	var result: Dictionary = Ember.select_targets(origin, 90, candidates, predicate)
	_expect(result.ok and result.target_ids == [20, 21, 22, 23, 24, 25, 26, 27], "Solid wall blocks targets and visible targets fill the cap")
	_expect(los_calls.size() == 20, "LOS runs only for alive non-spawning non-source in-range candidates")
	for call: Dictionary in los_calls:
		_expect(call.origin == origin and call.target != origin and call.target != origin + Vector2(121, 0), "LOS receives the actual origin and candidate center")
	var crossing: Array = [_candidate(1, origin + Vector2(60, 20)), _candidate(2, origin + Vector2(60, 21))]
	_expect(Ember.select_targets(origin, 90, crossing, predicate).target_ids == [2], "Closed wall endpoint blocks; a line above the segment is visible")
	_expect(Ember.select_targets(origin, 90, crossing).target_ids == [1, 2], "Absent optional LOS predicate retains normal radius selection")
	completed = true


func _reject_selection(origin: Variant, source: Variant, candidates: Variant, label: String) -> void:
	var before: PackedByteArray = var_to_bytes(candidates)
	var result: Dictionary = Ember.select_targets(origin, source, candidates)
	_expect(not result.ok and not result.reason.is_empty() and result.target_ids.is_empty(), label + ": rejected without partial IDs")
	_expect(var_to_bytes(candidates) == before, label + ": input is unchanged")


func _test_invalid_selection() -> void:
	var valid: Array = [_candidate(1, Vector2.ONE)]
	for invalid: Variant in [null, true, 1, "origin", [], {}, Vector2(NAN, 0), Vector2(0, INF)]:
		_reject_selection(invalid, 90, valid, "Invalid origin")
	for invalid: Variant in [null, true, false, 1.0, 0, -1, "90", [], {}, INF]:
		_reject_selection(Vector2.ZERO, invalid, valid, "Invalid source ID")
	for invalid: Variant in [null, true, 1, "candidates", {}, PackedInt32Array([1])]:
		_reject_selection(Vector2.ZERO, 90, invalid, "Invalid candidate container")
	for invalid: Variant in [null, true, 1, "candidate", [], {}, {"id": 2}, _candidate(1, Vector2(2, 2))]:
		_reject_selection(Vector2.ZERO, 90, valid + [invalid], "Malformed or duplicate later target")
	var invalid_fields: Dictionary = {
		"id": [null, true, false, 2.0, "2", 0, -1, [], {}, INF],
		"pos": [null, true, 1, "position", [], {}, Vector2(NAN, 0), Vector2(0, INF)],
		"health": [null, true, false, "100", [], {}, NAN, INF, -INF],
		"spawn": [null, true, false, "0", [], {}, NAN, INF, -INF]}
	for key: String in invalid_fields:
		for invalid: Variant in invalid_fields[key]:
			var bad: Dictionary = _candidate(2, Vector2(2, 2))
			bad[key] = invalid
			_reject_selection(Vector2.ZERO, 90, valid + [bad], "Invalid candidate " + key)
	var without_spawn: Dictionary = {"id": 2, "pos": Vector2(2, 2), "health": 1}
	_expect(Ember.select_targets(Vector2.ZERO, 90, [without_spawn]).target_ids == [2], "Missing spawn retains the documented zero default")
	completed = true


func _test_transfer_contract() -> void:
	var runtime := Runtime.new()
	var provenance: Dictionary = _lineage(0, 13.0)
	_expect(runtime.apply("monster", 1, 0, 17.25, 3.0, 10.0, provenance).ok, "Generation-zero source enters storage")
	runtime.advance_target("monster", 1, 10.4)
	var source: Dictionary = runtime.status_for("monster", 1)
	var before: PackedByteArray = var_to_bytes(source)
	var transfer: Dictionary = Ember.transfer(source, 11.75)
	_expect(transfer.ok and transfer.reason.is_empty() and not transfer.burn.is_empty(), "An active generation-zero source produces one transferred burn")
	_expect(transfer.burn.raw_dps == 17.25 and transfer.burn.duration == 1.25, "Transfer copies raw DPS and uses deadline minus event time")
	var inherited: Dictionary = provenance.duplicate(true)
	inherited.ember_generation = 1
	_expect(transfer.burn.provenance == inherited, "Only generation advances; all attribution and original expiry survive")
	_expect(var_to_bytes(source) == before and runtime.status_for("monster", 1) == source, "Transfer does not mutate the source or its storage")
	_expect(runtime.apply("monster", 2, 0, transfer.burn.raw_dps, transfer.burn.duration, 11.75, transfer.burn.provenance).ok, "The copied burn is accepted with the original absolute deadline")
	var next: Dictionary = Ember.transfer(runtime.status_for("monster", 2), 12.0)
	_expect(next.ok and next.reason == "spent_or_expired" and next.burn.is_empty(), "A transferred generation-one status cannot propagate again")
	for at: float in [13.0, 13.01, 1000000.0]:
		var expired: Dictionary = Ember.transfer(source, at)
		_expect(expired.ok and expired.reason == "spent_or_expired" and expired.burn.is_empty(), "At or after expiry no transfer is emitted")
	for status: Dictionary in [{"raw_dps": 30.0, "provenance": {"skill_id": "meteor", "phase": "direct"}}, {"raw_dps": 30.0}, {}]:
		var ordinary: Dictionary = Ember.transfer(status, 11.0)
		_expect(ordinary.ok and ordinary.reason == "not_ember" and ordinary.burn.is_empty(), "Ordinary Ignite or absent Ember metadata never propagates")
	transfer.burn.raw_dps = 999.0
	transfer.burn.duration = 999.0
	transfer.burn.provenance.ember_generation = 0
	transfer.burn.provenance.ember_expiry = 999.0
	transfer.burn.provenance.skill_id = "changed"
	_expect(var_to_bytes(source) == before, "Caller mutation of copied output cannot alter the input")
	_expect(Ember.transfer(source, 11.75).burn == {"raw_dps": 17.25, "duration": 1.25, "provenance": inherited}, "A later transfer is detached from every prior output")
	completed = true


func _reject_transfer(status: Variant, at: Variant, label: String) -> void:
	var before: PackedByteArray = var_to_bytes(status)
	var result: Dictionary = Ember.transfer(status, at)
	_expect(not result.ok and not result.reason.is_empty() and result.burn.is_empty(), label + ": invalid cannot emit a burn")
	_expect(var_to_bytes(status) == before, label + ": source stays byte-identical")


func _test_invalid_transfer() -> void:
	var valid: Dictionary = {"raw_dps": 10.0, "remaining": 3.0, "provenance": _lineage(0, 3.0)}
	for invalid: Variant in [null, true, false, 1, 1.0, "status", []]:
		_reject_transfer(invalid, 1.0, "Invalid source status shape")
	for invalid: Variant in [null, true, false, "1", [], {}, -1, NAN, INF, -INF]:
		_reject_transfer(valid, invalid, "Invalid transfer timestamp")
	for invalid: Variant in [null, true, 1, "provenance", []]:
		var bad: Dictionary = valid.duplicate(true)
		bad.provenance = invalid
		_reject_transfer(bad, 1.0, "Invalid provenance shape")
	var invalid_fields: Dictionary = {
		"ember_generation": [null, true, false, 0.0, 1.0, -1, 2, "0", [], {}, NAN, INF],
		"ember_expiry": [null, true, false, "3", [], {}, NAN, INF, -INF, 0, -1]}
	for key: String in invalid_fields:
		for invalid: Variant in invalid_fields[key]:
			var bad: Dictionary = valid.duplicate(true)
			bad.provenance[key] = invalid
			_reject_transfer(bad, 1.0, "Invalid transfer " + key)
	for missing: String in ["ember_generation", "ember_expiry"]:
		var bad: Dictionary = valid.duplicate(true)
		bad.provenance.erase(missing)
		_reject_transfer(bad, 1.0, "Unpaired transfer lineage missing " + missing)
	for invalid: Variant in [null, true, false, "10", [], {}, NAN, INF, -INF, 0, -1]:
		var bad: Dictionary = valid.duplicate(true)
		bad.raw_dps = invalid
		_reject_transfer(bad, 1.0, "Invalid copied raw DPS")
	completed = true


func _test_runtime_lineage() -> void:
	for generation: int in [0, 1]:
		var runtime := Runtime.new()
		var provenance: Dictionary = _lineage(generation, 4.0)
		var result: Dictionary = runtime.apply("monster", 1, 0, 10, 3, 1, provenance)
		_expect(result.ok and result.applied and result.segments.is_empty(), "Both bounded integer generations are accepted")
		_expect(runtime.has_ember_states() and runtime.status_for("monster", 1).provenance == provenance, "Storage retains exact paired lineage")
		provenance.ember_expiry = 99.0
		_expect(runtime.status_for("monster", 1).provenance.ember_expiry == 4.0, "Runtime clones incoming provenance")
		_expect(runtime.remove("monster", 1).removed and not runtime.has_ember_states(), "Removing last Ember target clears presence query")
	var runtime := Runtime.new()
	runtime.apply("monster", 1, 0, 10, 3, 1, _lineage(0, 4.0))
	runtime.apply("monster", 2, 0, 5, 3, 1, {"phase": "old"})
	var baseline: PackedByteArray = var_to_bytes(runtime.statuses())
	var invalid_provenance: Array = [{"ember_generation": 0}, {"ember_expiry": 5.0}]
	for invalid: Variant in [null, true, false, 0.0, 1.0, -1, 2, "0", [], {}, NAN, INF]:
		invalid_provenance.append({"ember_generation": invalid, "ember_expiry": 5.0})
	for invalid: Variant in [null, true, false, "5", [], {}, NAN, INF, -INF, 0, -1, 4.99, 5.01]:
		invalid_provenance.append({"ember_generation": 0, "ember_expiry": invalid})
	for provenance: Dictionary in invalid_provenance:
		var before: PackedByteArray = var_to_bytes(provenance)
		var rejected: Dictionary = runtime.apply("monster", 1, 99, 100, 3, 2, provenance)
		_expect(not rejected.ok and not rejected.applied and not rejected.reason.is_empty() and rejected.segments.is_empty(), "Malformed lineage/deadline rejects before settlement")
		_expect(var_to_bytes(runtime.statuses()) == baseline, "Malformed Ember apply leaves all actors byte-identical")
		_expect(var_to_bytes(provenance) == before, "Malformed Ember apply leaves caller provenance unchanged")
	var numeric_expiry: Dictionary = {"ember_generation": 1, "ember_expiry": 5}
	_expect(runtime.apply("monster", 3, 0, 1, 3, 2, numeric_expiry).ok, "Finite positive integer expiry is accepted")
	completed = true


func _test_runtime_expiry() -> void:
	var start: float = 0.1234567890123
	var expiry: float = 3.1234567890123
	var dps: float = 17.25
	var split := Runtime.new()
	var whole := Runtime.new()
	for runtime in [split, whole]:
		_expect(runtime.apply("monster", 1, 0, dps, expiry - start, start, _lineage(1, expiry)).ok, "Fractional absolute-deadline fixture admitted")
	var expected: float = _amount(whole.advance_target("monster", 1, 1000.0))
	var actual: float = 0.0
	var previous_end: float = start
	for step: int in range(1, 301):
		var at: float = expiry if step == 300 else start + 3.0 * float(step) / 300.0
		var result: Dictionary = split.advance_target("monster", 1, at)
		_expect(result.ok and result.segments.size() == 1, "Every positive split creates exactly one interval")
		if result.segments.size() != 1: continue
		var segment: Dictionary = result.segments[0]
		_expect(segment.from_time == previous_end and segment.to_time == at and segment.to_time <= expiry, "Split intervals are contiguous and never overrun original deadline")
		_expect(segment.provenance.ember_expiry == expiry and segment.provenance.ember_generation == 1, "Every split retains exact expiry and one-hop lineage")
		actual += float(segment.raw_amount)
		previous_end = float(segment.to_time)
		if step < 300:
			var state: Dictionary = split.status_for("monster", 1)
			_expect(state.remaining == expiry - at and state.provenance.ember_expiry == expiry, "Remaining lifetime derives from absolute expiry at every split")
	_expect(split.is_empty() and not split.has_ember_states() and previous_end == expiry, "Exact deadline reclaims the state with no extra frame")
	_near(actual, expected, "Split time and one advance pay the same total")
	_near(actual, dps * (expiry - start), "No transferred lifetime extension or loss")
	_expect(split.advance_all(1000000.0).segments.is_empty(), "Expired transfers cannot pay twice")
	# Accepted sub-nanosecond arithmetic difference still uses the declared deadline.
	var rounded := Runtime.new()
	var declared: float = 4.0 - 0.0000000005
	_expect(rounded.apply("monster", 1, 0, 10.0, 3.0, 1.0, _lineage(1, declared)).ok, "Representational deadline tolerance is accepted")
	var settled: Dictionary = rounded.advance_all(4.0)
	_expect(settled.segments.size() == 1 and settled.segments[0].to_time == declared and rounded.is_empty(), "Declared expiry remains authoritative after accepted rounding difference")
	completed = true


func _test_runtime_replacement() -> void:
	var runtime := Runtime.new()
	var original: Dictionary = _lineage(0, 3.0, 1)
	var incoming_one: Dictionary = _lineage(1, 4.0, 2)
	runtime.apply("monster", 1, 7, 10.0, 3.0, 0.0, original)
	var weak: Dictionary = runtime.apply("monster", 1, 8, 9.0, 3.0, 1.0, incoming_one)
	_expect(weak.ok and not weak.applied and weak.reason == "weaker", "Weaker transferred burn loses after old interval settles")
	_expect(weak.segments[0].provenance == original and weak.segments[0].source_id == 7, "Weak application settlement retains previous source and generation")
	var state: Dictionary = runtime.status_for("monster", 1)
	_expect(state.provenance == original and state.source_id == 7 and state.remaining == 2.0, "Weaker generation-one burn cannot replace generation zero or extend expiry")
	_expect(not Ember.transfer(state, 1.0).burn.is_empty(), "Winning generation-zero source remains eligible")
	var stronger: Dictionary = runtime.apply("monster", 1, 8, 20.0, 2.5, 1.5, incoming_one)
	_expect(stronger.ok and stronger.applied and stronger.reason == "stronger", "Stronger transferred burn replaces original")
	_expect(stronger.segments[0].provenance == original and stronger.segments[0].source_id == 7, "Stronger replacement settles old attribution first")
	state = runtime.status_for("monster", 1)
	_expect(state.provenance == incoming_one and state.source_id == 8 and state.raw_dps == 20.0, "Strong winner carries generation one and original transfer deadline")
	_expect(Ember.transfer(state, 1.75).burn.is_empty(), "Strong generation-one winner cannot propagate")
	var weak_zero: Dictionary = runtime.apply("monster", 1, 9, 19.0, 3.0, 2.0, _lineage(0, 5.0, 3))
	_expect(not weak_zero.applied and runtime.status_for("monster", 1).provenance == incoming_one, "Weaker generation-zero hit cannot reset transferred winner's lineage")
	var equal_zero: Dictionary = _lineage(0, 5.5, 4)
	var equal: Dictionary = runtime.apply("monster", 1, 9, 20.0, 3.0, 2.5, equal_zero)
	_expect(equal.ok and equal.applied and equal.reason == "equal", "Equal DPS refreshes with latest source")
	_expect(equal.segments[0].provenance == incoming_one and equal.segments[0].source_id == 8, "Equal refresh closes prior generation-one interval")
	state = runtime.status_for("monster", 1)
	_expect(state.provenance == equal_zero and state.source_id == 9 and state.remaining == 3.0, "Equal direct hit wins full new generation-zero provenance")
	_expect(Ember.transfer(state, 3.0).burn.provenance.ember_generation == 1, "A winning new direct burn can transfer once")
	var plain: Dictionary = {"skill_id": "ignite", "cast_id": 10, "phase": "direct"}
	var ordinary: Dictionary = runtime.apply("monster", 1, 0, 30.0, 3.0, 3.0, plain)
	_expect(ordinary.ok and ordinary.applied and ordinary.segments[0].provenance == equal_zero, "Ordinary stronger Ignite settles Ember interval first")
	state = runtime.status_for("monster", 1)
	_expect(state.provenance == plain and not runtime.has_ember_states() and Ember.transfer(state, 3.1).burn.is_empty(), "Ordinary winner removes all stale Ember lineage and cannot propagate")
	completed = true


func _test_legacy_shape_and_copies() -> void:
	var runtime := Runtime.new()
	var plain: Dictionary = {"skill_id": "ignite", "cast_id": 1, "projectile_id": 2, "phase": "direct"}
	_expect(runtime.apply("monster", 1, 0, 10.0, 3.0, 5.0, plain).ok and not runtime.has_ember_states(), "Legacy status remains a plain burn")
	var expected: Dictionary = {"target_kind": "monster", "target_id": 1, "source_id": 0,
		"raw_dps": 10.0, "remaining": 3.0, "last_time": 5.0, "provenance": plain.duplicate(true)}
	_expect(runtime.status_for("monster", 1) == expected, "Legacy new status exact shape has no added expiry or Ember fields")
	var result: Dictionary = runtime.advance_target("monster", 1, 6.25)
	var expected_segment: Dictionary = {"target_kind": "monster", "target_id": 1, "source_id": 0,
		"from_time": 5.0, "to_time": 6.25, "raw_dps": 10.0, "raw_amount": 12.5, "provenance": plain.duplicate(true)}
	_expect(result.segments == [expected_segment], "Legacy segment exact shape and damage remain unchanged")
	expected.remaining = 1.75
	expected.last_time = 6.25
	_expect(runtime.status_for("monster", 1) == expected, "Legacy progressed state exact shape remains unchanged")
	result.segments[0].provenance.phase = "changed"
	var detached: Dictionary = runtime.status_for("monster", 1)
	detached.provenance.skill_id = "changed"
	detached.remaining = 99.0
	var all: Array[Dictionary] = runtime.statuses()
	all[0].provenance.ember_generation = 0
	all.clear()
	_expect(runtime.status_for("monster", 1) == expected and not runtime.has_ember_states(), "Segment, one-state and all-state output edits cannot mutate stored old state")
	_near(_amount(runtime.advance_all(1000.0)), 17.5, "Legacy settlement still stops at the original three-second lifetime")
	_expect(runtime.is_empty(), "Legacy expiry removes status")
	runtime.apply("monster", 1, 0, 10.0, 3.0, 0.0, _lineage(0, 3.0))
	var before: PackedByteArray = var_to_bytes(runtime.statuses())
	detached = runtime.status_for("monster", 1)
	detached.provenance.ember_generation = 1
	detached.provenance.ember_expiry = 999.0
	all = runtime.statuses()
	all[0].provenance.ember_generation = 1
	_expect(var_to_bytes(runtime.statuses()) == before, "Ember status accessors deeply detach lineage")
	result = runtime.advance_all(1.0)
	result.segments[0].provenance.ember_expiry = 999.0
	result.segments[0].provenance.ember_generation = 1
	_expect(runtime.status_for("monster", 1).provenance == _lineage(0, 3.0), "Ember emitted segment provenance never aliases the active state")
	runtime.reset()
	_expect(runtime.is_empty() and not runtime.has_ember_states(), "Reset discards all Ember metadata")
	completed = true
