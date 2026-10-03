extends SceneTree
## Descriptive same-host CPU probe for the canonical HUD and combat simulation.
## This reports neither rendered pixels nor Windows FPS and is not a pass/fail speed gate.

const SUPPORT_SETS := {
	"five_frost": ["swift_projectiles", "heavy_projectiles", "lingering_chill", "efficiency", "quickcast"],
	"five_tornado": ["volley", "focus", "physical_focus", "fire_focus", "efficiency"],
}
const TICK_COUNT := 600
const FIXED_TICK := 1.0 / 60.0

var failures := 0
var model_change_callbacks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolated_data: String = OS.get_environment("XDG_DATA_HOME")
	var scenario: String = OS.get_environment("CANONICAL_PERF_SCENARIO")
	var output_path: String = OS.get_environment("CANONICAL_PERF_OUT")
	if not isolated_data.begins_with("/tmp/godot-m4-") or not OS.get_user_data_dir().begins_with(isolated_data + "/"):
		quit(78)
		return
	if scenario not in ["default", "five_frost", "five_tornado"] or output_path.is_empty():
		quit(78)
		return

	var arena: Node2D = load("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	for unused: int in range(5):
		await process_frame

	var fixture_group := ""
	if scenario == "five_frost":
		fixture_group = "group_000002"
		if not _install_supports(arena, fixture_group, SUPPORT_SETS[scenario]):
			_fail("Could not configure the exact five-support frost group")
	elif scenario == "five_tornado":
		fixture_group = "group_000001"
		arena.equip_tornado_example()
		if not _install_supports(arena, fixture_group, SUPPORT_SETS[scenario]):
			_fail("Could not configure the exact five-support tornado group")
		if arena.state.skill_group(fixture_group).skill_id != "tornado":
			_fail("Tornado fixture must use the real equip_tornado_example setup")

	# Keep the real F7 density fixture: catalog actors and their authored stats stay intact.
	arena.start_density_demo()
	if arena.enemies.size() != 100:
		_fail("start_density_demo did not create 100 real directory monsters")
	arena.hud.handle_menu_key(KEY_F7, true, false)
	if arena.hud.is_blocking():
		_fail("F7 density panel did not close before simulation")
	arena.auto_fire = false
	arena.spawn_timer = 999999.0
	arena.rng.seed = 210021
	arena.invulnerable = 100.0

	var model_before_hud: Dictionary = arena.state.snapshot()
	var rng_before_hud: int = arena.rng.state
	for unused: int in range(10):
		arena.hud._update_live()
	var warmed_compiles: int = int(arena.state.cache_diagnostics().skill_compiles)
	for unused: int in range(240):
		arena.hud._update_live()
	var compile_after_hud: int = int(arena.state.cache_diagnostics().skill_compiles)
	var hud_state_unchanged: bool = arena.state.snapshot() == model_before_hud
	var hud_rng_unchanged: bool = arena.rng.state == rng_before_hud
	if not hud_state_unchanged or not hud_rng_unchanged:
		_fail("HUD warmup/240 updates changed model state or simulation RNG")
	if compile_after_hud != warmed_compiles:
		_fail("Warm HUD updates recompiled a cached skill recipe")

	var menu_timings: Dictionary = {}
	for menu: Dictionary in [
		{"name": "inventory", "key": KEY_I},
		{"name": "skills", "key": KEY_K},
		{"name": "talents", "key": KEY_T},
	]:
		var opens: Array[int] = []
		for toggle: int in range(3):
			var opened_at: int = Time.get_ticks_usec()
			arena.hud.handle_menu_key(int(menu.key), true, false)
			opens.append(Time.get_ticks_usec() - opened_at)
			if not arena.hud.is_blocking():
				_fail("Menu did not open: " + str(menu.name))
			await _frames(5)
			arena.hud.handle_menu_key(int(menu.key), true, false)
			if arena.hud.is_blocking():
				_fail("Menu did not close: " + str(menu.name))
			await _frames(5)
		menu_timings[str(menu.name)] = {
			"cold_first_open_ms": float(opens[0]) / 1000.0,
			"hot_reopen_ms": [float(opens[1]) / 1000.0, float(opens[2]) / 1000.0],
			"toggle_cycles": opens.size(),
		}

	# Exercise a blocked world while a window is open, including 120 direct process calls.
	arena.hud.handle_menu_key(KEY_T, true, false)
	await _frames(5)
	var frozen_elapsed: float = float(arena.elapsed)
	var frozen_world_draws: int = int(arena._world_draw_count)
	var frozen_terrain_draws: int = int(arena.static_environment.draw_count)
	var frozen_state: Dictionary = arena.state.snapshot()
	var frozen_rng: int = arena.rng.state
	for unused: int in range(120):
		arena._process(FIXED_TICK)
		arena.hud._process(FIXED_TICK)
	await _frames(5)
	var freeze_ok: bool = arena.elapsed == frozen_elapsed \
		and int(arena._world_draw_count) == frozen_world_draws \
		and int(arena.static_environment.draw_count) == frozen_terrain_draws \
		and arena.state.snapshot() == frozen_state and arena.rng.state == frozen_rng
	var freeze_elapsed_ok: bool = arena.elapsed == frozen_elapsed
	var freeze_world_draws_ok: bool = int(arena._world_draw_count) == frozen_world_draws
	var freeze_terrain_draws_ok: bool = int(arena.static_environment.draw_count) == frozen_terrain_draws
	var freeze_model_ok: bool = arena.state.snapshot() == frozen_state
	var freeze_rng_ok: bool = arena.rng.state == frozen_rng
	if not freeze_ok:
		_fail("Blocked-menu direct process calls changed elapsed, draw counters, model, or RNG")
	arena.hud.handle_menu_key(KEY_T, true, false)
	await _frames(5)

	var cast_groups: Array[String] = []
	if not fixture_group.is_empty():
		cast_groups.append(fixture_group)
	else:
		var group_index := 0
		for group: Dictionary in arena.state.snapshot().skill_groups:
			var contents: Dictionary = arena.state.skill_group(str(group.id))
			if group_index < arena.state.active_group_capacity() and not str(contents.skill_id).is_empty():
				cast_groups.append(str(group.id))
			group_index += 1

	var tick_samples: Array[int] = []
	var step_samples: Array[int] = []
	var cast_samples: Array[int] = []
	var cast_records: Array[Dictionary] = []
	var kill_steps: Array[Dictionary] = []
	var peak_projectiles: int = arena.projectiles.size()
	var max_kills_in_step := 0
	var max_step_usec := 0
	var max_kill_step_usec := 0
	for tick_index: int in range(TICK_COUNT):
		var step_started: int = Time.get_ticks_usec()
		var kills_before_step: int = int(arena.kills)
		var hits_before_step: int = int(arena.event_counts.get("hit", 0))
		var tick_started: int = Time.get_ticks_usec()
		arena.tick(FIXED_TICK)
		tick_samples.append(Time.get_ticks_usec() - tick_started)
		peak_projectiles = maxi(peak_projectiles, arena.projectiles.size())
		for group_id: String in cast_groups:
			var compiled: Dictionary = arena.state.get_group_cast(group_id)
			if not bool(compiled.get("ok", false)):
				continue
			if arena.group_cooldown_remaining(group_id) > 0.000001:
				continue
			if float(arena.mana) + 0.000001 < float(compiled.mana):
				continue
			if arena.projectiles.size() + int(compiled.get("initial_count", 0)) > 180:
				continue
			var mana_before: float = float(arena.mana)
			var projectile_count_before: int = arena.projectiles.size()
			var cast_started: int = Time.get_ticks_usec()
			var accepted: bool = arena.cast_group(group_id)
			var cast_usec: int = Time.get_ticks_usec() - cast_started
			if accepted:
				cast_samples.append(cast_usec)
				var mana_ok: bool = is_equal_approx(float(arena.mana), mana_before - float(compiled.mana))
				var cooldown_ok: bool = is_equal_approx(arena.group_cooldown_remaining(group_id), float(compiled.cooldown))
				if not mana_ok or not cooldown_ok:
					_fail("Accepted cast did not charge compiled mana/cooldown: " + group_id)
				cast_records.append({
					"tick": tick_index + 1,
					"group_id": group_id,
					"skill_id": str(compiled.skill_id),
					"cast_cpu_ms": float(cast_usec) / 1000.0,
					"mana_cost": float(compiled.mana),
					"mana_before": mana_before,
					"mana_after": float(arena.mana),
					"cooldown_seconds": float(compiled.cooldown),
					"recipe": compiled.get("recipe", {}).duplicate(true),
					"projectiles_created": arena.projectiles.size() - projectile_count_before,
					"compile_count": int(arena.state.cache_diagnostics().skill_compiles),
				})
				peak_projectiles = maxi(peak_projectiles, arena.projectiles.size())
		var step_usec: int = Time.get_ticks_usec() - step_started
		step_samples.append(step_usec)
		max_step_usec = maxi(max_step_usec, step_usec)
		var kills_this_step: int = int(arena.kills) - kills_before_step
		if kills_this_step > 0:
			max_kills_in_step = maxi(max_kills_in_step, kills_this_step)
			max_kill_step_usec = maxi(max_kill_step_usec, step_usec)
			kill_steps.append({
				"tick": tick_index + 1,
				"kills": kills_this_step,
				"real_hits": int(arena.event_counts.get("hit", 0)) - hits_before_step,
				"tick_cpu_ms": float(tick_samples.back()) / 1000.0,
				"tick_and_cast_cpu_ms": float(step_usec) / 1000.0,
			})

	var sim_digest: String = _simulation_digest(arena)
	var final_survivors: int = 0
	for enemy: Dictionary in arena.enemies:
		if float(enemy.get("health", 0.0)) > 0.0:
			final_survivors += 1

	# One progress transaction: five genuine canonical XP awards, five changed signals, one final save.
	var xp_before: int = int(arena.state.xp)
	var saves_before: int = int(arena.progress_save_success_count)
	var save_attempts_before: int = int(arena.progress_save_attempt_count)
	model_change_callbacks = 0
	var changed_counter := Callable(self, "_count_model_change")
	arena.state.changed.connect(changed_counter)
	var xp_started: int = Time.get_ticks_usec()
	arena._begin_progress_transaction()
	var awards_ok := true
	for unused: int in range(5):
		if not bool(arena.state.add_xp(1)) and int(arena.state.xp) <= xp_before:
			# add_xp's return means level-up; ordinary XP awards correctly return false.
			pass
		awards_ok = awards_ok and int(arena.state.xp) >= xp_before + 1
	arena._end_progress_transaction()
	var xp_flush_usec: int = Time.get_ticks_usec() - xp_started
	arena.state.changed.disconnect(changed_counter)
	var xp_result_ok: bool = awards_ok and int(arena.state.xp) == xp_before + 5 \
		and model_change_callbacks == 5 \
		and int(arena.progress_save_success_count) == saves_before + 1 \
		and int(arena.progress_save_attempt_count) == save_attempts_before + 1 \
		and FileAccess.file_exists("user://build_save.json") and arena.state.save_block_reason().is_empty()
	if not xp_result_ok:
		_fail("Five XP awards did not result in XP+5, five changed callbacks, and one successful save")

	var report: Dictionary = {
		"schema_version": 1,
		"scenario": scenario,
		"fixture_group": fixture_group,
		"fixture_supports": SUPPORT_SETS.get(scenario, []),
		"engine": Engine.get_version_info().string,
		"platform": OS.get_name(),
		"processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(),
		"display_server": DisplayServer.get_name(),
		"rendering_measured": false,
		"pixels_measured": false,
		"windows_fps_measured": false,
		"sim_seconds": TICK_COUNT / 60.0,
		"tick_count": tick_samples.size(),
		"hud": {
			"warmup_updates": 10,
			"measured_updates": 240,
			"state_unchanged": hud_state_unchanged,
			"rng_unchanged": hud_rng_unchanged,
			"warmup_compile_count": warmed_compiles,
			"compile_count_after_updates": compile_after_hud,
			"compile_count_stable": compile_after_hud == warmed_compiles,
		},
		"menu_open_timings": menu_timings,
		"blocked_menu_freeze": {
			"manual_process_calls": 120,
			"elapsed_frozen": freeze_elapsed_ok,
			"dynamic_world_draw_count_frozen": freeze_world_draws_ok,
			"terrain_draw_count_frozen": freeze_terrain_draws_ok,
			"model_frozen": freeze_model_ok,
			"rng_frozen": freeze_rng_ok,
			"pixels_not_measured_in_headless": DisplayServer.get_name() == "headless",
		},
		"combat": {
			"enemy_count_start": 100,
			"enemy_count_alive_end": final_survivors,
			"real_hit_events": int(arena.event_counts.get("hit", 0)),
			"damage_records_retained": arena.damage_trace.size(),
			"cast_groups": cast_groups,
			"casts": cast_records,
			"cast_count": cast_records.size(),
			"cast_cpu_ms": _summary(cast_samples),
			"peak_projectiles": peak_projectiles,
			"final_projectiles": arena.projectiles.size(),
			"tick_cpu_ms": _summary(tick_samples),
			"tick_and_cast_step_cpu_ms": _summary(step_samples),
			"single_tick_peak_ms": float(max_step_usec) / 1000.0,
			"max_kills_in_one_step": max_kills_in_step,
			"single_tick_peak_with_kill_ms": null if kill_steps.is_empty() else float(max_kill_step_usec) / 1000.0,
			"kill_steps": kill_steps,
			"simulation_sha256": sim_digest,
			"final_simulation_state": {
				"elapsed": arena.elapsed,
				"kills": arena.kills,
				"mana": arena.mana,
				"health": arena.health,
				"shield": arena.shield,
				"xp_before_batch": xp_before,
				"rng_state": arena.rng.state,
				"build_revision": arena.state.revision(),
				"skill_compile_count": int(arena.state.cache_diagnostics().skill_compiles),
			},
		},
		"xp_batch": {
			"awards": 5,
			"xp_before": xp_before,
			"xp_after": int(arena.state.xp),
		"changed_callbacks": model_change_callbacks,
			"save_attempt_delta": int(arena.progress_save_attempt_count) - save_attempts_before,
			"save_success_delta": int(arena.progress_save_success_count) - saves_before,
			"flush_ms": float(xp_flush_usec) / 1000.0,
			"verified": xp_result_ok,
		},
		"failures": failures,
	}
	var output_file := FileAccess.open(output_path, FileAccess.WRITE)
	if output_file == null:
		_fail("Could not write probe output: " + output_path)
	else:
		output_file.store_string(JSON.stringify(report, "\t"))
		output_file.close()
	print("CANONICAL_PERFORMANCE_PROBE=" + JSON.stringify(report))
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _install_supports(arena: Node2D, group_id: String, support_ids: Array) -> bool:
	var state = arena.state
	var desired: Dictionary = {}
	for support_id: String in support_ids:
		desired["support:" + support_id] = true
	var current: Dictionary = state.skill_group(group_id)
	for uid: String in current.support_uids:
		if not desired.has(str(state.item(uid).get("definition_id", ""))):
			var bag_position: Dictionary = state.first_bag_position(uid)
			if bag_position.is_empty() or not state.move_item(uid, bag_position, state.revision(), "user://build_save.json").get("ok", false):
				return false
	for index: int in range(support_ids.size()):
		var definition_id := "support:" + str(support_ids[index])
		var uid := ""
		for candidate_uid: String in state.snapshot().items:
			if state.item(candidate_uid).get("definition_id", "") == definition_id:
				uid = candidate_uid
				break
		if uid.is_empty():
			uid = state.award_gem(definition_id)
		if uid.is_empty():
			return false
		var moved: Dictionary = state.move_item(uid, {"kind": "skill_support", "group_id": group_id, "index": index},
			state.revision(), "user://build_save.json")
		if not moved.get("ok", false):
			return false
	var actual: Dictionary = state.skill_group(group_id)
	return actual.support_ids == support_ids


func _simulation_digest(arena: Node2D) -> String:
	var sim_state := {
		"enemies": arena.enemies.duplicate(true),
		"projectiles": arena.projectiles.duplicate(true),
		"event_counts": arena.event_counts.duplicate(true),
		"damage_trace": arena.damage_trace.duplicate(true),
		"rng_state": int(arena.rng.state),
		"group_cooldowns": arena.group_cooldowns.snapshot(),
		"model": arena.state.snapshot(),
	}
	return JSON.stringify(_canonical(sim_state), "", true, true).sha256_text()


func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var sorted := {}
		for key: Variant in keys:
			sorted[str(key)] = _canonical(value[key])
		return sorted
	if value is Array:
		var copied: Array = []
		for entry: Variant in value:
			copied.append(_canonical(entry))
		return copied
	if value is PackedByteArray:
		return value.hex_encode()
	if value is Vector2:
		return {"__vector2": [value.x, value.y]}
	if value is Vector2i:
		return {"__vector2i": [value.x, value.y]}
	if value is Color:
		return {"__color": [value.r, value.g, value.b, value.a]}
	if value is StringName:
		return str(value)
	if value is Object:
		var resource := value as Resource
		return {"__resource": resource.resource_path if resource != null else value.get_class()}
	return value


func _summary(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {"samples": 0, "mean": 0.0, "p50": 0.0, "p95": 0.0, "max": 0.0}
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	var total := 0
	for value: int in sorted:
		total += value
	return {
		"samples": sorted.size(),
		"mean": float(total) / float(sorted.size()) / 1000.0,
		"p50": float(sorted[int((sorted.size() - 1) * 0.50)]) / 1000.0,
		"p95": float(sorted[int((sorted.size() - 1) * 0.95)]) / 1000.0,
		"max": float(sorted.back()) / 1000.0,
	}


func _frames(count: int) -> void:
	for unused: int in range(count):
		await process_frame


func _fail(message: String) -> void:
	failures += 1
	push_error(message)


func _count_model_change() -> void:
	model_change_callbacks += 1
