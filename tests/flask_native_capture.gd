extends SceneTree
## Four native layout pictures only; gameplay proof is separate and not rerun.
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for unused: int in range(6): await process_frame
	await RenderingServer.frame_post_draw
func run() -> void:
	var output: String=OS.get_environment("FLASK_CAPTURE_DIR")
	if DisplayServer.get_name()=="headless" or output.is_empty(): quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size=resolution
		var arena: Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena)
		arena.set_process(false);arena.set_physics_process(false);arena.auto_fire=false;arena.enemies.clear()
		await settle()
		while arena.hud.is_blocking(): arena.hud.close_panel()
		if resolution.x==2560:
			arena.visual_settings.ui_scale=1.1;arena.visual_settings.font_scale=1.2;arena.hud._apply_presentation()
		arena.hud._toast_left=0;arena.hud._toast.hide();arena.hud._update_live()
		await settle()
		root.get_texture().get_image().save_png(output.path_join("flasks-combat-%d.png"%resolution.x))
		arena.hud.open_panel("inventory");await settle()
		root.get_texture().get_image().save_png(output.path_join("flasks-inventory-%d.png"%resolution.x))
		arena.queue_free();await process_frame
	print("FLASK_NATIVE_CAPTURE_COMPLETE 4")
	quit()
