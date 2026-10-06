extends RefCounted
## Pure final-state legality for the imported source passive tree.
## The caller owns payload authenticity, item state, point budgets, and persistence.

const NODE_TYPES: Array[String] = ["start", "small", "notable", "keystone", "socket", "mastery", "proxy"]
const CONTEXT_KEYS: Array[String] = ["nodes", "adjacency", "start_id", "budget"]
const NODE_KEYS: Array[String] = ["id", "type", "group_id", "position", "blighted", "class_id", "mastery_effects"]
const SELECTION_KEYS: Array[String] = ["allocated", "masteries"]
const SOCKET_KEYS: Array[String] = ["rule_id", "radius"]


static func analyze(context: Variant, selection: Variant, socketed: Variant) -> Dictionary:
	var context_reason: String = _context_error(context)
	if not context_reason.is_empty():
		return _failure(context_reason)
	return _analyze_validated_context(context,selection,socketed)


## Internal hot path only for the owner's pinned, private context prepared once.
## Public analyze() continues validating arbitrary caller contexts in full.
static func _analyze_validated_context(context: Dictionary,selection: Variant,socketed: Variant)->Dictionary:
	var selection_reason: String = _selection_shape_error(selection)
	if not selection_reason.is_empty():
		return _failure(selection_reason)
	var socket_reason: String = _socketed_shape_error(socketed)
	if not socket_reason.is_empty():
		return _failure(socket_reason)

	var nodes: Dictionary = context["nodes"]
	var adjacency: Dictionary = context["adjacency"]
	var start_id: String = context["start_id"]
	var budget: int = context["budget"]
	var allocated: Dictionary = {}
	for value: Variant in selection["allocated"]:
		if not value is String or value.is_empty() or not nodes.has(value) or allocated.has(value):
			return _failure("分配节点未知或重复")
		allocated[value] = true
	if not allocated.has(start_id):
		return _failure("必须保留自己的职业起点")

	var spent: int = allocated.size() - 1
	if spent > budget:
		return _failure("分配点数超过调用方预算")

	for raw_id: Variant in allocated.keys():
		var id: String = raw_id
		var node: Dictionary = nodes[id]
		if node["blighted"]:
			return _failure("涂油专属节点不可直接分配")
		if node["class_id"] >= 0 and id != start_id:
			return _failure("只能分配自己的职业起点")
		if node["type"] == "proxy":
			return _failure("位置代理节点不可分配")

	var normal_connected_map: Dictionary = {start_id: true}
	var queue: Array[String] = [start_id]
	var cursor: int = 0
	while cursor < queue.size():
		var current_id: String = queue[cursor]
		cursor += 1
		for neighbor_value: Variant in adjacency[current_id]:
			var neighbor: String = neighbor_value
			if not allocated.has(neighbor) or normal_connected_map.has(neighbor):
				continue
			var neighbor_type: String = nodes[neighbor]["type"]
			# Masteries do not connect paths. Position proxies are not allocatable.
			if neighbor_type == "mastery" or neighbor_type == "proxy":
				continue
			normal_connected_map[neighbor] = true
			queue.append(neighbor)

	for raw_id: Variant in allocated.keys():
		var id: String = raw_id
		var node: Dictionary = nodes[id]
		if node["type"] == "mastery" or normal_connected_map.has(id):
			continue
		if node["type"] != "small" and node["type"] != "notable":
			return _failure("断连分配仅支持小型或显著天赋")

	var mastery_choices: Dictionary = selection["masteries"]
	for raw_id: Variant in mastery_choices.keys():
		if not raw_id is String or not allocated.has(raw_id) or nodes[raw_id]["type"] != "mastery":
			return _failure("精通选择必须对应已分配的精通节点")
	var seen_effects: Dictionary = {}
	for raw_id: Variant in allocated.keys():
		var id: String = raw_id
		var node: Dictionary = nodes[id]
		if node["type"] != "mastery":
			continue
		if not mastery_choices.has(id):
			return _failure("每个已分配精通都必须选择一个效果")
		var effect_id: Variant = mastery_choices[id]
		if typeof(effect_id) != TYPE_INT or not node["mastery_effects"].has(effect_id):
			return _failure("精通效果不在该节点的源效果列表中")
		if seen_effects.has(effect_id):
			return _failure("同一精通效果不能重复选择")
		seen_effects[effect_id] = true
		var has_connected_notable: bool = false
		for connected_value: Variant in normal_connected_map.keys():
			var connected_id: String = connected_value
			var connected_node: Dictionary = nodes[connected_id]
			if connected_node["type"] == "notable" and connected_node["group_id"] == node["group_id"]:
				has_connected_notable = true
				break
		if not has_connected_notable:
			return _failure("精通需要同组普通连通的显著天赋")

	var active_sockets: Array[String] = []
	var special_sockets: Array[Dictionary] = []
	for socket_id: String in _sorted_keys(socketed):
		if not allocated.has(socket_id) or nodes[socket_id]["type"] != "socket":
			return _failure("珠宝孔必须已分配")
		if not normal_connected_map.has(socket_id):
			return _failure("珠宝孔必须沿普通连线连通起点")
		active_sockets.append(socket_id)
		var jewel_rule: Dictionary = socketed[socket_id]
		if jewel_rule["rule_id"] == "disconnected_radius":
			special_sockets.append({"id": socket_id, "position": nodes[socket_id]["position"], "radius": jewel_rule["radius"]})

	var remote_sources: Dictionary = {}
	# Without a radius-granting jewel this projection is necessarily empty.
	# Keep all input/connectivity checks above and disconnected rejection below.
	if not special_sockets.is_empty():
		for id: String in _sorted_keys(nodes):
			if normal_connected_map.has(id):
				continue
			var node: Dictionary = nodes[id]
			if node["type"] != "small" and node["type"] != "notable":
				continue
			var sources: Array[String] = []
			for source: Dictionary in special_sockets:
				var radius: float = source["radius"]
				var center: Vector2 = source["position"]
				if node["position"].distance_squared_to(center) <= radius * radius:
					sources.append(source["id"])
			if not sources.is_empty():
				remote_sources[id] = sources

	for raw_id: Variant in allocated.keys():
		var id: String = raw_id
		if normal_connected_map.has(id) or nodes[id]["type"] == "mastery":
			continue
		if not remote_sources.has(id):
			return _failure("断连天赋不在任何普通连通珠宝孔的有效范围内")

	var normal_connected: Array[String] = _sorted_keys(normal_connected_map)
	return {
		"legal": true,
		"reason": "",
		"normal_connected": normal_connected,
		"remote_sources": remote_sources,
		"active_sockets": active_sockets,
		"spent": spent,
		"remaining": budget - spent,
	}


static func _context_error(value: Variant) -> String:
	if not value is Dictionary or not _has_exact_keys(value, CONTEXT_KEYS):
		return "context 字段无效"
	if not value["nodes"] is Dictionary or not value["adjacency"] is Dictionary:
		return "context 节点图无效"
	if not value["start_id"] is String or value["start_id"].is_empty():
		return "职业起点 ID 无效"
	if typeof(value["budget"]) != TYPE_INT or value["budget"] < 0 or value["budget"] > 123:
		return "调用方预算必须是 0 到 123 的整数"

	var nodes: Dictionary = value["nodes"]
	var adjacency: Dictionary = value["adjacency"]
	if nodes.is_empty() or adjacency.size() != nodes.size():
		return "context 节点图无效"
	var class_ids: Dictionary = {}
	for raw_id: Variant in nodes.keys():
		if not raw_id is String or raw_id.is_empty() or not _has_exact_keys(nodes[raw_id], NODE_KEYS):
			return "节点记录字段无效"
		var id: String = raw_id
		var node: Dictionary = nodes[id]
		if node["id"] != id or not node["id"] is String:
			return "节点身份与索引不匹配"
		if not node["type"] is String or not NODE_TYPES.has(node["type"]):
			return "存在未知节点类型"
		if not node["group_id"] is String or node["group_id"].is_empty():
			return "节点 group_id 无效"
		if not node["position"] is Vector2 or not node["position"].is_finite():
			return "节点位置无效"
		if typeof(node["blighted"]) != TYPE_BOOL:
			return "节点 blighted 标记无效"
		if typeof(node["class_id"]) != TYPE_INT or node["class_id"] < -1:
			return "节点 class_id 无效"
		if not node["mastery_effects"] is Array:
			return "节点 mastery_effects 无效"
		var effects_seen: Dictionary = {}
		for effect_id: Variant in node["mastery_effects"]:
			if typeof(effect_id) != TYPE_INT or effect_id < 0 or effects_seen.has(effect_id):
				return "节点 mastery_effects 无效"
			effects_seen[effect_id] = true
		if node["type"] == "mastery":
			if node["mastery_effects"].is_empty() or node["class_id"] != -1:
				return "精通节点源效果无效"
		elif not node["mastery_effects"].is_empty():
			return "非精通节点不能声明 mastery effects"
		if node["type"] == "start":
			if node["class_id"] < 0 or class_ids.has(node["class_id"]):
				return "职业起点 class_id 无效或重复"
			class_ids[node["class_id"]] = true
		elif node["class_id"] != -1:
			return "非职业起点的 class_id 必须为 -1"

	for raw_id: Variant in adjacency.keys():
		if not raw_id is String or not nodes.has(raw_id) or not adjacency[raw_id] is Array:
			return "context 邻接表无效"
		var id: String = raw_id
		var seen_neighbors: Dictionary = {}
		for raw_neighbor: Variant in adjacency[id]:
			if not raw_neighbor is String or raw_neighbor == id or not nodes.has(raw_neighbor) or seen_neighbors.has(raw_neighbor):
				return "context 邻接表含无效边"
			seen_neighbors[raw_neighbor] = true
	for raw_id: Variant in adjacency.keys():
		var id: String = raw_id
		for neighbor: String in adjacency[id]:
			if not adjacency[neighbor].has(id):
				return "context 邻接边必须双向"

	var start_id: String = value["start_id"]
	if not nodes.has(start_id) or nodes[start_id]["type"] != "start" or nodes[start_id]["blighted"]:
		return "自己的职业起点缺失或无效"
	return ""


static func _selection_shape_error(value: Variant) -> String:
	if not value is Dictionary or not _has_exact_keys(value, SELECTION_KEYS):
		return "selection 字段无效"
	if not value["allocated"] is Array or not value["masteries"] is Dictionary:
		return "selection 分配或精通表无效"
	return ""


static func _socketed_shape_error(value: Variant) -> String:
	if not value is Dictionary:
		return "socketed 必须是字典"
	for socket_id: Variant in value.keys():
		if not socket_id is String or socket_id.is_empty() or not _has_exact_keys(value[socket_id], SOCKET_KEYS):
			return "镶嵌珠宝记录字段无效"
		var jewel_rule: Dictionary = value[socket_id]
		if not jewel_rule["rule_id"] is String or typeof(jewel_rule["radius"]) != TYPE_FLOAT:
			return "镶嵌珠宝规则类型无效"
		var radius: float = jewel_rule["radius"]
		if not is_finite(radius) or radius < 0.0:
			return "珠宝半径必须是有限非负数"
		if jewel_rule["rule_id"] == "":
			if radius != 0.0:
				return "普通珠宝规则必须为空且半径为零"
		elif jewel_rule["rule_id"] != "disconnected_radius":
			return "不支持该珠宝分配规则"
	return ""


static func _has_exact_keys(value: Variant, expected: Array[String]) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true


static func _sorted_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in value.keys():
		if key is String:
			result.append(key)
	result.sort()
	return result


static func _failure(reason: String) -> Dictionary:
	# Rejections never expose partially authorized graph data.
	return {
		"legal": false,
		"reason": reason,
		"normal_connected": [],
		"remote_sources": {},
		"active_sockets": [],
		"spent": 0,
		"remaining": 0,
	}
