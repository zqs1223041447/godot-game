extends SceneTree
## Catalog-only metadata. No Main, user save, transaction or random generation.
const Purchase = preload("res://scripts/items/jewel_purchase.gd")
const BuildRules = preload("res://scripts/save/canonical_build_rules.gd")
static func collect() -> Dictionary:
	var offers: Array[Dictionary] = []
	for base_id: String in Purchase.Jewels.BASES:
		var item := Purchase.make_jewel(base_id,1)
		assert(not item.is_empty() and item.payload.rarity=="magic" and item.payload.affixes.size()==2)
		for affix: Dictionary in item.payload.affixes:
			assert(is_equal_approx(float(affix.value),float(Purchase.Jewels.AFFIXES[affix.id].min)))
		var preview := Purchase.Items.definition_for_instance(item)
		offers.append({"base_id":base_id,"name":preview.name,"cost":Purchase.JewelCraft.REFORGE_COSTS.magic,
			"rarity":"magic","affixes":item.payload.affixes,"description":preview.description,"stats":preview.stats,"size":[1,1]})
	var inputs: Dictionary = {}
	for source: String in ["scripts/items/equipment_purchase.gd","scripts/items/jewel_purchase.gd","scripts/jewel_data.gd","scripts/town/town_catalog.gd","scripts/items/jewel_craft_rules.gd","scripts/main.gd","scripts/ui/town_service_panel.gd","scripts/ui/town_square_view.gd"]:
		inputs[source]=FileAccess.get_sha256("res://"+source)
	return {"service_id":"jewel_merchant","cost":Purchase.JewelCraft.REFORGE_COSTS.magic,"salvage_credit":Purchase.JewelCraft.SALVAGE_UNITS.magic,
		"rarity":"magic","fixed_minimum":true,"special_sold":false,"offers":offers,"source_sha256":inputs,"save_version":BuildRules.VERSION}
func _initialize() -> void:
	var output := FileAccess.open("res://docs/qa/jewel-purchase-reference/fragment.json",FileAccess.WRITE)
	assert(output!=null)
	output.store_string(JSON.stringify(collect(),"\t",true,true)+"\n");output.close()
	print("Jewel purchase catalog-only reference exported");quit()
