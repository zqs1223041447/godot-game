extends "res://tests/formal_boss_equipment_recovery_test.gd"
## One actual formal boss reward flow; reuse existing capacity and write-fault helpers.
const Presentation = preload("res://scripts/ui/unified_item_presentation.gd")
var baseline := false
var receipt: Dictionary = {}
var pointer := Vector2.ZERO

func frames(count: int = 3) -> void:
	for unused: int in range(count): await process_frame
func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point; event.global_position = point; event.relative = point - pointer
	Input.parse_input_event(event); Input.flush_buffered_events(); pointer = point
	await frames()
func click(button: Control) -> void:
	await motion(button.get_global_rect().get_center())
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pointer; event.global_position = pointer
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		Input.parse_input_event(event); Input.flush_buffered_events(); await frames(1)
func shift(down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT; event.pressed = down
	Input.parse_input_event(event); Input.flush_buffered_events()
	arena.hud._process(0.001); await frames()
func pending_button(uid: String) -> Button:
	var panel: Control = arena.hud._inventory_panel
	return panel._pending.get_child(1).get_child(model.pending_items().find(uid))
func reveal_pending() -> void:
	await frames()
	var scroll: ScrollContainer = arena.hud._dock_scrolls.right
	scroll.scroll_vertical = roundi(scroll.get_v_scroll_bar().max_value)
	await frames()
func finish() -> void:
	var report := {"baseline":baseline,"checks":checks,"failures":failures,"evidence":evidence,"receipt":receipt}
	var path := OS.get_environment("RECOVERY_COMPARE_REPORT")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("Recovery comparison: %d checks, %d failures" % [checks, failures.size()])
	await dispose(); quit(0 if failures.is_empty() else 1)
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-recovery-comparison-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78); return
	baseline = OS.get_environment("RECOVERY_COMPARE_BASELINE") == "1"
	root.size = Vector2i(1280, 720)
	if not await fresh("actual full-bag boss to recovery comparison"): await finish(); return
	fill_bag()
	var prior := model.snapshot()
	var enemy := boss(); kill(enemy)
	if not check(arena.boss_awards.size() == 1, "Actual registered boss rolls equipment once"): await finish(); return
	receipt = arena.boss_awards[0]
	var uid: String = receipt.uid
	check(model.item(uid) == receipt.expected and receipt.rng == receipt.expected_rng, "Original rare roll, affixes and RNG retained")
	check(model.location(uid).kind == "recovery" and model.pending_items().size() == 2, "Full bag retains distinct original boss gear and jewel UIDs")
	check(model.snapshot().next_item_serial == prior.next_item_serial + 2, "Exactly one UID per original boss reward")
	check(model.snapshot().version == prior.version and Model.Rules.reason(model.snapshot()).is_empty(), "Current schema and canonical ownership validation unchanged")
	repeated_death(enemy)
	arena.hud.open_panel("inventory"); await frames()
	await reveal_pending()
	var panel: Control = arena.hud._inventory_panel
	var button := pending_button(uid)
	check(button.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(root.size)).has_point(button.get_global_rect().get_center()), "Recovery button lies within visible scrolled inventory")
	var before := observe()
	await motion(Vector2(20, 350)); arena.hud._dismiss_item_hover()
	await motion(button.get_global_rect().get_center())
	var card: Control = arena.hud._item_hover
	if baseline:
		check(not card.visible and arena.hud._hover_uid.is_empty(), "BASELINE REPRO: real pointer on recovery gear opens no shared detail card")
		check(not Presentation.view(model, uid).affix_lines.is_empty() and not Presentation.comparisons(model, uid).is_empty(), "Existing adapter already provides hidden rare affixes and equipped comparisons")
		check(observe() == before, "Baseline hover is read-only")
		await finish(); return
	check(card.visible and arena.hud._hover_uid == uid, "Actual pointer on pending gear opens existing shared card")
	check(card._last_view == Presentation.view(model, uid) and not card._last_view.affix_lines.is_empty(), "Card displays complete actual rare affixes without a second formatter")
	await shift(true)
	check(card._last_compare and card._last_comparison_views == Presentation.comparisons(model, uid) and card._row.get_child_count() >= 2, "Actual Shift press renders owned equipped comparison alongside recovery item")
	await shift(false)
	check(not card._last_compare and card._row.get_child_count() == 1, "Releasing Shift restores single item details")
	check(observe() == before, "All hover and comparison events preserve state, disk, save count, RNG and reward ledger")
	await click(button)
	check(observe() == before and model.location(uid).kind == "recovery", "Actual full-bag click refuses retrieval without mutation")
	await motion(Vector2(20, 350)); await create_timer(0.21).timeout; arena.hud._process(0.001)
	check(not card.visible, "Leaving pending item dismisses through original hover lifetime")
	var jewel_uid := ""
	for pending: String in model.pending_items():
		if model.item(pending).kind == "jewel": jewel_uid = pending
	before = observe()
	await motion(pending_button(jewel_uid).get_global_rect().get_center())
	await shift(true)
	check(card.visible and arena.hud._hover_uid == jewel_uid and card._last_view == Presentation.view(model, jewel_uid), "Same queue displays actual coexisting boss jewel details")
	check(card._last_comparison_views.is_empty() and card._row.get_child_count() == 1, "Shift on jewel shows no stale equipment comparison")
	await shift(false)
	check(observe() == before, "Inspecting second pending UID preserves both rewards and disk")
	await motion(Vector2(20, 350)); await create_timer(0.21).timeout; arena.hud._process(0.001)
	# Move only capacity-fixture gems into distinct existing support rows. No discard/sale.
	var size: Vector2i = model.item_definition(uid).size
	var destinations: Array[Dictionary] = []
	for row: Dictionary in model.snapshot().skill_groups:
		var content: Dictionary = model.skill_group(row.id)
		if content.support_ids.has("efficiency"): continue
		for index: int in range(5):
			var target := {"kind":"skill_support","group_id":row.id,"index":index}
			var occupied := false
			for location: Dictionary in model.snapshot().locations.values():
				if location == target: occupied = true
			if not occupied: destinations.append(target); break
	var moved := 0
	for filler: String in filler_uids:
		var location: Dictionary = model.location(filler)
		if location.page == 1 and location.x >= Locations.CURRENT_BAG_COLUMNS - size.x and location.y >= Locations.CURRENT_BAG_ROWS - size.y:
			if not check(moved < destinations.size(), "Existing legal support rows suffice to preserve fixture gems"): break
			accepted(model.move_item(filler, destinations[moved], model.revision(), PATH), "Free cell by equipping existing gem, never deleting it")
			moved += 1
	check(moved == size.x * size.y and not model.first_bag_position(uid).is_empty(), "Original placement planner sees sufficient contiguous gear space")
	check(model.snapshot().items.size() == prior.items.size() + 2, "No item sold or destroyed while freeing capacity")
	await reveal_pending(); before = observe(); model.fail_writes = true
	await click(pending_button(uid))
	check(observe() == before, "Actual retrieval with injected write failure preserves entire memory, disk, UID and serial")
	model.fail_writes = false
	await click(pending_button(uid)); await frames()
	check(model.location(uid).kind == "bag" and model.item(uid) == receipt.expected, "Actual retry retrieves exact same rolled UID and affixes")
	check(model.pending_items().size() == 1, "Retrieving gear preserves distinct pending boss jewel")
	await motion(Vector2(20, 350)); await create_timer(0.21).timeout; arena.hud._process(0.001)
	check(not card.visible, "After retrieval rebuilds queue, leaving dismisses removed source card")
	panel._grid.item_activated.emit(uid); await frames()
	check(model.location(uid).kind == "equipment" and model.item(uid) == receipt.expected, "Existing bag activation equips same rewarded UID without changing its roll")
	check(model.snapshot().items.size() == prior.items.size() + 2 and Model.Rules.reason(model.snapshot()).is_empty(), "After equip every original item and both rewards still have one valid location")
	for old_uid: String in prior.items:
		if model.item(old_uid) != prior.items[old_uid]: check(false, "Original item payload changed: " + old_uid)
	repeated_death(enemy); reload_exact("Final equipment, displaced gear and pending jewel survive exact saved reload")
	arena.hud.close_panel(); check(not card.visible, "Closing inventory dismisses shared card")
	await finish()
