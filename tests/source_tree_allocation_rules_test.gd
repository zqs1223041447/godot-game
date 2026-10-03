extends SceneTree
## Source-tree allocation legality only: no payload, item, save, or UI consumers.

const Rules = preload("res://scripts/passives/source_tree_allocation_rules.gd")
const SOURCE_PATH: String = "res://data/passive_source/normalized_tree.json"
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_small_graph()
	_test_real_standard_graph()
	print("Source tree allocation rules: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_small_graph() -> void:
	var context: Dictionary = _mini_context()
	var base_selection: Dictionary = {"allocated": ["s", "a", "n", "socket"], "masteries": {}}
	var ordinary_socket: Dictionary = {"socket": {"rule_id": "", "radius": 0.0}}
	var valid: Dictionary = Rules.analyze(context, base_selection, ordinary_socket)
	_expect(valid.legal, "Connected path and ordinary allocated socket are legal")
	_expect(valid.reason.is_empty(), "Success has an empty reason")
	_expect(valid.normal_connected == ["a", "n", "s", "socket"], "Normal connectivity is stable and excludes mastery/remote nodes")
	_expect(valid.active_sockets == ["socket"], "Active sockets include ordinary jewels on normal-connected holes")
	_expect(valid.remote_sources.is_empty(), "Ordinary jewels grant no remote coverage")
	_expect(valid.spent == 3 and valid.remaining == 5, "Start is free and each other allocation costs one point")
	_expect(_result_shape(valid, true), "Success has the exact result envelope")

	var remote_selection: Dictionary = {"allocated": ["s", "a", "n", "socket", "r"], "masteries": {}}
	var radius_socket: Dictionary = {"socket": {"rule_id": "disconnected_radius", "radius": 30.0}}
	var radius_result: Dictionary = Rules.analyze(context, remote_selection, radius_socket)
	_expect(radius_result.legal, "A remote small node exactly on the radius boundary is legal")
	_expect(radius_result.remote_sources.get("r", []) == ["socket"], "Remote source map names the granting socket")
	_expect(radius_result.remote_sources.has("remote_n"), "Coverage map includes unallocated remote candidates")
	_expect(not radius_result.remote_sources.has("r2"), "Coverage stops outside the inclusive radius")
	_expect(radius_result.normal_connected == ["a", "n", "s", "socket"], "Remote allocation never becomes a physical path")
	_expect(radius_result.spent == 4 and radius_result.remaining == 4, "Remote allocations also spend one point")

	var below_boundary: Dictionary = {"socket": {"rule_id": "disconnected_radius", "radius": 29.999}}
	_expect(not Rules.analyze(context, remote_selection, below_boundary).legal, "A remote node just outside the radius is rejected")
	_expect(not Rules.analyze(context, remote_selection, ordinary_socket).legal, "An ordinary jewel cannot grant remote allocation")
	_expect(not Rules.analyze(context, {"allocated": ["s", "r", "r2"], "masteries": {}}, radius_socket).legal, "A remote node cannot extend allocation to an uncovered node")
	_expect(not Rules.analyze(context, {"allocated": ["s", "a", "n", "r"], "masteries": {}}, radius_socket).legal, "A socket must itself be allocated before it can grant coverage")
	_expect(not Rules.analyze(context, {"allocated": ["s", "socket"], "masteries": {}}, radius_socket).legal, "A disconnected socket cannot become active through remote authorization")
	_expect(not Rules.analyze(context, {"allocated": ["s", "a", "n", "socket", "remote_n", "remote_mastery"], "masteries": {"remote_mastery": 6001}}, radius_socket).legal, "A remote notable cannot unlock its same-group mastery")

	var valid_mastery: Dictionary = Rules.analyze(context,
		{"allocated": ["s", "a", "n", "m"], "masteries": {"m": 5001}}, {})
	_expect(valid_mastery.legal, "A sourced mastery effect unlocks from a same-group connected notable")
	_expect(not valid_mastery.normal_connected.has("m"), "Mastery is not included in ordinary connectivity")
	_expect(valid_mastery.spent == 3, "A selected mastery costs one point")
	_expect(not Rules.analyze(context, {"allocated": ["s", "a", "n", "m"], "masteries": {"m": 5002}}, {}).legal, "A mastery cannot select an effect absent from its source list")
	_expect(not Rules.analyze(context, {"allocated": ["s", "a", "n", "m"], "masteries": {}}, {}).legal, "Every allocated mastery requires one selected effect")
	_expect(not Rules.analyze(context, {"allocated": ["s", "a", "n", "m", "m_dup"], "masteries": {"m": 5001, "m_dup": 5001}}, {}).legal, "The same effect ID cannot be selected twice")
	var mastery_bridge_result: Dictionary = Rules.analyze(context,
		{"allocated": ["s", "a", "n", "socket", "m_bridge", "bridge_n"], "masteries": {"m_bridge": 7001}},
		{"socket": {"rule_id": "disconnected_radius", "radius": 30.0}})
	_expect(not mastery_bridge_result.legal and mastery_bridge_result.reason == "精通需要同组普通连通的显著天赋",
		"A mastery cannot act as the physical bridge to a remote same-group notable")

	_expect(Rules.analyze(context, {"allocated": ["s"], "masteries": {}}, {}).legal, "Zero budget permits only the free own start")
	var exact_budget: Dictionary = context.duplicate(true)
	exact_budget.budget = 2
	_expect(Rules.analyze(exact_budget, {"allocated": ["s", "a", "n"], "masteries": {}}, {}).legal, "Allocation at the supplied budget boundary is legal")
	exact_budget.budget = 1
	_expect(not Rules.analyze(exact_budget, {"allocated": ["s", "a", "n"], "masteries": {}}, {}).legal, "Allocation over the supplied budget is rejected")
	exact_budget.budget = 124
	_expect(not Rules.analyze(exact_budget, {"allocated": ["s"], "masteries": {}}, {}).legal, "Analyzer never raises the parent's 123-point ceiling")

	_expect(not Rules.analyze(context, {"allocated": ["a"], "masteries": {}}, {}).legal, "Own start is mandatory")
	_expect(not Rules.analyze(context, {"allocated": ["s", "other_start"], "masteries": {}}, {}).legal, "Other class starts cannot be allocated")
	_expect(not Rules.analyze(context, {"allocated": ["s", "blight"], "masteries": {}}, {}).legal, "Blighted nodes cannot be allocated")
	_expect(not Rules.analyze(context, {"allocated": ["s", "missing"], "masteries": {}}, {}).legal, "Node IDs outside context are rejected")
	_expect(not Rules.analyze(context, {"allocated": ["s", "s"], "masteries": {}}, {}).legal, "Duplicate allocated IDs are rejected")
	_expect(not Rules.analyze(context, {"allocated": ["s", "proxy"], "masteries": {}}, {}).legal, "Position proxy nodes are recognized but not allocatable")
	_expect(not Rules.analyze(context, {"allocated": ["s", "a"], "masteries": {}}, {"socket": {"rule_id": "", "radius": 0.0}}).legal, "Socket metadata cannot authorize an unallocated hole")
	_expect(not Rules.analyze(context, base_selection, {"socket": {"rule_id": "future_rule", "radius": 1.0}}).legal, "Unknown special jewel rules are rejected")
	_expect(not Rules.analyze(context, base_selection, {"socket": {"rule_id": "", "radius": 1.0}}).legal, "Ordinary jewels must use a zero radius")
	_expect(not Rules.analyze(context, base_selection, {"socket": {"rule_id": "disconnected_radius", "radius": -1.0}}).legal, "Negative special jewel radii are rejected")

	var unknown_type: Dictionary = context.duplicate(true)
	unknown_type.nodes.a.type = "ascendancy"
	_expect(not Rules.analyze(unknown_type, {"allocated": ["s"], "masteries": {}}, {}).legal, "Unknown types anywhere in context are rejected strictly")
	var asymmetric: Dictionary = context.duplicate(true)
	asymmetric.adjacency.a.erase("s")
	_expect(not Rules.analyze(asymmetric, {"allocated": ["s"], "masteries": {}}, {}).legal, "Malformed one-way context edges are rejected")

	var input_context: Dictionary = context.duplicate(true)
	var input_selection: Dictionary = remote_selection.duplicate(true)
	var input_socketed: Dictionary = radius_socket.duplicate(true)
	seed(88429)
	randi()
	var expected_rng: Array[int] = [randi(), randi(), randi()]
	seed(88429)
	randi()
	var successful_call: Dictionary = Rules.analyze(context, remote_selection, radius_socket)
	var failed_call: Dictionary = Rules.analyze(context, {"allocated": ["s", "r"], "masteries": {}}, ordinary_socket)
	_expect([randi(), randi(), randi()] == expected_rng, "Successful and rejected calls preserve the global RNG stream")
	_expect(context == input_context and remote_selection == input_selection and radius_socket == input_socketed, "Analysis leaves all caller inputs untouched")
	_expect(successful_call.legal and failed_call.legal == false, "Repeated calls remain independent")
	_expect(_result_shape(failed_call, false), "Failure has the exact result envelope")
	_expect(failed_call.reason is String and not failed_call.reason.is_empty(), "Failure carries a reason")
	_expect(failed_call.normal_connected.is_empty() and failed_call.remote_sources.is_empty() and failed_call.active_sockets.is_empty(), "Failure returns no partial authorization graph")
	_expect(failed_call.spent == 0 and failed_call.remaining == 0, "Failure returns no partial point accounting")
	var detached: Dictionary = Rules.analyze(context, remote_selection, radius_socket)
	successful_call.normal_connected.clear()
	successful_call.remote_sources.clear()
	successful_call.active_sockets.clear()
	_expect(detached.legal and detached.remote_sources.has("r"), "Returned authorization data is detached between calls")


func _test_real_standard_graph() -> void:
	var context: Dictionary = _source_context()
	_expect(context.nodes.size() == 2387, "Source context has exactly 2,387 standard allocation nodes")
	_expect(_edge_count(context.adjacency) == 2697, "Source context has exactly 2,697 standard allocation edges")
	var start_id: String = context.start_id
	var socket_case: Dictionary = _find_socket_case(context)
	_expect(not socket_case.is_empty(), "Real source graph supplies a connected socket and remote radius-boundary candidate")
	if socket_case.is_empty():
		return
	var socket_id: String = socket_case.socket_id
	var socket_path: Array[String] = socket_case.path
	var remote_id: String = socket_case.remote_id
	var remote_radius: float = socket_case.radius
	var connected_selection: Dictionary = {"allocated": socket_path.duplicate(), "masteries": {}}
	var ordinary_socketed: Dictionary = {socket_id: {"rule_id": "", "radius": 0.0}}
	var connected_result: Dictionary = Rules.analyze(context, connected_selection, ordinary_socketed)
	_expect(connected_result.legal, "Real source-tree route to a physical socket is legal")
	_expect(connected_result.normal_connected == _sorted_strings(socket_path), "Real connected path is reported without remote nodes")
	_expect(connected_result.active_sockets == [socket_id], "Real allocated socket is active only on its normal path")
	_expect(connected_result.spent == socket_path.size() - 1, "Real route spends one point per non-start allocation")

	var refund_selection: Dictionary = connected_selection.duplicate(true)
	if socket_path.size() > 2:
		refund_selection.allocated.erase(socket_path[1])
		var refund_result: Dictionary = Rules.analyze(context, refund_selection, ordinary_socketed)
		_expect(not refund_result.legal, "Removing a real path bridge rejects a disconnected occupied socket")
		_expect(_result_shape(refund_result, false) and refund_result.normal_connected.is_empty(), "Real bridge refund rejection is atomic")
	else:
		_expect(false, "Real socket path has a refundable bridge for disconnection regression")

	var no_socket_selection: Dictionary = connected_selection.duplicate(true)
	no_socket_selection.allocated.erase(socket_id)
	_expect(not Rules.analyze(context, no_socket_selection, ordinary_socketed).legal, "Real socket jewelry depends on the selected socket node")
	var remote_selection: Dictionary = {"allocated": socket_path.duplicate(), "masteries": {}}
	remote_selection.allocated.append(remote_id)
	var special_socketed: Dictionary = {socket_id: {"rule_id": "disconnected_radius", "radius": remote_radius}}
	var boundary_result: Dictionary = Rules.analyze(context, remote_selection, special_socketed)
	_expect(boundary_result.legal, "Real graph covers a remote target exactly on its authored radius boundary")
	_expect(boundary_result.remote_sources.has(remote_id) and boundary_result.remote_sources[remote_id] == [socket_id], "Real boundary authorization points to the active socket")
	_expect(not boundary_result.normal_connected.has(remote_id), "Real covered node remains outside normal connectivity")
	var smaller_socketed: Dictionary = {socket_id: {"rule_id": "disconnected_radius", "radius": remote_radius - 0.001}}
	_expect(not Rules.analyze(context, remote_selection, smaller_socketed).legal, "Real graph rejects the same remote target just beyond the boundary")
	var remote_without_socket: Dictionary = {"missing_socket": {"rule_id": "disconnected_radius", "radius": remote_radius}}
	_expect(not Rules.analyze(context, remote_selection, remote_without_socket).legal, "Real remote authorization requires a real allocated socket")

	var mastery_case: Dictionary = _find_mastery_case(context)
	_expect(not mastery_case.is_empty(), "Real source graph has a mastery and same-group connected notable")
	if not mastery_case.is_empty():
		var mastery_selection: Dictionary = {"allocated": mastery_case.path.duplicate(), "masteries": {}}
		mastery_selection.allocated.append(mastery_case.mastery_id)
		mastery_selection.masteries[mastery_case.mastery_id] = mastery_case.effect_id
		var mastery_result: Dictionary = Rules.analyze(context, mastery_selection, {})
		_expect(mastery_result.legal, "Real mastery effect is legal with its own source and normally connected group notable")
		_expect(not mastery_result.normal_connected.has(mastery_case.mastery_id), "Real mastery does not become a physical connection")
		var wrong_effect: Dictionary = mastery_selection.duplicate(true)
		wrong_effect.masteries[mastery_case.mastery_id] = -1
		_expect(not Rules.analyze(context, wrong_effect, {}).legal, "Real mastery rejects an effect absent from that source node")

	var remote_mastery_case: Dictionary = _find_remote_mastery_case(context, socket_case)
	_expect(not remote_mastery_case.is_empty(), "Real graph supplies a remote-only same-group mastery counterexample")
	if not remote_mastery_case.is_empty():
		var remote_mastery_selection: Dictionary = {"allocated": remote_mastery_case.path.duplicate(), "masteries": {}}
		remote_mastery_selection.allocated.append(remote_mastery_case.remote_notable_id)
		remote_mastery_selection.allocated.append(remote_mastery_case.mastery_id)
		remote_mastery_selection.masteries[remote_mastery_case.mastery_id] = remote_mastery_case.effect_id
		var remote_mastery_socketed: Dictionary = {remote_mastery_case.socket_id: {
			"rule_id": "disconnected_radius", "radius": remote_mastery_case.radius}}
		_expect(not Rules.analyze(context, remote_mastery_selection, remote_mastery_socketed).legal, "A real remote notable alone cannot open its same-group mastery")

	var boundary_budget: Dictionary = context.duplicate(true)
	var budget_path: Array[String] = _first_connected_nodes(context, 124)
	_expect(budget_path.size() == 124, "Real source graph supplies 123 connected spendable allocations")
	if budget_path.size() == 124:
		boundary_budget.budget = 123
		var exact: Dictionary = Rules.analyze(boundary_budget, {"allocated": budget_path.duplicate(), "masteries": {}}, {})
		_expect(exact.legal and exact.spent == 123 and exact.remaining == 0, "Real allocation exactly at 123 parent-provided points is legal")
		budget_path.append(_first_connected_node_not_in(context, budget_path))
		var over: Dictionary = Rules.analyze(boundary_budget, {"allocated": budget_path, "masteries": {}}, {})
		_expect(not over.legal and _result_shape(over, false), "Real 124th spendable allocation is rejected without a partial graph")
	var invalid_cap: Dictionary = context.duplicate(true)
	invalid_cap.budget = 124
	_expect(not Rules.analyze(invalid_cap, {"allocated": [start_id], "masteries": {}}, {}).legal, "Source-tree analyzer refuses a budget above 123")
	var other_start: String = _first_other_start(context)
	_expect(not other_start.is_empty(), "Real source graph includes other class starts")
	if not other_start.is_empty():
		_expect(not Rules.analyze(context, {"allocated": [start_id, other_start], "masteries": {}}, {}).legal, "Other real class starts cannot be allocated")
	var blighted_id: String = _first_blighted(context)
	_expect(not blighted_id.is_empty(), "Real source graph includes blighted nodes")
	if not blighted_id.is_empty():
		_expect(not Rules.analyze(context, {"allocated": [start_id, blighted_id], "masteries": {}}, {}).legal, "Real blighted nodes cannot be allocated")
	var invalid_type: Dictionary = context.duplicate(true)
	var any_node: String = invalid_type.nodes.keys()[0]
	invalid_type.nodes[any_node].type = "expansion_jewel"
	_expect(not Rules.analyze(invalid_type, {"allocated": [start_id], "masteries": {}}, {}).legal, "Unknown imported node types fail against the full real graph")


func _mini_context() -> Dictionary:
	var nodes: Dictionary = {
		"s": _node("s", "start", "g0", Vector2(0, 0), false, 0, []),
		"a": _node("a", "small", "g0", Vector2(10, 0)),
		"n": _node("n", "notable", "g_master", Vector2(20, 0)),
		"m": _node("m", "mastery", "g_master", Vector2(20, 2), false, -1, [5001]),
		"m_dup": _node("m_dup", "mastery", "g_master", Vector2(20, 4), false, -1, [5001]),
		"socket": _node("socket", "socket", "g0", Vector2(30, 0)),
		"r": _node("r", "small", "g_remote", Vector2(60, 0)),
		"r2": _node("r2", "small", "g_remote", Vector2(64, 0)),
		"remote_n": _node("remote_n", "notable", "g_remote_master", Vector2(57, 0)),
		"remote_mastery": _node("remote_mastery", "mastery", "g_remote_master", Vector2(58, 0), false, -1, [6001]),
		"m_bridge": _node("m_bridge", "mastery", "g_bridge", Vector2(1, 1), false, -1, [7001]),
		"bridge_n": _node("bridge_n", "notable", "g_bridge", Vector2(2, 1)),
		"other_start": _node("other_start", "start", "g_other", Vector2(-10, 0), false, 1, []),
		"blight": _node("blight", "notable", "g_blight", Vector2(100, 0), true),
		"proxy": _node("proxy", "proxy", "g_proxy", Vector2(200, 0)),
	}
	var edges: Array[Array] = [
		["s", "a"], ["a", "n"], ["n", "socket"], ["n", "m"], ["n", "m_dup"],
		["r", "r2"], ["r2", "remote_n"], ["remote_n", "remote_mastery"],
		["s", "m_bridge"], ["m_bridge", "bridge_n"],
	]
	var adjacency: Dictionary = {}
	for id: String in nodes:
		adjacency[id] = []
	for edge: Array in edges:
		adjacency[edge[0]].append(edge[1])
		adjacency[edge[1]].append(edge[0])
	return {"nodes": nodes, "adjacency": adjacency, "start_id": "s", "budget": 8}


func _node(id: String, type: String, group_id: String, position: Vector2,
		blighted: bool = false, class_id: int = -1, mastery_effects: Array = []) -> Dictionary:
	return {"id": id, "type": type, "group_id": group_id, "position": position,
		"blighted": blighted, "class_id": class_id, "mastery_effects": mastery_effects.duplicate()}


func _source_context() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	if not parsed is Dictionary:
		return {"nodes": {}, "adjacency": {}, "start_id": "", "budget": 123}
	var source_records: Dictionary = parsed["node_records"]
	var groups: Dictionary = parsed["groups"]
	var standard: Dictionary = parsed["standard_tree"]
	var graph: Dictionary = standard["default_allocation_graph"]
	var nodes: Dictionary = {}
	for raw_id: Variant in graph["node_ids"]:
		var id: String = raw_id
		var source_node: Dictionary = source_records[id]
		var group_id: String = str(int(source_node["group"]))
		var source_group: Dictionary = groups[group_id]
		var type: String = "small"
		var class_id: int = -1
		if source_node.has("classStartIndex"):
			type = "start"
			class_id = int(source_node["classStartIndex"])
		elif source_node.get("isMastery", false):
			type = "mastery"
		elif source_node.get("isJewelSocket", false):
			type = "socket"
		elif source_node.get("isKeystone", false):
			type = "keystone"
		elif source_node.get("isNotable", false):
			type = "notable"
		elif source_node.get("isProxy", false):
			type = "proxy"
		var effects: Array = []
		for effect: Dictionary in source_node.get("masteryEffects", []):
			effects.append(int(effect["effect"]))
		nodes[id] = _node(id, type, group_id,
			Vector2(float(source_group["x"]), float(source_group["y"])),
			bool(source_node.get("isBlighted", false)), class_id, effects)
	var adjacency: Dictionary = {}
	for id: String in graph["node_ids"]:
		adjacency[id] = graph["adjacency"][id].duplicate()
	var start_id: String = standard["class_start_nodes"][0]["node_id"]
	return {"nodes": nodes, "adjacency": adjacency, "start_id": start_id, "budget": 123}


func _find_socket_case(context: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for socket_id: String in _sorted_keys(context.nodes):
		if context.nodes[socket_id].type != "socket":
			continue
		var path: Array[String] = _find_path(context, socket_id)
		if path.size() < 3 or path.size() > 123:
			continue
		var path_ids: Dictionary = {}
		for path_id: String in path:
			path_ids[path_id] = true
		for remote_id: String in _sorted_keys(context.nodes):
			var node: Dictionary = context.nodes[remote_id]
			if node.type != "small" and node.type != "notable":
				continue
			if node.blighted or path_ids.has(remote_id) or _touches_any(context, remote_id, path_ids):
				continue
			var distance: float = node.position.distance_to(context.nodes[socket_id].position)
			if distance > 0.0 and distance < best_distance:
				best_distance = distance
				best = {"socket_id": socket_id, "path": path, "remote_id": remote_id,
					"socket": socket_id, "radius": distance}
	return best


func _find_mastery_case(context: Dictionary) -> Dictionary:
	for mastery_id: String in _sorted_keys(context.nodes):
		var mastery: Dictionary = context.nodes[mastery_id]
		if mastery.type != "mastery" or mastery.blighted:
			continue
		for notable_id: String in _sorted_keys(context.nodes):
			var notable: Dictionary = context.nodes[notable_id]
			if notable.type != "notable" or notable.blighted or notable.group_id != mastery.group_id:
				continue
			var path: Array[String] = _find_path(context, notable_id)
			if not path.is_empty() and path.size() < 123:
				return {"mastery_id": mastery_id, "notable_id": notable_id, "path": path,
					"effect_id": mastery.mastery_effects[0]}
	return {}


func _find_remote_mastery_case(context: Dictionary, socket_case: Dictionary) -> Dictionary:
	var path: Array[String] = socket_case.path
	var path_ids: Dictionary = {}
	for id: String in path:
		path_ids[id] = true
	for mastery_id: String in _sorted_keys(context.nodes):
		var mastery: Dictionary = context.nodes[mastery_id]
		if mastery.type != "mastery" or mastery.blighted:
			continue
		for notable_id: String in _sorted_keys(context.nodes):
			var notable: Dictionary = context.nodes[notable_id]
			if notable.type != "notable" or notable.blighted or notable.group_id != mastery.group_id:
				continue
			if path_ids.has(notable_id) or _touches_any(context, notable_id, path_ids):
				continue
			var distance: float = notable.position.distance_to(context.nodes[socket_case.socket].position)
			return {"mastery_id": mastery_id, "remote_notable_id": notable_id,
				"path": path.duplicate(), "socket_id": socket_case.socket,
				"radius": distance, "effect_id": mastery.mastery_effects[0]}
	return {}


func _find_path(context: Dictionary, target_id: String) -> Array[String]:
	var start_id: String = context.start_id
	var previous: Dictionary = {start_id: ""}
	var queue: Array[String] = [start_id]
	var cursor: int = 0
	while cursor < queue.size():
		var id: String = queue[cursor]
		cursor += 1
		if id == target_id:
			break
		for neighbor: String in context.adjacency[id]:
			if previous.has(neighbor):
				continue
			var node: Dictionary = context.nodes[neighbor]
			if node.type == "mastery" or node.type == "proxy" or node.blighted:
				continue
			previous[neighbor] = id
			queue.append(neighbor)
	if not previous.has(target_id):
		return []
	var result: Array[String] = []
	var current: String = target_id
	while current != "":
		result.append(current)
		current = previous[current]
	result.reverse()
	return result


func _touches_any(context: Dictionary, node_id: String, ids: Dictionary) -> bool:
	for neighbor: String in context.adjacency[node_id]:
		if ids.has(neighbor):
			return true
	return false


func _first_connected_nodes(context: Dictionary, count: int) -> Array[String]:
	var result: Array[String] = []
	var queue: Array[String] = [context.start_id]
	var visited: Dictionary = {context.start_id: true}
	var cursor: int = 0
	while cursor < queue.size() and result.size() < count:
		var id: String = queue[cursor]
		cursor += 1
		result.append(id)
		for neighbor: String in context.adjacency[id]:
			if visited.has(neighbor):
				continue
			var node: Dictionary = context.nodes[neighbor]
			if node.type == "mastery" or node.type == "proxy" or node.blighted:
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return result


func _first_connected_node_not_in(context: Dictionary, selected: Array[String]) -> String:
	var included: Dictionary = {}
	for id: String in selected:
		included[id] = true
	var more: Array[String] = _first_connected_nodes(context, selected.size() + 1)
	for id: String in more:
		if not included.has(id):
			return id
	return ""


func _first_other_start(context: Dictionary) -> String:
	for id: String in _sorted_keys(context.nodes):
		if context.nodes[id].type == "start" and id != context.start_id:
			return id
	return ""


func _first_blighted(context: Dictionary) -> String:
	for id: String in _sorted_keys(context.nodes):
		if context.nodes[id].blighted:
			return id
	return ""


func _edge_count(adjacency: Dictionary) -> int:
	var degrees: int = 0
	for id: String in adjacency:
		degrees += adjacency[id].size()
	return int(degrees / 2)


func _sorted_strings(values: Array[String]) -> Array[String]:
	var result: Array[String] = values.duplicate()
	result.sort()
	return result


func _sorted_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in value.keys():
		if key is String:
			result.append(key)
	result.sort()
	return result


func _result_shape(value: Dictionary, legal: bool) -> bool:
	var expected: Array[String] = ["legal", "reason", "normal_connected", "remote_sources", "active_sockets", "spent", "remaining"]
	if value.size() != expected.size() or not value.has_all(expected) or value.legal != legal:
		return false
	return value.reason is String and value.normal_connected is Array and value.remote_sources is Dictionary \
		and value.active_sockets is Array and typeof(value.spent) == TYPE_INT and typeof(value.remaining) == TYPE_INT


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
