extends "res://tools/diagnostics/projectile_trace_copy_profile.gd"
## Actual canonical ownership and formal map; bounded projectile/effects steps, no AI tick.
const Cues=preload("res://scripts/visuals/combat_cues.gd")
class CueRecorder extends Cues:
	var emitted:Array[Dictionary]=[]
	func emit_cue(kind:String,origin:Vector2,data:Dictionary={})->int:
		var result:=super.emit_cue(kind,origin,data)
		if result>0:emitted.append(cues.back().duplicate(true))
		return result
class RecordedMain extends "res://scripts/main.gd":
	var trace_copy_meter:RefCounted # Existing fixture's disabled meter; no timing wrappers.
	var recorded_events:Array[Dictionary]=[]
	func _settle_projectile_events(events:Array[Dictionary],delta:float=0.0)->bool:
		var result:=super._settle_projectile_events(events,delta)
		for event:Dictionary in events:
			var row:=event.duplicate();row.erase("snapshot");row.erase("payload")
			recorded_events.append(row.duplicate(true))
		return result
var arena:Node
var checks:=0
var failed_labels:Array[String]=[]
var cases:Array=[]
var group:String
var recipe:Dictionary
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failed_labels.append(label);push_error(label)
	return ok
func events(kind:String)->Array:
	return arena.recorded_events.filter(func(e:Dictionary)->bool:return e.type==kind)
func emitted(kind:String)->Array:
	return arena.visual_cues.emitted.filter(func(c:Dictionary)->bool:return c.kind==kind)
func setup_case()->bool:
	var meter:=Existing.Meter.new();meter.enabled=false
	arena=fresh(RecordedMain,meter)
	arena.visual_cues=CueRecorder.new()
	var model:RefCounted=arena.state
	var items_before:int=model.snapshot().items.size()
	for definition:String in ["equipment:prism_bow","equipment:return_mantle","equipment:detonation_charm"]:
		var uid:=""
		for id:String in model.snapshot().items:
			if model.item(id).definition_id==definition:uid=id;break
		if not check(not uid.is_empty() and model.equip(uid),"Equip already-owned canonical "+definition):return false
	if not check(model.slot_skill(0,"tornado"),"Bind existing tornado gem through canonical transaction"):return false
	group=model.group_for_key(KEY_1);recipe=model.get_group_cast(group)
	if not check(recipe.ok and recipe.snapshot.effects.has("return_on_range") and recipe.snapshot.effects.has("explode_on_flight_end"),"Actual compiled snapshot owns return and natural-end explosion effects"):return false
	check(model.snapshot().items.size()==items_before,"Setup adds no items")
	check(int(recipe.initial_count)==5 and int(recipe.snapshot.tornado_recipe.child_count)==3,"Existing authored five-parent/three-child recipe is unchanged")
	check(arena.enemies.size()==37 and arena._geometry.snapshot().encounter_mode=="exploration","Keep real formal roster and map geometry")
	arena.mana=float(arena.get_stats().max_mana);arena.player_facing=Vector2.RIGHT
	if not check(arena.cast_group(group),"Real canonical tornado cast admitted"):return false
	check(arena.projectiles.size()==int(recipe.initial_count) and emitted("cast").size()==1,"One cast cue for the admitted full volley")
	return true
func advance_until(stage:String)->void:
	for step:int in range(150):
		arena.elapsed+=STEP
		arena._update_projectiles(STEP);arena._update_effects(STEP)
		if stage=="returned" and events("return_started").size()==15:return
		if stage=="ended" and arena.projectiles.is_empty():return
	check(false,"Bounded 150-step progress reached "+stage)
func check_cue_mapping()->void:
	var corresponding:Array=[]
	for event:Dictionary in arena.recorded_events:
		if event.type in ["split","return_started","explosion"]:corresponding.append(event)
	var cues:Array=arena.visual_cues.emitted.filter(func(c:Dictionary)->bool:return c.kind in ["split","return","explosion"])
	check(cues.size()==corresponding.size(),"One admitted cue per actual split/return/explosion event")
	for i:int in range(mini(cues.size(),corresponding.size())):
		var event:Dictionary=corresponding[i];var cue:Dictionary=cues[i]
		var kind:String="return" if event.type=="return_started" else event.type
		var radius:float=float(event.radius) if event.type=="explosion" else (19.0 if kind=="return" else 26.0)
		check(cue.kind==kind and cue.origin==event.pos and cue.radius==radius,"Cue preserves event order, actual origin and radius %d"%i)
		check(int(cue.id)==i+2,"Cue IDs remain sequential after the single cast cue %d"%i)
func save_case(name:String)->void:
	cases.append({"case":name,"events":arena.recorded_events.duplicate(true),"emitted_cues":arena.visual_cues.emitted.duplicate(true),"remaining_cues":arena.visual_cues.cues.size(),"next_cue_id":arena.visual_cues.next_id,"dropped":arena.visual_cues.dropped,"remaining_projectiles":arena.projectiles.size(),"rng":str(arena.rng.state),"critical":arena.critical_runtime.checkpoint()})
func natural_case()->void:
	if not setup_case():return
	var frozen:Dictionary=arena.projectiles[0].snapshot.duplicate(true)
	var rng_before:int=arena.rng.state;var critical_events:int=arena.critical_runtime.events
	var persistence:=var_to_bytes([arena.state.snapshot(),FileAccess.get_file_as_bytes(arena.build_save_path)])
	advance_until("ended")
	check(events("split").size()==5 and events("spawned").size()==15,"Five actual parents create fifteen child carriers")
	check(events("return_started").size()==15 and events("explosion").size()==15,"Every actual child returns then explodes exactly once")
	check(events("terrain_hit").is_empty() and events("hit").is_empty() and arena.kills==0,"Unobstructed entry fixture has no collision or damage interference")
	var parent_ids:Array=[]
	for event:Dictionary in events("split"):parent_ids.append(event.projectile_id)
	for parent_id:int in parent_ids:
		var parent_events:Array=arena.recorded_events.filter(func(e:Dictionary)->bool:return e.projectile_id==parent_id)
		check(parent_events.filter(func(e:Dictionary)->bool:return e.type=="terminated" and e.reason=="split_consumed").size()==1,"Parent is consumed exactly once by split")
		check(not parent_events.any(func(e:Dictionary)->bool:return e.type in ["flight_ended","explosion","return_started"]),"Split consumption cannot masquerade as natural end/return")
	for child:Dictionary in events("spawned"):
		var history:Array=arena.recorded_events.filter(func(e:Dictionary)->bool:return e.projectile_id==child.projectile_id)
		var returned:Array=history.filter(func(e:Dictionary)->bool:return e.type=="return_started")
		var ended:Array=history.filter(func(e:Dictionary)->bool:return e.type=="flight_ended")
		var explosions:Array=history.filter(func(e:Dictionary)->bool:return e.type=="explosion")
		check(child.generation==1 and parent_ids.has(child.parent_id) and child.root_id==child.parent_id,"Child retains real parent/root identity and bounded generation")
		check(returned.size()==1 and ended.size()==1 and explosions.size()==1,"Child return/end/explosion are each once-only")
		if returned.size()==1 and ended.size()==1 and explosions.size()==1:
			check(returned[0].sequence<ended[0].sequence and ended[0].sequence<explosions[0].sequence,"Child preserves return before natural-end before explosion ordering")
			check(ended[0].reason=="lifetime_expired" and is_equal_approx(ended[0].age,float(frozen.tornado_recipe.child.lifetime)),"Return never refreshes the immutable child lifetime")
			check(explosions[0].effect_id=="explosion:%d"%child.projectile_id and explosions[0].reason==ended[0].reason,"One explosion identity belongs to its naturally ended child")
	check_cue_mapping()
	check(arena.rng.state==rng_before and arena.critical_runtime.events==critical_events+15,"Presentation adds no gameplay RNG; fifteen actual secondary events retain critical admission")
	check(var_to_bytes([arena.state.snapshot(),FileAccess.get_file_as_bytes(arena.build_save_path)])==persistence,"Unobstructed chain does not mutate canonical ownership or save")
	var count:int=arena.visual_cues.emitted.size();arena._update_projectiles(1.0);arena._update_effects(1.0)
	check(arena.visual_cues.emitted.size()==count and arena.visual_cues.cues.is_empty(),"Empty subsequent tick cannot duplicate effects; all cues expire")
	save_case("natural_chain")
func cancel_case(returning:bool)->void:
	if not setup_case():return
	if returning:advance_until("returned")
	var shots:Array=arena.projectiles.duplicate()
	check(shots.size()==(15 if returning else 5),"Cancellation reaches the intended live phase")
	var explosions:int=emitted("explosion").size();var secondary_events:int=arena.critical_runtime.events
	if returning:
		arena.invulnerable=0.0;arena.shield=0.0;arena.health=1.0
		check(arena.hit_player_components({"chaos":100.0}) and not arena.alive,"Real player death cancels returning children")
	else:
		arena.restart_run()
		check(arena.alive,"Actual restart cancels outbound parents")
	check(arena.projectiles.is_empty(),"Actual cancellation removes all carriers")
	for shot:Dictionary in shots:
		check(not shot.active and shot.end_reason==("owner_death" if returning else "run_reset"),"Cancelled carrier retains non-natural reason")
	arena._update_projectiles(3.0);arena._update_effects(1.0)
	check(emitted("explosion").size()==explosions and events("flight_ended").is_empty() and events("explosion").is_empty(),"Cancellation and later empty tick cannot fabricate natural end or explosion")
	check(arena.critical_runtime.events==(secondary_events if returning else 0),"Death preserves critical count; restart resets it without a secondary event")
	check(arena.visual_cues.cues.is_empty(),"Remaining accepted presentation expires after cancellation")
	save_case("owner_death_returning" if returning else "restart_outbound")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-exploration-diagnostic-"):quit(78);return
	await natural_case();arena.queue_free();await process_frame
	await cancel_case(false);arena.queue_free();await process_frame
	await cancel_case(true);arena.queue_free();await process_frame
	var report:={"checks":checks,"failures":failed_labels.size(),"failed_labels":failed_labels,"cases":cases}
	FileAccess.open(OS.get_environment("TORNADO_CUES_OUT"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true)+"\n")
	print("CANONICAL_TORNADO_CUES checks=%d failures=%d"%[checks,failed_labels.size()]);quit(1 if not failed_labels.is_empty() else 0)
