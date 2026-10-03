extends SceneTree
var arena:Node
var output:=OS.get_environment("V026_KEYS_OUT")
func _initialize()->void:call_deferred("run")
func run()->void:
	if DisplayServer.get_name()=="headless" or output.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/workspace/scratch/a51485f153de/v026-shortcut-user/"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1280,720)
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);arena.set_process(false);arena.auto_fire=false;arena.enemies.clear();arena.projectiles.clear();arena.spawn_timer=9999;arena.demo_mode=true;arena.health=10;arena.mana=0
	while arena.hud.is_blocking():arena.hud.close_panel()
	var before:Dictionary=arena.state.snapshot();var saves:int=arena.state.successful_saves;var rows:Array=[]
	for index:int in 2:
		var uid:String=arena.state.flask_slots()[index].uid
		root.title="Native flask shortcut - press Alt+"+str(index+1)
		var deadline:int=Time.get_ticks_msec()+180000
		while int(arena.flask_runtime.snapshot().charges_by_uid[uid])==30:
			if Time.get_ticks_msec()>deadline:push_error("Physical Alt shortcut not received");quit(78);return
			arena.queue_redraw();await process_frame
		var ok:bool=arena.flask_runtime.snapshot().charges_by_uid[uid]==20 and arena.projectiles.is_empty() and arena.state.snapshot()==before and arena.state.successful_saves==saves
		rows.append({"shortcut":"Alt+"+str(index+1),"uid":uid,"charges":arena.flask_runtime.snapshot().charges_by_uid[uid],"projectiles":arena.projectiles.size(),"persistent_state_unchanged":arena.state.snapshot()==before,"ok":ok})
		if not ok:push_error("Shortcut had wrong resource/skill/persistence effect");quit(1);return
	for unused:int in 6:arena.hud._process(0.05);arena.queue_redraw();await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/both-physical-shortcuts.png")
	FileAccess.open(output+"/records.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	print("FLASK_NATIVE_SHORTCUTS_COMPLETE physicalAlt1/Alt2, no extra skill or persistent mutation")
	arena.queue_free();await process_frame;quit()
