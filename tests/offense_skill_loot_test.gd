extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Gems=preload("res://scripts/items/gem_catalog.gd")
var checks:=0
var failures:=0
var arena:Node
func _initialize()->void:call_deferred("run")
func run()->void:
	var isolated:=OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-") or not OS.get_user_data_dir().begins_with(isolated+"/"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false;arena.demo_mode=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	var ids:Array=Gems.definitions().keys();ids.sort()
	check(ids.size()==26,"Natural gem pool contains ten active plus sixteen support definitions")
	for skill:String in ["cleave","shade_bolt"]:
		var seed_value:=-1
		# Death's existing hit feedback consumes nine draws before its thirtieth
		# root-kill gem roll. Search deterministic seeds, then use the real route.
		for candidate:int in 10000:
			var trial:=RandomNumberGenerator.new();trial.seed=candidate
			for unused:int in 9:trial.randf()
			if ids[trial.randi_range(0,ids.size()-1)]=="skill:"+skill:seed_value=candidate;break
		check(seed_value>=0,"A natural positive-weight roll can select the new skill")
		arena.rng.seed=seed_value;arena.reward_kills=29;arena.enemies.clear()
		var enemy:Dictionary=arena.monster_runtime.create_root("crawler",1,arena.player_pos+Vector2(45,0))
		enemy.spawn=0.0;arena.enemies.append(enemy)
		var before:Dictionary=arena.state.snapshot();var previous_saves:int=arena.state.successful_saves
		arena._begin_progress_transaction();arena._damage_enemy(enemy,float(enemy.health)+1.0,Color.WHITE);arena._end_progress_transaction()
		var after:Dictionary=arena.state.snapshot();var added:Array=[]
		for uid:String in after.items:
			if not before.items.has(uid):added.append(after.items[uid])
		check(arena.reward_kills==30 and added.size()==1,"One real eligible root death creates exactly the expected gem reward")
		check(added.size()==1 and added[0].definition_id=="skill:"+skill,"The new skill is admitted by actual main death/reward logic")
		check(arena.state.successful_saves==previous_saves+1,"The complete XP and gem transaction saves once")
		var reopened:=Model.new();check(reopened.load_build() and reopened.snapshot()==after,"Natural new UID and updated progress survive reload")
		var replay_rng:int=arena.rng.state
		arena._damage_enemy(enemy,1.0,Color.WHITE)
		check(arena.state.snapshot()==after and arena.rng.state==replay_rng,"Already-dead root cannot grant a second new gem")
	var full:=Model.new();var accepted:=0
	while accepted<300:
		if full.award_gem("skill:cleave").is_empty():break
		accepted+=1
	check(accepted>0 and accepted<300,"Finite real 240-cell placement reaches a full bag")
	var saved:=var_to_bytes(full.snapshot());var rng:=RandomNumberGenerator.new();rng.seed=244024;var prior_rng:=rng.state
	check(full.award_random_gem(rng).is_empty() and rng.state==prior_rng and var_to_bytes(full.snapshot())==saved,"Full bag rejects the new pool without consuming RNG, serial or prior items")
	print("Offense skill natural rewards: %d checks, %d failures"%[checks,failures])
	arena.queue_free();await process_frame;quit(1 if failures else 0)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
