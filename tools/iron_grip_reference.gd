extends SceneTree
## Read-only bounded reference projection, reusing the existing exporters.
const Exporter = preload("res://tools/export_reference.gd")
const Coverage = preload("res://tools/export_source_execution_coverage.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const LINE := "Strength's Damage bonus applies to Projectile Attack Damage as well as Melee Damage"
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2: quit(78); return
	var source := Exporter.source_tree_reference()
	var localized := Exporter.source_tree_localization_reference(source)
	var coverage := Coverage.build_report()
	assert(coverage.integrity.ok and Rules.VERSION == 57 and Runtime.CURRENT_SAVE_VERSION == 57)
	var node: Dictionary = source.nodes["12926"].duplicate(true)
	assert(node.execution.status == "full" and Runtime.node_effect("12926",0,56).status == "unsupported")
	var classes: Array[int] = []
	for route: Dictionary in coverage.class_reachability:
		if route.reachable_node_ids_including_start.has("12926"): classes.append(int(route.class_id))
	node.ordinary_reachable_class_ids = classes
	var fragment := {"save_version":57,"source_policy":57,"source_sha256":source.source_sha256,
		"node":node,"localized_node":localized.nodes["12926"],"localized_line":localized.lines[LINE],
		"iron_grip":{"node_id":"12926","minimum_save_version":57,"previous_save_version":56,
			"backup_suffix":".v56-backup.json","equipment_vocabulary":Rules.equipment_vocabulary_for_save_version(57),
			"strength_step":5,"increased_per_step":0.01,"ranger_paid_points":14,
			"ranger_route":["50459","39821","52904","444","61306","63139","5408","11497","238","10829","16167","19144","28330","46578","12926"]}}
	var file := FileAccess.open(args[0],FileAccess.WRITE)
	assert(file != null); file.store_string(JSON.stringify(Exporter.clean(fragment),"\t",true,true)+"\n"); file.close()
	file = FileAccess.open(args[1],FileAccess.WRITE)
	assert(file != null); file.store_string(Coverage.serialize_report(coverage)); file.close()
	print("IRON_GRIP_REFERENCE target12926; save/source57, frozen56; ordinary classes=",classes)
	quit()
