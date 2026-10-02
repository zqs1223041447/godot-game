class_name ItemGridView
extends Control
## Original, code-drawn ARPG item grid. The model owns all occupancy transactions.

signal item_selected(key: String)
signal item_activated(key: String)
signal feedback(message: String)

const Data = preload("res://scripts/game_data.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const EquipmentVisuals = preload("res://scripts/visuals/equipment_art.gd")
const COLUMNS: int = 12
const ROWS: int = 8
const CELL: float = 42.0
const INSET: float = 8.0
const TEXT: Color = Color("eee2c7")
const MUTED: Color = Color("a3987e")
const CYAN: Color = Color("b8c891")
const GOLD: Color = Color("d8b577")
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
		var accent: Color = entry.get("color", Color("b8c891"))
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
	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), Color("201f18"))
	draw_rect(Rect2(Vector2.ONE, custom_minimum_size - Vector2(2, 2)), Color("786e51"), false, 1.0)
	for y: int in range(ROWS):
		for x: int in range(COLUMNS):
			var cell_rect := Rect2(Vector2(x, y) * CELL + grid_rect.position, Vector2.ONE * CELL)
			draw_rect(cell_rect.grow(-1.0), Color("302e24") if (x + y) % 2 == 0 else Color("2a2a20"))
			draw_rect(cell_rect.grow(-1.0), Color("4a4937"), false, 1.0)
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
	EquipmentVisuals.draw_item(canvas,entry,rect)
