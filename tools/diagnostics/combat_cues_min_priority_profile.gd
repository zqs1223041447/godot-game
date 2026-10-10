extends "res://tools/diagnostics/projectile_trace_copy_profile.gd"
## Reuse the existing formal-map fixture and identical Main timing wrappers.
const CUE_BASELINE="res://docs/qa/combat-cues-min-priority/baseline.gd.txt"
func observe(arena:Node)->Dictionary:
	var result:=super.observe(arena)
	result.visual_cues={"cues":arena.visual_cues.cues.duplicate(true),"next_id":arena.visual_cues.next_id,"dropped":arena.visual_cues.dropped}
	return result
func timed_cues(source:String)->GDScript:
	var code:=source.replace("class_name CombatCues\n","").replace("func emit_cue(","func _original_emit_cue(")
	code+="""
var cue_meter:RefCounted
func emit_cue(kind:String,origin:Vector2,data:Dictionary={})->int:
	if cues.size()>=MAX_CUES and int(PRIORITY.get(kind,-1))==0:cue_meter.extra("full_floor_calls")
	cue_meter.begin("cue_emit")
	var result:int=_original_emit_cue(kind,origin,data)
	cue_meter.end()
	return result
"""
	var script:=GDScript.new();script.source_code=code
	assert(script.reload()==OK);return script
func run()->void:
	if out.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-exploration-diagnostic-"):quit(78);return
	var sources:Array[String]=[FileAccess.get_file_as_string(CUE_BASELINE),FileAccess.get_file_as_string("res://scripts/visuals/combat_cues.gd")]
	var cue_scripts:Array[GDScript]=[timed_cues(sources[0]),timed_cues(sources[1])]
	var main_source:=FileAccess.get_file_as_string("res://scripts/main.gd")
	var main_script:=timed_source(main_source)
	var repetitions:Array=[]
	for repetition:int in range(2):
		var meters:Array=[Existing.Meter.new(),Existing.Meter.new()]
		for meter:Existing.Meter in meters:meter.enabled=false
		var arenas:Array[Node]=[fresh(main_script,meters[0]),fresh(main_script,meters[1])]
		for which:int in range(2):
			arenas[which].visual_cues=cue_scripts[which].new()
			arenas[which].visual_cues.cue_meter=meters[which]
		checked(var_to_bytes(observe(arenas[0]))==var_to_bytes(observe(arenas[1])),"Exact initial state including cue pool")
		var cast:Dictionary=Compiler.compile_group("tornado",Combat.snapshot({"damage":0.075,"crit_base_chance":0.0},[]),[])
		assert(cast.ok)
		var samples:Array=[];var times:Array=[[],[]];var cue_times:Array=[[],[]]
		for frame:int in range(24):
			var records:Array=[{},{}];var observed:Array[PackedByteArray]=[PackedByteArray(),PackedByteArray()]
			var order:Array=[0,1] if (frame+repetition)%2==0 else [1,0]
			for which:int in order:
				var arena:Node=arenas[which];var meter:Existing.Meter=meters[which]
				arena.projectiles.clear();assert(arena.enemies.size()==37)
				for index:int in range(180):
					var target:Dictionary=arena.enemies[index%37]
					var spec:Dictionary=cast.snapshot.tornado_recipe.parent.duplicate(true)
					var origin:Vector2=Vector2(target.pos)-Vector2(float(target.radius)+float(spec.radius)+3.0,0)
					arena.projectiles.append(arena.projectile_runtime.make_projectile(origin,Vector2.RIGHT,spec,cast.packets.parent,cast.snapshot,arena.projectile_runtime.new_cast(),Color.ORANGE))
				meter.clear();meter.enabled=true
				var began:=Time.get_ticks_usec();arena.tick(STEP);var duration:=Time.get_ticks_usec()-began
				meter.enabled=false;times[which].append(duration);cue_times[which].append(meter.totals.get("cue_emit_inclusive_us",0))
				observed[which]=var_to_bytes(observe(arena))
				records[which]={"cpu_us":duration,"phases":meter.totals.duplicate(),"calls":meter.counts.duplicate(),"extras":meter.extras.duplicate(),"sha256":sha(observed[which]),"cue_count":arena.visual_cues.cues.size(),"next_id":arena.visual_cues.next_id,"dropped":arena.visual_cues.dropped}
				checked(arena.alive and arena.kills==0,"Live no-death fixture")
			checked(observed[0]==observed[1],"Exact combat/RNG/cues bytes step %d round %d" % [frame,repetition])
			checked(records[0].calls==records[1].calls and records[0].extras==records[1].extras,"Same emitted cue and full-floor call counts")
			samples.append({"frame":frame,"order":order,"before":records[0],"after":records[1],"byte_equal":observed[0]==observed[1]})
			await process_frame
		var final_states:Array=[]
		for which:int in range(2):
			var arena:Node=arenas[which];var binary:=var_to_bytes(observe(arena))
			FileAccess.open(out.trim_suffix(".json")+"-%d-%d.bin" % [repetition,which],FileAccess.WRITE).store_buffer(binary)
			final_states.append({"sha256":sha(binary),"bytes":binary.size(),"rng":str(arena.rng.state),"critical":arena.critical_runtime.checkpoint(),"events":arena.event_counts.duplicate(),"damage":arena.total_damage,"kills":arena.kills,"cue_count":arena.visual_cues.cues.size(),"next_id":arena.visual_cues.next_id,"dropped":arena.visual_cues.dropped})
			arena.queue_free()
		repetitions.append({"repetition":repetition,"samples":samples,"final":final_states,"before":{"tick":summary(times[0]),"cue_emit":summary(cue_times[0])},"after":{"tick":summary(times[1]),"cue_emit":summary(cue_times[1])}})
		await process_frame
	var report:={"baseline_commit":"fabeeb3af1f8336ead5b49eac4bd40c1f216d37c","cue_source_sha256":[sha(sources[0].to_utf8_buffer()),sha(sources[1].to_utf8_buffer())],"main_source_sha256":sha(main_source.to_utf8_buffer()),"engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"failures":failures,"scope":"Two 24-step alternating comparisons, formal broken_ruins I,37 actors,180 controlled carriers per step. Identical Main and cue timing wrappers. Headless CPU excludes construction, observation hashing and rendering; not natural throughput or Windows FPS.","repetitions":repetitions}
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true)+"\n")
	for repetition:Dictionary in repetitions:print("CUES_PROFILE ",JSON.stringify({"round":repetition.repetition,"before":repetition.before,"after":repetition.after}))
	print("CUES_PROFILE failures=",failures);quit(1 if failures else 0)
