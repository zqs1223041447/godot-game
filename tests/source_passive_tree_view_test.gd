extends SceneTree

const View = preload("res://scripts/ui/source_passive_tree_view.gd")
const FIXTURE_PATH: String = "res://data/passive_source/normalized_tree.json"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func run() -> void:
	var fixture_text: String = FileAccess.get_file_as_string(FIXTURE_PATH)
	var source_value: Variant = JSON.parse_string(fixture_text)
	expect(typeof(source_value) == TYPE_DICTIONARY, "normalized tree fixture parses")
	if typeof(source_value) != TYPE_DICTIONARY:
		quit(1)
		return
	var source: Dictionary = source_value
	var fixture: Dictionary = _build_default_graph_fixture(source)
	var nodes: Dictionary = fixture["nodes"]
	var edges: Array = fixture["edges"]
	var graph: Dictionary = fixture["graph"]
	expect(nodes.size() == 2387, "default allocation fixture has 2,387 positioned nodes")
	expect(edges.size() == 2697, "default allocation fixture has 2,697 standard edges")
	var nodes_before: Dictionary = nodes.duplicate(true)
	var edges_before: Array = edges.duplicate(true)

	var view: Control = View.new()
	view.name = "SourcePassiveTreeViewTest"
	view.size = Vector2(1280.0, 720.0)
	root.add_child(view)
	await process_frame
	var focus_id: String = String(graph["class_start_ids"][0])
	expect(view.set_tree(nodes, edges, focus_id), "real normalized graph accepted")
	await process_frame
	await process_frame
	expect(view._nodes.size() == 2387, "all source graph nodes retained")
	expect(view._edges.size() == 2697, "all legal source graph edges retained")
	expect(view._edge_positions.size() == 5394, "each edge retains both original endpoints")
	for index: int in range(edges.size()):
		var expected_edge: Dictionary = edges[index]
		var actual_edge: Dictionary = view._edges[index]
		expect(actual_edge["a"] == expected_edge["a"] and actual_edge["b"] == expected_edge["b"], "edge order and endpoints retained %d" % index)
		var expected_a: Vector2 = nodes[expected_edge["a"]]["position"]
		var expected_b: Vector2 = nodes[expected_edge["b"]]["position"]
		expect(view._edge_positions[index * 2] == expected_a and view._edge_positions[index * 2 + 1] == expected_b, "edge coordinates retained %d" % index)
	expect(nodes == nodes_before and edges == edges_before, "set_tree leaves graph inputs unchanged")
	expect(not view.is_processing() and not view.is_physics_processing(), "view does not run an idle redraw loop")

	var first_id: String = String(graph["node_ids"][0])
	var second_id: String = String(graph["node_ids"][1])
	var third_id: String = String(graph["node_ids"][2])
	var state: Dictionary = {
		"allocated": [first_id],
		"available": [second_id],
		"remote": [third_id],
		"socket_ranges": [{"center": nodes[first_id]["position"], "radius": 280.0, "active": true}],
		"selected_id": second_id,
	}
	var state_before: Dictionary = state.duplicate(true)
	view.set_allocation_state(state)
	expect(state == state_before, "allocation state input remains unchanged")
	expect(view._allocated.has(first_id) and view._available.has(second_id) and view._remote.has(third_id), "display state lists map directly to visual flags")
	expect(view._selected_id == second_id and view._socket_ranges.size() == 1, "selection and socket range are retained")

	var invalid_nodes: Dictionary = {"kept": _node("kept", Vector2.ZERO)}
	var invalid_edges: Array = [{"a": "kept", "b": "unknown-endpoint"}]
	var internal_before: Dictionary = view._nodes.duplicate(true)
	expect(not view.set_tree(invalid_nodes, invalid_edges, "kept"), "unknown edge endpoint rejects the replacement")
	expect(view._nodes == internal_before and view._edges.size() == 2697, "invalid graph rejection is atomic")
	expect(invalid_nodes == {"kept": _node("kept", Vector2.ZERO)} and invalid_edges[0]["b"] == "unknown-endpoint", "invalid graph inputs remain unchanged")

	var cross_view_nodes: Dictionary = {
		"left": _node("left", Vector2(-2000.0, 0.0)),
		"right": _node("right", Vector2(2000.0, 0.0)),
	}
	var cross_view_edges: Array = [{"a": "left", "b": "right"}]
	expect(view.set_tree(cross_view_nodes, cross_view_edges, "left"), "cross-viewport edge fixture accepted")
	view.zoom = 0.5
	view.pan = Vector2.ZERO
	var left_screen: Vector2 = view.node_screen_position("left")
	var right_screen: Vector2 = view.node_screen_position("right")
	expect(not Rect2(Vector2.ZERO, view.size).has_point(left_screen) and not Rect2(Vector2.ZERO, view.size).has_point(right_screen), "crossing edge endpoints both lie outside the viewport")
	expect(view._count_visible_edges(Rect2(Vector2.ZERO, view.size).grow(1.0)) == 1, "offscreen endpoints do not hide an edge crossing the viewport")
	expect(View._segment_intersects_rect(Vector2(-100.0, 360.0), Vector2(1380.0, 360.0), Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))), "segment clipping accepts a horizontal viewport crossing")
	expect(not View._segment_intersects_rect(Vector2(-100.0, -100.0), Vector2(-20.0, -20.0), Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))), "segment clipping rejects a wholly offscreen edge")

	var small_nodes: Dictionary = {
		"alpha": _node("alpha", Vector2(0.0, 0.0)),
		"beta": _node("beta", Vector2(90.0, 0.0), "notable"),
		"gamma": _node("gamma", Vector2(180.0, 40.0), "socket"),
	}
	var small_edges: Array = [{"a": "alpha", "b": "beta"}, {"a": "beta", "b": "gamma"}]
	expect(view.set_tree(small_nodes, small_edges, "alpha"), "small interaction fixture accepted")
	view.zoom = 0.47
	view.pan = Vector2(31.0, -9.0)
	var camera_before_refresh: Vector2 = view.pan
	var refreshed_nodes: Dictionary = small_nodes.duplicate(true)
	refreshed_nodes["beta"]["description"] = "updated description"
	expect(view.set_tree(refreshed_nodes, small_edges, "alpha"), "metadata refresh accepted")
	expect(is_equal_approx(view.zoom, 0.47) and view.pan == camera_before_refresh, "metadata refresh preserves the current camera")
	var clicked: Array[Dictionary] = []
	var hovered: Array[Dictionary] = []
	var left_count: Array[int] = [0]
	view.node_clicked.connect(func(id: String, button: int, double_click: bool) -> void:
		clicked.append({"id": id, "button": button, "double_click": double_click})
	)
	view.node_hovered.connect(func(id: String, anchor: Rect2) -> void:
		hovered.append({"id": id, "anchor": anchor})
	)
	view.hover_left.connect(func() -> void:
		left_count[0] += 1
	)

	for logical_size: Vector2 in [Vector2(1280.0, 720.0), Vector2(2560.0, 1440.0)]:
		view.size = logical_size
		view.zoom = 0.31
		view.pan = Vector2(71.0, -44.0)
		for source_position: Vector2 in [Vector2.ZERO, Vector2(90.0, 0.0), Vector2(-300.0, 812.0)]:
			var round_trip: Vector2 = view.screen_to_world(view.world_to_screen(source_position))
			expect(round_trip.distance_to(source_position) < 0.001, "pan/zoom transform round-trip at %s" % logical_size)
		var anchor_rect: Rect2 = view.node_anchor_canvas("alpha")
		expect(anchor_rect.size.x > 0.0 and anchor_rect.size.y > 0.0, "hover anchor has a logical size at %s" % logical_size)
		expect(anchor_rect.get_center().distance_to(view.world_to_screen(Vector2.ZERO)) < 0.01, "hover anchor uses canvas logical coordinates at %s" % logical_size)

	view.size = Vector2(1280.0, 720.0)
	view.zoom = 0.31
	view.pan = Vector2.ZERO
	var click_point: Vector2 = view.node_screen_position("alpha")
	var hover_event: InputEventMouseMotion = InputEventMouseMotion.new()
	hover_event.position = click_point
	view._gui_input(hover_event)
	expect(not hovered.is_empty() and hovered[-1]["id"] == "alpha", "mouse hover resolves the node under the pointer")
	expect((hovered[-1]["anchor"] as Rect2).get_center().distance_to(click_point) < 0.01, "hover signal carries the node canvas anchor")
	var press: InputEventMouseButton = _mouse_button(click_point, MOUSE_BUTTON_LEFT, true, true)
	var release: InputEventMouseButton = _mouse_button(click_point, MOUSE_BUTTON_LEFT, false)
	view._gui_input(press)
	view._gui_input(release)
	expect(not clicked.is_empty() and clicked[-1]["id"] == "alpha", "node click emits the node ID")
	expect(clicked[-1]["button"] == MOUSE_BUTTON_LEFT and clicked[-1]["double_click"], "click signal preserves button and double-click state")

	var pointer: Vector2 = Vector2(820.0, 332.0)
	var world_under_pointer: Vector2 = view.screen_to_world(pointer)
	var wheel: InputEventMouseButton = _mouse_button(pointer, MOUSE_BUTTON_WHEEL_UP, true)
	view._gui_input(wheel)
	expect(view.screen_to_world(pointer).distance_to(world_under_pointer) < 0.0001, "wheel zoom remains anchored under the pointer")
	var second_world: Vector2 = Vector2(222.0, -51.0)
	expect(view.screen_to_world(view.world_to_screen(second_world)).distance_to(second_world) < 0.0001, "wheel zoom keeps inverse transforms consistent")

	var blank: Vector2 = Vector2(20.0, 20.0)
	var pan_before: Vector2 = view.pan
	view._gui_input(_mouse_button(blank, MOUSE_BUTTON_LEFT, true))
	var below_threshold: InputEventMouseMotion = InputEventMouseMotion.new()
	below_threshold.position = blank + Vector2(5.0, 0.0)
	below_threshold.relative = Vector2(5.0, 0.0)
	view._gui_input(below_threshold)
	view._gui_input(_mouse_button(below_threshold.position, MOUSE_BUTTON_LEFT, false))
	expect(view.pan == pan_before, "motion below the drag threshold does not pan")
	view._gui_input(_mouse_button(blank, MOUSE_BUTTON_LEFT, true))
	var dragging: InputEventMouseMotion = InputEventMouseMotion.new()
	dragging.position = blank + Vector2(22.0, 0.0)
	dragging.relative = Vector2(22.0, 0.0)
	view._gui_input(dragging)
	view._gui_input(_mouse_button(dragging.position, MOUSE_BUTTON_LEFT, false))
	expect(view.pan.distance_to(pan_before) > 20.0, "blank-area drag pans after the threshold")
	expect(left_count[0] > 0, "leaving the hovered node emits hover_left")
	expect(nodes == nodes_before and edges == edges_before and state == state_before, "all caller-owned inputs remain unchanged after use")

	print("source_passive_tree_view_test: %d checks, %d failures" % [checks, failures])
	view.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _build_default_graph_fixture(source: Dictionary) -> Dictionary:
	var standard_tree: Dictionary = source.get("standard_tree", {})
	var graph: Dictionary = standard_tree.get("default_allocation_graph", {})
	var node_records: Dictionary = source.get("node_records", {})
	var positions: Dictionary = source.get("positions", {})
	var start_ids: Dictionary = {}
	for start_id_value: Variant in graph.get("class_start_ids", []):
		start_ids[String(start_id_value)] = true
	var nodes: Dictionary = {}
	for node_id_value: Variant in graph.get("node_ids", []):
		var id: String = String(node_id_value)
		var record: Dictionary = node_records.get(id, {})
		var source_position: Dictionary = positions.get(id, {})
		var description_parts: PackedStringArray = PackedStringArray()
		for stat: Variant in record.get("stats", []):
			description_parts.append(String(stat))
		nodes[id] = {
			"id": id,
			"position": Vector2(float(source_position.get("x", 0.0)), float(source_position.get("y", 0.0))),
			"type": _source_node_type(id, record, start_ids),
			"name": String(record.get("name", id)),
			"description": " · ".join(description_parts),
			"status": "source",
		}
	var edges_by_id: Dictionary = {}
	for source_edge_value: Variant in source.get("edges", []):
		var source_edge: Dictionary = source_edge_value
		edges_by_id[String(source_edge.get("id", ""))] = source_edge
	var edges: Array = []
	for edge_id_value: Variant in graph.get("edge_ids", []):
		var source_edge: Dictionary = edges_by_id.get(String(edge_id_value), {})
		edges.append({"a": String(source_edge.get("a", "")), "b": String(source_edge.get("b", ""))})
	return {"graph": graph, "nodes": nodes, "edges": edges}


func _source_node_type(id: String, record: Dictionary, start_ids: Dictionary) -> String:
	if bool(record.get("isKeystone", false)):
		return "keystone"
	if bool(record.get("isNotable", false)):
		return "notable"
	if bool(record.get("isMastery", false)):
		return "mastery"
	if bool(record.get("isJewelSocket", false)):
		return "socket"
	if start_ids.has(id):
		return "start"
	return "small"


func _node(id: String, position: Vector2, node_type: String = "small") -> Dictionary:
	return {"id": id, "position": position, "type": node_type, "name": id, "description": "test node", "status": "idle"}


func _mouse_button(position: Vector2, button: int, pressed: bool, double_click: bool = false) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = pressed
	event.double_click = double_click
	return event
