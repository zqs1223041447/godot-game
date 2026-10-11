extends SceneTree

var checks := 0
var failures := 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if OS.get_name() != "Linux" or not OS.get_data_dir().begins_with("/tmp/godot-"):
		push_error("Encounter limit scene test requires isolated Linux XDG storage")
		quit(78)
		return
	var arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.hud.open_panel("pause")
	await process_frame
	var control = arena.hud._panel_body.find_child("EncounterControls", true, false)
	var before: Dictionary = arena.state.snapshot()
	var run_revision: int = arena.run_revision
	var rng_state: int = arena.rng.state
	var ids: Array[String] = ["enemy_max_health_120", "enemy_move_speed_110"]
	for id: String in ids:
		control._options[id].button_pressed = true
	expect(control.get_selected_ids() == ids, "Real pause menu accepts two challenge choices")
	control._options["enemy_damage_115"].button_pressed = true
	expect(control.get_selected_ids() == ids and not control._confirm.disabled, "Third callback preserves actionable pause-menu draft")
	control._options[ids[0]].button_pressed = false
	control._options["enemy_damage_115"].button_pressed = true
	expect(control.get_selected_ids() == ["enemy_damage_115", ids[1]], "Pause-menu draft can replace a choice immediately")
	control._confirm.pressed.emit()
	expect(arena.hud._encounter_dialog.visible, "Valid replacement still opens restart confirmation")
	expect(arena.hud._encounter_dialog.dialog_text.contains("凶猛") and arena.hud._encounter_dialog.dialog_text.contains("迅行"), "Confirmation describes replacement choices")
	arena.hud._encounter_dialog.canceled.emit()
	expect(not arena.hud._encounter_dialog.visible, "Cancel dismisses replacement confirmation")
	expect(arena.state.snapshot() == before and arena.run_revision == run_revision and arena.rng.state == rng_state, "Selection and cancellation preserve canonical state, current run and RNG")
	arena.hud.close_panel()
	arena.hud.open_panel("pause")
	await process_frame
	control = arena.hud._panel_body.find_child("EncounterControls", true, false)
	expect(control.get_selected_ids() == arena.encounter_selection() and not control._confirm.disabled, "Reopening reflects unchanged active run and usable controls")
	arena.free()
	await process_frame
	print("Encounter selection limit Main: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
