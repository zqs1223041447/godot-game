extends SceneTree
## Pure scheduler coverage. Baseline is the exact 70b75bc runtime without class_name.
const Runtime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Baseline = preload("res://docs/qa/v073-telegraph-pause/baseline_runtime.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Factory = preload("res://scripts/monsters/monster_runtime.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Admission = preload("res://scripts/world/map_admission.gd")
const CENTER := Vector2(345.25, 456.5)
var checks := 0
var failures := 0


func _initialize() -> void:
	_test_legacy_native_bytes()
	_test_windup_and_recovery()
	_test_echo_sequence()
	_test_resumed_order()
	_test_epsilon()
	_test_atomic_validation()
	_test_cancellation()
	_test_capacity_copies_and_rng()
	print("Frost Lock telegraph pause: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _near(actual: float, expected: float, label: String) -> void:
	_expect(is_finite(actual) and absf(actual - expected) < 0.000000000001, label)


func _enemy(id: int = 1, kind: String = "normal") -> Dictionary:
	var result: Dictionary
	if kind in ["old_garden", "broken_ruins", "sunwell_terrace"]:
		var map: Dictionary = Maps.compile(kind, [], []).profile
		result = Admission.create_root(Factory.new(), map, "rift_warden", map.wave,
			Vector2(111, 222), "map_boss", "", [], true).enemy
		result.id = id
		result.root_id = id
		result.attack_speed = Monsters.BASE_ATTACK_SPEED
	else:
		result = {"id": id, "health": 100.0, "shield": 10.0, "spawn": 0.0,
			"damage": 20.0, "contact_weights": {"physical": 0.5, "fire": 0.5},
			"pos": Vector2(111, 222), "extra": {"untouched": [1, 2, 3]}}
		if kind != "normal": result.template_id = kind
	result.spawn = 0.0
	return result


func _start(runtime: RefCounted, enemy: Dictionary) -> Dictionary:
	if enemy.has("map_boss_attack_id"):
		var policy: Dictionary = Monsters.telegraph_policy(enemy)
		return runtime.start(enemy, CENTER, policy.profile, policy.visual_pattern)
	return runtime.start(enemy, CENTER)


func _snapshot(runtime: RefCounted) -> Array:
	return [runtime.get("_states").duplicate(true), runtime.get("_next_attack_id"),
		runtime.active_count(), runtime.state_for(1), runtime.state_for(2),
		runtime.has_burning_actions(), runtime.has_timed_sequence_actions()]


func _legacy_record(runtime: RefCounted, kind: String, steps: Array, timed: bool, explicit_empty: bool) -> PackedByteArray:
	var enemy := _enemy(1, kind)
	var other := _enemy(2)
	var rows: Array = [_start(runtime, enemy), runtime.start(other, CENTER + Vector2.ONE, {"windup_seconds": 0.25}), _snapshot(runtime)]
	seed(736073)
	for delta: float in steps:
		rows.append(runtime.advance(delta, [other, enemy], timed, {}) if explicit_empty else runtime.advance(delta, [other, enemy], timed))
		rows.append(_snapshot(runtime))
	rows.append(randi())
	rows.append(enemy)
	runtime.reset()
	rows.append(_start(runtime, enemy))
	rows.append(_snapshot(runtime))
	return var_to_bytes(rows)


func _test_legacy_native_bytes() -> void:
	var partitions: Array = [
		[0.0, 0.1, 0.15, 0.4499999995, 0.0000000005, 0.1, 0.8, 1.2, 10.0],
		[0.0, -1.0, NAN, INF, -INF, 0.7, 0.1, 0.8, 1.9],
		[1.0e300], [0.8, 0.8, 1.9], [0.25, 0.45, 1.2], [0.699999998, 0.0000000015, 0.0000000005, 10.0],
	]
	var small_steps: Array = []
	for index: int in range(240): small_steps.append(1.0 / 60.0)
	partitions.append(small_steps)
	for kind: String in ["normal", "ember_guard", "storm_skitter", "old_garden", "broken_ruins", "sunwell_terrace"]:
		for timed: bool in [false, true]:
			for steps: Array in partitions:
				var expected := _legacy_record(Baseline.new(), kind, steps, timed, false)
				for explicit_empty: bool in [false, true]:
					_expect(_legacy_record(Runtime.new(), kind, steps, timed, explicit_empty) == expected,
						"No-pause native Variant bytes match 70b75bc: %s timed=%s explicit=%s" % [kind, timed, explicit_empty])
	# Legacy malformed-universe reset and malformed-delta cancellation also remain exact.
	for delta: float in [0.0, -1.0, NAN, INF, -INF, 0.7, 1.0e300]:
		for live: Variant in [null, {}, true, [null], [{}], [_enemy(), _enemy()], [], [_enemy()]]:
			for explicit_empty: bool in [false, true]:
				var original := Baseline.new()
				var current := Runtime.new()
				_start(original, _enemy())
				_start(current, _enemy())
				var expected: Array = [original.advance(delta, live, true), _snapshot(original)]
				var actual: Array = [current.advance(delta, live, true, {}) if explicit_empty else current.advance(delta, live, true), _snapshot(current)]
				_expect(var_to_bytes(actual) == var_to_bytes(expected), "Empty pause batch retains exact legacy invalid-input behavior")


func _test_windup_and_recovery() -> void:
	var runtime := Runtime.new()
	var enemy := _enemy()
	_expect(_start(runtime, enemy).ok, "Normal attack starts")
	runtime.advance(0.5, [enemy])
	var before := var_to_bytes(_snapshot(runtime))
	enemy.pos = Vector2(999, 999)
	_expect(runtime.advance(10.0, [enemy], true, {1: 10.0}).is_empty(), "Fully frozen windup emits nothing")
	_expect(var_to_bytes(_snapshot(runtime)) == before, "Fully frozen windup keeps every attack field")
	_expect(not runtime.start(enemy, Vector2.ZERO).ok, "Freeze never releases the source for retargeting")
	var events := runtime.advance(0.75, [enemy], true, {1: 0.5})
	_expect(events.size() == 1, "Partial thaw emits the one pending normal attack")
	if events.size() != 1: return
	_near(events[0].step_time, 0.7, "Normal deadline includes frozen frame prefix")
	_expect(events[0].center == CENTER and events[0].attack_id == 1, "Normal attack retains center and identity")
	_near(runtime.state_for(1).elapsed, 0.75, "Only thawed remainder advances the action clock")
	_expect(runtime.state_for(1).phase == "recovery", "Partial thaw carries its remainder into recovery")
	before = var_to_bytes(_snapshot(runtime))
	_expect(runtime.advance(2.0, [enemy], false, {1: 2.0}).is_empty(), "Frozen recovery emits nothing")
	_expect(var_to_bytes(_snapshot(runtime)) == before, "Fully frozen recovery keeps every field")
	_expect(runtime.advance(1.5, [enemy], true, {1: 0.5}).is_empty() and runtime.active_count() == 1, "Partial recovery thaw preserves the remaining recovery")
	_near(runtime.state_for(1).elapsed, 1.75, "Recovery advances only by unfrozen time")
	_expect(runtime.advance(0.15, [enemy]).is_empty() and runtime.active_count() == 0, "Recovery completes once its remaining time passes")
	for kind: String in ["normal", "ember_guard", "storm_skitter"]:
		runtime = Runtime.new()
		enemy = _enemy(1, kind)
		_start(runtime, enemy)
		events = runtime.advance(1.0, [enemy], false, {1: 0.25})
		_expect(events.size() == 1 and events[0].has("step_time") == (kind != "normal"), "Pause preserves the optional timing-field contract: " + kind)
		if kind != "normal" and events.size() == 1:
			_near(events[0].step_time, 0.95, "Status-bearing event receives the same thaw offset")


func _test_echo_sequence() -> void:
	var runtime := Runtime.new()
	var enemy := _enemy(1, "sunwell_terrace")
	_expect(_start(runtime, enemy).ok, "Echo starts through canonical map authority")
	runtime.advance(0.4, [enemy])
	var before := var_to_bytes(_snapshot(runtime))
	_expect(runtime.advance(1.0, [enemy], false, {1: 1.0}).is_empty() and var_to_bytes(_snapshot(runtime)) == before, "Freeze preserves first Echo warning and zero emitted pulses")
	var first := runtime.advance(1.0, [enemy], false, {1: 0.6})
	_expect(first.size() == 1 and first[0].pulse_index == 0, "Thaw emits only the first Echo pulse")
	if first.size() != 1: return
	_near(first[0].step_time, 1.0, "First Echo pulse has full frame-relative time")
	_expect(runtime.state_for(1).pulse_index == 1 and runtime.state_for(1).pulses_emitted == 1, "Second Echo warning retains the emitted count")
	_near(runtime.state_for(1).elapsed, 0.0, "Second warning starts at its existing sequence boundary")
	before = var_to_bytes(_snapshot(runtime))
	enemy.pos += Vector2(100, -100)
	_expect(runtime.advance(4.0, [enemy], false, {1: 4.0}).is_empty() and var_to_bytes(_snapshot(runtime)) == before, "Freeze between pulses preserves both clocks, phase and center")
	var second := runtime.advance(2.0, [enemy], false, {1: 0.5})
	_expect(second.size() == 1 and second[0].pulse_index == 1, "Thaw emits only the remaining Echo pulse")
	if second.size() != 1: return
	_near(second[0].step_time, 1.3, "Second Echo pulse receives frozen prefix")
	_expect(first[0].center == CENTER and second[0].center == CENTER and first[0].attack_id == second[0].attack_id, "Both Echo pulses retain the original center and identity")
	_expect(runtime.state_for(1).phase == "recovery" and runtime.state_for(1).pulses_emitted == 2, "Echo enters recovery after exactly two pulses")
	before = var_to_bytes(_snapshot(runtime))
	_expect(runtime.advance(5.0, [enemy], false, {1: 5.0}).is_empty() and var_to_bytes(_snapshot(runtime)) == before, "Echo recovery pauses without replaying a pulse")
	_expect(runtime.advance(100.0, [enemy], false, {1: 90.0}).is_empty() and runtime.active_count() == 0, "Thawed Echo recovery completes without another pulse")


func _test_resumed_order() -> void:
	var runtime := Runtime.new()
	var echo := _enemy(9, "sunwell_terrace")
	var first := _enemy(2)
	var middle := _enemy(5)
	_start(runtime, echo)
	runtime.start(first, CENTER, {"windup_seconds": 1.0})
	runtime.start(middle, CENTER, {"windup_seconds": 1.75})
	var events := runtime.advance(2.0, [middle, echo, first], true, {9: 0.2})
	_expect(events.size() == 4, "Mixed thaw frame emits normal actions and both Echo pulses")
	if events.size() != 4: return
	_expect([events[0].source_id, events[1].source_id, events[2].source_id, events[3].source_id] == [2, 9, 5, 9], "Resumed deadlines sort globally, retaining ascending source identity for ties")
	for index: int in range(4):
		_near(events[index].step_time, [1.0, 1.0, 1.75, 1.8][index], "Every mixed event reports its sorted frame time")
	# Exercise ordinary events that intentionally omit step_time; sorting still shifts.
	runtime = Runtime.new()
	runtime.start(_enemy(9), CENTER, {"windup_seconds": 0.25})
	runtime.start(_enemy(2), CENTER, {"windup_seconds": 0.5})
	events = runtime.advance(1.0, [_enemy(9), _enemy(2)], false, {9: 0.5})
	_expect(events.size() == 2 and events[0].source_id == 2 and events[1].source_id == 9, "Untimed events also sort by their resumed frame deadline")
	_expect(not events[0].has("step_time") and not events[1].has("step_time"), "Untimed ordinary event shape remains unchanged")


func _test_epsilon() -> void:
	for gap: float in [Runtime.TIME_EPSILON * 0.5, Runtime.TIME_EPSILON * 2.0]:
		var runtime := Runtime.new()
		var original := Baseline.new()
		var enemy := _enemy()
		var profile := {"windup_seconds": 0.25 + gap}
		runtime.start(enemy, CENTER, profile)
		original.start(enemy, CENTER, profile)
		var expected: Array[Dictionary] = original.advance(0.25, [enemy], true)
		for event: Dictionary in expected: event.step_time = float(event.step_time) + 0.5
		var actual := runtime.advance(0.75, [enemy], true, {1: 0.5})
		_expect(var_to_bytes(actual) == var_to_bytes(expected), "Partial thaw keeps original TIME_EPSILON event semantics exactly")
		_expect(var_to_bytes(_snapshot(runtime)) == var_to_bytes(_snapshot(original)), "Partial thaw changes no local arithmetic at the old epsilon boundary")
		if not actual.is_empty():
			_expect(float(actual[0].step_time) > 0.75, "Original epsilon-near deadline remains unclamped after thaw offset")
		var before := var_to_bytes(_snapshot(runtime))
		_expect(runtime.advance(0.5, [enemy], true, {1: 0.5}).is_empty() and var_to_bytes(_snapshot(runtime)) == before, "Whole-frame pause never trips an epsilon-near pending deadline")
	for progress: float in [0.0, 0.8]:
		for gap: float in [Runtime.TIME_EPSILON * 0.5, Runtime.TIME_EPSILON * 2.0]:
			var runtime := Runtime.new()
			var original := Baseline.new()
			var enemy := _enemy(1, "sunwell_terrace")
			_start(runtime, enemy)
			_start(original, enemy)
			runtime.advance(progress, [enemy])
			original.advance(progress, [enemy])
			var delta: float = 0.5 + 0.8 - gap
			var expected: Array[Dictionary] = original.advance(delta - 0.5, [enemy])
			for event: Dictionary in expected: event.step_time = float(event.step_time) + 0.5
			var actual := runtime.advance(delta, [enemy], false, {1: 0.5})
			_expect(var_to_bytes(actual) == var_to_bytes(expected), "Both Echo deadlines retain the old epsilon and exact offset arithmetic")
			_expect(var_to_bytes(_snapshot(runtime)) == var_to_bytes(_snapshot(original)), "Epsilon-near Echo thaw retains exact phase and pulse count")


func _reject_batch(delta: float, live: Variant, prefixes: Dictionary, label: String) -> void:
	var runtime := Runtime.new()
	_start(runtime, _enemy())
	_start(runtime, _enemy(2, "sunwell_terrace"))
	runtime.advance(0.3, [_enemy(), _enemy(2, "sunwell_terrace")])
	var before := var_to_bytes(_snapshot(runtime))
	var prefix_before := var_to_bytes(prefixes)
	var live_before := var_to_bytes(live)
	_expect(runtime.advance(delta, live, true, prefixes).is_empty(), "Invalid batch emits nothing: " + label)
	_expect(var_to_bytes(_snapshot(runtime)) == before, "Invalid batch cannot advance, cancel or consume identities: " + label)
	_expect(var_to_bytes(prefixes) == prefix_before and var_to_bytes(live) == live_before, "Invalid batch preserves caller inputs: " + label)


func _test_atomic_validation() -> void:
	var live: Array = [_enemy(), _enemy(2, "sunwell_terrace")]
	# Invalid suffix must also preserve sources that would otherwise advance or die.
	live[0].health = 0.0
	for invalid: Variant in [null, true, "0.2", [], {}, NAN, INF, -INF, -0.1, 1.000000001]:
		_reject_batch(1.0, live, {1: 0.5, 2: invalid}, "prefix value %s" % str(invalid))
	for invalid: Variant in [null, true, "1", 0, -1, 1.0, 3]:
		_reject_batch(1.0, live, {invalid: 0.5}, "prefix identity %s" % str(invalid))
	for delta: float in [-1.0, NAN, INF, -INF]:
		_reject_batch(delta, live, {1: 0.0}, "nonfinite or negative delta")
	_reject_batch(0.0, live, {1: 0.001}, "positive pause exceeds zero delta")
	var too_many: Dictionary = {}
	var oversized: Array = []
	for id: int in range(1, 102):
		too_many[id] = 0.5
		oversized.append(_enemy(id))
	_reject_batch(1.0, oversized, too_many, "101 prefix entries")
	for invalid: Variant in [null, {}, true, [null], [{}], [_enemy(), _enemy()], oversized]:
		_reject_batch(1.0, invalid, {1: 0.5}, "invalid complete source universe")
	var runtime := Runtime.new()
	_start(runtime, _enemy())
	_start(runtime, _enemy(2))
	_expect(runtime.advance(0.0, [_enemy(), _enemy(2)], true, {1: 0, 2: 0.0}).is_empty() and runtime.active_count() == 2, "Zero delta accepts both integer and floating zero prefixes")
	var old := Baseline.new()
	_start(old, _enemy())
	_start(old, _enemy(2))
	_expect(var_to_bytes(runtime.advance(1.0, [_enemy(), _enemy(2)], true, {1: 0, 2: -0.0})) == var_to_bytes(old.advance(1.0, [_enemy(), _enemy(2)], true)), "Validated zero prefixes use exact old event arithmetic")
	_expect(var_to_bytes(_snapshot(runtime)) == var_to_bytes(_snapshot(old)), "Validated zero prefixes retain exact old state bytes")
	# An idle, valid source may have a freeze prefix without owning an attack.
	runtime = Runtime.new()
	_start(runtime, _enemy())
	_expect(runtime.advance(0.7, [_enemy(), _enemy(2)], true, {2: 0.7}).size() == 1, "Valid idle-source prefix does not pause an unrelated action")


func _test_cancellation() -> void:
	var zero_runtime := Runtime.new()
	var dead := _enemy()
	_start(zero_runtime, dead)
	dead.health = 0.0
	_expect(zero_runtime.advance(0.0, [dead], true, {1: 0}).is_empty() and zero_runtime.active_count() == 0, "A valid zero-prefix batch still cancels death at zero delta")
	for kind: String in ["normal", "sunwell_terrace"]:
		for elapsed: float in [0.4, 0.8, 1.6]:
			for cause: String in ["death", "birth", "processed", "malformed_health", "missing"]:
				var runtime := Runtime.new()
				var enemy := _enemy(1, kind)
				var other := _enemy(2)
				_start(runtime, enemy)
				_start(runtime, other)
				runtime.advance(elapsed, [enemy, other])
				var live: Array = [enemy, other]
				var prefixes: Dictionary = {1: 1.0, 2: 1.0}
				match cause:
					"death": enemy.health = 0.0
					"birth": enemy.spawn = 0.1
					"processed": enemy.death_processed = true
					"malformed_health": enemy.health = NAN
					"missing":
						live = [other]
						prefixes.erase(1)
				var other_before := var_to_bytes(runtime.state_for(2))
				_expect(runtime.advance(1.0, live, true, prefixes).is_empty() and runtime.state_for(1).is_empty(), "Freeze retains existing cancellation: %s/%s/%.1f" % [kind, cause, elapsed])
				_expect(var_to_bytes(runtime.state_for(2)) == other_before, "Cancellation preserves the other frozen source")
				_expect(runtime.advance(100.0, [_enemy(1, kind)]).is_empty(), "Restored source cannot replay a cancelled frozen action")
				var restarted := _start(runtime, _enemy(1, kind))
				_expect(restarted.ok and restarted.attack.attack_id == 3 and restarted.attack.elapsed == 0.0, "Only explicit restart creates a new full warning")


func _test_capacity_copies_and_rng() -> void:
	var runtime := Runtime.new()
	var live: Array[Dictionary] = []
	var prefixes: Dictionary = {}
	for id: int in range(1, 101):
		var enemy := _enemy(id, "sunwell_terrace")
		live.append(enemy)
		prefixes[id] = 0.5
		_expect(_start(runtime, enemy).ok, "Bounded source admits before pause")
	var live_before := var_to_bytes(live)
	var prefix_before := var_to_bytes(prefixes)
	seed(736074)
	var expected_random := randi()
	seed(736074)
	var events := runtime.advance(2.1, live, false, prefixes)
	_expect(randi() == expected_random, "Paused advancement consumes no global RNG")
	_expect(events.size() == 200 and runtime.active_count() == 100, "100 paused Echo sources emit exactly 200 pulses within the existing bound")
	for index: int in range(events.size()):
		_expect(events[index].source_id == index % 100 + 1 and events[index].pulse_index == index / 100, "Paused capacity events preserve chronological identity order")
	_expect(var_to_bytes(live) == live_before and var_to_bytes(prefixes) == prefix_before, "Paused advancement never mutates input snapshots or prefix data")
	if not events.is_empty():
		events[0].profile.radius = 1.0
		events[0].packet.base.clear()
		_expect(runtime.state_for(1).profile.radius == 85.0 and not runtime.state_for(1).packet.base.is_empty(), "Paused events remain detached from retained recovery state")
	_expect(runtime.advance(10.0, live, false, prefixes).is_empty() and runtime.active_count() == 0, "All bounded paused sequences eventually reclaim their state")
