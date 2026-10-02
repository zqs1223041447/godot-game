extends SceneTree
## Indexed and original full-scan modes must produce identical complete values.
## Candidate counts are deterministic work measurements, not a wall-clock claim.
const Index = preload("res://scripts/combat/spatial_target_index.gd")
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
const Catalog = preload("res://scripts/monsters/monster_catalog.gd")
var checks: int = 0
var failures: int = 0
var _finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_case(_test_index_bounds, "index bounds/order/fallback")
	_case(_test_mutable_index, "mutable aliases/reordering")
	_case(_test_exact_edges, "exact numerical edges and filters")
	_case(_test_lifecycle, "split/return/expiry/capacity")
	_case(_test_partitions, "frame partition equivalence")
	_case(_test_random_differential, "seeded randomized differential")
	_case(_test_sequential_separation, "sequential separation")
	_case(_test_100_targets_180_projectiles, "100 actual monsters / 180 projectiles")
	print("Spatial collision: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _case(test: Callable, label: String) -> void:
	_finished = false
	test.call()
	_expect(_finished, "Suite reaches its last check without a script exception: " + label)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _target(id: int, position: Vector2, radius: float = 0.0) -> Dictionary:
	return {"id": id, "pos": position, "radius": radius, "health": 10000.0, "spawn": 0.0}


func _snapshot() -> Dictionary:
	return Recipes.snapshot({"damage": 31.0, "projectile_increased": 0.37, "attack_added_physical": 7.0,
		"attack_added_fire": 11.0}, ["return_on_range", "explode_on_flight_end"])


func _shot(runtime: RefCounted, origin: Vector2 = Vector2.ZERO, direction: Vector2 = Vector2.RIGHT,
		overrides: Dictionary = {}) -> Dictionary:
	var spec: Dictionary = {"speed": 100.0, "range": 100.0, "lifetime": 3.0,
		"radius": 0.0, "pierce": -1, "role": "child", "split": false}
	spec.merge(overrides, true)
	var snapshot: Dictionary = _snapshot()
	return runtime.make_projectile(origin, direction, spec,
		Recipes.tornado_packet(snapshot, "parent" if bool(spec.split) else "child"),
		snapshot, runtime.new_cast(), Color.WHITE)


func _compare(initial: Array[Dictionary], targets: Array[Dictionary], deltas: Array,
		label: String, capacity: int = 180) -> Dictionary:
	var reference = Runtime.new()
	var indexed = Runtime.new()
	reference.use_spatial_index = false
	var a: Array[Dictionary] = initial.duplicate(true)
	var b: Array[Dictionary] = initial.duplicate(true)
	var initial_a: Array[Dictionary] = a.duplicate()
	var initial_b: Array[Dictionary] = b.duplicate()
	for shot: Dictionary in initial:
		reference.next_projectile_id = maxi(reference.next_projectile_id, int(shot.id) + 1)
		reference.next_cast_id = maxi(reference.next_cast_id, int(shot.cast_id) + 1)
	indexed.next_projectile_id = reference.next_projectile_id
	indexed.next_cast_id = reference.next_cast_id
	var all_events: Array[Dictionary] = []
	var candidate_visits: int = 0
	var full_visits: int = 0
	var indexed_usec: int = 0
	var reference_usec: int = 0
	for step: int in range(deltas.size()):
		var delta: float = float(deltas[step])
		var started: int = Time.get_ticks_usec()
		var events_a: Array[Dictionary] = reference.advance(a, delta, targets, Vector2(17, -13), capacity)
		reference_usec += Time.get_ticks_usec() - started
		started = Time.get_ticks_usec()
		var events_b: Array[Dictionary] = indexed.advance(b, delta, targets, Vector2(17, -13), capacity)
		indexed_usec += Time.get_ticks_usec() - started
		_expect(events_a == events_b, "%s step %d: exact complete events (IDs/order/time/payload/snapshot)" % [label, step])
		_expect(a == b and initial_a == initial_b, "%s step %d: exact survivor and original terminated-shot values" % [label, step])
		_expect(reference.next_projectile_id == indexed.next_projectile_id and reference._sequence == indexed._sequence,
			"%s step %d: creation and event sequences" % [label, step])
		_expect(indexed.last_full_scan_visits == reference.last_full_scan_visits and
			reference.last_candidate_visits == reference.last_full_scan_visits and
			indexed.last_candidate_visits <= indexed.last_full_scan_visits,
			"%s step %d: candidate work never exceeds equivalent full scan" % [label, step])
		_expect(indexed.last_indexed_queries == indexed.last_contact_queries and reference.last_indexed_queries == 0,
			"%s step %d: every within-advance query uses requested mode" % [label, step])
		candidate_visits += indexed.last_candidate_visits
		full_visits += indexed.last_full_scan_visits
		all_events.append_array(events_b)
	return {"events": all_events, "shots": b, "candidates": candidate_visits, "full": full_visits,
		"indexed_usec": indexed_usec, "reference_usec": reference_usec}


func _event_count(events: Array[Dictionary], type: String) -> int:
	var result: int = 0
	for event: Dictionary in events:
		result += 1 if event.type == type else 0
	return result


func _assert_candidates(actual: Array[int], required: Array, label: String) -> void:
	var sorted: Array[int] = actual.duplicate()
	sorted.sort()
	var unique: Dictionary = {}
	for index: int in actual:
		unique[index] = true
	_expect(actual == sorted and unique.size() == actual.size(), label + ": ascending original indices, no repeated index")
	for index: int in required:
		_expect(actual.has(index), label + ": contains index %d" % index)


func _test_index_bounds() -> void:
	var duplicate: Dictionary = _target(9, Vector2(-128, -128), 0.0)
	var targets: Array[Dictionary] = [duplicate, _target(9, Vector2(256, 0), 260.0), duplicate,
		_target(2, Vector2(128, 0), 0.0), _target(1, Vector2(5000, 5000), 10.0)]
	for size: float in [32.0, 96.0, 128.0]:
		var index = Index.new(size)
		index.rebuild(targets)
		_assert_candidates(index.query_circle(Vector2(-128, -128), 0.0), [0, 2], "negative cell border")
		_assert_candidates(index.query_aabb(Rect2(128, 0, 0, 0)), [1, 3], "point AABB and multi-cell radius")
		_assert_candidates(index.query_sweep(Vector2(-500, 0), Vector2(500, 0), 0.0), [1, 3], "swept target circle")
		_expect(not index.query_circle(Vector2.ZERO, 1.0).has(4), "Far-away target excluded for cell size %.0f" % size)
		for rect: Rect2 in [Rect2(INF, 0, 1, 1), Rect2(0, 0, -1, 2), Rect2(0, 0, NAN, 1), Rect2(-1e20, -1e20, 2e20, 2e20)]:
			_expect(index.query_aabb(rect) == [0, 1, 2, 3, 4], "Unsafe or oversized AABB returns all original indices")
		for radius: float in [-1.0, INF, NAN]:
			_expect(index.query_circle(Vector2.ZERO, radius) == [0, 1, 2, 3, 4], "Invalid circle safely scans all")
			_expect(index.query_sweep(Vector2.ZERO, Vector2.ONE, radius) == [0, 1, 2, 3, 4], "Invalid sweep safely scans all")
		_expect(index.query_sweep(Vector2(NAN, 0), Vector2.ZERO, 0) == [0, 1, 2, 3, 4], "Nonfinite sweep safely scans all")
	var unsafe: Array[Dictionary] = [_target(1, Vector2(INF, 0)), _target(2, Vector2.ZERO, -1),
		_target(3, Vector2.ZERO, INF), {"id": 4}, {"id": 5, "pos": Vector2.ZERO, "radius": "invalid"}]
	var index = Index.new()
	index.rebuild(unsafe)
	_expect(index.query_circle(Vector2(-99999, 99999), 1.0) == [0, 1, 2, 3, 4], "Unsafe target bounds stay in every query; no silent drop")
	index.rebuild([])
	_expect(index.query_circle(Vector2.ZERO, 0.0).is_empty(), "Rebuild clears prior cells/overflow")
	_finished = true


func _test_mutable_index() -> void:
	var shared: Dictionary = _target(1, Vector2.ZERO, 5.0)
	var targets: Array[Dictionary] = [shared, _target(1, Vector2(2000, 0), 5.0), shared, _target(2, Vector2(4000, 0), 5.0)]
	var index = Index.new()
	index.rebuild(targets)
	_expect(index.query_circle(Vector2.ZERO, 0.0) == [0, 2], "Same-reference entries retained separately")
	shared.pos = Vector2(-4000, -4000)
	index.update(2)
	_expect(index.query_circle(Vector2.ZERO, 0.0).is_empty(), "Moved aliases removed from all old cells")
	_expect(index.query_circle(shared.pos, 0.0) == [0, 2], "One update moves all same-reference aliases")
	targets[1].radius = 1000.0
	index.update(1)
	_expect(index.query_circle(Vector2(1000, 0), 0.0) == [1], "Radius mutation reindexes actual circle extent")
	targets[3].radius = INF
	index.update(3)
	_expect(index.query_circle(Vector2(100000, 100000), 0.0) == [3], "Unsafe updated bound enters conservative overflow")
	targets[3].radius = 5.0
	index.update(3)
	_expect(index.query_circle(Vector2(100000, 100000), 0.0).is_empty(), "Recovered bounds remove overflow entry")
	targets.reverse()
	index.rebuild(targets)
	_expect(index.query_circle(shared.pos, 0.0) == [1, 3], "Rebuild after reordering returns new original-array positions")
	targets.append(_target(10, Vector2(-4000, -4000)))
	_expect(index.query_circle(shared.pos, 0.0) == [1, 3, 4], "Changed array length auto-rebuilds conservatively")
	index.update(-1)
	index.update(10000)
	_expect(index.query_circle(shared.pos, 0.0) == [1, 3, 4], "Invalid update does not damage existing membership")
	_finished = true


func _test_exact_edges() -> void:
	_expect(Runtime._segment_circle(Vector2(-100, 0), Vector2(100, 0), Vector2.ZERO, 6.0 + 14.0) == 0.4,
		"Exact shot6 + enemy14 world-space radius enters at t=0.4")
	_expect(Runtime._segment_circle(Vector2(-128, -128), Vector2(128, -128), Vector2(0, -118), 5.0 + 5.0) == 0.5,
		"Exact tangency enters at t=0.5 on a negative-coordinate cell border")
	_expect(Runtime._segment_circle(Vector2(-128, -128), Vector2(128, -128), Vector2(0, -118), 9.0) == -1.0,
		"A smaller mathematical radius would miss; broadphase must never alter it")
	_expect(Runtime._segment_circle(Vector2(-128, 0), Vector2(128, 0), Vector2.ZERO, 0.0) == 0.5,
		"Zero-radius segment/point intersection retains exact t=0.5")
	_expect(Index.DEFAULT_CELL_SIZE == 128.0 and Index.MAX_CELLS_PER_OPERATION == 4096,
		"Grid scale and bounded per-query/insertion work are explicit")
	var builder = Runtime.new()
	var shared: Dictionary = _target(9, Vector2(-64, -128), 0.0)
	var targets: Array[Dictionary] = [_target(7, Vector2(0, -118), 5.0), shared,
		_target(3, Vector2(0, -118), 5.0), shared, _target(4, Vector2(128, -128), 0.0),
		_target(12, Vector2(256, -128), 22.0), _target(11, Vector2(64, -128), 10.0),
		_target(14, Vector2(96, -128), 10.0), _target(21, Vector2(0, -117.95), 5.0)]
	targets[6].health = 0.0
	targets[7].spawn = 0.1
	var shots: Array[Dictionary] = [_shot(builder, Vector2(-128, -128), Vector2.RIGHT,
		{"speed": 512.0, "range": 1024.0, "radius": 5.0})]
	var compared: Dictionary = _compare(shots, targets, [1.0], "tangent/cell-edge/duplicate/protected/dead")
	_expect(_event_count(compared.events, "hit") == 6, "Exact full radii give six contacts, including duplicate reference twice")
	var ids: Array[int] = []
	for event: Dictionary in compared.events:
		if event.type == "hit":
			ids.append(event.target_id)
	_expect(ids == [9, 9, 3, 7, 4, 12], "Contact order preserves t then target ID; near-tangent miss stays a miss")
	var point_shot: Dictionary = _shot(builder, Vector2.ZERO, Vector2.RIGHT,
		{"speed": 0.0, "radius": 0.0, "range": 1000.0})
	var points: Array[Dictionary] = [_target(2, Vector2.ZERO), _target(1, Vector2(0.01, 0))]
	var point_result: Dictionary = _compare([point_shot], points, [0.1], "zero-length/zero-radius")
	_expect(_event_count(point_result.events, "hit") == 1, "Zero-radius point only hits exact overlap")
	for origin: Vector2 in [Vector2.ZERO, Vector2(-65536, 65536), Vector2(1000000, -1000000)]:
		var high_speed: Array[Dictionary] = [_shot(builder, origin, Vector2.RIGHT,
			{"speed": 200000.0, "range": 300000.0, "lifetime": 5.0, "radius": 0.25})]
		var distant: Array[Dictionary] = [_target(10, origin + Vector2(99999, 0.5), 0.25),
			_target(11, origin + Vector2(100000, 1.0), 0.25), _target(12, origin + Vector2(200001, 0), 0.0)]
		_compare(high_speed, distant, [1.0], "high-speed finite numerical sweep")
	var direct = Runtime.new()
	var direct_shots: Array[Dictionary] = [point_shot.duplicate(true)]
	direct.advance(direct_shots, 0.1, points, Vector2.ZERO, 180)
	points[1].pos = Vector2.ZERO
	_expect(direct._contacts(point_shot, Vector2.ZERO, Vector2.ZERO, points).size() == 2,
		"Direct _contacts outside advance scans current data rather than stale index")
	for delta: float in [0.0, -1.0, INF, NAN]:
		direct.advance(direct_shots, delta, points, Vector2.ZERO, 180)
		_expect(direct.last_candidate_visits == 0 and direct.last_full_scan_visits == 0 and direct.last_contact_queries == 0,
			"Invalid/empty advance resets counters")
	_finished = true


func _test_lifecycle() -> void:
	var builder = Runtime.new()
	var shots: Array[Dictionary] = []
	builder.spawn_tornado(shots, Vector2(-128, 0), Vector2.RIGHT, _snapshot(), 180, 9)
	var targets: Array[Dictionary] = []
	for i: int in range(100):
		targets.append(_target(100 - i, Vector2(-110 + i % 10 * 25, -110 + i / 10 * 25), 10 + i % 3 * 6))
	var result: Dictionary = _compare(shots, targets, [0.02, 0.1, 0.4, 0.8, 2.0], "nine parents to 27 returning children")
	_expect(_event_count(result.events, "split") == 9 and _event_count(result.events, "spawned") == 27, "All nine parents split into 27 independent children")
	_expect(_event_count(result.events, "return_started") == 27 and _event_count(result.events, "explosion") == 27,
		"All children return once and naturally expire with exact independent explosions")
	_expect(result.shots.is_empty() and _event_count(result.events, "hit") > 100, "Clumped real-radius targets exercise many actual hits and complete expiry")
	var mother: Dictionary = _shot(builder, Vector2.ZERO, Vector2.RIGHT, {"split": true, "role": "parent", "range": 50.0})
	var expires: Dictionary = _shot(builder, Vector2(5000, 5000), Vector2.RIGHT, {"lifetime": 0.1})
	for reverse: bool in [false, true]:
		var capacity_shots: Array[Dictionary] = []
		capacity_shots.assign([mother, expires] if not reverse else [expires, mother])
		var admitted: Dictionary = _compare(capacity_shots, targets, [0.6, 3.0], "earlier expiry frees capacity", 3)
		_expect(_event_count(admitted.events, "spawned") == 3, "Chronological capacity admission survives shot reordering")
	var rejected: Dictionary = _compare([mother], targets, [1.0], "atomic child capacity rejection", 2)
	_expect(_event_count(rejected.events, "spawn_rejected") == 1 and _event_count(rejected.events, "explosion") == 0,
		"Rejected child group remains cancelled without natural explosion")
	_finished = true


func _test_partitions() -> void:
	var builder = Runtime.new()
	var shots: Array[Dictionary] = []
	builder.spawn_tornado(shots, Vector2.ZERO, Vector2.RIGHT, _snapshot(), 180, 3)
	var targets: Array[Dictionary] = [_target(1, Vector2(50, 0), 5.0), _target(2, Vector2(-50, 0), 5.0)]
	var baseline: Dictionary = _compare(shots, targets, [3.4], "single full-lifecycle frame")
	for step: float in [0.17, 0.02, 0.007]:
		var deltas: Array[float] = []
		var elapsed: float = 0.0
		while elapsed < 3.4 - 0.000001:
			var delta: float = minf(step, 3.4 - elapsed)
			deltas.append(delta)
			elapsed += delta
		var partitioned: Dictionary = _compare(shots, targets, deltas, "partition %.3f" % step)
		for type: String in ["hit", "split", "spawned", "return_started", "explosion", "terminated"]:
			_expect(_event_count(partitioned.events, type) == _event_count(baseline.events, type), "Count invariant across frame partitions: " + type)
		_expect(partitioned.shots.is_empty(), "Partitioned flight completes within exact lifetime")
	_finished = true


func _test_random_differential() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 808100180
	for fixture: int in range(80):
		var builder = Runtime.new()
		var targets: Array[Dictionary] = []
		var spread: float = 80.0 if fixture % 3 == 0 else 2400.0
		for i: int in range(100):
			var target: Dictionary = _target(100 - i, Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread)),
				rng.randf_range(0.0, 40.0))
			target.health = 0.0 if i % 13 == 0 else 1000.0
			target.spawn = 0.1 if i % 17 == 0 else 0.0
			targets.append(target)
		# Duplicate dictionary references and IDs must keep both original iterations.
		targets[70] = targets[10]
		targets[71].id = targets[11].id
		if fixture % 2 == 0:
			targets.reverse()
		var shots: Array[Dictionary] = []
		for i: int in range(24):
			var shot: Dictionary = _shot(builder, Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread)),
				Vector2.RIGHT.rotated(rng.randf_range(-PI, PI)), {"speed": rng.randf_range(10, 3000),
				"radius": rng.randf_range(0, 20), "range": rng.randf_range(30, 2000), "lifetime": rng.randf_range(0.03, 2),
				"pierce": i % 4 - 1, "split": i % 11 == 0, "role": "parent" if i % 11 == 0 else "child"})
			if i % 7 == 0:
				shot.hit_ledger["outbound:%d" % targets[10].id] = true
			shots.append(shot)
		_compare(shots, targets, [0.016, 0.14, 0.37, 2.0], "seed 808100180 fixture %d" % fixture)
	_finished = true


func _actual_targets(clumped: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i: int in range(100):
		var position := Vector2(-188 + i % 20 * 86.0, 27 + floori(i / 20.0) * 133.0)
		if clumped:
			position = Vector2(-55 + i % 10 * 12.0, -55 + floori(i / 10.0) * 12.0)
		var enemy: Dictionary = Catalog.make_enemy(i + 1, ["crawler", "skitter", "brute"][i % 3], 12, position)
		enemy.spawn = 0.0
		result.append(enemy)
	return result


func _separate(targets: Array[Dictionary], indexed: bool) -> int:
	var index = Index.new()
	index.rebuild(targets)
	var visits: int = 0
	for i: int in range(targets.size()):
		var enemy: Dictionary = targets[i]
		if float(enemy.health) <= 0.0 or float(enemy.spawn) > 0.0:
			continue
		var candidates: Array[int] = []
		if indexed:
			candidates = index.query_circle(enemy.pos, float(enemy.radius) + 3.0)
		else:
			candidates.assign(range(targets.size()))
		var separation := Vector2.ZERO
		for other_index: int in candidates:
			visits += 1
			var other: Dictionary = targets[other_index]
			if int(other.id) == int(enemy.id):
				continue
			var offset: Vector2 = Vector2(enemy.pos) - Vector2(other.pos)
			var distance: float = offset.length()
			var separation_distance: float = float(enemy.radius) + float(other.radius) + 3.0
			if distance > 0.1 and distance < separation_distance:
				separation += offset / distance * (separation_distance - distance) * 2.5
		var direction: Vector2 = (Vector2(10, -15) - Vector2(enemy.pos)).normalized()
		enemy.pos = Vector2(enemy.pos) + (direction * float(enemy.speed) + separation + Vector2(enemy.knockback)) * 0.017
		index.update(i)
	return visits


func _test_sequential_separation() -> void:
	for clumped: bool in [false, true]:
		var a: Array[Dictionary] = _actual_targets(clumped)
		var b: Array[Dictionary] = a.duplicate(true)
		# Same-reference duplicate in each respective simulation.
		a[98] = a[1]
		b[98] = b[1]
		a[25].health = 0.0
		b[25].health = 0.0
		a[50].spawn = 0.3
		b[50].spawn = 0.3
		for frame: int in range(40):
			var full_visits: int = _separate(a, false)
			var visits: int = _separate(b, true)
			_expect(a == b, "Sequential movement sees every earlier target mutation exactly, clumped=%s frame=%d" % [clumped, frame])
			_expect(visits <= full_visits, "Separation candidates bounded by original full scan")
			if not clumped and frame == 0:
				print("Spatial separation fixture: candidates=%d equivalent_full_scan=%d reduction=%.2f%%" %
					[visits, full_visits, (1.0 - float(visits) / full_visits) * 100.0])
				_expect(visits * 4 < full_visits, "Distributed separation fixture reduces candidates by at least 75 percent")
	_finished = true


func _test_100_targets_180_projectiles() -> void:
	var targets: Array[Dictionary] = _actual_targets()
	_expect(targets.size() == 100 and targets[99].has("template_id") and targets[99].has("mechanism_ids"),
		"Fixture uses 100 complete factory-created gameplay enemy dictionaries")
	var builder = Runtime.new()
	var shots: Array[Dictionary] = []
	for i: int in range(180):
		var target: Dictionary = targets[i % targets.size()]
		shots.append(_shot(builder, Vector2(target.pos) - Vector2(35, 0), Vector2.RIGHT,
			{"speed": 420.0, "range": 1000.0, "radius": 6.0, "lifetime": 3.0}))
	var result: Dictionary = _compare(shots, targets, [0.12], "100 real targets / 180 concurrent projectiles")
	_expect(result.shots.size() == 180 and _event_count(result.events, "hit") == 180, "All 180 real projectile sweeps hit with unchanged exact radii")
	_expect(result.full == 18000 and result.candidates > 0 and result.candidates * 4 < result.full,
		"Reproducible distributed 100x180 fixture reduces candidate visits by at least 75 percent")
	print("Spatial 100x180 fixture: candidates=%d equivalent_full_scan=%d reduction=%.2f%%; observed indexed=%dus reference=%dus (non-gating)" %
		[result.candidates, result.full, (1.0 - float(result.candidates) / result.full) * 100.0, result.indexed_usec, result.reference_usec])
	# Worst-case overlap must stay correct even if candidate work cannot improve.
	for target: Dictionary in targets:
		target.pos = Vector2.ZERO
	for shot: Dictionary in shots:
		shot.pos = Vector2(-35, 0)
		shot.previous = shot.pos
	var clumped: Dictionary = _compare(shots, targets, [0.12], "100 fully overlapped enemies / 180 projectiles")
	_expect(clumped.candidates == clumped.full and _event_count(clumped.events, "hit") == 18000,
		"Worst-case overlap intentionally retains every one of 18,000 contacts")
	_finished = true
