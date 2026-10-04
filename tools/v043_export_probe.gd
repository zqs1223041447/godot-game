extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:=OS.get_environment("V043_PACK_QA");var expected_font:=OS.get_environment("V043_PACK_FONT_SHA256")
	if output.is_empty() or expected_font.length()!=64 or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	var model:RefCounted=arena.state;var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(font.data);var font_hash:=h.finish().hex_encode()
	var version:=str(ProjectSettings.get_setting("application/config/version"));var directory:=str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	var ok:bool=version=="0.43.0" and directory=="godot-game-preview-v021" and model.snapshot().version==27 and model.bag_layout()=={"pages":2,"columns":12,"rows":10} and font_hash==expected_font
	for index:int in "东西北据点木牌营地成员靠近推进".length():ok=ok and font.has_char("东西北据点木牌营地成员靠近推进".unicode_at(index))
	ok=ok and arena.save_build()
	var candidate:Dictionary=model.snapshot();candidate.journey.best_tiers.broken_ruins=1;ok=ok and model._set_bag_currency_balance(candidate,4).ok;candidate.revision+=1;ok=ok and model._commit(candidate,arena.NORMAL_BUILD_PATH).ok
	ok=ok and arena.craft_normal_map("broken_ruins",2,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok and arena.enemies.is_empty()
	var layout:Dictionary=arena.world_geometry().landmarks
	for index:int in [2,0,1]:arena.player_pos=layout.camps[index].trigger_center;arena._update_map_spawning(0.0)
	ok=ok and arena.enemies.size()==36 and model.crafting_balance()==0
	var full_group_states:Dictionary=arena.world_context()
	for enemy:Dictionary in arena.enemies:ok=ok and enemy.spawn==0.6 and arena._geometry.is_clear(enemy.pos,enemy.radius)
	arena._begin_progress_transaction()
	for enemy:Dictionary in arena.enemies.duplicate():enemy.spawn=0.0;arena._damage_enemy(enemy,float(enemy.health)+float(enemy.shield)+1000.0,Color.WHITE)
	arena._flush_monster_spawns();ok=ok and arena.world_context().boss_phase=="ready"
	arena.player_pos=layout.boss.trigger_center;arena._update_map_spawning(0.0);ok=ok and arena._map_run.boss_id>0
	var loops:=0
	while arena.world_context().mode=="map" and loops<20:
		loops+=1
		for enemy:Dictionary in arena.enemies.duplicate():
			if enemy.health>0.0:enemy.spawn=0.0;arena._damage_enemy(enemy,float(enemy.health)+float(enemy.shield)+1000.0,Color.WHITE)
		arena._flush_monster_spawns();arena._check_map_complete()
	arena._end_progress_transaction()
	ok=ok and loops<20 and arena.world_context().mode=="map_complete" and model.normal_journey().normal_root_kills==37 and arena.world_context().pending_map_reward.shards==8
	ok=ok and arena.return_to_town(arena.world_context().revision).ok
	var claim:Dictionary=arena.claim_normal_rewards(arena.world_context().revision);ok=ok and claim.ok and claim.claimed_shards==8 and model.crafting_balance()==8
	var result:Dictionary={"ok":ok,"version":version,"schema":model.snapshot().version,"save_directory":directory,"user_dir":OS.get_user_data_dir(),"bag_layout":model.bag_layout(),"font_sha256":font_hash,"font_characters":font.get_supported_chars().length(),"full_group_states":full_group_states,"normal_root_kills":model.normal_journey().normal_root_kills,"claim":claim,"currency":model.crafting_balance(),"order":[2,0,1],"max_simultaneous_roots":36}
	var file:=FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("Packed v43 camp probe: ","PASS" if ok else "FAIL");arena.queue_free();await process_frame;quit(0 if ok else 1)
