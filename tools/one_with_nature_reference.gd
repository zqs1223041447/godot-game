extends SceneTree
## Read-only source/coverage projection; no saves, transactions or combat runs.
const Exporter = preload("res://tools/export_reference.gd")
const Coverage = preload("res://tools/export_source_execution_coverage.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const LINE := "24% increased Elemental Damage with Attack Skills"
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2: quit(78); return
	var source := Exporter.source_tree_reference()
	var localized := Exporter.source_tree_localization_reference(source)
	var coverage := Coverage.build_report()
	assert(coverage.integrity.ok and Rules.VERSION == 56 and Runtime.CURRENT_SAVE_VERSION == 56)
	var reachable: Array[int] = []
	for route: Dictionary in coverage.class_reachability:
		assert(route.reachable_node_ids_including_start.has("15842") and route.reachable_node_ids_including_start.has("18670"))
		reachable.append(int(route.class_id))
	var node: Dictionary = source.nodes["15842"].duplicate(true)
	assert(node.execution.status == "full" and node.execution.unsupported.is_empty())
	node.ordinary_reachable_class_ids = reachable
	var fraction := 0.0
	for grant: Dictionary in node.execution.grants:
		if grant.stat == "attack_elemental_increased": fraction = float(grant.value); assert(grant.mode == "increased")
	assert(fraction == 0.24 and Runtime.node_effect("15842",0,55).status == "partial")
	var fragment := {"save_version":Rules.VERSION,"source_policy":Runtime.CURRENT_SAVE_VERSION,"source_sha256":source.source_sha256,
		"node":node,"localized_node":localized.nodes["15842"],"localized_line":localized.lines[LINE],
		"linked_existing_node":{"id":"18670","ordinary_reachable_class_ids":reachable},
		"one_with_nature":{"node_id":"15842","minimum_save_version":Rules.VERSION,"previous_save_version":Rules.V55_VERSION,
			"stat":"attack_elemental_increased","value":fraction,"mode":"increased","equipment_vocabulary":Rules.equipment_vocabulary_for_save_version(Rules.VERSION),
			"backup_suffix":".v55-backup.json","changes_only_version":true,"combat_runtime_restored":false,
			"arbitrary_concurrent_write_cas":false,"power_loss_durability_claim":false}}
	var file := FileAccess.open(args[0],FileAccess.WRITE)
	assert(file != null); file.store_string(JSON.stringify(Exporter.clean(fragment),"\t",true,true)+"\n"); file.close()
	file = FileAccess.open(args[1],FileAccess.WRITE)
	assert(file != null); file.store_string(Coverage.serialize_report(coverage)); file.close()
	print("ONE_WITH_NATURE_REFERENCE exact15842 + existing18670 reachable; save/source56, frozen55")
	quit()
