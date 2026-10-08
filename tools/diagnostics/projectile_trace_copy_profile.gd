extends "res://tools/diagnostics/exploration_density_profile.gd"
## One existing exploration fixture, two short interleaved repetitions.
## Dynamically loaded original/current Main receive identical timer wrappers.
var failures:=0
func checked(ok:bool,label:String)->void:
	if not ok:failures+=1;push_error(label)
func timed_source(source:String)->GDScript:
	var code:=source+"\nvar trace_copy_meter: RefCounted\n"
	var wrappers:Array=[
		["_update_projectiles","delta:float","delta","void","projectiles"],
		["_update_enemies","delta:float","delta","void","enemy_ai"],
		["_update_effects","delta:float","delta","void","effects"],
		["_settle_projectile_events","events:Array[Dictionary],original_delta:float=0.0","events,original_delta","bool","event_settlement"],
		["_apply_damage_packet","enemy:Dictionary,packet:Dictionary,snapshot:Dictionary,color:Color,slow:float=0.0,provenance:Dictionary={}","enemy,packet,snapshot,color,slow,provenance","void","damage_packet"]]
	for row:Array in wrappers:
		var marker:String="func "+str(row[0])+"("
		assert(code.count(marker)==1)
		code=code.replace(marker,"func _trace_copy_original"+str(row[0])+"(")
		code+="\nfunc %s(%s)->%s:\n\ttrace_copy_meter.begin(\"%s\")\n" % [row[0],row[1],row[3],row[4]]
		code+="\t%s_trace_copy_original%s(%s)\n\ttrace_copy_meter.end()\n" % ["var result=" if row[3]!="void" else "",row[0],row[2]]
		if row[3]!="void":code+="\treturn result\n"
	var result:=GDScript.new();result.source_code=code
	assert(result.reload()==OK);return result
func fresh(script:GDScript,m:Existing.Meter)->Node:
	var arena:Node=script.new();arena.trace_copy_meter=m
	arena.state=ProductionModel.new();arena.build_save_path="user://build_save.json"
	# Formal admission requires the canonical name. Reset only this tool's
	# guarded /tmp save between fixtures; measured no-death ticks never save.
	if FileAccess.file_exists(arena.build_save_path):
		assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(arena.build_save_path))==OK)
	assert(arena.state.save_build(arena.build_save_path)==OK)
	root.add_child(arena);arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	arena.rng.seed=500050;arena.critical_runtime.reset(500051)
	assert(arena.save_build())
	assert(arena.craft_normal_map("broken_ruins",1,[],[],arena.map_draft().revision).ok)
	assert(arena.start_map(arena.map_draft().revision).ok)
	assert(arena.enemies.size()==37 and arena._geometry.snapshot().encounter_mode=="exploration")
	arena.auto_fire=false;arena.invulnerable=1000.0
	while arena.hud.is_blocking():arena.hud.close_panel()
	for enemy:Dictionary in arena.enemies:enemy.spawn=0.0
	return arena
func run()->void:
	var baseline_path:=OS.get_environment("TRACE_COPY_BASELINE_MAIN")
	if out.is_empty() or baseline_path.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-exploration-diagnostic-"):quit(78);return
	var sources:Array[String]=[FileAccess.get_file_as_string(baseline_path),FileAccess.get_file_as_string("res://scripts/main.gd")]
	var scripts:Array[GDScript]=[timed_source(sources[0]),timed_source(sources[1])]
	var historical:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/projectile-trace-copy/baseline/control.json"))
	var all_timings:Array=[[],[]];var all_phases:Array=[{},{}];var repetitions:Array=[]
	for repetition:int in range(2):
		var meters:Array=[Existing.Meter.new(),Existing.Meter.new()]
		for m:Existing.Meter in meters:m.enabled=false
		var arenas:Array[Node]=[fresh(scripts[0],meters[0]),fresh(scripts[1],meters[1])]
		for arena:Node in arenas:checked(sha(var_to_bytes(observe(arena)))==historical.initial_sha256,"Same historical initial state")
		var cast:Dictionary=Compiler.compile_group("tornado",Combat.snapshot({"damage":0.075,"crit_base_chance":0.0},[]),[])
		assert(cast.ok)
		var samples:Array=[]
		for frame:int in range(24):
			var records:Array=[{},{}];var observed:Array[PackedByteArray]=[PackedByteArray(),PackedByteArray()]
			var order:Array=[0,1] if (frame+repetition)%2==0 else [1,0]
			for which:int in order:
				var arena:Node=arenas[which];var m:Existing.Meter=meters[which]
				arena.projectiles.clear();assert(arena.enemies.size()==37)
				for index:int in range(180):
					var target:Dictionary=arena.enemies[index%37]
					var spec:Dictionary=cast.snapshot.tornado_recipe.parent.duplicate(true)
					var origin:Vector2=Vector2(target.pos)-Vector2(float(target.radius)+float(spec.radius)+3.0,0)
					arena.projectiles.append(arena.projectile_runtime.make_projectile(origin,Vector2.RIGHT,spec,cast.packets.parent,cast.snapshot,arena.projectile_runtime.new_cast(),Color.ORANGE))
				m.clear();m.enabled=true
				var began:=Time.get_ticks_usec();arena.tick(STEP);var duration:=Time.get_ticks_usec()-began
				m.enabled=false;all_timings[which].append(duration)
				for key:String in m.totals:
					if not all_phases[which].has(key):all_phases[which][key]=[]
					all_phases[which][key].append(m.totals[key])
				observed[which]=var_to_bytes(observe(arena))
				records[which]={"cpu_us":duration,"phases":m.totals.duplicate(),"sha256":sha(observed[which])}
				checked(records[which].sha256==historical.samples[frame].observation_sha256,"Recorded historical state at step %d side %d" % [frame,which])
				checked(arena.alive and arena.kills==0,"Live no-death fixture")
			checked(observed[0]==observed[1],"Exact before/after observation bytes at step %d" % frame)
			samples.append({"frame":frame,"order":order,"before":records[0],"after":records[1],"byte_equal":observed[0]==observed[1]})
			await process_frame
		var final_states:Array=[]
		for which:int in range(2):
			var arena:Node=arenas[which];var binary:=var_to_bytes(observe(arena))
			var file:=FileAccess.open(out.trim_suffix(".json")+"-%d-%d.bin" % [repetition,which],FileAccess.WRITE);file.store_buffer(binary);file.close()
			final_states.append({"sha256":sha(binary),"bytes":binary.size(),"rng":str(arena.rng.state),"critical":arena.critical_runtime.checkpoint(),"events":arena.event_counts.duplicate(),"damage":arena.total_damage,"kills":arena.kills})
			arena.queue_free()
		repetitions.append({"repetition":repetition,"samples":samples,"final":final_states})
		await process_frame
	var totals:Array=[]
	for which:int in range(2):
		var phases:Dictionary={}
		for key:String in all_phases[which]:phases[key]=summary(all_phases[which][key])
		totals.append({"tick":summary(all_timings[which]),"phases":phases})
	var report:Dictionary={"baseline_commit":"dbdc846e21e70477c98516562bf18273b2ebcc95","source_sha256":[sha(sources[0].to_utf8_buffer()),sha(sources[1].to_utf8_buffer())],"scope":"Two same-input formal broken_ruins I repetitions, each 24 interleaved before/after steps,37 original actors,180 controlled carriers. Identical wrappers. Tick excludes creation/hash/render/HUD. Not Windows FPS.","engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"failures":failures,"before":totals[0],"after":totals[1],"repetitions":repetitions}
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true)+"\n")
	print("TRACE_COPY_PROFILE ",JSON.stringify({"failures":failures,"before":totals[0],"after":totals[1]}));quit(1 if failures else 0)
