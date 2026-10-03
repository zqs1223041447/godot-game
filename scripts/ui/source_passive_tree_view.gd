class_name SourcePassiveTreeView
extends Control
## Read-only canvas for a caller-supplied passive topology.
## The camera changes only the view transform; node coordinates and edges remain intact.

signal node_clicked(id: String, button: int, double_click: bool)
signal node_hovered(id: String, anchor: Rect2)
signal hover_left

const MIN_ZOOM: float = 0.005
const MAX_ZOOM: float = 2.0
const DEFAULT_ZOOM: float = 0.22
const WORLD_GRID_CELL: float = 1024.0
const CLICK_PADDING: float = 5.5
const DRAG_THRESHOLD: float = 7.0

const PAPER: Color = Color("f1deb3")
const INK: Color = Color("3b281b")
const MUTED_INK: Color = Color("69523a")
const COPPER: Color = Color("8c6b42")
const GOLD: Color = Color("a27742")
const OLIVE: Color = Color("52623b")
const BURGUNDY: Color = Color("7a2f29")
const PARCHMENT_TEXTURE: Texture2D = preload("res://assets/ui/grimoire/parchment.png")

var zoom: float = DEFAULT_ZOOM
var pan: Vector2 = Vector2.ZERO

var _nodes: Dictionary = {}
var _node_order: Array[String] = []
var _edges: Array[Dictionary] = []
var _edge_positions: PackedVector2Array = PackedVector2Array()
var _world_grid: Dictionary = {}
var _tree_bounds: Rect2 = Rect2(Vector2.ZERO, Vector2.ONE)
var _focus_id: String = ""
var _tree_loaded: bool = false

var _allocated: Dictionary = {}
var _available: Dictionary = {}
var _remote: Dictionary = {}
var _socket_ranges: Array[Dictionary] = []
var _selected_id: String = ""

var _hovered_id: String = ""
var _hover_anchor: Rect2 = Rect2()
var _last_mouse_position: Vector2 = Vector2.ZERO
var _has_mouse_position: bool = false
var _press_active: bool = false
var _press_button: int = MOUSE_BUTTON_NONE
var _press_start: Vector2 = Vector2.ZERO
var _press_node_id: String = ""
var _press_double_click: bool = false
var _pan_candidate: bool = false
var _dragging: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)

func _make_custom_tooltip(text:String)->Object:
	return preload("res://scripts/ui/crafting_controls.gd").wrapped_tooltip(self,text)


## Atomically replaces the displayed graph after validating every node and edge.
## A blank focus_id is allowed; any nonblank focus must name an input node.
func set_tree(nodes: Dictionary, edges: Array, focus_id: String) -> bool:
	if not focus_id.is_empty() and not nodes.has(focus_id):
		return false
	var next_nodes: Dictionary = {}
	var next_order: Array[String] = []
	var next_bounds: Rect2 = Rect2()
	var first_node: bool = true
	for key: Variant in nodes:
		if typeof(key) != TYPE_STRING:
			return false
		var id: String = String(key)
		var source_node: Variant = nodes[key]
		if typeof(source_node) != TYPE_DICTIONARY:
			return false
		var raw_node: Dictionary = source_node
		if not raw_node.has("id") or typeof(raw_node["id"]) != TYPE_STRING or String(raw_node["id"]) != id:
			return false
		if not raw_node.has("position") or typeof(raw_node["position"]) != TYPE_VECTOR2:
			return false
		var position: Vector2 = raw_node["position"]
		if not is_finite(position.x) or not is_finite(position.y):
			return false
		for field: String in ["type", "name", "description", "status"]:
			if not raw_node.has(field) or typeof(raw_node[field]) != TYPE_STRING:
				return false
		var node_type: String = String(raw_node["type"])
		if node_type not in ["small", "notable", "keystone", "mastery", "socket", "start"]:
			return false
		var snapshot: Dictionary = {
			"id": id,
			"position": position,
			"type": node_type,
			"name": String(raw_node["name"]),
			"description": String(raw_node["description"]),
			"status": String(raw_node["status"]),
		}
		next_nodes[id] = snapshot
		next_order.append(id)
		if first_node:
			next_bounds = Rect2(position, Vector2.ZERO)
			first_node = false
		else:
			next_bounds = next_bounds.expand(position)

	var next_edges: Array[Dictionary] = []
	var next_edge_positions: PackedVector2Array = PackedVector2Array()
	for raw_edge_variant: Variant in edges:
		if typeof(raw_edge_variant) != TYPE_DICTIONARY:
			return false
		var raw_edge: Dictionary = raw_edge_variant
		if not raw_edge.has("a") or not raw_edge.has("b"):
			return false
		if typeof(raw_edge["a"]) != TYPE_STRING or typeof(raw_edge["b"]) != TYPE_STRING:
			return false
		var a: String = String(raw_edge["a"])
		var b: String = String(raw_edge["b"])
		if not next_nodes.has(a) or not next_nodes.has(b):
			return false
		next_edges.append({"a": a, "b": b})
		next_edge_positions.append(next_nodes[a]["position"])
		next_edge_positions.append(next_nodes[b]["position"])
	if not focus_id.is_empty() and not next_nodes.has(focus_id):
		return false

	var unchanged: bool = _tree_loaded and _nodes == next_nodes and _edges == next_edges and _focus_id == focus_id
	if unchanged:
		return true
	var keep_camera: bool = _tree_loaded and _focus_id == focus_id
	if keep_camera and not focus_id.is_empty():
		keep_camera = _nodes.has(focus_id) and _nodes[focus_id]["position"] == next_nodes[focus_id]["position"]
	_nodes = next_nodes
	_node_order = next_order
	_edges = next_edges
	_edge_positions = next_edge_positions
	_tree_bounds = next_bounds.grow(48.0) if not first_node else Rect2(Vector2.ZERO, Vector2.ONE)
	_focus_id = focus_id
	_tree_loaded = true
	_build_world_grid()
	if not keep_camera:
		zoom = DEFAULT_ZOOM
		if not focus_id.is_empty():
			pan = -(_nodes[focus_id]["position"] as Vector2) * zoom
		else:
			pan = Vector2.ZERO
	_update_hover_at_last_position()
	queue_redraw()
	return true


## Installs display-only state already validated by the owner.
## No points, reachability, eligibility, or effects are computed here.
func set_allocation_state(state: Dictionary) -> void:
	var next_allocated: Dictionary = _ids_to_set(state.get("allocated", []))
	var next_available: Dictionary = _ids_to_set(state.get("available", []))
	var next_remote: Dictionary = _ids_to_set(state.get("remote", []))
	var next_selected: String = ""
	var selected_value: Variant = state.get("selected_id", "")
	if typeof(selected_value) == TYPE_STRING:
		next_selected = String(selected_value)
	var next_ranges: Array[Dictionary] = []
	var ranges_value: Variant = state.get("socket_ranges", [])
	if typeof(ranges_value) == TYPE_ARRAY:
		for range_value: Variant in ranges_value:
			if typeof(range_value) != TYPE_DICTIONARY:
				continue
			var socket_range: Dictionary = range_value
			if typeof(socket_range.get("center")) != TYPE_VECTOR2:
				continue
			if typeof(socket_range.get("radius")) not in [TYPE_FLOAT, TYPE_INT]:
				continue
			if typeof(socket_range.get("active")) != TYPE_BOOL:
				continue
			var center: Vector2 = socket_range["center"]
			var radius: float = float(socket_range["radius"])
			if not is_finite(center.x) or not is_finite(center.y) or not is_finite(radius) or radius <= 0.0:
				continue
			next_ranges.append({"center": center, "radius": radius, "active": bool(socket_range["active"])})
	if _allocated == next_allocated and _available == next_available and _remote == next_remote and _selected_id == next_selected and _socket_ranges == next_ranges:
		return
	_allocated = next_allocated
	_available = next_available
	_remote = next_remote
	_selected_id = next_selected
	_socket_ranges = next_ranges
	queue_redraw()


func world_to_screen(point: Vector2) -> Vector2:
	return size * 0.5 + pan + point * zoom


func screen_to_world(point: Vector2) -> Vector2:
	return (point - size * 0.5 - pan) / zoom


func set_zoom(value: float, anchor: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if anchor.x < 0.0 or anchor.y < 0.0:
		anchor = size * 0.5
	var world_anchor: Vector2 = screen_to_world(anchor)
	var next_zoom: float = clampf(value, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(next_zoom, zoom):
		return
	zoom = next_zoom
	pan = anchor - size * 0.5 - world_anchor * zoom
	queue_redraw()
	_update_hover_at_last_position()


func pan_by(delta: Vector2) -> void:
	if delta.is_zero_approx():
		return
	pan += delta
	queue_redraw()
	_update_hover_at_last_position()


## Fits the original coordinate bounds into the logical Control rectangle.
func fit_tree() -> void:
	if _nodes.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return
	var available: Vector2 = (size - Vector2(72.0, 72.0)).max(Vector2(80.0, 80.0))
	var next_zoom: float = minf(available.x / maxf(_tree_bounds.size.x, 1.0), available.y / maxf(_tree_bounds.size.y, 1.0))
	zoom = clampf(next_zoom, MIN_ZOOM, MAX_ZOOM)
	pan = -_tree_bounds.get_center() * zoom
	queue_redraw()
	_update_hover_at_last_position()


func node_screen_position(id: String) -> Vector2:
	if not _nodes.has(id):
		return Vector2.INF
	return world_to_screen(_nodes[id]["position"] as Vector2)


## Returns a viewport-canvas logical rect, suitable for a UI tooltip anchor.
## Control transforms are applied, but no physical-pixel scale is introduced.
func node_anchor_canvas(id: String) -> Rect2:
	if not _nodes.has(id):
		return Rect2()
	var center: Vector2 = node_screen_position(id)
	var radius: float = _node_radius(String(_nodes[id]["type"]))
	var local_rect: Rect2 = Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	var canvas_transform: Transform2D = get_global_transform_with_canvas()
	var p0: Vector2 = canvas_transform * local_rect.position
	var p1: Vector2 = canvas_transform * local_rect.end
	return Rect2(p0, p1 - p0).abs()


func _ids_to_set(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) != TYPE_ARRAY:
		return result
	for id_value: Variant in value:
		if typeof(id_value) == TYPE_STRING:
			result[String(id_value)] = true
	return result


func _build_world_grid() -> void:
	_world_grid.clear()
	for id: String in _node_order:
		var position: Vector2 = _nodes[id]["position"]
		var cell: Vector2i = _grid_cell(position)
		if not _world_grid.has(cell):
			_world_grid[cell] = []
		var bucket: Array = _world_grid[cell]
		bucket.append(id)


func _grid_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / WORLD_GRID_CELL), floori(point.y / WORLD_GRID_CELL))


func _visible_cell_range() -> Vector4i:
	var first: Vector2 = screen_to_world(Vector2.ZERO)
	var last: Vector2 = screen_to_world(size)
	var half_cell: float = 20.0 / zoom
	var low: Vector2 = Vector2(minf(first.x, last.x), minf(first.y, last.y)) - Vector2.ONE * half_cell
	var high: Vector2 = Vector2(maxf(first.x, last.x), maxf(first.y, last.y)) + Vector2.ONE * half_cell
	return Vector4i(
		floori(low.x / WORLD_GRID_CELL),
		floori(low.y / WORLD_GRID_CELL),
		floori(high.x / WORLD_GRID_CELL),
		floori(high.y / WORLD_GRID_CELL)
	)


func _node_radius(node_type: String) -> float:
	var scale_value: float = clampf(zoom, 0.08, 1.2)
	var overview:float=clampf(zoom/0.08,0.22,1.0)
	match node_type:
		"notable": return maxf(5.4, 10.0 * scale_value)*overview
		"keystone": return maxf(7.0, 14.0 * scale_value)*overview
		"mastery": return maxf(5.0, 9.0 * scale_value)*overview
		"socket": return maxf(5.1, 9.5 * scale_value)*overview
		"start": return maxf(7.0, 13.0 * scale_value)*overview
		_: return maxf(3.0, 5.2 * scale_value)*overview


func _node_fill(id: String) -> Color:
	if _nodes[id].get("status","")=="locked":return Color("c5bea9")
	if _allocated.has(id):
		return Color("c49b50")
	if _remote.has(id):
		return Color("b87764")
	if _available.has(id):
		return Color("b8c08d")
	return Color("ead9b5")


func _hit_node(point: Vector2) -> String:
	if _nodes.is_empty() or zoom <= 0.0:
		return ""
	var world: Vector2 = screen_to_world(point)
	var search_radius: float = (24.0 / zoom)
	var center_cell: Vector2i = _grid_cell(world)
	var cell_radius: int = ceili(search_radius / WORLD_GRID_CELL)
	var closest: String = ""
	var closest_distance: float = INF
	for y: int in range(center_cell.y - cell_radius, center_cell.y + cell_radius + 1):
		for x: int in range(center_cell.x - cell_radius, center_cell.x + cell_radius + 1):
			var cell: Vector2i = Vector2i(x, y)
			if not _world_grid.has(cell):
				continue
			for id_value: Variant in _world_grid[cell]:
				var id: String = String(id_value)
				var distance: float = point.distance_to(node_screen_position(id))
				var radius: float = _node_radius(String(_nodes[id]["type"])) + CLICK_PADDING
				if distance <= radius and distance < closest_distance:
					closest = id
					closest_distance = distance
	return closest


func _update_hover(point: Vector2) -> void:
	var next_id: String = _hit_node(point)
	var next_anchor: Rect2 = node_anchor_canvas(next_id) if not next_id.is_empty() else Rect2()
	var id_changed: bool = next_id != _hovered_id
	var anchor_changed: bool = next_anchor != _hover_anchor
	if id_changed and not _hovered_id.is_empty():
		hover_left.emit()
	_hovered_id = next_id
	_hover_anchor = next_anchor
	if not next_id.is_empty() and (id_changed or anchor_changed):
		node_hovered.emit(next_id, next_anchor)
	if id_changed or anchor_changed:
		queue_redraw()


func _update_hover_at_last_position() -> void:
	if _has_mouse_position:
		_update_hover(_last_mouse_position)


func _on_mouse_exited() -> void:
	_has_mouse_position = false
	if _hovered_id.is_empty():
		return
	_hovered_id = ""
	_hover_anchor = Rect2()
	hover_left.emit()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event: InputEventMouseButton = event as InputEventMouseButton
		_last_mouse_position = button_event.position
		_has_mouse_position = true
		if button_event.button_index == MOUSE_BUTTON_WHEEL_UP or button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if button_event.pressed:
				var factor: float = 1.15 if button_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
				set_zoom(zoom * factor, button_event.position)
			accept_event()
			return
		if button_event.pressed:
			_press_active = true
			_press_button = button_event.button_index
			_press_start = button_event.position
			_press_node_id = _hit_node(button_event.position)
			_press_double_click = button_event.double_click
			_pan_candidate = button_event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE] and _press_node_id.is_empty()
			_dragging = false
			mouse_default_cursor_shape = Control.CURSOR_DRAG if _pan_candidate else (Control.CURSOR_POINTING_HAND if not _press_node_id.is_empty() else Control.CURSOR_ARROW)
		else:
			if _press_active and button_event.button_index == _press_button:
				if not _dragging and not _press_node_id.is_empty() and _hit_node(button_event.position) == _press_node_id:
					node_clicked.emit(_press_node_id, _press_button, _press_double_click)
				_press_active = false
				_press_button = MOUSE_BUTTON_NONE
				_press_node_id = ""
				_press_double_click = false
				_pan_candidate = false
				_dragging = false
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not _hit_node(button_event.position).is_empty() else Control.CURSOR_ARROW
			_update_hover(button_event.position)
		accept_event()
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var delta: Vector2 = motion.relative
		if delta.is_zero_approx():
			delta = motion.position - _last_mouse_position
		_last_mouse_position = motion.position
		_has_mouse_position = true
		if _press_active and _pan_candidate:
			if not _dragging and motion.position.distance_to(_press_start) >= DRAG_THRESHOLD:
				_dragging = true
				mouse_default_cursor_shape = Control.CURSOR_DRAG
			if _dragging:
				pan += delta
				queue_redraw()
		_update_hover(motion.position)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
		_update_hover_at_last_position()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_press_active = false
		_press_button = MOUSE_BUTTON_NONE
		_press_node_id = ""
		_pan_candidate = false
		_dragging = false
		mouse_default_cursor_shape = Control.CURSOR_ARROW


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_texture_rect(PARCHMENT_TEXTURE, Rect2(Vector2.ZERO, size), false, Color(1.0, 1.0, 1.0, 0.94))
	draw_rect(Rect2(Vector2.ZERO, size), Color(PAPER, 0.12), true)
	_draw_socket_ranges()
	_draw_edges()
	_draw_visible_nodes()
	draw_rect(Rect2(Vector2.ZERO, size).grow(-0.75), COPPER, false, 1.5, true)


func _draw_socket_ranges() -> void:
	var view_rect: Rect2 = Rect2(Vector2.ZERO, size)
	for socket_range: Dictionary in _socket_ranges:
		var center: Vector2 = world_to_screen(socket_range["center"])
		var radius: float = float(socket_range["radius"]) * zoom
		if radius <= 0.0 or not Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0).intersects(view_rect):
			continue
		var active: bool = bool(socket_range["active"])
		var line_color: Color = GOLD if active else MUTED_INK
		var fill_color: Color = Color(line_color, 0.07 if active else 0.035)
		draw_circle(center, radius, fill_color)
		if active:
			draw_arc(center, radius, 0.08, TAU - 0.08, 64, Color(line_color, 0.62), 1.25, true)
		else:
			for part: int in range(16):
				var start_angle: float = float(part) * TAU / 16.0
				draw_arc(center, radius, start_angle, start_angle + TAU / 40.0, 5, Color(line_color, 0.32), 1.0, true)


func _draw_edges() -> void:
	var clip_rect: Rect2 = Rect2(Vector2.ZERO, size).grow(1.0)
	var edge_color: Color = Color(COPPER, 0.66)
	for index: int in range(0, _edge_positions.size(), 2):
		if _edge_is_visible(index, clip_rect):
			draw_line(world_to_screen(_edge_positions[index]), world_to_screen(_edge_positions[index + 1]), edge_color, 1.15, true)


func _edge_is_visible(position_index: int, clip_rect: Rect2) -> bool:
	if position_index < 0 or position_index + 1 >= _edge_positions.size():
		return false
	return _segment_intersects_rect(
		world_to_screen(_edge_positions[position_index]),
		world_to_screen(_edge_positions[position_index + 1]),
		clip_rect
	)


func _count_visible_edges(clip_rect: Rect2) -> int:
	var count: int = 0
	for index: int in range(0, _edge_positions.size(), 2):
		if _edge_is_visible(index, clip_rect):
			count += 1
	return count


func _draw_visible_nodes() -> void:
	if _nodes.is_empty():
		return
	var cells: Vector4i = _visible_cell_range()
	var view_rect: Rect2 = Rect2(Vector2.ZERO, size)
	for y: int in range(cells.y, cells.w + 1):
		for x: int in range(cells.x, cells.z + 1):
			var cell: Vector2i = Vector2i(x, y)
			if not _world_grid.has(cell):
				continue
			for id_value: Variant in _world_grid[cell]:
				var id: String = String(id_value)
				var node: Dictionary = _nodes[id]
				var center: Vector2 = world_to_screen(node["position"])
				var radius: float = _node_radius(String(node["type"]))
				if not view_rect.grow(radius + 2.0).has_point(center):
					continue
				_draw_node(id, String(node["type"]), center, radius)


func _draw_node(id: String, node_type: String, center: Vector2, radius: float) -> void:
	var fill: Color = _node_fill(id)
	var line: Color = COPPER
	if _allocated.has(id):
		line = GOLD
	elif _remote.has(id):
		line = BURGUNDY
	elif _available.has(id):
		line = OLIVE
	if id == _selected_id:
		_draw_polygon(center, radius + 4.2, 8, PI / 8.0, Color(BURGUNDY, 0.88), false, 1.5)
	if id == _focus_id:
		_draw_polygon(center, radius + 2.0, 4, PI / 4.0, Color(GOLD, 0.88), false, 1.15)
	if id == _hovered_id:
		_draw_polygon(center, radius + 6.0, 4, PI / 4.0, Color(INK, 0.68), false, 1.0)
	match node_type:
		"small":
			draw_circle(center, radius, fill)
			draw_arc(center, radius, 0.0, TAU, 20, line, 1.1, true)
			if _allocated.has(id):
				draw_circle(center, radius * 0.3, line)
		"notable":
			_draw_polygon(center, radius, 8, PI / 8.0, fill, true, 0.0)
			_draw_polygon(center, radius, 8, PI / 8.0, line, false, 1.4)
			draw_line(center + Vector2(-radius * 0.35, 0.0), center + Vector2(radius * 0.35, 0.0), line, 1.0, true)
		"keystone":
			_draw_polygon(center, radius, 8, -PI / 2.0, fill, true, 0.0)
			_draw_polygon(center, radius, 8, -PI / 2.0, BURGUNDY if not _allocated.has(id) else line, false, 1.65)
			_draw_polygon(center, radius * 0.43, 4, PI / 4.0, line, true, 0.0)
		"mastery":
			_draw_polygon(center, radius, 4, PI / 4.0, fill, true, 0.0)
			_draw_polygon(center, radius, 4, PI / 4.0, line, false, 1.35)
			draw_line(center + Vector2(-radius * 0.42, -radius * 0.42), center + Vector2(radius * 0.42, radius * 0.42), line, 1.0, true)
		"socket":
			_draw_polygon(center, radius, 4, 0.0, fill, true, 0.0)
			_draw_polygon(center, radius, 4, 0.0, line, false, 1.5)
			draw_circle(center, radius * 0.24, line)
		"start":
			_draw_polygon(center, radius, 8, -PI / 2.0, fill, true, 0.0, 0.48)
			_draw_polygon(center, radius, 8, -PI / 2.0, line, false, 1.65, 0.48)
			draw_circle(center, radius * 0.22, line)
	if _nodes[id].get("status","")=="locked":
		draw_line(center+Vector2(-radius,radius),center+Vector2(radius,-radius),Color("776e60"),1.2,true)


func _draw_polygon(center: Vector2, radius: float, sides: int, rotation: float, color: Color, filled: bool, width: float, inner_scale: float = 1.0) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(sides):
		var angle: float = rotation + TAU * float(index) / float(sides)
		var point_radius: float = radius * (inner_scale if inner_scale < 1.0 and index % 2 == 1 else 1.0)
		points.append(center + Vector2.from_angle(angle) * point_radius)
	if filled:
		draw_colored_polygon(points, color)
	else:
		points.append(points[0])
		draw_polyline(points, color, width, true)


## Liang-Barsky clipping test. Both endpoints may be off-canvas while the segment crosses it.
static func _segment_intersects_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	var delta: Vector2 = to - from
	var t_min: float = 0.0
	var t_max: float = 1.0
	var p_values: Array[float] = [-delta.x, delta.x, -delta.y, delta.y]
	var q_values: Array[float] = [from.x - rect.position.x, rect.end.x - from.x, from.y - rect.position.y, rect.end.y - from.y]
	for index: int in range(4):
		var p: float = p_values[index]
		var q: float = q_values[index]
		if is_zero_approx(p):
			if q < 0.0:
				return false
			continue
		var ratio: float = q / p
		if p < 0.0:
			t_min = maxf(t_min, ratio)
		else:
			t_max = minf(t_max, ratio)
		if t_min > t_max:
			return false
	return true
