extends SceneTree
const Maps = preload("res://scripts/world/map_compiler.gd")
class ObservedArena extends "res://scripts/main.gd":
	var normal_prepares := 0
	var test_prepares := 0
	func craft_normal_map(map_id: Variant,tier: Variant,normals: Variant,specials: Variant,revision: Variant) -> Dictionary:
		normal_prepares+=1;return super.craft_normal_map(map_id,tier,normals,specials,revision)
	func craft_map(map_id: Variant,normals: Variant,specials: Variant,revision: Variant) -> Dictionary:
		test_prepares+=1;return super.craft_map(map_id,normals,specials,revision)
var arena: ObservedArena
var panel: Control
var checks := 0
var failures: Array[String] = []
var states: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> bool:
	checks+=1
	if not ok: failures.append(label);push_error(label)
	return ok
func settle() -> void:
	await process_frame;await process_frame
func authority() -> PackedByteArray:
	return var_to_bytes([arena.state.snapshot(),arena.map_draft(),arena.world_context(),arena.rng.state,
		FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH),FileAccess.get_file_as_bytes(arena.TOWN_TEST_BUILD_PATH),
		arena.state.successful_saves,arena.state.save_attempts,arena.progress_save_success_count,arena.progress_save_attempt_count,
		arena._map_run.snapshot(),arena.run_revision])
func selection() -> Array:
	var normals: Array[String] = []
	var specials: Array[String] = []
	for id: String in panel._normal:
		if panel._normal[id].button_pressed:normals.append(id)
	for id: String in panel._special:
		if panel._special[id].button_pressed:specials.append(id)
	return [panel._map_select.get_selected_metadata(),int(panel._tier_select.get_selected_metadata()) if panel._tier_select.item_count>0 else 1,normals,specials]
func choose(option: OptionButton,value: Variant) -> bool:
	for index: int in range(option.item_count):
		if option.get_item_metadata(index)==value and not option.is_item_disabled(index):
			option.select(index);option.item_selected.emit(index);return true
	return check(false,"Missing available selection "+str(value))
func valid_preview(label: String) -> void:
	var controls := selection()
	var result: Dictionary = arena.map_selection_preview(controls[0],controls[1],controls[2],controls[3])
	check(result.ok and panel._map_preview.visible and panel._map_preview.text.begins_with("所选配置 · 尚未准备"),label+" is explicitly unprepared")
	if not result.ok:return
	if result.test_mode:
		check(panel._map_preview.text.contains("独立测试地图 · 免费；无正式地图结算") and not panel._map_preview.text.contains("入场"),label+" uses only free test contract")
	else:
		var compiled := Maps.compile_normal(controls[0],controls[1],controls[2],controls[3])
		check(result.cost==compiled.profile.fee and result.completion_reward==compiled.profile.completion_reward
			and panel._map_preview.text.contains("入场 %d 校准碎片 · 全清结算 %d" % [result.cost,result.completion_reward]),label+" equals compiler fee and reward")
		check(panel._map_preview.text.contains("背包余额 %d" % arena.state.crafting_balance())
			and panel._map_preview.text.contains("校准碎片不足")== (result.balance<result.cost),label+" reflects real balance/affordability")
	check(panel._map_launch.disabled and panel._map_selection_dirty,label+" never enables the old prepared draft")
	states.append({"case":label,"text":panel._map_preview.text,"draft_revision":arena.map_draft().revision})
func invalid_preview(label: String) -> void:
	var controls := selection()
	var result: Dictionary = arena.map_selection_preview(controls[0],controls[1],controls[2],controls[3])
	check(not result.ok and panel._map_preview.text=="所选配置 · 尚未准备\n"+str(result.reason),label+" shows exact authority reason")
	check(not panel._map_preview.text.contains("入场") and not panel._map_preview.text.contains("全清结算") and not panel._map_summary.text.contains("入场"),label+" clears current and old fees/rewards")
func recycle(inventory: Control,uid: String) -> void:
	inventory._select_item(uid)
	check(not inventory._craft_controls._salvage_button.disabled,"Existing selected-gem recycle enabled")
	inventory._craft_controls._salvage_button.pressed.emit()
	check(inventory._craft_dialog.visible,"Existing recycle confirmation opens")
	inventory._craft_dialog.confirmed.emit()
	inventory._craft_dialog.hide()
	await settle()
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-map-cost-preview.") or FileAccess.file_exists("user://build_save.json"):
		quit(78);return
	arena=ObservedArena.new();root.add_child(arena);arena.set_process(false);arena.set_physics_process(false);arena.hud.set_process(false);arena.auto_fire=false
	await settle()
	check(arena.save_build(),"Fresh canonical profile saved")
	# Trusted finite canonical UI fixture, not a combat/economic validation.
	# Existing modifier bonuses yield15; existing8/4 purchases leave3.
	for pair: Array in [["old_garden",1],["old_garden",2],["broken_ruins",1]]:
		var profile: Dictionary = Maps.compile_normal(pair[0],pair[1],["enemy_damage_115"],[]).profile
		var began: Dictionary = arena.state.normal_start_map(profile,arena.state.revision(),arena.build_save_path)
		check(began.ok and arena.state.normal_complete_map(began.run_id,arena.state.revision(),arena.build_save_path).ok
			and arena.state.normal_claim_rewards(arena.state.revision(),arena.build_save_path).ok,"Trusted fixture unlock/claim "+str(pair))
	var bought: Array[String] = []
	for id: String in ["skill:bolt","support:efficiency"]:
		var prior: Array = arena.state.snapshot().items.keys()
		var quote: Dictionary = arena.normal_gem_trade_quote("buy",id,arena.state.revision())
		check(quote.ok and arena.execute_normal_gem_trade(quote.handle,id).ok,"Existing paid gem fixture: "+id)
		for uid: String in arena.state.snapshot().items:
			if uid not in prior:bought.append(uid)
	check(bought.size()==2 and arena.state.crafting_balance()==3,"Fixture has two real bag gems and three physical shards")
	panel=arena.hud._town_view;panel.open_service("map_device");await settle()
	check(not panel._map_preview.visible and panel._map_preview.text.is_empty(),"Clean authoritative draft has no unprepared preview")
	var original: Dictionary = arena.map_draft()
	var old_launch: Button = panel._map_launch
	var before := authority()
	for args: Array in [["broken_ruins",3,[],[]],["missing",1,[],[]],["old_garden",1.0,[],[]],["old_garden",1,"invalid",[]],["old_garden",1,[],["missing"]]]:
		var rejected: Dictionary = arena.map_selection_preview(args[0],args[1],args[2],args[3])
		check(not rejected.ok and not rejected.reason.is_empty() and not rejected.has("cost") and not rejected.has("completion_reward"),"Locked/malformed preview exposes reason without any fee or reward")
	check(authority()==before,"Rejected readonly API inputs preserve complete authority")
	choose(panel._tier_select,3);panel._normal.enemy_damage_115.button_pressed=true;panel._special.storm_patrol.button_pressed=true;await settle()
	valid_preview("tierIII with two existing modifier bonuses")
	check(authority()==before and arena.normal_prepares==0 and arena.test_prepares==0,"Editing valid controls performs no prepare/save/RNG/balance/draft change")
	choose(panel._tier_select,2);await settle();invalid_preview("special wave gate")
	choose(panel._tier_select,3)
	panel._special.elemental_aegis.button_pressed=true;await settle();invalid_preview("too many special modifiers")
	panel._special.elemental_aegis.button_pressed=false
	var added: Array[String] = []
	for id: String in panel._normal:
		if id!="enemy_damage_115" and added.size()<2:added.append(id);panel._normal[id].button_pressed=true
	await settle();invalid_preview("too many normal modifiers")
	for id: String in added:panel._normal[id].button_pressed=false
	choose(panel._map_select,"old_garden");panel._normal.enemy_damage_115.button_pressed=false;panel._special.storm_patrol.button_pressed=false;await settle()
	valid_preview("returned original prepared configuration")
	old_launch.pressed.emit();await settle()
	check(authority()==before and arena.map_draft()==original and panel._map_launch.disabled,"Returning controls to old values cannot revive old launch revision")
	choose(panel._map_select,"broken_ruins");choose(panel._tier_select,2)
	panel._normal.enemy_damage_115.button_pressed=true;panel._special.storm_patrol.button_pressed=true;await settle()
	valid_preview("costfour at balancethree")
	check(authority()==before,"Valid and rejected control previews preserve complete authority")
	arena.hud.open_panel("inventory");await settle()
	var inventory: Control = arena.hud._inventory_panel
	var controls := selection()
	await recycle(inventory,bought[0])
	check(arena.state.crafting_balance()==4 and selection()==controls,"Actual recycle credits one and preserves dirty selection")
	before=authority()
	for unused: int in range(4):arena.world_context_changed.emit()
	await settle();valid_preview("balancefour refresh")
	check(authority()==before and arena.normal_prepares==0 and arena.map_draft()==original,"Balance/world refresh only updates preview, never prepares or adopts a draft")
	if DisplayServer.get_name()!="headless":
		var scroll := panel._content.get_parent() as ScrollContainer
		scroll.scroll_vertical=int(panel._map_preview.position.y)
		await process_frame;await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://docs/qa/map-cost-preview/unprepared.png")==OK,"Capture native unprepared price/reward preview")
	panel._map_prepare.pressed.emit();await settle()
	var prepared: Dictionary = arena.map_draft()
	check(arena.normal_prepares==1 and prepared.revision==original.revision+1 and prepared.map_id=="broken_ruins" and prepared.cost==4,
		"Only explicit prepare advances exact selected draft")
	check(not panel._map_preview.visible and panel._map_preview.text.is_empty() and not panel._map_selection_dirty and not panel._map_launch.disabled,
		"Prepared state clears preview and returns to authoritative launch gate")
	var after := bytes_to_var(before) as Array
	check(arena.state.snapshot()==after[0] and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==after[4] and arena.state.crafting_balance()==4
		and arena.rng.state==after[3] and arena.state.successful_saves==after[6],"Explicit prepare also never charges or writes inventory")
	before=authority();panel._launch_map(original.revision);await settle()
	check(authority()==before,"Captured obsolete launch rejects exact old revision after explicit preparation")
	panel.hide();panel.open_service("map_device");await settle()
	check(not panel._map_preview.visible and arena.map_draft()==prepared,"Cancel/reopen preserves prepared authority without stale preview")
	check(arena.enter_town_test(arena.world_context().revision).ok,"Enter existing test profile")
	await settle();panel.open_service("map_device");await settle()
	before=authority();choose(panel._map_select,"broken_ruins");panel._special.storm_patrol.button_pressed=true;await settle()
	valid_preview("independent test selection")
	check(authority()==before and arena.test_prepares==0,"Test preview neither prepares nor affects either profile")
	choose(panel._map_select,"old_garden");await settle();invalid_preview("test fixed-wave gate")
	check(arena.leave_town_test(arena.world_context().revision).ok,"Return to normal profile")
	await settle();panel.open_service("map_device");await settle()
	check(arena.map_draft().map_id=="broken_ruins" and not panel._map_preview.visible and not panel._map_launch.disabled,"Normal prepared state and revision survive test-profile preview")
	var next_run: int = arena.state.normal_journey().next_run_id
	panel._map_launch.pressed.emit();await settle()
	check(arena.world_context().mode=="map" and arena.state.crafting_balance()==0 and arena.state.normal_journey().active_run.fee_paid==4
		and arena.state.normal_journey().next_run_id==next_run+1,"Only actual lawful entry spends four and creates one real run")
	before=authority();panel._map_launch.pressed.emit();panel._launch_map(original.revision);await settle()
	check(authority()==before,"Repeated launch signals never charge again")
	await finish()
func finish() -> void:
	var hashes: Dictionary = {}
	for path: String in ["scripts/main.gd","scripts/ui/town_service_panel.gd","scripts/world/map_compiler.gd","scripts/world/normal_map_catalog.gd"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	var report := {"checks":checks,"failures":failures.size(),"failed_labels":failures,"states":states,"source_sha256":hashes,
		"display":DisplayServer.get_name(),"method":"Trusted finite canonical UI fixture, actual Main/panel/inventory signals, one lawful entry; no combat, model assets or economic balance claim"}
	var target := OS.get_environment("MAP_COST_PREVIEW_REPORT")
	if not target.is_empty():
		var output := FileAccess.open(target,FileAccess.WRITE);output.store_string(JSON.stringify(report,"\t")+"\n");output.close()
	print("MAP_COST_PREVIEW "+JSON.stringify(report))
	if is_instance_valid(arena):arena.queue_free()
	await process_frame;quit(0 if failures.is_empty() else 1)
