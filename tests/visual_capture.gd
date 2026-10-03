extends SceneTree
## Developer-only deterministic renderer QA. Run on a real display, not headless.
var arena: Node
var capture_index: int = 0
var output_directory: String = OS.get_environment("GODOT_VISUAL_QA_DIR")
func _initialize() -> void:
	call_deferred("run")
func settle() -> void:
	for i: int in range(16):
		await process_frame
	await RenderingServer.frame_post_draw
func capture(label: String) -> void:
	arena.queue_redraw()
	await settle()
	var image: Image = root.get_texture().get_image()
	var file: String = output_directory.path_join("%02d-%s.png" % [capture_index,label])
	image.save_png(file)
	print("VISUAL_CAPTURE ",file," ",image.get_size())
	capture_index += 1
func run() -> void:
	if output_directory.is_empty():
		output_directory = "user://visual-qa"
	DirAccess.make_dir_recursive_absolute(output_directory)
	root.position = Vector2i(0,0)
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.start_monster_demo()
	arena.hud.close_panel()
	arena.elapsed = 2.5
	for enemy: Dictionary in arena.enemies:
		enemy.spawn = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 501
	if arena.state.has_method("award_equipment"):
		var gear_id: String = arena.state.award_equipment(rng,30,"rare")
		print("QA_GEAR ",gear_id)
		arena.set_meta("qa_gear_id",gear_id)
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size = dimensions
		await settle()
		for ui: float in [0.9,1.0,1.1]:
			arena.visual_settings.ui_scale = ui
			arena.visual_settings.font_scale = 1.2 if ui == 1.1 else 1.0
			arena.hud._apply_presentation()
			arena.hud.close_panel()
			await capture("%dx%d-ui%.0f-arena"%[dimensions.x,dimensions.y,ui*100])
			for panel: String in ["inventory","talents","settings"]:
				arena.hud.open_panel(panel)
				if panel == "inventory" and arena.has_meta("qa_gear_id"):
					arena.hud.find_child("InventoryPanel",true,false).select_item("item:"+str(arena.get_meta("qa_gear_id")))
				await capture("%dx%d-ui%.0f-%s"%[dimensions.x,dimensions.y,ui*100,panel])
	# Actual runtime projectile/event data, rendered at 2K in three lifecycle phases.
	arena.visual_settings.ui_scale = 1.0
	arena.visual_settings.font_scale = 1.0
	arena.hud._apply_presentation()
	arena.hud.close_panel()
	arena.enemies.clear()
	arena.rings.clear()
	arena.projectiles.clear()
	arena.state.equip("prism_bow")
	arena.state.equip("return_mantle")
	arena.state.equip("detonation_charm")
	arena.state.slot_skill(0,"tornado")
	arena.state.slot_skill(1,"frost")
	arena.state.slot_skill(2,"bolt")
	arena.player_pos = Vector2(640,340)
	arena.player_facing = Vector2.RIGHT
	arena.mana = float(arena.get_stats().max_mana)
	arena.cast_skill(0)
	arena.cast_skill(1)
	arena.cast_skill(2)
	for i: int in range(20):
		arena._update_projectiles(0.01)
		arena._update_effects(0.01)
	await capture("2560x1440-effects-outbound")
	for i: int in range(90):
		arena._update_projectiles(0.01)
		arena._update_effects(0.01)
	await capture("2560x1440-effects-return")
	for i: int in range(104):
		arena._update_projectiles(0.01)
		arena._update_effects(0.01)
	await capture("2560x1440-effects-explosion")
	root.size = Vector2i(1280,720)
	arena.visual_settings.ui_scale = 1.0
	arena.visual_settings.font_scale = 1.0
	arena.hud._apply_presentation()
	arena.hud.close_panel()
	print("VISUAL_MATRIX_COMPLETE; window remains open for interaction QA")
