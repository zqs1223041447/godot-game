extends SceneTree
## Real Tab navigation of the talent details, with no allocation/refund actions.
const Settings = preload("res://scripts/visuals/visual_settings.gd")
const Data = preload("res://scripts/passives/source_tree_data.gd")
var arena: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func settle() -> void:
	for frame: int in range(3): await process_frame

func disk(path: String) -> Array:
	return [FileAccess.file_exists(path), FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()]

func preferences() -> Array:
	var settings: RefCounted = arena.visual_settings
	return [settings.ui_scale, settings.font_scale, settings.effects_level, settings.damage_numbers, settings.motion]

func tab(reverse: bool) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_TAB
		event.physical_keycode = KEY_TAB
		event.shift_pressed = reverse
		event.pressed = down
		root.push_input(event, true)
	await settle()

func visible_focus(target: Control, label: String) -> void:
	expect(root.gui_get_focus_owner() == target, label + " actual focus order")
	var bounds := target.get_global_rect()
	# Integer scroll offsets can leave less than one local unit of border clipped.
	var allowance: float = abs(target.get_global_transform().get_scale().y) + 0.001
	var style := target.get_theme_stylebox("normal")
	var content := Rect2(Vector2(style.get_content_margin(SIDE_LEFT), style.get_content_margin(SIDE_TOP)), target.size - style.get_minimum_size())
	var content_bounds: Rect2 = target.get_global_transform() * content
	expect(root.get_visible_rect().encloses(content_bounds), label + " content inside logical viewport")
	var ancestor := target.get_parent()
	while ancestor:
		if ancestor is Control and ancestor.clip_contents:
			var clip: Rect2 = ancestor.get_global_rect()
			if ancestor is ScrollContainer:
				if ancestor.get_v_scroll_bar().visible:
					clip.size.x = ancestor.get_v_scroll_bar().get_global_rect().position.x - clip.position.x
				if ancestor.get_h_scroll_bar().visible:
					clip.size.y = ancestor.get_h_scroll_bar().get_global_rect().position.y - clip.position.y
			expect(clip.grow_individual(0.001, allowance, 0.001, allowance).encloses(bounds), label + " border within one scroll unit of " + str(ancestor.name))
			expect(clip.encloses(content_bounds), label + " full content inside " + str(ancestor.name))
			expect(clip.has_point(bounds.get_center()), label + " interactive center inside " + str(ancestor.name))
		ancestor = ancestor.get_parent()

func variants(panel: Control) -> Dictionary:
	var result := {"allocated_start": panel.selected_node_id}
	var available: Array = arena.state.available_passives()
	if not available.is_empty(): result["available"] = available[0]
	var longest := ""
	var length := -1
	for id: String in Data.standard_ids():
		var node := Data.node(id)
		if node.type == "mastery" and not result.has("mastery"): result.mastery = id
		if node.type == "socket" and not result.has("socket"): result.socket = id
		var text_length := str(node.stats).length()
		if node.type != "mastery" and text_length > length:
			length = text_length
			longest = id
	result.long_description = longest
	return result

func run() -> void:
	if OS.get_name() != "Linux" or not OS.get_data_dir().begins_with("/tmp/godot-talent-focus-"):
		push_error("Requires fresh isolated Linux XDG storage /tmp/godot-talent-focus-*")
		quit(78)
		return
	create_timer(80.0).timeout.connect(func(): quit(1))
	var negative := OS.get_cmdline_user_args().has("--disable-follow-focus")
	root.size = Vector2i(1280, 720)
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.hud.set_process(false)
	await settle()
	expect(arena.state.save_build(arena.build_save_path) == OK, "Persist baseline through real save API")
	var before: Dictionary = arena.state.snapshot().duplicate(true)
	var saved := disk(arena.build_save_path)
	var practice_saved := disk("user://town_test_build_save.json")
	var settings_saved := disk(Settings.PATH)
	var rng: int = arena.rng.state
	var revision: int = arena.run_revision
	var cooldowns: Dictionary = arena.group_cooldowns.snapshot().duplicate(true)
	seed(515234)
	var expected_random := randi()
	seed(515234)
	arena.hud.open_panel("talents")
	await settle()
	var panel: Control = arena.hud._passive_panel
	var cases := variants(panel)
	expect(cases.size() == 5, "Five real node variants available")
	for ui: float in Settings.UI_SCALES:
		for font: float in Settings.FONT_SCALES:
			arena.visual_settings.ui_scale = ui
			arena.visual_settings.font_scale = font
			arena.hud._apply_presentation()
			var preferences_before := preferences()
			for variant: String in cases:
				for opening: int in range(2):
					arena.hud.close_panel()
					await settle()
					expect(not panel.is_visible_in_tree(), "Close hides talent panel")
					arena.hud.open_panel("talents")
					await settle()
					panel._tree.node_clicked.emit(cases[variant], MOUSE_BUTTON_LEFT, false)
					await settle()
					var scroll: ScrollContainer = panel._detail.get_parent().get_parent()
					var label := "ui=%.1f font=%.1f variant=%s node=%s opening=%d" % [ui, font, variant, cases[variant], opening]
					expect(root.get_visible_rect().size.is_equal_approx(Vector2(1280,720)), label + " logical viewport")
					expect(scroll.follow_focus, label + " production follows focus")
					var original_follow := scroll.follow_focus
					if negative: scroll.follow_focus = false
					var controls: Array[Control] = []
					for child: Node in panel._detail.get_parent().get_children():
						if child is Control and child.is_visible_in_tree() and child.focus_mode == Control.FOCUS_ALL:
							controls.append(child)
					expect(controls.has(panel._allocate) and controls.has(panel._refund), label + " action controls included")
					expect(controls.has(panel._mastery) == (variant == "mastery"), label + " mastery visibility")
					expect(controls.has(panel._socket) == (variant == "socket"), label + " socket visibility")
					scroll.scroll_vertical = 0
					panel._search.grab_focus()
					await settle()
					for target: Control in controls:
						await tab(false)
						visible_focus(target, label + " Tab " + str(target.name))
						expect_outer_scroll(label)
					await tab(false)
					for index: int in range(controls.size() - 1, -1, -1):
						await tab(true)
						visible_focus(controls[index], label + " Shift+Tab " + str(controls[index].name))
						expect_outer_scroll(label)
					await tab(true)
					expect(root.gui_get_focus_owner() == panel._search, label + " Shift+Tab returns to search")
					scroll.follow_focus = original_follow
					print("Talent focus matrix: %s controls=%d scroll=%d negative=%s" % [label, controls.size(), scroll.scroll_vertical, negative])
				expect(preferences() == preferences_before, "Navigation preserves presentation settings")
	arena.hud.close_panel()
	expect(arena.state.snapshot() == before, "Every canonical model field unchanged")
	expect(disk(arena.build_save_path) == saved, "Canonical save existence and bytes unchanged")
	expect(disk("user://town_test_build_save.json") == practice_saved, "Practice save existence and bytes unchanged")
	expect(disk(Settings.PATH) == settings_saved, "Settings existence and bytes unchanged")
	expect(arena.rng.state == rng and randi() == expected_random, "Arena and global RNG unchanged")
	expect(arena.run_revision == revision and arena.group_cooldowns.snapshot() == cooldowns, "Run revision and cooldowns unchanged")
	arena.free()
	await process_frame
	print("Talent details focus: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func expect_outer_scroll(label: String) -> void:
	expect(arena.hud._panel_scroll.scroll_vertical == 0 and arena.hud._panel_scroll.scroll_horizontal == 0, label + " outer scroll stays stationary")
