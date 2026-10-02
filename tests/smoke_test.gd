extends SceneTree
## Run with: godot --headless --path . --script res://tests/smoke_test.gd

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run_checks")


func _run_checks() -> void:
	_expect(ProjectSettings.get_setting("application/config/name") == "godot游戏仓", "Project title")
	var main_path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	_expect(main_path == "res://scenes/main.tscn", "Main scene configured")
	var packed: PackedScene = load(main_path) as PackedScene
	if packed == null:
		_expect(false, "Main scene loads")
		_finish()
		return

	var scene: Node = packed.instantiate()
	root.add_child(scene)
	_expect(scene is Control, "Main scene instantiates")
	var title: Label = scene.get_node_or_null("Margin/Center/Content/Title") as Label
	_expect(title != null and title.text == "godot游戏仓", "Visible title")
	var button: Button = scene.get_node_or_null("Margin/Center/Content/QuitButton") as Button
	_expect(button != null, "Quit button exists")
	if button != null:
		_expect(button.pressed.is_connected(Callable(scene, "_on_quit_pressed")), "Quit signal connected")
	_expect(InputMap.has_action("ui_cancel"), "Escape action available")

	var preset := ConfigFile.new()
	var export_error: Error = preset.load("res://export_presets.cfg")
	_expect(export_error == OK, "Export preset parses")
	if export_error == OK:
		_expect(preset.get_value("preset.0", "platform", "") == "Windows Desktop", "Windows export target")
		_expect(preset.get_value("preset.0.options", "binary_format/architecture", "") == "x86_64", "64-bit export architecture")

	scene.free()
	_finish()


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _finish() -> void:
	if failures == 0:
		print("Smoke test passed")
	else:
		push_error("Smoke test failed: %d check(s)" % failures)
	quit(0 if failures == 0 else 1)
