extends SceneTree
## Short paired settlement CPU samples, not rendering or Windows FPS.
const Main = preload("res://scripts/main.gd")
const Model = preload("res://scripts/canonical_game_state.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func reset(arena: Node, fixture: Array[Dictionary]) -> void:
	arena.enemies = fixture.duplicate(true)
	arena.rng.seed = 125180
	arena.total_damage = 0.0
	arena.combat_trace.clear(); arena.damage_trace.clear(); arena.event_counts.clear()
	arena.particles.clear(); arena.floating_text.clear()
	arena.visual_cues.reset(); arena.feedback_runtime.reset()
func observation(arena: Node) -> PackedByteArray:
	return var_to_bytes([arena.enemies, arena.total_damage, arena.rng.state,
		arena.combat_trace, arena.damage_trace, arena.event_counts, arena.particles,
		arena.visual_cues.cues, arena.feedback_runtime.entries(), arena.state.snapshot()])
func summary(samples: Array) -> Dictionary:
	var sorted := samples.duplicate(); sorted.sort()
	var total := 0
	for value: int in sorted: total += value
	return {"n": sorted.size(), "mean_us": float(total) / sorted.size(),
		"p50_us": sorted[sorted.size() / 2], "p95_us": sorted[int(sorted.size() * 0.95)]}
func run() -> void:
	var baseline_path := OS.get_environment("HIT_LOOKUP_BASELINE_MAIN")
	var output := OS.get_environment("HIT_LOOKUP_PROFILE_OUT")
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-hit-lookup-") or baseline_path.is_empty() or output.is_empty():
		printerr("Requires isolated /tmp/godot-hit-lookup-* data, HIT_LOOKUP_BASELINE_MAIN and HIT_LOOKUP_PROFILE_OUT")
		quit(78); return
	var baseline := GDScript.new()
	baseline.source_code = FileAccess.get_file_as_string(baseline_path)
	if baseline.reload() != OK: quit(1); return
	var arenas: Array[Node] = [baseline.new(), Main.new()]
	var fixtures: Array = []
	for arena: Node in arenas:
		arena.state = Model.new()
		arena.build_save_path = "user://lookup-profile.json"
		root.add_child(arena); arena.set_process(false); arena.hud.set_process(false)
		arena._world_mode = "normal"; arena.restart_run(); arena.auto_fire = false
		arena.enemies.clear(); arena.monster_runtime.reset()
		for i in 100:
			var enemy: Dictionary = arena.monster_runtime.create_root("crawler", 1, Vector2(i * 30, 300), "ordinary", "normal", [], false)
			enemy.spawn = 0.0; enemy.health = 10000.0
			arena.enemies.append(enemy)
		fixtures.append(arena.enemies.duplicate(true))
	var events: Array[Dictionary] = []
	var snapshot: Dictionary = Combat.snapshot({"damage": 1.0}, [])
	var packet: Dictionary = Damage.packet({"physical": 1.0}, ["hit", "projectile"], "basic")
	for i in 180:
		events.append({"type": "hit", "target_id": fixtures[0][i % 100].id, "payload": packet,
			"snapshot": snapshot, "color": Color.WHITE, "slow": 0.0,
			"direction": Vector2.RIGHT, "sequence": i, "time": 0.0})
	var samples: Array = [[], []]
	for repetition in 36:
		# Alternate the order, with four paired warmups excluded from timing.
		for which: int in ([0, 1] if repetition % 2 == 0 else [1, 0]):
			var arena: Node = arenas[which]
			reset(arena, fixtures[which])
			var began := Time.get_ticks_usec()
			var ok: bool = arena._settle_projectile_events(events)
			var elapsed_us := Time.get_ticks_usec() - began
			if repetition >= 4: samples[which].append(elapsed_us)
			if not ok: failures += 1
		if observation(arenas[0]) != observation(arenas[1]): failures += 1
	var report := {"scope": "Paired actual Main settlement, 100 real targets / 180 supplied hit events; setup and cloning excluded. Controlled phase CPU, not a full tick or Windows FPS.",
		"engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(),
		"pairs": 36, "failures": failures, "before": summary(samples[0]), "after": summary(samples[1]),
		"reference_target_visits_per_batch": 8290, "indexed_roster_visits_per_batch": 100, "hit_lookups_per_batch": 180}
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	for arena: Node in arenas: arena.queue_free()
	await process_frame
	print("PROJECTILE_HIT_LOOKUP_PROFILE ", JSON.stringify(report))
	quit(1 if failures else 0)
