extends "res://tests/inward_pull_gameplay_test.gd"
func run() -> void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-v067-") or not OS.get_user_data_dir().begins_with(isolated+"/"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false)
	for scenario: Callable in [real_enemy_movement,frozen_ambush_build]:
		completed=false;scenario.call();check(completed,"Original section completes: "+scenario.get_method())
		if failures>0:break
	print("OLD_AREA_PULL checks=%d failures=%d"%[checks,failures])
	arena.queue_free();await process_frame;quit(1 if failures else 0)
