extends SceneTree
var arena: Node2D
var output: String
var records: Array = []
func _initialize() -> void: call_deferred("run")
func frames(n: int = 6) -> void:
	for unused: int in range(n): await process_frame
func frame_image() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func run() -> void:
	var isolated: String = OS.get_environment("XDG_DATA_HOME")
	output = OS.get_environment("M0_VISUAL_OUT")
	if not isolated.begins_with("/tmp/godot-m0-visual-") or not OS.get_user_data_dir().begins_with(isolated + "/") or DisplayServer.get_name() == "headless" or not output.is_absolute_path():
		quit(78)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.title = "M0 cache and retained-world native pixel QA"
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.start_density_demo()
	arena.hud.close_panel()
	arena.auto_fire = false
	arena.rng.seed = 202610030
	arena.visual_settings.motion = false
	for enemy: Dictionary in arena.enemies:
		enemy.spawn = 0.0
	arena.state.skill_slots.assign(["tornado", "frost", "chain", "nova", "ward"])
	arena.state.skill_supports = {"tornado": ["volley", "focus"], "frost": ["heavy_projectiles", "lingering_chill"], "chain": ["chain_extension", "chain_reach"], "nova": ["breadth", "concentrate"], "ward": ["efficiency", "quickcast"]}
	arena.state.changed.emit()
	arena.mana = float(arena.get_stats().max_mana)
	arena.cast_skill(1)
	arena.hud._update_live()
	var retained: Node2D = arena.static_environment
	for resolution: Vector2i in [Vector2i(1280,720), Vector2i(2560,1440)]:
		root.size = resolution
		arena.visual_settings.ui_scale = 1.1
		arena.visual_settings.font_scale = 1.2
		arena.hud._apply_presentation()
		await frames()
		retained.hide()
		arena.static_environment = null
		arena.queue_redraw()
		await frames()
		var before: Image = await frame_image()
		before.save_png(output.path_join("inline-%d.png" % resolution.x))
		arena.static_environment = retained
		retained.show()
		arena.queue_redraw()
		await frames()
		var after: Image = await frame_image()
		after.save_png(output.path_join("retained-%d.png" % resolution.x))
		var equal: bool = before.get_data() == after.get_data()
		records.append({"width": resolution.x, "height": resolution.y, "pixel_identical": equal,
			"enemies": arena.enemies.size(), "projectiles": arena.projectiles.size(), "rendering": DisplayServer.get_name()})
		assert(equal, "Static layer must preserve the complete native image exactly")
	arena.hud.open_panel("inventory")
	await frames()
	var first: Image = await frame_image()
	first.save_png(output.path_join("paused-inventory-2k.png"))
	var world_draws: int = arena._world_draw_count
	var background_draws: int = retained.draw_count
	await frames(120)
	var last: Image = await frame_image()
	assert(first.get_data() == last.get_data(), "Paused native image must remain stable")
	assert(arena._world_draw_count == world_draws and retained.draw_count == background_draws)
	var report: Dictionary = {"rows": records, "paused_frames": 120, "paused_pixels_identical": true,
		"physical_mouse_tested": false, "windows_target_tested": false, "software_graphics": true}
	var file := FileAccess.open(output.path_join("native-pixel-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("M0_NATIVE_PIXEL_COMPLETE " + JSON.stringify(report))
	quit(0)
