extends SceneTree
var arena: Node
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	var hud: Node = arena.hud
	check(hud._windows.size() == 8, "eight independently owned window roots")
	var identities := {}
	for view: Dictionary in hud._windows.values():
		identities[view.root.get_instance_id()] = true
		check(view.body.get_parent() == view.scroll, "each root owns its scroll and body")
	check(identities.size() == 8 and hud._root.find_child("BuildTabs", true, false) == null, "shared tab bar removed")
	var before: Dictionary = arena.state._snapshot()
	for sequence: Array in [[KEY_I,"inventory"],[KEY_T,"talents"],[KEY_K,"skills"],[KEY_F6,"combat"],[KEY_F7,"monsters"],[KEY_ESCAPE,""]]:
		await key(sequence[0])
		check(hud._active_panel == sequence[1], "key selects exact independent root")
		var visible_count := 0
		for view: Dictionary in hud._windows.values():
			if view.root.visible: visible_count += 1
		check(visible_count == (0 if str(sequence[1]).is_empty() else 1), "only selected root visible")
	check(before == arena.state._snapshot(), "menu switching does not mutate build")
	await key(KEY_ESCAPE)
	check(hud._active_panel == "pause", "Esc from world opens pause")
	await key(KEY_I)
	check(hud._active_panel == "inventory", "pause to inventory switches root")
	await key(KEY_ESCAPE)
	check(not hud.is_blocking(), "Esc after pause to inventory returns to world")
	await key(KEY_I)
	await key(KEY_I, true)
	check(hud._active_panel == "inventory", "keyboard echo cannot close root")
	await key(KEY_B)
	check(not hud.is_blocking(), "B toggles same inventory root")
	hud.open_panel("settings")
	check(hud.is_blocking() and hud._menu_routes.current_state().window == "settings", "button-driven settings shares route authority")
	await key(KEY_ESCAPE)
	check(not hud.is_blocking(), "Esc closes settings")
	hud.open_panel("talents")
	var passive_id: int = hud._passive_panel.get_instance_id()
	hud.open_panel("inventory")
	hud.open_panel("talents")
	check(hud._passive_panel.get_instance_id() == passive_id, "independent passive state retained across root switches")
	var elapsed: float = arena.elapsed
	var rng_state: int = arena.rng.state
	arena.set_process(true)
	for i: int in range(20): await process_frame
	check(arena.elapsed == elapsed and arena.rng.state == rng_state, "root menu freezes actual battle simulation")
	arena.set_process(false)
	hud.close_panel()
	check(not hud.is_blocking() and hud._menu_routes.current_state().window == "", "close button clears same route")
	print("Independent menus: %d checks, %d failures" % [checks, failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
func key(code: int, echo_value: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.echo = echo_value
	root.push_input(event, true)
	await process_frame
	await process_frame
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
