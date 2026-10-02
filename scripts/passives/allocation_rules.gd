class_name AllocationRules
extends RefCounted
## Pure final-state legality: only physical origin connections activate jewels.
## Coverage never recursively powers another socket or extends a remote branch.

const Passives = preload("res://scripts/passive_data.gd")
const Jewels = preload("res://scripts/jewel_data.gd")


static func analyze(allocated: Array, sockets: Dictionary, jewels: Dictionary, graph: Dictionary = {}) -> Dictionary:
	var nodes: Dictionary = Passives.get_nodes() if graph.is_empty() else graph
	var result: Dictionary = {"legal": false, "reason": "", "connected": {}, "granted_by": {},
		"active_sources": {}, "unsupported_nodes": [], "remote_nodes": [], "eligible_nodes": {}}
	var allowed: Dictionary = {}
	for value: Variant in allocated:
		if not value is String or not nodes.has(value) or allowed.has(value):
			result.reason = "天赋节点未知或重复"
			return result
		allowed[value] = true
	if not allowed.has(Passives.START_ID):
		result.reason = "必须保留启明之核"
		return result
	# Validate occupied socket identities before computing any granted eligibility.
	var seen_jewels: Dictionary = {}
	for value: Variant in sockets:
		if not value is String or not allowed.has(value) or nodes[value].get("type", "") != "socket":
			result.reason = "珠宝必须位于已激活的珠宝孔"
			return result
		var jewel_id: Variant = sockets[value]
		if not jewel_id is String or not jewels.has(jewel_id) or seen_jewels.has(jewel_id) or not Jewels.validate_instance(jewels[jewel_id]):
			result.reason = "珠宝身份无效或镶嵌重复"
			return result
		if jewels[jewel_id]["id"] != jewel_id:
			result.reason = "珠宝身份不匹配"
			return result
		seen_jewels[jewel_id] = true
	var connected: Dictionary = result.connected
	connected[Passives.START_ID] = true
	var queue: Array[String] = [Passives.START_ID]
	var cursor: int = 0
	while cursor < queue.size():
		var id: String = queue[cursor]
		cursor += 1
		for neighbor: String in nodes[id].get("neighbors", []):
			if allowed.has(neighbor) and not connected.has(neighbor):
				connected[neighbor] = true
				queue.append(neighbor)
	for socket_id: String in sockets:
		if not connected.has(socket_id):
			continue
		var jewel_id: String = sockets[socket_id]
		var rule: Dictionary = Jewels.allocation_rule(jewels[jewel_id])
		if rule.is_empty():
			continue
		var source: Dictionary = coverage_for_socket(socket_id, jewels[jewel_id], nodes)
		result.active_sources[socket_id] = source
		for id: String in source.covered_nodes:
			if not result.granted_by.has(id):
				result.granted_by[id] = []
			result.granted_by[id].append(socket_id)
	for id: String in nodes:
		if allowed.has(id):
			if not connected.has(id):
				result.remote_nodes.append(id)
				if nodes[id].get("type", "") not in ["small", "notable"] or not result.granted_by.has(id):
					result.unsupported_nodes.append(id)
			continue
		if result.granted_by.has(id):
			result.eligible_nodes[id] = true
			continue
		for neighbor: String in nodes[id].get("neighbors", []):
			if connected.has(neighbor):
				result.eligible_nodes[id] = true
				break
	if not result.unsupported_nodes.is_empty():
		var labels: PackedStringArray = []
		for id: String in result.unsupported_nodes.slice(0, 3):
			labels.append("%s（%s）" % [nodes[id].get("name", id), id])
		result.reason = "以下天赋将失去起点连通或寻枝覆盖：" + "、".join(labels)
		if result.unsupported_nodes.size() > 3:
			result.reason += "，以及其余 %d 个节点" % (result.unsupported_nodes.size() - 3)
		return result
	result.legal = true
	return result


static func coverage_for_socket(socket_id: String, jewel: Dictionary, graph: Dictionary = {}) -> Dictionary:
	var nodes: Dictionary = Passives.get_nodes() if graph.is_empty() else graph
	var rule: Dictionary = Jewels.allocation_rule(jewel)
	if rule.is_empty() or not nodes.has(socket_id) or nodes[socket_id].get("type", "") != "socket":
		return {}
	var center: Vector2 = nodes[socket_id]["position"]
	var covered: Array[String] = []
	for id: String in nodes:
		var node: Dictionary = nodes[id]
		if node.get("type", "") not in rule.types:
			continue
		var position: Vector2 = node["position"]
		if center.distance_squared_to(position) <= float(rule.radius) * float(rule.radius):
			covered.append(id)
	return {"socket_id": socket_id, "jewel_id": jewel["id"], "base_id": jewel["base"],
		"rule_id": rule.id, "radius": rule.radius, "position": center, "covered_nodes": covered}
