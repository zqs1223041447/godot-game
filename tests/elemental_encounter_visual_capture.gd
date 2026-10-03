extends SceneTree
var arena:Node
var output:=OS.get_environment("V025_CAPTURE_OUT")
var records:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	if DisplayServer.get_name()=="headless" or output.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/workspace/scratch/a51485f153de/v025-visual-user/"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720);root.title="v0.25 elemental encounter native validation"
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena)
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	await frames(4)
	for size:Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size=size
		for id:String in ["frost_guard","storm_skitter"]:
			for effects:int in [0,2]:
				arena.enemies.clear();arena.telegraphs.reset();arena.telegraph_trace.clear();arena.projectiles.clear();arena.visual_cues.reset();arena.floating_text.clear();arena.particles.clear();arena.rings.clear()
				arena.visual_settings.effects_level=effects;arena.player_pos=arena.ARENA.get_center();arena.elapsed=12.0
				arena.demo_mode=true;arena.wave=4 if id=="frost_guard" else 5
				var enemy:Dictionary=arena._spawn_monster(id,arena.player_pos+Vector2(125,-30),"demo","normal",[],false)
				enemy.spawn=0.0;enemy.attack_timer=0.0
				arena._start_enemy_telegraphs()
				var profile:Dictionary=arena.Monsters.telegraph_policy(enemy).profile
				arena._advance_enemy_telegraphs(profile.windup_seconds*0.65)
				await capture("%s-fx%d-%d"%[id,effects,size.x],false)
				if effects==0:
					arena.player_pos+=Vector2(240,0)
					arena._advance_enemy_telegraphs(profile.windup_seconds*0.35)
					if arena.telegraph_trace.size()!=1 or arena.telegraph_trace[0].inside:push_error("Dodge capture did not avoid real attack");quit(1);return
					await capture("%s-dodged-%d"%[id,size.x],true)
	FileAccess.open(output+"/records.json",FileAccess.WRITE).store_string(JSON.stringify(records,"\t"))
	print("ELEMENTAL_VISUAL_COMPLETE ",records.size()," actual rendered frames")
	arena.queue_free();await process_frame;quit()
func frames(count:int)->void:
	for i:int in count:arena.hud._process(1.0/60.0);arena.queue_redraw();await process_frame
func capture(name:String,dodged:bool)->void:
	await frames(3);await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.save_png(output+"/"+name+".png")
	records.append({"name":name,"size":root.size,"schema":arena.state.snapshot().version,"visual_states":arena.telegraph_visual_states(),"actual_events":arena.telegraph_trace.duplicate(true),"dodged":dodged})
