extends SceneTree
## Cache only proven strict job orders; compare with historical every-pop sorting.
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
const Catalog = preload("res://scripts/monsters/monster_catalog.gd")
var checks: int = 0
var failures: int = 0
var _finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_case(_test_order_proof, "strict-order proof and asymmetric approximate boundaries")
	_case(_test_ambiguous_batches, "near-time chains and duplicate IDs")
	_case(_test_priority_and_capacity, "priority ties, capacity and appended work")
	_case(_test_lifecycle_and_partitions, "split, return, expiry, frame partitions")
	_case(_test_seeded_differential, "seeded chronological differential")
	_case(_test_real_density, "100 real enemies / 180 projectiles")
	print("Projectile schedule: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _case(test: Callable, label: String) -> void:
	_finished = false
	test.call()
	_expect(_finished, "Case reaches final assertion without exception: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _snapshot() -> Dictionary:
	return Recipes.snapshot({"damage": 31.0, "projectile_increased": 0.37,
		"attack_added_physical": 7.0, "attack_added_fire": 11.0}, ["return_on_range", "explode_on_flight_end"])


func _shot(runtime: RefCounted, overrides: Dictionary = {}, origin: Vector2 = Vector2.ZERO,
		direction: Vector2 = Vector2.RIGHT) -> Dictionary:
	var spec: Dictionary = {"speed": 100.0, "range": 100.0, "lifetime": 3.0,
		"radius": 0.0, "pierce": -1, "role": "child", "split": false}
	spec.merge(overrides, true)
	var snapshot: Dictionary = _snapshot()
	return runtime.make_projectile(origin, direction, spec,
		Recipes.tornado_packet(snapshot, "parent" if bool(spec.split) else "child"),
		snapshot, runtime.new_cast(), Color.WHITE)


func _compare(initial: Array[Dictionary], targets: Array[Dictionary], steps: Array,
		label: String, capacity: int = 180, reference_spatial: bool = true) -> Dictionary:
	var reference = Runtime.new()
	var cached = Runtime.new()
	reference.use_cached_work_order = false
	reference.use_spatial_index = reference_spatial
	var a: Array[Dictionary] = initial.duplicate(true)
	var b: Array[Dictionary] = initial.duplicate(true)
	var original_a: Array[Dictionary] = a.duplicate()
	var original_b: Array[Dictionary] = b.duplicate()
	for shot: Dictionary in initial:
		reference.next_projectile_id = maxi(reference.next_projectile_id, int(shot.id) + 1)
		reference.next_cast_id = maxi(reference.next_cast_id, int(shot.cast_id) + 1)
	cached.next_projectile_id = reference.next_projectile_id
	cached.next_cast_id = reference.next_cast_id
	var results: Dictionary = {"events": [], "reference_sorts": 0, "cached_sorts": 0, "skips": 0,
		"proofs": 0, "reference_usec": 0, "cached_usec": 0}
	for step: int in range(steps.size()):
		var delta: float = float(steps[step])
		var start: int = Time.get_ticks_usec()
		var events_a: Array[Dictionary] = reference.advance(a, delta, targets, Vector2(17, -13), capacity)
		results.reference_usec += Time.get_ticks_usec() - start
		start = Time.get_ticks_usec()
		var events_b: Array[Dictionary] = cached.advance(b, delta, targets, Vector2(17, -13), capacity)
		results.cached_usec += Time.get_ticks_usec() - start
		_expect(events_a == events_b, "%s step %d: complete events, order, times, payloads and snapshots" % [label, step])
		_expect(a == b and original_a == original_b, "%s step %d: surviving and terminated original shot states" % [label, step])
		_expect(reference.next_projectile_id == cached.next_projectile_id and reference._sequence == cached._sequence,
			"%s step %d: exact creation/event sequence" % [label, step])
		_expect(cached.last_work_sorts + cached.last_work_sort_skips == reference.last_work_sorts,
			"%s step %d: one historical sort per job, equal processed-job count" % [label, step])
		_expect(reference.last_work_sort_skips == 0 and reference.last_work_order_checks == 0,
			"%s step %d: flag false retains historical every-pop sorting" % [label, step])
		results.events.append_array(events_b)
		results.reference_sorts += reference.last_work_sorts
		results.cached_sorts += cached.last_work_sorts
		results.skips += cached.last_work_sort_skips
		results.proofs += cached.last_work_order_checks
	results.shots = b
	return results


func _job(at: float, id: int, priority: int = 3) -> Dictionary:
	return {"at": at, "priority": priority, "shot": {"id": id}}


func _count(events: Array, type: String) -> int:
	var result: int = 0
	for event: Dictionary in events:
		result += 1 if event.type == type else 0
	return result


func _test_order_proof() -> void:
	_expect(Runtime._work_order_is_strict([]), "Empty work has no ambiguous comparison")
	_expect(Runtime._work_order_is_strict([_job(1, 1), _job(1, 2), _job(1, 3, 0)]), "Exact equal times use priority then unique ID")
	_expect(Runtime._work_order_is_strict([_job(3, 1), _job(-10, 2), _job(0, 3)]), "Unordered separated finite times are safe")
	_expect(not Runtime._work_order_is_strict([_job(0, 1), _job(10, 1)]), "Duplicate integer shot IDs reject cache even at separated times")
	for invalid: float in [NAN, INF, -INF]:
		_expect(not Runtime._work_order_is_strict([_job(0, 1), _job(invalid, 2)]), "Nonfinite times reject cache")
	var chain: Array[Dictionary] = [_job(1.000012, 1), _job(1.0, 3), _job(1.000006, 2)]
	_expect(is_equal_approx(1.0, 1.000006) and is_equal_approx(1.000006, 1.000012) and not is_equal_approx(1.0, 1.000012),
		"Fixture has genuinely nontransitive approximate-time chain")
	_expect(not Runtime._work_order_is_strict(chain), "Independent numeric ordering detects hidden adjacent chain")
	var low: float = 1.0
	var high: float = 1.00001000005
	_expect(is_equal_approx(low, high) != is_equal_approx(high, low), "Fixture crosses asymmetric first-operand-scaled tolerance")
	_expect(not Runtime._work_order_is_strict([_job(high, 1), _job(low, 2)]), "Either approximate direction rejects cache")
	_finished = true


func _test_ambiguous_batches() -> void:
	var builder = Runtime.new()
	for reverse: bool in [false, true]:
		var shots: Array[Dictionary] = []
		for time: float in [1.000012, 1.0, 1.000006, 1.3, 1.5, 1.0, 1.00001000005]:
			shots.append(_shot(builder, {"range": 10000.0, "lifetime": time}))
		if reverse:
			shots.reverse()
		var result: Dictionary = _compare(shots, [], [2.0], "near-equal nontransitive chain reverse=%s" % reverse)
		_expect(result.cached_sorts == result.reference_sorts and result.skips == 0,
			"Ambiguous batch retains every-pop sorts even after ambiguous members leave")
	var duplicate_a: Dictionary = _shot(builder, {"range": 10000.0, "lifetime": 0.3})
	var duplicate_b: Dictionary = _shot(builder, {"range": 10000.0, "lifetime": 0.4})
	duplicate_b.id = duplicate_a.id
	var duplicates: Dictionary = _compare([duplicate_a, duplicate_b], [], [0.5], "duplicate shot IDs")
	_expect(duplicates.cached_sorts == 2 and duplicates.skips == 0, "Duplicate IDs stay on historical path")
	var invalid_runtime = Runtime.new()
	var invalid_shots: Array[Dictionary] = [_shot(builder)]
	for delta: float in [0.0, -1.0, INF, NAN]:
		invalid_runtime.advance(invalid_shots, delta, [], Vector2.ZERO, 180)
		_expect(invalid_runtime.last_work_sorts == 0 and invalid_runtime.last_work_sort_skips == 0 and invalid_runtime.last_work_order_checks == 0,
			"Empty/invalid frame resets all schedule counters")
	_finished = true


func _test_priority_and_capacity() -> void:
	var builder = Runtime.new()
	var target: Array[Dictionary] = [{"id": 1, "pos": Vector2(50, 0), "radius": 0.0, "health": 1000.0, "spawn": 0.0}]
	var ties: Array[Dictionary] = [_shot(builder, {"range": 10000.0}),
		_shot(builder, {"range": 50.0}), _shot(builder, {"pierce": 0, "range": 10000.0}),
		_shot(builder, {"lifetime": 0.5, "range": 10000.0})]
	var result: Dictionary = _compare(ties, target, [0.5], "same-time continuation/range/hit/expiry priorities")
	_expect(result.cached_sorts == 1 and result.skips == 3, "Exactly tied finite keys need only one sort despite priority differences")
	for later_expiry: bool in [false, true]:
		for reverse: bool in [false, true]:
			var mother: Dictionary = _shot(builder, {"split": true, "role": "parent", "range": 50.0})
			var expires: Dictionary = _shot(builder, {"range": 10000.0, "lifetime": 0.6 if later_expiry else 0.5}, Vector2(1000, 1000))
			var pair: Array[Dictionary] = [mother, expires]
			if reverse:
				pair.reverse()
			var capacity: Dictionary = _compare(pair, target, [1.0, 3.0], "capacity same-time expiry=%s reverse=%s" % [not later_expiry, reverse], 3)
			_expect(_count(capacity.events, "spawned") == (0 if later_expiry else 3), "Only earlier/same-time expiry frees child capacity")
			if not later_expiry:
				_expect(capacity.proofs > 1 and capacity.cached_sorts > 1, "Appended child/return jobs invalidate and re-prove ordering")
	var generation: Dictionary = _shot(builder, {"split": true, "role": "parent", "range": 50.0})
	generation.generation = 1
	var cancelled: Dictionary = _compare([generation], target, [1.0], "generation rejection")
	_expect(_count(cancelled.events, "spawn_rejected") == 1 and _count(cancelled.events, "explosion") == 0, "Generation cancellation does not acquire explosion")
	_finished = true


func _test_lifecycle_and_partitions() -> void:
	var builder = Runtime.new()
	var shots: Array[Dictionary] = []
	builder.spawn_tornado(shots, Vector2(-128, 0), Vector2.RIGHT, _snapshot(), 180, 9)
	var targets: Array[Dictionary] = [{"id": 1, "pos": Vector2(-70, 0), "radius": 5.0, "health": 10000.0},
		{"id": 2, "pos": Vector2(0, 0), "radius": 22.0, "health": 10000.0}]
	var baseline: Dictionary = _compare(shots, targets, [3.4], "full nine-parent lifecycle")
	_expect(_count(baseline.events, "split") == 9 and _count(baseline.events, "spawned") == 27 and
		_count(baseline.events, "return_started") == 27 and _count(baseline.events, "explosion") == 27,
		"Nine parents produce 27 children, one return and expiry/explosion each")
	for size: float in [0.17, 0.02, 0.007]:
		var steps: Array[float] = []
		var time: float = 0.0
		while time < 3.4 - 0.000001:
			var step: float = minf(size, 3.4 - time)
			steps.append(step)
			time += step
		var partition: Dictionary = _compare(shots, targets, steps, "partition %.3f" % size)
		for type: String in ["hit", "split", "spawned", "return_started", "explosion", "terminated"]:
			_expect(_count(baseline.events, type) == _count(partition.events, type), "Partition retains lifecycle event count: " + type)
		_expect(partition.shots.is_empty(), "Partition reaches full termination")
	_finished = true


func _test_seeded_differential() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 817180100
	for fixture: int in range(60):
		var builder = Runtime.new()
		var targets: Array[Dictionary] = []
		for i: int in range(100):
			targets.append({"id": i + 1, "pos": Vector2(rng.randf_range(-1200, 1200), rng.randf_range(-500, 500)),
				"radius": rng.randf_range(0, 30), "health": 0.0 if i % 17 == 0 else 10000.0,
				"spawn": 0.1 if i % 13 == 0 else 0.0})
		var shots: Array[Dictionary] = []
		for i: int in range(36):
			var lifetime: float = rng.randf_range(0.1, 2.0)
			if fixture % 3 == 0 and i < 5:
				lifetime = 1.0 + i * 0.000004
			shots.append(_shot(builder, {"speed": rng.randf_range(20, 1800), "range": rng.randf_range(10, 1300),
				"lifetime": lifetime, "radius": rng.randf_range(0, 8), "pierce": i % 4 - 1,
				"split": i % 7 == 0, "role": "parent" if i % 7 == 0 else "child"},
				Vector2(rng.randf_range(-900, 900), rng.randf_range(-300, 300)), Vector2.RIGHT.rotated(rng.randf_range(-PI, PI))))
		if fixture % 2 == 0:
			shots.reverse()
		_compare(shots, targets, [0.016, 0.14, 0.37, 2.0], "seed817180100 fixture%d" % fixture, 180, fixture % 2 == 0)
	_finished = true


func _test_real_density() -> void:
	var targets: Array[Dictionary] = []
	for i: int in range(100):
		var enemy: Dictionary = Catalog.make_enemy(i + 1, ["crawler", "skitter", "brute"][i % 3], 12,
			Vector2(-188 + i % 20 * 86.0, 27 + floori(i / 20.0) * 133.0))
		enemy.spawn = 0.0
		targets.append(enemy)
	for scenario: String in ["steady_no_hit", "mixed_hits", "clustered"]:
		var builder = Runtime.new()
		var shots: Array[Dictionary] = []
		var fixture_targets: Array[Dictionary] = targets.duplicate(true)
		if scenario == "clustered":
			for target: Dictionary in fixture_targets:
				target.pos = Vector2.ZERO
		for i: int in range(180):
			var origin := Vector2(-200 + i % 60 * 7, 680)
			if scenario == "mixed_hits" and i % 2 == 0:
				origin = Vector2(fixture_targets[i % 100].pos) - Vector2(25, 0)
			elif scenario == "clustered":
				origin = Vector2(-25, 0)
			shots.append(_shot(builder, {"speed": 450.0, "range": 20000.0, "lifetime": 60.0, "radius": 5.5}, origin))
		var result: Dictionary = _compare(shots, fixture_targets, [1.0 / 60.0], scenario + "100x180 historical both optimizations off", 180, false)
		_expect(result.reference_sorts == 180 and result.cached_sorts == 1 and result.skips == 179,
			"180 immutable same-end-time jobs need one historical-comparator sort: " + scenario)
		if scenario == "steady_no_hit":
			_expect(result.events.is_empty(), "Steady fixture genuinely has no hit/lifecycle events")
		elif scenario == "mixed_hits":
			_expect(_count(result.events, "hit") > 0 and _count(result.events, "hit") < 180, "Mixed fixture has both hitting and non-hitting projectiles")
		else:
			_expect(_count(result.events, "hit") > 10000, "Clustered fixture retains dense genuine hit work")
		print("Projectile schedule %s: historical_sorts=%d cached_sorts=%d skips=%d; observed historical=%dus optimized=%dus (non-gating, both broadphase and ordering enabled)" %
			[scenario, result.reference_sorts, result.cached_sorts, result.skips, result.reference_usec, result.cached_usec])
	_finished = true
