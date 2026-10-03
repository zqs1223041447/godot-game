extends "res://tests/crafting_ui_integration_test.gd"
var controls: CraftingControls
var dialog: ConfirmationDialog
func _run() -> void:
	var location: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	if OS.get_name() != "Linux" or not location.begins_with("/tmp/godot-crafting-qa-") or not OS.get_user_data_dir().begins_with(location + "/"):
		quit(78)
		return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.auto_fire = false
	arena.spawn_timer = 99999.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 200055
	for unused: int in range(12):
		var spare: String = arena.state.award_equipment(rng, 30, "rare", "current")
		var quote: Dictionary = arena.state.crafting_quote("salvage", spare)
		_expect(quote.ok and arena.state.execute_crafting(quote.handle, quote.source_instance).ok, "Actual spare gear funds all new crafts")
	arena.hud.open_panel("inventory")
	panel = arena.hud._inventory_panel
	controls = panel._craft_controls
	dialog = panel._craft_dialog
	for operation: String in ["enchant", "elevate", "augment", "reforge"]:
		var id: String = arena.state.award_equipment(rng, 30, "normal" if operation == "enchant" else "magic", "local_weapon")
		if operation == "augment":
			arena.state.equipment_instances[id].affixes.resize(1)
			arena.state.changed.emit()
		panel.select_item("item:" + id)
		await _frames()
		_expect(controls.get_node("CraftingRow").get_child_count() == 3 and controls._recalibrate_button.text == "工艺", "Existing three-control row retained")
		var index: int = controls._menu_operations.find(operation)
		_expect(index >= 0 and not controls._expansion_menu.get_popup().is_item_disabled(index), "Eligible action shown and enabled")
		var before: Dictionary = arena.state._snapshot()
		var writes: int = arena.state.primary_save_attempt_count
		_select(operation)
		await _frames()
		_expect(dialog.visible and dialog.dialog_text.contains("结果不会提前展示") and dialog.get_ok_button().text.contains("消耗"), "Concrete no-preview cost confirmation appears")
		_expect(arena.state._snapshot() == before and arena.state.primary_save_attempt_count == writes, "Opening menu and confirmation never changes model")
		var handle: String = panel._pending_craft.handle
		_select(operation)
		_expect(panel._pending_craft.handle == handle, "Repeated selection while modal is open cannot retarget")
		dialog.get_cancel_button().pressed.emit()
		await _frames()
		_expect(arena.state._snapshot() == before and not dialog.visible, "Cancel neither advances seed/revision nor pays")
		_select(operation)
		await _frames()
		var cost: int = panel._pending_craft.amount
		writes = arena.state.primary_save_attempt_count
		dialog.get_ok_button().pressed.emit()
		await _frames()
		_expect(_saved() and arena.state.primary_save_attempt_count == writes + 1, "UI performs exactly one primary durable save")
		_expect(arena.state.crafting.revision == before.crafting.revision + 1 and arena.state.crafting_balance() == int(before.crafting.materials.calibration_shard) - cost, "UI pays exact quote once")
		var committed: Dictionary = arena.state._snapshot()
		dialog.get_ok_button().pressed.emit()
		_expect(arena.state._snapshot() == committed, "Repeated confirm after commit is inert")
		_expect(panel.selected_item_key == "item:" + id and arena.state.equipment_instances.has(id), "Identity and selected item survive")
		# Menu snapshots are taken before selection changes, then rejected upstream.
		controls._capture_menu()
		var previous: Dictionary = controls._menu_requests.duplicate(true)
		var other: String = arena.state.award_equipment(rng, 30, "magic", "local_weapon")
		_expect(not other.is_empty(), "Secondary selection fixture is actually admitted")
		panel.select_item("item:" + other)
		await _frames()
		controls._menu_requests = previous
		controls._request_menu(controls._menu_operations.find("reforge"))
		_expect(not dialog.visible, "Old menu click cannot target a newly selected item")
		controls._capture_menu()
		controls._close_menu()
		await _frames()
		controls._request_menu(controls._menu_operations.find("reforge"))
		_expect(not dialog.visible, "Closed menu consumes no stale request")
		for resolution: Vector2i in [Vector2i(1280,720), Vector2i(2560,1440)]:
			root.size = resolution
			arena.visual_settings.ui_scale = 1.1
			arena.visual_settings.font_scale = 1.2
			arena.hud._apply_presentation()
			await _frames()
			var row: HBoxContainer = controls.get_node("CraftingRow")
			var end: float = 0.0
			for child: Control in row.get_children():
				_expect(child.position.x >= end and child.get_rect().end.x <= row.size.x + 0.1, "Menu fits approved layout at maximum scales")
				end = child.get_rect().end.x
			_expect(not arena.hud._panel_scroll.get_h_scroll_bar().visible, "No horizontal overflow")
		_expect(arena.state.discard_equipment(other) and arena.state.discard_equipment(id), "Remove only isolated fixture items to preserve later capacity")
	arena.queue_free()
	await _frames()
	print("Crafting expansion UI: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
func _select(operation: String) -> void:
	controls._capture_menu()
	controls._request_menu(controls._menu_operations.find(operation))
