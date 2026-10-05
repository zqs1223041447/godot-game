extends SceneTree
## Pure runtime contract checks. Run only after the restored runtime is present:
## godot --headless --path <project> --script res://tests/test_combat_feedback_runtime.gd

const FeedbackRuntime = preload("res://scripts/combat/combat_feedback_runtime.gd")
const EPSILON: float = 0.000000001

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_boundaries_and_fixed_windows()
	_test_categories_targets_and_actual_spends()
	_test_zero_tiny_and_copy_isolation()
	_test_death_flush_reset_and_pause()
	_test_capacity_and_order()
	_test_delta_partitioning()
	_test_invalid_inputs_are_atomic()
	_test_numeric_overflow_is_atomic()
	print("COMBAT_FEEDBACK_RUNTIME_TEST_COMPLETE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _result(result: Variant, expected_ok: bool, message: String) -> void:
	var shaped: bool = result is Dictionary and result.has("ok") and result.has("reason")
	_check(shaped, message + ": result has ok/reason")
	if shaped:
		_check(typeof(result["ok"]) == TYPE_BOOL and result["ok"] == expected_ok,
			message + ": expected ok=%s, got %s" % [expected_ok, result])


func _near(actual: Variant, expected: float, message: String) -> void:
	_check((actual is float or actual is int) and is_finite(float(actual))
		and absf(float(actual) - expected) <= EPSILON, message)


func _event(target_id: int = 1, kind: String = "hit", shield: float = 0.0,
		health: float = 1.0, position: Vector2 = Vector2.ZERO,
		target_kind: String = "monster") -> Dictionary:
	return {"target_kind": target_kind, "target_id": target_id, "kind": kind,
		"shield_spent": shield, "health_lost": health, "position": position}


func _entry(runtime: Variant, target_kind: String, target_id: int, kind: String) -> Dictionary:
	for entry in runtime.entries():
		if entry["target_kind"] == target_kind and entry["target_id"] == target_id and entry["kind"] == kind:
			return entry
	_check(false, "missing visible entry %s/%d/%s" % [target_kind, target_id, kind])
	return {}


func _test_boundaries_and_fixed_windows() -> void:
	var runtime = FeedbackRuntime.new()
	_result(runtime.record(_event(1, "hit", 2.0, 3.0)), true, "first hit accepted")
	_check(runtime.entries().is_empty(), "record only queues feedback")
	_result(runtime.advance(0.2 - EPSILON), true, "advance just before deadline")
	_check(runtime.entries().is_empty(), "nothing published before 0.20 seconds")
	_result(runtime.record(_event(1, "hit", 1.0, 4.0, Vector2(9, 7))), true, "late hit joins fixed window")
	_result(runtime.advance(EPSILON), true, "advance exactly to deadline")
	var entry = _entry(runtime, "monster", 1, "hit")
	if not entry.is_empty():
		_near(entry["amount"], 10.0, "fixed window sums actual spends")
		_check(entry["hit_count"] == 2, "hit count includes both events")
		_check(entry["position"] == Vector2(9, 7), "latest positive event position wins")
		_near(entry["age"], 0.0, "birth is the fixed deadline")
		_near(entry["lifetime"], 0.75, "visible lifetime is 0.75 seconds")
	_result(runtime.advance(0.75 - EPSILON), true, "advance just before expiry")
	_check(runtime.entries().size() == 1, "visible before absolute expiry")
	_result(runtime.advance(EPSILON), true, "advance to exact expiry")
	_check(runtime.entries().is_empty(), "entry expires at absolute born plus 0.75")

	runtime = FeedbackRuntime.new()
	_result(runtime.advance(0.2), true, "offset clock before rounding regression")
	_result(runtime.record(_event()), true, "queue at 0.2")
	_result(runtime.advance(0.2), true, "publish at 0.4")
	_check(runtime.entries().size() == 1, "0.4 birth exists")
	_result(runtime.advance(0.75), true, "advance from 0.4 to 0.4 plus 0.75")
	_check(runtime.entries().is_empty(), "absolute expiry avoids 1.15 minus 0.4 rounding residue")

	runtime = FeedbackRuntime.new()
	_result(runtime.record(_event()), true, "queue before long delta")
	_result(runtime.advance(0.9), true, "long delta publishes at earlier deadline")
	entry = _entry(runtime, "monster", 1, "hit")
	if not entry.is_empty():
		_near(entry["age"], 0.7, "long delta age uses deadline, not end of delta")
	_result(runtime.advance(0.05), true, "long delta entry reaches expiry")
	_check(runtime.entries().is_empty(), "long delta does not extend lifetime")

	runtime = FeedbackRuntime.new()
	_result(runtime.record(_event()), true, "queue before fully elapsed long delta")
	_result(runtime.advance(5.0), true, "advance beyond publication and expiry")
	_check(runtime.entries().is_empty(), "expired pending output is never left visible")


func _test_categories_targets_and_actual_spends() -> void:
	var runtime = FeedbackRuntime.new()
	_result(runtime.record(_event(1, "hit", 2.0, 0.0)), true, "shield-only hit")
	_result(runtime.record(_event(1, "hit", 0.0, 3.0)), true, "health-only hit")
	_result(runtime.record(_event(1, "critical", 0.5, 2.5)), true, "critical category")
	_result(runtime.record(_event(1, "burn", 0.25, 0.75)), true, "burn category")
	_result(runtime.record(_event(1, "burn", 0.5, 0.5)), true, "second burn")
	_result(runtime.record(_event(2, "hit", 0.0, 9.0)), true, "second monster")
	_result(runtime.record(_event(0, "hit", 4.0, 1.0, Vector2.ZERO, "player")), true, "player target")
	var metadata_event = _event(3, "hit", 1.0, 2.0)
	metadata_event["damage"] = 999999.0
	metadata_event["overkill"] = 999999.0
	metadata_event["critical_multiplier"] = 200.0
	_result(runtime.record(metadata_event), true, "irrelevant nominal damage metadata ignored")
	_result(runtime.advance(0.2), true, "publish all separate groups")
	_check(runtime.entries().size() == 6, "categories and target identities remain separate")
	var expectations = [
		["monster", 1, "hit", 5.0, 2.0, 3.0, 2],
		["monster", 1, "critical", 3.0, 0.5, 2.5, 1],
		["monster", 1, "burn", 2.0, 0.75, 1.25, 0],
		["monster", 2, "hit", 9.0, 0.0, 9.0, 1],
		["player", 0, "hit", 5.0, 4.0, 1.0, 1],
		["monster", 3, "hit", 3.0, 1.0, 2.0, 1],
	]
	var ids: Dictionary = {}
	for expected in expectations:
		var entry = _entry(runtime, expected[0], expected[1], expected[2])
		if entry.is_empty():
			continue
		for key in ["id", "target_kind", "target_id", "kind", "amount", "shield_spent", "health_lost", "hit_count", "position", "age", "lifetime"]:
			_check(entry.has(key), "entry exposes " + key)
		_near(entry["amount"], expected[3], "actual amount for %s" % [expected])
		_near(entry["shield_spent"], expected[4], "shield spend for %s" % [expected])
		_near(entry["health_lost"], expected[5], "health loss for %s" % [expected])
		_check(entry["hit_count"] == expected[6], "hit count for %s" % [expected])
		_check(typeof(entry["id"]) == TYPE_INT and not ids.has(entry["id"]), "output IDs are distinct integers")
		ids[entry["id"]] = true


func _test_zero_tiny_and_copy_isolation() -> void:
	var runtime = FeedbackRuntime.new()
	_result(runtime.record(_event(1, "hit", 0.0, 0.0)), true, "zero spend succeeds inertly")
	_result(runtime.advance(0.2), true, "advance after zero event")
	_check(runtime.entries().is_empty(), "zero event creates no output")
	var event = _event(1, "hit", 0.25, 0.125, Vector2(3, 4))
	event["metadata"] = {"nested": ["ignored"]}
	_result(runtime.record(event), true, "record detached source")
	event["health_lost"] = 200.0
	event["position"] = Vector2(90, 90)
	event["metadata"]["nested"][0] = "changed"
	_result(runtime.record(_event(1, "hit", 0.0, 0.0, Vector2(80, 80))), true, "zero event cannot alter pending position or hit count")
	_result(runtime.advance(0.2), true, "publish detached source")
	var entry = _entry(runtime, "monster", 1, "hit")
	if not entry.is_empty():
		_near(entry["amount"], 0.375, "fractional values are not rounded")
		_check(entry["position"] == Vector2(3, 4) and entry["hit_count"] == 1, "input mutation and zero event are inert")
		_check(not entry.has("metadata"), "metadata is not retained in output")
	var snapshot = runtime.entries()
	var original = snapshot.duplicate(true)
	if not snapshot.is_empty():
		snapshot[0]["amount"] = 9999.0
		snapshot[0]["position"] = Vector2(99, 99)
		snapshot[0]["extra"] = {"mutable": [1, 2]}
		snapshot.clear()
	_check(runtime.entries() == original, "entries returns detached arrays and dictionaries")
	_result(runtime.advance(0.1), true, "advance after snapshot")
	if not original.is_empty():
		_near(original[0]["age"], 0.0, "old snapshots do not change as clock advances")

	runtime = FeedbackRuntime.new()
	var tiny: float = 1.0e-200
	_result(runtime.record(_event(1, "burn", tiny, tiny)), true, "tiny positive float accepted")
	_result(runtime.advance(0.2), true, "publish tiny float")
	entry = _entry(runtime, "monster", 1, "burn")
	if not entry.is_empty():
		_check(entry["amount"] > 0.0 and entry["amount"] == tiny + tiny, "tiny positive spends are preserved without epsilon filtering")
		_check(entry["hit_count"] == 0, "tiny burn has zero hit count")
	runtime = FeedbackRuntime.new()
	var integer_event = _event()
	integer_event["shield_spent"] = 2
	integer_event["health_lost"] = 3
	_result(runtime.record(integer_event), true, "integer resource spends are valid numbers")
	_result(runtime.advance(0), true, "integer zero advance is valid")
	_result(runtime.flush_target("monster", 1), true, "publish integer resource spends")
	entry = _entry(runtime, "monster", 1, "hit")
	if not entry.is_empty():
		_near(entry["amount"], 5.0, "integer resource spends retain their actual total")


func _test_death_flush_reset_and_pause() -> void:
	var runtime = FeedbackRuntime.new()
	_result(runtime.record(_event(7, "burn", 0.0, 2.0)), true, "queue death burn first")
	_result(runtime.record(_event(7, "critical", 1.0, 2.0)), true, "queue death critical second")
	_result(runtime.record(_event(8, "hit", 0.0, 8.0)), true, "queue unrelated target")
	_result(runtime.record(_event(7, "hit", 0.0, 1.0)), true, "queue final positive hit")
	_result(runtime.advance(0.1), true, "advance before death")
	_result(runtime.flush_target("monster", 7), true, "death publishes final positive events")
	var entries = runtime.entries()
	_check(entries.size() == 3, "death flush affects only selected target")
	if entries.size() == 3:
		_check(entries[0]["kind"] == "burn" and entries[1]["kind"] == "critical" and entries[2]["kind"] == "hit", "death flush preserves pending creation order")
		for entry in entries:
			_near(entry["age"], 0.0, "death outputs are born now")
		_check(entries[0]["id"] < entries[1]["id"] and entries[1]["id"] < entries[2]["id"], "death outputs have increasing sequence IDs")
	_result(runtime.flush_target("monster", 7), true, "repeat death flush is safe")
	_check(runtime.entries() == entries, "repeat flush creates no duplicates")
	_result(runtime.flush_target("monster", 9999), true, "unknown valid target flush is harmless")
	_result(runtime.advance(0.0), true, "paused simulation accepts zero advance")
	_check(runtime.entries() == entries, "paused time does not age or publish anything")
	_result(runtime.advance(0.1), true, "resume simulation")
	_check(runtime.entries().size() == 4, "unrelated target retains original deadline")
	var old_id: int = 0
	for entry in runtime.entries():
		old_id = maxi(old_id, entry["id"])
	_result(runtime.record(_event(9)), true, "queue pending event before reset")
	runtime.reset()
	_check(runtime.entries().is_empty(), "reset clears visible outputs")
	_result(runtime.advance(0.2), true, "advance after reset")
	_check(runtime.entries().is_empty(), "reset clears pending outputs")
	_result(runtime.record(_event(7)), true, "new epoch accepts old target identity")
	_result(runtime.advance(0.2), true, "new epoch publishes normally")
	var fresh = _entry(runtime, "monster", 7, "hit")
	if not fresh.is_empty():
		_check(fresh["id"] > old_id, "reset never reuses output IDs")
		_near(fresh["age"], 0.0, "reset clock supports a fresh window")


func _test_capacity_and_order() -> void:
	var runtime = FeedbackRuntime.new()
	var accepted: bool = true
	for id in range(1, 304):
		accepted = bool(runtime.record(_event(id))["ok"]) and accepted
	_check(accepted, "all 303 pending slots accept distinct targets")
	_check(runtime.entries().is_empty(), "capacity 303 does not flush early")
	_result(runtime.record(_event(304, "hit", 0.0, 0.0)), true, "zero event at pending capacity is inert")
	_check(runtime.entries().is_empty(), "zero event does not evict pending bucket")
	_result(runtime.record(_event(1, "hit", 1.0, 1.0)), true, "same-key merge consumes no pending slot")
	_check(runtime.entries().is_empty(), "same-key merge does not evict pending bucket")
	_result(runtime.advance(0.1), true, "offset overflow publication clock")
	_result(runtime.record(_event(304)), true, "304th pending key accepted after oldest publication")
	var entries = runtime.entries()
	_check(entries.size() == 1, "one oldest pending bucket publishes on overflow")
	if entries.size() == 1:
		_check(entries[0]["target_id"] == 1, "pending overflow selects oldest creation")
		_near(entries[0]["amount"], 3.0, "overflow publishes full aggregate")
		_near(entries[0]["age"], 0.0, "overflow publication is born at current time")
	_result(runtime.advance(0.1), true, "original pending deadlines publish")
	entries = runtime.entries()
	_check(entries.size() == 48, "visible list is capped at 48")
	if entries.size() == 48:
		_check(entries[0]["target_id"] == 256 and entries[47]["target_id"] == 303, "visible eviction keeps newest 48 output sequences")
		var ordered: bool = true
		for index in range(1, entries.size()):
			ordered = ordered and entries[index - 1]["id"] < entries[index]["id"]
		_check(ordered, "retained visible entries follow increasing output sequence")
	_result(runtime.advance(0.1 + EPSILON), true, "new overflow key reaches its own deadline")
	entries = runtime.entries()
	_check(entries.size() == 48, "visible cap survives later deadline")
	if entries.size() == 48:
		_check(entries[0]["target_id"] == 257 and entries[47]["target_id"] == 304, "next publication evicts oldest output")

	runtime = FeedbackRuntime.new()
	_result(runtime.record(_event(1)), true, "first same-key window")
	_result(runtime.advance(0.2), true, "publish first same-key window")
	var first = _entry(runtime, "monster", 1, "hit")
	_result(runtime.record(_event(1, "hit", 2.0, 3.0)), true, "second same-key window")
	_result(runtime.advance(0.2), true, "publish second same-key window")
	entries = runtime.entries()
	_check(entries.size() == 1, "new window replaces older visible same-key output")
	if entries.size() == 1 and not first.is_empty():
		_check(entries[0]["id"] > first["id"], "replacement gets a fresh monotonic ID")
		_near(entries[0]["amount"], 5.0, "replacement amount belongs only to new window")
		_check(entries[0]["hit_count"] == 1, "replacement hit count starts afresh")


func _test_delta_partitioning() -> void:
	var large = FeedbackRuntime.new()
	var split = FeedbackRuntime.new()
	for runtime in [large, split]:
		_result(runtime.record(_event(1, "critical", 1.0, 2.0)), true, "partition first key")
		_result(runtime.advance(0.1), true, "partition stagger clock")
		_result(runtime.record(_event(2, "burn", 0.5, 0.5)), true, "partition second key")
	_result(large.advance(0.8), true, "one large advance")
	for delta in [0.1, 0.1, 0.2, 0.4]:
		_result(split.advance(delta), true, "equivalent split advance")
	_compare_entries(large.entries(), split.entries(), "large versus split advance")
	_result(large.advance(0.2), true, "large clock final expiry")
	_result(split.advance(0.2), true, "split clock final expiry")
	_check(large.entries().is_empty() and split.entries().is_empty(), "both delta partitions expire all outputs")


func _compare_entries(actual: Array, expected: Array, message: String) -> void:
	_check(actual.size() == expected.size(), message + ": size")
	if actual.size() != expected.size():
		return
	for index in actual.size():
		for key in ["id", "target_kind", "target_id", "kind", "amount", "shield_spent", "health_lost", "hit_count", "position", "lifetime"]:
			_check(actual[index][key] == expected[index][key], message + ": " + key)
		_near(actual[index]["age"], expected[index]["age"], message + ": age")


func _seed_atomic_pair() -> Array:
	var pair = [FeedbackRuntime.new(), FeedbackRuntime.new()]
	for runtime in pair:
		runtime.record(_event(1, "critical", 1.0, 2.0))
		runtime.flush_target("monster", 1)
		runtime.record(_event(2, "hit", 2.0, 3.0, Vector2(7, 8)))
	return pair


func _reject_atomically(method: String, arguments: Array, label: String) -> void:
	var pair = _seed_atomic_pair()
	_result(pair[0].callv(method, arguments), false, label)
	_check(pair[0].entries() == pair[1].entries(), label + ": visible state unchanged")
	for runtime in pair:
		runtime.advance(0.2)
	_check(pair[0].entries() == pair[1].entries(), label + ": clock, pending values, and output sequence unchanged")


func _test_invalid_inputs_are_atomic() -> void:
	for value in [null, true, 1, 1.0, "event", [], Vector2.ZERO]:
		_reject_atomically("record", [value], "reject non-dictionary event %s" % [value])
	for key in ["target_kind", "target_id", "kind", "shield_spent", "health_lost", "position"]:
		var event = _event()
		event.erase(key)
		_reject_atomically("record", [event], "reject missing " + key)
	var invalid_fields = {
		"target_kind": ["enemy", "", &"monster", 1, true, null],
		"target_id": [0, -1, 1.0, true, false, "1", null],
		"kind": ["heal", "", &"hit", 1, true, null],
		"shield_spent": [-1.0, NAN, INF, -INF, true, false, "1", null],
		"health_lost": [-1.0, NAN, INF, -INF, true, false, "1", null],
		"position": [null, [0, 0], Vector3.ZERO, Vector2(INF, 0), Vector2(0, NAN)],
	}
	for key in invalid_fields:
		for value in invalid_fields[key]:
			var event = _event()
			event[key] = value
			_reject_atomically("record", [event], "reject invalid %s=%s" % [key, value])
	for value in [-1, 1, 0.0, false, true, "0", null]:
		var event = _event(0, "hit", 0.0, 1.0, Vector2.ZERO, "player")
		event["target_id"] = value
		_reject_atomically("record", [event], "reject invalid player ID %s" % [value])
	for value in [-1.0, NAN, INF, -INF, true, false, "0.2", null, Vector2.ZERO]:
		_reject_atomically("advance", [value], "reject invalid advance %s" % [value])
	for arguments in [["enemy", 1], [&"monster", 1], [true, 1], [null, 1],
			["monster", 0], ["monster", -1], ["monster", 1.0], ["monster", true],
			["monster", null], ["player", 1], ["player", 0.0], ["player", false]]:
		_reject_atomically("flush_target", arguments, "reject invalid target flush %s" % [arguments])


func _test_numeric_overflow_is_atomic() -> void:
	_reject_atomically("record", [_event(2, "hit", 1.0e308, 1.0e308)], "reject event whose total overflows")
	for second in [_event(1, "hit", 1.0e308, 0.0), _event(1, "hit", 0.0, 1.0e308)]:
		var runtime = FeedbackRuntime.new()
		_result(runtime.record(_event(1, "hit", 1.0e308, 0.0, Vector2(1, 2))), true, "finite huge first event accepted")
		_result(runtime.record(second), false, "reject aggregate component or total overflow")
		_result(runtime.advance(0.2), true, "publish after rejected aggregate overflow")
		var entry = _entry(runtime, "monster", 1, "hit")
		if not entry.is_empty():
			_check(entry["amount"] == 1.0e308 and entry["shield_spent"] == 1.0e308 and entry["health_lost"] == 0.0, "aggregate overflow retains prior finite amounts")
			_check(entry["hit_count"] == 1 and entry["position"] == Vector2(1, 2), "aggregate overflow retains prior count and position")
	var runtime = FeedbackRuntime.new()
	_result(runtime.advance(1.0e308), true, "huge finite advance accepted")
	_result(runtime.advance(1.0e308), false, "reject simulated clock overflow")
	_result(runtime.advance(0.0), true, "rejected clock overflow leaves a usable finite clock")
	_check(runtime.entries().is_empty(), "clock overflow creates no outputs")
	runtime.reset()
	_result(runtime.record(_event()), true, "reset restores a usable window after huge clock")
	_result(runtime.advance(0.2), true, "reset clock restarts deadline from zero")
	_check(runtime.entries().size() == 1, "reset clears huge clock as well as stores")

	runtime = FeedbackRuntime.new()
	for id in range(1, 304):
		runtime.record(_event(id))
	_result(runtime.record(_event(304, "hit", 1.0e308, 1.0e308)), false, "invalid overflowing event rejected at full pending capacity")
	_check(runtime.entries().is_empty(), "invalid event cannot force capacity publication")
	_result(runtime.flush_target("monster", 1), true, "oldest pending survives rejected full-capacity event")
	var surviving = _entry(runtime, "monster", 1, "hit")
	if not surviving.is_empty():
		_near(surviving["amount"], 1.0, "oldest pending value survives invalid overflow")
