extends SceneTree
## Fixed published-source oracle; exact values/bytes, rather than a second optimized mode.
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Monsters = preload("res://scripts/monsters/monster_runtime.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
const Geometry = preload("res://scripts/world/map_geometry.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const ORACLE_PATH = "res://docs/qa/v038-projectiles/projectile_runtime_f074c26.gd.txt"
var Reference: GDScript
var checks := 0
var failures := 0
var completed: Array[String] = []
var report: Dictionary = {"source": "f074c2614540f0842964ced961b3430871adce57", "samples": [], "consumer_hashes": []}

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func digest(value: Variant) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(value))
	return hashing.finish().hex_encode()

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v038-projectile"):
		quit(78)
		return
	Reference = GDScript.new()
	Reference.source_code = FileAccess.get_file_as_string(ORACLE_PATH).replace("class_name ProjectileRuntime\n", "")
	if Reference.reload() != OK:
		quit(1)
		return
	_test_dense_replays()
	_test_exact_geometry()
	_test_lifecycle_and_ties()
	_test_seeded_and_mutable()
	await _test_consumers()
	expect(completed == ["density", "geometry", "lifecycle", "seeded", "consumers"], "Every test reaches its end without a script exception")
	report.checks = checks
	report.failures = failures
	report.scope = "Fixed 100-target spread/dense, 30/180 carriers, 20 paired one-tick repetitions; exact full events/shots/IDs/counters and seeded mutable-gate/lifecycle/wall differential. Timing is headless Linux CPU, never Windows FPS. Consumer replay uses actual main._update_projectiles and same RNG seed; no eligible rewards."
	var report_path:String=OS.get_environment("V038_PROJECTILE_REPORT")
	if report_path.is_empty():report_path="user://projectile-equivalence.json"
	FileAccess.open(report_path, FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true))
	print("Dense projectile equivalence: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _targets(layout: String) -> Array[Dictionary]:
	var factory := Monsters.new()
	var targets: Array[Dictionary] = []
	for i: int in range(100):
		var pos := Vector2(80 + (i % 10) * 100, 80 + int(i / 10) * 50) if layout == "spread" else Vector2(540 + (i % 10) * 14, 260 + int(i / 10) * 14)
		var enemy: Dictionary = factory.create_root("crawler", 1, pos, "ordinary", "normal", [], false)
		enemy.spawn = 0.0
		targets.append(enemy)
	return targets

func _dense_shots(runtime: RefCounted, cast: Dictionary, layout: String, amount: int) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	for j: int in range(amount):
		var origin := Vector2(60 + (j % 10) * 100, 70 + int(j % 100 / 10) * 50) if layout == "spread" else Vector2(530 + (j % 10) * 13, 250 + int(j % 100 / 10) * 13)
		shots.append(runtime.make_projectile(origin, Vector2.RIGHT, cast.recipe, cast.packets.projectile, cast.snapshot, runtime.new_cast(), Color.WHITE))
	return shots

func _test_dense_replays() -> void:
	var model := Model.new()
	var cast: Dictionary = Compiler.compile_group("bolt", model.get_combat_snapshot(), ["pierce"])
	expect(cast.ok, "Shipping bolt+pierce compiles")
	for layout: String in ["spread", "dense"]:
		var targets := _targets(layout)
		for amount: int in [30, 180]:
			var records: Array = []
			var replay_hash := ""
			for repetition: int in range(20):
				var a = Reference.new()
				var b = Runtime.new()
				var sa := _dense_shots(a, cast, layout, amount)
				var sb := _dense_shots(b, cast, layout, amount)
				var original_a := sa.duplicate()
				var original_b := sb.duplicate()
				var ea: Array[Dictionary]
				var eb: Array[Dictionary]
				var before_us := 0
				var after_us := 0
				# Alternate execution order so warm caches/load do not always favor b.
				for which: int in ([0, 1] if repetition % 2 == 0 else [1, 0]):
					var start := Time.get_ticks_usec()
					if which == 0:
						ea = a.advance(sa, 1.0 / 60.0, targets, Vector2(500, 300), 180)
						before_us = Time.get_ticks_usec() - start
					else:
						eb = b.advance(sb, 1.0 / 60.0, targets, Vector2(500, 300), 180)
						after_us = Time.get_ticks_usec() - start
				_compare(a, b, sa, sb, original_a, original_b, ea, eb, "%s/%d/%d" % [layout, amount, repetition])
				var outcome := digest([sb, eb, b.next_projectile_id, b.next_cast_id])
				if repetition == 0: replay_hash = outcome
				expect(replay_hash == outcome, "20 repeats retain identical replay digest")
				records.append({"before_us": before_us, "after_us": after_us, "events": eb.size(), "survivors": sb.size(), "candidate_visits": b.last_candidate_visits, "full_scan_visits": b.last_full_scan_visits, "queries": b.last_contact_queries})
			report.samples.append({"layout": layout, "shots": amount, "targets": 100, "same_replay_hash": replay_hash, "records": records})

	completed.append("density")

func _compare(a: RefCounted, b: RefCounted, sa: Array, sb: Array, oa: Array, ob: Array, ea: Array, eb: Array, label: String) -> void:
	expect(var_to_bytes(ea) == var_to_bytes(eb), label + " complete ordered events and Dictionary insertion bytes")
	expect(var_to_bytes([sa, oa]) == var_to_bytes([sb, ob]), label + " complete surviving and terminated original carriers")
	expect([a.next_projectile_id, a.next_cast_id, a._sequence] == [b.next_projectile_id, b.next_cast_id, b._sequence], label + " all IDs and event sequence")
	expect([a.last_contact_queries, a.last_candidate_visits, a.last_full_scan_visits, a.last_work_sorts, a.last_work_sort_skips] == [b.last_contact_queries, b.last_candidate_visits, b.last_full_scan_visits, b.last_work_sorts, b.last_work_sort_skips], label + " unchanged candidate/job ordering and counts")

func _shot(runtime: RefCounted, origin: Vector2 = Vector2.ZERO, changes: Dictionary = {}, heading: Vector2 = Vector2.RIGHT) -> Dictionary:
	var spec := {"speed": 100.0, "range": 100.0, "lifetime": 3.0, "radius": 0.0, "pierce": -1, "role": "child", "split": false}
	spec.merge(changes, true)
	var snapshot: Dictionary = Recipes.snapshot({"damage": 31.0, "attack_added_fire": 11.0}, ["return_on_range", "explode_on_flight_end"])
	return runtime.make_projectile(origin, heading, spec, Recipes.tornado_packet(snapshot, "parent" if spec.split else "child"), snapshot, runtime.new_cast(), Color.WHITE)

func _replay(initial: Array[Dictionary], targets: Array[Dictionary], steps: Array, label: String, capacity: int = 180, terrain: Callable = Callable(), mutable: bool = false) -> void:
	var a = Reference.new()
	var b = Runtime.new()
	var sa: Array[Dictionary] = initial.duplicate(true)
	var sb: Array[Dictionary] = initial.duplicate(true)
	var oa := sa.duplicate()
	var ob := sb.duplicate()
	var ta: Array[Dictionary] = targets.duplicate(true)
	var tb: Array[Dictionary] = targets.duplicate(true)
	for carrier: Dictionary in initial:
		a.next_projectile_id = maxi(a.next_projectile_id, int(carrier.id) + 1)
		a.next_cast_id = maxi(a.next_cast_id, int(carrier.cast_id) + 1)
	b.next_projectile_id = a.next_projectile_id
	b.next_cast_id = a.next_cast_id
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 3838180
	rng_b.seed = 3838180
	var ga := _gate.bind(ta, rng_a) if mutable else Callable()
	var gb := _gate.bind(tb, rng_b) if mutable else Callable()
	for i: int in range(steps.size()):
		var ea: Array[Dictionary] = a.advance(sa, float(steps[i]), ta, Vector2(17, -13), capacity, ga, terrain)
		var eb: Array[Dictionary] = b.advance(sb, float(steps[i]), tb, Vector2(17, -13), capacity, gb, terrain)
		_compare(a, b, sa, sb, oa, ob, ea, eb, label + "/" + str(i))
		expect(var_to_bytes(ta) == var_to_bytes(tb) and rng_a.state == rng_b.state, label + " mutable targets and gate RNG")

func _gate(shot: Dictionary, target_id: int, targets: Array[Dictionary], rng: RandomNumberGenerator) -> bool:
	var roll := rng.randi_range(0, 6)
	# Mutations visible to hit-event fields and later scheduling must never be cached.
	shot.color = Color(float(roll) / 7.0, 0.5, 0.75)
	shot.slow = float(roll) * 0.1
	shot.velocity = Vector2(shot.velocity).rotated(0.003)
	shot.radius = 2.0 + roll
	shot.age = float(shot.age) + 0.00001
	if roll == 4: shot.state = "returning"
	if roll == 5: shot.state = "outbound"
	if roll == 6: shot.pierce = 1
	shot.snapshot.modifiers.append({"id": "gate:" + str(target_id), "mode": "increased", "value": 0.0001})
	if roll == 2: shot.hit_ledger = {}
	for target: Dictionary in targets:
		if int(target.id) == target_id:
			target.pos += Vector2(0.5, -0.25)
			target.radius += 0.01
			target.health = maxf(0.0, float(target.health) - roll)
			target.spawn = 0.0 if roll % 2 else 0.01
			break
	return roll % 3 != 0

func _test_exact_geometry() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 38100180
	for i: int in range(2000):
		var start := Vector2(rng.randf_range(-2000, 2000), rng.randf_range(-1000, 1000))
		var end := start if i % 10 == 0 else start + Vector2(rng.randf_range(-600, 600), rng.randf_range(-600, 600))
		var center := start if i % 7 == 0 else start + Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
		var radius := rng.randf_range(0, 100)
		expect(Reference._segment_circle(start, end, center, radius) == Runtime._segment_circle(start, end, center, radius), "Exact narrowphase " + str(i))
	for center: Vector2 in [Vector2(50, 10), Vector2(50, 10.00001), Vector2(50, 9.99999), Vector2(100, 0), Vector2.ZERO]:
		expect(Reference._segment_circle(Vector2.ZERO, Vector2(100, 0), center, 10.0) == Runtime._segment_circle(Vector2.ZERO, Vector2(100, 0), center, 10.0), "Tangency/initial/end contact")

	var reference = Reference.new()
	var optimized = Runtime.new()
	var carrier := _shot(optimized)
	var contact_targets: Array[Dictionary] = [{"id": 3, "pos": Vector2(50, 0)}, {"id": 2, "pos": Vector2(50.0003, 0)}, {"id": 1, "pos": Vector2(50.0006, 0)}]
	contact_targets.append(contact_targets[1])
	for state: String in ["outbound", "returning"]:
		carrier.state = state
		for ledger: Dictionary in [{}, {"outbound:2": true}, {"returning:1": true, "outbound:3": true}]:
			carrier.hit_ledger = ledger
			expect(var_to_bytes(reference._contacts(carrier, Vector2.ZERO, Vector2(100, 0), contact_targets)) == var_to_bytes(optimized._contacts(carrier, Vector2.ZERO, Vector2(100, 0), contact_targets)), "Nontransitive contact times, alias target and phase-specific/nonempty ledger")
	completed.append("geometry")

func _test_lifecycle_and_ties() -> void:
	var builder = Runtime.new()
	var targets: Array[Dictionary] = [{"id": 1, "pos": Vector2(50, 0), "radius": 0.0, "health": 1000.0, "spawn": 0.0}]
	var shots: Array[Dictionary] = []
	for time: float in [1.000012, 1.0, 1.000006, 1.00001000005, 1.5]:
		shots.append(_shot(builder, Vector2.ZERO, {"lifetime": time, "range": 10000.0}))
	_replay(shots, targets, [2.0], "nontransitive approximate chain")
	shots.reverse()
	_replay(shots, targets, [2.0], "reversed approximate chain")
	shots[1].id = shots[0].id
	_replay(shots, targets, [2.0], "duplicate shot identity fallback")
	for capacity: int in [2, 3, 4, 180]:
		for expiry: float in [0.5, 0.5000000001, 0.6]:
			_replay([_shot(builder, Vector2.ZERO, {"split": true, "role": "parent", "range": 50.0}), _shot(builder, Vector2(1000, 1000), {"lifetime": expiry, "range": 10000.0})], targets, [1.0, 3.0], "capacity/expiry " + str(capacity) + "/" + str(expiry), capacity)
	var geometry := Geometry.new()
	expect(geometry.configure("broken_ruins", View.WORLD_ARENA), "Valid shipping arena wall fixture")
	var wall: Rect2 = geometry.snapshot().walls[0]
	var start := Vector2(wall.position.x - 106, wall.get_center().y)
	for lifespan: float in [10.0, 0.5]:
		for pierce: int in [-1, 0, 3]:
			_replay([_shot(builder, start, {"split": true, "role": "parent", "speed": 200.0, "range": 100.0, "lifetime": lifespan, "radius": 6.0, "pierce": pierce})], [{"id": 1, "pos": start + Vector2(40, 0), "radius": 8.0, "health": 1000.0}], [1.0, 3.0], "wall/range/lifetime/contact precedence", 180, geometry.sweep)

	completed.append("lifecycle")

func _test_seeded_and_mutable() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3818030
	for fixture: int in range(20):
		var builder = Runtime.new()
		var targets: Array[Dictionary] = []
		for i: int in range(100):
			targets.append({"id": i + 1, "pos": Vector2(rng.randf_range(-180, 180), rng.randf_range(-80, 80)), "radius": rng.randf_range(0, 30), "health": 0.0 if i % 17 == 0 else 1000.0, "spawn": 0.1 if i % 13 == 0 else 0.0})
		var shots: Array[Dictionary] = []
		for i: int in range(30):
			shots.append(_shot(builder, Vector2(rng.randf_range(-180, 180), rng.randf_range(-80, 80)), {"speed": rng.randf_range(20, 1800), "range": rng.randf_range(10, 500), "lifetime": rng.randf_range(0.1, 2.0), "radius": rng.randf_range(0, 8), "pierce": i % 4 - 1, "split": i % 7 == 0, "role": "parent" if i % 7 == 0 else "child"}, Vector2.RIGHT.rotated(rng.randf_range(-PI, PI))))
		_replay(shots, targets, [0.016, 0.033, 0.14, 0.37, 2.0], "seeded fixture " + str(fixture), 180, Callable(), fixture % 2 == 0)

	completed.append("seeded")

func _test_consumers() -> void:
	var a = load("res://scenes/main.tscn").instantiate()
	var b = load("res://scenes/main.tscn").instantiate()
	root.add_child(a)
	root.add_child(b)
	a.set_process(false)
	b.set_process(false)
	a.hud.set_process(false)
	b.hud.set_process(false)
	await process_frame
	a.projectile_runtime = Reference.new()
	b.projectile_runtime = Runtime.new()
	for arena in [a, b]:
		arena.enemies.clear()
		arena.projectiles.clear()
		arena.particles.clear()
		arena.floating_text.clear()
		arena.monster_runtime.reset()
		arena.monster_runtime.next_id = 0
		arena.auto_fire = false
		arena.total_damage = 0.0
		arena.kills = 0
		arena.combat_trace.clear()
		arena.damage_trace.clear()
		arena.attack_admission_trace.clear()
		arena.event_counts.clear()
		arena.visual_cues.reset()
		arena.rng.seed = 3810030
		for i: int in range(100):
			var enemy: Dictionary = arena._spawn_monster(["crawler", "skitter", "brute"][i % 3], Vector2(520 + (i % 10) * 14, 260 + int(i / 10) * 14), "demo", "normal", [], false)
			enemy.spawn = 0.0
			enemy.health = 30.0 + i
		for i: int in range(30):
			var carrier := _shot(arena.projectile_runtime, Vector2(510 + (i % 10) * 14, 250 + int(i / 10) * 14), {"speed": 250.0, "range": 50.0, "split": i % 4 == 0, "role": "parent" if i % 4 == 0 else "child", "radius": 5.0})
			carrier.snapshot.accuracy = 110.0
			arena.projectiles.append(carrier)
	for tick: int in range(16):
		a._update_projectiles(0.2)
		b._update_projectiles(0.2)
		var va := _consumer_values(a)
		var vb := _consumer_values(b)
		expect(var_to_bytes(va) == var_to_bytes(vb), "Actual main consumer all traces/health/shield/slow/knockback/deaths/particles/text/RNG tick " + str(tick))
		report.consumer_hashes.append(digest(vb))
	expect(a.total_damage > 0.0 and a.kills > 0, "Consumer replay actually settles damage and deaths")
	report.consumer_result = {"ticks": 16, "kills": b.kills, "total_damage": b.total_damage, "rng_state": b.rng.state, "event_counts": b.event_counts.duplicate(true)}
	a.queue_free()
	b.queue_free()
	await process_frame

	completed.append("consumers")

func _consumer_values(arena) -> Array:
	return [arena.enemies, arena.projectiles, arena.event_counts, arena.combat_trace, arena.damage_trace, arena.attack_admission_trace, arena.total_damage, arena.kills, arena.reward_kills, arena.particles, arena.floating_text, arena.rng.state, arena.monster_runtime.next_id, arena.monster_runtime.roots, arena.monster_runtime.queue, arena.monster_runtime.trace, arena.projectile_runtime.next_projectile_id, arena.projectile_runtime.next_cast_id, arena.projectile_runtime._sequence, arena.visual_cues.cues, arena.visual_cues.next_id, arena.visual_cues.dropped]
