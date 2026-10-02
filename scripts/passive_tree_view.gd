class_name PassiveTreeView
extends Control
## A retained star-map canvas. Model refreshes never reset its camera or selection.

signal selection_changed(node_id: String)
signal node_activated(node_id: String)
signal viewport_changed

const Passives = preload("res://scripts/passive_data.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const MIN_ZOOM: float = 0.15
const MAX_ZOOM: float = 1.8
const GOLD: Color = Color("d9b779")
const CYAN: Color = Color("78d9ce")
const MUTED: Color = Color("617689")

var zoom: float = 0.34
var pan: Vector2 = Vector2.ZERO
var selected_node_id: String = "origin"
var hovered_node_id: String = ""
var search_query: String = ""
var _state: BuildState
var _nodes: Dictionary = {}
var _edges: Array = []
var _allocated: Dictionary = {}
var _reachable: Dictionary = {}
var _matches: Dictionary = {}
var _dragging: bool = false
var _drag_button: int = MOUSE_BUTTON_NONE


func setup(state: BuildState) -> void:
	_state = state
	name = "TreeViewport"
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(450, 290)
	_nodes = Passives.get_nodes()
	_edges = Passives.get_edges()
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	refresh()


func refresh() -> void:
	_allocated.clear()
	_reachable.clear()
	if _state == null:
		return
	for id: String in _state.allocated_nodes:
		_allocated[id] = true
	for id: String in _nodes:
		if _state.can_allocate(id):
			_reachable[id] = true
	queue_redraw()


func select_node(node_id: String) -> void:
	if not _nodes.has(node_id):
		return
	selected_node_id = node_id
	selection_changed.emit(node_id)
	queue_redraw()


func node_screen_position(node_id: String) -> Vector2:
	if not _nodes.has(node_id):
		return Vector2.INF
	return world_to_screen(_nodes[node_id]["position"] as Vector2)


func world_to_screen(point: Vector2) -> Vector2:
	return size * 0.5 + pan + point * zoom


func screen_to_world(point: Vector2) -> Vector2:
	return (point - size * 0.5 - pan) / zoom


func set_zoom(value: float, anchor: Vector2 = Vector2(-1, -1)) -> void:
	if anchor.x < 0.0 or anchor.y < 0.0:
		anchor = size * 0.5
	var world_anchor: Vector2 = screen_to_world(anchor)
	zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	pan = anchor - size * 0.5 - world_anchor * zoom
	_clamp_pan()
	viewport_changed.emit()
	queue_redraw()


func center_origin() -> void:
	zoom = 0.34
	pan = Vector2.ZERO
	viewport_changed.emit()
	queue_redraw()


func center_on_node(node_id: String) -> void:
	if not _nodes.has(node_id):
		return
	zoom = maxf(zoom, 0.5)
	pan = -(_nodes[node_id]["position"] as Vector2) * zoom
	viewport_changed.emit()
	queue_redraw()


func fit_tree() -> void:
	if _nodes.is_empty():
		return
	var bounds: Rect2 = _tree_bounds()
	var available: Vector2 = (size - Vector2(100, 84)).max(Vector2(100, 100))
	zoom = clampf(minf(available.x / bounds.size.x, available.y / bounds.size.y), MIN_ZOOM, MAX_ZOOM)
	pan = -bounds.get_center() * zoom
	viewport_changed.emit()
	queue_redraw()


func set_search_query(query: String) -> void:
	search_query = query.strip_edges()
	_matches.clear()
	if not search_query.is_empty():
		for id: String in _nodes:
			var node: Dictionary = _nodes[id] as Dictionary
			if (str(node.get("name", "")) + " " + str(node.get("description", ""))).contains(search_query):
				_matches[id] = true
	queue_redraw()


func focus_first_match() -> void:
	if not _matches.is_empty():
		var id: String = str(_matches.keys()[0])
		select_node(id)
		center_on_node(id)


func get_search_match_count() -> int:
	return _matches.size()


func _tree_bounds() -> Rect2:
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2.ONE)
	for node: Dictionary in _nodes.values():
		bounds = bounds.expand(node["position"] as Vector2)
	return bounds.grow(48)


func _clamp_pan() -> void:
	var limit: Vector2 = _tree_bounds().size * zoom * 0.65 + size * 0.45
	pan = pan.clamp(-limit, limit)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				set_zoom(zoom * (1.15 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), button.position)
			accept_event()
			return
		if button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			if button.pressed:
				var id: String = _hit_node(button.position)
				if button.button_index == MOUSE_BUTTON_MIDDLE or id.is_empty():
					_dragging = true
					_drag_button = button.button_index
					mouse_default_cursor_shape = Control.CURSOR_DRAG
				else:
					select_node(id)
					if button.double_click:
						node_activated.emit(id)
			elif button.button_index == _drag_button:
				_dragging = false
				_drag_button = MOUSE_BUTTON_NONE
				mouse_default_cursor_shape = Control.CURSOR_ARROW
			accept_event()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _dragging:
			pan += motion.relative
			_clamp_pan()
			viewport_changed.emit()
			queue_redraw()
		else:
			var id: String = _hit_node(motion.position)
			if id != hovered_node_id:
				hovered_node_id = id
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not id.is_empty() else Control.CURSOR_ARROW
				queue_redraw()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_dragging = false
		_drag_button = MOUSE_BUTTON_NONE


func _on_mouse_exited() -> void:
	hovered_node_id = ""
	queue_redraw()


func _hit_node(point: Vector2) -> String:
	var closest: String = ""
	var closest_distance: float = INF
	for id: String in _nodes:
		var node: Dictionary = _nodes[id] as Dictionary
		var distance: float = point.distance_to(node_screen_position(id))
		var radius: float = _node_radius(node) + 5.0
		if distance <= radius and distance < closest_distance:
			closest = id
			closest_distance = distance
	return closest


func _get_tooltip(at_position: Vector2) -> String:
	var id: String = _hit_node(at_position)
	if id.is_empty():
		return "拖动空白处或按住中键平移；滚轮缩放"
	var node: Dictionary = _nodes[id] as Dictionary
	var status: String = "已点亮" if _allocated.has(id) else ("可分配 · 消耗 1 点" if _reachable.has(id) else "尚未连接")
	if id == "origin":
		status = "星图起点 · 永久点亮"
	var description: String = str(node.get("description", ""))
	if str(node.get("type", "")) == "socket" and _state != null:
		var jewel: Dictionary = _state.get_jewel_at(id)
		if not jewel.is_empty():
			description = Jewels.display_name(jewel) + "\n" + Jewels.get_description(jewel)
	return "%s  ·  %s\n%s\n单击查看详情" % [str(node.get("name", id)), status, description]


func _node_radius(node: Dictionary) -> float:
	match str(node.get("type", "small")):
		"start": return maxf(14.0, 25.0 * zoom)
		"notable": return maxf(7.0, 16.0 * zoom)
		"socket": return maxf(7.0, 15.0 * zoom)
		_: return maxf(3.8, 8.5 * zoom)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d1a1b"))
	_draw_backdrop()
	if _state == null:
		return
	for edge: Array in _edges:
		var a: String = str(edge[0])
		var b: String = str(edge[1])
		var color: Color = Color("26364b")
		var width: float = 1.2
		if _allocated.has(a) and _allocated.has(b):
			color = GOLD.darkened(0.22)
			width = 2.4
		elif (_allocated.has(a) and _reachable.has(b)) or (_allocated.has(b) and _reachable.has(a)):
			color = CYAN.darkened(0.3)
			width = 1.7
		draw_line(node_screen_position(a), node_screen_position(b), color, width, true)
	for id: String in _nodes:
		_draw_node(id, _nodes[id] as Dictionary)
	_draw_map_labels()
	_draw_minimap()
	var font: Font = get_theme_default_font()
	draw_string(font, Vector2(15, 23), "星脉图谱", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("91aabd"))
	draw_string(font, Vector2(15, size.y - 16), "拖动空白平移  ·  滚轮缩放  ·  双击分配", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("7890a5"))


func _draw_backdrop() -> void:
	# Deterministic decorative stars: no random generator or mutable world state.
	for i: int in range(95):
		var p: Vector2 = Vector2(fmod(float(i * 137 + 19), maxf(size.x, 1)), fmod(float(i * 83 + 43), maxf(size.y, 1)))
		var color: Color = Color(0.36, 0.51, 0.66, 0.14 + float(i % 4) * 0.035)
		draw_circle(p, 0.7 if i % 5 else 1.2, color)
	var origin: Vector2 = world_to_screen(Vector2.ZERO)
	for radius: float in [200.0, 450.0, 700.0, 950.0, 1120.0]:
		draw_arc(origin, radius * zoom, 0, TAU, 144, Color(0.25, 0.42, 0.56, 0.07), 1.0, true)
	for i: int in range(6):
		var angle: float = float(i) * TAU / 6.0
		draw_line(origin + Vector2.from_angle(angle) * 85.0 * zoom, origin + Vector2.from_angle(angle) * 1190.0 * zoom, Color(0.25, 0.42, 0.56, 0.06), 1.0, true)


func _draw_node(id: String, node: Dictionary) -> void:
	var p: Vector2 = node_screen_position(id)
	var radius: float = _node_radius(node)
	if not Rect2(Vector2.ZERO, size).grow(radius + 12).has_point(p):
		return
	var allocated: bool = _allocated.has(id)
	var reachable: bool = _reachable.has(id)
	var type: String = str(node.get("type", "small"))
	var color: Color = GOLD if allocated else (CYAN if reachable else MUTED)
	var fill: Color = Color("101d2d")
	if allocated:
		fill = Color("59492d")
	elif reachable:
		fill = Color("183b46")
	if not search_query.is_empty() and not _matches.has(id):
		color = color.darkened(0.56)
		fill = fill.darkened(0.45)
	if selected_node_id == id:
		draw_circle(p, radius + 9.0, Color(0.45, 0.85, 0.94, 0.1))
		draw_arc(p, radius + 6.0, 0, TAU, 48, Color("eaf4f7"), 1.2, true)
	elif hovered_node_id == id or _matches.has(id):
		draw_arc(p, radius + 4.0, 0, TAU, 36, CYAN if hovered_node_id == id else GOLD, 1.2, true)
	if type == "socket":
		var jewel: Dictionary = _state.get_jewel_at(id)
		if not jewel.is_empty():
			color = _jewel_color(jewel)
			fill = color.darkened(0.65)
			if allocated:
				draw_circle(p, radius + 4.0, Color(color.r, color.g, color.b, 0.14))
		var diamond: PackedVector2Array = PackedVector2Array([p + Vector2(0, -radius), p + Vector2(radius, 0), p + Vector2(0, radius), p + Vector2(-radius, 0)])
		draw_colored_polygon(diamond, fill)
		diamond.append(diamond[0])
		draw_polyline(diamond, color, 1.7, true)
		if not jewel.is_empty():
			draw_line(p + Vector2(0, -radius * 0.6), p + Vector2(radius * 0.45, 0), color, 1.2, true)
			draw_line(p + Vector2(radius * 0.45, 0), p + Vector2(0, radius * 0.6), color, 1.2, true)
			draw_line(p + Vector2(-radius * 0.5, 0), p + Vector2(radius * 0.5, 0), color, 1.0, true)
		else:
			draw_circle(p, 1.5, color)
	elif type == "start":
		draw_circle(p, radius + 3, Color("172c3b"))
		draw_arc(p, radius + 1, 0, TAU, 48, GOLD, 1.5, true)
		var star: PackedVector2Array = PackedVector2Array()
		for i: int in range(8):
			star.append(p + Vector2.from_angle(float(i) * TAU / 8.0 - PI / 2.0) * (radius * 0.8 if i % 2 == 0 else radius * 0.3))
		draw_colored_polygon(star, GOLD)
	elif type == "notable":
		draw_circle(p, radius, fill)
		draw_arc(p, radius, 0, TAU, 36, color, 2.0, true)
		for i: int in range(4):
			var direction: Vector2 = Vector2.from_angle(float(i) * PI / 2.0)
			draw_line(p + direction * (radius + 2), p + direction * (radius + 4), color, 1.3, true)
		draw_circle(p, radius * 0.35, color)
	else:
		draw_circle(p, radius, fill)
		draw_arc(p, radius, 0, TAU, 24, color, 1.5 if allocated or reachable else 1.0, true)
		if allocated:
			draw_circle(p, radius * 0.4, color)


func _jewel_color(jewel: Dictionary) -> Color:
	var base_id: String = str(jewel.get("base", ""))
	if Jewels.BASES.has(base_id):
		return Jewels.BASES[base_id].get("color", Color("b4a1ff")) as Color
	return Color("b4a1ff")


func _draw_map_labels() -> void:
	var font: Font = get_theme_default_font()
	for sector: Dictionary in Passives.SECTORS:
		var angle: float = deg_to_rad(float(sector.get("angle", 0.0)))
		var p: Vector2 = world_to_screen(Vector2.from_angle(angle) * 1180.0)
		var caption: String = str(sector.get("name", ""))
		var width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var color: Color = sector.get("color", MUTED) as Color
		draw_string(font, p - Vector2(width * 0.5, -5.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color.darkened(0.12))


func _draw_minimap() -> void:
	var rect: Rect2 = Rect2(Vector2(size.x - 133, size.y - 100), Vector2(119, 84))
	draw_style_box(_minimap_style(), rect)
	var bounds: Rect2 = _tree_bounds()
	var scale_value: float = minf((rect.size.x - 12) / bounds.size.x, (rect.size.y - 12) / bounds.size.y)
	var center: Vector2 = rect.get_center()
	for edge: Array in _edges:
		var a: Vector2 = _nodes[str(edge[0])]["position"] as Vector2
		var b: Vector2 = _nodes[str(edge[1])]["position"] as Vector2
		draw_line(center + a * scale_value, center + b * scale_value, Color("32445a"), 0.7, true)
	for id: String in _allocated:
		if _nodes.has(id):
			draw_circle(center + (_nodes[id]["position"] as Vector2) * scale_value, 1.7, GOLD)
	var visible_rect: Rect2 = Rect2(center + screen_to_world(Vector2.ZERO) * scale_value, size / zoom * scale_value)
	visible_rect = visible_rect.intersection(rect.grow(-2))
	if visible_rect.has_area():
		draw_rect(visible_rect, Color(0.4, 0.8, 0.85, 0.10))
		draw_rect(visible_rect, Color("6a9daa"), false, 1.0)


func _minimap_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.065, 0.11, 0.94)
	style.border_color = Color("273c50")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style
