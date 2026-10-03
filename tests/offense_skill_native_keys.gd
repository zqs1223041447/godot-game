extends SceneTree
var arena:Node
var output:=OS.get_environment("V024_KEYS_OUT")
func _initialize()->void:call_deferred("run")
func run()->void:
	if DisplayServer.get_name()=="headless" or output.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/workspace/scratch/a51485f153de/v024-key-user/"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1280,720)
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);arena.set_process(false);arena.auto_fire=false
	await process_frame
	arena._begin_progress_transaction()
	for i:int in 2:
		var gem:String=arena.state.award_gem("skill:"+["cleave","shade_bolt"][i])
		var group:="group_%06d"%(9+i)
		if gem.is_empty() or not arena.state.move_item(gem,{"kind":"skill_main","group_id":group},arena.state.revision(),"user://build_save.json").ok or not arena.state.bind_group(group,KEY_9 if i==0 else KEY_0,arena.state.revision(),"user://build_save.json").ok:quit(1);return
	arena._end_progress_transaction()
	while arena.hud.is_blocking():arena.hud.close_panel()
	var records:Array=[]
	for stage:int in 2:
		arena.enemies.clear();arena.projectiles.clear();arena.damage_trace.clear();arena.visual_cues.reset();arena.floating_text.clear()
		var enemy:Dictionary=arena.monster_runtime.create_root("brute",1,arena.player_pos+Vector2(65 if stage==0 else 380,0),"ordinary","",[],false)
		arena._apply_source_actor_profile(enemy);enemy.spawn=0.0;arena.enemies.append(enemy)
		var skill:String=["cleave","shade_bolt"][stage];var group:="group_%06d"%(9+stage)
		root.title="Native skill key test - press "+("9" if stage==0 else "0")
		var mana_before:float=arena.mana
		var deadline:int=Time.get_ticks_msec()+180000
		while arena.group_cooldown_remaining(group)<=0:
			if Time.get_ticks_msec()>deadline:push_error("Timed out waiting for physical keyboard input");quit(78);return
			arena.queue_redraw();await process_frame
		var spawned:int=arena.projectiles.size()
		if stage==1:arena._update_projectiles(0.7)
		arena.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/"+skill+"-physical-key.png")
		var cast:Dictionary=arena.state.get_group_cast(group)
		var ok:bool=is_equal_approx(mana_before-arena.mana,float(cast.mana)) and not arena.damage_trace.is_empty() and arena.damage_trace.back().skill_id==skill
		records.append({"skill":skill,"key":9 if stage==0 else 0,"group":group,"main_uid":cast.main_uid,"mana_before":mana_before,"mana_after":arena.mana,"recipe_mana":cast.mana,"spawned_projectiles":spawned,"actual_damage_trace":arena.damage_trace.duplicate(true),"ok":ok})
		FileAccess.open(output+"/records.json",FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
		if not ok:push_error("Physical key cast did not match recipe");quit(1);return
	print("OFFENSE_NATIVE_KEYS_COMPLETE physical 9 and 0 reached actual main casts")
	arena.queue_free();await process_frame;quit()
