extends SceneTree
## Real pause menu, viewport input and logical geometry; no native visual/FPS claim.
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

func click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
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

func run() -> void:
	if OS.get_name() != "Linux" or not OS.get_data_dir().begins_with("/tmp/godot-"):
		push_error("Pause keyboard scroll requires isolated Linux XDG storage")
		quit(78)
		return
	create_timer(75.0).timeout.connect(func():
		push_error("Pause keyboard scroll timed out")
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
	if not require(not saved.is_empty(), "Guard observes actual canonical save bytes"): return
	var revision: int = arena.run_revision
	var rng_before: int = arena.rng.state
	seed(515231)
	var next_random: int = randi()
	seed(515231)
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		for font_scale: float in Settings.FONT_SCALES:
			for ui_scale: float in Settings.UI_SCALES:
				root.size = resolution
				arena.visual_settings.font_scale = font_scale
				arena.visual_settings.ui_scale = ui_scale
				hud._apply_presentation()
				hud.open_panel("pause")
				await settle()
				expect(root.get_visible_rect().size.is_equal_approx(Vector2(1280, 720)), "canvas_items preserves intended 1280x720 logical viewport")
				var scroll: ScrollContainer = hud._panel_scroll
				var control: Control = hud._panel_body.find_child("EncounterControls", true, false)
				if not require(control != null, "Pause embeds encounter controls"): return
				expect(scroll.follow_focus, "Production pause scroll follows keyboard focus")
				for panel_name: String in hud._windows:
					if panel_name not in ["pause", "settings"]:
						expect(not hud._windows[panel_name].scroll.follow_focus, "Unrelated panel retains default focus scrolling: " + panel_name)
				var original_follow_focus: bool = scroll.follow_focus
				if negative_control:
					scroll.follow_focus = false
				var widgets: Array[Control] = [hud._panel_body.find_child("ReferenceCatalogButton", true, false)]
				for id: String in control._options:
					widgets.append(control._options[id])
				widgets.append(control._confirm)
				if not require(widgets.size() == 8, "Reference action, six catalog options and confirm are traversed"): return
				# Establish only the starting focus; all later focus is real Tab input.
				scroll.scroll_vertical = 0
				widgets[0].grab_focus()
				await settle()
				var label := "window=%s logical=%s font=%.1f ui=%.1f" % [resolution, root.get_visible_rect().size, font_scale, ui_scale]
				visible_focus(widgets[0], scroll, label + " initial")
				for index: int in range(1, widgets.size()):
					await key(KEY_TAB)
					visible_focus(widgets[index], scroll, label + " Tab %d" % index)
				expect(scroll.scroll_vertical > 0, label + " Tab actually scrolls down")
				var bottom: int = scroll.scroll_vertical
				for index: int in range(widgets.size() - 2, -1, -1):
					await key(KEY_TAB, true)
					visible_focus(widgets[index], scroll, label + " Shift+Tab %d" % index)
				expect(scroll.scroll_vertical < bottom, label + " Shift+Tab actually scrolls back up")
				# A pointer toggle at a keyboard-reached location still changes only draft.
				var returned: int = scroll.scroll_vertical
				await key(KEY_TAB)
				await click(widgets[1])
				expect(control.get_selected_ids() == ["enemy_armour_80"], label + " actual pointer checks option")
				await click(widgets[1])
				expect(control.get_selected_ids().is_empty(), label + " actual pointer unchecks option")
				for index: int in range(2, widgets.size()):
					await key(KEY_TAB)
				await click(control._confirm)
				expect(hud._encounter_dialog.visible and hud._encounter_request_pending, label + " actual pointer opens confirmation")
				hud._encounter_dialog.canceled.emit()
				await settle()
				expect(not hud._encounter_dialog.visible and not hud._encounter_request_pending, label + " cancellation clears request")
				print("Pause keyboard matrix: %s bottom=%d return=%d" % [label, bottom, returned])
				# Do not leak the negative-control mutation into the next matrix cell.
				scroll.follow_focus = original_follow_focus
				hud.close_panel()
	expect(arena.state.snapshot() == before, "Navigation and canceled confirmation preserve every canonical build field")
	expect(disk("user://build_save.json") == saved and disk("user://town_test_build_save.json") == practice_saved, "Both save files remain byte-identical")
	expect(arena.run_revision == revision and arena.encounter_selection().is_empty(), "Navigation and cancel never restart or select an active encounter")
	expect(arena.rng.state == rng_before, "Arena RNG is unchanged")
	expect(randi() == next_random, "Global RNG is unchanged")
	arena.free()
	await process_frame
	print("Pause keyboard scroll: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
