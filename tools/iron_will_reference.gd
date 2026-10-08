extends SceneTree
## Read-only bounded reference projection, reusing the existing exporters.
const Exporter = preload("res://tools/export_reference.gd")
const Coverage = preload("res://tools/export_source_execution_coverage.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const LINE := "Strength's Damage bonus applies to all Spell Damage as well"
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2: quit(78); return
	var source := Exporter.source_tree_reference()
	var localized := Exporter.source_tree_localization_reference(source)
	var coverage := Coverage.build_report()
	assert(coverage.integrity.ok and Rules.VERSION == 58 and Runtime.CURRENT_SAVE_VERSION == 58)
	var node: Dictionary = source.nodes["50288"].duplicate(true)
	assert(node.execution.status == "full" and Runtime.node_effect("50288",0,57).status == "unsupported")
	var classes: Array[int] = []
	for route: Dictionary in coverage.class_reachability:
		if route.reachable_node_ids_including_start.has("50288"): classes.append(int(route.class_id))
	node.ordinary_reachable_class_ids = classes
	var fragment := {"save_version":58,"source_policy":58,"source_sha256":source.source_sha256,
		"node":node,"localized_node":localized.nodes["50288"],"localized_line":localized.lines[LINE],
		"iron_will":{"node_id":"50288","minimum_save_version":58,"previous_save_version":57,
			"backup_suffix":".v57-backup.json","equipment_vocabulary":Rules.equipment_vocabulary_for_save_version(58),
			"strength_step":5,"increased_per_step":0.01,"scion_paid_points":8,
			"scion_route":["58833","2151","37690","48423","6204","63976","16775","46910","50288"]}}
	var file := FileAccess.open(args[0],FileAccess.WRITE)
	assert(file != null); file.store_string(JSON.stringify(Exporter.clean(fragment),"\t",true,true)+"\n"); file.close()
	file = FileAccess.open(args[1],FileAccess.WRITE)
	assert(file != null); file.store_string(Coverage.serialize_report(coverage)); file.close()
	print("IRON_WILL_REFERENCE target50288; save/source58, frozen57; ordinary classes=",classes)
	quit()
