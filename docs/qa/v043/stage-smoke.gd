extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	assert(arena.world_context().normal_town)
	assert(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok)
	var entered:Dictionary=arena.start_map(arena.map_draft().revision);print("Map entry: ",entered)
	assert(entered.ok and arena.enemies.is_empty() and arena.world_geometry().landmarks.camps.size()==3)
	arena.player_pos=arena.world_geometry().landmarks.camps[1].trigger_center
	arena._update_map_spawning(0.0)
	assert(arena.enemies.size()==8 and arena.world_context().camp_states[1].state=="active")
	print("Camp stage smoke PASS: one real full8group active, no initial trickle")
	arena.queue_free();await process_frame;quit()
