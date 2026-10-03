extends SceneTree
var arena: Node2D
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(reason)
func frames(count: int = 6) -> void:
	for unused: int in range(count): await process_frame
func run() -> void:
	var isolated: String = OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m0-scene-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	var fresh := preload("res://scripts/build_state.gd").new()
	expect(fresh.save_build() == OK, "Fresh isolated scene save")
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.auto_fire = false
	arena.spawn_timer = 99999.0
	await frames()
	arena.hud.open_panel("inventory")
	await frames()
	var time_before: float = arena.elapsed
	var draws: int = arena._world_draw_count
	var background_draws: int = arena.static_environment.draw_count
	var state_before: Dictionary = arena.state._snapshot()
	var rng_before: int = arena.rng.state
	await frames(120)
	expect(arena.elapsed == time_before and arena.state._snapshot() == state_before and arena.rng.state == rng_before, "Menu freezes actual simulation and preserves build/RNG")
	expect(arena._world_draw_count == draws, "Paused arena does not queue repeated dynamic redraws")
	expect(arena.static_environment.draw_count == background_draws, "Static environment remains retained while paused")
	var diagnostics: Dictionary = arena.state.cache_diagnostics()
	var tooltip: String = arena.hud._skill_buttons[0].tooltip_text
	arena.mana = 0.0
	arena.cooldowns.bolt = 2.75
	arena.hud._update_live()
	expect(arena.hud._skill_buttons[0].text.contains("2.8s") and arena.hud._skill_buttons[0].tooltip_text == tooltip, "Dynamic cooldown changes without freezing/rebuilding static tooltip")
	arena.cooldowns.bolt = 0.0
	arena.hud._update_live()
	expect(arena.hud._skill_buttons[0].text.contains("法力不足"), "Dynamic mana gate remains live")
	arena.mana = 1000.0
	arena.hud._update_live()
	expect(arena.hud._skill_buttons[0].text.contains("就绪") and arena.state.cache_diagnostics() == diagnostics, "Dynamic UI does not trigger stable compilation")
	arena.state.set_skill_supports("bolt", ["focus"])
	arena.hud._update_live()
	expect(arena.hud._skill_buttons[0].tooltip_text != tooltip, "Actual support change refreshes static tooltip")
	for resolution: Vector2i in [Vector2i(1920,1080), Vector2i(2560,1440)]:
		root.size = resolution
		arena.visual_settings.font_scale = 1.2
		arena.hud._apply_presentation()
		await frames()
		draws = arena._world_draw_count
		var settled_background_draws: int = arena.static_environment.draw_count
		await frames()
		expect(arena._world_draw_count == draws, "Presentation invalidates once, then the paused background remains still")
		expect(arena.static_environment.draw_count == settled_background_draws, "After viewport/font invalidation, static geometry stays cached")
		background_draws = settled_background_draws
	arena.hud.close_panel()
	await frames()
	expect(arena.elapsed > time_before and arena._world_draw_count > draws, "Closing menu resumes simulation and dynamic rendering")
	expect(arena.static_environment.draw_count == background_draws, "Terrain remains cached during actual combat frames")
	arena.queue_free()
	await frames()
	print("M0 scene cache: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
