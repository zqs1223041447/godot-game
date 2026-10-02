class_name ItemGridView
extends Control
## Original, code-drawn ARPG item grid. The model owns all occupancy transactions.

signal item_selected(key: String)
signal item_activated(key: String)
signal feedback(message: String)

const Data = preload("res://scripts/game_data.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const COLUMNS: int = 12
const ROWS: int = 8
const CELL: float = 42.0
const INSET: float = 8.0
const TEXT: Color = Color("eee9dd")
const MUTED: Color = Color("8399aa")
const CYAN: Color = Color("78d9ce")
const GOLD: Color = Color("d9b779")
const RED: Color = Color("f27786")
const GREEN: Color = Color("85e2b6")

var state: BuildState
var selected_key: String = ""
var _hovered_key: String = ""
var _ghost_key: String = ""
var _ghost_cell: Vector2i = Vector2i(-1, -1)
var _ghost_valid: bool = false


class ItemArt extends Control:
	var entry: Dictionary = {}
	var draw_border: bool = true

	func _draw() -> void:
		var accent: Color = entry.get("color", Color("78d9ce"))
		if draw_border:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.065, 0.105, 0.94))
			draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), accent, false, 2.0)
		ItemGridView.draw_item_icon(self, entry, Rect2(Vector2(4, 4), size - Vector2(8, 8)))


func _ready() -> void:
	name = "InventoryGrid"
	custom_minimum_size = Vector2(COLUMNS * CELL + INSET * 2.0, ROWS * CELL + INSET * 2.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)
	set_process(true)


func setup(build_state: BuildState) -> void:
	state = build_state
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func select_item(key: String) -> void:
	selected_key = key
	queue_redraw()


func cell_at_position(point: Vector2) -> Vector2i:
	return Vector2i(floori((point.x - INSET) / CELL), floori((point.y - INSET) / CELL))


func item_rect(key: String) -> Rect2:
	if state == null or not state.backpack_positions.has(key):
		return Rect2()
	var cell: Vector2i = state.backpack_positions[key]
	return Rect2(Vector2(cell) * CELL + Vector2(INSET, INSET), Vector2(state.item_size(key)) * CELL)


func item_at_position(point: Vector2) -> String:
	if state == null:
		return ""
	for key: String in state.get_backpack_items():
		if item_rect(key).has_point(point):
			return key
	return ""


func _draw() -> void:
	var grid_rect := Rect2(Vector2(INSET, INSET), Vector2(COLUMNS, ROWS) * CELL)
	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), Color("080f19"))
	draw_rect(Rect2(Vector2.ONE, custom_minimum_size - Vector2(2, 2)), Color("465566"), false, 1.0)
	for y: int in range(ROWS):
		for x: int in range(COLUMNS):
			var cell_rect := Rect2(Vector2(x, y) * CELL + grid_rect.position, Vector2.ONE * CELL)
			draw_rect(cell_rect.grow(-1.0), Color("182b2a") if (x + y) % 2 == 0 else Color("142423"))
			draw_rect(cell_rect.grow(-1.0), Color("30433c"), false, 1.0)
	if state == null:
		return
	var font: Font = get_theme_default_font()
	for key: String in state.get_backpack_items():
		var box: Rect2 = item_rect(key).grow(-2.0)
		var entry: Dictionary = describe_item(state, key)
		var accent: Color = entry.get("color", CYAN)
		var selected: bool = key == selected_key
		var hovered: bool = key == _hovered_key
		draw_rect(box, Color("203345") if selected else accent.darkened(0.82))
		draw_rect(box, CYAN if selected else accent.darkened(0.30 if hovered else 0.52), false, 2.0 if selected or hovered else 1.0)
		draw_rect(Rect2(box.position + Vector2(3, 3), Vector2(3, 10)), accent)
		var art_rect: Rect2 = box.grow(-5.0)
		if box.size.y > CELL * 1.2:
			art_rect.size.y -= 21.0
		draw_item_icon(self, entry, art_rect)
		if box.size.y > CELL * 1.2:
			var caption: String = str(entry.get("short_name", "装备"))
			var caption_width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, Vector2(box.get_center().x - caption_width / 2.0, box.end.y - 7.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, accent)
	if not _ghost_key.is_empty():
		var ghost_box := Rect2(Vector2(_ghost_cell) * CELL + grid_rect.position, Vector2(state.item_size(_ghost_key)) * CELL)
		var ghost_color: Color = GREEN if _ghost_valid else RED
		# Clip a rejected out-of-bounds ghost to the actual bag; never hide a valid footprint.
		var clipped: Rect2 = ghost_box.intersection(grid_rect)
		if clipped.has_area():
			draw_rect(clipped.grow(-2.0), Color(ghost_color, 0.24))
			draw_rect(clipped.grow(-2.0), ghost_color, false, 2.5)
			draw_string(font, clipped.position + Vector2(7, 18), "可放" if _ghost_valid else "禁止", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ghost_color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var next_hover: String = item_at_position(event.position)
		if next_hover != _hovered_key:
			_hovered_key = next_hover
			tooltip_text = item_tooltip(state, next_hover) if not next_hover.is_empty() else "拖动物品整理背包；多格装备不能重叠或越界"
			queue_redraw()
	if event is InputEventMouseButton and event.pressed:
		var key: String = item_at_position(event.position)
		if key.is_empty():
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			selected_key = key
			item_selected.emit(key)
			queue_redraw()
			if event.double_click:
				item_activated.emit(key)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			selected_key = key
			item_selected.emit(key)
			item_activated.emit(key)
			accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	var key: String = item_at_position(at_position)
	if key.is_empty():
		return null
	selected_key = key
	item_selected.emit(key)
	var offset: Vector2i = cell_at_position(at_position) - Vector2i(state.backpack_positions[key])
	set_drag_preview(make_drag_preview(describe_item(state, key), Vector2(state.item_size(key)) * CELL, Vector2(offset) * CELL + Vector2(CELL / 2.0, CELL / 2.0)))
	queue_redraw()
	return {"type": "inventory_item", "key": key, "grab_offset": offset}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if state == null or not is_item_drag(data):
		return false
	_ghost_key = str(data["key"])
	_ghost_cell = cell_at_position(at_position) - Vector2i(data.get("grab_offset", Vector2i.ZERO))
	_ghost_valid = state.can_place_in_backpack(_ghost_key, _ghost_cell)
	queue_redraw()
	return _ghost_valid


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not is_item_drag(data):
		return
	var key: String = str(data["key"])
	var destination: Vector2i = cell_at_position(at_position) - Vector2i(data.get("grab_offset", Vector2i.ZERO))
	var moved: bool = false
	if key.begins_with("item:"):
		var slot: String = str(state.get_item_definition(key.substr(5)).get("slot", ""))
		if state.equipped.get(slot, "") == key.substr(5):
			moved = state.unequip_to_backpack(slot, destination)
		else:
			moved = state.move_in_backpack(key, destination)
	else:
		moved = state.move_in_backpack(key, destination)
	if moved:
		selected_key = key
		item_selected.emit(key)
		feedback.emit("已放入背包 · " + str(describe_item(state, key).get("name", "物品")))
	_clear_ghost()


func _process(_delta: float) -> void:
	if not _ghost_key.is_empty() and (not get_viewport().gui_is_dragging() or not get_global_rect().has_point(get_global_mouse_position())):
		_clear_ghost()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_ghost()


func _on_mouse_exited() -> void:
	_hovered_key = ""
	queue_redraw()


func _clear_ghost() -> void:
	_ghost_key = ""
	_ghost_cell = Vector2i(-1, -1)
	queue_redraw()


static func is_item_drag(data: Variant) -> bool:
	return data is Dictionary and data.get("type", "") == "inventory_item" and data.get("key") is String and data.get("grab_offset", Vector2i.ZERO) is Vector2i


static func make_drag_preview(entry: Dictionary, dimensions: Vector2, offset: Vector2 = Vector2(20, 20)) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := ItemArt.new()
	art.entry = entry
	art.size = dimensions
	art.position = -offset
	art.modulate.a = 0.88
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(art)
	return root


static func describe_item(build: BuildState, key: String) -> Dictionary:
	if key.begins_with("item:"):
		var id: String = key.substr(5)
		var entry: Dictionary = build.get_item_definition(id).duplicate(true)
		if entry.is_empty():
			return {}
		entry["id"] = id
		entry["kind"] = "gear"
		var rarity: String = str(entry.get("rarity", "magic" if id in ["guardian_robe", "azure_charm", "ember_wand"] else "rare"))
		entry["color"] = {"normal":Color("d6ded8"),"magic":Color("8dbaff"),"rare":GOLD,"unique":Color("e9a877")}.get(rarity,GOLD)
		entry["rarity_name"] = {"normal":"普通","magic":"魔法","rare":"稀有","unique":"传奇"}.get(rarity,"装备")
		entry["short_name"] = {"weapon": "长弓" if id == "prism_bow" else "法杖" if id in ["ember_wand","cinder_reed"] or str(entry.get("base_name","")).ends_with("杖") else "短刃", "armor": "披风" if id == "return_mantle" else "长袍" if id == "guardian_robe" or str(entry.get("base_name","")).ends_with("袍") else "轻甲", "charm": "护符"}.get(entry.get("slot", ""), "装备")
		return entry
	if key.begins_with("jewel:"):
		var id: String = key.substr(6)
		var jewel: Dictionary = build.jewels.get(id, {})
		if jewel.is_empty():
			return {}
		return {"id": id, "kind": "jewel", "name": Jewels.display_name(jewel), "short_name": "珠宝", "color": Jewels.get_color(jewel), "base": jewel.get("base", ""), "description": Jewels.get_description(jewel), "stats": Jewels.get_stats(jewel), "rarity_name": Jewels.RARITIES[jewel["rarity"]]["name"], "affixes": jewel.get("affixes", [])}
	return {}


static func item_tooltip(build: BuildState, key: String) -> String:
	if build == null or key.is_empty():
		return ""
	var entry: Dictionary = describe_item(build, key)
	var dimensions: Vector2i = build.item_size(key)
	return "%s\n%s\n占用 %d × %d 格 · 拖动整理\n%s" % [entry.get("name", "物品"), entry.get("description", ""), dimensions.x, dimensions.y, "双击前往天赋星图镶嵌" if entry.get("kind") == "jewel" else "双击或右键装备；可拖到左侧对应部位"]


static func draw_item_icon(canvas: CanvasItem, entry: Dictionary, rect: Rect2) -> void:
	if not rect.has_area():
		return
	var accent: Color = entry.get("color", CYAN)
	var center: Vector2 = rect.get_center()
	var unit: float = minf(rect.size.x, rect.size.y) * 0.36
	var id: String = str(entry.get("base_id", entry.get("id", "")))
	if entry.get("kind", "") == "jewel":
		var gem_color: Color = Jewels.BASES.get(entry.get("base", ""), {}).get("color", accent)
		var diamond := PackedVector2Array([center + Vector2(0, -unit), center + Vector2(unit * 0.76, -unit * 0.15), center + Vector2(unit * 0.48, unit * 0.70), center + Vector2(-unit * 0.48, unit * 0.70), center + Vector2(-unit * 0.76, -unit * 0.15)])
		canvas.draw_colored_polygon(diamond, gem_color.darkened(0.27))
		canvas.draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[4], diamond[0]]), accent, 1.8, true)
		canvas.draw_line(diamond[0], center + Vector2(0, unit * 0.6), gem_color.lightened(0.35), 1.0, true)
		canvas.draw_line(diamond[4], diamond[1], gem_color.lightened(0.35), 1.0, true)
		canvas.draw_line(diamond[4], center + Vector2(0, unit * 0.6), gem_color, 1.0, true)
		return
	match str(entry.get("slot", "")):
		"weapon":
			var length: float = minf(rect.size.y * 0.67, rect.size.x * 2.0)
			if id == "prism_bow":
				var bow_points := PackedVector2Array()
				for i: int in range(25):
					var angle: float = lerpf(-PI/2,PI/2,i/24.0)
					bow_points.append(center+Vector2(cos(angle)*unit*0.85-unit*0.3,sin(angle)*length*0.52))
				canvas.draw_polyline(bow_points,Color("9fbfb6"),4,true)
				canvas.draw_line(bow_points[0],bow_points[-1],Color("dcceb3"),1,true)
				canvas.draw_line(center+Vector2(-unit*0.6,0),center+Vector2(unit*1.2,0),GOLD,2,true)
				canvas.draw_colored_polygon(PackedVector2Array([center+Vector2(unit*1.3,0),center+Vector2(unit*0.8,-4),center+Vector2(unit*0.8,4)]),accent)
			elif id in ["ember_wand","cinder_reed"] or str(entry.get("base_name","")).ends_with("杖"):
				canvas.draw_line(center + Vector2(-unit * 0.18, length * 0.5), center + Vector2(unit * 0.14, -length * 0.30), Color("b08b58"), 5.0, true)
				canvas.draw_line(center + Vector2(-unit * 0.22, length * 0.43), center + Vector2(unit * 0.08, -length * 0.22), GOLD.lightened(0.1), 1.2, true)
				var head: Vector2 = center + Vector2(unit * 0.15, -length * 0.40)
				canvas.draw_circle(head, unit * 0.8, Color(accent, 0.08))
				canvas.draw_colored_polygon(PackedVector2Array([head + Vector2(0, -unit * 0.72), head + Vector2(unit * 0.6, 0), head + Vector2(0, unit * 0.72), head + Vector2(-unit * 0.6, 0)]), Color("f6af78"))
				canvas.draw_line(head + Vector2(-unit * 0.65, 0), head + Vector2(0, unit * 0.8), GOLD, 2, true)
				canvas.draw_line(head + Vector2(unit * 0.65, 0), head + Vector2(0, unit * 0.8), GOLD, 2, true)
			else:
				var tip: Vector2 = center + Vector2(unit * 0.25, -length * 0.56)
				var guard: Vector2 = center + Vector2(-unit * 0.1, length * 0.2)
				canvas.draw_colored_polygon(PackedVector2Array([tip, guard + Vector2(unit * 0.44, 0), guard + Vector2(-unit * 0.34, 0)]), Color("afcad9"))
				canvas.draw_line(tip, guard, Color("eef6ff"), 1.6, true)
				canvas.draw_line(guard + Vector2(-unit * 0.7, 0), guard + Vector2(unit * 0.75, 0), GOLD, 4, true)
				canvas.draw_line(guard, center + Vector2(-unit * 0.2, length * 0.47), Color("a47650"), 5, true)
				canvas.draw_circle(center + Vector2(-unit * 0.2, length * 0.48), 3.0, GOLD)
		"armor":
			var h: float = minf(rect.size.y * 0.40, rect.size.x * 0.67)
			var w: float = minf(rect.size.x * 0.31, h * 0.80)
			var robe: bool = id in ["guardian_robe","return_mantle","tidebound_coat"] or str(entry.get("base_name","")).ends_with("袍")
			var outline := PackedVector2Array([center + Vector2(-w * 0.46, -h), center + Vector2(-w * 1.2, -h * 0.7), center + Vector2(-w * 1.3, -h * 0.08), center + Vector2(-w * 0.74, h * 0.06), center + Vector2(-w * 0.81 if robe else -w * 0.67, h), center + Vector2(w * 0.81 if robe else w * 0.67, h), center + Vector2(w * 0.74, h * 0.06), center + Vector2(w * 1.3, -h * 0.08), center + Vector2(w * 1.2, -h * 0.7), center + Vector2(w * 0.46, -h), center + Vector2(0, -h * 0.66)])
			canvas.draw_colored_polygon(outline, Color("42678e") if robe else Color("778973"))
			var closed: PackedVector2Array = outline.duplicate()
			closed.append(outline[0])
			canvas.draw_polyline(closed, accent, 1.8, true)
			canvas.draw_line(center + Vector2(0, -h * 0.65), center + Vector2(0, h * 0.91), accent, 2, true)
			canvas.draw_line(center + Vector2(-w * 0.7, h * 0.24), center + Vector2(w * 0.7, h * 0.24), GOLD, 2.5, true)
			if not robe:
				canvas.draw_polyline(PackedVector2Array([center + Vector2(-w * 0.6, -h * 0.4), center + Vector2(0, -h * 0.13), center + Vector2(w * 0.6, -h * 0.4)]), GOLD, 2, true)
		"charm":
			canvas.draw_arc(center + Vector2(0, -unit * 0.2), unit * 0.65, PI * 0.75, PI * 2.25, 24, GOLD.darkened(0.05), 2.0, true)
			var gem: Vector2 = center + Vector2(0, unit * 0.45)
			canvas.draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -unit * 0.63), gem + Vector2(unit * 0.53, 0), gem + Vector2(0, unit * 0.57), gem + Vector2(-unit * 0.53, 0)]), Color("6ebfdb") if id == "azure_charm" else Color("dcc883"))
			canvas.draw_circle(gem, 2.0, Color("ecf9ff"))
		_:
			canvas.draw_circle(center, unit * 0.5, accent)
