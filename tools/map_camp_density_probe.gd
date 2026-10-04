extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var input:=OS.get_environment("V043_DENSITY_FIXTURE");var output:=OS.get_environment("V043_DENSITY_OUTPUT")
	if input.is_empty() or output.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var fixture:Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(input))
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	var compiled:Dictionary=arena.MapCompiler.compile_normal(fixture.profile.id,fixture.profile.journey_tier,fixture.profile.normal_ids,fixture.profile.special_ids);assert(compiled.ok)
	# Rebuild version-local display text while preserving all numeric combat inputs.
	var local_profile:Dictionary=compiled.profile
	for key:String in ["wave","ordinary_target","fee","completion_reward","normal_ids","special_ids","encounter_profile"]:assert(local_profile[key]==fixture.profile[key])
	arena.state._accept_memory(fixture.build);arena._stats=arena.state.get_stats();arena._world_mode="map";arena.wave=int(local_profile.wave);assert(arena._map_run.begin(local_profile));arena._map_run.admitted=fixture.admitted.duplicate(true)
	if arena.has_method("_prepare_camp_run"):
		var plan:Dictionary=arena._prepare_camp_run(local_profile,43);assert(plan.ok);arena._map_camps=plan.state;arena._camp_landmarks=plan.landmarks
		for camp:Dictionary in fixture.camps:assert(arena._map_camps.activate(camp.id,camp.root_ids))
	arena._refresh_world_geometry();arena.enemies.assign(fixture.enemies.duplicate(true));arena.EncounterAdmission._restore(arena.monster_runtime,fixture.runtime.duplicate(true))
	arena.player_pos=fixture.position;arena.auto_fire=false;arena.alive=true;arena.invulnerable=999.0;arena.rng.seed=431234;arena.critical_runtime.reset(43);arena.health=arena._stats.max_health;arena.mana=arena._stats.max_mana;arena.shield=arena._stats.max_shield
	arena.elapsed=0.0;arena._autosave_timer=0.0;arena.projectiles.clear();arena.particles.clear();arena.rings.clear();arena.pickups.clear();arena.floating_text.clear();arena.damage_trace.clear()
	var samples:Array[int]=[]
	for i:int in range(120):
		var start:=Time.get_ticks_usec();arena._tick(1.0/60.0);samples.append(Time.get_ticks_usec()-start)
	assert(is_equal_approx(arena.elapsed,2.0))
	var observation:Dictionary={"enemies":arena.enemies,"runtime":arena.EncounterAdmission._snapshot(arena.monster_runtime),"projectiles":arena.projectiles,"particles":arena.particles,"rings":arena.rings,"pickups":arena.pickups,"player":arena.player_pos,"health":arena.health,"mana":arena.mana,"shield":arena.shield,"rng":arena.rng.state,"critical":arena.critical_runtime.checkpoint(),"elapsed":arena.elapsed,"kills":arena.kills}
	var raw:=var_to_bytes(observation);var file:=FileAccess.open(output+".bin",FileAccess.WRITE);file.store_buffer(raw);file.close();samples.sort()
	var sum:=0.0;var over16:=0;var over33:=0
	for sample:int in samples:sum+=sample;over16+=int(sample>16667);over33+=int(sample>33333)
	var report:Dictionary={"version":ProjectSettings.get_setting("application/config/version"),"samples":120,"seconds_simulated":2,"actors_before":fixture.enemies.size(),"actors_after":arena.enemies.size(),"median_cpu_ms":samples[60]/1000.0,"p95_cpu_ms":samples[113]/1000.0,"max_cpu_ms":samples[119]/1000.0,"mean_cpu_ms":sum/120000.0,"over16_7":over16,"over33_3":over33,"scope":"headless simulation CPU, same frozen36enemy input, no WindowsFPS or render claim"}
	file=FileAccess.open(output+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close();print("Camp density: ",report);arena.queue_free();await process_frame;quit()
