extends SceneTree
## Deterministic source-tree inventory and execution-coverage export.
## Effect status is always taken from SourceTreeRuntime.node_effect; nodes with
## no direct source stats are reported separately instead of counting a vacuous
## empty grant set as full effect coverage.

const TreeData = preload("res://scripts/passives/source_tree_data.gd")
const TreeRuntime = preload("res://scripts/passives/source_tree_runtime.gd")
const OUTPUT_PATH := "res://docs/reference/source-tree-coverage.json"
const EFFECT_STATUSES := ["full", "partial", "unsupported"]
const NODE_API_STATUSES := ["full", "partial", "unsupported", "choice", "unknown"]


func _initialize() -> void:
	if not TreeData.ready():
		push_error("Locked source tree data is unavailable")
		quit(1)
		return
	var report := build_report()
	if report.is_empty() or not report.integrity.ok:
		push_error("Source tree coverage report failed its source-count checks")
		quit(1)
		return
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write source tree coverage report: %s" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(serialize_report(report))
	file.close()
	var default_route: Dictionary = report.class_reachability[0]
	print("Source tree coverage: %d records, %d positioned standard nodes, %d standard edges; default %s reachable=%d, blocked frontier=%d" % [
		int(report.inventory.node_records), int(report.inventory.standard_position_nodes),
		int(report.inventory.standard_graph_edges), str(default_route.class_name),
		int(default_route.reachable_count_including_start), int(default_route.blocked_frontier.size())
	])
	print("Effect entries: full=%d partial=%d unsupported=%d; empty direct-stat entries=%d" % [
		int(report.effect_coverage.all_source.direct_effect_entries.full),
		int(report.effect_coverage.all_source.direct_effect_entries.partial),
		int(report.effect_coverage.all_source.direct_effect_entries.unsupported),
		int(report.effect_coverage.all_source.direct_effect_entries.no_direct_stats)
	])
	quit(0)


static func serialize_report(report: Dictionary) -> String:
	return JSON.stringify(report, "\t", true, true) + "\n"


static func build_report() -> Dictionary:
	if not TreeData.ready():
		return {}
	var all_nodes := TreeData.nodes()
	var all_ids: Array = all_nodes.keys()
	all_ids.sort()
	var standard_ids: Array = TreeData.standard_ids()
	standard_ids.sort()
	var standard_set := {}
	for id: String in standard_ids:
		standard_set[id] = true
	var source_coverage := TreeData.source_coverage()
	var source_starts: Array = TreeData.class_starts()
	source_starts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("class_index", -1)) < int(b.get("class_index", -1))
	)

	var effect_coverage := {
		"all_source": _empty_coverage_bucket(),
		"standard_allocation_graph": _empty_coverage_bucket(),
	}
	var effect_by_id := {}
	var node_by_id := {}
	var node_records: Array[Dictionary] = []
	var positioned_standard_count := 0
	var positioned_source_count := 0
	var mastery_node_count := 0
	var mastery_option_count := 0
	var mastery_option_stats_count := 0
	var mastery_option_status_counts := _empty_status_counts()
	var no_stats_kind_counts := {}

	for id_value: Variant in all_ids:
		var id := str(id_value)
		var node := TreeData.node(id)
		if node.is_empty():
			return {}
		node_by_id[id] = node
		var is_standard := standard_set.has(id)
		if bool(node.has_position):
			positioned_source_count += 1
		if is_standard and bool(node.has_position):
			positioned_standard_count += 1

		var api_effect: Dictionary = TreeRuntime.node_effect(id)
		var is_mastery := str(node.type) == "mastery"
		var node_has_stats: bool = not node.stats.is_empty()
		var node_execution := _effect_record(api_effect, node_has_stats, is_mastery)
		effect_by_id[id] = node_execution
		_record_node_status(effect_coverage.all_source, str(api_effect.get("status", "unknown")), node_has_stats, is_mastery)
		if is_standard:
			_record_node_status(effect_coverage.standard_allocation_graph, str(api_effect.get("status", "unknown")), node_has_stats, is_mastery)
		if not node_has_stats:
			var no_stats_kind := str(node.type)
			no_stats_kind_counts[no_stats_kind] = int(no_stats_kind_counts.get(no_stats_kind, 0)) + 1

		var mastery_options: Array[Dictionary] = []
		if is_mastery:
			mastery_node_count += 1
			effect_coverage.all_source.mastery_nodes += 1
			if is_standard:
				effect_coverage.standard_allocation_graph.mastery_nodes += 1
			var source_options: Array = node.mastery_effects.duplicate(true)
			source_options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("effect", 0)) < int(b.get("effect", 0))
			)
			for option: Dictionary in source_options:
				var effect_id := int(option.get("effect", 0))
				var option_stats: Array = option.get("stats", [])
				var option_effect: Dictionary = TreeRuntime.node_effect(id, effect_id)
				var has_option_stats := not option_stats.is_empty()
				var option_execution := _effect_record(option_effect, has_option_stats, false)
				mastery_option_count += 1
				if has_option_stats:
					mastery_option_stats_count += 1
				var option_status := str(option_effect.get("status", "unknown"))
				mastery_option_status_counts[option_status] = int(mastery_option_status_counts.get(option_status, 0)) + 1
				_record_mastery_option(effect_coverage.all_source, option_status, has_option_stats)
				if is_standard:
					_record_mastery_option(effect_coverage.standard_allocation_graph, option_status, has_option_stats)
				var option_record := option.duplicate(true)
				option_record["effect_id"] = effect_id
				option_record["stats"] = option_stats.duplicate(true)
				option_record["execution"] = option_execution
				option_record["source"] = option.duplicate(true)
				mastery_options.append(option_record)

		var position: Variant = null
		if bool(node.has_position):
			position = {"x": float(node.position.x), "y": float(node.position.y)}
		var source_record: Dictionary = node.source.duplicate(true)
		node_records.append({
			"id": id,
			"name": str(node.name),
			"type": str(node.type),
			"default_allocation_graph": is_standard,
			"group_id": str(node.group_id),
			"has_position": bool(node.has_position),
			"position": position,
			"stats": node.stats.duplicate(true),
			"execution": node_execution,
			"mastery_options": mastery_options,
			"source": source_record,
		})

	var edges := _standard_edges(standard_ids, standard_set)
	var reachability: Array[Dictionary] = []
	for start: Dictionary in source_starts:
		var class_id := int(start.get("class_index", -1))
		var start_id := str(start.get("node_id", ""))
		var class_definition := TreeData.class_definition(class_id)
		reachability.append(_class_reachability(class_id, str(class_definition.get("name", "")), start_id,
			standard_set, node_by_id, effect_by_id))

	var inventory := {
		"node_records": all_ids.size(),
		"positioned_source_nodes": positioned_source_count,
		"standard_graph_nodes": standard_ids.size(),
		"standard_position_nodes": positioned_standard_count,
		"standard_graph_edges": edges.size(),
		"class_starts": source_starts.size(),
		"mastery_nodes": mastery_node_count,
		"mastery_options": mastery_option_count,
		"mastery_options_with_stats": mastery_option_stats_count,
		"no_direct_stats_nodes_by_type": no_stats_kind_counts,
	}
	var source_reported := {
		"source_nodes": int(source_coverage.get("source_nodes", -1)),
		"nodes_with_derived_positions": int(source_coverage.get("nodes_with_derived_positions", -1)),
		"default_allocation_nodes": int(source_coverage.get("default_allocation_nodes", -1)),
		"standard_tree_positioned_nodes": int(source_coverage.get("standard_tree_positioned_nodes", -1)),
		"default_allocation_edges": int(source_coverage.get("default_allocation_edges", -1)),
		"mastery_nodes": int(source_coverage.get("mastery_nodes", -1)),
		"mastery_effect_options": int(source_coverage.get("mastery_effect_options", -1)),
	}
	var integrity := {
		"node_records_match_source": inventory.node_records == source_reported.source_nodes,
		"positioned_source_nodes_match_source": inventory.positioned_source_nodes == source_reported.nodes_with_derived_positions,
		"standard_graph_nodes_match_source": inventory.standard_graph_nodes == source_reported.default_allocation_nodes,
		"standard_position_nodes_match_source": inventory.standard_position_nodes == source_reported.standard_tree_positioned_nodes,
		"standard_edges_match_source": inventory.standard_graph_edges == source_reported.default_allocation_edges,
		"mastery_nodes_match_source": inventory.mastery_nodes == source_reported.mastery_nodes,
		"mastery_options_match_source": inventory.mastery_options == source_reported.mastery_effect_options,
	}
	var integrity_ok := true
	for check_name: String in integrity:
		integrity_ok = integrity_ok and bool(integrity[check_name])
	integrity["ok"] = integrity_ok

	return {
		"schema_version": 1,
		"report_kind": "source-tree-execution-coverage",
		"source": {
			"data_sha256": TreeData.SOURCE_SHA256,
			"api": "SourceTreeData plus SourceTreeRuntime.node_effect",
		},
		"inventory": inventory,
		"source_reported_counts": source_reported,
		"integrity": integrity,
		"effect_coverage": {
			"status_basis": "SourceTreeRuntime.node_effect status for the complete node or mastery option; supported, unsupported and grant arrays are exported directly from that API.",
			"counting_rule": "Only source entries with non-empty direct stats count as full, partial or unsupported effect entries. Empty-stat nodes/options are recorded as no_direct_stats even when node_effect returns full with no grants.",
			"all_source": effect_coverage.all_source,
			"standard_allocation_graph": effect_coverage.standard_allocation_graph,
		},
		"reachability_policy": {
			"graph_api": "SourceTreeData.standard_ids and SourceTreeData.adjacency",
			"node_effect_api": "SourceTreeRuntime.node_effect",
			"traversable_effect_status": "full",
			"empty_stats_nodes": "The API's full empty-grant result is treated as a neutral structural step for path traversal, but is not counted as full effect coverage.",
			"excluded_nodes": ["position_proxy", "blighted_only", "mastery_not_path", "other_class_start"],
			"point_budget_applied": false,
			"scope_note": "Topological reachability through currently full node_effect entries; this does not model allocated-point budgets, remote jewel allocation, ascendancy, or expansion subtrees.",
		},
		"standard_graph": {"node_ids": standard_ids, "edges": edges},
		"class_reachability": reachability,
		"nodes": node_records,
		"limitations": [
			"A full status means every direct source stat line on that node or selected mastery option is reported supported by the current node_effect API; it is not a claim that the complete PoE ruleset or every possible conditional mechanic is implemented.",
			"Source records and positions are inventory facts. Imported data completeness does not imply execution completeness; inspect full, partial, unsupported, and no_direct_stats counts separately.",
			"Starts have no node-local stats: the class start is the route origin while class base attributes are supplied through the runtime class definition. Jewel sockets have no direct node stats; socket occupancy and jewel grants are handled by the separate jewel path.",
		],
	}


static func _empty_coverage_bucket() -> Dictionary:
	return {
		"node_records": 0,
		"node_api_status_counts": _empty_node_status_counts(),
		"node_direct_effect_status_counts": _empty_status_counts(),
		"nodes_with_direct_stats": 0,
		"nodes_without_direct_stats": 0,
		"mastery_nodes": 0,
		"mastery_options": 0,
		"mastery_option_status_counts": _empty_status_counts(),
		"mastery_options_with_direct_stats": 0,
		"mastery_options_without_direct_stats": 0,
		"direct_effect_entries": {
			"total_with_stats": 0,
			"full": 0,
			"partial": 0,
			"unsupported": 0,
			"no_direct_stats": 0,
			"other_status": 0,
		},
	}


static func _empty_status_counts() -> Dictionary:
	return {"full": 0, "partial": 0, "unsupported": 0, "other": 0}


static func _empty_node_status_counts() -> Dictionary:
	return {"full": 0, "partial": 0, "unsupported": 0, "choice": 0, "unknown": 0}


static func _effect_record(effect: Dictionary, has_direct_stats: bool, is_mastery_node: bool) -> Dictionary:
	var api_status := str(effect.get("status", "unknown"))
	var coverage_status := api_status
	if is_mastery_node:
		coverage_status = "choice_requires_option"
	elif not has_direct_stats:
		coverage_status = "no_direct_stats"
	return {
		"api_status": api_status,
		"coverage_status": coverage_status,
		"has_direct_stats": has_direct_stats,
		"supported": effect.get("supported", []).duplicate(true),
		"unsupported": effect.get("unsupported", []).duplicate(true),
		"grants": effect.get("grants", []).duplicate(true),
	}


static func _record_node_status(bucket: Dictionary, api_status: String, has_direct_stats: bool, is_mastery_node: bool) -> void:
	bucket.node_records += 1
	var node_key := api_status if bucket.node_api_status_counts.has(api_status) else "unknown"
	bucket.node_api_status_counts[node_key] = int(bucket.node_api_status_counts[node_key]) + 1
	if is_mastery_node:
		return
	if has_direct_stats:
		bucket.nodes_with_direct_stats += 1
		_record_direct_effect(bucket, api_status)
	else:
		bucket.nodes_without_direct_stats += 1
		bucket.direct_effect_entries.no_direct_stats += 1


static func _record_mastery_option(bucket: Dictionary, api_status: String, has_direct_stats: bool) -> void:
	bucket.mastery_options += 1
	var option_key := api_status if bucket.mastery_option_status_counts.has(api_status) else "other"
	bucket.mastery_option_status_counts[option_key] = int(bucket.mastery_option_status_counts[option_key]) + 1
	if has_direct_stats:
		bucket.mastery_options_with_direct_stats += 1
		_record_direct_effect(bucket, api_status)
	else:
		bucket.mastery_options_without_direct_stats += 1
		bucket.direct_effect_entries.no_direct_stats += 1


static func _record_direct_effect(bucket: Dictionary, api_status: String) -> void:
	bucket.direct_effect_entries.total_with_stats += 1
	var status_counts: Dictionary = bucket.node_direct_effect_status_counts
	if EFFECT_STATUSES.has(api_status):
		status_counts[api_status] = int(status_counts.get(api_status, 0)) + 1
		bucket.direct_effect_entries[api_status] = int(bucket.direct_effect_entries[api_status]) + 1
	else:
		status_counts.other = int(status_counts.other) + 1
		bucket.direct_effect_entries.other_status = int(bucket.direct_effect_entries.other_status) + 1


static func _standard_edges(standard_ids: Array, standard_set: Dictionary) -> Array[Dictionary]:
	var by_pair := {}
	for id: String in standard_ids:
		var neighbors: Array = TreeData.adjacency(id)
		neighbors.sort()
		for neighbor_value: Variant in neighbors:
			var neighbor := str(neighbor_value)
			if not standard_set.has(neighbor) or id >= neighbor:
				continue
			by_pair[id + "\t" + neighbor] = {"a": id, "b": neighbor}
	var edge_keys: Array = by_pair.keys()
	edge_keys.sort()
	var result: Array[Dictionary] = []
	for key: String in edge_keys:
		result.append(by_pair[key])
	return result


static func _class_reachability(class_id: int, character_name: String, start_id: String,
		standard_set: Dictionary, node_by_id: Dictionary, effect_by_id: Dictionary) -> Dictionary:
	var reached := {start_id: true}
	var parent := {}
	var queue: Array[String] = [start_id]
	var queue_index := 0
	var frontier_by_id := {}
	var excluded_by_id := {}
	var reachable_direct_effect_nodes := 0
	var reachable_no_direct_stats_nodes := 0
	while queue_index < queue.size():
		var current := queue[queue_index]
		queue_index += 1
		var neighbors: Array = TreeData.adjacency(current)
		neighbors.sort()
		for neighbor_value: Variant in neighbors:
			var neighbor := str(neighbor_value)
			if not standard_set.has(neighbor) or reached.has(neighbor):
				continue
			var node: Dictionary = node_by_id.get(neighbor, {})
			var exclusion := _path_exclusion(neighbor, node, start_id)
			if not exclusion.is_empty():
				if not excluded_by_id.has(neighbor):
					excluded_by_id[neighbor] = {"node_id": neighbor, "reason": exclusion, "via_reachable_node_id": current}
				continue
			var execution: Dictionary = effect_by_id.get(neighbor, {})
			var status := str(execution.get("api_status", "unknown"))
			if status != "full":
				if not frontier_by_id.has(neighbor):
					var prefix := _path_to(parent, start_id, current)
					prefix.append(neighbor)
					frontier_by_id[neighbor] = {
						"node_id": neighbor,
						"name": str(node.get("name", "")),
						"status": status,
						"supported": execution.get("supported", []).duplicate(true),
						"unsupported": execution.get("unsupported", []).duplicate(true),
						"via_reachable_node_id": current,
						"shortest_executable_prefix": prefix,
					}
				continue
			reached[neighbor] = true
			parent[neighbor] = current
			queue.append(neighbor)
			if node.get("stats", []).is_empty():
				reachable_no_direct_stats_nodes += 1
			else:
				reachable_direct_effect_nodes += 1

	var reachable_ids: Array = reached.keys()
	reachable_ids.sort()
	var frontier_ids: Array = frontier_by_id.keys()
	frontier_ids.sort()
	var frontier: Array[Dictionary] = []
	var frontier_status_counts := _empty_status_counts()
	for id: String in frontier_ids:
		var item: Dictionary = frontier_by_id[id]
		var status := str(item.status)
		var status_key := status if frontier_status_counts.has(status) else "other"
		frontier_status_counts[status_key] = int(frontier_status_counts[status_key]) + 1
		frontier.append(item)
	var excluded_ids: Array = excluded_by_id.keys()
	excluded_ids.sort()
	var excluded: Array[Dictionary] = []
	var excluded_counts := {"position_proxy": 0, "blighted_only": 0, "mastery_not_path": 0, "other_class_start": 0}
	for id: String in excluded_ids:
		var item: Dictionary = excluded_by_id[id]
		excluded.append(item)
		var reason := str(item.reason)
		if excluded_counts.has(reason):
			excluded_counts[reason] = int(excluded_counts[reason]) + 1
	return {
		"class_id": class_id,
		"class_name": character_name,
		"start_node_id": start_id,
		"reachable_node_ids_including_start": reachable_ids,
		"reachable_count_including_start": reachable_ids.size(),
		"reachable_count_excluding_start": maxi(0, reachable_ids.size() - 1),
		"reachable_full_direct_effect_nodes": reachable_direct_effect_nodes,
		"reachable_no_direct_stats_neutral_nodes": reachable_no_direct_stats_nodes,
		"blocked_frontier": frontier,
		"blocked_frontier_count": frontier.size(),
		"blocked_frontier_status_counts": frontier_status_counts,
		"excluded_adjacent_nodes": excluded,
		"excluded_adjacent_counts": excluded_counts,
	}


static func _path_exclusion(node_id: String, node: Dictionary, own_start_id: String) -> String:
	if node.is_empty():
		return ""
	var source: Dictionary = node.get("source", {})
	if bool(source.get("isProxy", false)):
		return "position_proxy"
	if bool(source.get("isBlighted", false)):
		return "blighted_only"
	if str(node.get("type", "")) == "mastery":
		return "mastery_not_path"
	if str(node.get("type", "")) == "start" and node_id != own_start_id:
		return "other_class_start"
	return ""


static func _path_to(parent: Dictionary, start_id: String, target_id: String) -> Array[String]:
	var result: Array[String] = [target_id]
	var cursor := target_id
	while cursor != start_id:
		if not parent.has(cursor):
			return []
		cursor = str(parent[cursor])
		result.push_front(cursor)
	return result
