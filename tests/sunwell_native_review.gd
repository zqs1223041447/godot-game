extends SceneTree
## One static presentation review; not a gameplay or FPS benchmark.
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/v048-native"):
		quit(78)
		return
	var arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	var entered: Dictionary = arena.enter_town_test(arena.world_context().revision)
	var crafted: Dictionary = arena.craft_map("sunwell_terrace", [], [], arena.map_draft().revision)
	var started: Dictionary = arena.start_map(arena.map_draft().revision)
	if not entered.get("ok",false) or not crafted.get("ok",false) or not started.get("ok",false):
		push_error("Sunwell visual fixture could not enter the real map")
		quit(1)
		return
	arena.queue_redraw()
	print("Sunwell native review: real map prepared; simulation paused for layout inspection")
