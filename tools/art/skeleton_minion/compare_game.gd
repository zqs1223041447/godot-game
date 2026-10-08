extends SceneTree
## One fixed head-scale comparison on the real formal map and its current ground shader.
const Art = preload("res://scripts/visuals/fantasy_actors.gd")
const View = preload("res://scripts/visuals/world_view.gd")
var arena: Node2D

class Samples extends Node2D:
	var items: Array[Dictionary] = []
	func _draw() -> void:
		for item: Dictionary in items:
			Art._shadow(self, item.pos, Vector2(18, 8.04))
			Art._shadow(self, item.pos, Vector2(18, 8.04) * .72)
			draw_texture_rect(item.texture, Rect2(item.pos - Vector2(64, 158) / 1.3, Vector2(128, 192) / 1.3), false)

func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-skeleton-game-"):
		printerr("Use an isolated /tmp/godot-skeleton-game- XDG directory"); quit(78); return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	await process_frame
	for unused: int in 4: arena.hud.close_panel()
	assert(arena.save_build())
	assert(arena.craft_normal_map("ruins_garden", 1, [], [], arena.map_draft().revision).ok)
	var entered: Dictionary = await arena.open_map(arena.map_draft().revision)
	assert(entered.ok, str(entered.get("reason", "")))
	arena.set_process(false); arena.hud.hide()
	assert(arena.world_geometry().id == "ruins_garden")
	assert(arena.static_environment._study_ground.diagnostics().ready)
	var camera: Camera2D = arena.get_node("WorldCamera")
	assert(camera.zoom.is_equal_approx(Vector2.ONE * .65))
	var before := var_to_bytes([arena.state.snapshot(), arena.enemies, arena.health, arena.mana, arena.cooldowns,
		arena.attack_timer, arena.monster_runtime.next_id, arena.rng.state, FileAccess.get_file_as_bytes(arena.build_save_path)])
	var samples := Samples.new(); samples.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	arena.world_depth.add_child(samples)
	var overlay := CanvasLayer.new(); overlay.layer = 40; root.add_child(overlay)
	var note := Label.new(); note.position = Vector2(42, 36)
	note.text = "Skeleton head comparison / fixed -25 pitch / left 1.00, right 0.85\nFormal ruins_garden ground / actual 0.65 camera / combat paused / display copies only"
	font(note, 18); overlay.add_child(note)
	var headings := ["south", "southeast", "east"]
	var clips := ["idle", "walk", "attack"]
	var columns := [120, 190, 310, 380, 490, 560]
	for clip: int in 3:
		var heading := Label.new(); heading.position = Vector2(columns[clip * 2], 116)
		heading.text = clips[clip]; font(heading, 16); overlay.add_child(heading)
	for row: int in 3:
		for clip: int in 3:
			for variant: int in 2:
				var fraction_index := 1 if clip == 1 else 2 if clip == 2 else 0
				var folder := "head-fit-small" if variant == 1 else "head-fit"
				var path := "res://docs/qa/kaykit-skeleton-minion/%s/frames/%s-%s-%02d.png" % [folder, headings[row], clips[clip], fraction_index]
				var texture := ImageTexture.create_from_image(Image.load_from_file(path))
				assert(texture.get_size() == Vector2(128, 192))
				var screen := Vector2(columns[clip * 2 + variant], 200 + row * 162)
				var world: Vector2 = arena.get_global_transform_with_canvas().affine_inverse() * screen
				samples.items.append({"pos": world, "texture": texture})
				var label := Label.new(); label.position = screen + Vector2(-20, 20)
				label.text = "%.2f" % [.85 if variant else 1.0]
				font(label, 14); overlay.add_child(label)
		var direction_label := Label.new(); direction_label.position = Vector2(42, 170 + row * 162)
		direction_label.text = headings[row]; font(direction_label, 14); overlay.add_child(direction_label)
	samples.queue_redraw(); arena.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(before == var_to_bytes([arena.state.snapshot(), arena.enemies, arena.health, arena.mana, arena.cooldowns,
		arena.attack_timer, arena.monster_runtime.next_id, arena.rng.state, FileAccess.get_file_as_bytes(arena.build_save_path)]))
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1)
	assert(root.get_texture().get_image().save_png(args[0]) == OK)
	print("SKELETON_HEAD_GAME_COMPARE formal-ground=true scale=.65 display=64x96 authority-preserved=true")
	arena.queue_free(); await process_frame; quit(0)

func font(label: Label, size: int) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color("20251c"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
