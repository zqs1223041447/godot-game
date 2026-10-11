extends "res://tests/flask_purchase_transactions_test.gd"
## Canonical Main regression: destructive actions must follow visible bag selection.
var arena: Node
var panel: Control
var model: Model
func authority() -> PackedByteArray:
	return var_to_bytes([model.snapshot(), FileAccess.get_file_as_bytes(PATH), model.successful_saves, arena.rng.state])
func select(uid: String) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = panel._grid.item_rect(uid).get_center()
	panel._grid._gui_input(click)
func cleared(label: String) -> void:
	check(panel._selected_uid.is_empty() and panel._grid._selected_uid.is_empty(), label + ": both selection owners clear")
	check(panel._discard.disabled, label + ": discard disabled")
	check(panel._pending_discard.is_empty() and panel._pending_craft.is_empty() and not panel._craft_dialog.visible, label + ": pending confirmation cancelled")
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-inventory-page-selection-") or not OS.get_user_data_dir().begins_with(isolated + "/") or FileAccess.file_exists(PATH): quit(78); return
	model = Model.new()
	check(model.save_build(PATH) == OK, "Fresh isolated canonical save")
	arena = load("res://scenes/main.tscn").instantiate()
	arena.state = model
	arena.build_save_path = PATH
	root.add_child(arena)
	arena.set_process(false); arena.set_physics_process(false); arena.hud.set_process(false)
	arena.hud.open_panel("inventory")
	await process_frame; await process_frame
	panel = arena.hud._inventory_panel
	var uid := ""
	for entry: Dictionary in panel._grid._items:
		if model.item(entry.uid).kind == "jewel" and model.can_discard_item(entry.uid): uid = entry.uid; break
	check(not uid.is_empty() and panel._bag_layout.pages > 1, "Starter jewel and second page exist")
	if uid.is_empty(): await finish(); return
	select(uid)
	check(panel._selected_uid == uid and panel._grid._selected_uid == uid and not panel._discard.disabled, "Grid click selects actual starter jewel")
	var before := authority()
	panel._refresh_dirty = true; panel.refresh()
	check(panel._selected_uid == uid and panel._grid._selected_uid == uid and authority() == before, "Ordinary refresh preserves valid selection without transaction")
	panel._next_page.pressed.emit()
	cleared("Page forward")
	check(authority() == before, "Page forward never changes model, disk, save count or RNG")
	panel._previous_page.pressed.emit()
	cleared("Page back does not resurrect selection")
	check(authority() == before, "Page back never changes authority")
	if not failures.is_empty(): await finish(); return
	select(uid); panel._discard.pressed.emit()
	check(panel._craft_dialog.visible and panel._pending_discard.uid == uid, "Visible selection opens actual discard confirmation")
	panel._next_page.pressed.emit()
	cleared("Page change interrupts discard")
	panel._craft_dialog.confirmed.emit()
	check(authority() == before, "Late discard confirmation cannot consume prior-page item")
	panel._previous_page.pressed.emit(); select(uid)
	panel._request_craft("salvage", uid, model.item(uid).payload)
	check(panel._craft_dialog.visible and not panel._pending_craft.is_empty(), "Visible starter jewel opens actual salvage quote")
	var quote: Dictionary = panel._pending_craft.get("quote", {}).duplicate(true)
	var source: Dictionary = model.item(uid).payload.duplicate(true)
	panel._next_page.pressed.emit()
	cleared("Page change interrupts crafting")
	check(panel._craft_quotes.is_empty(), "Invisible selection retains no crafting quotes")
	panel._craft_dialog.confirmed.emit()
	check(authority() == before, "Late crafting confirmation cannot consume prior-page item")
	check(not quote.is_empty() and not model.execute_crafting(quote.handle, source).ok and authority() == before, "Cancelled crafting handle is revoked without transaction")
	panel._previous_page.pressed.emit(); select(uid); panel._discard.pressed.emit()
	var destination := {"kind":"bag", "page":1, "x":0, "y":0}
	check(model.can_move_item(uid, destination, model.revision()), "Empty second-page destination accepts starter jewel")
	var saves := model.successful_saves
	check(model.move_item(uid, destination, model.revision(), PATH).ok, "Canonical move takes selected item off visible page")
	cleared("Off-page move interrupts selection and discard")
	check(model.successful_saves == saves + 1, "Only authorized move commits once")
	before = authority(); panel._craft_dialog.confirmed.emit()
	check(authority() == before and model.location(uid) == destination, "Late confirmation after move is inert")
	panel._next_page.pressed.emit(); select(uid)
	before = authority(); panel._refresh_dirty = true; panel.refresh()
	check(panel._selected_uid == uid and panel._grid._selected_uid == uid and authority() == before, "New-page selection remains usable and stable")
	var same_page := {"kind":"bag", "page":1, "x":2, "y":0}
	check(model.move_item(uid, same_page, model.revision(), PATH).ok, "Canonical same-page move succeeds")
	check(panel._selected_uid == uid and panel._grid._selected_uid == uid and not panel._discard.disabled, "Visible item remains selected after same-page move")
	await finish()
func finish() -> void:
	print("INVENTORY_PAGE_SELECTION ", JSON.stringify({"checks":checks, "failures":failures}))
	if is_instance_valid(arena): arena.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
