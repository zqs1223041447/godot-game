extends SceneTree

const ItemHoverCardScript = preload("res://scripts/ui/item_hover_card.gd")

class TestDragSource extends Control:
	var drag_calls: int = 0
	var item_uid: String = "test-drag-item"
	var last_drag_uid: String = ""

	func _get_drag_data(_at_position: Vector2) -> Variant:
		drag_calls += 1
		last_drag_uid = item_uid
		var preview := ColorRect.new()
		preview.color = Color("ba9148")
		preview.custom_minimum_size = Vector2(24, 24)
		set_drag_preview(preview)
		return {"type":"hover_test_item", "uid":item_uid}


class TestDropTarget extends Control:
	var drop_calls: int = 0
	var dropped_uid: String = ""
	var drop_position: Vector2 = Vector2.ZERO
	var drop_position_global: Vector2 = Vector2.ZERO
	var final_release_position: Vector2 = Vector2(-1, -1)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("type", "") == "hover_test_item"

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		drop_calls += 1
		dropped_uid = str(data.get("uid", "")) if data is Dictionary else ""
		drop_position = at_position
		drop_position_global = get_global_rect().position + at_position

	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton and not event.pressed:
			final_release_position = event.position


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
	var structured_view: Dictionary = _structured_view()
	var structured_before: Dictionary = structured_view.duplicate(true)
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
		host.size = root.get_visible_rect().size / ui_scale
		card.font_scale = 1.2
		var bounds := Rect2(Vector2.ZERO, host.size)
		var corners: Array[String] = ["top_left", "top_right", "bottom_left", "bottom_right"]
		if screen != Vector2i(1920, 1080) or not is_equal_approx(ui_scale, 1.0):
			corners = ["top_left", "bottom_right"]
		for corner: String in corners:
			var anchor := _anchor(corner, bounds, ui_scale)
			card.present(input_view, [equipped_ring_a, equipped_ring_b, extra], anchor, bounds, true)
			await process_frame
			await process_frame
			_expect(card.visible, "visible at %dx%d ui %.1f %s" % [screen.x, screen.y, ui_scale, corner])
			_expect(card.find_child("MainItemCard", true, false) != null, "main item card exists")
			_expect(card.find_child("EquippedItemCard1", true, false) != null, "first equipped target exists")
			_expect(card.find_child("EquippedItemCard2", true, false) != null, "second equipped target exists for dual-ring comparison")
			_expect(card.find_child("EquippedItemCard3", true, false) == null, "comparisons are capped at two equipped targets")
			_expect(_inside_viewport(card.get_global_rect(), root.get_visible_rect().size), "three-card bounds fit %dx%d ui %.1f %s: %s" % [screen.x, screen.y, ui_scale, corner, card.get_global_rect()])
			var row: HBoxContainer = card.find_child("ItemHoverCards", true, false) as HBoxContainer
			for panel: Control in row.get_children():
				_expect(_inside_viewport(panel.get_global_rect(), root.get_visible_rect().size), "each card frame fits %dx%d ui %.1f %s: %s" % [screen.x, screen.y, ui_scale, corner, panel.get_global_rect()])
				var frame: Control = panel.get_child(0) as Control
				_expect(frame != null and _inside_viewport(frame.get_global_rect(), root.get_visible_rect().size), "material panel remains inside its clipped column")
				var details: ScrollContainer = frame.find_child("ItemDetailsScroll", true, false) as ScrollContainer
				_expect(details != null and _rect_inside(details.get_global_rect(), frame.get_global_rect()), "scroll viewport stays inside its card frame")
			_expect(input_view == before, "rendering leaves the source view dictionary unchanged")
			if capture_dir != "" and corner == "bottom_right":
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
				_capture("%dx%d-ui%d-compare" % [screen.x, screen.y, roundi(ui_scale * 100.0)])
		for region: String in ["left_third", "right_third"]:
			var anchor_x: float = bounds.position.x + bounds.size.x / 3.0 if region == "left_third" else bounds.position.x + bounds.size.x * 2.0 / 3.0
			var region_anchor := Rect2(Vector2(anchor_x, bounds.position.y + bounds.size.y * 0.45), Vector2(40.0, 36.0))
			card.present(input_view, [equipped_ring_a, equipped_ring_b], region_anchor, bounds, true)
			await process_frame
			_expect(_inside_viewport(card.get_global_rect(), root.get_visible_rect().size), "three-card comparison stays inside the %s third" % region)

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
		Rect2(Vector2.ZERO, host.size), false)
	await process_frame
	_expect(card.find_child("EquippedItemCard1", true, false) == null, "compare false renders only the hovered item")
	card.dismiss()
	_expect(not card.visible, "dismiss hides the component")
	card.font_scale = 1.1
	_expect(not card.visible, "font change does not resurrect dismissed hover")
	card.present({}, [], Rect2(), Rect2(Vector2.ZERO, host.size))
	_expect(not card.visible, "empty view remains hidden")
	card.present(input_view, [], Rect2(40, 40, 30, 30), Rect2(Vector2.ZERO, host.size))
	await process_frame
	_expect(card.visible, "present can reopen a dismissed component")
	card.present(structured_view, [equipped_ring_a, equipped_ring_b], Rect2(40, 40, 30, 30),
		Rect2(Vector2.ZERO, host.size), true)
	await process_frame
	var structured_name: Label = card.find_child("ItemName", true, false) as Label
	var type_badge: Control = card.find_child("ItemTypeBadge", true, false) as Control
	var rarity_badge: Control = card.find_child("ItemRarityBadge", true, false) as Control
	var base_stats: GridContainer = card.find_child("BaseStats", true, false) as GridContainer
	var first_value: Label = card.find_child("BaseStatValue0", true, false) as Label
	var second_value: Label = card.find_child("BaseStatValue1", true, false) as Label
	var gain: Label = card.find_child("ModifierText0", true, false) as Label
	var cost: Label = card.find_child("ModifierText1", true, false) as Label
	_expect(card.find_child("Text_功能", true, false) != null, "structured function is a separate body section")
	_expect(card.find_child("ItemTags", true, false) != null, "structured tags use a compact tag row")
	_expect(card.find_child("Text_当前组合施放预览", true, false) != null, "current cast preview has its own section")
	var main_card: Control = card.find_child("MainItemCard", true, false) as Control
	_expect(main_card != null and main_card.find_child("Text_描述", true, false) == null, "same legacy description is not duplicated beside function in the main card")
	_expect(base_stats != null and base_stats.columns == 2, "base properties use a two-column key/value grid")
	_expect(first_value != null and second_value != null and is_equal_approx(first_value.global_position.x, second_value.global_position.x), "base property values align to one column")
	_expect(gain != null and cost != null and gain.get_theme_color("font_color") != cost.get_theme_color("font_color"), "benefit and cost use distinct semantic inks")
	_expect(str((card.find_child("ModifierMarker0", true, false) as Label).text) == "▲", "benefit has a visible positive marker")
	_expect(str((card.find_child("ModifierMarker1", true, false) as Label).text) == "▼", "cost has a visible negative marker")
	var type_badge_text: Label = type_badge.get_child(0) as Label if type_badge != null else null
	_expect(structured_name != null and type_badge_text != null and structured_name.get_theme_font_size("font_size") > type_badge_text.get_theme_font_size("font_size"), "item name has stronger type hierarchy than type and quality chips")
	var title_font: FontVariation = structured_name.get_theme_font("font") as FontVariation if structured_name != null else null
	_expect(title_font != null and title_font.variation_embolden > 0.0, "item name uses synthetic weight from the existing Arena Sans font")
	_expect(card.find_child("EquippedItemCard1", true, false) != null and card.find_child("EquippedItemCard2", true, false) != null, "structured view keeps the two-comparison ring layout")
	_expect(structured_view == structured_before, "structured rendering leaves all source fields unchanged")
	_expect(card.size.y <= ItemHoverCardScript.MAX_CARD_HEIGHT, "long unbroken name and affixes remain inside the card height cap")
	await _test_drag_suppression(input_view)
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
	var long_line: String = "卓越的奥术回响使装备者的每一道火焰与冰霜法术获得显著增幅，并在持续战斗中保持稳定的魔力循环。UNBREAKABLE".repeat(3)
	var affixes: Array[String] = []
	for index: int in range(6):
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


func _structured_view() -> Dictionary:
	var long_word: String = "RunicModifierWithoutWordBreak".repeat(5)
	return {
		"uid":"STRUCTURED-SKILL",
		"name":"风暴编织者·长名测试 " + "Arcane".repeat(10),
		"kind_label":"主动宝石",
		"rarity_label":"等级 1 · 品质 0",
		"description":"结构化功能正文不再重复。",
		"function":"结构化功能正文不再重复。",
		"tags":["投射物", "法术", long_word],
		"base_stats":[
			{"label":"基础魔力消耗", "value":"7"},
			{"label":"基础命中系数", "value":"160%"},
		],
		"modifiers":[
			{"label":"凝束辅助 · 投射物命中伤害", "value":"+25%", "polarity":"benefit"},
			{"label":"疾咏辅助 · 魔力消耗", "value":"×1.40", "polarity":"cost"},
		],
		"preview_lines":["当前组合消耗：9.80 魔力 · 0.80 秒冷却", "命中预估：每枚投射物 42.00"],
	}


func _test_drag_suppression(view: Dictionary) -> void:
	root.size = Vector2i(1920, 1080)
	host.position = Vector2.ZERO
	host.scale = Vector2.ONE
	host.size = root.get_visible_rect().size
	card.queue_free()
	await process_frame

	var underlying_scroll := ScrollContainer.new()
	underlying_scroll.name = "UnderlyingInventoryScroll"
	underlying_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(underlying_scroll)
	var underlying_content := VBoxContainer.new()
	underlying_content.name = "UnderlyingInventoryContent"
	underlying_content.custom_minimum_size = Vector2(host.size.x, host.size.y * 2.0)
	underlying_scroll.add_child(underlying_content)
	var underlying_fill := Control.new()
	underlying_fill.custom_minimum_size = Vector2(16, host.size.y * 2.0)
	underlying_content.add_child(underlying_fill)
	underlying_scroll.scroll_vertical = 0

	var source := TestDragSource.new()
	source.name = "RealGuiDragSource"
	source.size = Vector2(72, 72)
	host.add_child(source)
	var target := TestDropTarget.new()
	target.name = "RealGuiDropTarget"
	target.size = Vector2(120, 84)
	host.add_child(target)
	card = ItemHoverCardScript.new()
	card.name = "FrontmostItemHoverCard"
	host.add_child(card)
	card.present(_pointer_transparency_view(view), [], Rect2(40, 40, 30, 30), Rect2(Vector2.ZERO, host.size))
	await process_frame
	await process_frame
	_expect(host.get_child(host.get_child_count() - 1) == card, "test puts the hover card after the real source and target in tree order")
	var content: VBoxContainer = card.find_child("CardContent", true, false) as VBoxContainer
	var body: VBoxContainer = card.find_child("ItemDetails", true, false) as VBoxContainer
	var base_stats: GridContainer = card.find_child("BaseStats", true, false) as GridContainer
	var card_scroll: ScrollContainer = card.find_child("ItemDetailsScroll", true, false) as ScrollContainer
	_expect(content != null and content.mouse_filter == Control.MOUSE_FILTER_IGNORE, "card content container explicitly passes pointer input through")
	_expect(body != null and body.mouse_filter == Control.MOUSE_FILTER_IGNORE, "detail body explicitly passes pointer input through")
	_expect(base_stats != null and base_stats.mouse_filter == Control.MOUSE_FILTER_IGNORE, "base-stat grid explicitly passes pointer input through")
	_expect(_all_controls_ignore_pointer(card), "all card controls and generated scrollbars are pointer-transparent")
	_expect(card_scroll.get_v_scroll_bar().mouse_filter == Control.MOUSE_FILTER_IGNORE and card_scroll.get_h_scroll_bar().mouse_filter == Control.MOUSE_FILTER_IGNORE, "automatic detail scrollbars do not intercept lower controls")
	var card_scroll_bar: VScrollBar = card_scroll.get_v_scroll_bar()
	var underlying_bar: VScrollBar = underlying_scroll.get_v_scroll_bar()
	_expect(card_scroll_bar.max_value > card_scroll_bar.page, "structured fixture keeps the card details scrollable")
	_expect(underlying_bar.max_value > underlying_bar.page, "underlying inventory scroll is also scrollable")

	var wheel_point: Vector2 = card_scroll.get_global_rect().get_center()
	card_scroll.scroll_vertical = 0
	underlying_scroll.scroll_vertical = 0
	_push_mouse_motion(wheel_point, wheel_point)
	await process_frame
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.factor = 1.0
	wheel.position = wheel_point
	wheel.global_position = wheel_point
	root.push_input(wheel, true)
	await process_frame
	_expect(card_scroll.scroll_vertical > 0, "wheel over the card scrolls its own details")
	_expect(underlying_scroll.scroll_vertical == 0, "handled card wheel does not scroll the underlying inventory")

	var details_rect: Rect2 = card_scroll.get_global_rect()
	var source_point: Vector2 = details_rect.position + Vector2(24, 24)
	source.position = source_point - source.size * 0.5
	target.position = card.position + Vector2(210, 150)
	var body_pass_hover: Control = null
	var source_hover: Control = null
	var final_drop_hover: Control = null
	var target_point: Vector2 = target.position + target.size * 0.5
	var viewport: Viewport = host.get_viewport()
	var negative_drag_uid: String = ""
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	_push_mouse_motion(source_point, source_point)
	await process_frame
	body_pass_hover = viewport.gui_get_hovered_control()
	_push_mouse_button(source_point, true)
	await process_frame
	_push_mouse_motion(source_point, target_point)
	await process_frame
	var negative_control_started_drag: bool = viewport.gui_is_dragging()
	negative_drag_uid = source.last_drag_uid
	_push_mouse_button(target_point, false)
	await process_frame
	_expect(body_pass_hover == body, "PASS negative control actually hovers ItemDetails above the earlier source: %s" % (body_pass_hover.name if body_pass_hover != null else "null"))
	_expect(not negative_control_started_drag and source.drag_calls == 0 and negative_drag_uid.is_empty(), "PASS negative control reproduces the blocked drag with no drag uid")

	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source.item_uid = "covered-source-uid"
	source.last_drag_uid = ""
	target.final_release_position = Vector2(-1, -1)
	_push_mouse_motion(source_point, source_point)
	await process_frame
	source_hover = viewport.gui_get_hovered_control()
	_push_mouse_button(source_point, true)
	await process_frame
	_push_mouse_motion(source_point, target_point)
	await process_frame
	final_drop_hover = viewport.gui_get_hovered_control()
	var positive_control_started_drag: bool = viewport.gui_is_dragging()
	_expect(positive_control_started_drag, "real viewport GUI events start a drag from a source beneath the frontmost visible card")
	_expect(source_hover == source, "IGNORE fix changes hovered control from ItemDetails to the covered source: %s" % (source_hover.name if source_hover != null else "null"))
	_expect(source.drag_calls == 1 and source.last_drag_uid == source.item_uid, "covered source returns its uid through Control._get_drag_data")
	_expect(final_drop_hover == target, "drag motion ends over the real drop target at %s" % target_point)
	_expect(card._drag_active and not card.visible, "drag-begin notification hides and locks a previously visible card")
	card.present(view, [], Rect2(source.position, source.size), Rect2(Vector2.ZERO, host.size))
	_expect(not card.visible, "present cannot reopen while drag suppression is active")
	_push_mouse_button(target_point, false)
	await process_frame
	_expect(target.drop_calls == 1 and target.dropped_uid == source.item_uid, "hidden card delivers a real drop with the same source uid")
	_expect(target.final_release_position.distance_to(target_point) <= 2.0, "final viewport release event is recorded at the target position")
	_expect(not card._drag_active and not card.visible, "drag end unlocks without restoring stale hover text")
	print("CARD_DRAG_TRACE negative_hover=%s negative_drag_uid=%s negative_started=%s positive_hover=%s drag_uid=%s drop_hover=%s drop_uid=%s final_release_position=%s drop_local=%s target_rect=%s" % [
		body_pass_hover.name if body_pass_hover != null else "null", negative_drag_uid,
		str(negative_control_started_drag), source_hover.name if source_hover != null else "null",
		source.last_drag_uid, final_drop_hover.name if final_drop_hover != null else "null",
		target.dropped_uid, str(target.final_release_position), str(target.drop_position), str(target.get_global_rect())])

	card.dismiss()
	var quick_source := TestDragSource.new()
	quick_source.name = "QuickGuiDragSource"
	quick_source.position = Vector2(32, 32)
	quick_source.size = Vector2(72, 72)
	host.add_child(quick_source)
	target.drop_calls = 0
	target.dropped_uid = ""
	var quick_start: Vector2 = quick_source.position + quick_source.size * 0.5
	_push_mouse_button(quick_start, true)
	await process_frame
	_push_mouse_motion(quick_start, target_point)
	await process_frame
	_push_mouse_button(target_point, false)
	await process_frame
	_expect(quick_source.drag_calls == 1 and target.drop_calls == 1 and target.dropped_uid == quick_source.item_uid, "quick drag with no visible card reaches the same target")
	_expect(not card.visible and not card._drag_active, "a quick no-card drag returns to the normal unlocked state")
	source.queue_free()
	quick_source.queue_free()
	target.queue_free()
	underlying_scroll.queue_free()
	await process_frame


func _pointer_transparency_view(view: Dictionary) -> Dictionary:
	var result: Dictionary = view.duplicate(true)
	result["base_stats"] = []
	for index: int in range(24):
		result.base_stats.append({"label":"基础属性 %02d" % index, "value":"%d" % (index * 13)})
	result["function"] = "明确展示长正文，不进行任何下层输入处理。".repeat(18)
	return result


func _all_controls_ignore_pointer(node: Node) -> bool:
	if node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for child: Node in node.get_children(true):
		if not _all_controls_ignore_pointer(child):
			return false
	return true


func _push_mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	root.push_input(event, true)


func _push_mouse_motion(previous: Vector2, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - previous
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func _capture(stem: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("CAPTURE_SKIPPED ", stem, " — headless display server has no rendered viewport texture")
		return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var image: Image = root.get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_png(capture_dir.path_join(stem + ".png"))
		var pixel_scale: Vector2 = Vector2(image.get_size()) / root.get_visible_rect().size
		for column: Control in card.get_node("ItemHoverCards").get_children():
			var rect: Rect2 = column.get_global_rect()
			var sample: Vector2i = Vector2i((rect.position + Vector2(20, 20)) * pixel_scale)
			_expect(sample.x >= 0 and sample.y >= 0 and sample.x < image.get_width() and sample.y < image.get_height(), "rendered card sample inside actual pixels")
			if sample.x >= 0 and sample.y >= 0 and sample.x < image.get_width() and sample.y < image.get_height():
				_expect(image.get_pixelv(sample).get_luminance() > 0.25, "actual parchment pixels present in every comparison card")
