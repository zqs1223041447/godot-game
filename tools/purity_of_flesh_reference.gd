extends SceneTree
## Read-only bounded reference projection, reusing the existing exporters.
const Exporter = preload("res://tools/export_reference.gd")
const Coverage = preload("res://tools/export_source_execution_coverage.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const LINE := "+8% to Chaos Resistance"
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2: quit(78); return
	var source := Exporter.source_tree_reference()
	var localized := Exporter.source_tree_localization_reference(source)
	var coverage := Coverage.build_report()
	assert(coverage.integrity.ok and Rules.VERSION == 60 and Runtime.CURRENT_SAVE_VERSION == 60)
	var node: Dictionary = source.nodes["58218"].duplicate(true)
	assert(node.execution.status == "full" and Runtime.node_effect("58218",0,59).status == "partial")
	var classes: Array[int] = []
	for route: Dictionary in coverage.class_reachability:
		if route.reachable_node_ids_including_start.has("58218"): classes.append(int(route.class_id))
	node.ordinary_reachable_class_ids = classes
	var fragment := {"save_version":60,"source_policy":60,"source_sha256":source.source_sha256,
		"node":node,"localized_node":localized.nodes["58218"],"localized_line":localized.lines[LINE],
		"chaos_defense_metadata":Defense.chaos_resistance_metadata(),"purity_of_flesh":Exporter.purity_of_flesh_reference()}
	var file := FileAccess.open(args[0],FileAccess.WRITE)
	assert(file != null); file.store_string(JSON.stringify(Exporter.clean(fragment),"\t",true,true)+"\n"); file.close()
	file = FileAccess.open(args[1],FileAccess.WRITE)
	assert(file != null); file.store_string(Coverage.serialize_report(coverage)); file.close()
	print("PURITY_OF_FLESH_REFERENCE target58218; save/source60, frozen59; ordinary classes=",classes)
	quit()
