extends SceneTree
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
var checks := 0
var failures := 0
var arena: Node
var panel: Control
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func frames(count: int = 2) -> void:
	for unused: int in range(count): await process_frame
func request(operation: String) -> void:
	var button: Button = panel._craft_controls._operation_buttons[operation]
	button.button_down.emit()
	button.pressed.emit()
	await frames()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/v091-root-ui-"): quit(78); return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await frames(4)
	arena.set_process(false)
	var state = arena.state
	var source: Dictionary = Jewels.starter_jewels()["jewel_000001"].duplicate(true)
	var uid := "jewel_%06d" % int(state.snapshot().next_item_serial)
	source.id = uid
	check(state._admit_reward_item(Items.wrap_jewel(source)), "Legal ordinary jewel admitted")
	var candidate: Dictionary = state.snapshot()
	check(state._set_bag_currency_balance(candidate, 64).ok, "Fund isolated UI fixture")
	state._accept_memory(candidate)
	check(state.save_build("user://build_save.json") == OK, "Fixture saved")
	while arena.hud.is_blocking(): arena.hud.close_panel()
	arena.hud.open_panel("inventory")
	await frames()
	panel = arena.hud._inventory_panel
	panel.feedback.connect(func(message: String): print("UI_FEEDBACK ", message))
	panel._select_item(uid)
	await frames()
	check(panel._craft_controls._source_instance == source, "Jewel payload forwarded")
	check(not panel._craft_controls._operation_buttons.reforge.disabled, "Reforge enabled")
	check(not panel._craft_controls._operation_buttons.salvage.disabled, "Salvage enabled")
	check(state._craft_quotes.is_empty(), "Selection does not create quote")
	await request("reforge")
	check(panel._craft_dialog.visible and state._craft_quotes.size() == 1, "Click opens one quote")
	var cost := int(panel._pending_craft.quote.cost.calibration_shard)
	check(cost == (8 if source.rarity == "magic" else 16), "Authoritative fee")
	check(panel._craft_dialog.dialog_text.contains(str(cost)), "Fee shown in confirmation")
	panel._craft_dialog.get_cancel_button().pressed.emit()
	await frames()
	check(state._craft_quotes.is_empty() and state.crafting_balance() == 64, "Cancel releases without charge")
	await request("reforge")
	panel._craft_dialog.get_ok_button().pressed.emit()
	await frames()
	print("UI_RESULT balance=",state.crafting_balance()," expected=",64-cost," source=",source," item=",state.item(uid))
	check(state.crafting_balance() == 64-cost and state.item(uid).payload.base == source.base, "Confirmed craft keeps base and exact charge")
	var revision: int = state.revision()
	panel._craft_dialog.confirmed.emit()
	await frames()
	check(state.revision() == revision, "Duplicate confirmation no transaction")
	await request("salvage")
	print("SALVAGE_STATE ",panel._craft_dialog.visible," title=",panel._craft_dialog.title," text=",panel._craft_dialog.dialog_text," disabled=",panel._craft_controls._operation_buttons.salvage.disabled," ops=",panel._craft_metadata)
	check(panel._craft_dialog.title.contains("珠宝") and panel._craft_dialog.dialog_text.contains("这颗珠宝"), "Jewel salvage wording")
	panel._craft_dialog.get_cancel_button().pressed.emit()
	await frames()
	check(not state.item(uid).is_empty(), "Cancel preserves jewel")
	print("Jewel crafting UI: %d checks, %d failures" % [checks,failures])
	arena.queue_free()
	await frames(1)
	quit(0 if failures == 0 else 1)
