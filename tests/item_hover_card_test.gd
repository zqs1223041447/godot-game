extends SceneTree

const ItemHoverCardScript = preload("res://scripts/ui/item_hover_card.gd")

var checks: int = 0
var failures: int = 0
var host: Control
var card: Control
var capture_dir: String = OS.get_environment("ITEM_HOVER_CARD_CAPTURE_DIR")


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	host = Control.new()
	host.name = "ScaledOverlayHost"
	root.add_child(host)
	card = ItemHoverCardScript.new()
	card.name = "ItemHoverCardUnderTest"
	host.add_child(card)
	await process_frame

	var input_view: Dictionary = _long_view("MAIN-UID", "长词缀传奇护符")
	var equipped_ring_a: Dictionary = _long_view("RING-LEFT", "左戒指")
	var equipped_ring_b: Dictionary = _long_view("RING-RIGHT", "右戒指")
	var before: Dictionary = input_view.duplicate(true)
	var extra: Dictionary = _long_view("IGNORED-FOURTH", "第四个比较对象")
	var scenarios: Array[Dictionary] = [
		{"screen": Vector2i(1920, 1080), "scale": 1.0},
		{"screen": Vector2i(2560, 1440), "scale": 1.0},
		{"screen": Vector2i(1920, 1080), "scale": 1.1},
		{"screen": Vector2i(2560, 1440), "scale": 1.1},
	]
	for scenario: Dictionary in scenarios:
		var screen: Vector2i = scenario.screen
		var ui_scale: float = scenario.scale
		root.size = screen
		host.position = Vector2.ZERO
		host.scale = Vector2.ONE * ui_scale
		host.size = Vector2(screen) / ui_scale
		card.font_scale = 1.2
		var bounds := Rect2(Vector2.ZERO, Vector2(screen) / ui_scale)
		for corner: String in ["top_left", "top_right", "bottom_left", "bottom_right"]:
			var anchor := _anchor(corner, bounds, ui_scale)
			card.present(input_view, [equipped_ring_a, equipped_ring_b, extra], anchor, bounds, true)
			await process_frame
			await process_frame
			_expect(card.visible, "visible at %dx%d ui %.1f %s" % [screen.x, screen.y, ui_scale, corner])
			_expect(card.find_child("MainItemCard", true, false) != null, "main item card exists")
			_expect(card.find_child("EquippedItemCard1", true, false) != null, "first equipped target exists")
			_expect(card.find_child("EquippedItemCard2", true, false) != null, "second equipped target exists for dual-ring comparison")
			_expect(card.find_child("EquippedItemCard3", true, false) == null, "comparisons are capped at two equipped targets")
			_expect(_inside_viewport(card.get_global_rect(), Vector2(screen)), "three-card bounds fit %dx%d ui %.1f %s: %s" % [screen.x, screen.y, ui_scale, corner, card.get_global_rect()])
			var row: HBoxContainer = card.find_child("ItemHoverCards", true, false) as HBoxContainer
			for panel: Control in row.get_children():
				_expect(_inside_viewport(panel.get_global_rect(), Vector2(screen)), "each card frame fits %dx%d ui %.1f %s: %s" % [screen.x, screen.y, ui_scale, corner, panel.get_global_rect()])
				var frame: Control = panel.get_child(0) as Control
				_expect(frame != null and _inside_viewport(frame.get_global_rect(), Vector2(screen)), "material panel remains inside its clipped column")
				var details: ScrollContainer = frame.find_child("ItemDetailsScroll", true, false) as ScrollContainer
				_expect(details != null and _rect_inside(details.get_global_rect(), frame.get_global_rect()), "scroll viewport stays inside its card frame")
			_expect(input_view == before, "rendering leaves the source view dictionary unchanged")
			if capture_dir != "" and corner == "bottom_right":
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
				_capture("%dx%d-ui%d-compare" % [screen.x, screen.y, roundi(ui_scale * 100.0)])

	var first_scroll: ScrollContainer = card.find_child("ItemDetailsScroll", true, false) as ScrollContainer
	_expect(first_scroll != null, "detail body has a native vertical scroll container")
	if first_scroll != null:
		await process_frame
		var bar: VScrollBar = first_scroll.get_v_scroll_bar()
		_expect(bar.max_value > bar.page, "long affixes overflow into scrollable detail content")
		if bar.max_value > bar.page:
			first_scroll.scroll_vertical = 0
			var scroll_rect: Rect2 = first_scroll.get_global_rect()
			var motion := InputEventMouseMotion.new()
			motion.position = scroll_rect.get_center()
			motion.global_position = scroll_rect.get_center()
			root.push_input(motion, true)
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			wheel.factor = 1.0
			wheel.position = scroll_rect.get_center()
			wheel.global_position = scroll_rect.get_center()
			root.push_input(wheel, true)
			await process_frame
			_expect(first_scroll.scroll_vertical > 0, "mouse wheel over a card scrolls the long item details")

	card.present(input_view, [equipped_ring_a, equipped_ring_b], Rect2(40, 40, 30, 30),
		Rect2(Vector2.ZERO, Vector2(root.size)), false)
	await process_frame
	_expect(card.find_child("EquippedItemCard1", true, false) == null, "compare false renders only the hovered item")
	card.dismiss()
	_expect(not card.visible, "dismiss hides the component")
	card.present(input_view, [], Rect2(40, 40, 30, 30), Rect2(Vector2.ZERO, Vector2(root.size)))
	await process_frame
	_expect(card.visible, "present can reopen a dismissed component")
	print("item_hover_card_test: %d checks, %d failures" % [checks, failures])
	if is_instance_valid(host):
		host.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _inside_viewport(rect: Rect2, viewport_size: Vector2) -> bool:
	return rect.position.x >= -1.0 and rect.position.y >= -1.0 \
		and rect.end.x <= viewport_size.x + 1.0 and rect.end.y <= viewport_size.y + 1.0


func _rect_inside(rect: Rect2, bounds: Rect2) -> bool:
	return rect.position.x >= bounds.position.x - 1.0 and rect.position.y >= bounds.position.y - 1.0 \
		and rect.end.x <= bounds.end.x + 1.0 and rect.end.y <= bounds.end.y + 1.0


func _anchor(corner: String, bounds: Rect2, ui_scale: float) -> Rect2:
	var margin: float = 8.0 / ui_scale
	var span: Vector2 = Vector2(42.0, 34.0) / ui_scale
	var x: float = bounds.position.x + margin if corner.ends_with("left") else bounds.end.x - margin - span.x
	var y: float = bounds.position.y + margin if corner.begins_with("top") else bounds.end.y - margin - span.y
	return Rect2(Vector2(x, y), span)


func _long_view(uid: String, name: String) -> Dictionary:
	var long_line: String = "卓越的奥术回响使装备者的每一道火焰与冰霜法术获得显著增幅，并在持续战斗中保持稳定的魔力循环。"
	var affixes: Array[String] = []
	for index: int in range(10):
		affixes.append("T%d · %s（+%d）" % [index % 3 + 1, long_line.repeat(2), index * 7 + 12])
	return {
		"uid": uid,
		"name": name,
		"kind_label": "戒指",
		"rarity_label": "传奇",
		"description": long_line,
		"requirements": ["等级 68", "需要 42 点智慧与 35 点敏捷"],
		"base_lines": ["增加 24 点最大生命", "增加 17 点法术伤害"],
		"affix_lines": affixes,
		"effect_lines": ["奥术效果只作显示文本，不在卡片内执行任何计算。"],
	}


func _capture(stem: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("CAPTURE_SKIPPED ", stem, " — headless display server has no rendered viewport texture")
		return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var image: Image = root.get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_png(capture_dir.path_join(stem + ".png"))
