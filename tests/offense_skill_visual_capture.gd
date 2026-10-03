extends SceneTree
var arena:Node
var output:=OS.get_environment("V024_CAPTURE_OUT")
var records:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	if DisplayServer.get_name()=="headless" or output.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/workspace/scratch/a51485f153de/v024-visual-user/"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720);root.title="v0.24 skill visual validation"
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena)
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	await frames(4)
	arena._begin_progress_transaction()
	for i:int in 2:
		var uid:String=arena.state.award_gem("skill:"+["cleave","shade_bolt"][i])
		if uid.is_empty():fail("Gem admission failed");return
		var group:="group_%06d"%(9+i)
		if not arena.state.move_item(uid,{"kind":"skill_main","group_id":group},arena.state.revision(),"user://build_save.json").ok:fail("Main insertion failed");return
		if not arena.state.bind_group(group,KEY_9 if i==0 else KEY_0,arena.state.revision(),"user://build_save.json").ok:fail("Binding failed");return
	arena._end_progress_transaction()
	if not arena.state.last_error.is_empty():fail(arena.state.last_error);return
	arena.hud._process(5.0)
	for size:Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size=size
		arena.hud.open_panel("skills");arena.hud.open_panel("inventory")
		await frames(5)
		var rows:ScrollContainer=arena.hud._skill_support_panel._rows
		rows.scroll_vertical=roundi(rows.get_v_scroll_bar().max_value)
		await capture("skills-bag-%d"%size.x)
		while arena.hud.is_blocking():arena.hud.close_panel()
		for skill:String in ["cleave","shade_bolt"]:
			for effects:int in [0,2]:
				arena.enemies.clear();arena.projectiles.clear();arena.visual_cues.reset();arena.floating_text.clear();arena.particles.clear();arena.rings.clear()
				arena.group_cooldowns.reset();arena.mana=arena._stats.max_mana;arena.visual_settings.effects_level=effects
				var offsets:Array=[Vector2(75,0),Vector2(65,40),Vector2(65,-40),Vector2(-85,0)] if skill=="cleave" else [Vector2(380,0)]
				for offset:Vector2 in offsets:
					var enemy:Dictionary=arena.monster_runtime.create_root("brute",1,arena.player_pos+offset,"ordinary","",[],false)
					arena._apply_source_actor_profile(enemy);enemy.spawn=0.0;arena.enemies.append(enemy)
				if not arena.cast_group("group_000009" if skill=="cleave" else "group_000010"):fail("Actual skill cast rejected");return
				if skill=="shade_bolt":arena._update_projectiles(0.25)
				arena.visual_cues.advance(0.10)
				await capture("%s-fx%d-%d"%[skill,effects,size.x])
	FileAccess.open(output+"/records.json",FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
	print("OFFENSE_VISUAL_COMPLETE ",records.size()," actual rendered frames")
	arena.queue_free();await process_frame;quit()
func frames(count:int)->void:
	for i:int in count:arena.hud._process(1.0/60.0);arena.queue_redraw();await process_frame
func capture(name:String)->void:
	await frames(3);await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.save_png(output+"/"+name+".png")
	records.append({"name":name,"size":root.size,"schema":arena.state.snapshot().version,"projectiles":arena.projectiles.size(),"mana":arena.mana,"damage_trace":arena.damage_trace.duplicate(true),"cue_count":arena.visual_cues.cues.size()})
func fail(reason:String)->void:push_error(reason);quit(1)
