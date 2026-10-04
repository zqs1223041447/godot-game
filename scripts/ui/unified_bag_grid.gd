class_name UnifiedBagGrid
extends Control
const RarityStyle=preload("res://scripts/ui/item_rarity_style.gd")
## Read-only presentation of parent-owned bag entries. All placement decisions
## and persistence remain with the caller through move_requested.

signal item_selected(uid: String)
signal item_activated(uid: String)
signal item_hovered(uid: String, anchor: Rect2)
signal hover_left
signal move_requested(uid: String, destination: Dictionary, revision: int)

const EquipmentArt = preload("res://scripts/visuals/equipment_art.gd")
const PresentationTheme = preload("res://scripts/visuals/visual_theme.gd")
const GemIconLayout = preload("res://scripts/ui/gem_icon.gd")
const DockStyle = preload("res://scripts/ui/dock_visual_style.gd")

const COLUMNS: int = 12
const ROWS: int = 8
const MAX_CELL_SIZE: float = 64.0
const EDGE_INSET: float = 8.0
const ENTRY_KINDS: Array[String] = ["equipment", "jewel", "skill_gem", "support_gem", "currency", "flask"]
const ICON_ENTRY_KINDS: Array[String] = ["skill_gem", "support_gem"]

const PAPER := Color("f8ecd0")
const CELL_LIGHT := Color("ddd2b9")
const CELL_DARK := Color("d8cbb1")
const CELL_LINE := Color("b39b70")
const DROP_GREEN := Color("3f8551")
const DROP_RED := Color("a13b2d")

var _items: Array[Dictionary] = []
var _revision: int = 0
var _columns: int = COLUMNS
var _rows: int = ROWS
var _pages: int = 1
var _page: int = 0
var _uses_page_contract: bool = false
var _selected_uid: String = ""
var _hovered_uid: String = ""
var _hover_anchor: Rect2 = Rect2()
var _last_pointer: Vector2 = Vector2.ZERO
var _has_pointer: bool = false

var _drop_validator: Callable = Callable()
var _external_item_resolver: Callable = Callable()
var _preview_uid: String = ""
var _preview_destination: Vector2i = Vector2i(-1, -1)
var _preview_valid: bool = false
var _drop_emitted: bool = false

var _outer_style: StyleBox


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_outer_style = DockStyle.surface(Color("e5dbc4"),0.0)
	resized.connect(_on_resized)
	mouse_exited.connect(_on_mouse_exited)
	queue_redraw()


## Entries passed here are the parent's current bag entries only. This control
## owns a deep copy and never reads model state or writes placement itself.
func set_items(entries: Array, revision: int) -> void:
	var previous_revision: int = _revision
	_items.clear()
	var seen_uids: Dictionary = {}
	for value: Variant in entries:
		if not value is Dictionary or not _valid_entry(value):
			continue
		var uid: String = value["uid"]
		if seen_uids.has(uid):
			continue
		seen_uids[uid] = true
		_items.append(value.duplicate(true))
	_revision = revision
	if not _has_uid(_selected_uid):
		_selected_uid = ""
	if previous_revision != _revision:
		_preview_valid = false
	if _has_pointer:
		_update_hover(item_at_position(_last_pointer))
	elif not _has_uid(_hovered_uid):
		_update_hover("")
	queue_redraw()


## Layout and selected page are view state supplied by the owning model.
## The grid never persists a page or derives bag capacity itself.
func set_bag_layout(layout: Dictionary, page: int) -> void:
	if not layout.get("columns") is int or not layout.get("rows") is int:
		return
	var next_columns: int = int(layout.columns)
	var next_rows: int = int(layout.rows)
	var next_pages: int = int(layout.get("pages", 1))
	if next_columns <= 0 or next_rows <= 0 or next_pages <= 0:
		return
	var next_page: int = clampi(page, 0, next_pages - 1)
	var changed_layout: bool = _columns != next_columns or _rows != next_rows or _pages != next_pages or _page != next_page
	_columns = next_columns
	_rows = next_rows
	_pages = next_pages
	_page = next_page
	_uses_page_contract = layout.has("pages")
	if changed_layout:
		_preview_uid = ""
		_preview_valid = false
		if _has_pointer: _update_hover(item_at_position(_last_pointer))
		queue_redraw()


func bag_page() -> int:
	return _page


func bag_page_count() -> int:
	return _pages


func grid_columns() -> int:
	return _columns


func grid_rows() -> int:
	return _rows


func set_drop_validator(validator: Callable) -> void:
	_drop_validator = validator


## External equipment/gem slots use the same drag protocol without duplicating
## them in bag entries. The parent resolves only authoritative UID and footprint.
func set_external_item_resolver(resolver: Callable) -> void:
	_external_item_resolver = resolver


## Current cell pitch in logical CanvasItem units, capped at MAX_CELL_SIZE.
func grid_cell_size() -> float:
	return _cell_pitch()


## Grid board rectangle in this Control's local logical coordinates.
func grid_rect() -> Rect2:
	return Rect2(_grid_origin(), Vector2(_columns, _rows) * _cell_pitch())


func cell_rect(cell: Vector2i) -> Rect2:
	if not _cell_is_inside(cell):
		return Rect2()
	var pitch: float = _cell_pitch()
	return Rect2(_grid_origin() + Vector2(cell) * pitch, Vector2.ONE * pitch)


func cell_at_position(point: Vector2) -> Vector2i:
	var pitch: float = _cell_pitch()
	if pitch <= 0.0:
		return Vector2i(-1, -1)
	var relative: Vector2 = point - _grid_origin()
	if relative.x < 0.0 or relative.y < 0.0:
		return Vector2i(-1, -1)
	var cell := Vector2i(floori(relative.x / pitch), floori(relative.y / pitch))
	return cell if _cell_is_inside(cell) else Vector2i(-1, -1)


func item_rect(uid: String) -> Rect2:
	var entry: Dictionary = _entry_for_uid(uid)
	if entry.is_empty():
		return Rect2()
	return _entry_rect(entry)


func item_at_position(point: Vector2) -> String:
	var cell: Vector2i = cell_at_position(point)
	if not _cell_is_inside(cell):
		return ""
	# Later records are drawn on top if a bad caller snapshot overlaps items.
	for index: int in range(_items.size() - 1, -1, -1):
		var entry: Dictionary = _items[index]
		var origin: Vector2i = entry["cell"]
		var dimensions: Vector2i = entry["size"]
		if cell.x >= origin.x and cell.y >= origin.y \
				and cell.x < origin.x + dimensions.x and cell.y < origin.y + dimensions.y:
			return str(entry["uid"])
	return ""


func _draw() -> void:
	if _outer_style != null and size.x > 0.0 and size.y > 0.0:
		draw_style_box(_outer_style, Rect2(Vector2.ZERO, size))
	var pitch: float = _cell_pitch()
	if pitch <= 0.0:
		return
	var board: Rect2 = grid_rect()
	draw_rect(board, Color("d8c39a"))
	for y: int in range(_rows):
		for x: int in range(_columns):
			var cell: Rect2 = cell_rect(Vector2i(x, y)).grow(-1.0)
			draw_rect(cell, CELL_LIGHT if (x + y) % 2 == 0 else CELL_DARK)
			draw_rect(cell, CELL_LINE, false, 1.0)

	for entry: Dictionary in _items:
		_draw_entry(entry)
	if not _preview_uid.is_empty():
		_draw_drop_preview()


func _draw_entry(entry: Dictionary) -> void:
	var uid: String = str(entry["uid"])
	var box: Rect2 = _entry_rect(entry)
	if not box.has_area():
		return
	var accent: Color = entry["accent"]
	var is_selected: bool = uid == _selected_uid
	var is_hovered: bool = uid == _hovered_uid
	var rarity: String=str(entry.get("art",{}).get("rarity","normal"))
	accent=RarityStyle.border(rarity)
	draw_rect(box.grow(-2.0), RarityStyle.background(rarity).lightened(0.10) if is_selected else RarityStyle.background(rarity))
	var footer_height: float = minf(15.0, box.size.y * 0.34) if _has_caption(entry) else 0.0
	var art_box := Rect2(box.position + Vector2(5.0, 5.0), box.size - Vector2(10.0, 10.0 + footer_height))
	var icon: Variant = entry["icon"]
	if art_box.has_area():
		if str(entry["kind"]) == "currency":
			_draw_currency_stack(art_box,box,int(entry["art"].get("quantity",0)))
		elif str(entry["kind"]) == "flask":
			if icon is Texture2D:
				draw_texture_rect(icon,GemIconLayout.aspect_fit_rect(icon.get_size(),art_box),false)
		elif _is_icon_entry(str(entry["kind"])):
			if icon is Texture2D:
				var fit: Rect2 = GemIconLayout.image_fit_rect(box.size, icon.get_size())
				if fit.has_area():
					draw_texture_rect(icon, Rect2(box.position + fit.position, fit.size), false)
			else:
				_draw_missing_icon_placeholder(entry, art_box)
		else:
			EquipmentArt.draw_item(self, entry["art"], art_box)
	if footer_height > 0.0:
		var caption_box := Rect2(box.position + Vector2(5.0, box.size.y - footer_height - 1.0), Vector2(maxf(0.0, box.size.x - 10.0), footer_height))
		var caption_color: Color = PresentationTheme.ink(accent)
		var font: Font = get_theme_default_font()
		var font_size: int = maxi(8, roundi(minf(11.0, footer_height * 0.8)))
		var caption: String = str(entry["short_name"])
		draw_string(font, Vector2(caption_box.position.x, caption_box.end.y - 2.0), caption,
			HORIZONTAL_ALIGNMENT_CENTER, maxf(0.0, caption_box.size.x), font_size, caption_color)
	var outline: Color = PresentationTheme.GOLD if is_selected else PresentationTheme.ACCENT if is_hovered else accent
	draw_rect(box.grow(-1.5), outline, false, 2.0 if is_selected or is_hovered else 1.0)


func _draw_currency_stack(art_box: Rect2, box: Rect2, quantity: int) -> void:
	# Original small crystal fragments; item quantity is supplied by the owning
	# model, never a second wallet or a local UI counter.
	var center := art_box.get_center()
	var unit := minf(art_box.size.x,art_box.size.y)*0.43
	for offset: Vector2 in [Vector2(-0.35,0.12),Vector2(0.32,0.22),Vector2(0,-0.18)]:
		var c := center+offset*unit
		var points := PackedVector2Array([c+Vector2(0,-unit),c+Vector2(unit*0.5,-unit*0.15),c+Vector2(unit*0.25,unit*0.7),c+Vector2(-unit*0.35,unit*0.45)])
		draw_colored_polygon(points,Color("b48757"))
		draw_polyline(PackedVector2Array([points[0],points[1],points[2],points[3],points[0]]),Color("785533"),1.0,true)
		draw_line(points[0],points[2],Color("ffebaf"),1.4,true)
	var font: Font = get_theme_default_font()
	var label := str(quantity)
	var point_size := 12
	while point_size > 4 and font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x > box.size.x-6.0: point_size -= 1
	var baseline := Vector2(box.position.x+3.0,box.end.y-4.0)
	draw_string_outline(font,baseline,label,HORIZONTAL_ALIGNMENT_RIGHT,box.size.x-6.0,point_size,3,Color("2c2119"))
	draw_string(font,baseline,label,HORIZONTAL_ALIGNMENT_RIGHT,box.size.x-6.0,point_size,Color("fff2cf"))


func _draw_missing_icon_placeholder(entry: Dictionary, rect: Rect2) -> void:
	draw_rect(rect, CELL_LIGHT)
	if rect.size.x > 2.0 and rect.size.y > 2.0:
		draw_rect(rect.grow(-1.0), CELL_LINE, false, 1.0)
	var caption: String = str(entry["short_name"])
	if caption.is_empty():
		caption = "宝石"
	var font: Font = get_theme_default_font()
	var font_size: int = maxi(7, roundi(minf(11.0, rect.size.y * 0.34)))
	draw_string(font, Vector2(rect.position.x, rect.get_center().y + font_size * 0.34), caption,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, PresentationTheme.MUTED)


func _draw_drop_preview() -> void:
	var entry: Dictionary = _drag_entry_for_uid(_preview_uid)
	if entry.is_empty():
		return
	var pitch: float = _cell_pitch()
	var candidate := Rect2(_grid_origin() + Vector2(_preview_destination) * pitch, Vector2(entry["size"]) * pitch)
	var clipped: Rect2 = candidate.intersection(grid_rect())
	if not clipped.has_area():
		return
	var color: Color = DROP_GREEN if _preview_valid else DROP_RED
	var visible: Rect2 = clipped.grow(-1.5)
	if not visible.has_area():
		return
	draw_rect(visible, Color(color, 0.22))
	draw_rect(visible, color, false, 2.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_last_pointer = event.position
		_has_pointer = true
		_update_hover(item_at_position(_last_pointer))
		queue_redraw()
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	var uid: String = item_at_position(event.position)
	if uid.is_empty():
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_selected_uid = uid
		item_selected.emit(uid)
		if event.double_click:
			item_activated.emit(uid)
		queue_redraw()
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_selected_uid = uid
		item_selected.emit(uid)
		item_activated.emit(uid)
		queue_redraw()
		accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	var uid: String = item_at_position(at_position)
	if uid.is_empty():
		return null
	var entry: Dictionary = _entry_for_uid(uid)
	if entry.is_empty():
		return null
	var grab_offset: Vector2i = cell_at_position(at_position) - Vector2i(entry["cell"])
	var dimensions: Vector2i = entry["size"]
	if grab_offset.x < 0 or grab_offset.y < 0 or grab_offset.x >= dimensions.x or grab_offset.y >= dimensions.y:
		return null
	_selected_uid = uid
	item_selected.emit(uid)
	_drop_emitted = false
	_preview_uid = ""
	_preview_destination = Vector2i(-1, -1)
	_preview_valid = false
	queue_redraw()
	return {"type": "unified_item", "uid": uid, "revision": _revision, "grab_offset": grab_offset}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var evaluation: Dictionary = _evaluate_drop(at_position, data)
	queue_redraw()
	return bool(evaluation.get("accepted", false))


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if _drop_emitted:
		return
	var evaluation: Dictionary = _evaluate_drop(at_position, data)
	queue_redraw()
	if not bool(evaluation.get("accepted", false)):
		return
	var uid: String = str(evaluation["uid"])
	var destination: Dictionary = evaluation["destination"]
	var source_revision: int = int(evaluation["revision"])
	_drop_emitted = true
	_preview_uid = ""
	move_requested.emit(uid, destination, source_revision)


func _evaluate_drop(at_position: Vector2, data: Variant) -> Dictionary:
	if not _strict_payload(data):
		_preview_invalid_candidate(at_position, data)
		_preview_valid = false
		return {"accepted": false}
	var uid: String = data["uid"]
	var source_revision: int = data["revision"]
	var grab_offset: Vector2i = data["grab_offset"]
	var entry: Dictionary = _drag_entry_for_uid(uid)
	var pointer_cell: Vector2i = cell_at_position(at_position)
	var destination_cell: Vector2i = pointer_cell - grab_offset
	if not entry.is_empty():
		_preview_uid = uid
		_preview_destination = destination_cell
		_preview_valid = false
	else:
		_preview_uid = ""
		_preview_valid = false
	var accepted: bool = false
	if not entry.is_empty() and source_revision == _revision and _cell_is_inside(pointer_cell):
		var dimensions: Vector2i = entry["size"]
		var offset_fits: bool = grab_offset.x >= 0 and grab_offset.y >= 0 \
				and grab_offset.x < dimensions.x and grab_offset.y < dimensions.y
		var destination_fits: bool = destination_cell.x >= 0 and destination_cell.y >= 0 \
				and destination_cell.x + dimensions.x <= _columns and destination_cell.y + dimensions.y <= _rows
		if offset_fits and destination_fits and _drop_validator.is_valid():
			var destination := {"kind": "bag", "x": destination_cell.x, "y": destination_cell.y}
			if _uses_page_contract: destination["page"] = _page
			var validator_result: Variant = _drop_validator.call(uid, destination, source_revision)
			accepted = bool(validator_result)
			# The validator may synchronously refresh the parent snapshot.
			var revision_still_current: bool = source_revision == _revision
			var item_still_resolves: bool = not _drag_entry_for_uid(uid).is_empty()
			accepted = accepted and revision_still_current and item_still_resolves
	_preview_valid = accepted
	var result: Dictionary = {"accepted": accepted}
	if accepted:
		result["uid"] = uid
		var result_destination := {"kind": "bag", "x": destination_cell.x, "y": destination_cell.y}
		if _uses_page_contract: result_destination["page"] = _page
		result["destination"] = result_destination
		result["revision"] = source_revision
	return result


func _preview_invalid_candidate(at_position: Vector2, data: Variant) -> void:
	_preview_uid = ""
	if not data is Dictionary:
		return
	var candidate_uid: Variant = data.get("uid", "")
	if typeof(candidate_uid) != TYPE_STRING:
		return
	if _drag_entry_for_uid(candidate_uid).is_empty():
		return
	var candidate_offset: Variant = data.get("grab_offset", Vector2i.ZERO)
	var offset: Vector2i = candidate_offset if candidate_offset is Vector2i else Vector2i.ZERO
	_preview_uid = candidate_uid
	_preview_destination = cell_at_position(at_position) - offset


func _process(_delta: float) -> void:
	if not _preview_uid.is_empty() and (not get_viewport().gui_is_dragging()
			or not get_global_rect().has_point(get_global_mouse_position())):
		_preview_uid = ""
		_preview_valid = false
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_drop_emitted = false
	if what == NOTIFICATION_DRAG_END:
		_preview_uid = ""
		_preview_valid = false
		queue_redraw()


func _on_resized() -> void:
	if _has_pointer:
		_update_hover(item_at_position(_last_pointer))
	queue_redraw()


func _on_mouse_exited() -> void:
	_has_pointer = false
	_update_hover("")
	queue_redraw()


func _update_hover(uid: String) -> void:
	if uid == _hovered_uid:
		if not uid.is_empty():
			var next_anchor: Rect2 = get_global_transform() * item_rect(uid)
			if next_anchor != _hover_anchor:
				_hover_anchor = next_anchor
				item_hovered.emit(uid, _hover_anchor)
		return
	if not _hovered_uid.is_empty():
		_hovered_uid = ""
		_hover_anchor = Rect2()
		hover_left.emit()
	if not uid.is_empty():
		_hovered_uid = uid
		_hover_anchor = get_global_transform() * item_rect(uid)
		item_hovered.emit(uid, _hover_anchor)


func _cell_pitch() -> float:
	var available_width: float = maxf(0.0, size.x - EDGE_INSET * 2.0)
	var available_height: float = maxf(0.0, size.y - EDGE_INSET * 2.0)
	return maxf(0.0, minf(MAX_CELL_SIZE, minf(available_width / _columns, available_height / _rows)))


func _grid_origin() -> Vector2:
	var board_size := Vector2(_columns, _rows) * _cell_pitch()
	var free_space: Vector2 = size - board_size
	return Vector2(maxf(EDGE_INSET, free_space.x * 0.5), EDGE_INSET)


func _entry_rect(entry: Dictionary) -> Rect2:
	var pitch: float = _cell_pitch()
	return Rect2(_grid_origin() + Vector2(entry["cell"]) * pitch, Vector2(entry["size"]) * pitch)


func _has_caption(entry: Dictionary) -> bool:
	# Item art and rarity borders identify the grid at a glance; names belong
	# in the shared hover card rather than repeating across every footprint.
	return false


func _entry_for_uid(uid: String) -> Dictionary:
	if uid.is_empty():
		return {}
	for entry: Dictionary in _items:
		if entry["uid"] == uid:
			return entry
	return {}


func _drag_entry_for_uid(uid: String) -> Dictionary:
	var local: Dictionary = _entry_for_uid(uid)
	if not local.is_empty(): return local
	if not _external_item_resolver.is_valid(): return {}
	var value: Variant = _external_item_resolver.call(uid)
	if not value is Dictionary or value.size() != 2 or value.get("uid") != uid or not value.get("size") is Vector2i:
		return {}
	var dimensions: Vector2i = value.size
	if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.x > _columns or dimensions.y > _rows: return {}
	return value.duplicate(true)


func _has_uid(uid: String) -> bool:
	return not _entry_for_uid(uid).is_empty()


func _cell_is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _columns and cell.y < _rows


func _is_icon_entry(kind: String) -> bool:
	return ICON_ENTRY_KINDS.has(kind)


func _strict_payload(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 4:
		return false
	for key: String in ["type", "uid", "revision", "grab_offset"]:
		if not data.has(key):
			return false
	return typeof(data["type"]) == TYPE_STRING and data["type"] == "unified_item" \
		and typeof(data["uid"]) == TYPE_STRING and not data["uid"].is_empty() \
		and typeof(data["revision"]) == TYPE_INT and data["grab_offset"] is Vector2i


func _valid_entry(value: Dictionary) -> bool:
	for key: String in ["uid", "kind", "size", "cell", "art", "icon", "accent", "short_name"]:
		if not value.has(key):
			return false
	if typeof(value["uid"]) != TYPE_STRING or value["uid"].is_empty():
		return false
	if typeof(value["kind"]) != TYPE_STRING or not ENTRY_KINDS.has(value["kind"]):
		return false
	if not value["size"] is Vector2i or not value["cell"] is Vector2i or not value["art"] is Dictionary:
		return false
	if value["icon"] != null and not value["icon"] is Texture2D:
		return false
	if not value["accent"] is Color or typeof(value["short_name"]) != TYPE_STRING:
		return false
	var dimensions: Vector2i = value["size"]
	var cell: Vector2i = value["cell"]
	return dimensions.x > 0 and dimensions.y > 0 and cell.x >= 0 and cell.y >= 0 \
		and cell.x + dimensions.x <= _columns and cell.y + dimensions.y <= _rows
