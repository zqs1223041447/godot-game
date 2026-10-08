extends SceneTree
## Catalog-only metadata; no Main, user save, transaction or RNG.
const Purchase = preload("res://scripts/items/flask_purchase.gd")
const BuildRules = preload("res://scripts/save/canonical_build_rules.gd")
static func collect() -> Dictionary:
	var offers: Array[Dictionary] = []
	for definition_id: String in Purchase.Flasks.DEFINITIONS:
		var item := Purchase.make_flask(definition_id,1)
		assert(Purchase.Flasks.validate_instance(item) and item.payload.is_empty())
		var preview := Purchase.Flasks.definition(definition_id)
		var size: Vector2i = preview.size
		offers.append({"definition_id":definition_id,"name":preview.name,"resource":preview.resource,
			"cost":Purchase.COST,"size":[size.x,size.y],"description":preview.description,
			"max_charges":preview.max_charges,"use_cost":preview.cost,
			"duration":preview.duration,"recovery_fraction":preview.recovery_fraction})
	var inputs: Dictionary = {}
	for source: String in ["scripts/items/flask_purchase.gd","scripts/items/equipment_purchase.gd","scripts/items/flask_catalog.gd","scripts/combat/flask_runtime.gd","scripts/main.gd","scripts/ui/town_service_panel.gd","scripts/ui/canonical_inventory_panel.gd","scripts/save/canonical_build_rules.gd"]:
		inputs[source]=FileAccess.get_sha256("res://"+source)
	return {"service_id":"equipment_merchant","cost":Purchase.COST,"offers":offers,
		"source_sha256":inputs,"save_version":BuildRules.VERSION}
func _initialize() -> void:
	var output := FileAccess.open("res://docs/qa/flask-purchase-reference/fragment.json",FileAccess.WRITE)
	assert(output!=null)
	output.store_string(JSON.stringify(collect(),"\t",true,true)+"\n");output.close()
	print("Flask purchase catalog-only reference exported");quit()
