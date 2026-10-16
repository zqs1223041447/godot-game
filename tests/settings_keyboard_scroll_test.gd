extends SceneTree
## Real settings menu, viewport input and logical geometry; no native visual/FPS claim.
const Model = preload("res://scripts/canonical_game_state.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
var checks: int = 0
var failures: int = 0
var arena: Node2D
var negative_control: bool = false

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func require(ok: bool, message: String) -> bool:
	expect(ok, message)
	if not ok:
		quit(1)
	return ok

func settle() -> void:
	for frame: int in range(5):
		await process_frame

func disk(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func key(code: int, shift: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await settle()

func visible_focus(target: Control, scroll: ScrollContainer, label: String) -> void:
	expect(root.gui_get_focus_owner() == target, label + " reaches expected focus")
	# Scroll offsets are integral while scaled controls have fractional bounds.
	# At most one logical pixel is allowed, never a larger clipping allowance.
	var clip: Rect2 = scroll.get_global_rect()
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	if bar.visible:
		clip.size.x = bar.get_global_rect().position.x - clip.position.x
	expect(clip.grow(1.0).encloses(target.get_global_rect()), label + " stays inside scroll content clip")
	expect(root.get_visible_rect().grow(1.0).encloses(target.get_global_rect()), label + " stays inside actual logical viewport")

func preferences() -> Array:
	var settings: RefCounted = arena.visual_settings
	return [settings.ui_scale, settings.font_scale, settings.effects_level, settings.damage_numbers, settings.motion]

func run() -> void:
	if OS.get_name() != "Linux" or not OS.get_data_dir().begins_with("/tmp/godot-"):
		push_error("Settings keyboard scroll requires isolated Linux XDG storage")
		quit(78)
		return
	create_timer(75.0).timeout.connect(func():
		push_error("Settings keyboard scroll timed out")
		quit(1))
	negative_control = OS.get_cmdline_user_args().has("--disable-follow-focus")
	root.size = Vector2i(1280, 720)
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	if not require(arena.state is Model, "Real main scene uses canonical model"): return
	if not require(arena.leave_normal_town(arena.world_context().revision).ok, "Enter practice via supported world API"): return
	await settle()
	var hud: Node = arena.hud
	var before: Dictionary = arena.state.snapshot().duplicate(true)
	var saved: PackedByteArray = disk("user://build_save.json")
	var practice_saved: PackedByteArray = disk("user://town_test_build_save.json")
	var presentation_saved: PackedByteArray = disk(Settings.PATH)
	if not require(not saved.is_empty(), "Guard observes actual canonical save bytes"): return
	var revision: int = arena.run_revision
	var rng_before: int = arena.rng.state
	seed(515232)
	var next_random: int = randi()
	seed(515232)
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		for font_scale: float in Settings.FONT_SCALES:
			for ui_scale: float in Settings.UI_SCALES:
				root.size = resolution
				# Set supported presentation inputs before navigation, never to expose a target.
				arena.visual_settings.font_scale = font_scale
				arena.visual_settings.ui_scale = ui_scale
				hud._apply_presentation()
				var preferences_before: Array = preferences()
				hud.open_panel("settings")
				await settle()
				expect(root.get_visible_rect().size.is_equal_approx(Vector2(1280, 720)), "canvas_items preserves intended 1280x720 logical viewport")
				var scroll: ScrollContainer = hud._panel_scroll
				expect(scroll.follow_focus, "Production settings scroll follows keyboard focus")
				for panel_name: String in hud._windows:
					expect(hud._windows[panel_name].scroll.follow_focus == (panel_name in ["pause", "settings"]), "Focus scrolling remains scoped to pause/settings: " + panel_name)
				var original_follow_focus: bool = scroll.follow_focus
				if negative_control:
					scroll.follow_focus = false
				var widgets: Array[Control] = []
				for stable_name: String in ["UIScaleOption", "FontScaleOption", "EffectsOption", "DamageNumbersToggle", "MotionToggle", "ResetVisualSettings", "BackToPause"]:
					var widget: Control = hud._panel_body.find_child(stable_name, true, false)
					if not require(widget != null, "Settings has control " + stable_name): return
					widgets.append(widget)
				# Only starting focus and starting scroll are established programmatically.
				scroll.scroll_vertical = 0
				widgets[0].grab_focus()
				await settle()
				var needs_scroll: bool = widgets[-1].get_global_rect().end.y > scroll.get_global_rect().end.y + 1.0
				var label := "window=%s logical=%s font=%.1f ui=%.1f" % [resolution, root.get_visible_rect().size, font_scale, ui_scale]
				visible_focus(widgets[0], scroll, label + " initial")
				for index: int in range(1, widgets.size()):
					await key(KEY_TAB)
					visible_focus(widgets[index], scroll, label + " Tab " + str(widgets[index].name))
				if needs_scroll:
					expect(scroll.scroll_vertical > 0, label + " clipped lower actions trigger actual scrolling")
				var bottom: int = scroll.scroll_vertical
				var needs_reverse_scroll: bool = widgets[0].get_global_rect().position.y < scroll.get_global_rect().position.y - 1.0
				for index: int in range(widgets.size() - 2, -1, -1):
					await key(KEY_TAB, true)
					visible_focus(widgets[index], scroll, label + " Shift+Tab " + str(widgets[index].name))
				expect(not needs_reverse_scroll or scroll.scroll_vertical < bottom, label + " Shift+Tab scrolls up when first control is above clip")
				expect(preferences() == preferences_before, label + " keyboard navigation preserves all presentation values")
				print("Settings keyboard matrix: %s bottom=%d return=%d needs_scroll=%s" % [label, bottom, scroll.scroll_vertical, needs_scroll])
				# Do not leak the negative-control mutation into the next matrix cell.
				scroll.follow_focus = original_follow_focus
				hud.close_panel()
	expect(arena.state.snapshot() == before, "Navigation preserves every canonical build field")
	expect(disk("user://build_save.json") == saved and disk("user://town_test_build_save.json") == practice_saved, "Both save files remain byte-identical")
	expect(disk(Settings.PATH) == presentation_saved, "Navigation does not write presentation settings")
	expect(arena.run_revision == revision and arena.encounter_selection().is_empty(), "Navigation never restarts or selects an active encounter")
	expect(arena.rng.state == rng_before, "Arena RNG is unchanged")
	expect(randi() == next_random, "Global RNG is unchanged")
	arena.free()
	await process_frame
	print("Settings keyboard scroll: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
