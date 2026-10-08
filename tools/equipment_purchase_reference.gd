extends SceneTree
## Catalog-only export: no Main instance, save, transactions or RNG.
const Purchase = preload("res://scripts/items/equipment_purchase.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const BuildRules = preload("res://scripts/save/canonical_build_rules.gd")
static func collect() -> Dictionary:
	var offers: Array[Dictionary] = []
	for base_id: String in Gear.all_base_ids():
		var item := Purchase.make_item(base_id,1)
		assert(not item.is_empty() and item.payload.rarity=="normal" and item.payload.affixes.is_empty())
		var preview := Items.definition_for_instance(item)
		var size: Vector2i = preview.size
		offers.append({"base_id":base_id,"name":preview.name,"cost":Purchase.COST,"item_level":item.payload.item_level,
			"rarity":item.payload.rarity,"affix_count":item.payload.affixes.size(),"size":[size.x,size.y]})
	var inputs: Dictionary = {}
	for source: String in ["scripts/items/equipment_purchase.gd","scripts/main.gd","scripts/ui/town_service_panel.gd","scripts/ui/town_square_view.gd","scripts/items/equipment_catalog.gd"]:
		inputs[source]=FileAccess.get_sha256("res://"+source)
	return {"cost":Purchase.COST,"item_level":Purchase.ITEM_LEVEL,"rarity":"normal","affix_count":0,
		"offers":offers,"source_sha256":inputs,"service_id":"equipment_merchant","save_version":BuildRules.VERSION}
func _initialize() -> void:
	var output := FileAccess.open("res://docs/qa/equipment-purchase-reference/fragment.json",FileAccess.WRITE)
	assert(output!=null)
	output.store_string(JSON.stringify(collect(),"\t",true,true)+"\n");output.close()
	print("Equipment purchase catalog-only reference exported");quit()
