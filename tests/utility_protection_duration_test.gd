extends SceneTree
## One bounded Main consumer proof. Run only after the owner's editor import.
## Runtime positioning/timers are controlled; the default build and gear are real.
var arena: Node
var checks: int = 0
var failures: int = 0
var groups: Dictionary = {}
var build_before: Dictionary = {}
var disk_before: PackedByteArray


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	return value


func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.000001, "%s: %.10f / %.10f" % [label, actual, expected])


func isolated() -> bool:
	if OS.get_name() != "Linux": return false
	for key: String in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		if not OS.get_environment(key).simplify_path().begins_with("/tmp/godot-m1-"): return false
	return OS.get_user_data_dir().simplify_path().begins_with(OS.get_environment("XDG_DATA_HOME").simplify_path() + "/")


func prepare(protection: float = 0.0) -> void:
	while arena.hud.is_blocking(): arena.hud.close_panel()
	for action: String in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
	arena.enemies.clear()
	arena.projectiles.clear()
	arena.pickups.clear()
	arena.monster_runtime.reset()
	arena.telegraphs.reset()
	arena.burn_runtime.reset()
	arena.shock_runtime.reset()
	arena.freeze_runtime.reset()
	arena.trap_runtime.reset()
	arena.leech_runtime.clear()
	arena.group_cooldowns.reset()
	for id: String in arena.cooldowns: arena.cooldowns[id] = 0.0
	arena.burn_trace.clear()
	arena.incoming_damage_trace.clear()
	arena.visual_cues.reset()
	arena.particles.clear()
	arena.floating_text.clear()
	arena.rings.clear()
	arena.elapsed = 0.0
	arena._burn_step_active = false
	arena._burn_immunity_until = 0.0
	arena._burn_incoming_time = -1.0
	arena._autosave_timer = 0.0
	arena.alive = true
	arena.auto_fire = false
	arena.spawn_timer = 1000.0
	arena.boss_wave_pending = 0
	arena.player_pos = arena.ARENA.get_center()
	arena.player_facing = Vector2.RIGHT
	arena.health = float(arena._stats.max_health)
	arena.shield = float(arena._stats.max_shield)
	arena.mana = float(arena._stats.max_mana)
	arena.invulnerable = protection
	arena.damage_delay = 2.0


func cast(skill: String) -> bool:
	if skill == "dash": Input.action_press("move_right")
	var accepted: bool = arena.cast_group(str(groups[skill]))
	if skill == "dash": Input.action_release("move_right")
	return accepted


func outcome() -> Dictionary:
	return {"protection": arena.invulnerable, "mana": arena.mana, "shield": arena.shield,
		"health": arena.health, "delay": arena.damage_delay, "position": arena.player_pos,
		"cooldowns": arena.group_cooldowns.snapshot(), "rng": arena.rng.state,
		"critical": arena.critical_runtime.checkpoint(), "next_cast": arena.projectile_runtime.next_cast_id,
		"cues": arena.visual_cues.cues.duplicate(true), "particles": arena.particles.duplicate(true),
		"text": arena.floating_text.duplicate(true)}


func baseline_effects() -> void:
	for skill: String in ["dash", "ward"]:
		prepare()
		arena.shield = float(arena._stats.max_shield) * 0.1
		var before: Dictionary = outcome()
		var compiled: Dictionary = arena.state.get_group_cast(str(groups[skill]))
		check(cast(skill), "Default owned group accepts " + skill)
		near(arena.invulnerable, 0.6 if skill == "dash" else 0.8, "Standalone protection budget " + skill)
		near(arena.mana, float(before.mana) - float(compiled.mana), "Exactly the compiled mana cost " + skill)
		near(arena.group_cooldown_remaining(str(groups[skill])), float(compiled.cooldown), "Exactly the compiled group cooldown " + skill)
		near(arena.shield, float(before.shield) if skill == "dash" else float(arena._stats.max_shield) * 0.85, "Original shield restoration " + skill)
		near(arena.damage_delay, 2.0 if skill == "dash" else 0.0, "Original recharge wait behavior " + skill)
		check(arena.player_pos.is_equal_approx(Vector2(before.position) + Vector2(175.0, 0.0) if skill == "dash" else Vector2(before.position)), "Original movement/stationary behavior " + skill)
		check(arena.rng.state == before.rng and arena.critical_runtime.checkpoint() == before.critical, "Utility effect adds no shared or critical RNG draws " + skill)


func overlap_orders() -> void:
	for order: Array in [["ward", "dash"], ["dash", "ward"]]:
		prepare()
		check(cast(order[0]) and cast(order[1]), "Both different owned groups accept in order " + str(order))
		near(arena.invulnerable, 0.8, "Longer grant survives without adding durations " + str(order))
	for skill: String in ["dash", "ward"]:
		prepare(1.5)
		check(cast(skill), "Cast during existing start protection " + skill)
		near(arena.invulnerable, 1.5, "Preserve existing 1.5 seconds " + skill)
		arena.tick(0.5)
		near(arena.invulnerable, 1.0, "Existing protection still expires on its original clock " + skill)
	prepare()
	check(cast("ward"), "Start ward before elapsed overlap")
	arena.tick(0.1)
	check(cast("dash"), "Dash accepts after 0.1 seconds")
	near(arena.invulnerable, 0.7, "Keep remaining ward duration rather than reset to 0.8 or add 0.6")
	arena.tick(0.5)
	near(arena.invulnerable, 0.2, "Overlapped protection keeps elapsing")
	for skill: String in ["dash", "ward"]:
		prepare(0.125)
		check(cast(skill), "New grant accepts over shorter remaining protection " + skill)
		near(arena.invulnerable, 0.6 if skill == "dash" else 0.8, "New grant extends the shorter remainder " + skill)


func rejected_casts() -> void:
	for skill: String in ["dash", "ward"]:
		prepare(0.7)
		arena.mana = 0.0
		var before: Dictionary = outcome()
		check(not cast(skill) and outcome() == before, "No-mana rejection preserves protection and all cast effects " + skill)
		prepare(0.7)
		check(cast(skill), "Stage a genuine group cooldown " + skill)
		before = outcome()
		check(not cast(skill) and outcome() == before, "Cooling group rejection preserves protection and all cast effects " + skill)
		prepare(0.7)
		arena.hud.open_panel("pause")
		before = outcome()
		check(arena.hud.is_blocking() and not cast(skill) and outcome() == before, "Blocking HUD rejects without protection or cast mutation " + skill)
		arena.hud.close_panel()


func hit_cutoff() -> void:
	prepare()
	check(cast("ward") and cast("dash"), "Stage overlapping grants for the real incoming hit consumer")
	var before: Dictionary = outcome()
	check(not arena.hit_player_components({"physical": 10.0}) and outcome() == before, "Immediate incoming hit respects merged protection")
	arena.tick(0.4)
	before = outcome()
	check(not arena.hit_player_components({"physical": 10.0}) and outcome() == before, "Incoming hit is still refused inside protection")
	arena.tick(0.4)
	near(arena.invulnerable, 0.0, "Protection expires at 0.8 seconds")
	var resources: float = float(arena.shield) + float(arena.health)
	check(arena.hit_player_components({"physical": 10.0}) and float(arena.shield) + float(arena.health) < resources, "Real incoming hit settles after the exact cutoff")
	near(arena.invulnerable, 0.32, "Settled hit retains its original short protection")
	check(arena.incoming_damage_trace.size() == 1, "Only the post-cutoff hit reached actual settlement")


func burn_cutoff(split: bool) -> Dictionary:
	prepare()
	check(arena.burn_runtime.apply("player", 0, 999, 100.0, 3.0, 0.0).ok, "Attach controlled existing player burn")
	check(cast("ward") and cast("dash"), "Stage overlapping real utility casts for burning")
	var shield_before: float = float(arena.shield)
	var rng_before: int = arena.rng.state
	var critical_before: Dictionary = arena.critical_runtime.checkpoint()
	if split:
		arena.tick(0.4)
		arena.tick(0.4)
		check(is_equal_approx(arena.shield, shield_before) and arena.burn_trace.is_empty(), "No burn damage anywhere in the full merged 0.8-second window")
		arena.tick(0.1)
	else:
		arena.tick(0.9)
	var raw: float = 0.0
	for entry: Dictionary in arena.burn_trace: raw += float(entry.effective_raw_amount)
	near(raw, 10.0, "Burn charges only 0.1 seconds after protection, without catch-up")
	check(arena.invulnerable == 0.0 and arena.rng.state == rng_before and arena.critical_runtime.checkpoint() == critical_before, "Burn adds neither protection nor shared/critical RNG draws")
	var statuses: Array = arena.burn_statuses()
	check(statuses.size() == 1 and is_equal_approx(float(statuses[0].remaining_seconds), 2.1), "Burn lifetime elapses during protection as before")
	return {"shield": arena.shield, "health": arena.health, "raw": raw, "remaining": statuses[0].remaining_seconds if statuses.size() == 1 else -1.0}


func run() -> void:
	if not isolated():
		printerr("Utility protection test requires isolated Linux /tmp/godot-m1-* XDG data/config/cache roots")
		quit(78)
		return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	while arena.hud.is_blocking(): arena.hud.close_panel()
	if not check(arena.world_context().normal_town and not arena.world_context().test_mode, "Fresh default begins in the real normal town"):
		quit(1)
		return
	if not check(arena.leave_normal_town(arena.world_context().revision).ok, "Enter actual practice through the normal town transaction"):
		quit(1)
		return
	groups = {"dash": arena.state.group_for_key(KEY_4), "ward": arena.state.group_for_key(KEY_5)}
	if not check(not groups.dash.is_empty() and not groups.ward.is_empty() and arena.state.skill_group(groups.dash).skill_id == "dash" and arena.state.skill_group(groups.ward).skill_id == "ward", "Default owned dash and ward are real bound skill groups"):
		quit(1)
		return
	near(arena.invulnerable, 1.5, "Practice entry retains original start protection")
	build_before = arena.state.snapshot()
	disk_before = FileAccess.get_file_as_bytes(arena.build_save_path)
	baseline_effects()
	overlap_orders()
	rejected_casts()
	hit_cutoff()
	var whole: Dictionary = burn_cutoff(false)
	var split: Dictionary = burn_cutoff(true)
	check(is_equal_approx(float(whole.shield), float(split.shield)) and is_equal_approx(float(whole.health), float(split.health)) and is_equal_approx(float(whole.raw), float(split.raw)) and is_equal_approx(float(whole.remaining), float(split.remaining)), "Whole and subdivided Main ticks agree across the immunity cutoff")
	check(arena.state.snapshot() == build_before and FileAccess.get_file_as_bytes(arena.build_save_path) == disk_before, "All cases preserve the actual default build and saved bytes")
	print("Utility protection duration: %d checks, %d failures" % [checks, failures])
	print("UTILITY_PROTECTION_RESULT " + JSON.stringify({"checks": checks, "failures": failures, "whole_burn": whole, "split_burn": split, "scope": "Actual default Main groups, real practice entry and incoming hit/burn consumers; controlled runtime timers; no map, content, schema or performance test."}))
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
