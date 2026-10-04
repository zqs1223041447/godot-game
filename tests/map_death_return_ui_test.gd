extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/v29root-death-"):
		quit(78); return
	var arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	var entered: Dictionary = arena.enter_town_test(arena.world_context().revision)
	if not entered.ok: push_error("entry failed"); quit(1); return
	var started: Dictionary = arena.start_map(arena.map_draft().revision)
	if not started.ok: push_error("map failed"); quit(1); return
	arena.alive = false
	arena.hud.open_panel("death")
	var button = arena.hud._root.find_child("DeathReturnTown",true,false)
	if button == null: push_error("no death return"); quit(1); return
	button.pressed.emit()
	var ok: bool = arena.world_context().mode == "town" and arena.alive and not arena.hud._menu_routes.snapshot().death_latched and not arena.hud.is_blocking()
	print("Map death return UI: ","PASS" if ok else "FAIL")
	arena.queue_free()
	await process_frame
	quit(0 if ok else 1)
