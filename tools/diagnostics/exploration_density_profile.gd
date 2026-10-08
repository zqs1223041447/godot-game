extends "res://tools/diagnostics/latest_density_profile.gd"
const Existing=preload("res://tools/diagnostics/latest_density_profile.gd")
class Arena extends Existing.TimedArena:
	func _settle_projectile_events(events:Array[Dictionary],delta:float=0.0)->bool:
		meter.begin("event_settlement");var result:=super._settle_projectile_events(events,delta);meter.end();return result
	func _apply_damage_packet(enemy:Dictionary,packet:Dictionary,snapshot:Dictionary,color:Color,slow:float=0.0,provenance:Dictionary={})->void:
		meter.begin("damage_packet");super._apply_damage_packet(enemy,packet,snapshot,color,slow,provenance);meter.end()
	func _apply_enemy_settlement(enemy:Dictionary,settlement:Dictionary,color:Color,slow:float=0.0,critical:bool=false,at:float=-1.0)->void:
		meter.begin("enemy_settlement_feedback");super._apply_enemy_settlement(enemy,settlement,color,slow,critical,at);meter.end()
	func _start_enemy_telegraphs()->void:
		meter.begin("start_telegraphs");super._start_enemy_telegraphs();meter.end()
class Projectiles extends "res://scripts/combat/projectile_runtime.gd":
	var meter:Existing.Meter
	func advance(shots:Array[Dictionary],delta:float,targets:Array[Dictionary],owner_center:Vector2,max_projectiles:int,contact_gate:Callable=Callable(),terrain_query:Callable=Callable())->Array[Dictionary]:
		meter.begin("projectile_advance");var result:=super.advance(shots,delta,targets,owner_center,max_projectiles,contact_gate,terrain_query);meter.end();return result
	func _contacts(shot:Dictionary,start:Vector2,end:Vector2,targets:Array[Dictionary])->Array[Dictionary]:
		meter.begin("projectile_contacts");var result:=super._contacts(shot,start,end,targets);meter.end();return result
class Geometry extends "res://scripts/world/map_geometry.gd":
	var meter:Existing.Meter
	func direction(start:Vector2,goal:Vector2,radius:float,max_step:float=0.0)->Vector2:
		meter.begin("navigation_direction");var result:=super.direction(start,goal,radius,max_step);meter.end();return result
	func sweep(start:Vector2,end:Vector2,radius:float=0.0)->Dictionary:
		meter.begin("geometry_sweep");var result:=super.sweep(start,end,radius);meter.end();return result
	func _make_route_graph(radius:float)->Dictionary:
		meter.begin("route_graph_build");var result:=super._make_route_graph(radius);meter.end();return result
	func _update_goal(route:Dictionary,goal:Vector2,radius:float)->void:
		meter.begin("route_goal_update");super._update_goal(route,goal,radius);meter.end()
func observe(arena:Node)->Dictionary:
	return {"enemies":arena.enemies.duplicate(true),"projectiles":arena.projectiles.duplicate(true),"burns":arena.burn_runtime.statuses(),"rng":arena.rng.state,"critical":arena.critical_runtime.checkpoint(),"kills":arena.kills,"reward_kills":arena.reward_kills,"state":arena.state.snapshot(),"damage":arena.total_damage,"combat_trace":arena.combat_trace.duplicate(true),"damage_trace":arena.damage_trace.duplicate(true),"burn_trace":arena.burn_trace.duplicate(true),"particles":arena.particles.duplicate(true),"pickups":arena.pickups.duplicate(true),"feedback":arena.feedback_runtime.entries(),"events":arena.event_counts.duplicate(true),"map":arena._map_run.snapshot(),"player":{"pos":arena.player_pos,"health":arena.health,"mana":arena.mana,"shield":arena.shield,"elapsed":arena.elapsed},"projectile_ids":[arena.projectile_runtime.next_projectile_id,arena.projectile_runtime.next_cast_id,arena.projectile_runtime._sequence]}
func run()->void:
	if out.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-exploration-diagnostic-"):quit(78);return
	var m:=Existing.Meter.new();m.enabled=false
	var arena:Node=Arena.new() if instrumented else ProductionMain.new()
	if instrumented:
		arena.meter=m
		arena.projectile_runtime=Projectiles.new();arena.projectile_runtime.meter=m
		arena._geometry=Geometry.new();arena._geometry.meter=m
	arena.state=ProductionModel.new();arena.build_save_path="user://build_save.json"
	assert(arena.state.save_build(arena.build_save_path)==OK)
	root.add_child(arena);arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	arena.rng.seed=500050;arena.critical_runtime.reset(500051)
	assert(arena.save_build())
	assert(arena.craft_normal_map("broken_ruins",1,[],[],arena.map_draft().revision).ok)
	assert(arena.start_map(arena.map_draft().revision).ok)
	assert(arena.enemies.size()==37 and arena._geometry.snapshot().encounter_mode=="exploration")
	if instrumented:assert(arena._geometry is Geometry)
	arena.auto_fire=false;arena.invulnerable=1000.0
	while arena.hud.is_blocking():arena.hud.close_panel()
	# Same controlled volley recipe as the existing profile. Only fixture birth
	# protection is removed; catalog stats, initial positions, AI and walls stay.
	for enemy:Dictionary in arena.enemies:enemy.spawn=0.0
	var cast:Dictionary=Compiler.compile_group("tornado",Combat.snapshot({"damage":0.075,"crit_base_chance":0.0},[]),[])
	assert(cast.ok)
	var initial_sha:=sha(var_to_bytes(observe(arena)))
	var timings:Array=[];var phases:Dictionary={};var counts:Dictionary={};var samples:Array=[]
	for frame:int in range(24):
		arena.projectiles.clear();assert(arena.enemies.size()==37)
		for index:int in range(180):
			var target:Dictionary=arena.enemies[index%37]
			var spec:Dictionary=cast.snapshot.tornado_recipe.parent.duplicate(true)
			var origin:Vector2=Vector2(target.pos)-Vector2(float(target.radius)+float(spec.radius)+3.0,0)
			arena.projectiles.append(arena.projectile_runtime.make_projectile(origin,Vector2.RIGHT,spec,cast.packets.parent,cast.snapshot,arena.projectile_runtime.new_cast(),Color.ORANGE))
		m.clear();m.enabled=instrumented
		var began:=Time.get_ticks_usec();arena.tick(STEP);var duration:=Time.get_ticks_usec()-began
		m.enabled=false;timings.append(duration)
		for key:String in m.totals:
			if not phases.has(key):phases[key]=[]
			phases[key].append(m.totals[key])
		for key:String in m.counts:counts[key]=int(counts.get(key,0))+int(m.counts[key])
		var awake:=0
		for enemy:Dictionary in arena.enemies:awake+=int(enemy.get("exploration_awake",false))
		samples.append({"frame":frame,"cpu_us":duration,"phases":m.totals.duplicate(),"awake":awake,"enemies":arena.enemies.size(),"particles":arena.particles.size(),"hits":arena.event_counts.get("hit",0),"candidate_visits":arena.projectile_runtime.last_candidate_visits,"full_scan_visits":arena.projectile_runtime.last_full_scan_visits,"sorts":arena.projectile_runtime.last_work_sorts,"sort_skips":arena.projectile_runtime.last_work_sort_skips,"separation_candidates":arena.separation_candidate_visits,"observation_sha256":sha(var_to_bytes(observe(arena)))})
		assert(arena.alive and arena.kills==0)
		await process_frame
	var phase_summary:Dictionary={}
	for key:String in phases:phase_summary[key]=summary(phases[key])
	var observation:=observe(arena);var binary:=var_to_bytes(observation)
	var f:=FileAccess.open(out.trim_suffix(".json")+".bin",FileAccess.WRITE);f.store_buffer(binary);f.close()
	var result:Dictionary={"base_commit":"dbdc846e21e70477c98516562bf18273b2ebcc95","engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"instrumented":instrumented,"scope":"Headless tick CPU only, excluding draw/render/HUD presentation, projectile construction and observation hashing. Formal broken_ruins I roster/geometry with protected player and spawn protection removed; 180 artificial near-contact carriers per tick, not natural player throughput. No supports/burn/shock/freeze/deaths/rewards. Nested inclusive phases overlap.","frames":24,"step":STEP,"seeds":[500050,500051],"geometry":arena._geometry.snapshot(),"tick":summary(timings),"phases":phase_summary,"calls":counts,"samples":samples,"initial_sha256":initial_sha,"observation_sha256":sha(binary),"observation_bytes":binary.size(),"rng_state":str(arena.rng.state),"critical":arena.critical_runtime.checkpoint(),"events":arena.event_counts,"kills":arena.kills,"damage":arena.total_damage,"map":arena._map_run.snapshot()}
	f=FileAccess.open(out,FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t",true,true));f.close()
	print("EXPLORATION_DIAGNOSTIC ",JSON.stringify(result.tick)," sha=",result.observation_sha256)
	arena.queue_free();await process_frame;quit(0)
