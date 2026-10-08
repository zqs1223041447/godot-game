extends SceneTree
## Read-only bounded reference projection, reusing the existing exporters.
const Exporter = preload("res://tools/export_reference.gd")
const Coverage = preload("res://tools/export_source_execution_coverage.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const LINE := "Maximum Life becomes 1, Immune to Chaos Damage"
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2: quit(78); return
	var source := Exporter.source_tree_reference()
	var localized := Exporter.source_tree_localization_reference(source)
	var coverage := Coverage.build_report()
	assert(coverage.integrity.ok and Rules.VERSION == 59 and Runtime.CURRENT_SAVE_VERSION == 59)
	var node: Dictionary = source.nodes["11455"].duplicate(true)
	assert(node.execution.status == "full" and Runtime.node_effect("11455",0,58).status == "unsupported")
	var classes: Array[int] = []
	for route: Dictionary in coverage.class_reachability:
		if route.reachable_node_ids_including_start.has("11455"): classes.append(int(route.class_id))
	node.ordinary_reachable_class_ids = classes
	var fragment := {"save_version":59,"source_policy":59,"source_sha256":source.source_sha256,
		"node":node,"localized_node":localized.nodes["11455"],"localized_line":localized.lines[LINE],
		"chaos_inoculation":{"node_id":"11455","minimum_save_version":59,"previous_save_version":58,
			"backup_suffix":".v58-backup.json","equipment_vocabulary":Rules.equipment_vocabulary_for_save_version(59),
			"maximum_life":1,"witch_paid_points":11,
			"witch_route":["54447","57226","21678","32210","8948","27659","37671","27415","32710","49605","60440","11455"]}}
	var file := FileAccess.open(args[0],FileAccess.WRITE)
	assert(file != null); file.store_string(JSON.stringify(Exporter.clean(fragment),"\t",true,true)+"\n"); file.close()
	file = FileAccess.open(args[1],FileAccess.WRITE)
	assert(file != null); file.store_string(Coverage.serialize_report(coverage)); file.close()
	print("CHAOS_INOCULATION_REFERENCE target11455; save/source59, frozen58; ordinary classes=",classes)
	quit()
