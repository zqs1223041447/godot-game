extends SceneTree
var arena:Node
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func observe()->Dictionary:
	return {"state":arena.state.snapshot(),"world":arena.world_context(),"draft":arena.map_draft(),"rng":arena.rng.state,"run":arena._map_run.snapshot(),"ids":[arena.monster_runtime.next_id,arena.projectile_runtime.next_projectile_id],"disk":FileAccess.get_file_as_bytes(arena.build_save_path)}
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	while arena.hud.is_blocking():arena.hud.close_panel()
	var world:Dictionary=arena.world_context()
	check(world.normal_town and not world.test_mode and arena.enemies.is_empty(),"Default starts safe formal town with original normal profile")
	check(arena.state.snapshot().version==26 and arena.state.normal_journey().normal_root_kills==0,"Old progress begins only new cumulative milestone counter")
	var before:=observe()
	check(not arena.town_buy("currency:calibration_shard",arena.state.revision()).ok and observe()==before,"Visible test merchant cannot supply normal inventory")
	check(arena.map_options().tiers.size()==6,"Both maps show three actual challenge tiers")
	var locked:=0
	for row:Dictionary in arena.map_options().tiers:
		if not row.unlocked:locked+=1
	check(locked==4,"Initially both tierI open, higher four locked")
	check(not arena.craft_normal_map("old_garden",2,[],[],arena.map_draft().revision).ok and observe()==before,"Locked draft rejects before RNG or state mutation")
	check(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok,"Real normal draft prepared")
	var draft:Dictionary=arena.map_draft();check(draft.cost==0 and draft.completion_reward==4 and draft.can_start,"UI draft values come from real prototype budget")
	check(arena.start_map(draft.revision).ok and arena.world_context().map_tier==1 and arena.wave==1,"Actual first map begins with tier wave1")
	check(arena.state.normal_journey().active_run.run_id==1 and arena.enemies.size()==3,"Admission persisted before initial real roots")
	before=observe();check(not arena.start_map(draft.revision).ok and observe()==before,"Old start handle cannot issue duplicate run")
	check(not arena.start_encounter(["vitality"],arena.run_revision),"F7 cannot replace a frozen formal challenge")
	finish_map()
	world=arena.world_context()
	check(world.mode=="map_complete" and world.normal_root_kills==25,"24 actual ordinary roots plus boss count once")
	check(world.pending_map_reward.shards==4 and arena.state.normal_journey().active_run.is_empty(),"Actual completion durably records one pending award")
	check(arena.state.normal_journey().best_tiers.old_garden==1 and arena.state.normal_journey().best_tiers.broken_ruins==0,"Only completed map unlocks next tier")
	check(arena.return_to_town(world.revision).ok,"Completed map returns to formal town")
	check(not arena.map_draft().can_start and arena.map_draft().reason.contains("领取"),"Unclaimed map cash blocks next formal run clearly")
	var claim_revision:int=arena.world_context().revision
	var claimed:Dictionary=arena.claim_normal_rewards(claim_revision)
	check(claimed.ok and claimed.claimed_shards==4 and arena.state.crafting_balance()==4,"UI claim credits four physical currency units")
	before=observe();check(not arena.claim_normal_rewards(claim_revision).ok and observe()==before,"Stale UI claim cannot duplicate payout")
	check(arena.craft_normal_map("old_garden",2,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Unlocked tierII starts")
	check(arena.wave==4 and arena.state.crafting_balance()==0 and arena.world_context().retry_cost==4,"TierII consumes real4 once and advertises actual retry fee")
	arena.invulnerable=0.0;arena.hit_player_components({"chaos":1000000.0})
	check(not arena.alive,"Actual death creates retry decision")
	before=observe();arena.hud._restart()
	check(not arena.alive and arena.hud.is_blocking() and observe()==before,"Insufficient retry funds leave death menu and authoritative state intact")
	check(arena.return_to_town(arena.world_context().revision).ok and arena.state.normal_journey().active_run.is_empty() and arena.state.crafting_balance()==0,"Abandoned failed run returns without refund or reward")
	# Repeat free map. Cumulative root milestones continue across maps and deaths.
	check(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Second free map remains reachable at zero currency")
	finish_map()
	check(arena.world_context().normal_root_kills==50 and arena.state.normal_journey().claimed_gems==1,"Root30 gem is actually delivered across two short maps")
	check(arena.return_to_town(arena.world_context().revision).ok and arena.claim_normal_rewards(arena.world_context().revision).ok,"Second actual completion closes normally")
	check(arena.craft_normal_map("broken_ruins",1,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Second terrain first tier admits without unlocking from other map")
	check(arena.wave==2 and arena.world_geometry().walls.size()==2,"Tier changes budget while retaining real ruin walls")
	finish_map()
	check(arena.world_context().normal_root_kills==87 and arena.state.normal_journey().claimed_gems==2 and arena.state.normal_journey().claimed_flasks==1,"Root60 gives second gem and first new flask across finite maps")
	check(arena.return_to_town(arena.world_context().revision).ok and arena.claim_normal_rewards(arena.world_context().revision).ok,"Ruins payout commits once")
	# A real bound footer signal exercises the observed native return concern.
	var normal_bytes:=var_to_bytes(arena.state.snapshot());var normal_disk:=FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	check(arena.enter_town_test(arena.world_context().revision).ok and arena.world_context().test_mode,"Explicit entry opens isolated test profile")
	check(arena.state.normal_journey()==arena.state.Journey.empty(),"First test copy does not borrow normal progress or active receipts")
	check(arena.town_buy("currency:calibration_shard",arena.state.revision()).ok,"Test supplier remains genuinely usable")
	check(arena.craft_map("old_garden",[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok and arena.wave==4,"Test maps preserve original fixed wave4 budget")
	finish_map()
	check(arena.state.normal_journey()==arena.state.Journey.empty() and arena.world_context().pending_map_reward.is_empty(),"Test combat cannot earn normal unlock/cash/milestones")
	check(arena.return_to_town(arena.world_context().revision).ok,"Test map returns before switching profiles")
	await process_frame
	arena.hud._town_view._leave.pressed.emit()
	await process_frame
	world=arena.world_context()
	check(world.normal_town and not world.test_mode,"Actual footer signal returns from test to formal town")
	var restored:Dictionary=arena.state.snapshot();var original:Dictionary=bytes_to_var(normal_bytes)
	if var_to_bytes(restored)!=normal_bytes:
		print("Normal reload dictionary values equal: ",restored==original,"; normal disk bytes equal: ",FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==normal_disk)
		for key:Variant in original:
			if original[key]!=restored.get(key):print("Changed normal field: ",key)
	check(restored==original and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==normal_disk,"Test stock/XP/loot never contaminates normal values or original disk bytes")
	check(arena.leave_normal_town(world.revision).ok and arena.world_context().mode=="normal","Old unlimited arena remains explicit practice entry")
	check(arena.enter_normal_town(arena.world_context().revision).ok and arena.world_context().normal_town,"Practice returns to formal town with same profile")
	print("Normal map gameplay: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)

func finish_map()->void:
	var loops:=0
	arena._begin_progress_transaction()
	while arena.world_context().mode=="map" and loops<100:
		loops+=1
		arena._update_map_spawning(5.0)
		var targets:Array=arena.enemies.duplicate()
		for target:Dictionary in targets:
			if float(target.health)>0.0:
				target.spawn=0.0
				arena._damage_enemy(target,float(target.health)+float(target.shield)+100.0,Color.WHITE)
		arena._flush_monster_spawns()
		arena._check_map_complete()
	arena._end_progress_transaction()
	check(loops<100 and arena.world_context().mode=="map_complete","Finite actual admission/death/descendant queue reaches completion")
