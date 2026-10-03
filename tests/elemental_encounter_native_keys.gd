extends SceneTree
var arena:Node
var output:=OS.get_environment("V025_KEYS_OUT")
func _initialize()->void:call_deferred("run")
func run()->void:
	if DisplayServer.get_name()=="headless" or output.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/workspace/scratch/a51485f153de/v025-key-user/"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1280,720)
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);arena.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	var records:Array=[]
	for id:String in ["frost_guard","storm_skitter"]:
		while Input.is_physical_key_pressed(KEY_D):await process_frame
		arena.enemies.clear();arena.telegraphs.reset();arena.telegraph_trace.clear();arena.incoming_damage_trace.clear();arena.visual_cues.reset();arena.rings.clear();arena.floating_text.clear()
		arena.player_pos=arena.ARENA.get_center();arena.spawn_timer=9999.0;arena.demo_mode=true;arena.invulnerable=0.0;arena.elapsed=95.0 if id=="frost_guard" else 125.0
		arena.wave=4 if id=="frost_guard" else 5;arena.visual_settings.effects_level=0
		var enemy:Dictionary=arena._spawn_monster(id,arena.player_pos+Vector2(100,0),"demo","normal",[],false);enemy.spawn=0.0;enemy.attack_timer=0.0
		var before:Vector2=arena.player_pos
		root.title="Native elemental dodge - hold D - "+id
		print("ELEMENTAL_NATIVE_READY "+id)
		var deadline:int=Time.get_ticks_msec()+180000
		while not Input.is_physical_key_pressed(KEY_D):
			if Time.get_ticks_msec()>deadline:push_error("Physical input not received");quit(78);return
			arena.queue_redraw();await process_frame
		arena.set_process(true)
		while arena.telegraph_trace.is_empty():
			if Time.get_ticks_msec()>deadline:push_error("Real attack did not resolve");quit(1);return
			await process_frame
		arena.set_process(false)
		var event:Dictionary=arena.telegraph_trace.back()
		var ok:bool=not event.inside and not event.applied and arena.incoming_damage_trace.is_empty() and arena.player_pos.x>before.x
		records.append({"template":id,"key":"D","player_before":before,"player_after":arena.player_pos,"real_event":event,"ok":ok,"input":"physical desktop key; main _process movement and warning clock"})
		arena.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/"+id+"-physical-dodge.png")
		FileAccess.open(output+"/records.json",FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
		if not ok:push_error("Actual physical movement failed to avoid warning");quit(1);return
	print("ELEMENTAL_NATIVE_KEYS_COMPLETE two physical D holds avoided actual attacks")
	arena.queue_free();await process_frame;quit()
