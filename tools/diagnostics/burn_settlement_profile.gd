extends SceneTree
## Short same-source stress samples; instrumentation lives only in this tool.
## The protected player fixture leaves monster AI/attack scheduling enabled.
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const Combat=preload("res://scripts/combat/combat_data.gd")
const STEP:=1.0/60.0
const ProductionMain=preload("res://scripts/main.gd")
const ProductionModel=preload("res://scripts/canonical_game_state.gd")
const ProductionBurn=preload("res://scripts/combat/burn_runtime.gd")
var instrumented:=false
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
	var f:=FileAccess.open(out,FileAccess.WRITE);f.store_string(JSON.stringify({"base_commit":"b93018005413444ad6f988974f4ef3ea09902c5e","instrumented":instrumented,"production_without_wrappers":not instrumented and OS.get_environment("DENSITY_CAPTURE_INVERSION")!="1","scope":"Headless script CPU; nested inclusive phases are not additive. Stress volleys are controlled carriers, not a claim one player naturally emits180 every tick. Catalog monsters retain AI and attack scheduling; player protected for the benchmark. No rendering/WindowsFPS measurement.","engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"rows":rows},"\t",true,true));f.close()
func run()->void:
	create_timer(60.0).timeout.connect(func():push_error("Density diagnostic did not complete within60seconds");quit(1))
	if out.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v063-"):quit(78);return
	for mode:String in ["no_burn","ember_deaths"]:
		if not OS.get_environment("DENSITY_MODE").is_empty() and mode!=OS.get_environment("DENSITY_MODE"):continue
		var arena:Node=ProductionMain.new()
		var state:RefCounted=ProductionModel.new()
		arena.state=state;arena.build_save_path="user://build_save.json"
		if state.save_build(arena.build_save_path)!=OK:push_error("Fresh diagnostic save rejected");quit(1);return
		var burns:RefCounted=ProductionBurn.new()
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
		var frame_observations:Array=[]
		for frame:int in range(frames):
			if mode!="ember_deaths" or frame==0:
				arena.projectiles.clear()
				assert(arena.enemies.size()==100,"The controlled volley begins at full real100actor density")
				for index:int in range(180):
					var target:Dictionary=arena.enemies[index%100]
					var spec:Dictionary=cast.snapshot.tornado_recipe.parent.duplicate(true)
					var origin:Vector2=Vector2(target.pos)-Vector2(float(target.radius)+float(spec.radius)+3.0,0)
					arena.projectiles.append(arena.projectile_runtime.make_projectile(origin,Vector2.RIGHT,spec,cast.packets.parent,cast.snapshot,arena.projectile_runtime.new_cast(),Color.ORANGE))
			var hits:int=int(arena.event_counts.get("hit",0));var kills:int=arena.kills
			var began:=Time.get_ticks_usec();arena.tick(STEP);var total:int=Time.get_ticks_usec()-began
			timings.append(total)

			samples.append({"frame":frame,"cpu_us":total,"hits":int(arena.event_counts.get("hit",0))-hits,"kills":arena.kills-kills,"enemies":arena.enemies.size(),"projectiles":arena.projectiles.size(),"burns":burns._states.size(),"particles":arena.particles.size(),"pickups":arena.pickups.size(),"feedback":arena.feedback_runtime.entries().size(),"pending_feedback":arena.feedback_runtime._pending.size()})
			assert(arena.alive)
			frame_observations.append(observe(arena))
			await process_frame
		var phase_summary:Dictionary={}
		for key:String in phases:phase_summary[key]=summary(phases[key])
		var observation:Dictionary=observe(arena)
		var binary:PackedByteArray=var_to_bytes(frame_observations);var f:=FileAccess.open(out.trim_suffix(".json")+"-"+mode+".bin",FileAccess.WRITE);f.store_buffer(binary);f.close()
		assert(arena.save_build(),"Final unchanged-state save must succeed")
		f=FileAccess.open(out.trim_suffix(".json")+"-"+mode+".save",FileAccess.WRITE);f.store_buffer(FileAccess.get_file_as_bytes(arena.build_save_path));f.close()
		rows.append({"mode":mode,"frames":frames,"initial_enemies":100,"initial_inventory":initial.items.size(),"final_inventory":arena.state.snapshot().items.size(),"tick":summary(timings),"phases":phase_summary,"calls":counts,"extra_counts":extras,"samples":samples,"kills":arena.kills-start_kills,"reward_kills":arena.reward_kills,"observation_sha256":sha(binary),"observation_bytes":binary.size()})
		write();print("DENSITY_CASE ",mode," ",JSON.stringify(rows.back().tick)," calls=",JSON.stringify(counts))
		arena.queue_free();await process_frame
	print("LATEST_DENSITY_PROFILE_COMPLETE");quit(0)

func observe(arena:Node)->Dictionary:
	return {"enemies":arena.enemies.duplicate(true),"projectiles":arena.projectiles.duplicate(true),
		"queue":arena.monster_runtime.queue.duplicate(true),"roots":arena.monster_runtime.roots.duplicate(true),"monster_trace":arena.monster_runtime.trace.duplicate(true),
		"rng":arena.rng.state,"state":arena.state.snapshot(),"stats":arena._stats.duplicate(true),"resources":[arena.health,arena.mana,arena.shield],
		"combat":arena.combat_trace.duplicate(true),"hits":arena.damage_trace.duplicate(true),"incoming":arena.incoming_damage_trace.duplicate(true),"admission":arena.attack_admission_trace.duplicate(true),
		"burn_trace":arena.burn_trace.duplicate(true),"burns":arena.burn_runtime._states.duplicate(true),"burn_keys":arena.burn_runtime._status_keys.duplicate(),"burn_order_dirty":arena.burn_runtime._status_order_dirty,
		"ember_deaths":arena._ember_deaths.duplicate(true),"ember_projectile_clock":arena._ember_projectile_clock.duplicate(true),
		"timers":[arena.attack_timer,arena.spawn_timer,arena.damage_delay,arena.invulnerable,arena.elapsed],"cooldowns":arena.cooldowns.duplicate(true),"groups":arena.group_cooldowns.snapshot(),
		"flasks":arena.flask_runtime.snapshot(),"shock":arena.shock_runtime.statuses(arena.elapsed),"critical":arena.critical_runtime.checkpoint(),"leech":arena.leech_runtime.snapshot(),"events":arena.event_counts.duplicate(true),
		"feedback":[arena.feedback_runtime._time,arena.feedback_runtime._pending.duplicate(true),arena.feedback_runtime._visible.duplicate(true)],
		"particles":arena.particles.duplicate(true),"text":arena.floating_text.duplicate(true),"pickups":arena.pickups.duplicate(true),"rings":arena.rings.duplicate(true),
		"kills":arena.kills,"reward_kills":arena.reward_kills,"total_damage":arena.total_damage,"shots":arena.total_shots,"saves":arena.state.successful_saves,
		"disk":FileAccess.get_file_as_bytes(arena.build_save_path)}
