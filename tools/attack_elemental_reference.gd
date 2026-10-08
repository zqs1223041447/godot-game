extends SceneTree
## Bounded F8 refresh; the existing exporters remain the only data authority.
const Exporter = preload("res://tools/export_reference.gd")
const Coverage = preload("res://tools/export_source_execution_coverage.gd")
const TreeRuntime = preload("res://scripts/passives/source_tree_runtime.gd")
const IDS := ["18670", "25511", "30894", "56646", "64878"]
const LINE := "12% increased Elemental Damage with Attack Skills"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Expected fragment and coverage output paths")
		quit(1)
		return
	var source := Exporter.source_tree_reference()
	var localized := Exporter.source_tree_localization_reference(source)
	var coverage := Coverage.build_report()
	assert(coverage.integrity.ok)
	var nodes: Dictionary = {}
	var localized_nodes: Dictionary = {}
	for id: String in IDS:
		assert(source.nodes[id].stats == [LINE])
		assert(source.nodes[id].execution.status == "full")
		nodes[id] = source.nodes[id].duplicate(true)
		var ordinary_classes: Array[int] = []
		for route: Dictionary in coverage.class_reachability:
			if route.reachable_node_ids_including_start.has(id):
				ordinary_classes.append(int(route.class_id))
		nodes[id]["ordinary_reachable_class_ids"] = ordinary_classes
		localized_nodes[id] = localized.nodes[id]
	assert(nodes["18670"].ordinary_reachable_class_ids.is_empty())
	var fragment := {"save_version": TreeRuntime.CURRENT_SAVE_VERSION, "source_policy": TreeRuntime.CURRENT_SAVE_VERSION,
		"source_sha256": source.source_sha256, "nodes": nodes, "localized_nodes": localized_nodes,
		"localized_lines": {LINE: localized.lines[LINE]}}
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(Exporter.clean(fragment), "\t", true, true) + "\n")
	file.close()
	file = FileAccess.open(args[1], FileAccess.WRITE)
	assert(file != null)
	file.store_string(Coverage.serialize_report(coverage))
	file.close()
	print("Exported five current source cards; 18670 has no supported ordinary route")
	quit(0)
