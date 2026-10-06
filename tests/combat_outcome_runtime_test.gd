extends SceneTree
## Focused v077 observer contract and byte-level frozen v076 damage comparison.
const Runtime = preload("res://scripts/combat/combat_feedback_runtime.gd")
const BASELINE_PATH: String = "res://docs/qa/v077-runtime/combat_feedback_runtime.baseline.gd.txt"
const BASELINE_SHA256: String = "a22cebcb8a73f705c5c976363c0c328c3b3c349ca8357bbf73708e465585a1df"
const EPSILON: float = 0.000000001
var checks: int = 0
var failures: int = 0
var _baseline: GDScript
var _trace_step: int = 0

func _initialize() -> void:
	_check(FileAccess.get_sha256(BASELINE_PATH) == BASELINE_SHA256, "baseline fixture is the immutable 587c195 source")
	_baseline = GDScript.new()
	_baseline.source_code = FileAccess.get_file_as_string(BASELINE_PATH).replace("class_name CombatFeedbackRuntime\n", "")
	var error: Error = _baseline.reload()
	_check(error == OK, "frozen baseline compiles independently without registering a duplicate class")
	if error == OK:
		_test_damage_compatibility(false)
		_test_damage_compatibility(true)
		_test_outcome_schema_and_order()
		_test_fixed_window_and_expiry()
		_test_capacity_and_independence()
		_test_death_flush_and_reset()
		_test_readonly_and_detached()
		_test_invalid_observations()
		_test_observation_overflow_and_rng()
	print("COMBAT_OUTCOME_RUNTIME_TEST_COMPLETE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _bytes_equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(var_to_bytes(actual) == var_to_bytes(expected), label)

func _damage_event(id: int = 1, kind: String = "hit", shield: float = 0.0,
		health: float = 1.0, position: Vector2 = Vector2.ZERO, target_kind: String = "monster") -> Dictionary:
	return {"target_kind":target_kind, "target_id":id, "kind":kind,
		"shield_spent":shield, "health_lost":health, "position":position}

func _event(id: int = 1, outcome: String = "evaded", at: float = 0.0,
		position: Vector2 = Vector2.ZERO) -> Dictionary:
	var result: Dictionary = {"outcome":outcome, "target_kind":"monster", "target_id":id,
		"position":position, "at":at}
	if outcome == "terrain_blocked":
		result.target_kind = "environment"
		result.target_id = 0
	if outcome == "evaded": result.chance = 0.35
	return result

func _damage_state(runtime: Variant) -> Array:
	return [runtime.get("_time"), runtime.get("_epoch"), runtime.get("_next_sequence"),
		runtime.get("_next_id"), runtime.get("_pending"), runtime.get("_visible")]

func _observer_state(runtime: Variant) -> Array:
	return [runtime.get("_next_outcome_id"), runtime.get("_next_observation_id"),
		runtime.get("_outcomes"), runtime.get("_observation_pending"), runtime.get("_observation_visible")]

func _damage_call(pair: Array, method: String, arguments: Array, mixed: bool) -> void:
	_trace_step += 1
	if mixed:
		var outcome: String = ["evaded", "zero_damage", "terrain_blocked", "spawn_protected"][_trace_step % 4]
		# Decreasing/repeating gameplay times cannot order or advance the observer clock.
		var observed: Dictionary = pair[1].observe(_event(_trace_step % 35 + 1, outcome, float(50 - _trace_step % 51)))
		_check(observed.ok or float(pair[1].get("_time")) >= 1.0e308,
			"mixed observation accepted whenever its deadline is representable")
	var expected: Variant = pair[0].callv(method, arguments)
	var actual: Variant = pair[1].callv(method, arguments)
	var label: String = "%s trace %d %s" % ["mixed" if mixed else "legacy", _trace_step, method]
	_bytes_equal(actual, expected, label + " result bytes and error precedence")
	_bytes_equal(pair[1].entries(), pair[0].entries(), label + " public damage bytes")
	_bytes_equal(_damage_state(pair[1]), _damage_state(pair[0]), label + " damage state and sequences")

func _test_damage_compatibility(mixed: bool) -> void:
	var pair: Array = [_baseline.new(), Runtime.new()]
	_trace_step = 0
	_damage_call(pair, "record", [_damage_event(1, "hit", 0.0, 0.0)], mixed)
	_damage_call(pair, "advance", [0], mixed)
	for kind: String in ["hit", "critical", "burn"]:
		_damage_call(pair, "record", [_damage_event(1, kind, 0.25, 0.125, Vector2(3, 4))], mixed)
		_damage_call(pair, "record", [_damage_event(1, kind, 1.0e-200, 1.0e-200, Vector2(-3, -4))], mixed)
	_damage_call(pair, "record", [_damage_event(0, "hit", 2.0, 3.0, Vector2.ZERO, "player")], mixed)
	_damage_call(pair, "advance", [0.2 - EPSILON], mixed)
	_damage_call(pair, "record", [_damage_event(1, "hit", 0.0, 0.0, Vector2(99, 99))], mixed)
	_damage_call(pair, "record", [_damage_event(1, "hit", 0.5, 0.75, Vector2(7, 8))], mixed)
	_damage_call(pair, "advance", [EPSILON], mixed)
	_damage_call(pair, "advance", [0.0], mixed)
	_damage_call(pair, "advance", [0.75 - EPSILON], mixed)
	_damage_call(pair, "advance", [EPSILON], mixed)
	_damage_call(pair, "reset", [], mixed)
	for id: int in range(1, 304):
		_damage_call(pair, "record", [_damage_event(id)], mixed)
	_damage_call(pair, "record", [_damage_event(304, "hit", 0.0, 0.0)], mixed)
	_damage_call(pair, "record", [_damage_event(1, "hit", 1.0, 1.0)], mixed)
	_damage_call(pair, "record", [_damage_event(304, "hit", 1.0e308, 1.0e308)], mixed)
	_damage_call(pair, "advance", [0.1], mixed)
	_damage_call(pair, "record", [_damage_event(304)], mixed)
	_damage_call(pair, "advance", [0.1], mixed)
	_damage_call(pair, "advance", [0.1 + EPSILON], mixed)
	_damage_call(pair, "record", [_damage_event(304, "burn", 1.0, 2.0)], mixed)
	_damage_call(pair, "record", [_damage_event(304, "critical", 2.0, 3.0)], mixed)
	_damage_call(pair, "flush_target", ["monster", 304], mixed)
	_damage_call(pair, "flush_target", ["monster", 304], mixed)
	_damage_call(pair, "flush_target", ["monster", 99999], mixed)
	_damage_call(pair, "advance", [5.0], mixed)
	_damage_call(pair, "reset", [], mixed)
	for value: Variant in [null, true, 1, 1.0, "event", [], Vector2.ZERO]:
		_damage_call(pair, "record", [value], mixed)
	var required: Array = ["target_kind", "target_id", "kind", "shield_spent", "health_lost", "position"]
	for field: String in required:
		var missing: Dictionary = _damage_event()
		missing.erase(field)
		_damage_call(pair, "record", [missing], mixed)
	# Missing-field precedence is verified even when present fields are invalid.
	var multiple: Dictionary = {}
	for field: String in required:
		_damage_call(pair, "record", [multiple.duplicate()], mixed)
		multiple[field] = false
	_damage_call(pair, "record", [multiple], mixed)
	var invalid: Dictionary = {
		"target_kind":["enemy", "", &"monster", 1, true, null],
		"target_id":[0, -1, 1.0, true, false, "1", null],
		"kind":["evaded", "zero_damage", "heal", "", &"hit", 1, true, null],
		"shield_spent":[-1.0, NAN, INF, -INF, true, false, "1", null],
		"health_lost":[-1.0, NAN, INF, -INF, true, false, "1", null],
		"position":[null, [0, 0], Vector3.ZERO, Vector2(INF, 0), Vector2(0, NAN)]}
	for field: String in invalid:
		for value: Variant in invalid[field]:
			var event: Dictionary = _damage_event()
			event[field] = value
			_damage_call(pair, "record", [event], mixed)
	for value: Variant in [-1, 1, 0.0, false, true, "0", null]:
		var event: Dictionary = _damage_event(0, "hit", 0.0, 1.0, Vector2.ZERO, "player")
		event.target_id = value
		_damage_call(pair, "record", [event], mixed)
	for value: Variant in [-1.0, NAN, INF, -INF, true, false, "0.2", null, Vector2.ZERO]:
		_damage_call(pair, "advance", [value], mixed)
	for arguments: Array in [["enemy", 1], [&"monster", 1], [true, 1], [null, 1],
		["monster", 0], ["monster", -1], ["monster", 1.0], ["monster", true],
		["monster", null], ["player", 1], ["player", 0.0], ["player", false], ["environment", 0]]:
		_damage_call(pair, "flush_target", arguments, mixed)
	_damage_call(pair, "record", [_damage_event(1, "hit", 1.0e308, 0.0)], mixed)
	_damage_call(pair, "record", [_damage_event(1, "hit", 1.0e308, 0.0)], mixed)
	_damage_call(pair, "record", [_damage_event(1, "hit", 0.0, 1.0e308)], mixed)
	_damage_call(pair, "advance", [0.2], mixed)
	_damage_call(pair, "advance", [1.0e308], mixed)
	_damage_call(pair, "advance", [1.0e308], mixed)
	_damage_call(pair, "record", [_damage_event()], mixed)
	_damage_call(pair, "record", [_damage_event(1, "hit", 0.0, 0.0)], mixed)
	_damage_call(pair, "reset", [], mixed)
	_damage_call(pair, "record", [_damage_event()], mixed)
	_damage_call(pair, "advance", [0.2], mixed)

func _test_outcome_schema_and_order() -> void:
	var runtime = Runtime.new()
	var outcomes: Array = ["evaded", "zero_damage", "terrain_blocked", "spawn_protected"]
	for index: int in outcomes.size():
		var event: Dictionary = _event(index + 1, outcomes[index], float(100 - index), Vector2(index, -index))
		event.skill_id = "arc"
		event.phase = "primary"
		event.cast_id = 7
		event.projectile_id = index
		event.extra = {"nested":["ignored"]}
		event.amount = 999
		var before: PackedByteArray = var_to_bytes(event)
		_bytes_equal(runtime.observe(event), {"ok":true, "reason":""}, "all four outcomes accepted")
		_check(var_to_bytes(event) == before, "observe never writes into its source")
	var receipts: Array = runtime.outcomes()
	_check(receipts.size() == 4, "every settled event gets its own receipt")
	for index: int in receipts.size():
		var row: Dictionary = receipts[index]
		_check(row.id == index + 1 and row.outcome == outcomes[index], "receipt IDs preserve invocation order despite decreasing at")
		_check(row.at == float(100 - index), "gameplay timestamp stays in receipt")
		_check(row.skill_id == "arc" and row.phase == "primary" and row.cast_id == 7 and row.projectile_id == index, "metadata scalar values retained")
		_check(row.has("chance") == (row.outcome == "evaded"), "only evaded receipt exposes chance")
		_check(not row.has("amount") and not row.has("extra"), "unknown payload fields do not enter receipts")
		_check(row.size() == (11 if row.outcome == "evaded" else 10), "receipt schema is bounded")
	_check(runtime.entries().is_empty() and runtime.observation_entries().is_empty(), "observing never publishes damage or early markers")
	runtime.advance(0.2)
	var markers: Array = runtime.observation_entries()
	_check(markers.size() == 1 and markers[0].target_id == 1, "only evaded gets a marker")
	if markers.size() == 1:
		_bytes_equal(markers[0], {"id":-1, "target_kind":"monster", "target_id":1,
			"kind":"evaded", "count":1, "position":Vector2.ZERO, "age":0.0, "lifetime":0.75}, "marker exact schema has count without damage amount")
	runtime = Runtime.new()
	var defaults: Dictionary = _event(1, "zero_damage")
	defaults.chance = {"ignored":"for non-evaded"}
	_check(runtime.observe(defaults).ok, "irrelevant chance is ignored for non-evaded outcomes")
	var row: Dictionary = runtime.outcomes()[0]
	_check(row.skill_id == "" and row.phase == "" and row.cast_id == 0 and row.projectile_id == 0, "optional metadata always gets scalar defaults")
	_check(not row.has("chance"), "non-evaded cannot leak a chance field")
	for id: int in range(2, 42):
		runtime.observe(_event(id, "zero_damage", float(42 - id)))
	receipts = runtime.outcomes()
	_check(receipts.size() == 32 and receipts[0].id == 10 and receipts[-1].id == 41, "history keeps newest 32 real observations")
	for index: int in range(1, receipts.size()):
		_check(receipts[index].id > receipts[index - 1].id and receipts[index].at < receipts[index - 1].at, "history never sorts by round timestamp")

func _test_fixed_window_and_expiry() -> void:
	var runtime = Runtime.new()
	runtime.observe(_event(1, "evaded", 900.0, Vector2(1, 1)))
	runtime.advance(0.2 - EPSILON)
	_check(runtime.observation_entries().is_empty(), "marker hidden just before 0.20")
	runtime.observe(_event(1, "evaded", 1.0, Vector2(2, 3)))
	var paused: PackedByteArray = var_to_bytes(_observer_state(runtime))
	runtime.advance(0)
	_check(var_to_bytes(_observer_state(runtime)) == paused, "zero delta does not change observation stores")
	runtime.advance(EPSILON)
	var markers: Array = runtime.observation_entries()
	_check(markers.size() == 1, "late merge does not extend fixed 0.20 window")
	if markers.size() == 1:
		_check(markers[0].count == 2 and markers[0].position == Vector2(2, 3), "same monster merges count and latest position")
		_check(markers[0].age == 0.0 and markers[0].lifetime == 0.75, "marker born at exact deadline")
	_check(runtime.outcomes().size() == 2, "merged marker keeps both real history events")
	runtime.advance(0.75 - EPSILON)
	_check(runtime.observation_entries().size() == 1, "marker exists just before absolute lifetime")
	runtime.advance(EPSILON)
	_check(runtime.observation_entries().is_empty(), "marker expires exactly at born plus 0.75")
	_check(runtime.outcomes().size() == 2, "marker expiry retains receipts")
	runtime = Runtime.new()
	runtime.advance(0.2)
	runtime.observe(_event())
	runtime.advance(0.2)
	runtime.advance(0.75)
	_check(runtime.observation_entries().is_empty(), "0.4 plus 0.75 rounding boundary uses absolute expiry")
	runtime = Runtime.new()
	runtime.observe(_event())
	runtime.advance(0.9)
	markers = runtime.observation_entries()
	_check(markers.size() == 1 and absf(markers[0].age - 0.7) <= EPSILON, "long advance publishes at deadline with correct age")
	runtime.advance(0.05)
	_check(runtime.observation_entries().is_empty(), "long advance never extends marker lifetime")
	runtime.observe(_event())
	runtime.advance(10.0)
	_check(runtime.observation_entries().is_empty(), "long advance through birth and expiry leaves no marker")
	runtime = Runtime.new()
	runtime.observe(_event())
	runtime.advance(0.2)
	var first: Dictionary = runtime.observation_entries()[0]
	runtime.observe(_event(1, "evaded", 2.0, Vector2(5, 6)))
	runtime.observe(_event(1, "evaded", 0.0, Vector2(7, 8)))
	_check(runtime.observation_entries()[0].id == first.id, "pending next window does not remove existing marker early")
	runtime.advance(0.2)
	markers = runtime.observation_entries()
	_check(markers.size() == 1 and markers[0].id < first.id and markers[0].count == 2, "new same-target publication replaces previous marker")
	_check(markers[0].age == 0.0 and markers[0].position == Vector2(7, 8), "replacement gets fresh birth and latest position")

func _test_capacity_and_independence() -> void:
	var runtime = Runtime.new()
	for id: int in range(1, 25):
		_check(runtime.observe(_event(id)).ok, "all 24 pending marker slots accept events")
	_check(runtime.get("_observation_pending").size() == 24 and runtime.observation_entries().is_empty(), "pending markers capped independently before first deadline")
	runtime.observe(_event(1, "evaded", 100.0, Vector2(9, 9)))
	_check(runtime.get("_observation_pending").size() == 24, "merge at capacity never evicts")
	runtime.observe(_event(25))
	_check(runtime.get("_observation_pending").size() == 24 and runtime.observation_entries().is_empty(), "25th pending marker drops oldest without publishing early")
	_check(runtime.outcomes().size() == 26 and runtime.outcomes()[0].target_id == 1, "dropped oldest marker retains all real history events")
	var pending_targets: Array = []
	for value: Dictionary in runtime.get("_observation_pending").values(): pending_targets.append(value.target_id)
	_check(not pending_targets.has(1) and pending_targets.has(2) and pending_targets.has(25), "overflow removes oldest pending creation despite recent merge")
	var observer_before: PackedByteArray = var_to_bytes(_observer_state(runtime))
	for id: int in range(1, 305): runtime.record(_damage_event(id))
	_check(var_to_bytes(_observer_state(runtime)) == observer_before, "damage pending overflow cannot alter any observer store or sequence")
	_check(runtime.get("_pending").size() == 303 and runtime.entries().size() == 1, "original 303 damage pending and overflow behavior retained")
	var damage_before: PackedByteArray = var_to_bytes(_damage_state(runtime))
	for id: int in range(26, 66): runtime.observe(_event(id))
	_check(var_to_bytes(_damage_state(runtime)) == damage_before, "observation overflow cannot alter any damage store or sequence")
	_check(runtime.get("_observation_pending").size() == 24 and runtime.outcomes().size() == 32, "history and pending limits hold under repeated overflow")
	runtime.advance(0.2)
	var markers: Array = runtime.observation_entries()
	_check(markers.size() == 8 and markers[0].target_id == 58 and markers[-1].target_id == 65, "visible pool retains newest eight marker publications")
	_check(runtime.entries().size() == 48, "damage visible capacity remains 48 alongside eight markers")
	var output_ids: Dictionary = {}
	for row: Dictionary in runtime.entries() + runtime.observation_entries():
		_check(not output_ids.has(row.id), "damage and observation IDs never collide in a combined list")
		output_ids[row.id] = true
	for index: int in range(1, markers.size()):
		_check(markers[index].id < markers[index - 1].id, "visible observations retain publication order with negative IDs")
	for id: int in range(70, 94): runtime.observe(_event(id))
	_check(runtime.get("_observation_pending").size() == 24 and runtime.observation_entries().size() == 8,
		"pending 24 and visible eight coexist without sharing a capacity")
	runtime.advance(0.2)
	markers = runtime.observation_entries()
	_check(markers.size() == 8 and markers[0].target_id == 86 and markers[-1].target_id == 93, "later publications evict oldest visible marker")
	_check(runtime.get("_observation_pending").is_empty(), "all due pending markers are consumed within bounded pool")

func _test_death_flush_and_reset() -> void:
	var runtime = Runtime.new()
	runtime.observe(_event(7))
	runtime.observe(_event(8))
	runtime.advance(0.2)
	runtime.observe(_event(7))
	runtime.observe(_event(9))
	runtime.record(_damage_event(7, "burn", 0.0, 2.0))
	runtime.record(_damage_event(7, "critical", 1.0, 2.0))
	runtime.record(_damage_event(7, "hit", 0.0, 1.0))
	runtime.record(_damage_event(8))
	var receipts: Array = runtime.outcomes()
	_bytes_equal(runtime.flush_target("monster", 7), {"ok":true, "reason":""}, "death flush succeeds")
	var damage: Array = runtime.entries()
	_check(damage.size() == 3 and damage[0].kind == "burn" and damage[1].kind == "critical" and damage[2].kind == "hit", "death flush still publishes final actual damage in original order")
	_check(runtime.observation_entries().size() == 1 and runtime.observation_entries()[0].target_id == 8, "death clears only selected target's visible miss marker")
	_bytes_equal(runtime.outcomes(), receipts, "death keeps per-event history intact")
	runtime.flush_target("monster", 7)
	runtime.flush_target("monster", 9999)
	runtime.flush_target("player", 0)
	runtime.advance(0.2)
	var targets: Array = []
	for row: Dictionary in runtime.observation_entries(): targets.append(row.target_id)
	_check(targets == [8, 9], "death removes selected pending marker while other targets keep their deadlines")
	var old_outcome_id: int = runtime.outcomes()[-1].id
	var old_marker_id: int = runtime.observation_entries()[-1].id
	runtime.observe(_event(10))
	runtime.reset()
	_check(runtime.outcomes().is_empty() and runtime.observation_entries().is_empty()
		and runtime.get("_observation_pending").is_empty(), "reset clears all observer history, pending and visible state")
	runtime.advance(1.0)
	_check(runtime.observation_entries().is_empty(), "reset leaves no deferred marker")
	runtime.observe(_event(7))
	runtime.advance(0.2)
	_check(runtime.outcomes()[0].id > old_outcome_id and runtime.observation_entries()[0].id < old_marker_id,
		"observer IDs stay unique across reset independently of damage IDs")

func _test_readonly_and_detached() -> void:
	var runtime = Runtime.new()
	var event: Dictionary = _event(3, "evaded", 0.0, Vector2(3, 4))
	event.skill_id = "ice"
	event.phase = "primary"
	event.cast_id = 0
	event.projectile_id = 3
	event.ignored = {"list":[1, 2]}
	var original: Dictionary = event.duplicate(true)
	event.make_read_only()
	var response: Dictionary = runtime.observe(event)
	_bytes_equal(event, original, "read-only input and nested extras accepted without mutation")
	response.ok = false
	response.reason = "changed"
	event.ignored.list[0] = 999
	var receipts: Array = runtime.outcomes()
	var frozen: Array = receipts.duplicate(true)
	receipts[0].target_id = 999
	receipts[0].skill_id = "changed"
	receipts.clear()
	_bytes_equal(runtime.outcomes(), frozen, "history snapshots are detached from source and caller mutations")
	runtime.advance(0.2)
	var markers: Array = runtime.observation_entries()
	var frozen_markers: Array = markers.duplicate(true)
	markers[0].count = 999
	markers[0].position = Vector2(999, 999)
	markers.clear()
	_bytes_equal(runtime.observation_entries(), frozen_markers, "visible marker snapshots are detached")
	runtime.advance(0.1)
	_check(frozen_markers[0].age == 0.0, "previous marker snapshots do not age in place")
	var mutable: Dictionary = _event(4, "evaded", 1.0, Vector2(7, 8))
	runtime.observe(mutable)
	mutable.position = Vector2(0, 0)
	mutable.chance = 1.0
	mutable.outcome = "zero_damage"
	runtime.advance(0.2)
	_check(runtime.observation_entries()[-1].position == Vector2(7, 8), "source mutations cannot rewrite pending marker")
	_check(runtime.outcomes()[-1].chance == 0.35 and runtime.outcomes()[-1].outcome == "evaded", "source mutations cannot rewrite receipt")

func _reject_observation(runtime: Variant, event: Variant, label: String, reason: String = "") -> void:
	var before: PackedByteArray = var_to_bytes([_damage_state(runtime), _observer_state(runtime)])
	var input: PackedByteArray = var_to_bytes(event)
	var result: Dictionary = runtime.observe(event)
	_check(result.size() == 2 and result.ok == false and typeof(result.reason) == TYPE_STRING and not result.reason.is_empty(), label + " rejects with reason")
	if not reason.is_empty(): _check(result.reason == reason, label + " error precedence")
	_check(var_to_bytes([_damage_state(runtime), _observer_state(runtime)]) == before, label + " rejection is fully atomic")
	_check(var_to_bytes(event) == input, label + " invalid source remains untouched")

func _test_invalid_observations() -> void:
	var runtime = Runtime.new()
	runtime.record(_damage_event())
	runtime.observe(_event(1))
	runtime.advance(0.2)
	runtime.observe(_event(2))
	for value: Variant in [null, true, false, 0, 1.0, "event", [], Vector2.ZERO]:
		_reject_observation(runtime, value, "non-dictionary", "Observation event must be a dictionary")
	var required: Array = ["outcome", "target_kind", "target_id", "position", "at"]
	for field: String in required:
		var event: Dictionary = _event()
		event.erase(field)
		_reject_observation(runtime, event, "missing " + field, "Observation event is missing " + field)
	var multiple: Dictionary = {}
	for field: String in required:
		_reject_observation(runtime, multiple, "multiple missing/invalid", "Observation event is missing " + field)
		multiple[field] = false
	var invalid: Dictionary = {
		"outcome":["hit", "critical", "burn", "", "unknown", &"evaded", 1, false, null],
		"target_kind":["player", "environment", &"monster", false, 1, null],
		"target_id":[0, -1, 1.0, true, false, "1", null],
		"position":[null, [], {}, true, Vector3.ZERO, Vector2(INF, 0), Vector2(0, NAN), Vector2(-INF, 0)],
		"at":[-1, -EPSILON, INF, -INF, NAN, true, false, "0", null],
		"chance":[-EPSILON, 1.0 + EPSILON, INF, -INF, NAN, true, false, "0.35", null],
		"skill_id":[null, 1, true, false, &"arc", [], {}],
		"phase":[null, 1, true, false, &"primary", [], {}],
		"cast_id":[null, -1, 1.0, true, false, "1", [], {}, INF, NAN],
		"projectile_id":[null, -1, 1.0, true, false, "1", [], {}, INF, NAN]}
	for field: String in invalid:
		for value: Variant in invalid[field]:
			var event: Dictionary = _event()
			event[field] = value
			_reject_observation(runtime, event, "invalid " + field)
	var missing_chance: Dictionary = _event()
	missing_chance.erase("chance")
	_reject_observation(runtime, missing_chance, "missing chance", "Observation event is missing chance")
	for value: Variant in [1, -1, 0.0, true, false, "0", null]:
		var event: Dictionary = _event(0, "terrain_blocked")
		event.target_id = value
		_reject_observation(runtime, event, "invalid environment ID")
	for outcome: String in ["zero_damage", "spawn_protected"]:
		for field: String in ["target_kind", "target_id"]:
			var event: Dictionary = _event(1, outcome)
			event[field] = "environment" if field == "target_kind" else 0
			_reject_observation(runtime, event, outcome + " needs positive monster target")
	for value: Variant in [0, 1, 0.0, 1.0]:
		var event: Dictionary = _event()
		event.chance = value
		event.at = 0
		_check(runtime.observe(event).ok, "closed chance endpoints and integer time accepted")
	var invalid_readonly: Dictionary = _event()
	invalid_readonly.phase = &"phase"
	invalid_readonly.make_read_only()
	_reject_observation(runtime, invalid_readonly, "read-only malformed metadata")
	var before: PackedByteArray = var_to_bytes([_damage_state(runtime), _observer_state(runtime)])
	_check(not runtime.flush_target("environment", 0).ok, "flush target retains legacy target validation")
	_check(var_to_bytes([_damage_state(runtime), _observer_state(runtime)]) == before, "invalid flush leaves both pools and receipts untouched")
	for value: Variant in [-1.0, INF, NAN, true]:
		before = var_to_bytes([_damage_state(runtime), _observer_state(runtime)])
		_check(not runtime.advance(value).ok, "invalid advance rejected with observers active")
		_check(var_to_bytes([_damage_state(runtime), _observer_state(runtime)]) == before, "invalid advance leaves both pools and receipts untouched")

func _test_observation_overflow_and_rng() -> void:
	var runtime = Runtime.new()
	runtime.advance(1.0e308)
	_reject_observation(runtime, _event(), "unrepresentable marker deadline", "Observation window deadline is not representable")
	_check(runtime.observe(_event(1, "zero_damage", 1.0e308)).ok, "history-only receipt does not need a representable marker deadline")
	var before: PackedByteArray = var_to_bytes([_damage_state(runtime), _observer_state(runtime)])
	_check(not runtime.advance(1.0e308).ok, "clock overflow still rejected with receipt present")
	_check(var_to_bytes([_damage_state(runtime), _observer_state(runtime)]) == before, "clock overflow is atomic for both pools")
	runtime.reset()
	_check(runtime.observe(_event()).ok, "reset restores usable observer deadline")
	runtime.advance(0.2)
	_check(runtime.observation_entries().size() == 1, "observer publishes normally after huge clock reset")
	seed(770077)
	var expected: float = randf()
	seed(770077)
	for id: int in range(1, 40): runtime.observe(_event(id))
	runtime.advance(0.2)
	runtime.flush_target("monster", 39)
	runtime.reset()
	_check(randf() == expected, "observe, publication, overflow, flush and reset consume no RNG")
