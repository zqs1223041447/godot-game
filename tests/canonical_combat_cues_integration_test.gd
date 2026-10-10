extends "res://tools/diagnostics/projectile_trace_copy_profile.gd"
## Reuse the canonical formal-map fixture only; this is not a timing run.
var checks:=0
var failed_labels:Array[String]=[]
var stages:Array=[]
var arena:Node
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failed_labels.append(label);push_error(label)
	return ok
func cue_state()->PackedByteArray:
	return var_to_bytes([arena.visual_cues.cues,arena.visual_cues.next_id,arena.visual_cues.dropped])
func kinds(kind:String)->Array:
	return arena.visual_cues.cues.filter(func(cue:Dictionary)->bool:return cue.kind==kind)
func gameplay()->PackedByteArray:
	return var_to_bytes([observe(arena),arena.group_cooldowns.snapshot(),arena.flask_runtime.snapshot(),arena.incoming_damage_trace,arena.state.save_attempts,arena.state.successful_saves,FileAccess.get_file_as_bytes(arena.build_save_path)])
func rejected(group:String,label:String)->void:
	var before:=gameplay();var cues:=cue_state()
	check(not arena.cast_group(group),label+": rejected by actual group admission")
	check(gameplay()==before and cue_state()==cues,label+": no combat/RNG/save/resource/cooldown/cue/ID/drop mutation")
func record(label:String)->void:
	stages.append({"stage":label,"cues":arena.visual_cues.cues.duplicate(true),"next_id":arena.visual_cues.next_id,"dropped":arena.visual_cues.dropped,"kills":arena.kills,"reward_kills":arena.reward_kills,"rng":str(arena.rng.state)})
func run()->void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-exploration-diagnostic-") or not OS.get_user_data_dir().begins_with(isolated+"/"):quit(78);return
	var meter:=Existing.Meter.new();meter.enabled=false
	arena=fresh(timed_source(FileAccess.get_file_as_string("res://scripts/main.gd")),meter)
	check(arena.state is ProductionModel and arena.world_context().mode=="map","Canonical model owns actual formal map")
	check(arena.enemies.size()==37 and arena.visual_cues.cues.is_empty(),"Existing formal roster starts with an empty cue pool")
	var group:="";var compiled:Dictionary={}
	for row:Dictionary in arena.state.snapshot().skill_groups:
		var recipe:Dictionary=arena.state.get_group_cast(row.id)
		if recipe.get("ok",false) and int(recipe.get("initial_count",0))>0 and recipe.skill_id in ["tornado","bolt","frost","shade_bolt"]:
			group=row.id;compiled=recipe;break
	if not check(not group.is_empty(),"Existing owned projectile gem compiles without granting items"):
		await finish();return
	arena.mana=0.0;rejected(group,"Insufficient mana")
	arena.mana=float(arena.get_stats().max_mana)
	arena.hud.open_panel("inventory");rejected(group,"Blocking inventory");arena.hud.close_panel()
	var mana_before:float=arena.mana
	if not check(arena.cast_group(group),"Actual owned group cast admitted"):
		await finish();return
	check(arena.projectiles.size()==int(compiled.initial_count),"Admitted volley owns the compiled projectile count")
	check(is_equal_approx(arena.mana,mana_before-float(compiled.mana)) and arena.group_cooldown_remaining(group)>0.0,"Admitted volley pays mana and starts canonical cooldown")
	var casts:=kinds("cast")
	check(casts.size()==1,"Exactly one cast cue per admitted volley")
	if not casts.is_empty():check(casts[0].skill==compiled.skill_id and casts[0].origin==arena.player_pos,"Cast cue identifies actual skill and origin")
	record("accepted cast")
	rejected(group,"Active cooldown")
	arena.group_cooldowns.advance(10.0)
	# Controlled saturation uses copies of an actual admitted projectile; no tick
	# runs with duplicate IDs, and the admission path checks capacity only.
	var template:Dictionary=arena.projectiles[0].duplicate(true)
	while arena.projectiles.size()<arena.MAX_PROJECTILES:arena.projectiles.append(template.duplicate(true))
	rejected(group,"Full projectile capacity")
	arena.projectile_runtime.cancel_all(arena.projectiles)
	arena.visual_cues.reset();arena.invulnerable=0.0;arena.shield=0.0
	var health_before:float=arena.health
	check(arena.hit_player_components({"chaos":5.0}),"Actual unshielded incoming damage admitted")
	check(arena.health<health_before and kinds("hurt").size()==1,"Life loss emits one hurt cue")
	if not kinds("hurt").is_empty():check(not kinds("hurt")[0].shielded,"Life hurt cue is not shielded")
	var before:=gameplay();var cues:=cue_state()
	check(not arena.hit_player_components({"chaos":5.0}),"Hurt immunity rejects repeated incoming hit")
	check(gameplay()==before and cue_state()==cues,"Rejected incoming hit preserves gameplay and exact cue identity")
	arena.invulnerable=0.0;arena.shield=10.0;health_before=arena.health
	check(arena.hit_player_components({"chaos":5.0}),"Actual fully shielded incoming hit admitted")
	check(arena.health==health_before and arena.shield<10.0 and kinds("hurt").size()==2,"Shield loss emits exactly one additional hurt cue")
	if kinds("hurt").size()==2:check(kinds("hurt").back().shielded,"Shield absorption uses shielded hurt cue")
	record("player damage")
	var enemy:Dictionary={}
	for candidate:Dictionary in arena.enemies:
		if candidate.rarity=="normal" and int(candidate.generation)==0:enemy=candidate;break
	if not check(not enemy.is_empty(),"Use a registered ordinary root from the actual map"):
		await finish();return
	# Controlled resources isolate the actual settlement/feedback consumer.
	enemy.health=100.0;enemy.shield=10.0
	arena.visual_cues.reset()
	arena._damage_enemy(enemy,5.0,Color.CYAN)
	check(enemy.health==100.0 and enemy.shield==5.0 and kinds("impact").size()==1,"Enemy shield settlement emits exactly one impact")
	if not kinds("impact").is_empty():check(kinds("impact")[0].shielded and kinds("impact")[0].target_id==enemy.id,"Shield impact keeps real target identity")
	enemy.shield=0.0;arena._damage_enemy(enemy,5.0,Color.CYAN)
	check(enemy.health==95.0 and kinds("impact").size()==2,"Enemy life settlement emits one additional impact")
	if kinds("impact").size()==2:check(not kinds("impact").back().shielded,"Life impact uses unshielded cue")
	var kills:int=arena.kills;var rewards:int=arena.reward_kills;var roots:int=arena.state.normal_journey().normal_root_kills
	arena._begin_progress_transaction();arena._damage_enemy(enemy,200.0,Color.CYAN);arena._end_progress_transaction()
	check(enemy.health<=0.0 and arena.kills==kills+1 and arena.reward_kills==rewards+1,"Real registered root death settles once")
	check(arena.state.normal_journey().normal_root_kills==roots+1,"Canonical journey records the actual root kill")
	check(kinds("death").size()==1 and kinds("impact").size()==3,"Lethal hit emits impact followed by one death cue")
	if not kinds("death").is_empty():check(kinds("death")[0].target_id==enemy.id and arena.visual_cues.cues.back().kind=="death","Death cue preserves target ID and event order")
	before=gameplay();cues=cue_state()
	arena._damage_enemy(enemy,200.0,Color.CYAN);arena._finish_enemy_death(enemy)
	check(gameplay()==before and cue_state()==cues,"Duplicate corpse settlement cannot duplicate cues, rewards, RNG or saves")
	record("root death")
	# Effect ticks may age particles/feedback, but never resources or progression.
	var protected:=var_to_bytes([arena.state.snapshot(),FileAccess.get_file_as_bytes(arena.build_save_path),arena.rng.state,arena.critical_runtime.checkpoint(),arena.health,arena.mana,arena.shield,arena.kills,arena.reward_kills,arena.group_cooldowns.snapshot()])
	var next_id:int=arena.visual_cues.next_id;var dropped:int=arena.visual_cues.dropped
	arena._update_effects(0.21)
	check(kinds("impact").is_empty() and kinds("death").size()==1,"Actual effects tick expires impacts while preserving longer death cue")
	arena._update_effects(0.5)
	check(arena.visual_cues.cues.is_empty() and arena.visual_cues.next_id==next_id and arena.visual_cues.dropped==dropped,"Actual effects tick drains all cues without reusing IDs or changing drops")
	check(var_to_bytes([arena.state.snapshot(),FileAccess.get_file_as_bytes(arena.build_save_path),arena.rng.state,arena.critical_runtime.checkpoint(),arena.health,arena.mana,arena.shield,arena.kills,arena.reward_kills,arena.group_cooldowns.snapshot()])==protected,"Presentation expiry preserves resources, RNG, cooldowns and canonical persistence")
	record("expired")
	await finish()
func finish()->void:
	var report:={"checks":checks,"failures":failed_labels.size(),"failed_labels":failed_labels,"stages":stages,"scope":"Current canonical Main formal map; controlled mana/shield/target resources and capacity saturation; no models or production code changed"}
	FileAccess.open(OS.get_environment("CUES_CANONICAL_OUT"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true)+"\n")
	print("CANONICAL_CUES_INTEGRATION checks=%d failures=%d" % [checks,failed_labels.size()])
	arena.queue_free();await process_frame;quit(1 if not failed_labels.is_empty() else 0)
