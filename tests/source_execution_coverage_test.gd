extends SceneTree

const TreeData = preload("res://scripts/passives/source_tree_data.gd")
const TreeRuntime = preload("res://scripts/passives/source_tree_runtime.gd")
const Exporter = preload("res://tools/export_source_execution_coverage.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	check(TreeData.ready(), "pinned source tree is available")
	var report: Dictionary = Exporter.build_report()
	check(not report.is_empty(), "coverage report builds")
	if report.is_empty():
		_finish()
		return
	check(bool(report.integrity.ok), "computed inventory counts match SourceTreeData coverage facts")
	check(report.inventory.node_records == TreeData.nodes().size(), "all source records retained")
	check(report.inventory.positioned_source_nodes == TreeData.source_coverage().nodes_with_derived_positions, "all-source position count derives from SourceTreeData nodes")
	check(report.inventory.standard_graph_nodes == TreeData.standard_ids().size(), "all safe standard graph nodes retained")
	check(report.inventory.standard_graph_edges == TreeData.source_coverage().default_allocation_edges, "standard edge ledger matches source graph count")
	check(report.inventory.standard_position_nodes == TreeData.source_coverage().standard_tree_positioned_nodes, "position count derives from SourceTreeData nodes")
	check(report.inventory.mastery_options == TreeData.source_coverage().mastery_effect_options, "mastery option count derives from node records")
	check(Exporter.serialize_report(report) == Exporter.serialize_report(report), "serialized report is deterministic")
	_verify_records(report)
	_verify_edges(report)
	_verify_coverage_counts(report)
	_verify_reachability(report)
	_finish()


func _verify_records(report: Dictionary) -> void:
	var expected_ids: Array = TreeData.nodes().keys()
	expected_ids.sort()
	var records: Array = report.nodes
	check(records.size() == expected_ids.size(), "one exported record per source node")
	var by_id := {}
	for index in range(mini(records.size(), expected_ids.size())):
		var item: Dictionary = records[index]
		var id := str(expected_ids[index])
		check(str(item.get("id", "")) == id, "source records are deterministically ordered")
		by_id[id] = item
	for id_value: Variant in expected_ids:
		var id := str(id_value)
		if not by_id.has(id):
			check(false, "source node record exists: " + id)
			continue
		var exported: Dictionary = by_id[id]
		var source_node := TreeData.node(id)
		check(exported.source == source_node.source, "complete source record preserved: " + id)
		check(exported.stats == source_node.stats, "source stats preserved: " + id)
		var node_effect: Dictionary = TreeRuntime.node_effect(id)
		check(exported.execution.api_status == node_effect.status, "node API status is not reimplemented: " + id)
		if str(source_node.type) == "mastery":
			check(exported.execution.coverage_status == "choice_requires_option", "mastery record requires an explicit option: " + id)
			var source_options: Array = source_node.mastery_effects
			var exported_options: Array = exported.mastery_options
			check(exported_options.size() == source_options.size(), "every mastery option is exported: " + id)
			for option: Dictionary in exported_options:
				var option_effect: Dictionary = TreeRuntime.node_effect(id, int(option.effect_id))
				check(option.execution.api_status == option_effect.status, "mastery option status comes from node_effect: %s/%s" % [id, str(option.effect_id)])
				check(option.source == _find_source_option(source_options, int(option.effect_id)), "mastery option source facts preserved: %s/%s" % [id, str(option.effect_id)])
		else:
			if source_node.stats.is_empty():
				check(exported.execution.coverage_status == "no_direct_stats", "empty source stats are not counted as full coverage: " + id)
				check(exported.execution.api_status == "full", "empty effect status is retained as the API reports it: " + id)
			else:
				check(exported.execution.coverage_status == node_effect.status, "stat-bearing node coverage follows node_effect: " + id)


func _find_source_option(options: Array, effect_id: int) -> Dictionary:
	for option: Dictionary in options:
		if int(option.get("effect", -1)) == effect_id:
			return option
	return {}


func _verify_edges(report: Dictionary) -> void:
	var standard_ids: Array = TreeData.standard_ids()
	var standard_set := {}
	for id: String in standard_ids:
		standard_set[id] = true
	var expected := {}
	for id: String in standard_ids:
		for neighbor_value: Variant in TreeData.adjacency(id):
			var neighbor := str(neighbor_value)
			if standard_set.has(neighbor) and id < neighbor:
				expected[id + "\t" + neighbor] = true
	var actual := {}
	for edge: Dictionary in report.standard_graph.edges:
		var a := str(edge.get("a", ""))
		var b := str(edge.get("b", ""))
		check(a < b, "edge endpoints use canonical order")
		check(TreeData.adjacency(a).has(b) and TreeData.adjacency(b).has(a), "edge comes from SourceTreeData adjacency")
		actual[a + "\t" + b] = true
	check(actual == expected, "exported edge ledger equals public adjacency API")


func _verify_coverage_counts(report: Dictionary) -> void:
	var recomputed := {"full": 0, "partial": 0, "unsupported": 0, "no_direct_stats": 0}
	var standard_recomputed := {"full": 0, "partial": 0, "unsupported": 0, "no_direct_stats": 0}
	for item: Dictionary in report.nodes:
		var is_standard := bool(item.get("default_allocation_graph", false))
		if str(item.type) == "mastery":
			for option: Dictionary in item.mastery_options:
				_tally_option(recomputed, option)
				if is_standard:
					_tally_option(standard_recomputed, option)
		else:
			_tally_node(recomputed, item)
			if is_standard:
				_tally_node(standard_recomputed, item)
	var all_counts: Dictionary = report.effect_coverage.all_source.direct_effect_entries
	var standard_counts: Dictionary = report.effect_coverage.standard_allocation_graph.direct_effect_entries
	for status: String in ["full", "partial", "unsupported", "no_direct_stats"]:
		check(int(all_counts[status]) == int(recomputed[status]), "all-source effect count recomputes from record statuses: " + status)
		check(int(standard_counts[status]) == int(standard_recomputed[status]), "standard-tree effect count recomputes from record statuses: " + status)
	check(int(all_counts.full) + int(all_counts.partial) + int(all_counts.unsupported) == int(all_counts.total_with_stats), "empty stats are excluded from full/partial/unsupported totals")
	check(int(report.effect_coverage.all_source.nodes_without_direct_stats) > 0, "empty-stat structural nodes are visibly separated")


func _tally_node(counts: Dictionary, item: Dictionary) -> void:
	if item.stats.is_empty():
		counts.no_direct_stats += 1
	else:
		var status := str(item.execution.api_status)
		if counts.has(status): counts[status] += 1


func _tally_option(counts: Dictionary, option: Dictionary) -> void:
	if option.stats.is_empty():
		counts.no_direct_stats += 1
	else:
		var status := str(option.execution.api_status)
		if counts.has(status): counts[status] += 1


func _verify_reachability(report: Dictionary) -> void:
	var standard_set := {}
	for id: String in TreeData.standard_ids():
		standard_set[id] = true
	check(report.class_reachability.size() == TreeData.class_starts().size(), "seven class start reports derive from source starts")
	for route: Dictionary in report.class_reachability:
		var start_id := str(route.start_node_id)
		var reached := {start_id: true}
		var queue: Array[String] = [start_id]
		var cursor := 0
		var blocked := {}
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			for neighbor_value: Variant in TreeData.adjacency(current):
				var neighbor := str(neighbor_value)
				if not standard_set.has(neighbor) or reached.has(neighbor):
					continue
				var node := TreeData.node(neighbor)
				if _is_excluded(neighbor, node, start_id):
					continue
				var effect: Dictionary = TreeRuntime.node_effect(neighbor)
				if str(effect.status) != "full":
					blocked[neighbor] = str(effect.status)
					continue
				reached[neighbor] = true
				queue.append(neighbor)
		var expected_ids: Array = reached.keys()
		expected_ids.sort()
		var actual_ids: Array = route.reachable_node_ids_including_start.duplicate()
		actual_ids.sort()
		check(actual_ids == expected_ids, "reachable set independently recomputes for " + str(route.class_name))
		check(actual_ids.has(start_id), "reachable set includes its own start: " + str(route.class_name))
		var expected_frontier: Array = blocked.keys()
		expected_frontier.sort()
		var actual_frontier: Array = []
		for item: Dictionary in route.blocked_frontier:
			actual_frontier.append(str(item.node_id))
			check(str(item.status) == str(blocked[item.node_id]), "frontier status comes from node_effect: " + str(item.node_id))
			var path: Array = item.shortest_executable_prefix
			check(not path.is_empty() and str(path[0]) == start_id and str(path[-1]) == str(item.node_id), "frontier retains a blocked path prefix: " + str(item.node_id))
			for index in range(path.size() - 1):
				check(TreeData.adjacency(str(path[index])).has(str(path[index + 1])), "frontier path uses source adjacency: " + str(item.node_id))
			for index in range(path.size() - 1):
				var path_node := TreeData.node(str(path[index]))
				if index == 0:
					continue
				check(str(TreeRuntime.node_effect(str(path_node.id)).status) == "full", "frontier path prefix before endpoint is executable: " + str(item.node_id))
			check(str(TreeRuntime.node_effect(str(item.node_id)).status) != "full", "frontier endpoint is currently locked: " + str(item.node_id))
		actual_frontier.sort()
		check(actual_frontier == expected_frontier, "blocked frontier independently recomputes for " + str(route.class_name))
		for id_value: Variant in actual_ids:
			var node := TreeData.node(str(id_value))
			check(not _is_excluded(str(id_value), node, start_id), "reachable set excludes prohibited node classes: " + str(id_value))
			if str(id_value) != start_id:
				check(str(TreeRuntime.node_effect(str(id_value)).status) == "full", "reachable ordinary node is full by node_effect: " + str(id_value))


func _is_excluded(node_id: String, node: Dictionary, own_start_id: String) -> bool:
	var source: Dictionary = node.get("source", {})
	return bool(source.get("isProxy", false)) \
		or bool(source.get("isBlighted", false)) \
		or str(node.get("type", "")) == "mastery" \
		or (str(node.get("type", "")) == "start" and node_id != own_start_id)


func _finish() -> void:
	print("Source execution coverage test: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
