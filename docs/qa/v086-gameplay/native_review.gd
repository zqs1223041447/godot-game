extends SceneTree
## Interactive native fixture. Legal Main entry, ordinary processes and actors.
## No gear, stats, currency, unlock, position, health or freeze modifications.
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v086-exploration-native-"):
		printerr("Use isolated XDG_DATA_HOME=/tmp/godot-m1-v086-exploration-native-*")
		quit(78)
		return
	var arena: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	var map_id: String=OS.get_environment("EXPLORATION_NATIVE_MAP")
	if map_id.is_empty():map_id="ginkgo_arcade"
	var crafted: Dictionary=arena.craft_normal_map(map_id,1,[],[],arena.map_draft().revision)
	if not crafted.get("ok",false):printerr(JSON.stringify(crafted));quit(1);return
	var started: Dictionary=arena.start_map(arena.map_draft().revision)
	if not started.get("ok",false):printerr(JSON.stringify(started));quit(1);return
	for unused: int in range(4):arena.hud.close_panel()
	print("EXPLORATION_NATIVE_READY map=%s roots_and_boss=%d save=%s ordinary_processes=true" % [map_id,arena.enemies.size(),arena.build_save_path])
