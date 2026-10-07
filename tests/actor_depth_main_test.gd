extends SceneTree
## Actual Main presentation wiring only; isolated user:// supplied by validate.sh.
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func snapshot(arena: Node) -> PackedByteArray:
	return var_to_bytes([arena.state.snapshot(), arena.enemies, arena.projectiles, arena.rng.state, arena.elapsed, arena.player_pos, arena.player_facing, arena.attack_timer, arena.world_geometry(), arena._map_run.snapshot(), arena.visual_cues.cues])
func run() -> void:
	var arena: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	for unused: int in range(4): arena.hud.close_panel()
	check(arena.world_context().normal_town, "Fresh actual Main starts in formal town")
	check(arena.world_depth == arena.retained_actors and arena.world_depth.name == "WorldDepth" and arena.world_depth.y_sort_enabled, "Main installs exactly one shared WorldDepth")
	check(arena.dimensional_props != null, "Main installs the independent scenery manager")
	check(not arena.world_geometry().has("dimensional_wall_indices"), "Scenery coverage remains outside authoritative world geometry")
	arena.retained_actors.sync(arena)
	var hero: Node2D = arena.retained_actors._hero
	check(is_instance_valid(hero) and hero.get_parent() == arena.world_depth and hero.position == arena.player_pos, "Actual hero body is a foot root in shared depth")
	var initial_elapsed: float = arena.elapsed
	var initial_time: float = arena.retained_actors._visual_time
	var start: Vector2 = arena.player_pos
	Input.action_press("move_right")
	for unused: int in range(12):
		arena._process(1.0 / 60.0)
		arena.retained_actors.sync(arena)
	Input.action_release("move_right")
	check(arena.player_pos.x > start.x and arena.elapsed == initial_elapsed and arena.retained_actors._visual_time > initial_time, "Real held town input advances independent display time without combat elapsed")
	check(hero.animation == "walk" and hero.direction == 0 and hero.frame > 4, "Actual town hero advances east-walk atlas frames")
	var before := snapshot(arena)
	var disk_before := FileAccess.get_file_as_bytes(arena.build_save_path) if FileAccess.file_exists(arena.build_save_path) else PackedByteArray()
	for unused: int in range(20):
		arena.retained_actors.advance(1.0 / 60.0)
		arena.retained_actors.sync(arena)
		arena.dimensional_props.update_player(arena.player_pos)
	check(snapshot(arena) == before, "Repeated actor/scenery presentation leaves model, combat, geometry, cues and RNG unchanged")
	var disk_after := FileAccess.get_file_as_bytes(arena.build_save_path) if FileAccess.file_exists(arena.build_save_path) else PackedByteArray()
	check(disk_after == disk_before, "Presentation makes no save writes")
	arena.hud.open_panel("pause")
	var pause_time: float = arena.retained_actors._visual_time
	arena._process(0.1)
	check(arena.retained_actors._visual_time == pause_time, "Blocking menus pause display time along with simulation")
	arena.hud.close_panel()
	var actor_count: int = arena.retained_actors.get_child_count()
	arena.retained_actors.clear()
	check(arena.retained_actors._hero == null and arena.retained_actors.get_child_count() == actor_count - 1, "Restart detaches hero without clearing independent town scenery")
	arena.retained_actors.sync(arena)
	check(is_instance_valid(arena.retained_actors._hero), "Town re-entry reconstructs hero once")
	var after_source := FileAccess.get_file_as_string("res://scripts/visuals/arena_visuals.gd").split("static func draw_after_actors(")[1]
	check(not after_source.contains("draw_player(arena"), "Foreground no longer paints a duplicate always-front player")
	arena.queue_free(); await process_frame; await process_frame
	print("Actual Main actor depth: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
