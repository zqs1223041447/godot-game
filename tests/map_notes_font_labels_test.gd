extends "res://tests/map_device_description_test.gd"
## Read-only regression for the disclosure labels; no pointer/transaction fixture.
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-map-notes-font-") or FileAccess.file_exists("user://build_save.json"):
		quit(78)
		return
	arena = ObservedArena.new()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	await settle()
	check(arena.save_build(), "Save isolated canonical profile")
	panel = arena.hud._town_view
	panel.open_service("map_device")
	await settle()
	var before := authority()
	for id: String in Maps.Catalog.MAPS:
		choose(panel._map_select, id)
		await settle()
		for expanded: bool in [false, true, false, true, false]:
			panel._map_notes_toggle.button_pressed = expanded
			await settle()
			notes_check(id, expanded)
			var expected := "− 布局与首领 · 收起" if expanded else "+ 布局与首领 · 展开"
			check(panel._map_notes_toggle.text == expected, "Bundled disclosure label matches state: " + id)
	check(authority() == before, "Repeated font-label disclosure changes no model, draft, resources, save or RNG")
	print("MAP_NOTES_FONT_LABELS ", JSON.stringify({"checks": checks, "failures": failures.size(), "failed_labels": failures, "display": DisplayServer.get_name()}))
	arena.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
