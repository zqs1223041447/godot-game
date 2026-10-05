extends SceneTree
const Compiler=preload("res://scripts/combat/skill_compiler.gd")
const OldDefense=preload("res://tests/fixtures/v052/defense_before_shock.gd")
const NewDefense=preload("res://scripts/mechanics/defense_rules.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:String=OS.get_environment("SHOCK_LEGACY_OUTPUT")
	if output.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v052-"):quit(78);return
	var arena=load("res://scenes/main.tscn").instantiate()
	if OS.get_environment("SHOCK_LEGACY_OLD")=="1":arena.set_script(load("res://tests/fixtures/v052/main_before_shock.gd"))
	root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	arena.hud.close_panel();arena._world_mode="normal";arena.rng.seed=520882;arena.restart_run();arena.hud.close_panel();arena._world_mode="normal"
	arena.enemies.clear();arena.monster_runtime.reset();arena.monster_runtime.next_id=0;arena.spawn_timer=1000.0;arena.player_pos=arena.ARENA.get_center();arena.auto_fire=true
	arena._stats.life_regen=1000.0;arena._stats.mana_regen=1000.0;arena._stats.max_health=10000.0;arena.health=10000.0
	for i:int in range(12):
		var enemy:Dictionary=arena._spawn_monster(["crawler","skitter","brute"][i%3],arena.player_pos+Vector2(80+i*11,20 if i%2 else -20));enemy.spawn=0.0
	var observations:Array=[];var casts:=0
	for tick:int in range(180):
		if tick in [0,60,120]:
			var spell:Dictionary=Compiler.compile_group("meteor",arena.state.get_combat_snapshot(),["ignite"])
			if arena._execute_compiled(spell):casts+=1
		if tick in [10,80]:
			var spell:Dictionary=Compiler.compile_group("tornado",arena.state.get_combat_snapshot(),["ember_proliferation"])
			if arena._execute_compiled(spell):casts+=1
		if tick in [20,100]:
			var spell:Dictionary=Compiler.compile_group("chain",arena.state.get_combat_snapshot(),[])
			if arena._execute_compiled(spell):casts+=1
		arena.tick(1.0/60.0)
		observations.append([arena.enemies.duplicate(true),arena.projectiles.duplicate(true),arena.monster_runtime.queue.duplicate(true),arena.monster_runtime.roots.duplicate(true),arena.rng.state,arena.state.snapshot(),arena.health,arena.mana,arena.shield,arena.combat_trace.duplicate(true),arena.damage_trace.duplicate(true),arena.incoming_damage_trace.duplicate(true),arena.group_cooldowns.snapshot(),arena.flask_runtime.snapshot(),arena.burn_runtime.statuses(),arena.burn_trace.duplicate(true),arena.critical_runtime.checkpoint(),arena.leech_runtime.snapshot(),[arena.feedback_runtime._time,arena.feedback_runtime._pending.duplicate(true),arena.feedback_runtime._visible.duplicate(true)],arena.particles.duplicate(true),arena.floating_text.duplicate(true)])
	var exact_cases:=0
	for component:Variant in [{},{"fire":10.0},{"physical":1.0,"cold":25.5,"lightning":0.0},{"fire":-1.0},true]:
		for def:Variant in [{},{"fire_resistance":0.75},{"fire_resistance":-0.2},{"fire_resistance":INF}]:
			assert(var_to_bytes(OldDefense.incoming_hit(component,def,5.0,100.0))==var_to_bytes(NewDefense.incoming_hit(component,def,5.0,100.0)));exact_cases+=1
	var bytes:=var_to_bytes(observations);FileAccess.open(output+".bin",FileAccess.WRITE).store_buffer(bytes)
	assert(arena.elapsed>2.9 and casts>0 and arena.kills>0,"Must exercise actual combat and deaths")
	assert(arena.save_build());var save:PackedByteArray=FileAccess.get_file_as_bytes(arena.build_save_path);FileAccess.open(output+".save",FileAccess.WRITE).store_buffer(save)
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes)
	var report:Dictionary={"ticks":180,"casts":casts,"kills":arena.kills,"reward_kills":arena.reward_kills,"damage":arena.total_damage,"events":arena.event_counts,"rng":arena.rng.state,"observation_bytes":bytes.size(),"observation_sha256":h.finish().hex_encode(),"defense_exact_cases":exact_cases}
	FileAccess.open(output+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print("SHOCK_LEGACY ",JSON.stringify(report));arena.queue_free();await process_frame;quit()
