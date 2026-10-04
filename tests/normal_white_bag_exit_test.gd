extends SceneTree
const Items=preload("res://scripts/items/unified_item_catalog.gd")
const Maps=preload("res://scripts/world/map_compiler.gd")
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var arena:Node=load("res://scenes/main.tscn").instantiate();root.add_child(arena);await process_frame;arena.set_process(false);arena.hud.set_process(false)
	var model:RefCounted=arena.state;var candidate:Dictionary=model.snapshot()
	for uid:String in candidate.locations.keys():
		if candidate.locations[uid].kind=="bag":candidate.locations.erase(uid);candidate.items.erase(uid)
	var white_ids:Array[String]=[]
	while true:
		var uid:="gear_%06d"%int(candidate.next_item_serial)
		var wrapped:Dictionary=Items.wrap_equipment({"id":uid,"base_id":"wayglass_token","rarity":"normal","item_level":1,"affixes":[]})
		if not model._place_journey_reward(candidate,wrapped):break
		white_ids.append(uid)
	candidate.revision+=1
	check(white_ids.size()==240 and model._commit(candidate,arena.NORMAL_BUILD_PATH).ok,"All240 bag cells contain real ordinary equipment")
	var first:Dictionary=model.normal_start_map(Maps.compile_normal("old_garden",1,[],[]).profile,model.revision(),arena.NORMAL_BUILD_PATH)
	check(first.ok and model.normal_complete_map(first.run_id,model.revision(),arena.NORMAL_BUILD_PATH).ok,"Valid pending cash setup")
	arena.world_context_changed.emit()
	var before:=var_to_bytes(model.snapshot());var disk:=FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)
	check(not arena.claim_normal_rewards(arena.world_context().revision).ok and var_to_bytes(model.snapshot())==before and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==disk,"Full-white bag denies claim while preserving pending reward")
	check(model.can_discard_item(white_ids[0]),"Normal unreferenced white equipment has an explicit discard exit")
	for uid:String in model.equipped_items().values():check(not model.can_discard_item(uid),"Equipped/reference item still cannot be discarded")
	# Existing confirmation controls, cancellation first, then an actual UID removal.
	arena.hud.open_panel("inventory");await process_frame
	var panel:Control=arena.hud._inventory_panel
	panel._select_item(white_ids[0]);panel._discard.pressed.emit()
	check(panel._craft_dialog.visible and panel._pending_discard.uid==white_ids[0],"Existing confirmation opens for exactly selected white UID")
	panel._craft_dialog.canceled.emit()
	check(var_to_bytes(model.snapshot())==before and FileAccess.get_file_as_bytes(arena.NORMAL_BUILD_PATH)==disk,"Cancellation leaves full bag and reward exact")
	panel._discard.pressed.emit();panel._craft_dialog.confirmed.emit();panel._craft_dialog.hide()
	check(model.item(white_ids[0]).is_empty() and model.item(white_ids[1]).payload.rarity=="normal","Confirmed discard removes one UID, not same-name items")
	check(model.crafting_balance()==0 and model.normal_pending_rewards().pending_map_reward.shards==4,"Discard creates no shards and keeps pending cash")
	var claimed:Dictionary=arena.claim_normal_rewards(arena.world_context().revision)
	check(claimed.ok and claimed.claimed_shards==4 and model.crafting_balance()==4,"One freed white-item cell admits complete real shard reward")
	check(model.normal_pending_rewards().pending_map_reward.is_empty() and model.Rules.reason(model.snapshot()).is_empty(),"Successful claim preserves canonical snapshot and clears receipt")
	# Blue and gold restrictions remain unchanged on otherwise identical bases.
	var saved:Dictionary=model.snapshot();var alternate:Dictionary=saved.duplicate(true)
	alternate.items[white_ids[1]].payload.rarity="magic";alternate.items[white_ids[1]].payload.affixes=[{"id":"rootwell","tier":1,"value":8}]
	check(model.Rules.reason(alternate).is_empty(),"Magic comparison fixture is a legal item")
	model._accept_memory(alternate);check(not model.can_discard_item(white_ids[1]),"Normal-profile magic gear keeps prior discard restriction")
	alternate.items[white_ids[1]].payload.rarity="rare";alternate.items[white_ids[1]].payload.affixes=[{"id":"rootwell","tier":1,"value":8},{"id":"deepwell","tier":1,"value":5},{"id":"coalglow","tier":1,"value":5},{"id":"wellturn","tier":1,"value":3}]
	check(model.Rules.reason(alternate).is_empty(),"Rare comparison fixture is a legal item")
	model._accept_memory(alternate);check(not model.can_discard_item(white_ids[1]),"Normal-profile rare gear keeps prior discard restriction")
	model._accept_memory(saved)
	print("Normal white-bag exit: %d checks, %d failures"%[checks,failures]);arena.queue_free();await process_frame;quit(1 if failures else 0)
