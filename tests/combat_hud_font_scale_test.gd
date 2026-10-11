extends SceneTree
## Canonical HUD: independent font zoom, round trips, refresh and rebuilt hotbars.
const Preferences = preload("res://scripts/visuals/visual_settings.gd")
const ROOTS = ["RunStatus", "PlayerVitals", "Hotbar", "CombatHelp"]
var checks := 0
var failures := 0
var arena: Node
var hud: Node
var base_sizes: Array[int] = []
var clicked_buttons: Array[int] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)
func frames() -> void:
	for i in range(4): await process_frame
func controls() -> Array[Control]:
	var result: Array[Control] = []
	for name: String in ROOTS:
		for node: Node in hud._root.get_node(name).find_children("*", "Control", true, false):
			if node.has_theme_font_size_override("font_size"): result.append(node)
	return result
func verify_fonts(scale: float, stage: String) -> void:
	var current := controls()
	check(current.size() == base_sizes.size(), stage + " same authored controls")
	for index: int in range(current.size()):
		var control: Control = current[index]
		var key := str(hud._root.get_path_to(control))
		var base: int = base_sizes[index]
		check(base > 0 and control.get_theme_font_size("font_size") == roundi(base * scale), "%s %s font %.1f" % [stage, key, scale])
		check(control.get_meta("base_font_size", 0) == base, "%s preserves authored base %s" % [stage, key])
func verify_layout() -> void:
	var viewport_rect := hud.get_viewport().get_visible_rect()
	for control: Control in controls():
		if not control.is_visible_in_tree(): continue
		var rect := control.get_global_rect()
		check(viewport_rect.encloses(rect), "visible text stays inside logical viewport " + str(control.name))
		check(control.size.x + 0.1 >= control.get_minimum_size().x and control.size.y + 0.1 >= control.get_minimum_size().y, "text has minimum room " + str(control.name))
	for index: int in range(hud._skill_buttons.size()):
		var button: Button = hud._skill_buttons[index]
		check(button.size.x >= 94 and button.size.y >= 84, "skill hit target retained")
		for other: int in range(index + 1, hud._skill_buttons.size()):
			check(not button.get_global_rect().intersects(hud._skill_buttons[other].get_global_rect()), "skill hit targets do not overlap")
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	root.size = Vector2i(1280, 720)
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	hud = arena.hud
	hud.set_process(false)
	await frames()
	check(arena.state is CanonicalGameState, "actual canonical state")
	for control: Control in controls(): base_sizes.append(control.get_theme_font_size("font_size"))
	var before: PackedByteArray = var_to_bytes(arena.state.snapshot())
	var default_rects := {}
	for name: String in ROOTS + ["WorldControls"]: default_rects[name] = hud._root.get_node(name).get_rect()
	var origin: Vector2 = arena.player_pos
	var rng_state: int = arena.rng.state
	for ui: float in Preferences.UI_SCALES:
		for font: float in [1.0, 1.2, 1.0, 1.1]:
			hud.open_panel("settings")
			hud._set_ui_scale(Preferences.UI_SCALES.find(ui))
			hud._set_font_scale(Preferences.FONT_SCALES.find(font))
			await frames()
			verify_fonts(font, "settings")
			check(hud._root.get_node("RunStatus").get_rect().end.y + 9.0 <= hud._root.get_node("WorldControls").position.y, "status cannot cover map controls")
			hud.refresh_build()
			hud._apply_presentation()
			verify_fonts(font, "refresh")
			hud.close_panel()
			hud.open_panel("settings")
			check(hud._root.find_child("FontScaleOption", true, false).selected == Preferences.FONT_SCALES.find(font), "reopened font selection")
			check(hud._root.find_child("UIScaleOption", true, false).selected == Preferences.UI_SCALES.find(ui), "reopened UI selection")
			hud.close_panel()
			var loaded := Preferences.new()
			loaded.load_settings()
			check(loaded.font_scale == font and loaded.ui_scale == ui, "saved settings round trip")
			check(hud._root.scale.is_equal_approx(Vector2.ONE * ui), "independent UI transform")
			verify_fonts(font, "reopened")
			await frames()
			verify_layout()
	# Simulate replacing the retained hotbar while a larger preference is active.
	hud._set_font_scale(2)
	var old_hotbar: Node = hud._root.get_node("Hotbar")
	hud._root.remove_child(old_hotbar)
	old_hotbar.free()
	hud._skill_buttons.clear()
	hud._skill_emblems.clear()
	hud._build_hotbar()
	hud.refresh_build()
	check(hud._skill_buttons[0].get_theme_font_size("font_size") == 14, "new skill button scaled before another presentation pass")
	verify_fonts(1.2, "rebuilt")
	hud._reset_presentation()
	await frames()
	verify_fonts(1.0, "reset")
	for name: String in ROOTS + ["WorldControls"]:
		check(hud._root.get_node(name).get_rect().is_equal_approx(default_rects[name]), "reset restores authored geometry " + name)
	check(var_to_bytes(arena.state.snapshot()) == before, "presentation preserves canonical build and bindings")
	check(arena.player_pos == origin and arena.rng.state == rng_state, "presentation preserves world and RNG")
	# Real viewport dispatch, not direct signal emission, checks the largest targets.
	hud._set_ui_scale(2)
	hud._set_font_scale(2)
	hud._update_live()
	await frames()
	for index: int in range(hud._skill_buttons.size()):
		var button: Button = hud._skill_buttons[index]
		button.pressed.connect(func(): clicked_buttons.append(index))
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = button.get_global_rect().get_center()
		click.pressed = true
		root.push_input(click, true)
		click = click.duplicate()
		click.pressed = false
		root.push_input(click, true)
		await process_frame
		check(clicked_buttons.size() == index + 1 and clicked_buttons.back() == index, "viewport click reaches intended skill button %d" % index)
	print("Combat HUD font scale: %d checks, %d failures" % [checks, failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
