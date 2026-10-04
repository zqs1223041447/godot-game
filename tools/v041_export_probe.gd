extends SceneTree
var arena:Node
var ok:=true
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	if not value:ok=false;push_error(label)
func run()->void:
	var output:=OS.get_environment("V041_PACK_QA");var expected_font:=OS.get_environment("V041_PACK_FONT_SHA256")
	if output.is_empty() or expected_font.length()!=64 or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	var model:RefCounted=arena.state;var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(font.data);var font_hash:=h.finish().hex_encode()
	var version:=str(ProjectSettings.get_setting("application/config/version"));var directory:=str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	check(version=="0.41.0" and directory=="godot-game-preview-v021" and model.snapshot().version==26,"Version/schema/path actual exported project")
	check(model.bag_layout()=={"pages":2,"columns":12,"rows":10} and font_hash==expected_font,"Actual bag/font matches frozen source")
	for index:int in "正式城镇竞技练习里程碑领取但张征".length():check(font.has_char("正式城镇竞技练习里程碑领取但张征".unicode_at(index)),"New runtime word coverage")
	check(arena.world_context().normal_town and arena.enemies.is_empty(),"Default formal town is safe")
	check(arena.map_options().tiers.size()==6,"Actual six challenge tiers")
	# A legal controlled unlock/currency fixture exercises the paid final package path.
	var candidate:Dictionary=model.snapshot();candidate.journey.best_tiers.old_garden=1
	check(model._set_bag_currency_balance(candidate,4).ok,"Real currency fixture fits")
	candidate.revision+=1;check(model._commit(candidate,arena.NORMAL_BUILD_PATH).ok,"Fixture passes full persistence validator")
	check(arena.craft_normal_map("old_garden",2,[],[],arena.map_draft().revision).ok,"Actual paid draft compiled")
	check(arena.start_map(arena.map_draft().revision).ok and model.crafting_balance()==0 and arena.wave==4,"Paid admission debits four before battle")
	var loops:=0;arena._begin_progress_transaction()
	while arena.world_context().mode=="map" and loops<100:
		loops+=1;arena._update_map_spawning(5.0)
		var targets:Array=arena.enemies.duplicate()
		for target:Dictionary in targets:
			if float(target.health)>0.0:target.spawn=0.0;arena._damage_enemy(target,float(target.health)+float(target.shield)+100.0,Color.WHITE)
		arena._flush_monster_spawns();arena._check_map_complete()
	arena._end_progress_transaction()
	var completed:Dictionary=arena.world_context()
	check(loops<100 and completed.mode=="map_complete" and completed.pending_map_reward.shards==8,"Actual roots boss and descendants finish once")
	check(model.normal_journey().active_run.is_empty() and completed.fee_paid==4 and completed.retry_cost==4,"Completed paid map retains fee display after active receipt clears")
	check(arena.return_to_town(completed.revision).ok,"Real return route")
	var claim:Dictionary=arena.claim_normal_rewards(arena.world_context().revision)
	check(claim.ok and claim.claimed_shards==8 and model.crafting_balance()==8,"Real deferred reward credits eight currency")
	check(model.normal_journey().best_tiers.old_garden==2 and model.normal_journey().normal_root_kills==25,"Actual unlock and cumulative roots retained")
	var result:Dictionary={"ok":ok,"version":version,"schema":model.snapshot().version,"save_directory":directory,"user_dir":OS.get_user_data_dir(),"bag_layout":model.bag_layout(),"font_sha256":font_hash,"font_characters":font.get_supported_chars().length(),"completed_map":completed,"claim":claim,"journey":model.normal_journey(),"currency":model.crafting_balance(),"fixture":"Legal isolated tierI completion record and four real shards; actual tierII admission/combat/completion/claim"}
	var file:=FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("Packed v41 normal map probe: ","PASS" if ok else "FAIL");arena.queue_free();await process_frame;quit(0 if ok else 1)
