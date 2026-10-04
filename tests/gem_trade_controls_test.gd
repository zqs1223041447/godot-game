extends SceneTree
const Arena = preload("res://scripts/main.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/v044-root-ui-"):
		quit(78)
		return
	var arena := Arena.new()
	root.add_child(arena)
	await process_frame
	var model: RefCounted = arena.state
	var uid := "item_%06d" % int(model.snapshot().next_item_serial)
	expect(model._admit_reward_item(model.Items.calibration_shard(uid, 19)), "Fixture uses real shard item")
	expect(model.save_build(arena.build_save_path) == OK, "Normal save receipt is current")
	var panel: Control = arena.hud._town_view
	panel.open_service("skill_merchant")
	expect(not panel._service_buttons.skill_merchant.disabled, "Normal paid gem merchant is enabled")
	expect(panel._content.get_child_count() == 26, "All implemented gem offers are represented")
	var before := var_to_bytes(model.snapshot())
	panel._request_gem_purchase("skill:bolt")
	expect(panel._gem_dialog.visible and panel._gem_dialog.dialog_text.contains("8"), "Purchase requires visible cost confirmation")
	panel._cancel_gem_purchase()
	expect(panel._gem_pending.is_empty() and var_to_bytes(model.snapshot()) == before, "Cancel does not charge or create item")
	var bought: Array[String] = []
	for index: int in range(2):
		var old_ids: Array = model.snapshot().items.keys()
		var balance: int = model.crafting_balance()
		panel._request_gem_purchase("skill:bolt")
		panel._confirm_gem_purchase()
		panel._confirm_gem_purchase()
		expect(model.crafting_balance() == balance - 8, "Confirmation consumes exactly one purchase")
		for id: String in model.snapshot().items:
			if id not in old_ids and model.item(id).definition_id == "skill:bolt": bought.append(id)
	expect(bought.size() == 2 and bought[0] != bought[1], "Same-name gems remain separate instances")
	panel._gem_dialog.hide()
	arena.hud.open_panel("inventory")
	panel.open_service("skill_merchant")
	var support_index := -1
	var offers: Array = arena.town_stock("skill_merchant")
	for index: int in range(offers.size()):
		if str(offers[index].kind) == "support_gem": support_index = index; break
	expect(support_index >= 0 and panel._content.get_child(support_index).get_child(2).disabled, "Three shards cannot buy a four-shard support")
	var inventory: Control = arena.hud._inventory_panel
	inventory._select_item(bought[0])
	inventory._request_craft("salvage", bought[0], model.item(bought[0]).payload)
	expect(inventory._craft_dialog.visible and inventory._pending_craft.get("gem", false), "Existing recycle button uses gem confirmation")
	before = var_to_bytes(model.snapshot())
	inventory._select_item(bought[1])
	inventory._confirm_craft()
	expect(var_to_bytes(model.snapshot()) == before, "Changing selected UID cancels the old confirmation")
	inventory._select_item(bought[0])
	inventory._request_craft("salvage", bought[0], model.item(bought[0]).payload)
	var balance: int = model.crafting_balance()
	inventory._confirm_craft()
	expect(model.item(bought[0]).is_empty() and not model.item(bought[1]).is_empty(), "Recycle consumes only selected gem")
	expect(model.crafting_balance() == balance + 1, "Recycle credits one real shard")
	await process_frame
	await process_frame
	expect(not panel._content.get_child(support_index).get_child(2).disabled, "Visible shop updates affordability after recycling in the bag")
	inventory._select_item(bought[1])
	expect(arena.leave_normal_town(int(arena.world_context().revision)).ok, "Fixture enters practice through real route")
	expect(inventory._craft_controls._salvage_button.disabled, "Gem recycle is disabled outside normal town")
	arena.queue_free()
	await process_frame
	print("Gem trade controls: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
