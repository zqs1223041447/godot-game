extends SceneTree
## Checks the local file and actual F8/button dispatch, without launching a browser.
## Cloud browser policy blocks file/loopback viewing; this is NOT rendered HTML QA.
const Model = preload("res://scripts/build_state.gd")
class Probe extends "res://scripts/main.gd":
	var reference_calls: int = 0
	var requested_path: String = ""
	func open_reference_catalog() -> bool:
		reference_calls += 1
		requested_path = reference_catalog_path()
		return not requested_path.is_empty()
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
	var model = Model.new()
	expect(model.save_build() == OK, "Save isolated fresh fixture")
	var arena := Probe.new()
	arena.state=Model.new() # This historical launch contract intentionally uses schema13.
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	var path: String = arena.reference_catalog_path()
	expect(path.is_absolute_path() and path.ends_with("docs/reference/index.html"), "Catalog resolves actual absolute local artifact")
	expect(FileAccess.file_exists(path), "Resolved artifact exists")
	var content: String = FileAccess.get_file_as_string(path)
	expect(content.contains("jewels-branchfinder") and content.contains("category-skills"), "Packaged manual has actual rule and skill anchors")
	expect(FileAccess.file_exists(path.get_base_dir().path_join("reference.js")) and FileAccess.file_exists(path.get_base_dir().path_join("reference.css")), "Relative offline scripts and styles accompany HTML")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F8
	event.pressed = true
	arena._unhandled_key_input(event)
	expect(arena.reference_calls == 1 and arena.requested_path == path, "Actual F8 dispatch requests the same local file")
	event.echo = true
	arena._unhandled_key_input(event)
	expect(arena.reference_calls == 1, "Key-repeat does not launch more copies")
	arena.hud.open_panel("pause")
	var button: Button = arena.hud.find_child("ReferenceCatalogButton", true, false)
	expect(button != null and not button.disabled, "Pause menu exposes dedicated local reference control")
	if button != null:
		button.pressed.emit()
		expect(arena.reference_calls == 2 and arena.requested_path == path, "Real button signal dispatches same local path")
	expect(arena.hud.is_blocking(), "Reference button keeps pause panel in place")
	arena.queue_free()
	await process_frame
	print("Reference launch wiring: %d checks, %d failures; browser deliberately not invoked" % [checks, failures])
	quit(1 if failures else 0)
