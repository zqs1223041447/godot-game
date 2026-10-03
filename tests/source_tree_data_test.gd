extends SceneTree
const TreeData = preload("res://scripts/passives/source_tree_data.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	check(TreeData.ready(), "pinned runtime facts available")
	var nodes := TreeData.nodes()
	check(nodes.size() == 3390 and TreeData.standard_ids().size() == 2387, "all data and safe standard population distinguished")
	check(TreeData.class_starts().size() == 7 and TreeData.standard_socket_ids().size() == 15, "seven source starts and fifteen ordinary sockets")
	check(TreeData.start_for_class(0) == "58833" and TreeData.start_for_class(6) == "44683" and TreeData.start_for_class(7) == "", "source class mapping")
	check(TreeData.source_points() == {"ascendancyPoints":8.0,"totalPoints":123.0}, "original point maxima")
	var standard: Array = TreeData.standard_ids()
	var directed := 0
	for id: String in standard:
		var node := TreeData.node(id)
		check(node.has_position and node.position.is_finite(), "standard source position finite")
		check(id != "root" and not node.source.has("ascendancyName") and not node.source.has("expansionJewel"), "no root or alternate partition admission")
		for adjacent: String in TreeData.adjacency(id):
			directed += 1
			check(standard.has(adjacent) and TreeData.adjacency(adjacent).has(id), "safe undirected internal adjacency")
	check(directed == 2697 * 2, "all safe internal source edges retained")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/passive_source/normalized_tree.json"))
	for id: String in raw.node_records:
		check(nodes[id].stats == raw.node_records[id].get("stats",[]), "all original stat lines exact")
		check(nodes[id].mastery_effects == raw.node_records[id].get("masteryEffects",[]), "all original mastery choices exact")
	var altered := TreeData.node("58833")
	altered.source.clear()
	check(TreeData.node("58833").source.has("classStartIndex"), "detached source record")
	print("Source tree data: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
