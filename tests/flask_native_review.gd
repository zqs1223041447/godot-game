extends SceneTree
## Isolated native review fixture; keeps actual arena input and recovery ticking.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless" or not OS.get_environment("XDG_DATA_HOME").contains("root-flask-native"):
		quit(78);return
	root.size=Vector2i(1280,720)
	var arena: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	for unused: int in range(6): await process_frame
	arena.auto_fire=false;arena.demo_mode=true;arena.enemies.clear();arena.spawn_timer=999999.0
	arena.health=10.0;arena.mana=10.0
	arena.hud._toast_left=0.0;arena.hud._toast.hide()
	while arena.hud.is_blocking(): arena.hud.close_panel()
	print("FLASK_NATIVE_REVIEW_READY")
