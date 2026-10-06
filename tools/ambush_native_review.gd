extends SceneTree
## Isolated actual-main setup for one visual review. No normal-profile gifts.
var arena: Node
func _initialize() -> void: call_deferred("run")
func accepted(result: Dictionary, label: String) -> bool:
	if result.get("ok", false): return true
	push_error(label + ": " + str(result)); quit(1); return false
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/v066-native"):
		quit(78); return
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	arena.set_process(false); arena.hud.set_process(false)
	if not accepted(arena.enter_town_test(arena.world_context().revision), "Actual isolated test town"): return
	for uid: String in arena.state.pending_items():
		var destination: Dictionary = arena.state.first_bag_position(uid)
		if destination.is_empty(): push_error("Recovery bag space missing"); quit(1); return
		if not accepted(arena.state.move_item(uid, destination, arena.state.revision(), arena.build_save_path), "Recovery ownership"): return
	var groups: Array[String] = []
	for index: int in range(3): groups.append(str(arena.state.snapshot().skill_groups[index].id))
	for kind: String in ["skill_support", "skill_main"]:
		for uid: String in arena.state.snapshot().locations:
			var location: Dictionary = arena.state.location(uid)
			if location.kind != kind or str(location.get("group_id", "")) not in groups: continue
			var destination: Dictionary = arena.state.first_bag_position(uid)
			if destination.is_empty(): push_error("Old skill bag space missing"); quit(1); return
			if not accepted(arena.state.move_item(uid, destination, arena.state.revision(), arena.build_save_path), "Keep previous gems in bag"): return
	for index: int in range(3):
		var skill: String = "meteor" if index == 1 else "nova"
		var main_item: Dictionary = arena.town_buy("skill:" + skill, arena.state.revision())
		if not accepted(main_item, "Real free test active supply"): return
		var support: Dictionary = arena.town_buy("support:ambush", arena.state.revision())
		if not accepted(support, "Real free test Ambush supply"): return
		if not accepted(arena.state.move_item(main_item.uid, {"kind":"skill_main", "group_id":groups[index]}, arena.state.revision(), arena.build_save_path), "Real active slot"): return
		if not accepted(arena.state.move_item(support.uid, {"kind":"skill_support", "group_id":groups[index], "index":0}, arena.state.revision(), arena.build_save_path), "Real support slot"): return
	if not accepted(arena.craft_map("old_garden", [], [], arena.map_draft().revision), "Real test map draft"): return
	if not accepted(arena.start_map(arena.map_draft().revision), "Real test map entry"): return
	arena.set_process(false); arena.auto_fire = false; arena.hud._process(0.0); arena.hud.close_panel()
	for index: int in range(3):
		arena.player_pos = arena.ARENA.get_center() + Vector2((index - 1) * 160.0, 0.0)
		if index == 2: arena.elapsed = 0.2
		if not arena.cast_group(groups[index]): push_error("Real trap placement failed"); quit(1); return
	arena.elapsed = 0.35; arena._update_traps(); arena.player_pos = arena.ARENA.get_center() + Vector2(300, 90); arena.hud._process(0.0)
	arena.queue_redraw()
	if not arena.save_build(): push_error("Isolated fixture save failed"); quit(1); return
	print("Ambush native review: real test supplies, three real cast payments; simulation paused; two armed and one arming; no natural combat/FPS claim")
	print("Groups: ", groups, " statuses: ", arena.trap_statuses())
