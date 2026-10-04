extends SceneTree
const Geometry=preload("res://scripts/world/map_geometry.gd")
const View=preload("res://scripts/visuals/world_view.gd")
const Orders=[[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]]
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func observe()->Dictionary:
	return {"runtime":arena.EncounterAdmission._snapshot(arena.monster_runtime),"admitted":arena._map_run.admitted.duplicate(true),"camp":arena._map_camps.checkpoint(),"enemies":arena.enemies.duplicate(true),"rng":arena.rng.state,"rings":arena.rings.duplicate(true),"save":arena.state.snapshot()}
func kill_all()->void:
	arena._begin_progress_transaction()
	for enemy:Dictionary in arena.enemies.duplicate():
		if float(enemy.health)>0.0:enemy.spawn=0.0;arena._damage_enemy(enemy,float(enemy.health)+float(enemy.shield)+1000.0,Color.WHITE)
	arena._flush_monster_spawns();arena._end_progress_transaction()
func complete()->void:
	kill_all()
	check(arena.world_context().boss_phase=="ready" and arena._map_run.boss_id==0,"All ordinary roots unlocks gate, no timer-spawned boss")
	var remaining_descendants:int=arena.enemies.size()
	arena.player_pos=arena.world_geometry().landmarks.boss.trigger_center;arena._update_map_spawning(0.0)
	check(arena.world_context().boss_phase=="active" and arena.enemies.size()==remaining_descendants+1,"Explicit safe boss gate admits one real boss")
	var boss_id:int=arena._map_run.boss_id;var before:=observe();arena._update_map_spawning(5.0)
	check(arena._map_run.boss_id==boss_id and arena.enemies.size()==remaining_descendants+1 and observe()==before,"Standing in gate never duplicates boss")
	kill_all();check(arena.enemies.size()==4 and arena.world_context().mode=="map","Boss descendants retain queue and prevent early completion")
	kill_all();arena._check_map_complete()
	check(arena.world_context().mode=="map_complete" and arena.world_context().boss_phase=="defeated","Defeated boss plus all descendants closes once")
	before=observe();arena._check_map_complete();check(observe()==before,"Repeated completion cannot mint another receipt")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	# Additive traversal reporting must retain the old movement result exactly.
	var movement:Array=bytes_to_var(FileAccess.get_file_as_bytes("res://docs/qa/v043/v042-movement.bin"))
	for row:Dictionary in movement:
		var geometry:=Geometry.new();geometry.configure(row.map_id,View.WORLD_ARENA);var segments:Array=[]
		check(var_to_bytes(geometry.move(row.start,row.desired,row.radius))==var_to_bytes(row.result),"Old no-trace movement is exact")
		check(var_to_bytes(geometry.move(row.start,row.desired,row.radius,segments))==var_to_bytes(row.result) and not segments.is_empty(),"Tracing does not change movement result")
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	check(arena.save_build() and arena.world_context().normal_town,"Actual normal town remains safe default")
	for map_id:String in ["old_garden","broken_ruins"]:
		var count:int=8 if map_id=="old_garden" else 12
		for order_index:int in range(Orders.size()):
			var order:Array=Orders[order_index]
			check(arena.craft_normal_map(map_id,1,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Actual formal map starts "+map_id+str(order))
			var geometry:Dictionary=arena.world_geometry();check(geometry.landmarks.camps.size()==3 and arena.enemies.is_empty() and arena.player_pos==geometry.landmarks.entry,"No initial trickle; entry and all3landmarks same-source")
			var frozen:Dictionary=arena._map_camps.checkpoint();var roster:Array=[]
			for camp:Dictionary in frozen.camps:roster.append(camp.entries)
			for position:int in range(3):
				var camp:Dictionary=geometry.landmarks.camps[order[position]]
				var rng_before:int=arena.rng.state;arena.player_pos=camp.trigger_center
				arena._update_map_spawning(0.0)
				check(arena.enemies.size()==count*(position+1),"Full groups coexist before any kill, no sequential lock")
				check(arena.rng.state==rng_before,"Activation does not draw existing loot/visual RNG")
				var alive:=0
				for enemy:Dictionary in arena.enemies:
					if enemy.health>0.0:alive+=1
					check(arena._geometry.is_clear(enemy.pos,enemy.radius) and enemy.spawn==0.6,"Actual position legal with full spawn cue")
				check(alive==count*(position+1),"Simultaneous density is preserved")
				var before:=observe();arena._update_map_spawning(5.0);check(observe()==before,"Repeated position/time never duplicates group")
			var after_roster:Array=[]
			for camp:Dictionary in arena._map_camps.checkpoint().camps:after_roster.append(camp.entries)
			check(var_to_bytes(after_roster)==var_to_bytes(roster),"Chosen activation order cannot reroll frozen roster")
			check(arena._map_run.admitted.size()==3*count and arena.world_context().boss_phase=="sealed","All original roots admitted, boss still waits for deaths")
			if order_index==5:
				var before_kills:int=arena.state.normal_journey().normal_root_kills
				complete()
				check(arena.state.normal_journey().normal_root_kills==before_kills+3*count+1,"Only original roots and boss count, four descendants do not")
				check(arena.world_context().pending_map_reward.shards==4,"Same tierI completion reward")
				check(arena.return_to_town(arena.world_context().revision).ok and arena.claim_normal_rewards(arena.world_context().revision).ok,"Existing run receipt and real reward route closes")
			else:check(arena.return_to_town(arena.world_context().revision).ok,"Abandoning multiple active camps returns safely")
			check(arena.world_context().camp_states.is_empty() and not arena.world_geometry().has("landmarks") and arena.enemies.is_empty(),"Town clears camp/runtime geometry without changing other systems")
	# Whole-group failure rollback, independent from trigger-request presentation.
	check(arena.craft_normal_map("broken_ruins",1,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Boundary case enters real map")
	var landmark:Dictionary=arena.world_geometry().landmarks.camps[0]
	arena.player_pos=landmark.center;var before:=observe()
	check(not arena._activate_camp(landmark.id).ok and observe()==before,"Too-close rejects every ID/RNG/root/effect atomically")
	arena.player_pos=landmark.trigger_center
	var blocker:Dictionary=arena._spawn_monster("crawler",arena.ARENA.position+Vector2(50,50),"ordinary","normal",[],false)
	for i:int in range(88):arena.enemies.append(blocker.duplicate(true))
	before=observe();check(not arena._activate_camp(landmark.id).ok and observe()==before,"Insufficient12slots cannot trickle partial group")
	arena.enemies.clear();arena.monster_runtime.collect_lineages(arena.enemies)
	before=observe();var saved_template:Dictionary=arena.monster_runtime.templates.crawler;arena.monster_runtime.templates.erase("crawler")
	var malformed_before:=observe();check(not arena._activate_camp(landmark.id).ok and observe()==malformed_before,"Factory rejection has no partial admission or markers")
	arena.monster_runtime.templates["crawler"]=saved_template
	check(arena._activate_camp(landmark.id).ok and arena.enemies.size()==12,"Same full camp retries after capacity/source recovery")
	before=observe();check(not arena._activate_camp(landmark.id).ok and observe()==before,"Direct duplicate also rolls back all bookkeeping")
	check(arena.return_to_town(arena.world_context().revision).ok,"Boundary run returns")
	# Real dash crosses an entrance disk using accepted movement, not a signal.
	check(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Dash case enters")
	landmark=arena.world_geometry().landmarks.camps[0];arena.player_pos=landmark.trigger_center+Vector2(-90,0);arena.player_facing=Vector2.RIGHT;arena.mana=100.0
	var dash:Dictionary=arena.state.get_skill_cast("dash");check(arena._execute_compiled(dash),"Actual dash accepted")
	check(arena.player_pos.distance_to(landmark.trigger_center)>64.0,"Dash ends outside marker so endpoint alone would miss it")
	arena._update_map_spawning(0.0)
	check(arena.enemies.size()==8,"Actual swept dash activates full group once")
	arena.alive=false;var untouched:=observe();arena.player_pos=arena.world_geometry().landmarks.camps[1].trigger_center;arena._update_map_spawning(0.0)
	check(arena._map_run.admitted.size()==8 and arena._map_camps.checkpoint()==untouched.camp,"Dead player cannot activate another camp")
	check(arena.return_to_town(arena.world_context().revision).ok,"Death return retains normal lifecycle")
	# Mode-specific descriptions no longer contradict real completion economics.
	for special:Dictionary in arena.map_options().special_modifiers:check(special.completion_reward_bonus==2 and special.description.contains("+2"),"Formal special explains existing2completion bonus")
	var normal_disk:=FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	check(arena.enter_town_test(arena.world_context().revision).ok,"Test profile still explicit")
	for special:Dictionary in arena.map_options().special_modifiers:check(special.completion_reward_bonus==0,"Test special has no formal extra reward")
	check(arena.craft_map("broken_ruins",[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok and arena.wave==5,"Test map old budget, new same camp flow")
	landmark=arena.world_geometry().landmarks.camps[2];arena.player_pos=landmark.trigger_center;arena._update_map_spawning(0.0)
	check(arena.enemies.size()==12 and arena.world_context().test_mode,"Test full camp actually admits")
	check(arena.return_to_town(arena.world_context().revision).ok and arena.leave_town_test(arena.world_context().revision).ok and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==normal_disk,"Test camp actions cannot alter normal file")
	check(arena.leave_normal_town(arena.world_context().revision).ok and arena.enemies.size()==3 and arena.world_context().mode=="normal","Old practice initial3andtimer flow retained")
	print("Map camp gameplay: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
