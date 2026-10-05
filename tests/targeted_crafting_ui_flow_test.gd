extends SceneTree
const Items = preload("res://scripts/items/unified_item_catalog.gd")
var arena: Node
var panel: Control
var checks := 0
var failures := 0
func expect(condition: bool,label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func frames(count: int=2) -> void:
	for unused in range(count): await process_frame
func request() -> void:
	var button: Button = panel._craft_controls._target_button
	button.button_down.emit()
	button.pressed.emit()
	await frames()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/v049-root-ui-flow"):
		quit(78)
		return
	root.size = Vector2i(1280,720)
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	await frames(3)
	var state = arena.state
	var uid := "gear_%06d" % int(state.snapshot().next_item_serial)
	expect(state._admit_reward_item(Items.wrap_equipment({"id":uid,"base_id":"cinder_reed","rarity":"magic","item_level":30,"affixes":[{"id":"deepwell","tier":1,"value":5}]})),"Real eligible magic item admitted")
	var candidate: Dictionary = state.snapshot()
	expect(state._set_bag_currency_balance(candidate,100).ok,"Real bag material funded")
	state._accept_memory(candidate)
	expect(state.save_build(arena.build_save_path) == OK,"Fixture saved through authoritative model")
	while arena.hud.is_blocking(): arena.hud.close_panel()
	arena.hud.open_panel("inventory")
	await frames()
	panel = arena.hud._inventory_panel
	panel._select_item(uid)
	await frames()
	var controls: Control = panel._craft_controls
	var selected := -1
	for index in range(controls._target_select.item_count):
		if controls._target_select.get_item_metadata(index) == "targeted_reforge_damage": selected = index
	expect(selected >= 0,"Real operation metadata exposes damage family")
	if selected < 0:
		quit(1)
		return
	controls._target_select.select(selected)
	controls._target_select.item_selected.emit(selected)
	expect(not controls._target_button.disabled,"Funded compatible operation enabled")
	var before := var_to_bytes(state.snapshot())
	await request()
	expect(panel._craft_dialog.visible and panel._pending_craft.quote.operation == "targeted_reforge_damage","One exact targeted quote reaches confirmation")
	expect(panel._craft_dialog.dialog_text.contains("16") and panel._craft_dialog.dialog_text.contains("伤害") and panel._craft_dialog.dialog_text.contains("全部原词缀将被替换"),"Fee target and destructive replacement shown before payment")
	panel._craft_dialog.get_cancel_button().pressed.emit()
	await frames()
	expect(var_to_bytes(state.snapshot()) == before and state._craft_quotes.is_empty(),"Cancel preserves saved build and releases quote")
	await request()
	panel._craft_dialog.get_ok_button().pressed.emit()
	await frames()
	expect(state.crafting_balance() == 84 and not state.item(uid).is_empty(),"Confirmation pays16 once and keeps item identity")
	var after := var_to_bytes(state.snapshot())
	panel._craft_dialog.confirmed.emit()
	await frames()
	expect(var_to_bytes(state.snapshot()) == after,"Duplicate confirm cannot charge or reroll again")
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size = resolution
		arena.hud._apply_presentation()
		await frames()
		expect(controls._target_row.get_global_rect().encloses(controls._target_button.get_global_rect()),"Target button fits at %d" % resolution.x)
		expect(controls._target_row.get_global_rect().encloses(controls._target_select.get_global_rect()),"Target selector fits at %d" % resolution.x)
	print("Targeted crafting UI flow: %d checks, %d failures" % [checks,failures])
	arena.queue_free()
	await frames(1)
	quit(0 if failures == 0 else 1)
