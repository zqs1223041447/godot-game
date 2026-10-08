extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Purchase = preload("res://scripts/items/jewel_purchase.gd")
var arena: Node
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label); push_error(label)
	return ok
func settle() -> void:
	await process_frame; await process_frame
func authority() -> Array:
	return [arena.state.snapshot(),FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH),arena.state.successful_saves,arena.rng.state]
func combat() -> Array:
	return [arena.rng.state,arena.critical_runtime.checkpoint(),arena.group_cooldowns.snapshot(),arena.flask_runtime.snapshot(),arena.attack_timer]
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
	check(arena.world_context().mode=="map_complete" and arena.world_context().pending_map_reward.shards==4,"Actual finite tier-I map earns four-shard receipt")
	check(arena.return_to_town(arena.world_context().revision).ok,"Actual completed run returns to normal town")
	var claimed: Dictionary = arena.claim_normal_rewards(arena.world_context().revision)
	check(claimed.ok and claimed.claimed_shards==4,"Existing claim admits four physical reward shards")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-jewel-purchase.") or FileAccess.file_exists("user://build_save.json"):
		quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena)
	arena.set_process(false);arena.set_physics_process(false);arena.hud.set_process(false);arena.auto_fire=false
	await settle()
	check(arena.save_build() and arena.world_context().normal_town and arena.state.crafting_balance()==0,"Fresh formal town starts without purchase funds")
	var model: RefCounted = arena.state
	var before := authority()
	var rows: Array = arena.town_stock("jewel_merchant")
	check(rows.size()==3 and rows.all(func(row: Dictionary):return row.paid and row.cost==8 and row.purchase_kind=="jewel" and not row.available),"Formal zero-fund stock exposes three paid ordinary samples only")
	check(authority()==before and not arena.town_buy("jewel:emberheart",model.revision()).ok,"Stock reads and free supplier cannot inject normal jewels")
	for unused: int in range(2):
		check(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Actual finite free map starts")
		before=authority()
		check(not arena.normal_jewel_purchase_quote("emberheart",model.revision()).ok and authority()==before,"Formal purchase unavailable during actual map")
		complete_map()
	check(model.crafting_balance()==8 and model.normal_journey().normal_root_kills==50,"Two actual25-root maps fund exactly one purchase without injected funds")
	check(model.jewels.values().any(func(jewel: Dictionary):return jewel.rarity in ["magic","rare"]),"Existing ordinary map jewel drops still occur")
	var panel: Control = arena.hud._town_view
	var square: Control = arena.hud._town_square
	var shop_index: int = square._ids.find("jewel_merchant")
	check(shop_index>=0 and not square._buttons[shop_index].disabled,"Formal town jewel shopkeeper is enabled")
	square._buttons[shop_index].pressed.emit();await settle()
	check(panel._service=="jewel_merchant" and not panel._service_buttons.jewel_merchant.disabled and panel._content.get_child_count()==3,"Actual merchant route renders three paid rows")
	before=authority()
	panel._request_jewel_purchase("emberheart")
	var cancelled: String = panel._gem_pending.quote.handle
	panel._gem_dialog.canceled.emit()
	check(panel._gem_pending.is_empty() and not arena.execute_normal_jewel_purchase(cancelled,"emberheart").ok and authority()==before,"UI cancel consumes no funds and invalidates jewel quote")
	panel._request_jewel_purchase("emberheart");cancelled=panel._gem_pending.quote.handle
	panel._request_equipment_purchase("forgeblade")
	check(panel._gem_pending.kind=="equipment" and not arena.execute_normal_jewel_purchase(cancelled,"emberheart").ok and authority()==before,"Shared equipment confirmation cancels jewel quote without buying")
	panel._request_jewel_purchase("emberheart");cancelled=panel._gem_pending.quote.handle
	panel._request_gem_purchase("skill:bolt")
	check(panel._gem_pending.kind=="gem" and not arena.execute_normal_jewel_purchase(cancelled,"emberheart").ok and authority()==before,"Shared gem confirmation cancels jewel quote without buying")
	panel._request_jewel_purchase("emberheart");cancelled=panel._gem_pending.quote.handle
	check(model.allocate_passive("2151",0,model.revision(),arena.build_save_path).ok,"First existing connected path node spends its real available point")
	await settle();before=authority()
	check(panel._gem_pending.is_empty() and not arena.execute_normal_jewel_purchase(cancelled,"emberheart").ok and authority()==before,"Model change refreshes jewel stock and cancels old confirmation")
	var button: Button = panel._content.get_child(0).get_child(2)
	button.pressed.emit()
	check(panel._gem_pending.kind=="jewel" and panel._gem_dialog.visible and panel._gem_dialog.dialog_text.contains("固定最低数值")
		and panel._gem_dialog.dialog_text.contains("8") and panel._gem_dialog.dialog_text.contains("连通"),"Actual purchase row shows exact fixed sample, price and socket restriction")
	if DisplayServer.get_name()!="headless":
		await process_frame;await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://docs/qa/jewel-purchase/confirmation.png")==OK,"Capture native fixed-jewel confirmation")
	var uid: String = panel._gem_pending.quote.uid
	var build_before: Dictionary = model.snapshot()
	var combat_before := combat()
	var stats_before: Dictionary = model.get_stats()
	panel._gem_dialog.confirmed.emit();await settle()
	var purchased: Dictionary = model.item(uid)
	if not check(not purchased.is_empty(),"Confirmed purchase creates real owned jewel"): await finish();return
	check(model.crafting_balance()==0 and model.snapshot().locations[uid].kind=="bag" and purchased==Purchase.make_jewel("emberheart",Purchase.Jewels.serial_from_id(uid)),"Existing reward funds debit eight and exact fixed template enters real bag")
	check(model.snapshot().talents==build_before.talents and model.get_stats()==stats_before and combat()==combat_before,"Purchase grants no points, stats, allocation rules, RNG or combat changes")
	before=authority()
	check(not model.move_item(uid,{"kind":"passive_socket","node_id":"6230"},model.revision(),arena.build_save_path).ok and authority()==before,"Unallocated/disconnected socket rejects with jewel retained in bag")
	arena.hud.open_panel("talents");await settle()
	var passives: Control = arena.hud._passive_panel
	var points: int = model.talent_points
	for node_id: String in ["37690","48423","6230"]:
		passives._find_node(node_id)
		check(not passives._allocate.disabled,"Existing connected node is legally allocatable: "+node_id)
		passives._allocate.pressed.emit();await settle()
	check(model.talent_points==points-3 and model.snapshot().talents.allocated.has("6230"),"Real UI path allocation spends three points and connects existing socket")
	passives._find_node("6230")
	for index: int in range(passives._jewel.item_count):
		if passives._jewel.get_item_metadata(index)==uid:
			passives._jewel.select(index);passives._jewel.item_selected.emit(index);break
	check(not passives._socket.disabled,"Existing talent picker accepts purchased bag jewel in connected socket")
	var socket_base: Dictionary = model.get_stats()
	passives._socket.pressed.emit();await settle()
	check(model.snapshot().locations[uid]=={"kind":"passive_socket","node_id":"6230"} and is_equal_approx(model.get_stats().damage,socket_base.damage+2.0)
		and is_equal_approx(model.get_stats().attack_speed,socket_base.attack_speed+0.04),"Actual socket button applies only existing fixed damage/tempo stats")
	var restored := Model.new()
	check(restored.load_build(arena.NORMAL_BUILD_PATH) and restored.snapshot()==model.snapshot() and restored.get_stats()==model.get_stats(),"Paid socketed jewel and connected tree survive exact reload")
	passives._return.pressed.emit();await settle()
	check(model.snapshot().locations[uid].kind=="bag" and model.get_stats()==socket_base,"Existing return button safely restores jewel to bag and reverses only its stats")
	before=authority()
	var salvage: Dictionary = model.crafting_quote("salvage",uid,arena.build_save_path)
	check(salvage.ok and model.execute_crafting(salvage.handle,purchased.payload).ok and model.item(uid).is_empty() and model.crafting_balance()==1,"Existing salvage consumes purchased jewel and returns only one shard")
	panel.open_service("jewel_merchant");await settle()
	check(panel._content.get_children().all(func(row: Node):return row.get_child(2).disabled),"Real stock refresh disables paid rows at one shard")
	check(arena.enter_town_test(arena.world_context().revision).ok,"Enter independent test profile after normal loop")
	await settle();panel.open_service("jewel_merchant");await settle()
	rows=arena.town_stock("jewel_merchant")
	check(rows.size()==4 and rows.any(func(row: Dictionary):return row.catalog_id=="branchfinder") and rows.all(func(row: Dictionary):return not row.get("paid",false)),"Original free test stock still includes special jewel solely in test mode")
	var normal_disk := FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	check(not arena.normal_jewel_purchase_quote("emberheart",arena.state.revision()).ok,"Paid normal API rejects test mode")
	check(arena.town_buy("jewel:branchfinder",arena.state.revision()).ok and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==normal_disk,"Free special test supply remains isolated from normal save")
	check(arena.leave_town_test(arena.world_context().revision).ok,"Return to original normal profile")
	await settle();panel.open_service("jewel_merchant");await settle()
	check(arena.state.crafting_balance()==1 and arena.town_stock("jewel_merchant").size()==3 and not arena.town_buy("jewel:branchfinder",arena.state.revision()).ok,"Normal profile restores actual one-shard balance and rejects special/free stock")
	await finish()
func finish() -> void:
	var hashes: Dictionary = {}
	for source: String in ["scripts/items/equipment_purchase.gd","scripts/items/jewel_purchase.gd","scripts/main.gd","scripts/ui/town_service_panel.gd","scripts/ui/town_square_view.gd","scripts/jewel_data.gd","scripts/items/jewel_craft_rules.gd"]:
		hashes[source]=FileAccess.get_sha256("res://"+source)
	var report := {"checks":checks,"failures":failures.size(),"failed_labels":failures,"source_sha256":hashes,"display":DisplayServer.get_name(),
		"method":"Two real finite maps, earned8shards, fixed purchase, actual connected talent/socket/return UI, existing salvage; no money/point injection or model assets"}
	var target := OS.get_environment("JEWEL_GAMEPLAY_REPORT")
	if not target.is_empty():
		var output := FileAccess.open(target,FileAccess.WRITE);output.store_string(JSON.stringify(report,"\t")+"\n");output.close()
	print("JEWEL_PURCHASE_GAMEPLAY "+JSON.stringify(report))
	if is_instance_valid(arena): arena.queue_free()
	await process_frame;quit(0 if failures.is_empty() else 1)
