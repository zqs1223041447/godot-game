extends SceneTree
class MeasuredIndex extends "res://scripts/combat/spatial_target_index.gd":
	var usec:int=0
	var calls:int=0
	func rebuild(targets:Array[Dictionary])->void:
		var began:int=Time.get_ticks_usec()
		super.rebuild(targets)
		usec=Time.get_ticks_usec()-began;calls+=1
class MeasuredMain extends "res://scripts/main.gd":
	var projectile_usec:int=0
	func _update_projectiles(delta:float)->void:
		var began:int=Time.get_ticks_usec()
		super._update_projectiles(delta)
		projectile_usec=Time.get_ticks_usec()-began
var arena:Node2D
var report:Dictionary={"scope":"Actual Main entrance, real pregenerated sleeping map roster; 60 fixed ticks per map, timer observers only; not GPU/FPS", "cases":[]}
func _initialize()->void:call_deferred("run")
func accepted(result:Dictionary)->bool:
	if not result.get("ok",false):printerr(result);quit(1);return false
	return true
func run()->void:
	arena=MeasuredMain.new();root.add_child(arena);arena.set_process(false);arena.hud.set_process(false)
	if not accepted(arena.enter_town_test(arena.world_context().revision)):return
	for map_id:String in ["old_garden","ginkgo_arcade"]:
		if arena._world_mode!="town":
			if not accepted(arena.return_to_town(arena.world_context().revision)):return
		if not accepted(arena.craft_map(map_id,[],[],arena.map_draft().revision)):return
		if not accepted(arena.start_map(arena.map_draft().revision)):return
		arena.set_process(false);arena.hud.set_process(false)
		for unused:int in range(4):arena.hud.close_panel()
		arena.auto_fire=true;arena.rng.seed=89001
		var index:=MeasuredIndex.new();arena.projectile_runtime._target_index=index
		var rows:Array=[];var start_rng:int=arena.rng.state
		var roots:PackedByteArray=var_to_bytes(arena.map_spawn_records())
		for n:int in range(60):
			var before_calls:int=index.calls
			var began:int=Time.get_ticks_usec();arena.tick(1.0/60.0);var total:int=Time.get_ticks_usec()-began
			rows.append({"tick_us":total,"projectile_us":arena.projectile_usec,"index_us":index.usec,"index_rebuilds":index.calls-before_calls,"targets":index._targets.size(),"id_map_size":arena._projectile_targets.size(),"shots":arena.projectiles.size(),"awake":arena._exploration_awake_count()})
		report.cases.append({"map_id":map_id,"actors":arena.enemies.size(),"samples":rows,"no_reward_or_spell_rng":arena.rng.state==start_rng,"same_initial_spawn_records":var_to_bytes(arena.map_spawn_records())==roots,"spawn_queue_size":arena.monster_runtime.queue.size(),"trace_count":arena.combat_trace.size()})
	FileAccess.open(OS.get_environment("PROBE_OUT"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print("EMPTY_PROJECTILE_PROBE_DONE")
	arena.queue_free();await process_frame;quit(0)
