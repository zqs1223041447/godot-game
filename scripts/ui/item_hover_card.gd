class_name ItemHoverCard
extends Control
## Read-only item presentation. The caller owns selection, comparisons, and hover lifetime.
## Legacy text fields remain supported; structured fields are display-only.
## base_stats: Array[Dictionary] of {label: String, value: String}.
## modifiers: Array[Dictionary] of {label: String, value: String, polarity: String}.
## polarity is one of MODIFIER_BENEFIT, MODIFIER_COST, or MODIFIER_NEUTRAL.

const RarityStyle = preload("res://scripts/ui/item_rarity_style.gd")
const PresentationTheme = preload("res://scripts/visuals/visual_theme.gd")

const OUTER_MARGIN: float = 12.0
const COLUMN_GAP: float = 10.0
const MAX_COLUMN_WIDTH: float = 360.0
const MAX_CARD_HEIGHT: float = 680.0
const MIN_CARD_HEIGHT: float = 160.0
const HEADER_HEIGHT: float = 36.0
const CARD_PADDING: float = 12.0
const MODIFIER_BENEFIT: String = "benefit"
const MODIFIER_COST: String = "cost"
const MODIFIER_NEUTRAL: String = "neutral"
const BENEFIT_INK: Color = Color("52623b")
const COST_INK: Color = Color("7a2f29")

var font_scale: float = 1.0:
	set(value):
		font_scale = clampf(value, 0.8, 1.6)
		if not _last_view.is_empty():
			_refresh_layout()

var _row: HBoxContainer
var _last_view: Dictionary = {}
var _last_comparison_views: Array = []
var _last_anchor: Rect2 = Rect2()
var _last_viewport_bounds: Rect2 = Rect2()
var _last_compare: bool = false
var _drag_active: bool = false


func _ready() -> void:
	_ensure_interface()
	hide()


## Show a legacy or structured view and at most two equipped comparisons.
## Anchor and bounds use the parent Control's local coordinates.
func present(view: Dictionary, comparison_views: Array, anchor: Rect2,
		viewport_bounds: Rect2, compare: bool = false) -> void:
	if _drag_active:
		dismiss()
		return
	_last_view = view.duplicate(true)
	_last_comparison_views = comparison_views.duplicate(true)
	_last_anchor = anchor
	_last_viewport_bounds = viewport_bounds
	_last_compare = compare
	_ensure_interface()
	_refresh_layout()


## Hide and forget the current presentation. A drag lock, if active, remains active.
func dismiss() -> void:
	_last_view.clear()
	_last_comparison_views.clear()
	hide()


## Integration hook for owners that have their own drag lifecycle.
## Releasing the lock never restores a stale card; the next hover must call present().
func set_drag_active(active: bool) -> void:
	if _drag_active == active:
		return
	_drag_active = active
	if active:
		dismiss()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		set_drag_active(true)
	elif what == NOTIFICATION_DRAG_END:
		set_drag_active(false)


## Keep the visual overlay pointer-transparent. Wheel input is routed only to the
## detail column under the pointer, so an item behind the card can still drag/drop.
func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventMouseButton or not event.pressed: return
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: return
	if scroll_at(event.position, -1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1,maxi(1,roundi(event.factor))):
		get_viewport().set_input_as_handled()


func contains_viewport_point(point: Vector2) -> bool:
	return visible and Rect2(Vector2.ZERO,size).has_point(get_global_transform_with_canvas().affine_inverse()*point)


func scroll_at(point: Vector2, direction: int, steps: int=1) -> bool:
	if not visible or _drag_active: return false
	var scrolls: Array[ScrollContainer] = []
	for column: Control in _row.get_children():
		var scroll := column.find_child("ItemDetailsScroll",true,false) as ScrollContainer
		if scroll == null: continue
		scrolls.append(scroll)
		var local: Vector2=column.get_global_transform_with_canvas().affine_inverse()*point
		if Rect2(Vector2.ZERO,column.size).has_point(local):
			scroll.scroll_vertical += direction*maxi(1,steps)*42
			return true
	# The pointer may remain on the source item; no focus transfer is needed.
	var parent_control := get_parent() as Control
	if parent_control != null and _last_anchor.has_point(parent_control.get_global_transform_with_canvas().affine_inverse()*point) and not scrolls.is_empty():
		scrolls[0].scroll_vertical += direction*maxi(1,steps)*42
		return true
	return false


func _ensure_interface() -> void:
	if _row != null:
		return
	if theme == null:
		theme = PresentationTheme.create_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	z_index = 100
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_row = HBoxContainer.new()
	_row.name = "ItemHoverCards"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_row.add_theme_constant_override("separation", int(COLUMN_GAP))
	add_child(_row)


func _refresh_layout() -> void:
	if _row == null:
		return
	for child: Node in _row.get_children():
		_row.remove_child(child)
		child.free()

	var safe_bounds: Rect2 = _safe_bounds(_last_viewport_bounds)
	if _drag_active or safe_bounds.size.x <= 0.0 or safe_bounds.size.y <= 0.0 or _last_view.is_empty():
		hide()
		return

	var views: Array[Dictionary] = [_last_view]
	if _last_compare:
		for candidate: Variant in _last_comparison_views:
			if candidate is Dictionary and views.size() < 3:
				views.append(candidate)
	var count: int = views.size()
	var available_width: float = maxf(1.0, safe_bounds.size.x - COLUMN_GAP * float(count - 1))
	var column_width: float = minf(MAX_COLUMN_WIDTH, available_width / float(count))
	var total_width: float = column_width * float(count) + COLUMN_GAP * float(count - 1)
	var max_height: float = minf(MAX_CARD_HEIGHT, safe_bounds.size.y)
	var natural_height: float = 0.0
	for item_view: Dictionary in views:
		natural_height = maxf(natural_height, _natural_height(item_view, column_width))
	var card_height: float = minf(max_height, maxf(minf(MIN_CARD_HEIGHT, max_height), natural_height))
	var scroll_height: float = maxf(48.0, card_height - HEADER_HEIGHT)

	for index: int in range(views.size()):
		var role: String = "悬停物品" if index == 0 else "已装备目标 %d" % index
		_row.add_child(_build_card(views[index], role, index, column_width, card_height, scroll_height))
	_set_mouse_transparent(_row)
	for scroll: ScrollContainer in find_children("ItemDetailsScroll", "ScrollContainer", true, false):
		scroll.focus_mode = Control.FOCUS_NONE
		scroll.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
		scroll.get_h_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	PresentationTheme.apply_font_scale(self, font_scale)

	size = Vector2(total_width, card_height)
	position = _place(safe_bounds, _last_anchor, size)
	_row.position = Vector2.ZERO
	_row.size = size
	show()


func _safe_bounds(bounds: Rect2) -> Rect2:
	var source: Rect2 = bounds
	if source.size.x <= 0.0 or source.size.y <= 0.0:
		source = get_viewport_rect()
	var inset_amount: float = minf(OUTER_MARGIN, minf(source.size.x, source.size.y) * 0.25)
	var inset: Vector2 = Vector2.ONE * inset_amount
	return Rect2(source.position + inset, Vector2(maxf(1.0, source.size.x - inset.x * 2.0),
		maxf(1.0, source.size.y - inset.y * 2.0)))


func _place(bounds: Rect2, anchor: Rect2, card_size: Vector2) -> Vector2:
	var max_x: float = maxf(bounds.position.x, bounds.end.x - card_size.x)
	var right_x: float = anchor.end.x + OUTER_MARGIN
	var left_x: float = anchor.position.x - card_size.x - OUTER_MARGIN
	var x: float
	if right_x <= max_x:
		x = right_x
	elif left_x >= bounds.position.x:
		x = left_x
	else:
		x = clampf(anchor.get_center().x - card_size.x * 0.5, bounds.position.x, max_x)

	var max_y: float = maxf(bounds.position.y, bounds.end.y - card_size.y)
	var below_y: float = anchor.end.y + OUTER_MARGIN
	var above_y: float = anchor.position.y - card_size.y - OUTER_MARGIN
	var y: float
	if below_y <= max_y:
		y = below_y
	elif above_y >= bounds.position.y:
		y = above_y
	else:
		y = clampf(anchor.get_center().y - card_size.y * 0.5, bounds.position.y, max_y)
	return Vector2(x, y)


func _set_mouse_transparent(node: Node) -> void:
	if node is Control:
		var control := node as Control
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.focus_mode = Control.FOCUS_NONE
	for child: Node in node.get_children(true):
		_set_mouse_transparent(child)


func _build_card(view: Dictionary, role: String, index: int, width: float,
		height: float, scroll_height: float) -> Control:
	var column := Control.new()
	column.name = "MainItemCardColumn" if index == 0 else "EquippedItemCardColumn%d" % index
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.clip_contents = true
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size = Vector2(width, height)
	var card := PanelContainer.new()
	card.name = "MainItemCard" if index == 0 else "EquippedItemCard%d" % index
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var border: Color = RarityStyle.border(str(view.get("rarity","normal")))
	card.add_theme_stylebox_override("panel", PresentationTheme.panel(Color("f1deb3"), border, 7, 1, CARD_PADDING))
	card.set_meta("item_uid", str(view.get("uid", "")))

	var content := VBoxContainer.new()
	content.name = "CardContent"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 5)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(content)
	var role_label := _label(role, 11, PresentationTheme.MUTED)
	role_label.name = "ItemCardRole"
	if index > 0: content.add_child(role_label)
	else: role_label.free()

	var scroll := ScrollContainer.new()
	scroll.name = "ItemDetailsScroll"
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 48.0
	content.add_child(scroll)

	var body := VBoxContainer.new()
	body.name = "ItemDetails"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 7)
	scroll.add_child(body)
	var title := _label(_text(view, "name", "未命名物品"), 18, border)
	title.name = "ItemName"
	var title_font := FontVariation.new()
	title_font.base_font = get_theme_default_font()
	title_font.variation_embolden = 0.45
	title.add_theme_font_override("font", title_font)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.tooltip_text = str(view.get("uid", ""))
	content.add_child(title)
	var metadata := _build_metadata(view, width)
	if metadata.get_child_count() > 0:
		content.add_child(metadata)
	else:
		metadata.free()
	var tags: Array[String] = _string_array(view.get("tags", []))
	if not tags.is_empty():
		content.add_child(_build_tags(tags, width))

	content.move_child(scroll,content.get_child_count()-1)
	var function_text: String = _section_text(view.get("function", ""))
	var description_text: String = _section_text(view.get("description", ""))
	_add_section(body, "功能", function_text)
	if description_text != function_text:
		_add_section(body, "描述", description_text)
	_add_section(body, "要求", view.get("requirements", []))
	var base_stats: Array[Dictionary] = _structured_rows(view.get("base_stats", []), false)
	if not base_stats.is_empty():
		_add_stats(body, base_stats, width)
	else:
		_add_section(body, "基础属性", view.get("base_lines", []))
	var modifiers: Array[Dictionary] = _structured_rows(view.get("modifiers", []), true)
	if not modifiers.is_empty():
		_add_modifiers(body, modifiers)
	else:
		_add_section(body, "额外词缀", view.get("affix_lines", []),13,Color("475c87"))
	var preview_lines: Array[String] = _string_array(view.get("preview_lines", []))
	if not preview_lines.is_empty():
		_add_section(body, "当前组合", preview_lines, 12, PresentationTheme.MUTED)
	else:
		_add_section(body, "效果", view.get("effect_lines", []))
	column.add_child(card)
	return column


func _build_metadata(view: Dictionary, width: float) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.name = "ItemMetadata"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 3)
	var content_width: float = maxf(1.0, width - CARD_PADDING * 2.0 - 8.0)
	var max_badge_width: float = maxf(1.0, minf(content_width - 4.0, width * 0.48))
	var kind: String = _text(view, "kind_label").strip_edges()
	var rarity: String = _text(view, "rarity_label").strip_edges()
	if not kind.is_empty():
		row.add_child(_badge(kind, "ItemTypeBadge", PresentationTheme.MUTED, Color("ead9b8"), max_badge_width))
	if not rarity.is_empty():
		row.add_child(_badge(rarity, "ItemRarityBadge", PresentationTheme.GOLD, Color("f4e5c3"), max_badge_width))
	return row


func _badge(value: String, stable_name: String, color: Color, background: Color,
		max_width: float) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = stable_name
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.add_theme_stylebox_override("panel", PresentationTheme.panel(background, Color("9c7a4d"), 3, 1, 4))
	var font: Font = get_theme_default_font()
	var font_size: int = maxi(1, roundi(11.0 * font_scale))
	var measured_width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x if font != null else 24.0
	var text_width: float = minf(measured_width, maxf(1.0, max_width - 12.0))
	var text_height: float = font.get_height(font_size) if font != null else float(font_size)
	var text_frame := Control.new()
	text_frame.name = stable_name + "TextFrame"
	text_frame.clip_contents = true
	text_frame.custom_minimum_size = Vector2(maxf(1.0, text_width), text_height)
	var label := _label(value, 11, color)
	label.name = stable_name + "Text"
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.tooltip_text = value
	text_frame.add_child(label)
	badge.add_child(text_frame)
	badge.tooltip_text = value
	return badge


func _build_tags(tags: Array[String], width: float) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.name = "ItemTags"
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 3)
	for index: int in range(tags.size()):
		var tag:=_label(tags[index],11,PresentationTheme.MUTED)
		tag.name="ItemTag%d"%index
		flow.add_child(tag)

	return flow


func _add_section(parent: VBoxContainer, caption: String, value: Variant,
		font_size: int = 13, body_color: Color = PresentationTheme.TEXT) -> void:
	var text_value: String = _section_text(value)
	if text_value.strip_edges().is_empty():
		return
	_section_break(parent)
	var heading := _label(caption, 11, PresentationTheme.GOLD)
	heading.name = "Section_" + caption
	parent.add_child(heading)
	var body := _label(text_value, font_size, body_color)
	body.name = "Text_" + caption
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(body)


func _add_stats(parent: VBoxContainer, entries: Array[Dictionary], width: float) -> void:
	_section_break(parent)
	var heading := _label("基础属性", 11, PresentationTheme.GOLD)
	heading.name = "Section_基础属性"
	parent.add_child(heading)
	var grid := GridContainer.new()
	grid.name = "BaseStats"
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 3)
	var body_width: float = maxf(40.0, width - CARD_PADDING * 2.0 - 8.0)
	var column_min: float = maxf(36.0, body_width * 0.36)
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		var key_label := _label(str(entry.label), 13, PresentationTheme.MUTED)
		key_label.name = "BaseStatKey%d" % index
		key_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		key_label.custom_minimum_size.x = column_min
		key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(key_label)
		var value_label := _label(str(entry.value), 13, PresentationTheme.TEXT)
		value_label.name = "BaseStatValue%d" % index
		value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.custom_minimum_size.x = column_min
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value_label)
	parent.add_child(grid)


func _add_modifiers(parent: VBoxContainer, entries: Array[Dictionary]) -> void:
	_section_break(parent)
	var heading := _label("辅助效果", 11, PresentationTheme.GOLD)
	heading.name = "Section_增益与代价"
	parent.add_child(heading)
	var rows := VBoxContainer.new()
	rows.name = "Modifiers"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		var polarity: String = str(entry.polarity)
		var color: Color = BENEFIT_INK if polarity == MODIFIER_BENEFIT else COST_INK if polarity == MODIFIER_COST else PresentationTheme.MUTED
		var symbol: String = "▲" if polarity == MODIFIER_BENEFIT else "▼" if polarity == MODIFIER_COST else "·"
		var line := HBoxContainer.new()
		line.name = "Modifier%d" % index
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_theme_constant_override("separation", 4)
		var marker := _label(symbol, 14, color)
		marker.name = "ModifierMarker%d" % index
		marker.custom_minimum_size.x = 18.0
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_child(marker)
		var copy: String = str(entry.label)
		if not str(entry.value).is_empty():
			copy = str(entry.value) if copy.is_empty() else "%s  %s" % [copy, str(entry.value)]
		var text_label := _label(copy, 13, color)
		text_label.name = "ModifierText%d" % index
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text_label)
		rows.add_child(line)
	parent.add_child(rows)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text_value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", PresentationTheme.ink(color))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


func _natural_height(view: Dictionary, width: float) -> float:
	var font: Font = get_theme_default_font()
	if font == null:
		return MIN_CARD_HEIGHT
	var body_width: float = maxf(40.0, width - CARD_PADDING * 2.0 - 8.0)
	var title_size: int = maxi(1, roundi(18.0 * font_scale))
	var small_size: int = maxi(1, roundi(12.0 * font_scale))
	var body_size: int = maxi(1, roundi(14.0 * font_scale))
	var height: float = HEADER_HEIGHT + CARD_PADDING * 1.3 + 8.0
	height += _measure_height(font, _text(view, "name", "未命名物品"), body_width, title_size)
	height += 5.0 + _measure_height(font, _metadata_text(view), body_width, small_size)
	var tags: Array[String] = _string_array(view.get("tags", []))
	if not tags.is_empty():
		height += 5.0 + float(_tag_row_count(tags, body_width, font, small_size)) * (float(small_size) + 8.0)

	var function_text: String = _section_text(view.get("function", ""))
	var description_text: String = _section_text(view.get("description", ""))
	for text_value: String in [function_text, description_text if description_text != function_text else ""]:
		if not text_value.strip_edges().is_empty():
			height += 5.0 + float(small_size + 4) + _measure_height(font, text_value, body_width, body_size) + 3.0
	var requirements_text: String = _section_text(view.get("requirements", []))
	if not requirements_text.strip_edges().is_empty():
		height += 5.0 + float(small_size + 4) + _measure_height(font, requirements_text, body_width, body_size) + 3.0

	var stats: Array[Dictionary] = _structured_rows(view.get("base_stats", []), false)
	if not stats.is_empty():
		height += 5.0 + float(small_size + 4)
		var cell_width: float = maxf(28.0, body_width * 0.43)
		for entry: Dictionary in stats:
			var key_height: float = _measure_height(font, str(entry.label), cell_width, body_size - 1)
			var value_height: float = _measure_height(font, str(entry.value), cell_width, body_size - 1)
			height += maxf(key_height, value_height) + 3.0
	else:
		height += _legacy_section_height(font, view.get("base_lines", []), body_width, small_size, body_size)

	var modifiers: Array[Dictionary] = _structured_rows(view.get("modifiers", []), true)
	if not modifiers.is_empty():
		height += 5.0 + float(small_size + 4)
		for entry: Dictionary in modifiers:
			var line: String = "%s  %s" % [str(entry.label), str(entry.value)]
			height += _measure_height(font, line, body_width, body_size - 1) + 3.0
	else:
		height += _legacy_section_height(font, view.get("affix_lines", []), body_width, small_size, body_size)

	var preview_lines: Array[String] = _string_array(view.get("preview_lines", []))
	var effect_value: Variant = preview_lines if not preview_lines.is_empty() else view.get("effect_lines", [])
	var effect_text: String = _section_text(effect_value)
	if not effect_text.strip_edges().is_empty():
		var caption_size: int = small_size + 4
		height += 5.0 + float(caption_size) + _measure_height(font, effect_text, body_width, body_size) + 3.0
	return maxf(MIN_CARD_HEIGHT, height + 64.0)


func _legacy_section_height(font: Font, value: Variant, width: float,
		title_size: int, body_size: int) -> float:
	var text_value: String = _section_text(value)
	if text_value.strip_edges().is_empty():
		return 0.0
	return 5.0 + float(title_size + 4) + _measure_height(font, text_value, width, body_size) + 3.0


func _measure_height(font: Font, value: String, width: float, font_size: int) -> float:
	if value.strip_edges().is_empty():
		return 0.0
	return maxf(float(font_size), font.get_multiline_string_size(value,
		HORIZONTAL_ALIGNMENT_LEFT, maxf(24.0, width), font_size).y)


func _tag_row_count(tags: Array[String], width: float, font: Font, font_size: int) -> int:
	var rows: int = 1
	var used_width: float = 0.0
	for tag: String in tags:
		var tag_width: float = minf(width * 0.70, font.get_string_size(tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x + 16.0)
		if used_width > 0.0 and used_width + 4.0 + tag_width > width:
			rows += 1
			used_width = tag_width
		else:
			used_width += (4.0 if used_width > 0.0 else 0.0) + tag_width
	return rows


func _metadata_text(view: Dictionary) -> String:
	return "%s %s" % [_text(view, "kind_label"), _text(view, "rarity_label")]


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for candidate: Variant in value:
		if candidate is String and not candidate.strip_edges().is_empty():
			result.append(candidate)
	return result


func _structured_rows(value: Variant, modifier_rows: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for candidate: Variant in value:
		if not candidate is Dictionary:
			continue
		var label_value: Variant = candidate.get("label", "")
		var text_value: Variant = candidate.get("value", "")
		if not label_value is String or not text_value is String:
			continue
		if label_value.strip_edges().is_empty() and text_value.strip_edges().is_empty():
			continue
		if not modifier_rows:
			result.append({"label": label_value, "value": text_value})
			continue
		var polarity_value: Variant = candidate.get("polarity", MODIFIER_NEUTRAL)
		if not polarity_value is String:
			continue
		var polarity: String = polarity_value if polarity_value in [MODIFIER_BENEFIT, MODIFIER_COST, MODIFIER_NEUTRAL] else MODIFIER_NEUTRAL
		result.append({"label": label_value, "value": text_value, "polarity": polarity})
	return result


func _section_text(value: Variant) -> String:
	if value is String:
		return value
	if value is Array:
		var lines: PackedStringArray = PackedStringArray()
		for line: Variant in value:
			lines.append(str(line))
		return "\n".join(lines)
	return ""


func _text(view: Dictionary, key: String, fallback: String = "") -> String:
	var value: Variant = view.get(key, fallback)
	return str(value) if value != null else fallback


func _section_break(parent: VBoxContainer) -> void:
	var separator:=HSeparator.new()
	separator.custom_minimum_size.y=8
	separator.mouse_filter=Control.MOUSE_FILTER_IGNORE
	separator.modulate=Color(0.55,0.43,0.28,0.55)
	parent.add_child(separator)
