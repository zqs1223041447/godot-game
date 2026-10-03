extends SceneTree
## Standalone contract and routed-input checks; does not load BuildState or the main scene.
const Grid = preload("res://scripts/ui/unified_bag_grid.gd")

var checks: int = 0
var failures: int = 0
var grid: Variant
var selected: Array[String] = []
var activated: Array[String] = []
var hovered: Array[Dictionary] = []
var hover_left_count: int = 0
var moves: Array[Dictionary] = []
var validator_calls: Array[Dictionary] = []
var reject_drop: bool = false
var synthetic_pointer: Vector2 = Vector2.ZERO


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	grid = Grid.new()
	grid.name = "UnifiedBagGridTestControl"
	grid.position = Vector2(24.0, 32.0)
	grid.size = Vector2(520.0, 352.0)
	root.add_child(grid)
	grid.item_selected.connect(_on_selected)
	grid.item_activated.connect(_on_activated)
	grid.item_hovered.connect(_on_hovered)
	grid.hover_left.connect(_on_hover_left)
	grid.move_requested.connect(_on_move_requested)
	grid.set_drop_validator(_validate_drop)
	await process_frame

	_test_snapshot_copy()
	await _test_kind_protocol()
	await process_frame
	_test_full_grid_geometry()
	_test_shrink_geometry()
	_test_drag_contract()
	await _test_routed_selection_and_hover()
	await _test_routed_drag_revision_invalidation()

	grid.queue_free()
	await process_frame
	print("unified_bag_grid_test: %d checks, %d failures; pointer paths used Input.parse_input_event and Viewport.push_input. Headless checks do not verify rendered pixels." % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _entry(uid: String, cell: Vector2i, dimensions: Vector2i = Vector2i.ONE,
		kind: String = "equipment", icon: Texture2D = null) -> Dictionary:
	return {
		"uid": uid,
		"kind": kind,
		"size": dimensions,
		"cell": cell,
		"art": {"id": "swift_blade", "slot": "weapon", "nested": {"values": [1, 2]}},
		"icon": icon,
		"accent": Color("8dbaff"),
		"short_name": "短刃",
	}


func _test_snapshot_copy() -> void:
	var image: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color("aa6644"))
	var gem_icon: Texture2D = ImageTexture.create_from_image(image)
	var supplied: Dictionary = _entry("bag-copy", Vector2i(2, 1), Vector2i.ONE, "skill_gem", gem_icon)
	var nested_art: Dictionary = supplied["art"]
	grid.set_items([supplied], 7)
	nested_art["nested"]["values"][0] = 99
	supplied["cell"] = Vector2i(9, 7)
	_expect(grid._items.size() == 1 and grid._items[0]["cell"] == Vector2i(2, 1), "set_items copies the entry rather than retaining its source dictionary")
	_expect(grid._items[0]["art"]["nested"]["values"] == [1, 2], "set_items recursively copies nested art dictionaries and arrays")
	_expect(grid._items[0]["icon"] == gem_icon, "Texture2D icon resource remains available to the renderer")
	_expect(grid._revision == 7, "set_items records the supplied revision")
	var invalid: Dictionary = _entry("bad-size", Vector2i(11, 7), Vector2i(2, 1))
	var missing_schema: Dictionary = {"uid": "not-a-bag-record"}
	grid.set_items([supplied, invalid, missing_schema], 8)
	_expect(grid._items.size() == 1 and grid._items[0]["uid"] == "bag-copy", "invalid and out-of-grid records are not presented")


func _test_kind_protocol() -> void:
	var image: Image = Image.create(6, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color("b46b52"))
	var icon: Texture2D = ImageTexture.create_from_image(image)
	var active: Dictionary = _entry("active-skill", Vector2i(0, 0), Vector2i.ONE, "skill_gem", icon)
	var support: Dictionary = _entry("support-skill", Vector2i(1, 0), Vector2i.ONE, "support_gem", icon)
	var iconless_active: Dictionary = _entry("missing-active-icon", Vector2i(2, 0), Vector2i.ONE, "skill_gem")
	var iconless_support: Dictionary = _entry("missing-support-icon", Vector2i(3, 0), Vector2i.ONE, "support_gem")
	iconless_active["short_name"] = "技能"
	iconless_support["short_name"] = "辅助"
	grid.set_items([active, support, iconless_active, iconless_support], 9)
	_expect(grid._items.size() == 4, "both gem kinds remain valid whether their optional icon is present or null")
	_expect(grid._items[0]["icon"] is Texture2D and grid._items[1]["icon"] is Texture2D, "active and support gem snapshots retain supplied real Texture2D resources")
	_expect(grid._items[2]["icon"] == null and grid._items[3]["icon"] == null, "iconless active and support gem snapshots retain their null icon")
	_expect(grid._is_icon_entry("skill_gem") and grid._is_icon_entry("support_gem"), "active and support gem kinds use the icon-or-neutral-placeholder draw branch")
	_expect(not grid._is_icon_entry("equipment") and not grid._is_icon_entry("jewel"), "equipment and jewel kinds keep the EquipmentArt draw branch")
	_expect(grid.item_rect("missing-active-icon").size == Vector2(42.0, 42.0), "iconless active gem keeps its occupied grid rectangle")
	_expect(grid.item_rect("missing-support-icon").size == Vector2(42.0, 42.0), "iconless support gem keeps its occupied grid rectangle")
	_expect(grid.item_at_position(grid.cell_rect(Vector2i(2, 0)).get_center()) == "missing-active-icon"
		and grid.item_at_position(grid.cell_rect(Vector2i(3, 0)).get_center()) == "missing-support-icon", "iconless gem entries remain hit-testable")
	await process_frame # Runs both textured and iconless gem kinds through the CanvasItem draw callback.
	var drag_payload: Variant = grid._get_drag_data(grid.cell_rect(Vector2i(2, 0)).get_center())
	_expect(drag_payload is Dictionary and drag_payload.get("uid") == "missing-active-icon" and drag_payload.get("revision") == 9,
		"iconless active gem can start a revision-bound drag")
	if drag_payload is Dictionary:
		var destination_point: Vector2 = grid.cell_rect(Vector2i(4, 0)).get_center()
		_expect(grid._can_drop_data(destination_point, drag_payload), "iconless active gem remains eligible for a validated drop")
		var moves_before: int = moves.size()
		grid._drop_data(destination_point, drag_payload)
		_expect(moves.size() == moves_before + 1 and moves.back()["uid"] == "missing-active-icon",
			"iconless gem drop still emits its UID move request")
	var support_drag: Variant = grid._get_drag_data(grid.cell_rect(Vector2i(3, 0)).get_center())
	_expect(support_drag is Dictionary and support_drag.get("uid") == "missing-support-icon" and support_drag.get("revision") == 9,
		"iconless support gem can start a revision-bound drag")
	if support_drag is Dictionary:
		var support_destination: Vector2 = grid.cell_rect(Vector2i(5, 0)).get_center()
		_expect(grid._can_drop_data(support_destination, support_drag), "iconless support gem remains eligible for a validated drop")
		var support_moves_before: int = moves.size()
		grid._drop_data(support_destination, support_drag)
		_expect(moves.size() == support_moves_before + 1 and moves.back()["uid"] == "missing-support-icon",
			"iconless support gem drop still emits its UID move request")

	var equipment_with_icon: Dictionary = _entry("equipment-art", Vector2i(0, 1), Vector2i.ONE, "equipment", icon)
	var jewel_with_icon: Dictionary = _entry("jewel-art", Vector2i(1, 1), Vector2i.ONE, "jewel", icon)
	grid.set_items([equipment_with_icon, jewel_with_icon], 10)
	_expect(grid._items.size() == 2 and not grid._is_icon_entry(grid._items[0]["kind"])
		and not grid._is_icon_entry(grid._items[1]["kind"]), "equipment and jewel draw art even if an icon field is present")
	await process_frame

	var unknown: Dictionary = _entry("unknown-kind", Vector2i.ZERO, Vector2i.ONE, "gem", icon)
	var old_alias: Dictionary = _entry("unknown-alias", Vector2i(1, 0), Vector2i.ONE, "gemstone", icon)
	grid.set_items([unknown, old_alias], 11)
	_expect(grid._items.is_empty(), "unknown kinds and uncontracted aliases are rejected instead of falling through to equipment art")
	_expect(grid.item_at_position(grid.cell_rect(Vector2i.ZERO).get_center()).is_empty(), "rejected kind cannot be hit or presented as an item")
	await process_frame


func _test_full_grid_geometry() -> void:
	var entries: Array[Dictionary] = []
	for y: int in range(8):
		for x: int in range(12):
			entries.append(_entry("cell-%02d-%02d" % [x, y], Vector2i(x, y)))
	grid.size = Vector2(520.0, 352.0)
	grid.set_items(entries, 20)
	_expect(is_equal_approx(grid.grid_cell_size(), 42.0), "default logical cell pitch is 42")
	_expect(grid.grid_rect().position == Vector2(8.0, 8.0), "default board starts eight logical pixels from each edge")
	_expect(grid.grid_rect().size == Vector2(504.0, 336.0), "default board has 12 by 8 cells")
	for y: int in range(8):
		for x: int in range(12):
			var cell := Vector2i(x, y)
			var center: Vector2 = grid.cell_rect(cell).get_center()
			_expect(grid.cell_at_position(center) == cell, "cell center maps to itself: %s" % cell)
			_expect(grid.item_at_position(center) == "cell-%02d-%02d" % [x, y], "hit test covers all 96 cell centers: %s" % cell)
	_expect(grid.cell_at_position(Vector2(8.0, 8.0)) == Vector2i.ZERO, "top-left board edge belongs to first cell")
	_expect(grid.cell_at_position(grid.grid_rect().end - Vector2(0.01, 0.01)) == Vector2i(11, 7), "bottom-right interior belongs to last cell")
	_expect(grid.cell_at_position(grid.grid_rect().end) == Vector2i(-1, -1), "right and bottom board edges are exclusive")
	_expect(grid.cell_at_position(Vector2(7.99, 8.0)) == Vector2i(-1, -1), "eight-pixel outer inset is not a hit target")


func _test_shrink_geometry() -> void:
	grid.size = Vector2(400.0, 240.0)
	_expect(is_equal_approx(grid.grid_cell_size(), 28.0), "small allocation proportionally shrinks cells to the limiting height")
	_expect(grid.grid_rect().position.y == 8.0 and is_equal_approx(grid.grid_rect().end.y, 232.0), "shrunken grid preserves eight-pixel top and bottom insets")
	_expect(is_equal_approx(grid.grid_rect().position.x, 32.0), "shrunken board stays centered with at least the requested side inset")
	for cell: Vector2i in [Vector2i.ZERO, Vector2i(11, 0), Vector2i(0, 7), Vector2i(11, 7), Vector2i(5, 4)]:
		var center: Vector2 = grid.cell_rect(cell).get_center()
		_expect(grid.cell_at_position(center) == cell, "shrunk coordinate and hit test share one cell pitch: %s" % cell)
	_expect(grid.item_at_position(grid.cell_rect(Vector2i(11, 7)).get_center()) == "cell-11-07", "shrunk bottom-right hit resolves the matching entry")


func _test_drag_contract() -> void:
	grid.size = Vector2(520.0, 352.0)
	var large: Dictionary = _entry("multi-cell", Vector2i(9, 5), Vector2i(2, 3), "jewel")
	grid.set_items([large], 30)
	var source_point: Vector2 = grid.cell_rect(Vector2i(10, 7)).get_center()
	var payload: Variant = grid._get_drag_data(source_point)
	_expect(payload is Dictionary and payload.size() == 4, "drag payload contains exactly four fields")
	_expect(payload is Dictionary and payload.get("type") == "unified_item" and payload.get("uid") == "multi-cell", "drag payload has the canonical item type and stable uid")
	_expect(payload is Dictionary and payload.get("revision") == 30 and payload.get("grab_offset") == Vector2i(1, 2), "multi-cell grab offset and source revision are captured")
	if not payload is Dictionary:
		return
	var target_point: Vector2 = grid.cell_rect(Vector2i(11, 7)).get_center()
	validator_calls.clear()
	reject_drop = false
	_expect(grid._can_drop_data(target_point, payload), "validator-accepted last-cell drop is valid for the 2 by 3 item")
	_expect(grid._preview_valid and grid._preview_uid == "multi-cell" and grid._preview_destination == Vector2i(10, 5), "accepted drop preview is green at offset-adjusted destination")
	_expect(validator_calls.size() == 1 and validator_calls[0]["destination"] == {"kind": "bag", "x": 10, "y": 5}, "validator receives the exact bag destination schema")
	var moves_before: int = moves.size()
	grid._drop_data(target_point, payload)
	grid._drop_data(target_point, payload)
	_expect(moves.size() == moves_before + 1, "a valid drop emits move_requested only once")
	if moves.size() > moves_before:
		_expect(moves.back() == {"uid": "multi-cell", "destination": {"kind": "bag", "x": 10, "y": 5}, "revision": 30}, "move_requested carries uid, destination, and source revision")
	var rejection_payload: Variant = grid._get_drag_data(source_point)

	var extra_field: Dictionary = payload.duplicate(true)
	extra_field["source"] = "forbidden"
	_expect(not grid._can_drop_data(target_point, extra_field), "payload with an extra field is rejected")
	_expect(not grid._preview_valid and grid._preview_uid == "multi-cell", "known item with malformed payload shows a red preview")
	var missing_field: Dictionary = payload.duplicate(true)
	missing_field.erase("revision")
	_expect(not grid._can_drop_data(target_point, missing_field), "payload missing a field is rejected")
	var wrong_offset: Dictionary = payload.duplicate(true)
	wrong_offset["grab_offset"] = Vector2i(2, 0)
	_expect(not grid._can_drop_data(target_point, wrong_offset), "grab offset outside item footprint is rejected")
	var wrong_type: Dictionary = payload.duplicate(true)
	wrong_type["revision"] = "30"
	_expect(not grid._can_drop_data(target_point, wrong_type), "non-integer revision is rejected")

	var edge_payload: Dictionary = payload.duplicate(true)
	edge_payload["grab_offset"] = Vector2i.ZERO
	var edge_point: Vector2 = grid.cell_rect(Vector2i(11, 7)).get_center()
	_expect(not grid._can_drop_data(edge_point, edge_payload), "multi-cell footprint may not extend beyond 12 by 8 grid")
	_expect(not grid._preview_valid, "out-of-bounds drop preview is red")

	reject_drop = true
	_expect(not grid._can_drop_data(target_point, rejection_payload), "parent validator rejection refuses the drop")
	_expect(not grid._preview_valid and grid._preview_uid == "multi-cell", "parent-rejected drop retains a red item preview")
	var moves_after_rejection: int = moves.size()
	grid._drop_data(target_point, rejection_payload)
	_expect(moves.size() == moves_after_rejection, "validator rejection never emits move_requested")

	reject_drop = false
	grid.set_items([large], 31)
	_expect(not grid._can_drop_data(target_point, payload), "old drag payload is rejected after set_items advances revision")
	_expect(not grid._preview_valid, "stale payload preview is red")
	var moves_after_stale: int = moves.size()
	grid._drop_data(target_point, rejection_payload)
	_expect(moves.size() == moves_after_stale, "stale revision cannot request a move")


func _test_routed_selection_and_hover() -> void:
	var click_entry: Dictionary = _entry("click-target", Vector2i(0, 0))
	var other_entry: Dictionary = _entry("second-target", Vector2i(3, 1))
	var large_entry: Dictionary = _entry("routed-multi", Vector2i(1, 1), Vector2i(2, 2))
	grid.set_items([click_entry, other_entry, large_entry], 40)
	selected.clear()
	activated.clear()
	hovered.clear()
	hover_left_count = 0
	var logical_point: Vector2 = grid.get_global_transform() * grid.cell_rect(Vector2i.ZERO).get_center()
	await _move_pointer(logical_point)
	_expect(root.gui_get_hovered_control() == grid, "Viewport routes the pointer to the actual Control")
	_expect(not hovered.is_empty() and hovered.back()["uid"] == "click-target", "real pointer routing emits item_hovered")
	if not hovered.is_empty():
		var expected_anchor: Rect2 = grid.get_global_transform() * grid.item_rect("click-target")
		_expect(hovered.back()["anchor"] == expected_anchor, "hover anchor is the get_global_transform canvas-logical rectangle")
		_expect(hovered.back()["anchor"].size == Vector2(42.0, 42.0), "hover anchor is not multiplied into 2K physical pixels")
	await _click_at(logical_point, MOUSE_BUTTON_LEFT, false)
	_expect(selected == ["click-target"] and activated.is_empty(), "routed left click selects without deciding parent behavior")
	await _click_at(logical_point, MOUSE_BUTTON_LEFT, true)
	_expect(activated == ["click-target"], "routed double-click emits item_activated")
	await _click_at(logical_point, MOUSE_BUTTON_RIGHT, false)
	_expect(activated == ["click-target", "click-target"], "routed right-click emits item_activated")
	var empty_cell: Vector2 = grid.get_global_transform() * grid.cell_rect(Vector2i(11, 7)).get_center()
	await _move_pointer(empty_cell)
	_expect(hover_left_count == 1, "routed pointer leaving an item emits hover_left")
	_expect(grid.item_at_position(grid.cell_rect(Vector2i(2, 2)).get_center()) == "routed-multi", "multi-cell hit routes through the common cell geometry")


func _test_routed_drag_revision_invalidation() -> void:
	var click_entry: Dictionary = _entry("click-target", Vector2i(0, 0))
	var large_entry: Dictionary = _entry("routed-multi", Vector2i(1, 1), Vector2i(2, 2))
	var entries: Array[Dictionary] = [click_entry, large_entry]
	grid.set_items(entries, 50)
	var source: Vector2 = grid.get_global_transform() * grid.cell_rect(Vector2i(2, 2)).get_center()
	var destination: Vector2 = grid.get_global_transform() * grid.cell_rect(Vector2i(11, 7)).get_center()
	var move_count: int = moves.size()
	await _move_pointer(source)
	await _send_button(source, MOUSE_BUTTON_LEFT, true)
	await process_frame
	await _move_pointer(destination, MOUSE_BUTTON_MASK_LEFT)
	await process_frame
	var drag_started: bool = root.gui_is_dragging()
	_expect(drag_started, "Viewport's native GUI drag routing starts a drag from the multi-cell item")
	if drag_started:
		grid.set_items(entries, 51)
		await _move_pointer(destination, MOUSE_BUTTON_MASK_LEFT)
		_expect(not grid._preview_valid and grid._preview_uid == "routed-multi", "revision change turns the live drag preview red")
		await _send_button(destination, MOUSE_BUTTON_LEFT, false)
		await process_frame
		await process_frame
		_expect(moves.size() == move_count, "revision update during a live GUI drag blocks the old payload")
	else:
		await _send_button(destination, MOUSE_BUTTON_LEFT, false)
		var stale_payload: Dictionary = {"type": "unified_item", "uid": "routed-multi", "revision": 50, "grab_offset": Vector2i(1, 1)}
		grid.set_items(entries, 51)
		_expect(not grid._can_drop_data(grid.cell_rect(Vector2i(11, 7)).get_center(), stale_payload), "fallback verifies stale revision on the native drop contract")
		_expect(moves.size() == move_count, "failed native drag start still leaves no move request")
	_expect(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "routed test releases the synthetic pointer button")
	if not drag_started:
		return
	grid.set_items(entries, 52)
	var valid_move_count: int = moves.size()
	await _move_pointer(source)
	await _send_button(source, MOUSE_BUTTON_LEFT, true)
	await _move_pointer(destination, MOUSE_BUTTON_MASK_LEFT)
	var valid_drag_started: bool = root.gui_is_dragging()
	_expect(valid_drag_started, "Viewport starts a fresh native drag after the snapshot refresh")
	if valid_drag_started:
		await _send_button(destination, MOUSE_BUTTON_LEFT, false)
		await process_frame
		await process_frame
		_expect(moves.size() == valid_move_count + 1, "native accepted drop emits exactly one move request")
		if moves.size() > valid_move_count:
			_expect(moves.back() == {"uid": "routed-multi", "destination": {"kind": "bag", "x": 10, "y": 6}, "revision": 52}, "native move request preserves the offset-adjusted destination and revision")
	else:
		await _send_button(destination, MOUSE_BUTTON_LEFT, false)
	_expect(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "valid routed drag releases the synthetic pointer button")


func _move_pointer(point: Vector2, button_mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - synthetic_pointer
	event.button_mask = button_mask
	synthetic_pointer = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame


func _send_button(point: Vector2, button: MouseButton, pressed: bool, double_click: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.global_position = point
	event.pressed = pressed
	event.double_click = double_click
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame


func _click_at(point: Vector2, button: MouseButton, double_click: bool) -> void:
	await _move_pointer_via_viewport(point)
	await _send_button(point, button, true, double_click)
	await _send_button(point, button, false)


func _move_pointer_via_viewport(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)
	await process_frame


func _on_selected(uid: String) -> void:
	selected.append(uid)


func _on_activated(uid: String) -> void:
	activated.append(uid)


func _on_hovered(uid: String, anchor: Rect2) -> void:
	hovered.append({"uid": uid, "anchor": anchor})


func _on_hover_left() -> void:
	hover_left_count += 1


func _on_move_requested(uid: String, destination: Dictionary, source_revision: int) -> void:
	moves.append({"uid": uid, "destination": destination, "revision": source_revision})


func _validate_drop(uid: String, destination: Dictionary, source_revision: int) -> bool:
	validator_calls.append({"uid": uid, "destination": destination.duplicate(true), "revision": source_revision})
	return not reject_drop
