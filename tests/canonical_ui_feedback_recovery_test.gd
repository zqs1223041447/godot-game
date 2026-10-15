extends "res://tests/flask_purchase_transactions_test.gd"
## Actual main HUD/panel handlers, isolated storage, no visual/pixel assertions.
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-ui-feedback.") or not OS.get_user_data_dir().begins_with(isolated + "/") or FileAccess.file_exists(PATH):
		quit(78)
		return
	var model := FaultModel.new()
	check(model.save_build(PATH) == OK, "Fixture saves")
	var arena = load("res://scenes/main.tscn").instantiate()
	arena.state = model
	arena.build_save_path = PATH
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.hud.set_process(false)
	await process_frame
	await process_frame
	arena.hud.open_panel("skills")
	var panel = arena.hud._skill_support_panel
	check(panel.get_script().resource_path == "res://scripts/ui/canonical_skill_panel.gd", "Actual canonical skills panel")
	var group: String = model.snapshot().skill_groups[0].id
	var before := observe(model)
	model.fail_writes = true
	panel._bind(group, KEY_Z, model.revision())
	var failed: String = arena.hud._dock_footers.left.text
	check(observe(model) == before and not failed.is_empty(), "Failed bind preserves memory/disk/revision/save count and reports error")
	model.fail_writes = false
	panel._bind(group, KEY_Z, model.revision())
	check(model.group_for_key(KEY_Z) == group and arena.hud._dock_footers.left.text == "操作已保存", "Bind retry replaces stale error with saved feedback")
	model.fail_writes = true
	panel._bind(group, KEY_V, model.revision())
	model.fail_writes = false
	before = observe(model)
	panel._bind(group, KEY_Z, model.revision())
	check(observe(model) == before and arena.hud._dock_footers.left.text == "无需更改", "Repeated binding clears error without claiming another save")
	arena.hud.open_panel("inventory")
	panel = arena.hud._inventory_panel
	var uid := ""
	for entry: Dictionary in panel._grid._items:
		if model.can_discard_item(entry.uid):
			uid = entry.uid
			break
	check(not uid.is_empty(), "Visible discardable fixture item")
	var destination := {"kind":"bag", "page":1, "x":0, "y":0}
	before = observe(model)
	model.fail_writes = true
	panel._move_requested(uid, destination, model.revision())
	failed = arena.hud._dock_footers.right.text
	check(observe(model) == before and not failed.is_empty(), "Failed inventory move preserves exact state and reports error")
	model.fail_writes = false
	panel._move_requested(uid, destination, model.revision())
	check(model.location(uid) == destination and arena.hud._dock_footers.right.text == "操作已保存", "Inventory retry replaces stale failure")
	model.fail_writes = true
	panel._move_requested(uid, {"kind":"bag", "page":1, "x":3, "y":0}, model.revision())
	model.fail_writes = false
	before = observe(model)
	panel._move_requested(uid, destination, model.revision())
	check(observe(model) == before and arena.hud._dock_footers.right.text == "无需更改", "No-change inventory move clears failure without saving")
	panel._turn_page(1)
	panel._select_item(uid)
	panel._request_discard()
	var stale_request: Dictionary = panel._pending_discard.duplicate(true)
	check(not stale_request.is_empty() and panel._craft_dialog.visible, "Discard confirmation opens for visible item")
	# Cancellation feedback is synchronous; a late confirmation listener must be harmless.
	var late_confirm := func(message: String) -> void:
		if message == "物品已变化，已取消丢弃，请重新操作": panel._craft_dialog.confirmed.emit()
	panel.feedback.connect(late_confirm)
	var saves: int = model.successful_saves
	check(model.bind_group(group, KEY_V, model.revision(), PATH).ok, "Unrelated binding advances revision")
	check(panel._pending_discard.is_empty() and not panel._craft_dialog.visible and not model.item(uid).is_empty() and model.successful_saves == saves + 1, "Revision cancels pending dialog before reentrant confirmation; no deletion/save")
	panel.feedback.disconnect(late_confirm)
	before = observe(model)
	panel._craft_dialog.confirmed.emit()
	check(observe(model) == before, "Late confirmation after revision invalidation is harmless")
	# Defense in depth: even an old retained request cannot delete against a newer revision.
	panel._pending_discard = stale_request
	panel._craft_dialog.confirmed.emit()
	check(observe(model) == before and not model.item(uid).is_empty(), "Stale retained request is rejected byte-identically by model")
	panel._request_discard()
	panel._craft_dialog.canceled.emit()
	check(panel._pending_discard.is_empty() and not panel._craft_dialog.visible, "Explicit cancel consumes request and hides dialog")
	before = observe(model)
	panel._craft_dialog.confirmed.emit()
	check(observe(model) == before, "Late confirmation after explicit cancel is harmless")
	panel._request_discard()
	panel.hide()
	check(panel._pending_discard.is_empty() and not panel._craft_dialog.visible, "Panel hide cancels pending discard")
	panel.show()
	panel._request_discard()
	before = observe(model)
	model.fail_writes = true
	panel._craft_dialog.confirmed.emit()
	model.fail_writes = false
	check(observe(model) == before and not model.item(uid).is_empty() and panel._pending_discard.is_empty(), "Failed discard preserves exact state and consumes request")
	panel._cancel_craft()
	panel._request_discard()
	panel._craft_dialog.confirmed.emit()
	check(model.item(uid).is_empty() and arena.hud._dock_footers.right.text == "操作已保存", "Fresh discard succeeds and replaces failure feedback")
	print("CANONICAL_UI_FEEDBACK_RECOVERY ", JSON.stringify({"checks":checks,"failures":failures}))
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
