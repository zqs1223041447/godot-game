extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
class FaultModel extends Model:
	var fail_save:=false
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:return ERR_CANT_CREATE if fail_save else super._write_bytes(path,bytes)
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func observed()->Dictionary:return {"build":arena.state.snapshot(),"world":arena.world_context(),"camp":arena._map_camps.checkpoint(),"runtime":arena.EncounterAdmission._snapshot(arena.monster_runtime),"rng":arena.rng.state,"enemies":arena.enemies.duplicate(true),"disk":FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)}
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	check(arena.save_build(),"Real initial save")
	var model:=FaultModel.new();check(model.load_build(arena.NORMAL_BUILD_PATH),"Fault-injectable full model loads")
	var candidate:=model.snapshot();candidate.journey.best_tiers.broken_ruins=1
	check(model._set_bag_currency_balance(candidate,12).ok,"Exact paid-run budget fixture")
	candidate.revision+=1;check(model._commit(candidate,arena.NORMAL_BUILD_PATH).ok,"Fixture full candidate commits")
	arena._replace_build(model,arena.NORMAL_BUILD_PATH);arena.restart_run()
	check(arena.craft_normal_map("broken_ruins",2,["enemy_shield_from_health_20","enemy_armour_80"],["storm_patrol"],arena.map_draft().revision).ok,"TierII full layered map draft")
	var before:=observed();model.fail_save=true
	check(not arena.start_map(arena.map_draft().revision).ok and observed()==before,"Preflight does not spend or activate after failed admission save")
	model.fail_save=false;check(arena.start_map(arena.map_draft().revision).ok and model.crafting_balance()==8,"Success charges original four once")
	for camp:Dictionary in arena.world_geometry().landmarks.camps:
		arena.player_pos=camp.trigger_center;arena._update_map_spawning(0.0)
	check(arena.enemies.size()==36,"All36tierII roots coexist")
	for enemy:Dictionary in arena.enemies:check(enemy.wave==5 and enemy.has("encounter_source") and enemy.armour>=80.0 and enemy.max_shield>=enemy.encounter_source.before.max_health*0.2,"Actual modifiers and tier remain applied once")
	var output:=OS.get_environment("V043_DENSITY_FIXTURE")
	if not output.is_empty():
		var data:Dictionary={"build":model.snapshot(),"profile":arena._map_run.profile,"enemies":arena.enemies,"runtime":arena.EncounterAdmission._snapshot(arena.monster_runtime),"admitted":arena._map_run.admitted,"camps":arena._map_camps.checkpoint().camps,"position":arena.player_pos}
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_buffer(var_to_bytes(data));file.close()
	var old_id:int=arena._normal_run_id;var old_next:int=arena.monster_runtime.next_id
	arena.invulnerable=0.0;arena.hit_player_components({"chaos":1000000.0});check(not arena.alive,"Real death")
	before=observed();model.fail_save=true
	check(not arena.retry_normal_map(arena.world_context().revision).ok and observed()==before,"Failed paid retry keeps dead/camp/UID/RNG/file state")
	model.fail_save=false;check(arena.retry_normal_map(arena.world_context().revision).ok and model.crafting_balance()==4,"Retry charges four again")
	check(arena._normal_run_id==old_id+1 and arena.alive and arena.enemies.is_empty() and arena.monster_runtime.next_id==old_next,"New run keeps monotonic runtimeIDs and no automatic roots")
	for camp:Dictionary in arena.world_context().camp_states:check(camp.state=="dormant" and camp.roots_spawned==0,"Retry clears previous group admission")
	arena.player_pos=arena.world_geometry().landmarks.camps[1].trigger_center;arena._update_map_spawning(0.0)
	check(arena.enemies.size()==12 and arena.enemies[0].id>old_next,"Same camp can activate exactly once in paid new run")
	check(arena.return_to_town(arena.world_context().revision).ok and model.crafting_balance()==4 and arena._map_camps.checkpoint().is_empty(),"Return abandons without refund and clears frozen roster")
	print("Map camp retry: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
