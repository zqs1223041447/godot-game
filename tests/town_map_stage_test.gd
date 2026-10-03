extends SceneTree
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false)
	check(arena.state.snapshot().version==19,"New build initializes through frozen migration stages")
	check(arena.world_context().mode=="normal","Normal game remains default")
	var old=arena.state;var normal:Dictionary=old.snapshot()
	var entered:Dictionary=arena.enter_town_test(arena.world_context().revision)
	check(entered.ok and arena.world_context().mode=="town" and arena.enemies.is_empty(),"Explicit test entry creates safe town")
	var normal_bytes:=FileAccess.get_file_as_bytes("user://build_save.json")
	check(arena.state!=old and arena.state.snapshot()==normal,"First test clone preserves all source items and data")
	check(arena.town_services().size()==6,"All six real services exposed")
	for id:String in ["skill_merchant","equipment_merchant","jewel_merchant"]:
		var stock:Array=arena.town_stock(id);check(not stock.is_empty(),"Dynamic stock "+id)
		for row:Dictionary in stock:check(not row.preview.is_empty() and row.available,"Every stock entry has a real implemented definition")
	var result:Dictionary=arena.town_buy("base:ashwood_bow",arena.state.revision())
	check(result.ok and arena.state.item(result.uid).payload.base_id=="ashwood_bow","Real base transaction enters bag")
	check(arena.town_buy("currency:calibration_shard",arena.state.revision()).ok and arena.state.crafting_balance()==100,"Test supply gives actual currency items")
	check(FileAccess.get_file_as_bytes("user://build_save.json")==normal_bytes and old.snapshot()==normal,"Supply cannot pollute normal file or memory")
	var invalid:Dictionary=arena.craft_map("old_garden",[],["storm_patrol"],arena.map_draft().revision)
	check(not invalid.ok,"Unavailable special modifier rejects")
	check(arena.craft_map("old_garden",["enemy_max_health_120"],["frost_patrol"],arena.map_draft().revision).ok,"Valid normal+special draft compiled")
	check(arena.start_map(arena.map_draft().revision).ok and arena.world_context().mode=="map","Frozen draft starts real map")
	while arena._map_run.can_admit():
		if arena._spawn_enemy().is_empty():check(false,"Map admission succeeds");break
	check(arena._map_run.admitted.size()==24 and arena.enemies.size()==24,"Finite ordinary admission budget")
	for enemy:Dictionary in arena.enemies.duplicate():
		check(enemy.has("encounter_source"),"Existing ordinary modifier applied at canonical admission")
		enemy.spawn=0.0;arena._begin_progress_transaction();arena._damage_enemy(enemy,enemy.health+enemy.shield+1.0,Color.WHITE);arena._end_progress_transaction()
	check(arena.world_context().ordinary_kills==24 and arena._map_run.ready_for_boss(),"Actual death authority advances map target once")
	arena.enemies=arena.enemies.filter(func(e:Dictionary)->bool:return float(e.health)>0.0)
	arena._update_map_spawning(0.1)
	check(arena._map_run.boss_id>0,"One real map boss created")
	var guard:=0
	while not arena.enemies.is_empty() or not arena.monster_runtime.queue.is_empty():
		guard+=1
		if guard>20:check(false,"Finite descendant work terminates");break
		for enemy:Dictionary in arena.enemies.duplicate():
			enemy.spawn=0.0;arena._begin_progress_transaction();arena._damage_enemy(enemy,enemy.health+enemy.shield+1.0,Color.WHITE);arena._end_progress_transaction()
		arena.enemies=arena.enemies.filter(func(e:Dictionary)->bool:return float(e.health)>0.0)
		arena._flush_monster_spawns()
	arena._check_map_complete()
	check(arena.world_context().mode=="map_complete" and arena.reward_kills==25,"Map ends after actual boss+descendants, roots reward exactly once")
	check(arena.return_to_town(arena.world_context().revision).ok and arena.enemies.is_empty(),"Return stores rewards then clears world")
	var test_snapshot:Dictionary=arena.state.snapshot()
	check(arena.leave_town_test(arena.world_context().revision).ok and arena.state.snapshot()==normal,"Leave restores original normal build")
	check(arena.enter_town_test(arena.world_context().revision).ok and arena.state.snapshot()==test_snapshot,"Re-entry resumes existing test save without overwriting")
	print("Town map stage: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
