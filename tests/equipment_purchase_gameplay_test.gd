extends SceneTree
## Bounded real-map earned-money flow plus the actual new merchant controls.
const Model = preload("res://scripts/canonical_game_state.gd")
const Purchase = preload("res://scripts/items/equipment_purchase.gd")
var arena: Node
var checks := 0
var failures := 0
var evidence: Array[Dictionary] = []
func check(value: bool, label: String) -> void:
	checks+=1;evidence.append({"ok":value,"label":label})
	if not value: failures+=1;push_error(label)
func _initialize() -> void: call_deferred("run")
func observe() -> Array:
	return [arena.state.snapshot(),FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH),arena.state.successful_saves,
		arena.rng.state,arena.critical_runtime.checkpoint(),arena.group_cooldowns.snapshot(),arena.flask_runtime.snapshot()]
func kill_all() -> void:
	for enemy: Dictionary in arena.enemies.duplicate():
		if float(enemy.health)>0.0:
			enemy.spawn=0.0;arena._damage_enemy(enemy,float(enemy.health)+float(enemy.shield)+1000.0,Color.WHITE)
	arena._flush_monster_spawns()
func complete_map() -> void:
	var geometry: Dictionary = arena.world_geometry().landmarks
	for camp: Dictionary in geometry.camps:
		arena.player_pos=camp.trigger_center;arena._update_map_spawning(0.0)
	arena._begin_progress_transaction()
	kill_all()
	arena.player_pos=geometry.boss.trigger_center;arena._update_map_spawning(0.0)
	kill_all();kill_all();arena._check_map_complete();arena._end_progress_transaction()
	check(arena.world_context().mode=="map_complete" and arena.world_context().pending_map_reward.shards==4,"Real tier-one root/boss/descendant completion earns four-shard receipt")
	check(arena.return_to_town(arena.world_context().revision).ok,"Real completed map returns to town")
	var claim: Dictionary = arena.claim_normal_rewards(arena.world_context().revision)
	check(claim.ok and claim.claimed_shards==4,"Existing claim puts four physical shards in bag")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"): quit(78);return
	arena=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	check(arena.save_build() and arena.world_context().normal_town and arena.state.crafting_balance()==0,"Fresh actual formal town starts without free currency")
	var before:=observe()
	var rows: Array = arena.town_stock("equipment_merchant")
	check(rows.size()==Purchase.Gear.all_base_ids().size(),"Formal merchant lists existing bases only")
	for row: Dictionary in rows:check(row.paid and row.cost==8 and not row.available and row.purchase_kind=="equipment","Zero-shard stock uses paid base metadata")
	check(observe()==before,"Reading stock has no authoritative effects")
	check(not arena.town_buy("base:forgeblade",arena.state.revision()).ok and observe()==before,"Free supplier cannot write paid base into normal save")
	for cycle: int in range(4):
		check(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok and arena.start_map(arena.map_draft().revision).ok,"Actual free tier-one map starts")
		before=observe()
		check(not arena.normal_equipment_purchase_quote("forgeblade",arena.state.revision()).ok and observe()==before,"Paid equipment unavailable during real map")
		complete_map()
	check(arena.state.crafting_balance()==16 and arena.state.normal_journey().normal_root_kills==100,"Four bounded real maps fund purchase and existing eight-shard enchant; descendants do not add reward")
	var panel: Control = arena.hud._town_view
	var square: Control = arena.hud._town_square
	var merchant_index: int = square._ids.find("equipment_merchant")
	check(merchant_index>=0 and not square._buttons[merchant_index].disabled,"Actual town shopkeeper button is enabled")
	square._buttons[merchant_index].pressed.emit();await process_frame
	check(panel._service=="equipment_merchant" and not panel._service_buttons.equipment_merchant.disabled,"Existing town route exposes actual formal equipment service")
	rows=arena.town_stock("equipment_merchant")
	check(panel._content.get_child_count()==rows.size(),"Actual panel renders one row per catalog base")
	var index := -1
	for i: int in range(rows.size()):
		if rows[i].base_id=="forgeblade": index=i;break
	check(index>=0,"Existing short blade is a selectable crafting base")
	if index<0: arena.queue_free();quit(1);return
	var button: Button = panel._content.get_child(index).get_child(2)
	before=observe();button.pressed.emit()
	check(panel._gem_pending.get("kind")=="equipment" and panel._gem_dialog.visible and panel._gem_dialog.dialog_text.contains("物品等级 1") and panel._gem_dialog.dialog_text.contains("8"),"Actual purchase button shows exact base, level and cost confirmation")
	check(observe()==before,"Opening confirmation allocates no item, money or RNG")
	if DisplayServer.get_name()!="headless":
		await process_frame;await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://docs/qa/equipment-purchase/merchant-confirmation.png")==OK,"Capture one native merchant confirmation")
	var cancelled: String = panel._gem_pending.quote.handle
	panel._gem_dialog.canceled.emit()
	check(panel._gem_pending.is_empty() and observe()==before,"Actual cancel signal preserves earned money and inventory")
	check(not arena.execute_normal_equipment_purchase(cancelled,"forgeblade").ok and observe()==before,"Cancelled GUI quote cannot be reused")
	# Any external inventory update while the confirmation is open cancels it.
	button.pressed.emit()
	var stale: String = panel._gem_pending.quote.handle
	var copy: Dictionary = arena.state.snapshot();copy.revision+=1
	check(arena.state._commit(copy,arena.NORMAL_BUILD_PATH).ok,"Controlled unrelated revision commits through real store")
	check(panel._gem_pending.is_empty() and not arena.execute_normal_equipment_purchase(stale,"forgeblade").ok,"Live inventory notification cancels old confirmation")
	await process_frame;await process_frame
	button=panel._content.get_child(index).get_child(2)
	var old_ids: Array = arena.state.snapshot().items.keys()
	before=observe()
	button.pressed.emit();panel._gem_dialog.confirmed.emit();panel._gem_dialog.hide();panel._confirm_gem_purchase()
	check(arena.state.crafting_balance()==8 and arena.state.successful_saves==before[2]+1,"UI confirmation and repeated callback debit once and save once")
	check(arena.rng.state==before[3] and arena.critical_runtime.checkpoint()==before[4] and arena.group_cooldowns.snapshot()==before[5] and arena.flask_runtime.snapshot()==before[6],"Purchase preserves combat/loot RNG, cooldowns and flask runtime")
	var bought := ""
	for uid: String in arena.state.snapshot().items:
		if uid not in old_ids and arena.state.item(uid).payload.get("base_id","")=="forgeblade":bought=uid
	check(not bought.is_empty(),"Real bag owns the selected original base")
	if bought.is_empty(): arena.queue_free();quit(1);return
	var quote: Dictionary = arena.state.crafting_quote("enchant",bought,arena.NORMAL_BUILD_PATH)
	check(quote.ok,"Purchased base gets authoritative existing enchant quote")
	if quote.ok:
		check(arena.state.execute_crafting(quote.handle,arena.state.item(bought).payload).ok and arena.state.crafting_balance()==0,"Existing enchant consumes its exact eight shards")
		var owned: Dictionary = arena.state.item(bought)
		check(owned.payload.rarity=="magic" and owned.payload.affixes.size()>=1 and owned.payload.item_level==1,"Existing catalog generates valid level-one magic affixes")
		panel.hide();arena.hud.open_panel("inventory")
		var inventory: Control = arena.hud._inventory_panel
		inventory._activate_item(bought)
		check(arena.state.location(bought)=={"kind":"equipment","slot_id":"weapon"},"Existing inventory activation equips purchased crafted base")
		check(arena.state.get_basic_attack_profile().delivery=="melee" and arena.state.get_basic_cast().ok,"Existing real basic attack compiler consumes equipped short blade")
	# A quoted purchase cannot cross practice/town or test-profile transitions.
	var borrowed: Dictionary = arena.state.snapshot()
	check(arena.state._set_bag_currency_balance(borrowed,8).ok,"Boundary fixture only adds physical test-controlled money")
	borrowed.revision+=1;check(arena.state._commit(borrowed,arena.NORMAL_BUILD_PATH).ok,"Boundary fixture commits schema unchanged")
	panel.open_service("equipment_merchant");panel._request_equipment_purchase("forgeblade")
	var switched_handle: String = panel._gem_pending.quote.handle
	panel._select("skill_merchant");before=observe()
	check(not arena.execute_normal_equipment_purchase(switched_handle,"forgeblade").ok and observe()==before,"Switching merchant cancels the equipment quote")
	panel._request_gem_purchase("support:efficiency")
	check(panel._gem_pending.get("kind")=="gem" and panel._gem_dialog.title=="购买宝石" and panel._gem_dialog.dialog_text.contains("4"),"Shared confirmation still routes the original gem price and title")
	panel._gem_dialog.canceled.emit();check(observe()==before,"Cancelling original gem confirmation after equipment leaves money unchanged")
	quote=arena.normal_equipment_purchase_quote("forgeblade",arena.state.revision())
	panel.hide()
	check(arena.leave_normal_town(arena.world_context().revision).ok,"Existing route enters arena practice")
	check(arena.enter_normal_town(arena.world_context().revision).ok,"Existing route returns to town")
	before=observe();check(not arena.execute_normal_equipment_purchase(quote.handle,"forgeblade").ok and observe()==before,"Quote cannot survive leaving and returning to same town")
	quote=arena.normal_equipment_purchase_quote("forgeblade",arena.state.revision())
	check(arena.enter_town_test(arena.world_context().revision).ok,"Existing test isolation route enters separate profile")
	var normal_disk:=FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	check(not arena.normal_equipment_purchase_quote("forgeblade",arena.state.revision()).ok and not arena.execute_normal_equipment_purchase(quote.handle,"forgeblade").ok,"Paid service rejects test profile and old normal handle")
	rows=arena.town_stock("equipment_merchant")
	check(rows.size()>Purchase.Gear.all_base_ids().size() and not rows[0].get("paid",false),"Original test supply retains fixed equipment, flasks, free level-thirty bases and currency")
	check(arena.town_buy("base:forgeblade",arena.state.revision()).ok and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==normal_disk,"Test supply still works without touching normal file")
	check(arena.leave_town_test(arena.world_context().revision).ok and arena.state.item(bought).payload.rarity=="magic" and arena.state.location(bought).slot_id=="weapon","Returning preserves crafted normal equipment")
	var reloaded:=Model.new();check(reloaded.load_build(arena.NORMAL_BUILD_PATH) and reloaded.snapshot()==arena.state.snapshot(),"Current version reload preserves complete purchase/crafting/equip state")
	var report: Dictionary = {"checks":checks,"failures":failures,"renderer":DisplayServer.get_name(),"evidence":evidence,"save_version":arena.state.snapshot().version,
		"source_sha256":{"purchase":FileAccess.get_sha256("res://scripts/items/equipment_purchase.gd"),"main":FileAccess.get_sha256("res://scripts/main.gd"),"panel":FileAccess.get_sha256("res://scripts/ui/town_service_panel.gd")}}
	var output:=FileAccess.open("res://docs/qa/equipment-purchase/"+("headless" if DisplayServer.get_name()=="headless" else "native")+"-report.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t",true,true)+"\n");output.close()
	print("Equipment purchase gameplay: %d checks, %d failures" % [checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
