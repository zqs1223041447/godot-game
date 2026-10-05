extends SceneTree
## Short same-source stress samples; instrumentation lives only in this tool.
## The protected player fixture leaves monster AI/attack scheduling enabled.
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const STEP:=1.0/60.0
const ProductionMain=preload("res://tests/fixtures/v050/main_clock_fixed_baseline.gd")
const ProductionModel=preload("res://scripts/canonical_game_state.gd")
const ProductionBurn=preload("res://tests/fixtures/v050/burn_runtime_before_allocation.gd")
class Meter extends RefCounted:
	var enabled:=true
	var stack:Array=[]
	var totals:Dictionary={}
	var counts:Dictionary={}
	var extras:Dictionary={}
	func begin(key:String)->void:
		if enabled:stack.append({"key":key,"start":Time.get_ticks_usec(),"child":0})
	func end()->void:
		if not enabled:return
		var row:Dictionary=stack.pop_back();var span:int=Time.get_ticks_usec()-int(row.start)
		var key:String=row.key
		totals[key+"_inclusive_us"]=int(totals.get(key+"_inclusive_us",0))+span
		totals[key+"_self_us"]=int(totals.get(key+"_self_us",0))+maxi(0,span-int(row.child))
		counts[key]=int(counts.get(key,0))+1
		if not stack.is_empty():stack.back().child+=span
	func extra(key:String,value:int=1)->void:
		if enabled:extras[key]=int(extras.get(key,0))+value
	func clear()->void:totals.clear();counts.clear();extras.clear();assert(stack.is_empty())
class TimedBurn extends "res://tests/fixtures/v050/burn_runtime_before_allocation.gd":
	var meter:Meter
	func statuses()->Array[Dictionary]:
		meter.begin("burn_status_copies");var value:=super.statuses();meter.extra("copied_status_rows",value.size());meter.end();return value
	func advance_target(kind:Variant,id:Variant,to_time:Variant)->Dictionary:
		meter.begin("burn_advance_target");var value:=super.advance_target(kind,id,to_time)
		meter.extra("advance_empty_segments" if value.get("segments",[]).is_empty() else "advance_nonempty_segments");meter.end();return value
class TimedState extends "res://scripts/canonical_game_state.gd":
	var meter:Meter
	func add_normal_root_xp(amount:int)->bool:
		if meter==null:return super.add_normal_root_xp(amount)
		meter.begin("normal_xp_and_changed");var value:=super.add_normal_root_xp(amount);meter.end();return value
	func award_equipment(rng:RandomNumberGenerator,level:int,rarity:String="",pool:String="current")->String:
		meter.begin("equipment_award");var value:=super.award_equipment(rng,level,rarity,pool);meter.end();return value
	func save_build(path:String="user://build_save.json")->Error:
		if meter==null:return super.save_build(path)
		meter.begin("save_validation_serialize_write");var value:=super.save_build(path);meter.end();return value
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:
		if meter==null:return super._write_bytes(path,bytes)
		meter.begin("atomic_write_close");var value:=super._write_bytes(path,bytes);meter.end();return value
class TimedArena extends "res://tests/fixtures/v050/main_clock_fixed_baseline.gd":
	var meter:Meter
	var capture_inversion:=false
	var captured:=false
	var capture_path:=""
	var current_frame:=0
	var frame_checkpoint:Dictionary={}
	var previous_event:Dictionary={}
	func _update_enemies(delta:float)->void:
		meter.begin("enemy_ai");super._update_enemies(delta);meter.end()
	func _update_projectiles(delta:float)->void:
		meter.begin("projectiles");super._update_projectiles(delta);meter.end()
	func _update_effects(delta:float)->void:
		meter.begin("effects");super._update_effects(delta);meter.end()
	func _update_pickups(delta:float)->void:
		meter.begin("pickups");super._update_pickups(delta);meter.end()
	func _update_spawning(delta:float)->void:
		meter.begin("spawn_cleanup");super._update_spawning(delta);meter.end()
	func _ember_event_time(at:float,event:Dictionary)->float:
		if capture_inversion and not captured:
			var latest:float=at
			for raw:Dictionary in burn_runtime._states.values():
				if raw.target_kind=="monster":latest=maxf(latest,float(raw.last_time))
			if latest>at and not (_burn_step_active and event.has("time") and latest<=elapsed and is_equal_approx(float(event.time),latest-_burn_step_start)):
				captured=true
				var evidence:Dictionary={"frame":current_frame,"at":at,"latest":latest,"step_start":_burn_step_start,"elapsed":elapsed,"event":event.duplicate(true),"previous_event":previous_event.duplicate(true),"states":burn_runtime._states.duplicate(true),"enemies":enemies.duplicate(true),"checkpoint":frame_checkpoint.duplicate(true),"recent_events":combat_trace.duplicate(true)}
				var f:=FileAccess.open(capture_path+".bin",FileAccess.WRITE);f.store_buffer(var_to_bytes(evidence));f.close()
				var brief:Dictionary={"frame":current_frame,"at":at,"latest":latest,"step_start":_burn_step_start,"elapsed":elapsed,"event_offset":event.time,"latest_offset":latest-_burn_step_start,"reverse_seconds":latest-at,"previous_offset":previous_event.get("time",-1.0),"event_type":event.type,"event_sequence":event.sequence,"relative_tie":is_equal_approx(float(event.time),latest-_burn_step_start),"previous_pair_tie":is_equal_approx(float(event.time),float(previous_event.get("time",-1.0)))}
				f=FileAccess.open(capture_path+".json",FileAccess.WRITE);f.store_string(JSON.stringify(brief,"\t",true,true));f.close();print("FIRST_CLOCK_INVERSION ",JSON.stringify(brief));get_tree().quit(2)
			previous_event=event.duplicate(true)
		meter.begin("ember_event_clock");var value:=super._ember_event_time(at,event);meter.end();return value
	func _advance_proliferating_burns(to_time:float)->void:
		meter.begin("ember_advance_guard" if _ember_advancing else "ember_advance_all");super._advance_proliferating_burns(to_time);meter.end()
	func _settle_burn_segments(segments:Array,targets:Dictionary={},death_states:Dictionary={},exact_deaths:Dictionary={})->void:
		meter.begin("burn_settlement");meter.extra("settled_burn_segments",segments.size());super._settle_burn_segments(segments,targets,death_states,exact_deaths);meter.end()
	func _flush_ember_deaths()->void:
		meter.begin("ember_transfer");meter.extra("queued_ember_deaths",_ember_deaths.size());super._flush_ember_deaths();meter.end()
	func _finish_enemy_death(enemy:Dictionary,legacy_particles:bool=true,at:float=-1.0,source_burn:Dictionary={})->void:
		meter.begin("death_and_rewards");super._finish_enemy_death(enemy,legacy_particles,at,source_burn);meter.end()
	func _flush_progress(force_save:bool=false)->bool:
		meter.begin("progress_flush");var value:=super._flush_progress(force_save);meter.end();return value
	func _on_build_changed()->void:
		meter.begin("build_changed");super._on_build_changed();meter.end()
var instrumented:=OS.get_environment("DENSITY_INSTRUMENTED")!="0"
var out:=OS.get_environment("DENSITY_PROFILE_OUT")
var rows:Array=[]
func _initialize()->void:call_deferred("run")
func summary(values:Array)->Dictionary:
	if values.is_empty():return {}
	var copy:=values.duplicate();copy.sort();var total:=0.0;var n16:=0;var n33:=0
	for value:float in copy:total+=value;n16+=int(value>16667.0);n33+=int(value>33333.0)
	return {"n":copy.size(),"mean_us":total/copy.size(),"p50_us":copy[copy.size()/2],"p95_us":copy[mini(copy.size()-1,int(copy.size()*0.95))],"max_us":copy.back(),"over_16_7_ms":n16,"over_33_3_ms":n33}
func sha(bytes:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func write()->void:
	var f:=FileAccess.open(out,FileAccess.WRITE);f.store_string(JSON.stringify({"base_commit":"a9a402d3d1f590e20c8917d177f1869ad9274751","instrumented":instrumented,"production_without_wrappers":not instrumented and OS.get_environment("DENSITY_CAPTURE_INVERSION")!="1","scope":"Headless script CPU; nested inclusive phases are not additive. Stress volleys are controlled carriers, not a claim one player naturally emits180 every tick. Catalog monsters retain AI and attack scheduling; player protected for the benchmark. No rendering/WindowsFPS measurement.","engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"rows":rows},"\t",true,true));f.close()
func run()->void:
	create_timer(60.0).timeout.connect(func():push_error("Density diagnostic did not complete within60seconds");quit(1))
	if out.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v050-"):quit(78);return
	for mode:String in ["no_burn","ignite","ember_proliferation","ember_deaths"]:
		if not OS.get_environment("DENSITY_MODE").is_empty() and mode!=OS.get_environment("DENSITY_MODE"):continue
		var m:=Meter.new();m.enabled=false
		var wrapped:bool=instrumented or OS.get_environment("DENSITY_CAPTURE_INVERSION")=="1"
		var arena:Node=TimedArena.new() if wrapped else ProductionMain.new()
		if wrapped:arena.meter=m
		var state:RefCounted=TimedState.new() if wrapped else ProductionModel.new()
		if wrapped:state.meter=m
		arena.state=state;arena.build_save_path="user://build_save.json"
		assert(state.save_build(arena.build_save_path)==OK)
		if wrapped:
			arena.capture_inversion=OS.get_environment("DENSITY_CAPTURE_INVERSION")=="1";arena.capture_path=out.trim_suffix(".json")+"-first-inversion"
		var burns:RefCounted=TimedBurn.new() if wrapped else ProductionBurn.new()
		if wrapped:burns.meter=m
		arena.burn_runtime=burns
		root.add_child(arena);arena.set_process(false);arena.hud.set_process(false)
		arena._world_mode="normal";arena.restart_run();arena.auto_fire=false;arena.spawn_timer=100000.0
		arena.rng.seed=500050;arena.critical_runtime.reset(500051)
		arena.enemies.clear();arena.monster_runtime.reset();arena.telegraphs.reset();arena.projectiles.clear()
		arena.invulnerable=1000.0;arena.player_pos=arena.ARENA.get_center()+Vector2(0,210)
		while arena.hud.is_blocking():arena.hud.close_panel()
		for index:int in range(100):
			var point:Vector2=arena.ARENA.get_center()+Vector2((index%10-4.5)*36,(index/10-4.5)*36)
			var template:String="brute" if mode=="ember_deaths" and index<20 else ["crawler","brute","skitter","frost_guard","storm_skitter","ember_guard"][index%6]
			var enemy:Dictionary=arena.monster_runtime.create_root(template,6,point,"ordinary","",[],true)
			assert(not enemy.is_empty());arena._apply_source_actor_profile(enemy);enemy.spawn=0.0;arena.enemies.append(enemy)
		var supports:Array=[] if mode=="no_burn" else ["ignite" if mode=="ignite" else "ember_proliferation"]
		var cast:Dictionary=Compiler.compile_group("tornado",Combat.snapshot({"damage":0.075 if mode=="no_burn" else 0.1,"crit_base_chance":0.0},[]),supports)
		assert(cast.ok)
		if mode=="ember_deaths":
			var meteor:=Compiler.compile_group("meteor",Combat.snapshot({"damage":50.0,"crit_base_chance":0.0},[]),["ember_proliferation"])
			arena._begin_progress_transaction()
			for index:int in range(20):arena._apply_damage_packet(arena.enemies[index],meteor.packets.direct,meteor.snapshot,Color.ORANGE)
			arena._end_progress_transaction()
		var timings:Array=[];var phases:Dictionary={};var counts:Dictionary={};var extras:Dictionary={};var samples:Array=[]
		var initial:Dictionary=arena.state.snapshot();var start_kills:int=arena.kills
		var frames:int=150 if mode=="ember_deaths" else 24
		for frame:int in range(frames):
			if mode!="ember_deaths" or frame==0:
				arena.projectiles.clear()
				assert(arena.enemies.size()==100,"The controlled volley begins at full real100actor density")
				for index:int in range(180):
					var target:Dictionary=arena.enemies[index%100]
					var spec:Dictionary=cast.snapshot.tornado_recipe.parent.duplicate(true)
					var origin:Vector2=Vector2(target.pos)-Vector2(float(target.radius)+float(spec.radius)+3.0,0)
					arena.projectiles.append(arena.projectile_runtime.make_projectile(origin,Vector2.RIGHT,spec,cast.packets.parent,cast.snapshot,arena.projectile_runtime.new_cast(),Color.ORANGE))
			m.clear();m.enabled=instrumented
			if wrapped:arena.current_frame=frame
			if wrapped and arena.capture_inversion:arena.frame_checkpoint={"enemies":arena.enemies.duplicate(true),"projectiles":arena.projectiles.duplicate(true),"burns":burns._states.duplicate(true),"elapsed":arena.elapsed,"rng":arena.rng.state,"player_pos":arena.player_pos}
			var hits:int=int(arena.event_counts.get("hit",0));var kills:int=arena.kills
			var began:=Time.get_ticks_usec();arena.tick(STEP);var total:int=Time.get_ticks_usec()-began
			m.enabled=false;timings.append(total)
			for key:String in m.totals:
				if not phases.has(key):phases[key]=[]
				phases[key].append(m.totals[key])
			for key:String in m.counts:counts[key]=int(counts.get(key,0))+int(m.counts[key])
			for key:String in m.extras:extras[key]=int(extras.get(key,0))+int(m.extras[key])
			samples.append({"frame":frame,"cpu_us":total,"hits":int(arena.event_counts.get("hit",0))-hits,"kills":arena.kills-kills,"enemies":arena.enemies.size(),"projectiles":arena.projectiles.size(),"burns":burns._states.size(),"particles":arena.particles.size(),"pickups":arena.pickups.size(),"feedback":arena.feedback_runtime.entries().size()})
			assert(arena.alive)
			await process_frame
		var phase_summary:Dictionary={}
		for key:String in phases:phase_summary[key]=summary(phases[key])
		var observation:Dictionary={"enemies":arena.enemies.duplicate(true),"projectiles":arena.projectiles.duplicate(true),"burns":burns.statuses(),"rng":arena.rng.state,"critical":arena.critical_runtime.checkpoint(),"kills":arena.kills,"reward_kills":arena.reward_kills,"state":arena.state.snapshot(),"damage":arena.total_damage,"combat_trace":arena.combat_trace.duplicate(true),"damage_trace":arena.damage_trace.duplicate(true),"burn_trace":arena.burn_trace.duplicate(true)}
		var binary:PackedByteArray=var_to_bytes(observation);var f:=FileAccess.open(out.trim_suffix(".json")+"-"+mode+".bin",FileAccess.WRITE);f.store_buffer(binary);f.close()
		rows.append({"mode":mode,"frames":frames,"initial_enemies":100,"initial_inventory":initial.items.size(),"final_inventory":arena.state.snapshot().items.size(),"tick":summary(timings),"phases":phase_summary,"calls":counts,"extra_counts":extras,"samples":samples,"kills":arena.kills-start_kills,"reward_kills":arena.reward_kills,"observation_sha256":sha(binary),"observation_bytes":binary.size()})
		write();print("DENSITY_CASE ",mode," ",JSON.stringify(rows.back().tick)," calls=",JSON.stringify(counts))
		arena.queue_free();await process_frame
	print("LATEST_DENSITY_PROFILE_COMPLETE");quit(0)
