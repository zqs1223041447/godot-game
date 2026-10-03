extends SceneTree
var arena: Node2D
var panel: InventoryPanel
var checks: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")
func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _frames() -> void:
	for unused: int in range(4): await process_frame

func _saved() -> bool:
	return FileAccess.get_file_as_string("user://build_save.json") == JSON.stringify(arena.state._snapshot(),"\t",true,true)

func _run() -> void:
	var location: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	if OS.get_name() != "Linux" or not location.begins_with("/tmp/godot-crafting-qa-") or not OS.get_user_data_dir().begins_with(location+"/"):
		quit(78)
		return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.auto_fire = false
	arena.spawn_timer = 99999.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 150015
	var target: String = arena.state.award_equipment(rng,30,"magic","local_weapon")
	var spare: String = arena.state.award_equipment(rng,30,"rare","current")
	_expect(not target.is_empty() and not spare.is_empty(), "Actual generated items populate the main inventory")
	arena.hud.open_panel("inventory")
	panel = arena.hud._inventory_panel
	panel.select_item("item:"+spare)
	await _frames()
	var controls: CraftingControls = panel.get_node("InventoryColumns/ItemDetailPanel").find_child("InventoryCraftingControls",true,false)
	var salvage: Button = controls.find_child("SalvageButton",true,false)
	var calibrate: Button = controls.find_child("RecalibrateButton",true,false)
	var dialog: ConfirmationDialog = panel.get_node("CraftingConfirmation")
	_expect(controls.visible and not salvage.disabled and calibrate.disabled, "Zero-wallet inventory offers salvage, refuses unaffordable calibration")
	var before: Dictionary = arena.state._snapshot()
	var writes: int = arena.state.primary_save_attempt_count
	salvage.pressed.emit()
	await _frames()
	_expect(dialog.visible and dialog.dialog_text.contains("无法恢复") and dialog.dialog_text.contains("校准碎片"), "Salvage opens a concrete permanent-consumption confirmation")
	_expect(dialog.get_ok_button().get_theme_color("font_focus_color")==Color("3b281b") and dialog.get_cancel_button().get_theme_color("font_focus_color")==Color("3b281b"), "Confirmation focus keeps dark ink on its paper buttons too")
	_expect(dialog.theme.get_color("title_color","Window")==Color("f8ecd0"), "Confirmation title remains readable over the warm embedded frame")
	_expect(arena.state._snapshot()==before and arena.state.primary_save_attempt_count==writes, "Opening confirmation never consumes or writes")
	var first_handle: String = panel._pending_craft.handle
	salvage.pressed.emit()
	_expect(panel._pending_craft.handle==first_handle, "Repeated request while modal is open never changes its target")
	dialog.get_cancel_button().pressed.emit()
	await _frames()
	_expect(not dialog.visible and panel._pending_craft.is_empty() and arena.state._snapshot()==before, "Actual Cancel button preserves build and clears pending confirmation")
	salvage.pressed.emit()
	await _frames()
	_expect(dialog.visible, "Cancelled operation can be quoted and requested again")
	dialog.get_ok_button().pressed.emit()
	await _frames()
	_expect(not arena.state.inventory.has(spare) and arena.state.crafting_balance()>0 and _saved(), "Confirmed salvage reaches durable model transaction")
	var revision: int = arena.state.crafting.revision
	dialog.get_ok_button().pressed.emit()
	_expect(arena.state.crafting.revision==revision, "Repeated confirmation event cannot duplicate reward")
	for unused: int in range(4):
		spare = arena.state.award_equipment(rng,30,"rare","current")
		var quote: Dictionary = arena.state.crafting_quote("salvage",spare)
		_expect(quote.ok and arena.state.execute_crafting(quote.handle,quote.source_instance).ok, "Real additional surplus supplies currency")
	panel.select_item("item:"+target)
	await _frames()
	_expect(not calibrate.disabled, "Funded eligible item can be calibrated")
	before = arena.state._snapshot()
	controls._capture_menu()
	controls._request_menu(controls._menu_operations.find("recalibrate"))
	await _frames()
	_expect(dialog.visible and dialog.dialog_text.contains("可能降低或不变") and dialog.get_ok_button().text.contains("消耗"), "Calibration confirmation displays cost and downside before any roll")
	dialog.get_cancel_button().pressed.emit()
	await _frames()
	_expect(arena.state._snapshot()==before, "Calibration cancel does not advance currency, sequence or seed source")
	controls._capture_menu()
	controls._request_menu(controls._menu_operations.find("recalibrate"))
	await _frames()
	var cost: int = panel._pending_craft.amount
	writes = arena.state.primary_save_attempt_count
	dialog.get_ok_button().pressed.emit()
	await _frames()
	_expect(arena.state.crafting_balance()==int(before.crafting.materials.calibration_shard)-cost and arena.state.crafting.revision==int(before.crafting.revision)+1, "UI pays and advances exactly once")
	_expect(arena.state.primary_save_attempt_count==writes+1 and _saved(), "UI confirmation persists once through real main routing")
	_expect(panel.selected_item_key=="item:"+target and panel._detail_stats.text.contains("本武器"), "Same item remains selected and actual derived local weapon details refresh")
	# A press snapshot cannot retarget to the new selection at release.
	spare = arena.state.award_equipment(rng,30,"rare","current")
	panel.select_item("item:"+target)
	salvage.button_down.emit()
	panel.select_item("item:"+spare)
	salvage.pressed.emit()
	_expect(not dialog.visible and arena.state.inventory.has(target) and arena.state.inventory.has(spare), "Selection change between press and release refuses a stale action")
	# Confirmation remains bound to its original build, including unrelated changes.
	salvage.pressed.emit()
	await _frames()
	_expect(dialog.visible, "Current item can open a new confirmation")
	arena.state.add_xp(1)
	dialog.get_ok_button().pressed.emit()
	await _frames()
	_expect(arena.state.inventory.has(spare), "Build changes while modal is open invalidate its quote instead of consuming")
	panel.select_item("item:ember_wand")
	_expect(not controls.visible, "Fixed demonstration items do not display misleading crafting actions")
	panel.select_item("item:"+target)
	_expect(arena.state.equip(target), "Generated target equips through existing control model")
	panel.refresh()
	_expect(salvage.disabled and calibrate.disabled, "Worn target visibly refuses both operations")
	_expect(arena.state.unequip("weapon"), "Restore target to backpack for layout checks")
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size = resolution
		arena.visual_settings.ui_scale = 1.1
		arena.visual_settings.font_scale = 1.2
		arena.hud._apply_presentation()
		panel.select_item("item:"+target)
		await _frames()
		arena.hud._panel_scroll.ensure_control_visible(controls)
		await _frames()
		var row: HBoxContainer = controls.get_node("CraftingRow")
		_expect(controls.visible and controls.size.x<=panel.get_node("InventoryColumns/ItemDetailPanel").size.x, "Compact crafting row stays in existing detail column")
		var end: float = 0.0
		for child: Control in row.get_children():
			_expect(child.position.x>=end and child.get_rect().end.x<=row.size.x+0.1, "Scaled row children neither overlap nor overflow")
			end = child.get_rect().end.x
		_expect(salvage.get_theme_color("font_focus_color")==Color("3b281b"), "Focused paper action keeps approved dark ink")
		_expect(not arena.hud._panel_scroll.get_h_scroll_bar().visible, "Existing panel uses vertical scrolling without new horizontal overflow")
	var saved: Dictionary = arena.state._snapshot()
	arena.hud.close_panel()
	arena.hud.open_panel("inventory")
	await _frames()
	_expect(arena.state._snapshot()==saved and _saved(), "Close and reopen retains complete persistent crafting state")
	arena.free()
	print("Crafting UI integration: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
