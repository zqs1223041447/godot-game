extends SceneTree
## Non-gating headless CPU benchmark. No hardware-dependent FPS threshold.
## Compares the same deterministic real scene, 100 actors and 180 projectiles.
## Reference disables both spatial lookup and cached work ordering.
## Full tick timing includes AI, projectile collision/damage, and visual cue updates;
## it excludes rendering, HUD frame processing, setup, and fixture cloning.
## Run in disposable XDG directories. JSON lines are suitable for saving/comparing.
const Model = preload("res://scripts/build_state.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Runtime = preload("res://scripts/combat/projectile_runtime.gd")
const STEP: float = 1.0 / 60.0
var arena: Node2D
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fresh = Model.new()
	if fresh.save_build() != OK:
		push_error("Could not save isolated benchmark fixture")
		quit(1)
		return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	print("Density benchmark environment: %s; %s; %s; %d logical processors; headless debug engine; no rendering/FPS claim" % [OS.get_name(), Engine.get_version_info().string, OS.get_processor_name(), OS.get_processor_count()])
	for scenario: String in ["steady_no_hit", "mixed_hits", "clustered_mixed", "burst_180_hits"]:
		var results: Array[Dictionary] = []
		for indexed: bool in [false, true]:
			_prepare(scenario, indexed)
			for warmup: int in range(5):
				arena.tick(STEP)
			_prepare(scenario, indexed)
			results.append(_measure(scenario, indexed))
			print(JSON.stringify(results.back().summary))
		if results[0].final != results[1].final:
			failures += 1
			push_error("Indexed/reference final state differs in " + scenario)
		else:
			print("Exact full tick state equivalence: " + scenario)
	print("Density benchmark: %d differential failures; timings are descriptive, never a pass/fail threshold" % failures)
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _prepare(scenario: String, indexed: bool) -> void:
	# New lifecycle IDs make exact comparisons independent of previous scenarios.
	arena.monster_runtime.next_id = 0
	arena.start_density_demo()
	arena.hud.close_panel()
	arena.use_spatial_separation = indexed
	arena.projectile_runtime = Runtime.new()
	arena.projectile_runtime.use_spatial_index = indexed
	arena.projectile_runtime.use_cached_work_order = indexed
	arena.rng.seed = 8100818
	arena.health = 100000.0
	arena.shield = 0.0
	arena.invulnerable = 100.0
	arena.auto_fire = false
	arena._autosave_timer = 0.0
	var random := RandomNumberGenerator.new()
	random.seed = 7201440
	for index: int in range(arena.enemies.size()):
		var enemy: Dictionary = arena.enemies[index]
		enemy.pos = arena.ARENA.position + Vector2(100 + (index % 10) * 165, 40 + int(index / 10) * 48)
		if scenario == "clustered_mixed":
			enemy.pos = arena.player_pos + Vector2(random.randf_range(-140, 140), random.randf_range(-140, 140))
		enemy.health = 100000.0
		enemy.max_health = 100000.0
		enemy.spawn = 0.0
	var snapshot: Dictionary = Recipes.snapshot({"damage": 1.0}, [])
	for index: int in range(180):
		var origin: Vector2 = arena.ARENA.position + Vector2(random.randf_range(80, 1740), random.randf_range(30, 660))
		var direction: Vector2 = Vector2.RIGHT.rotated(random.randf_range(-PI, PI))
		var speed: float = 450.0
		var pierce: int = -1
		if scenario == "steady_no_hit":
			origin = Vector2(arena.ARENA.position.x + 20 + (index % 60) * 7, arena.ARENA.end.y - 30)
			direction = Vector2.RIGHT
		elif scenario == "burst_180_hits":
			var target: Dictionary = arena.enemies[index % 100]
			origin = Vector2(target.pos) - Vector2(float(target.radius) + 5.5 + 8.0, 0)
			direction = Vector2.RIGHT
			speed = 1800.0
			pierce = 0
		arena.projectiles.append(arena.projectile_runtime.make_projectile(origin, direction,
			{"speed": speed, "range": 20000.0, "lifetime": 60.0, "radius": 5.5, "pierce": pierce},
			Damage.packet({"physical": 1.0, "fire": 0.5}, ["hit", "projectile"], "basic"),
			snapshot, arena.projectile_runtime.new_cast(), Color.WHITE))


func _measure(scenario: String, indexed: bool) -> Dictionary:
	var samples: Array[int] = []
	var enemy_candidates: int = 0
	var enemy_full: int = 0
	var projectile_candidates: int = 0
	var projectile_full: int = 0
	var work_sorts: int = 0
	var work_sort_skips: int = 0
	var work_order_checks: int = 0
	var hits: int = 0
	var fixture: Array[Dictionary] = arena.enemies.duplicate(true)
	var carriers: Array[Dictionary] = arena.projectiles.duplicate(true)
	var initial_rng: int = arena.rng.state
	var frames: int = 60 if scenario == "burst_180_hits" else 120
	var total_usec: int = 0
	for frame: int in range(frames):
		if scenario == "burst_180_hits":
			# Every sample starts with 180 simultaneous genuine hits, not 179 empty ticks.
			# Reset/cloning is outside the measured region.
			arena.enemies = fixture.duplicate(true)
			arena.projectiles = carriers.duplicate(true)
			arena.projectile_runtime = Runtime.new()
			arena.projectile_runtime.use_spatial_index = indexed
			arena.projectile_runtime.use_cached_work_order = indexed
			arena.rng.state = initial_rng
			arena.combat_trace.clear()
			arena.damage_trace.clear()
			arena.event_counts.clear()
			arena.visual_cues.reset()
			arena.particles.clear()
			arena.floating_text.clear()
			arena.total_damage = 0.0
		var hits_before: int = int(arena.event_counts.get("hit", 0))
		var start: int = Time.get_ticks_usec()
		arena.tick(STEP)
		var duration: int = Time.get_ticks_usec() - start
		samples.append(duration)
		total_usec += duration
		enemy_candidates += arena.separation_candidate_visits
		enemy_full += arena.separation_full_scan_visits
		projectile_candidates += arena.projectile_runtime.last_candidate_visits
		projectile_full += arena.projectile_runtime.last_full_scan_visits
		work_sorts += arena.projectile_runtime.last_work_sorts
		work_sort_skips += arena.projectile_runtime.last_work_sort_skips
		work_order_checks += arena.projectile_runtime.last_work_order_checks
		hits += int(arena.event_counts.get("hit", 0)) - hits_before
	samples.sort()
	var summary: Dictionary = {"scenario": scenario, "mode": "indexed_cached" if indexed else "historical_reference", "frames": frames,
		"spatial_lookup": indexed, "cached_work_order": indexed,
		"initial_actors": 100, "initial_projectiles": 180, "tick_ms_mean": total_usec / float(frames) / 1000.0,
		"tick_ms_p50": samples[int(frames * 0.5)] / 1000.0, "tick_ms_p95": samples[mini(frames - 1, int(frames * 0.95))] / 1000.0,
		"tick_ms_max": samples.back() / 1000.0, "actual_hit_events": hits,
		"enemy_candidate_visits": enemy_candidates, "enemy_full_scan_visits": enemy_full,
		"projectile_candidate_visits": projectile_candidates, "projectile_full_scan_visits": projectile_full,
		"work_sorts": work_sorts, "work_sort_skips": work_sort_skips, "work_order_checks": work_order_checks,
		"final_actors": arena.enemies.size(), "final_projectiles": arena.projectiles.size()}
	if scenario == "steady_no_hit" and hits != 0:
		failures += 1
		push_error("No-hit benchmark unexpectedly produced contacts")
	if scenario == "burst_180_hits" and hits != 180 * frames:
		failures += 1
		push_error("Burst benchmark did not produce 180 genuine contacts per frame")
	return {"summary": summary, "final": {"enemies": arena.enemies.duplicate(true), "projectiles": arena.projectiles.duplicate(true),
		"health": arena.health, "shield": arena.shield, "elapsed": arena.elapsed, "total_damage": arena.total_damage,
		"event_counts": arena.event_counts.duplicate(true), "damage_trace": arena.damage_trace.duplicate(true),
		"combat_trace": arena.combat_trace.duplicate(true), "state": arena.state._snapshot()}}
