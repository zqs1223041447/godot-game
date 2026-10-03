extends SceneTree
const Model = preload("res://scripts/build_state.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	call_deferred("run")
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
func run() -> void:
	var original: String = "broken save bytes that must survive\n"
	var file := FileAccess.open("user://build_save.json", FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var arena: Node = load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	await process_frame
	expect(not arena.state.save_block_reason().is_empty(), "Failed default load enters protected-save state")
	expect(arena.hud._active_panel == "pause", "Failed default load visibly pauses instead of silently replacing progress")
	expect(arena.hud._panel_footer.text.contains("未写入"), "Every open-panel footer explains persistence is paused")
	var exit_button: Button = arena.hud.find_child("ExitButton", true, false)
	expect(exit_button != null and exit_button.text.contains("未保存"), "Exit action never falsely claims it will save")
	arena.state.equip("swift_blade")
	expect(not arena.save_build(), "Default autosave cannot overwrite a rejected source")
	expect(FileAccess.get_file_as_string("user://build_save.json") == original, "Original bytes survive build changes and autosave attempts")
	expect(arena.state.save_build("user://manual_copy.json") == OK, "A separate valid copy can be saved")
	expect(not arena.state.save_block_reason().is_empty(), "Save As does not consume the protected source guard")
	var valid = Model.new()
	file = FileAccess.open("user://build_save.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(valid._snapshot()))
	file.close()
	expect(arena.state.load_build() and arena.state.save_block_reason().is_empty(), "A successful load after external restoration unlocks this path")
	expect(arena.save_build(), "Normal autosaving works after valid restoration")
	arena.hud.open_panel("pause")
	expect(not arena.hud._panel_footer.text.contains("未写入"), "Restored UI no longer reports a stale guard")
	print("Save guard integration: %d checks, %d failures" % [checks, failures])
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
