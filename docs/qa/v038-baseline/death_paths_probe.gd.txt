extends SceneTree
class TimedState extends "res://scripts/canonical_game_state.gd":
	var times:Dictionary={}
	var counts:Dictionary={}
	func mark(k:String,t:int)->void:times[k]=int(times.get(k,0))+Time.get_ticks_usec()-t;counts[k]=int(counts.get(k,0))+1
	func add_xp(n:int)->bool:
		var t:=Time.get_ticks_usec();var v:=super.add_xp(n);mark("xp_including_changed",t);return v
	func award_equipment(rng:RandomNumberGenerator,level:int,rarity:String="",pool:String="current")->String:
		var t:=Time.get_ticks_usec();var v:=super.award_equipment(rng,level,rarity,pool);mark("equipment_including_changed",t);return v
	func award_jewel(rng:RandomNumberGenerator)->String:
		var t:=Time.get_ticks_usec();var v:=super.award_jewel(rng);mark("jewel_including_changed",t);return v
	func save_build(path:String="user://build_save.json")->Error:
		var t:=Time.get_ticks_usec();var v:=super.save_build(path);mark("save_full_validation_serialize_write",t);return v
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:
		var t:=Time.get_ticks_usec();var v:=super._write_bytes(path,bytes);mark("atomic_write_including_close",t);return v
	func _ensure_cache()->void:
		var t:=Time.get_ticks_usec();super._ensure_cache();mark("cache_checks_inclusive",t)
class TimedArena extends "res://scripts/main.gd":
	var times:Dictionary={}
	var counts:Dictionary={}
	func mark(k:String,t:int)->void:times[k]=int(times.get(k,0))+Time.get_ticks_usec()-t;counts[k]=int(counts.get(k,0))+1
	func _on_build_changed()->void:
		var t:=Time.get_ticks_usec();super._on_build_changed();mark("changed_callback",t)
	func _flush_progress(force_save:bool=false)->bool:
		var t:=Time.get_ticks_usec();var v:=super._flush_progress(force_save);mark("flush_HUD_plus_save",t);return v
	func _sync_flasks(reset_run:bool=false)->void:
		var t:=Time.get_ticks_usec();super._sync_flasks(reset_run);mark("sync_flasks",t)
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v038-death"):quit(78);return
	var rows:Array=[]
	for batch:int in [1,8,20]:
		for repetition:int in range(3):
			var arena:=TimedArena.new();var state:=TimedState.new();arena.state=state;arena.build_save_path="user://batch-%d-%d.json"%[batch,repetition]
			root.add_child(arena);arena.set_process(false);arena.hud.set_process(false);arena.rng.seed=380037
			arena.enemies.clear();arena.monster_runtime.reset();arena.telegraphs.reset();arena.auto_fire=false;arena.spawn_timer=100000.0
			for i:int in range(batch):
				var enemy:Dictionary=arena.monster_runtime.create_root("crawler",1,arena.player_pos+Vector2(80+i*3,0),"ordinary","normal",[],true);enemy.spawn=0.0;arena.enemies.append(enemy)
			state.times.clear();state.counts.clear();arena.times.clear();arena.counts.clear();var items_before:int=state.snapshot().items.size();var builds_before:=state.cache_diagnostics()
			var total:=Time.get_ticks_usec();arena._begin_progress_transaction();var simulation:=Time.get_ticks_usec()
			for enemy:Dictionary in arena.enemies:arena._damage_enemy(enemy,float(enemy.health)+1.0,Color.WHITE)
			var simulation_us:=Time.get_ticks_usec()-simulation;var flush:=Time.get_ticks_usec();arena._end_progress_transaction();var flush_us:=Time.get_ticks_usec()-flush
			rows.append({"batch":batch,"repetition":repetition,"total_us":Time.get_ticks_usec()-total,"death_reward_before_flush_us":simulation_us,"flush_us":flush_us,"state_nested_us":state.times.duplicate(),"state_calls":state.counts.duplicate(),"arena_nested_us":arena.times.duplicate(),"arena_calls":arena.counts.duplicate(),"reward_kills":arena.reward_kills,"items_before":items_before,"items_after":state.snapshot().items.size(),"cache_before":builds_before,"cache_after":state.cache_diagnostics(),"saved":state.successful_saves})
			arena.queue_free();await process_frame
	var result={"source":"f074c2614540f0842964ced961b3430871adce57","production_unchanged":true,"scope":"Three isolated repeats each1/8/20 legal root deaths; real reward and persisted flush. Labels inclusive/nested, not summable. No corpse-scheduling or RNG changes.","samples":rows}
	FileAccess.open("/workspace/scratch/a51485f153de/v038-diagnostics/death-paths.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true));print(JSON.stringify(result));quit()
