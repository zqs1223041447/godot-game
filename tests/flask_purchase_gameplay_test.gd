extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Purchase = preload("res://scripts/items/flask_purchase.gd")
var arena: Node
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label); push_error(label)
	return ok
func settle() -> void:
	await process_frame;await process_frame
func authority() -> Array:
	return [arena.state.snapshot(),FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH),arena.state.successful_saves,arena.rng.state]
func combat() -> Array:
	return [arena.rng.state,arena.critical_runtime.checkpoint(),arena.group_cooldowns.snapshot(),arena.attack_timer]
func kill_all() -> void:
	for enemy: Dictionary in arena.enemies.duplicate():
		if float(enemy.health)>0.0:
			enemy.spawn=0.0;arena._damage_enemy(enemy,float(enemy.health)+float(enemy.shield)+1000.0,Color.WHITE)
	arena._flush_monster_spawns()
func complete_map() -> void:
	var landmarks: Dictionary = arena.world_geometry().landmarks
	for camp: Dictionary in landmarks.camps:
		arena.player_pos=camp.trigger_center;arena._update_map_spawning(0.0)
	arena._begin_progress_transaction();kill_all()
	arena.player_pos=landmarks.boss.trigger_center;arena._update_map_spawning(0.0)
	kill_all();kill_all();arena._check_map_complete();arena._end_progress_transaction()
	check(arena.world_context().mode=="map_complete" and arena.world_context().pending_map_reward.shards==4,"Finite real tier-I map earns four-shard receipt")
	check(arena.return_to_town(arena.world_context().revision).ok,"Completed map returns to formal town")
	var claim: Dictionary = arena.claim_normal_rewards(arena.world_context().revision)
	check(claim.ok and claim.claimed_shards==4,"Existing claim places real reward shards in bag")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-flask-purchase.") or FileAccess.file_exists("user://build_save.json"): quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena)
	arena.set_process(false);arena.set_physics_process(false);arena.hud.set_process(false);arena.auto_fire=false
	await settle()
	check(arena.save_build() and arena.world_context().normal_town and arena.state.crafting_balance()==0,"Fresh formal town begins without purchase funds")
	var before := authority()
	var rows: Array = arena.town_stock("equipment_merchant")
	var bottles: Array = rows.filter(func(row: Dictionary):return row.purchase_kind=="flask")
	check(rows.size()==17 and bottles.size()==2 and bottles.all(func(row: Dictionary):return row.paid and row.cost==8 and not row.available),"Formal merchant includes15bases and two paid unavailable bottles at zero funds")
	check(authority()==before and not arena.town_buy("flask:life",arena.state.revision()).ok and not arena.town_buy("flask:mana",arena.state.revision()).ok,"Read-only stock and free supplier cannot grant formal bottles")
	for unused: int in range(4):
		check(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Existing finite free map starts")
		before=authority()
		check(not arena.normal_flask_purchase_quote("flask:life",arena.state.revision()).ok and authority()==before,"Buying bottles during actual map rejects")
		complete_map()
	check(arena.state.crafting_balance()==16 and arena.state.normal_journey().normal_root_kills==100,"Four bounded maps earn16physical shards for two bottles without fund injection")
	var panel: Control = arena.hud._town_view
	var square: Control = arena.hud._town_square
	var index: int = square._ids.find("equipment_merchant")
	check(index>=0 and not square._buttons[index].disabled,"Existing equipment shopkeeper is enabled")
	square._buttons[index].pressed.emit();await settle()
	check(panel._service=="equipment_merchant" and panel._content.get_child_count()==17,"Real merchant renders15bases plus two existing bottle icons/rows")
	before=authority()
	panel._request_flask_purchase("flask:life")
	var cancelled: String = panel._gem_pending.quote.handle
	panel._gem_dialog.canceled.emit()
	check(panel._gem_pending.is_empty() and not arena.execute_normal_flask_purchase(cancelled,"flask:life").ok and authority()==before,"Real cancel signal invalidates bottle quote without debit")
	panel._request_flask_purchase("flask:life");cancelled=panel._gem_pending.quote.handle
	panel._request_equipment_purchase("forgeblade")
	check(panel._gem_pending.kind=="equipment" and not arena.execute_normal_flask_purchase(cancelled,"flask:life").ok and authority()==before,"Shared equipment request cancels old bottle confirmation")
	panel._request_flask_purchase("flask:life");cancelled=panel._gem_pending.quote.handle
	panel._request_jewel_purchase("emberheart")
	check(panel._gem_pending.kind=="jewel" and not arena.execute_normal_flask_purchase(cancelled,"flask:life").ok and authority()==before,"Shared jewel request cancels old bottle confirmation")
	panel._request_flask_purchase("flask:mana");cancelled=panel._gem_pending.quote.handle
	panel._request_gem_purchase("skill:bolt")
	check(panel._gem_pending.kind=="gem" and not arena.execute_normal_flask_purchase(cancelled,"flask:mana").ok and authority()==before,"Shared gem request cancels old bottle confirmation")
	panel._request_flask_purchase("flask:life");cancelled=panel._gem_pending.quote.handle
	var candidate: Dictionary = arena.state.snapshot();candidate.revision+=1
	check(arena.state._commit(candidate,arena.NORMAL_BUILD_PATH).ok,"Controlled unrelated revision saves through existing authority")
	await settle();before=authority()
	check(panel._gem_pending.is_empty() and not arena.execute_normal_flask_purchase(cancelled,"flask:life").ok and authority()==before,"Inventory change cancels stale real UI confirmation")
	var world_quote: Dictionary = arena.normal_flask_purchase_quote("flask:life",arena.state.revision())
	panel.hide()
	check(arena.leave_normal_town(arena.world_context().revision).ok and arena.enter_normal_town(arena.world_context().revision).ok,"Existing routes leave and return to same formal town")
	before=authority()
	check(world_quote.ok and not arena.execute_normal_flask_purchase(world_quote.handle,"flask:life").ok and authority()==before,"Bottle quote cannot survive world round trip")
	panel.open_service("equipment_merchant");await settle()
	# Defensive fixture: existing runtime APIs seed consumed old bottles and recovery.
	# Town normally blocks use; the purchase must nevertheless preserve this state.
	var slots: Array = arena.state.flask_slots()
	var old_life: String = slots[0].uid
	var old_mana: String = slots[1].uid
	check(arena.flask_runtime.use(old_life,10.0,float(arena._stats.max_health),arena._stats).ok and arena.flask_runtime.use(old_mana,0.0,float(arena._stats.max_mana),arena._stats).ok,"Existing runtime fixture starts old life/mana recovery at20charge")
	arena.flask_runtime.advance(0.25,{"health":10.0,"mana":0.0},{"health":arena._stats.max_health,"mana":arena._stats.max_mana})
	var old_runtime: Dictionary = arena.flask_runtime.snapshot()
	var bought: Dictionary = {}
	for definition_id: String in ["flask:life","flask:mana"]:
		rows=arena.town_stock("equipment_merchant")
		index=-1
		for i: int in range(rows.size()):
			if rows[i].definition_id==definition_id:index=i;break
		if not check(index>=0,"Existing bottle is selectable: "+definition_id):await finish();return
		var button: Button = panel._content.get_child(index).get_child(2)
		before=authority()
		button.pressed.emit()
		check(panel._gem_pending.kind=="flask" and panel._gem_dialog.visible and panel._gem_dialog.title=="购买基础药剂" and panel._gem_dialog.dialog_text.contains("8") and panel._gem_dialog.dialog_text.contains("35%"),"Real bottle row opens name/effect/eight-shard confirmation")
		check(authority()==before,"Opening bottle confirmation changes no inventory, money or RNG")
		var uid: String = panel._gem_pending.quote.uid
		var issued: String = panel._gem_pending.quote.handle
		var prior: Dictionary = arena.state.snapshot()
		var prior_balance: int = arena.state.crafting_balance()
		var prior_stats: Dictionary = arena.state.get_stats()
		var combat_before := combat()
		var runtime_before: Dictionary = arena.flask_runtime.snapshot()
		if DisplayServer.get_name()!="headless" and definition_id=="flask:life":
			await process_frame;await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://docs/qa/flask-purchase/confirmation.png")==OK,"Capture native existing-style bottle confirmation")
		panel._gem_dialog.confirmed.emit();panel._gem_dialog.hide();panel._confirm_gem_purchase();await settle()
		if not check(not arena.state.item(uid).is_empty(),"Confirmed real bottle UID is owned"):await finish();return
		check(arena.state.item(uid)==Purchase.Flasks.create_instance(uid,definition_id) and arena.state.location(uid).kind=="bag" and arena.state.crafting_balance()==prior_balance-8,"Purchased original empty-payload bottle enters bag with exact debit")
		check(arena.state.successful_saves==before[2]+1 and arena.state.snapshot().next_item_serial==prior.next_item_serial+1 and arena.state.snapshot().version==55,"Confirmation plus repeated callback saves once with one new UID under schema55")
		check(arena.state.snapshot().journey==prior.journey and arena.state.get_stats()==prior_stats,"Purchase does not repeat starter/milestone gifts or change reward counters/stats")
		check(combat()==combat_before,"Purchase retains combat/loot RNG, critical state and skill cooldowns")
		var runtime_after: Dictionary = arena.flask_runtime.snapshot()
		check(runtime_after.active_by_resource==runtime_before.active_by_resource and runtime_after.charges_by_uid[old_life]==old_runtime.charges_by_uid[old_life] and runtime_after.charges_by_uid[old_mana]==old_runtime.charges_by_uid[old_mana] and runtime_after.charges_by_uid[uid]==30,"New UID initializes charge while old bottles and active recovery stay exact")
		for old_uid: String in runtime_before.charges_by_uid:
			check(runtime_after.charges_by_uid[old_uid]==runtime_before.charges_by_uid[old_uid],"Every pre-existing bottle keeps charge: "+old_uid)
		before=authority()
		check(not arena.execute_normal_flask_purchase(issued,definition_id).ok and authority()==before,"Real purchase handle cannot replay")
		bought[definition_id]=uid
	check(arena.state.crafting_balance()==0,"Two purchases consume only16earned shards")
	panel.hide();arena.hud.open_panel("inventory");await settle()
	var inventory: Control = arena.hud._inventory_panel
	for definition_id: String in bought:
		inventory._activate_item(bought[definition_id]);await settle()
		check(arena.state.location(bought[definition_id]).kind=="flask_slot","Existing inventory activation equips bought bottle: "+definition_id)
	check(arena.flask_runtime.snapshot().active_by_resource==old_runtime.active_by_resource and arena.flask_runtime.snapshot().charges_by_uid[old_life]==20,"Equipping purchased bottles leaves old recovery and spent charge intact")
	var restored := Model.new()
	check(restored.load_build(arena.NORMAL_BUILD_PATH) and restored.snapshot()==arena.state.snapshot(),"Both purchased and equipped bottles survive exact reload")
	while arena.hud.is_blocking():arena.hud.close_panel()
	check(arena.leave_normal_town(arena.world_context().revision).ok,"Existing town route enters playable practice")
	arena.demo_mode=true;arena.spawn_timer=9999.0;arena.enemies.clear();arena.health=10.0;arena.mana=0.0
	before=authority()
	for definition_id: String in bought:
		var slot_id: String = arena.state.location(bought[definition_id]).slot_id
		arena.hud._flask_buttons[slot_id].pressed.emit()
		check(arena.flask_runtime.snapshot().charges_by_uid[bought[definition_id]]==20,"Actual HUD uses equipped bought bottle at original ten-charge cost")
	check(authority()==before,"Using purchased bottles changes no persistent build, money or save count")
	arena.tick(3.0)
	check(is_equal_approx(arena.health,10.0+float(arena._stats.max_health)*0.35+float(arena._stats.life_regen)*3.0) and is_equal_approx(arena.mana,float(arena._stats.max_mana)*0.35+float(arena._stats.mana_regen)*3.0),"Actual gameplay restores original35percent in three seconds plus existing regeneration")
	check(arena.enter_normal_town(arena.world_context().revision).ok,"Return to existing formal town")
	check(arena.enter_town_test(arena.world_context().revision).ok,"Existing route enters independent test profile")
	await settle();before=authority()
	rows=arena.town_stock("equipment_merchant")
	check(rows.filter(func(row: Dictionary):return row.kind=="flask").size()==2 and rows.all(func(row: Dictionary):return not row.get("paid",false)),"Original test stock retains two free bottles and other free supplies")
	check(not arena.normal_flask_purchase_quote("flask:life",arena.state.revision()).ok,"Paid bottle API rejects test profile")
	var disk := FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	check(arena.town_buy("flask:mana",arena.state.revision()).ok and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==disk,"Free test bottle never writes normal save")
	check(arena.leave_town_test(arena.world_context().revision).ok,"Existing route restores original normal profile")
	await settle()
	check(arena.state.crafting_balance()==0 and arena.state.item(bought["flask:life"]).definition_id=="flask:life" and arena.state.item(bought["flask:mana"]).definition_id=="flask:mana","Normal paid bottles and zero balance remain after test isolation")
	await finish()
func finish() -> void:
	var hashes: Dictionary = {}
	for source: String in ["scripts/items/flask_purchase.gd","scripts/items/equipment_purchase.gd","scripts/items/flask_catalog.gd","scripts/combat/flask_runtime.gd","scripts/main.gd","scripts/ui/town_service_panel.gd","scripts/save/canonical_build_rules.gd"]:
		hashes[source]=FileAccess.get_sha256("res://"+source)
	var report := {"checks":checks,"failures":failures.size(),"failed_labels":failures,"source_sha256":hashes,"display":DisplayServer.get_name(),"method":"Four actual finite maps fund two bottles; real merchant confirmation, inventory activation, HUD use; old-runtime defensive fixture; no money injection"}
	var target := OS.get_environment("FLASK_GAMEPLAY_REPORT")
	if not target.is_empty():
		var output := FileAccess.open(target,FileAccess.WRITE);output.store_string(JSON.stringify(report,"\t")+"\n");output.close()
	print("FLASK_PURCHASE_GAMEPLAY "+JSON.stringify(report))
	if is_instance_valid(arena):arena.queue_free()
	await process_frame;quit(0 if failures.is_empty() else 1)
