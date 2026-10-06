extends SceneTree
## Same external 90-tick actual-main harness loads each project's own dependencies.
const Model = preload("res://scripts/canonical_game_state.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
var arena: Node
var checks := 0
var failures := 0
var completed := false
var report := {}
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok
func clean() -> void:
	arena.enemies.clear(); arena.projectiles.clear(); arena.pickups.clear(); arena.particles.clear(); arena.floating_text.clear(); arena.rings.clear()
	arena.monster_runtime = arena.MonsterLifecycle.new(); arena.telegraphs = arena.TelegraphRuntime.new()
	arena.projectile_runtime = arena.Projectiles.new(); arena.feedback_runtime = arena.FeedbackRuntime.new(); arena.visual_cues = arena.VisualCueRuntime.new()
	arena.burn_runtime.reset(); arena.shock_runtime.reset(); arena.leech_runtime.clear(); arena._sync_flasks(true)
	arena.damage_trace.clear(); arena.incoming_damage_trace.clear(); arena.burn_trace.clear(); arena.combat_trace.clear(); arena.attack_admission_trace.clear()
	arena.telegraph_trace.clear(); arena.event_counts.clear(); arena._ember_deaths.clear(); arena._ember_projectile_clock.clear()
	arena.group_cooldowns.reset(); arena.elapsed = 0.0; arena._burn_step_active = false; arena._burn_incoming_time = -1.0
	arena._burn_immunity_until = 0.0; arena.alive = true; arena.invulnerable = 0.0; arena.damage_delay = 0.0
	arena.auto_fire = false; arena.spawn_timer = 1000.0; arena._autosave_timer = 0.0; arena.wave = 1
	arena._simulation_accumulator = 0.0; arena._world_mode = "normal"; arena._geometry.configure("normal", arena.ARENA)
	arena._stats = arena.state.get_stats()
	for field: String in ["life_regen", "mana_regen", "shield_regen", "shield_recharge_rate"]: arena._stats[field] = 0.0
	arena.health = float(arena._stats.max_health) * 0.25; arena.shield = 0.0; arena.mana = float(arena._stats.max_mana) * 0.8
	arena.kills = 0; arena.reward_kills = 0; arena.total_damage = 0.0; arena.total_shots = 0; arena.attack_timer = 0.0
	arena._refresh_leech_caps(); arena.player_pos = arena.ARENA.get_center(); arena.player_facing = Vector2.RIGHT
	arena.rng.seed = 610061; arena.critical_runtime.reset(610062); arena._player_evasion_entropy = 13.25
	arena.hud._process(0.0); arena.hud.close_panel()
	check(not arena.hud.is_blocking(), "Controlled actual-main fixture is unpaused")
	for id: String in arena.Data.SKILLS: arena.cooldowns[id] = 0.0

func target(offset: Vector2 = Vector2(40, 0), rewarding: bool = false) -> Dictionary:
	var value: Dictionary = arena._spawn_monster("crawler", arena.player_pos + offset, "ordinary", "", [], rewarding)
	value.spawn = 0.0; value.health = 10000.0; value.max_health = 10000.0; value.shield = 0.0; value.max_shield = 0.0
	value.armour = 0.0; value.evasion = 1000000000.0; value.evasion_entropy = 13.25; value.radius = 1.0
	value.resistances = {}; value.speed = 0.0; value.attack_timer = 1000.0; value.shield_regen = 0.0; value.shield_recharge_rate = 0.0
	return value
func projected_model(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	check(int(result.version) in [42, 43], "Only schema42/schema43 version projection allowed")
	result.erase("version")
	return result
func projected_stats(raw: Dictionary) -> Dictionary:
	return raw.duplicate(true)
func legacy_probe(output: String) -> void:
	clean(); arena.rng.seed = 620882; arena.critical_runtime.reset(620882)
	for pending_uid: String in arena.state.pending_items():
		var place: Dictionary = arena.state.first_bag_position(pending_uid)
		if not check(not place.is_empty() and arena.state.move_item(pending_uid, place, arena.state.revision(), arena.build_save_path).ok, "Move recovery UID to real bag before reward"): return
	var old_uid: String = arena.state.award_equipment(arena.rng, 16, "rare", "defense")
	if not check(not old_uid.is_empty(), "Explicit immutable defense pool actually awards old gear"): return
	for item: Dictionary in arena.state.snapshot().items.values():
		if item.kind != "equipment": continue
		for affix: Dictionary in item.payload.get("affixes", []):
			if not check(affix.id not in ["ironhide", "mistweave"], "Independent baseline has no v62 families"): return
	check(arena.state.snapshot().talents.allocated.size() == 1, "No-node independent oracle uses default legal source root")
	if not check(arena.save_build(), "Legacy probe initial save succeeds"): return
	for index: int in range(8):
		var enemy := target(Vector2(75 + index * 12, 15 if index % 2 else -15), true)
		enemy.evasion = 0.0; enemy.health = 1.0 if index < 3 else 10000.0; enemy.max_health = enemy.health
	check(arena.burn_runtime.apply("player", 0, 71, 2.0, 0.75, 0.0).ok, "Actual existing player burn attaches")
	check(arena.burn_runtime.apply("monster", int(arena.enemies[-1].id), 0, 8.0, 0.75, 0.0).ok, "Actual existing monster burn attaches")
	arena.mana = float(arena._stats.max_mana)
	var samples: Array = []; var casts := 0
	for step: int in range(90):
		if step == 0: check(arena.hit_player_components({"physical":10.0}, 0, ["hit", "attack"]), "Legacy incoming attack exercised")
		if step in [0, 60]:
			if arena._execute_compiled(arena.state.get_skill_cast("nova")): casts += 1
		if step == 30:
			if arena._execute_compiled(arena.state.get_skill_cast("tornado")): casts += 1
		arena.auto_fire = true; arena.tick(1.0 / 60.0)
		var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(arena.build_save_path))
		if not check(disk is Dictionary, "Saved JSON parses before explicit version projection"): return
		samples.append({"enemies":arena.enemies.duplicate(true), "projectiles":arena.projectiles.duplicate(true),
			"queue":arena.monster_runtime.queue.duplicate(true), "roots":arena.monster_runtime.roots.duplicate(true),
			"rng":arena.rng.state, "model":projected_model(arena.state.snapshot()), "stats":projected_stats(arena._stats),
			"resources":[arena.health, arena.mana, arena.shield], "combat":arena.combat_trace.duplicate(true), "hits":arena.damage_trace.duplicate(true),
			"incoming":arena.incoming_damage_trace.duplicate(true), "admission":arena.attack_admission_trace.duplicate(true),
			"timer":arena.attack_timer, "cooldowns":arena.cooldowns.duplicate(true), "groups":arena.group_cooldowns.snapshot(),
			"flasks":arena.flask_runtime.snapshot(), "burns":arena.burn_runtime.statuses(), "shock":arena.shock_runtime.statuses(arena.elapsed),
			"critical":arena.critical_runtime.checkpoint(), "leech":arena.leech_runtime.snapshot(), "events":arena.event_counts.duplicate(true),
			"feedback":[arena.feedback_runtime._time, arena.feedback_runtime._pending.duplicate(true), arena.feedback_runtime._visible.duplicate(true)],
			"particles":arena.particles.duplicate(true), "text":arena.floating_text.duplicate(true), "pickups":arena.pickups.duplicate(true),
			"saves":arena.state.successful_saves, "saved_json":projected_model(disk)})
	check(casts > 0 and arena.kills >= 3 and arena.reward_kills >= 3 and arena.total_damage > 0.0, "Short actual legacy covers cast, attack, hit, kill, historical-pool award and save")
	if not check(arena.save_build(), "Legacy final save succeeds"): return
	FileAccess.open(output + ".bin", FileAccess.WRITE).store_buffer(var_to_bytes(samples))
	FileAccess.open(output + ".save", FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(arena.build_save_path))
	FileAccess.open(output + ".projected-save.json", FileAccess.WRITE).store_string(JSON.stringify(projected_model(arena.state.snapshot()), "\t", true, true))
	report = {"ticks":90, "seconds":arena.elapsed, "casts":casts, "kills":arena.kills, "reward_kills":arena.reward_kills,
		"damage":arena.total_damage, "rng":arena.rng.state, "critical":arena.critical_runtime.checkpoint(), "events":arena.event_counts,
		"version":arena.state.snapshot().version, "project_version":ProjectSettings.get_setting("application/config/version"), "historical_defense_item":arena.state.item(old_uid), "observation_projection":"version42/43 only; no stats, combat or source-cache projection"}
	completed = true

func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v067-legacy-") or not OS.get_user_data_dir().begins_with(isolated + "/"): quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	var output := OS.get_environment("PULL_LEGACY_OUTPUT")
	if output.is_empty(): quit(78); return
	legacy_probe(output); check(completed, "Legacy probe returned normally")
	report.merge({"checks":checks, "failures":failures})
	FileAccess.open(output + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t", true, true))
	print("PULL_LEGACY ", JSON.stringify(report))
	arena.queue_free(); await process_frame; quit(1 if failures else 0)
