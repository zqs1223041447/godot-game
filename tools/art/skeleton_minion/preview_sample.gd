extends SceneTree
## Isolated art gallery; no Main, enemies, combat, physics, persistence or catalog registration.
const Art = preload("res://scripts/visuals/fantasy_actors.gd")
const Ground = preload("res://assets/environment/garden_ground.png")
const BASE := "res://docs/qa/kaykit-skeleton-minion/"

class Gallery extends Node2D:
	var textures: Dictionary = {}
	var durations: Dictionary = {}
	var floor_texture: Texture2D
	var seconds := 0.0
	var adapted := false
	var freeze := false
	var font: Font

	func _process(delta: float) -> void:
		if not freeze: seconds += delta
		queue_redraw()

	func _draw() -> void:
		# Same scale (0.4 world * 0.65 camera) and palette as FantasyEnvironment.
		texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * 0.26)
		draw_texture_rect(floor_texture, Rect2(Vector2.ZERO, Vector2(960, 540) / 0.26), true, Color("d4d7c1"))
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(0, 0, 960, 46), Color("292b27"))
		draw_string(font, Vector2(24, 28), "KayKit Skeletons 1.0 / 55 degrees / 64 x 96 display cells / " + ("fixed head tilt -25" if adapted else "author poses"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		var directions := ["south", "southeast", "east"]
		var clips := ["idle", "walk", "attack"]
		for row: int in 3:
			for column: int in 3:
				var clip: String = clips[column]
				var frame := mini(3, int(fmod(seconds, float(durations[clip])) / float(durations[clip]) * 4.0))
				var foot := Vector2(160 + column * 310, 160 + row * 165)
				if clip == "walk": foot.x += sin(seconds / float(durations[clip]) * TAU) * 24.0
				# Existing ordinary crawler radius14 is a visual reference only, not a new monster definition.
				var shadow_half_size := Vector2(18, 8.04) * .65
				Art._shadow(self, foot, shadow_half_size)
				Art._shadow(self, foot, shadow_half_size * .72)
				var key := "%s-%s-%02d" % [directions[row], clip, frame]
				draw_texture_rect(textures[key], Rect2(foot - Vector2(32, 79), Vector2(64, 96)), false)
				draw_string(font, Vector2(foot.x - 80, foot.y + 34), "%s / %s / f%d" % [directions[row], clip, frame], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("20251c"))

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var capture := args.size() == 2
	if args.size() > 2:
		push_error("Use -- author|head-fit for interactive gallery, optionally followed by a capture path")
		quit(1)
		return
	if not args.is_empty() and args[0] not in ["author", "head-fit"]:
		quit(1)
		return
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(960, 540)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var gallery := Gallery.new()
	gallery.adapted = args.is_empty() or args[0] == "head-fit"
	gallery.freeze = capture
	gallery.seconds = .8 if capture else 0.0
	gallery.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	gallery.font = ThemeDB.fallback_font
	var path := BASE + ("head-fit/" if gallery.adapted else "")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + "render-audit.json"))
	for clip: String in report.deformation: gallery.durations[clip] = float(report.deformation[clip].duration_seconds)
	for record: Dictionary in report.frames:
		var texture := ImageTexture.create_from_image(Image.load_from_file(path + record.path))
		assert(texture.get_size() == Vector2(128, 192))
		gallery.textures[record.path.get_file().get_basename()] = texture
	gallery.floor_texture = Ground
	root.add_child(gallery)
	if capture:
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(args[1]) == OK)
		print("Captured native isolated art gallery: %s; no game state created" % args[0])
		quit(0)
