class_name ItemHoverCard
extends Control
## Read-only item presentation. The caller owns inventory selection, comparisons,
## hover lifetime, and the coordinate conversion for anchor/viewport bounds.

const PresentationTheme = preload("res://scripts/visuals/visual_theme.gd")

const OUTER_MARGIN: float = 12.0
const COLUMN_GAP: float = 10.0
const MAX_COLUMN_WIDTH: float = 400.0
const MAX_CARD_HEIGHT: float = 680.0
const HEADER_HEIGHT: float = 46.0
const CARD_PADDING: float = 12.0

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


func _ready() -> void:
	_ensure_interface()
	hide()


## Show the supplied view and, when requested, at most two equipped comparisons.
## anchor and viewport_bounds must use this Control parent's local coordinates.
func present(view: Dictionary, comparison_views: Array, anchor: Rect2,
		viewport_bounds: Rect2, compare: bool = false) -> void:
	_last_view = view.duplicate(true)
	_last_comparison_views = comparison_views.duplicate(true)
	_last_anchor = anchor
	_last_viewport_bounds = viewport_bounds
	_last_compare = compare
	_ensure_interface()
	_refresh_layout()


func dismiss() -> void:
	_last_view.clear()
	_last_comparison_views.clear()
	hide()


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
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.add_theme_constant_override("separation", int(COLUMN_GAP))
	add_child(_row)


func _refresh_layout() -> void:
	if _row == null:
		return
	for child: Node in _row.get_children():
		_row.remove_child(child)
		child.free()

	var safe_bounds: Rect2 = _safe_bounds(_last_viewport_bounds)
	if safe_bounds.size.x <= 0.0 or safe_bounds.size.y <= 0.0 or _last_view.is_empty():
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
	var card_height: float = clampf(natural_height, minf(210.0, max_height), max_height)
	var scroll_height: float = maxf(72.0, card_height - HEADER_HEIGHT)

	for index: int in range(views.size()):
		var role: String = "悬停物品" if index == 0 else "已装备目标 %d" % index
		_row.add_child(_build_card(views[index], role, index, column_width, card_height, scroll_height))
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
	var inset: Vector2 = Vector2.ONE * minf(OUTER_MARGIN, minf(source.size.x, source.size.y) * 0.25)
	return Rect2(source.position + inset, Vector2(maxf(1.0, source.size.x - inset.x * 2.0),
		maxf(1.0, source.size.y - inset.y * 2.0)))


func _place(bounds: Rect2, anchor: Rect2, card_size: Vector2) -> Vector2:
	var max_x: float = bounds.end.x - card_size.x
	var right_x: float = anchor.end.x + OUTER_MARGIN
	var left_x: float = anchor.position.x - card_size.x - OUTER_MARGIN
	var x: float
	if right_x <= max_x:
		x = right_x
	elif left_x >= bounds.position.x:
		x = left_x
	else:
		x = clampf(anchor.get_center().x - card_size.x * 0.5, bounds.position.x, max_x)

	var max_y: float = bounds.end.y - card_size.y
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
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var border: Color = PresentationTheme.GOLD if index == 0 else PresentationTheme.ACCENT
	card.add_theme_stylebox_override("panel", PresentationTheme.panel(Color("f8ecd0"), border, 7, 1, CARD_PADDING))
	card.set_meta("item_uid", str(view.get("uid", "")))

	var content := VBoxContainer.new()
	content.name = "CardContent"
	content.add_theme_constant_override("separation", 5)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(content)

	var role_label := _label(role, 12, PresentationTheme.MUTED)
	content.add_child(role_label)

	var scroll := ScrollContainer.new()
	scroll.name = "ItemDetailsScroll"
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = scroll_height
	content.add_child(scroll)

	var body := VBoxContainer.new()
	body.name = "ItemDetails"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	scroll.add_child(body)
	var title := _label(_text(view, "name", "未命名物品"), 18, PresentationTheme.TEXT)
	title.name = "ItemName"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.tooltip_text = str(view.get("uid", ""))
	body.add_child(title)
	var metadata: String = "%s · %s" % [_text(view, "kind_label"), _text(view, "rarity_label")]
	var metadata_label := _label(metadata, 13, PresentationTheme.GOLD)
	metadata_label.name = "ItemMetadata"
	metadata_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(metadata_label)
	_add_section(body, "描述", view.get("description", ""))
	_add_section(body, "要求", view.get("requirements", []))
	_add_section(body, "基础属性", view.get("base_lines", []))
	_add_section(body, "词缀", view.get("affix_lines", []))
	_add_section(body, "效果", view.get("effect_lines", []))
	column.add_child(card)
	return column


func _add_section(parent: VBoxContainer, caption: String, value: Variant) -> void:
	var text_value: String = _section_text(value)
	if text_value.strip_edges().is_empty():
		return
	var heading := _label(caption, 14, PresentationTheme.GOLD)
	heading.name = "Section_" + caption
	parent.add_child(heading)
	var body := _label(text_value, 15, PresentationTheme.TEXT)
	body.name = "Text_" + caption
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(body)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text_value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", PresentationTheme.ink(color))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


func _natural_height(view: Dictionary, width: float) -> float:
	var font: Font = get_theme_default_font()
	var body_width: float = maxf(40.0, width - CARD_PADDING * 2.0 - 8.0)
	var name_height: float = font.get_multiline_string_size(_text(view, "name", "未命名物品"),
		HORIZONTAL_ALIGNMENT_LEFT, body_width, maxi(1, roundi(18.0 * font_scale))).y
	var metadata: String = "%s · %s" % [_text(view, "kind_label"), _text(view, "rarity_label")]
	var metadata_height: float = font.get_multiline_string_size(metadata, HORIZONTAL_ALIGNMENT_LEFT,
		body_width, maxi(1, roundi(13.0 * font_scale))).y
	var height: float = HEADER_HEIGHT + maxf(18.0, name_height) + maxf(16.0, metadata_height) + 10.0
	for value: Variant in [view.get("description", ""), view.get("requirements", []),
			view.get("base_lines", []), view.get("affix_lines", []), view.get("effect_lines", [])]:
		var text_value: String = _section_text(value)
		if text_value.strip_edges().is_empty():
			continue
		var measured: Vector2 = font.get_multiline_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT,
			body_width, maxi(1, roundi(15.0 * font_scale)))
		height += 23.0 + maxf(18.0, measured.y) + 7.0
	return maxf(190.0, height)


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
