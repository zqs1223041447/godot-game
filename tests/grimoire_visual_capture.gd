extends SceneTree
var arena: Node
var output: String=OS.get_environment("GODOT_GRIMOIRE_QA_DIR")
func _initialize()->void: call_deferred("run")
func settle()->void:
	for i: int in range(16): await process_frame
	await RenderingServer.frame_post_draw
func shot(label: String)->void:
	await settle()
	var image: Image=root.get_texture().get_image()
	image.save_png(output.path_join(label+".png"))
	print("CAPTURE ",label," ",image.get_size())
func run()->void:
	if output.is_empty(): output=ProjectSettings.globalize_path("user://grimoire-qa")
	DirAccess.make_dir_recursive_absolute(output)
	root.title="Grimoire UI v0.12 QA"
	arena=load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.auto_fire=false
	arena.elapsed=2.5
	arena.hud.set_process(false)
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(2560,1080)]:
		root.size=dimensions
		for scale: float in [1.0,1.1]:
			arena.visual_settings.ui_scale=scale
			arena.visual_settings.font_scale=1.2 if scale>1.0 else 1.0
			arena.hud._apply_presentation()
			for panel: String in ["inventory","skills","talents","settings",""]:
				if panel.is_empty(): arena.hud.close_panel()
				else: arena.hud.open_panel(panel)
				await shot("%dx%d-%d-%s"%[dimensions.x,dimensions.y,roundi(scale*100),panel if not panel.is_empty() else "hud"])
	root.size=Vector2i(1280,720)
	arena.visual_settings.ui_scale=1.0
	arena.visual_settings.font_scale=1.0
	arena.hud._apply_presentation()
	arena.hud.open_panel("inventory")
	print("GRIMOIRE_CAPTURE_COMPLETE")
	if "--quit-on-complete" in OS.get_cmdline_user_args(): quit()
