extends SceneTree

const LEFT_BUTTON: int = MOUSE_BUTTON_LEFT
const RIGHT_BUTTON: int = MOUSE_BUTTON_RIGHT

var arena: Node2D
var checks: int = 0
var failures: int = 0
var _last_pointer: Vector2 = Vector2.ZERO
var _move_requests: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolated: String = OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-ui-drag-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78)
		return
	root.size = Vector2i(1280, 720)
	arena = load("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	await _frames(6)
	var state = arena.state
	check(state.has_method("get_group_cast"), "Fixture uses the v0.21 canonical model")
	var group_id: String = "group_000008"
	var initial: Dictionary = state.skill_group(group_id)
	if not str(initial.main_uid).is_empty():
		var old_bag: Dictionary = state.first_bag_position(str(initial.main_uid))
		check(not old_bag.is_empty() and state.move_item(str(initial.main_uid), old_bag, state.revision(), "user://build_save.json").ok,
			"Fixture clears group eight through the canonical transfer API")
	var tornado_uid: String = state.award_gem("skill:tornado")
	check(not tornado_uid.is_empty(), "Fixture creates one real tornado gem identity")
	check(state.move_item(tornado_uid, {"kind":"skill_main","group_id":group_id}, state.revision(), "user://build_save.json").ok,
		"Fixture equips that identity in row eight using model validation")

	# Open both independent docks, as on the target layout.
	arena.hud.handle_menu_key(KEY_K, true, false)
	arena.hud.handle_menu_key(KEY_I, true, false)
	await _frames(5)
	var skills: Control = arena.hud._skill_support_panel as Control
	var rows: Control = skills._rows as Control
	var main_slot: Control = rows.find_child("MainGem_07", true, false) as Control
	var inventory: Control = arena.hud._inventory_panel as Control
	var grid: Control = inventory._grid as Control
	grid.move_requested.connect(func(_uid: String, _destination: Dictionary, _revision: int): _move_requests += 1)
	var row_scroll: ScrollContainer = rows as ScrollContainer
	check(row_scroll.get_v_scroll_bar().max_value > 0.0, "Skills rows remain scrollable beyond the visible subset")
	row_scroll.scroll_vertical = roundi(row_scroll.get_v_scroll_bar().max_value)
	var inventory_scroll: ScrollContainer = arena.hud._dock_scrolls.right as ScrollContainer
	check(inventory_scroll.get_v_scroll_bar().max_value - inventory_scroll.get_v_scroll_bar().page <= 1.0
		and grid.grid_rect().end.y <= grid.size.y + 1.0, "The whole right dock and complete 8×6 page fit without dock scrolling")
	inventory_scroll.scroll_vertical = 0
	await _frames(4)
	main_slot = rows.find_child("MainGem_07", true, false) as Control
	grid = inventory._grid as Control
	check(main_slot != null and main_slot.is_visible_in_tree(), "Group eight main slot is a visible drop target")
	check(grid != null and inventory.is_visible_in_tree(), "Right dock shows the canonical shared bag grid")
	check(arena.hud._menu_routes.snapshot().left == "skills" and arena.hud._menu_routes.snapshot().right_inventory,
		"Skills and the same inventory are open at once")
	check(grid.bag_page_count() == 2 and grid.grid_columns() == 12 and grid.grid_rows() == 10,
		"Visible bag follows the model's exact two-page 12×10 layout")
	check(arena.hud.handle_menu_key(KEY_C, true, false) == false, "Character UI routing does not consume the existing C skill key")
	var next_page: Control = inventory.find_child("NextBagPage", true, false) as Control
	var previous_page: Control = inventory.find_child("PreviousBagPage", true, false) as Control
	await _mouse_button(_center(next_page), LEFT_BUTTON, true)
	await _mouse_button(_center(next_page), LEFT_BUTTON, false)
	check(grid.bag_page() == 1, "Actual page button switches the shared bag to page two")
	await _mouse_button(_center(previous_page), LEFT_BUTTON, true)
	await _mouse_button(_center(previous_page), LEFT_BUTTON, false)
	check(grid.bag_page() == 0, "Actual page button returns the same shared bag to page one")
	inventory_scroll.scroll_vertical = roundi(inventory_scroll.get_v_scroll_bar().max_value)
	await _frames(3)
	var unload_point: Vector2 = _center(main_slot)

	# Reproduce the urgent path: right-click the eighth-row main gem into the real bag,
	# hover until its long card is present, then perform an actual threshold drag.
	await _mouse_button(unload_point, RIGHT_BUTTON, true)
	await _mouse_button(unload_point, RIGHT_BUTTON, false)
	await _frames(4)
	check(state.location(tornado_uid).get("kind", "") == "bag", "Real right-click unload places row-eight tornado in the shared bag")
	main_slot = rows.find_child("MainGem_07", true, false) as Control
	grid = inventory._grid as Control
	var first_page: int = int(state.location(tornado_uid).get("page", 0))
	await _inventory_page(inventory, grid, first_page)
	var source_point: Vector2 = _bag_center(grid, tornado_uid)
	await _mouse_motion(source_point, 0)
	await _frames(3)
	check(arena.hud._item_hover.visible, "Moving onto the real bag item opens the long hover card")
	main_slot = rows.find_child("MainGem_07", true, false) as Control
	var target_point: Vector2 = _center(main_slot)
	var valid_drag: Dictionary = await _drag_sequence("hovered row-eight tornado -> main", source_point, target_point, tornado_uid, true)
	check(bool(valid_drag.dragging), "Viewport begins the hovered main-gem drag")
	check(str(valid_drag.uid) == tornado_uid, "Viewport drag payload keeps the real gem UID")
	check(str(valid_drag.hover_path).contains("MainGem_07"), "Pointer actually reaches the row-eight main target")
	check(not arena.hud._item_hover.visible, "HUD dismisses and keeps the hover card closed during drag")
	check(state.location(tornado_uid).get("kind", "") == "skill_main" and state.location(tornado_uid).get("group_id", "") == group_id,
		"Physical press-motion-release installs that exact UID into the main slot")

	# Run the quick no-card path too, then prove the model rejects a support gem in a main slot.
	main_slot = rows.find_child("MainGem_07", true, false) as Control
	var second_unload_point: Vector2 = _center(main_slot)
	await _mouse_button(second_unload_point, RIGHT_BUTTON, true)
	await _mouse_button(second_unload_point, RIGHT_BUTTON, false)
	await _frames(4)
	main_slot = rows.find_child("MainGem_07", true, false) as Control
	grid = inventory._grid as Control
	source_point = _bag_center(grid, tornado_uid)
	var quick_drag: Dictionary = await _drag_sequence("quick row-eight tornado -> main", source_point, _center(main_slot), tornado_uid, false)
	check(bool(quick_drag.dragging) and str(quick_drag.uid) == tornado_uid, "Quick drag starts from bag without a prior hover card")
	check(state.location(tornado_uid).get("kind", "") == "skill_main", "Quick threshold drag restores the main gem")
	main_slot = rows.find_child("MainGem_07", true, false) as Control

	var support_uid: String = state.award_gem("support:focus")
	await _frames(3)
	main_slot = rows.find_child("MainGem_07", true, false) as Control
	grid = inventory._grid as Control
	var support_main: Dictionary = await _drag_sequence("support gem -> main (invalid)", _bag_center(grid, support_uid), _center(main_slot), support_uid, false)
	check(str(support_main.hover_path).contains("MainGem_07"), "Invalid support attempt hovers the intended main slot")
	check(state.location(support_uid).get("kind", "") == "bag", "Main slot rejects a real support gem through the parent validator")

	# A legal support drop and the reverse slot-to-bag path use the same UID and revision.
	var support_slot: Control = rows.find_child("SupportGem_07_0", true, false) as Control
	var support_drag: Dictionary = await _drag_sequence("support gem -> support hole", _bag_center(grid, support_uid), _center(support_slot), support_uid, false)
	check(str(support_drag.hover_path).contains("SupportGem_07_0"), "Pointer reaches the legal support hole")
	check(state.location(support_uid).get("kind", "") == "skill_support" and int(state.location(support_uid).get("index", -1)) == 0,
		"Model accepts the real support gem in the chosen support hole")
	support_slot = rows.find_child("SupportGem_07_0", true, false) as Control
	grid = inventory._grid as Control
	var bag_destination: Dictionary = state.first_bag_position(support_uid)
	await _inventory_page(inventory, grid, int(bag_destination.get("page", 0)))
	var bag_target: Vector2 = _cell_center(grid, Vector2i(int(bag_destination.x), int(bag_destination.y)))
	var reverse_drag: Dictionary = await _drag_sequence("support slot -> right bag", _center(support_slot), bag_target, support_uid, false)
	check(str(reverse_drag.hover_path).contains("SharedCanonicalBagGrid"), "Pointer reaches the right bag after leaving the support slot")
	check(int(reverse_drag.move_requests) == 1, "Viewport release emits one canonical bag move request")
	check(state.location(support_uid).get("kind", "") == "bag", "Support slot returns to the shared bag through a physical drag")

	# Canvas-scale and post-scroll coordinates are captured from the controls themselves.
	arena.visual_settings.ui_scale = 1.1
	arena.visual_settings.font_scale = 1.2
	arena.hud._apply_presentation()
	await _frames(4)
	grid = inventory._grid as Control
	var scroll: ScrollContainer = arena.hud._dock_scrolls.right as ScrollContainer
	var scroll_before: int = scroll.scroll_vertical
	scroll.scroll_vertical = roundi(scroll.get_v_scroll_bar().max_value)
	row_scroll.scroll_vertical = roundi(row_scroll.get_v_scroll_bar().max_value)
	await _frames(2)
	support_slot = rows.find_child("SupportGem_07_1", true, false) as Control
	var scaled_drag: Dictionary = await _drag_sequence("scaled bag -> support hole", _bag_center(grid, support_uid), _center(support_slot), support_uid, false)
	check(bool(scaled_drag.dragging), "Scaled 110% UI still dispatches the source event chain")
	check(state.location(support_uid).get("kind", "") == "skill_support" and int(state.location(support_uid).get("index", -1)) == 1,
		"Canvas-space bag-to-support drag remains valid at 110% UI scale")
	check(scroll.scroll_vertical >= scroll_before, "Post-scroll test keeps the real dock ScrollContainer state")
	var left_panel: Control = arena.hud._dock_roots.left.get_child(0) as Control
	var right_panel: Control = arena.hud._dock_roots.right.get_child(0) as Control
	var left_rect: Rect2 = left_panel.get_global_rect()
	var right_rect: Rect2 = right_panel.get_global_rect()
	print("viewport_layout logical_size=%s left=%s right=%s anchors=%s..%s/%s..%s" % [root.get_visible_rect().size, left_rect, right_rect, left_panel.anchor_left, left_panel.anchor_right, right_panel.anchor_left, right_panel.anchor_right])
	check(absf((left_panel.anchor_right - left_panel.anchor_left) - 1.0 / 3.0) < 0.001
		and absf((right_panel.anchor_right - right_panel.anchor_left) - 1.0 / 3.0) < 0.001,
		"Left and right dock widths remain one third at any viewport resolution")
	check(left_panel.anchor_right <= right_panel.anchor_left, "Dock anchors leave the center battle column free")
	check(arena.hud.is_blocking(), "Any dock still blocks combat while the route remains open")

	print("Docked inventory drag events: %d checks, %d failures" % [checks, failures])
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _drag_sequence(label: String, source: Vector2, target: Vector2, uid: String, hover_first: bool) -> Dictionary:
	if not hover_first:
		arena.hud._dismiss_item_hover()
	await _mouse_button(source, LEFT_BUTTON, true)
	await _mouse_motion(target, MOUSE_BUTTON_MASK_LEFT)
	await _frames(2)
	var drag_value: Variant = root.gui_get_drag_data()
	var hovered: Control = root.gui_get_hovered_control() as Control
	var drag_active: bool = root.gui_is_dragging()
	var drag_uid: String = str(drag_value.get("uid", "")) if drag_value is Dictionary else ""
	var hover_path: String = str(hovered.get_path()) if is_instance_valid(hovered) else "<none>"
	print("viewport_drag %s gui_is_dragging=%s uid=%s hovered=%s" % [label, drag_active, drag_uid, hover_path])
	if drag_active:
		check(drag_uid == uid, "%s keeps the requested real UID in Viewport drag data" % label)
	await _mouse_button(target, LEFT_BUTTON, false)
	await _frames(3)
	return {"dragging":drag_active, "uid":drag_uid, "hover_path":hover_path, "released_dragging":root.gui_is_dragging(), "move_requests":_move_requests}


func _inventory_page(panel: Control, grid: Control, page: int) -> void:
	var current: int = int(grid.bag_page())
	if current != page:
		panel._turn_page(page - current)
	await _frames(2)


func _bag_center(grid: Control, uid: String) -> Vector2:
	var rect: Rect2 = grid.item_rect(uid)
	return grid.get_global_transform_with_canvas() * rect.get_center()


func _cell_center(grid: Control, cell: Vector2i) -> Vector2:
	return grid.get_global_transform_with_canvas() * grid.cell_rect(cell).get_center()


func _center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func _mouse_button(position: Vector2, button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_last_pointer = position
	await process_frame


func _mouse_motion(position: Vector2, button_mask: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = button_mask
	event.relative = position - _last_pointer
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_last_pointer = position
	await process_frame


func _frames(count: int) -> void:
	for unused: int in range(count):
		await process_frame


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
