extends SceneTree
## Explicit standalone launcher. It never opens the user's normal data directory.
const Session = preload("res://scripts/studies/modular_study_session.gd")
var arena: Node2D
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME").simplify_path()
	if not isolated.begins_with("/tmp/godot-m1-v112-"):
		printerr("Use tools/run_modular_study.sh: an isolated study data directory is required")
		quit(78); return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	arena.auto_fire = false
	for unused in 4: arena.hud.close_panel()
	if not arena.save_build(): fail("Study save failed"); return
	var draft: Dictionary = arena.craft_normal_map("old_garden", 1, [], [], arena.map_draft().revision)
	if not draft.ok: fail(draft.reason); return
	var entered: Dictionary = arena.start_map(arena.map_draft().revision)
	if not entered.ok: fail(entered.reason); return
	arena.set_process(false)
	var installed: Dictionary = await Session.install(arena)
	if not installed.ok: fail(installed.error); return
	var badge_layer := CanvasLayer.new()
	badge_layer.layer = 40
	root.add_child(badge_layer)
	var badge := Label.new()
	badge.text = "MODULAR ENVIRONMENT STUDY | isolated save | static direction hero"
	badge.position = Vector2(52, 80)
	badge.add_theme_font_size_override("font_size", 16)
	badge.add_theme_color_override("font_color", Color(0.94,0.86,0.63))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_layer.add_child(badge)
	arena.auto_fire = true
	arena.set_process(true)
	print("MODULAR_STUDY_READY roots=25 remapped=0 geometry=4 original_contours camera=0.65 isolated_data=true")
func fail(reason: String) -> void:
	printerr("MODULAR_STUDY_FAILED: ", reason)
	quit(1)
