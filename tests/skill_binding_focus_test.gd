extends SceneTree
## Real binding controls and viewport key input; logical geometry, not native pixel QA.
const Model = preload("res://scripts/canonical_game_state.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
var checks := 0
var failures := 0
var arena: Node
var negative_control := false

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func settle() -> void:
	for frame: int in range(3): await process_frame

func key(code: int, shift: bool = false, window: Window = root) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = down
		if window == root:
			root.push_input(event, true)
		else:
			event.window_id = root.get_window_id() if window.is_embedded() else window.get_window_id()
			Input.parse_input_event(event)
	await settle()

func disk(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func preferences() -> Array:
	var settings: RefCounted = arena.visual_settings
	return [settings.ui_scale, settings.font_scale, settings.effects_level, settings.damage_numbers, settings.motion]

func visible_focus(target: OptionButton, rows: ScrollContainer, label: String) -> void:
	expect(root.gui_get_focus_owner() == target, label + " focus order")
	var clip := rows.get_global_rect()
	if rows.get_v_scroll_bar().visible:
		clip.size.x = rows.get_v_scroll_bar().get_global_rect().position.x - clip.position.x
	# Integer scrolling can leave one local unit of border outside the clip.
	# Derive its logical-space allowance from the actual transform, not a magic pixel count.
	var allowance: float = abs(rows.get_global_transform().get_scale().y) + 0.001
	var bounds := target.get_global_rect()
	expect(clip.grow_individual(0.001, allowance, 0.001, allowance).encloses(bounds), label + " border within one local scroll unit")
	var style := target.get_theme_stylebox("normal")
	var content := Rect2(Vector2(style.get_content_margin(SIDE_LEFT), style.get_content_margin(SIDE_TOP)), target.size - style.get_minimum_size())
	var text_region: Rect2 = target.get_global_transform() * content
	expect(clip.encloses(text_region), label + " entire text/content region visible")
	expect(clip.has_point(bounds.get_center()), label + " interactive center visible")
	expect(root.get_visible_rect().encloses(text_region), label + " text/content inside logical viewport")
	expect(root.get_visible_rect().has_point(bounds.get_center()), label + " center inside logical viewport")

func run() -> void:
	if OS.get_name() != "Linux" or not OS.get_data_dir().begins_with("/tmp/godot-skill-focus-"):
		push_error("Requires fresh isolated Linux XDG storage /tmp/godot-skill-focus-*")
		quit(78)
		return
	create_timer(75.0).timeout.connect(func(): quit(1))
	negative_control = OS.get_cmdline_user_args().has("--disable-follow-focus")
	root.size = Vector2i(1280, 720)
	if DisplayServer.get_name() == "headless": root.gui_embed_subwindows = true
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.hud.set_process(false)
	await settle()
	var model: RefCounted = arena.state
	expect(model is Model, "Real canonical model")
	var capacity := 11 if OS.get_cmdline_user_args().has("--capacity11") else 10
	if capacity == 11:
		var fixture_rng := RandomNumberGenerator.new()
		fixture_rng.seed = 91414
		var extra_item := ""
		for attempt: int in range(8):
			var uid: String = model.award_equipment(fixture_rng, 30, "rare", "nine_slot")
			if uid.is_empty(): break
			if model.item_definition(uid).stats.has("additional_skill_slots"):
				extra_item = uid
				break
		expect(not extra_item.is_empty(), "Real generated additional-slot gear exists")
		if extra_item.is_empty(): quit(1); return
		var result: Dictionary = model.move_item(extra_item, {"kind":"equipment", "slot_id":model.item_definition(extra_item).category}, model.revision(), arena.build_save_path)
		expect(result.get("ok", false), "Equip generated gear via supported transaction")
	expect(model.active_group_capacity() == capacity, "Supported active capacity fixture")
	expect(model.save_build(arena.build_save_path) == OK, "Persist fixture before read-only navigation")
	var before: Dictionary = model.snapshot().duplicate(true)
	var saved := disk(arena.build_save_path)
	var practice_saved := disk("user://town_test_build_save.json")
	var settings_saved := disk(Settings.PATH)
	expect(not saved.is_empty(), "Observe real canonical save bytes")
	var rng_before: int = arena.rng.state
	var run_revision: int = arena.run_revision
	var cooldowns: Dictionary = arena.group_cooldowns.snapshot().duplicate(true)
	seed(515232)
	var expected_random := randi()
	seed(515232)
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		for font: float in Settings.FONT_SCALES:
			for ui: float in Settings.UI_SCALES:
				root.size = resolution
				arena.visual_settings.font_scale = font
				arena.visual_settings.ui_scale = ui
				arena.hud._apply_presentation()
				var preferences_before := preferences()
				arena.hud.open_panel("skills")
				await settle()
				var rows: ScrollContainer = arena.hud._skill_support_panel._rows
				var controls: Array = rows._binding_controls.values()
				var label := "capacity=%d window=%s logical=%s font=%.1f ui=%.1f" % [capacity, resolution, root.get_visible_rect().size, font, ui]
				expect(root.get_visible_rect().size.is_equal_approx(Vector2(1280, 720)), label + " actual logical viewport")
				expect(controls.size() == capacity, label + " actual supported row count")
				expect(rows.follow_focus, label + " production follows focus")
				for slot: Node in rows.find_children("*Gem_*", "Button", true, false):
					expect(slot.focus_mode == Control.FOCUS_NONE, label + " gem slot retains no keyboard focus")
				var original_follow_focus := rows.follow_focus
				if negative_control: rows.follow_focus = false
				rows.scroll_vertical = 0
				controls[0].grab_focus()
				await settle()
				visible_focus(controls[0], rows, label + " initial")
				for index: int in range(1, controls.size()):
					await key(KEY_TAB)
					visible_focus(controls[index], rows, label + " Tab %d" % index)
				expect(rows.scroll_vertical > 0, label + " lower rows cause actual scrolling")
				var bottom := rows.scroll_vertical
				# Open the keyboard-reached bottom binding; prove dismissal before reverse traversal.
				await key(KEY_ENTER)
				var popup: PopupMenu = controls[-1].get_popup()
				expect(popup.visible, label + " focused binding opens through Enter")
				if popup.visible: await key(KEY_ESCAPE, false, popup)
				expect(not popup.visible, label + " popup really dismissed before further traversal")
				if popup.visible:
					rows.follow_focus = original_follow_focus
					arena.free()
					quit(1)
					return
				for index: int in range(controls.size() - 2, -1, -1):
					await key(KEY_TAB, true)
					visible_focus(controls[index], rows, label + " Shift+Tab %d" % index)
				expect(rows.scroll_vertical < bottom, label + " reverse traversal scrolls upward")
				expect(preferences() == preferences_before, label + " presentation values unchanged")
				rows.follow_focus = original_follow_focus
				expect(rows.follow_focus, label + " per-cell follow flag restored")
				print("Skill focus matrix: %s bottom=%d return=%d negative=%s" % [label, bottom, rows.scroll_vertical, negative_control])
				arena.hud.close_panel()
	expect(model.snapshot() == before, "Every model field unchanged")
	expect(disk(arena.build_save_path) == saved and disk("user://town_test_build_save.json") == practice_saved, "Canonical and practice save bytes unchanged")
	expect(disk(Settings.PATH) == settings_saved, "Settings file bytes unchanged")
	expect(arena.rng.state == rng_before and randi() == expected_random, "Arena and global RNG unchanged")
	expect(arena.run_revision == run_revision and arena.group_cooldowns.snapshot() == cooldowns, "Run revision and cooldowns unchanged")
	arena.free()
	await process_frame
	print("Skill binding focus: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
