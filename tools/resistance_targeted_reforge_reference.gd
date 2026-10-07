extends SceneTree
## One bounded, read-only projection. No model, scene, save, combat or full export.
const Export = preload("res://tools/export_reference.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const NEW_IDS: Array[String] = ["targeted_reforge_fire_resistance", "targeted_reforge_cold_resistance",
	"targeted_reforge_lightning_resistance", "targeted_reforge_chaos_resistance"]
const REPORT := "res://docs/qa/v103-transactions/first/transactions-report.json"
const OUT := "res://docs/qa/v103-reference/authority-fragment.json"


func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
	assert(source.failure_count == 0 and source.schema == 53 and source.vocabulary == 51)
	var fragment := {"schema": source.schema, "vocabulary": Gear.CURRENT_VOCABULARY,
		"operations": {}, "definitions": {}, "new_helper_checks": 0, "old_helper_checks": 0}
	var metadata := Craft.metadata()
	for operation: String in Craft.operation_ids():
		var instance: Dictionary = Export._crafting_example_instance(operation)
		if operation in NEW_IDS:
			assert(Gear.validate_instance(instance) and Craft.operation_quote(instance, operation).ok)
			fragment.new_helper_checks += 1
			fragment.operations[operation] = {"presentation": Craft.operation_metadata(operation),
				"rule": metadata.operations[operation], "constraints": Export._targeted_crafting_constraints(operation)}
		else:
			var original: Dictionary = Export._local_instance(["whetstone_edge"], "magic")
			if Craft.Targeted.operation_ids().has(operation) and operation != "targeted_reforge_damage":
				original = Export._local_instance(["global_critical_chance"], "magic", "wayglass_token")
			assert(var_to_bytes(instance) == var_to_bytes(original))
			fragment.old_helper_checks += 1
	for row: Dictionary in source.transactions:
		assert(Gear.validate_instance(row.generation.source) and Gear.validate_instance(row.crafted))
		assert(row.quote.ok and row.result.ok and row.quote.source_instance == row.generation.source)
		fragment.definitions[row.name] = {"before": Gear.definition(row.generation.source),
			"after": Gear.definition(row.crafted)}
	assert(fragment.new_helper_checks == 4 and fragment.old_helper_checks == 10 and fragment.definitions.size() == 14)
	var output := FileAccess.open(OUT, FileAccess.WRITE)
	assert(output != null)
	output.store_string(JSON.stringify(fragment, "\t", true) + "\n")
	output.close()
	print("v103 bounded reference: four authority entries, fourteen actual-source definitions, four new and ten exact old exporter witnesses")
	quit(0)
