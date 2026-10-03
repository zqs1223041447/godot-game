extends SceneTree

const MainScene = preload("res://scenes/main.tscn")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_layout(Vector2i(1280, 720), 1.0, 1.0)
	await _check_layout(Vector2i(1280, 720), 1.1, 1.2)
	await _check_layout(Vector2i(2560, 1440), 1.0, 1.0)
	await _check_layout(Vector2i(2560, 1440), 1.1, 1.2)
	await _check_recovery_access()
	print("Docked layout geometry: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _check_layout(view_size: Vector2i, ui_scale: float, font_scale: float) -> void:
	var viewport := root
	viewport.size = view_size
	var arena: Node2D = MainScene.instantiate() as Node2D
	viewport.add_child(arena)
	await _frames(5)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.visual_settings.ui_scale = ui_scale
	arena.visual_settings.font_scale = font_scale
	arena.hud._apply_presentation()
	arena.hud.handle_menu_key(KEY_K, true, false)
	arena.hud.handle_menu_key(KEY_I, true, false)
	await _frames(5)

	var screen_rect: Rect2 = viewport.get_visible_rect()
	var right_root: Control = arena.hud._dock_roots.right as Control
	var right_panel: Control = right_root.get_child(0) as Control
	var right_scroll: ScrollContainer = arena.hud._dock_scrolls.right as ScrollContainer
	var inventory: Control = arena.hud._inventory_panel as Control
	var equipment: Control = inventory.find_child("EquipmentSlotGrid", true, false) as Control
	var page_bar: Control = inventory.find_child("BagPageControls", true, false) as Control
	var bag_grid: Control = inventory._grid as Control
	var equip_rect: Rect2 = equipment.get_global_rect()
	var page_rect: Rect2 = page_bar.get_global_rect()
	var bag_rect: Rect2 = bag_grid.get_global_transform_with_canvas() * bag_grid.grid_rect()
	var right_rect: Rect2 = right_panel.get_global_rect()
	var right_scroll_rect: Rect2 = right_scroll.get_global_rect()
	var dock_ratio: float = (equip_rect.end.y-right_rect.position.y) / right_rect.size.y
	var page_ratio: float = (page_rect.end.y-right_rect.position.y) / right_rect.size.y
	var right_scroll_range: float = maxf(0.0, right_scroll.get_v_scroll_bar().max_value - right_scroll.get_v_scroll_bar().page)
	check(viewport.size == view_size, "Real root window uses the requested %d×%d output" % [view_size.x, view_size.y])
	check(right_rect.size.x <= screen_rect.size.x / 3.0 + 0.1 and right_rect.end.x <= screen_rect.end.x+0.1, "Right dock stays within one-third screen width and actual logical screen boundary")
	var bag_header: Control = inventory.find_child("BagHeader",true,false)
	check(dock_ratio <= 0.34 and page_ratio <= 0.44 and bag_header.get_global_rect().position.y >= equip_rect.end.y-0.1, "Equipment stays in the upper third; inventory operations and page controls occupy the following bag area")
	check(right_scroll_range <= 1.0, "Right inventory content needs no full-dock vertical scroll")
	check(bag_grid.grid_columns() == 12 and bag_grid.grid_rows() == 10
		and bag_grid.cell_rect(Vector2i(11, 9)).end.y <= bag_grid.size.y + 1.0,
		"Complete 12×10 bag page fits inside its grid viewport")
	var expected_pitch: float = maxf(0.0, minf(64.0, minf((bag_grid.size.x - 16.0) / 12.0, (bag_grid.size.y - 16.0) / 10.0)))
	check(is_equal_approx(bag_grid.grid_cell_size(), expected_pitch),
		"Bag cells use the smaller of available width/12 and height/10 at this viewport and UI scale, capped at 64 logical pixels")
	check(bag_rect.position.y >= right_scroll_rect.position.y - 1.0
		and bag_rect.end.y <= right_scroll_rect.end.y + 1.0,
		"All ten bag rows are inside the visible right-dock scroll viewport")
	print("Layout %d×%d ui=%.1f font=%.1f: equipment-bottom=%.1f%% page-bottom=%.1f%% right-scroll-range=%.1f bag-board=%s"
		% [view_size.x, view_size.y, ui_scale, font_scale, dock_ratio * 100.0, page_ratio * 100.0,
			right_scroll_range, str(bag_rect)])
	var size_summary := ""
	for child: Node in inventory.get_children():
		if child is Control:
			var control := child as Control
			size_summary += "%s:%0.1f/%0.1f " % [control.name, control.size.y, control.get_combined_minimum_size().y]
	print("Right geometry panel=%s scroll=%s content=%s inventory=%s children=%s"
		% [str(right_rect), str(right_scroll_rect), str((arena.hud._dock_bodies.right as Control).get_global_rect()),
			str(inventory.get_global_rect()), size_summary])

	var left_scroll: ScrollContainer = arena.hud._dock_scrolls.left as ScrollContainer
	var left_content: Control = arena.hud._dock_bodies.left as Control
	var skills: Control = arena.hud._skill_support_panel as Control
	var rows: ScrollContainer = skills._rows as ScrollContainer
	var last_row: Control = rows.find_child("SkillGroupRow_09", true, false) as Control
	rows.scroll_vertical = roundi(rows.get_v_scroll_bar().max_value)
	await _frames(3)
	check(left_content.size.y >= left_scroll.size.y - 1.0 and rows.size.y > 0.0,
		"Left dock content and skill rows fill the available pane height")
	check(last_row.get_global_rect().intersects(rows.get_global_rect()), "Last skill row remains reachable by scrolling")
	check(str(arena.hud._dock_subtitles.left.text).is_empty()
		and str(arena.hud._dock_footers.left.text).is_empty()
		and skills.get_child_count() == 2,
		"Repeated top and inner drag instructions are removed from the skill pane")
	check(inventory.find_child("EquipmentSlotsTitle", true, false) == null
		and inventory.find_child("BagGridHint", true, false) == null,
		"Inventory keeps one compact count and removes duplicate section and footer hints")

	print("Left %d×%d ui=%.1f font=%.1f: viewport=%.1f content=%.1f rows=%.1f last-visible=%s"
		% [view_size.x, view_size.y, ui_scale, font_scale, left_scroll.size.y, left_content.size.y,
			rows.size.y, str(last_row.get_global_rect().intersects(rows.get_global_rect()))])
	arena.queue_free()
	await _frames(2)


func _frames(count: int) -> void:
	for unused: int in range(count):
		await process_frame


func _check_recovery_access() -> void:
	# An isolated legal recovery fixture verifies that compact sizing does not hide
	# overflow controls or sacrifice the model's recovery transaction.
	var arena: Node2D = MainScene.instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	await _frames(3)
	var candidate: Dictionary = arena.state.snapshot()
	var pending: Array[String] = []
	for uid: String in candidate.locations:
		if candidate.locations[uid].kind == "bag":
			candidate.locations[uid] = {"kind":"recovery","index":pending.size()}
			pending.append(uid)
	var path := "user://layout-recovery-fixture.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(candidate,"\t",true,true))
	check(not pending.is_empty() and arena.state.load_build(path), "Recovery fixture is accepted by the complete canonical validator")
	arena.hud.open_panel("inventory")
	await _frames(3)
	var panel: Control = arena.hud._inventory_panel
	panel.save_path = path
	var queue: VBoxContainer = panel._pending
	check(queue.visible and queue.get_child_count() == 2, "Pending items keep their visible recovery section")
	var list: Control = queue.get_child(1)
	var button: Button = list.get_child(list.get_child_count()-1)
	var scroll: ScrollContainer = arena.hud._dock_scrolls.right
	scroll.ensure_control_visible(button)
	await _frames(3)
	check(button.get_global_rect().intersects(scroll.get_global_rect()), "Last recovery action remains reachable through the outer scroll fallback")
	var before_count: int = arena.state.pending_items().size()
	button.pressed.emit()
	await _frames(3)
	check(arena.state.pending_items().size() == before_count-1, "Reachable recovery button returns exactly one owned item through the model")
	arena.queue_free()
	await _frames(2)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
