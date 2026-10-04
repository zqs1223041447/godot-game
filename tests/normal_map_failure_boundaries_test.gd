extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
class FaultModel extends Model:
	var fail_save:=false
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:return ERR_CANT_CREATE if fail_save else super._write_bytes(path,bytes)
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func observation()->Dictionary:return {"state":arena.state.snapshot(),"disk":FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH),"world":arena.world_context(),"run":arena._map_run.snapshot(),"rng":arena.rng.state,"revision":arena.run_revision}
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	check(arena.save_build(),"Fresh normal file written")
	var model:=FaultModel.new();check(model.load_build(arena.NORMAL_BUILD_PATH),"Fault-injectable model reads real normal envelope")
	var candidate:=model.snapshot();candidate.journey.best_tiers.old_garden=2
	check(model._set_bag_currency_balance(candidate,32).ok,"Controlled high-tier budget fixture fits actual currency cells")
	candidate.revision+=1;check(model._commit(candidate,arena.NORMAL_BUILD_PATH).ok,"High-tier fixture validates full snapshot")
	arena._replace_build(model,arena.NORMAL_BUILD_PATH);arena.restart_run()
	var normals:Array=["enemy_shield_from_health_20","enemy_armour_80"]
	check(arena.craft_normal_map("old_garden",3,normals,["elemental_aegis"],arena.map_draft().revision).ok,"Highest tier accepts two ordinary plus one supported special")
	check(arena.map_draft().cost==8 and arena.map_draft().completion_reward==16,"Maximum risk premium is exactly four")
	check(arena.start_map(arena.map_draft().revision).ok and model.crafting_balance()==24 and arena.wave==8,"Actual top tier uses wave8 and charges8")
	for enemy:Dictionary in arena.enemies:
		check(enemy.wave==8 and enemy.has("encounter_source") and enemy.has("map_defense_source"),"Real root consumes tier and both modifier layers")
		check(is_equal_approx(enemy.armour,float(enemy.encounter_source.before.armour)+80.0),"Real armor modifier consumed")
		check(is_equal_approx(enemy.max_shield,float(enemy.encounter_source.before.max_shield)+float(enemy.encounter_source.before.max_health)*0.2),"Shield uses original health baseline once")
		check(float(enemy.resistances.cold)>=0.2 and float(enemy.resistances.lightning)>=0.2,"Special resistance reaches actual enemy defense")
	var entry_disk:=FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	model.fail_save=true
	finish_map()
	check(arena.world_context().mode=="map_complete" and arena.world_context().completion_save_pending,"Failed completion remains an explicit retryable runtime state")
	check(model.normal_journey().best_tiers.old_garden==2 and model.normal_journey().pending_map_reward.is_empty() and not model.normal_journey().active_run.is_empty(),"Failed completion does not unlock or mint pending cash")
	check(FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==entry_disk,"All failing writes preserve admitted source bytes")
	var before:=observation()
	check(not arena.return_to_town(arena.world_context().revision).ok and observation()==before,"Cannot leave failed settlement by discarding its receipt")
	model.fail_save=false
	check(arena.return_to_town(arena.world_context().revision).ok and not arena.world_context().completion_save_pending,"Retry saves completion then returns to town")
	check(model.normal_journey().best_tiers.old_garden==3 and model.normal_pending_rewards().pending_map_reward.shards==16,"Exact top-tier completion unlocks/queues once")
	var ilvl_found:=false
	for owned:Dictionary in model.snapshot().items.values():
		if owned.kind=="equipment" and not owned.payload.is_empty() and int(owned.payload.item_level)==15:ilvl_found=true
	check(ilvl_found,"Actual drop uses existing2*wave-1 item-level consumer")
	before=observation();model.fail_save=true
	check(not arena.claim_normal_rewards(arena.world_context().revision).ok and observation()==before,"Failed cash delivery preserves pending receipt, UID and balance")
	model.fail_save=false
	check(arena.claim_normal_rewards(arena.world_context().revision).ok and model.crafting_balance()==40,"Successful retry credits exactly16 physical shards")
	# A paid retry with enough money is also one atomic run replacement.
	check(arena.craft_normal_map("old_garden",2,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Another paid run starts")
	var old_id:int=arena._normal_run_id;arena.alive=false;before=observation();model.fail_save=true
	check(not arena.retry_normal_map(arena.world_context().revision).ok and observation()==before and not arena.alive,"Retry write failure leaves prior run and fee untouched")
	model.fail_save=false
	check(arena.retry_normal_map(arena.world_context().revision).ok and arena.alive and arena._normal_run_id==old_id+1 and model.crafting_balance()==32,"Successful retry pays again and gets next run ID")
	before=observation();check(not model.normal_complete_map(old_id,model.revision(),arena.NORMAL_BUILD_PATH).ok and observation()==before,"Previous retry ID cannot settle")
	# Simulate process end without battle-state resume; only saved journey remains.
	var active_id:int=arena._normal_run_id;var sequence:int=model.normal_journey().next_run_id;var items:Dictionary=model.snapshot().items
	arena.queue_free();await process_frame
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	check(arena.world_context().normal_town and arena.state.normal_journey().active_run.is_empty(),"Reload abandons unfinished map into normal town")
	check(arena.state.crafting_balance()==32 and arena.state.normal_journey().next_run_id==sequence and arena.state.snapshot().items==items,"Reload keeps spent fee, monotonic serial and earned inventory")
	check(not arena.state.normal_complete_map(active_id,arena.state.revision(),arena.NORMAL_BUILD_PATH).ok,"Reloaded abandoned ID cannot manufacture completion")
	print("Normal map failure boundaries: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
func finish_map()->void:
	var count:=0;arena._begin_progress_transaction()
	while arena.world_context().mode=="map" and count<100:
		count+=1;arena._update_map_spawning(5.0)
		var targets:Array=arena.enemies.duplicate()
		for enemy:Dictionary in targets:
			if float(enemy.health)>0.0:enemy.spawn=0.0;arena._damage_enemy(enemy,float(enemy.health)+float(enemy.shield)+100.0,Color.WHITE)
		arena._flush_monster_spawns();arena._check_map_complete()
	arena._end_progress_transaction()
	check(count<100,"Real finite high-tier encounter completed including descendants")
