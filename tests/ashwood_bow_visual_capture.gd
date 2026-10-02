extends SceneTree
## Native-only v0.13 art QA. Launch with isolated XDG data and -- --output DIR.
## Captures the unchanged inventory UI at 720p/2K plus exact inventory/detail sizes.
const Model = preload("res://scripts/build_state.gd")
const Grid = preload("res://scripts/item_grid_view.gd")
const Painterly = preload("res://scripts/visuals/equipment_painterly_art.gd")
const Presentation = preload("res://scripts/visuals/visual_theme.gd")
var directory: String = "/tmp/ashwood-bow-native-qa"
var arena: Node2D
var panel: InventoryPanel

class ArtSizes extends Node2D:
	var entry: Dictionary
	func _draw() -> void:
		draw_style_box(Presentation.panel(), Rect2(0, 0, 600, 300))
		var font: Font = load("res://assets/fonts/arena_sans.otf")
		draw_string(font, Vector2(20, 30), "白蜡长弓 / native inventory art sizes", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Presentation.TEXT)
		var grid_box := Rect2(28, 65, 84, 126)
		for y: int in range(3):
			for x: int in range(2):
				var cell := Rect2(grid_box.position + Vector2(x, y) * 42.0, Vector2(42, 42))
				draw_rect(cell.grow(-1.0), Color("423123") if (x + y) % 2 == 0 else Color("3b2b20"))
				draw_rect(cell.grow(-1.0), Color("78603e"), false, 1.0)
		var box := grid_box.grow(-2.0)
		draw_rect(box, Color("30261e"))
		draw_rect(box, Color("8c6b42"), false, 1.0)
		var art_rect := box.grow(-5.0)
		art_rect.size.y -= 21.0
		Grid.draw_item_icon(self, entry, art_rect)
		draw_string(font, Vector2(28, 220), "42px cells · 2×3", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Presentation.TEXT)
		Grid.draw_item_icon(self, entry, Rect2(184, 69, 100, 100))
		draw_string(font, Vector2(165, 220), "108px detail control", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Presentation.TEXT)
		Grid.draw_item_icon(self, entry, Rect2(355, 53, 158, 238))
		draw_string(font, Vector2(350, 45), "material close-up", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Presentation.TEXT)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for unused: int in range(16):
		await process_frame
	await RenderingServer.frame_post_draw

func save_view(view: Viewport, label: String) -> void:
	await settle()
	var image: Image = view.get_texture().get_image()
	assert(image != null and not image.is_empty())
	assert(image.save_png(directory.path_join(label + ".png")) == OK)
	print("ASHWOOD_NATIVE_CAPTURE ", label, " ", image.get_size())

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Ashwood art pixel capture needs the established native desktop/rendering backend.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var output_index: int = args.find("--output")
	if output_index >= 0 and output_index + 1 < args.size():
		directory = args[output_index + 1]
	DirAccess.make_dir_recursive_absolute(directory)
	assert(Model.new().save_build() == OK)
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.auto_fire = false
	arena.hud.set_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 130013
	var id: String = arena.state.award_equipment(rng, 16, "rare", "local_weapon")
	assert(not id.is_empty())
	var entry: Dictionary = Grid.describe_item(arena.state, "item:" + id)
	assert(Painterly.canonical_id(entry) == "ashwood_bow")
	assert(Painterly.texture_for_entry(entry) != null)
	arena.visual_settings.ui_scale = 1.0
	arena.visual_settings.font_scale = 1.0
	arena.hud.open_panel("inventory")
	panel = arena.hud.find_child("InventoryPanel", true, false)
	panel.select_item("item:" + id)
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		root.size = dimensions
		arena.hud._apply_presentation()
		await save_view(root, "ashwood-inventory-%dx%d" % [dimensions.x, dimensions.y])
		print("ASHWOOD_UI_BOUNDS ", dimensions, " grid_cell=", Grid.CELL, " detail=", panel._detail_art.size, " item=", panel._grid.item_rect("item:" + id), " source=", Painterly.source_rect(entry))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(600, 300)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sheet := ArtSizes.new()
	sheet.entry = entry
	viewport.add_child(sheet)
	await save_view(viewport, "ashwood-native-art-sizes")
	print("ASHWOOD_VISUAL_CAPTURE_PASS")
	quit(0)
