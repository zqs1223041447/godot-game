extends "res://scripts/items/equipment_purchase.gd"
## Existing fixed-minimum magic samples only; shared purchase/receipt authority.
const Jewels = preload("res://scripts/jewel_data.gd")
const Town = preload("res://scripts/town/town_catalog.gd")
const JewelCraft = preload("res://scripts/items/jewel_craft_rules.gd")
static func make_jewel(base_id: Variant, serial: int) -> Dictionary:
	if typeof(base_id) != TYPE_STRING or not Jewels.BASES.has(base_id) or serial < 1 or serial >= Rules.MAX_SERIAL: return {}
	return Town.make_item({"supply_kind":"jewel","catalog_id":base_id},serial)
func _make_item(base_id: Variant, serial: int) -> Dictionary: return make_jewel(base_id,serial)
func _cost() -> int: return JewelCraft.REFORGE_COSTS.magic
func _quote_details(base_id: String) -> Dictionary:
	var preview := Items.definition_for_instance(make_jewel(base_id,1))
	return {"name":preview.name,"description":preview.description,"rarity":"magic"}
func offers(model: RefCounted, path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var guard := _guard(model,model.revision(),path)
	for base_id: String in Jewels.BASES:
		var wrapped := make_jewel(base_id,1)
		var preview := Items.definition_for_instance(wrapped)
		var reason := str(guard.reason)
		if guard.ok: reason = str(_plan(model,base_id).reason)
		rows.append({"id":"jewel:"+base_id,"base_id":base_id,"definition_id":wrapped.definition_id,"kind":"jewel",
			"name":preview.name,"description":"固定最低数值魔法珠宝；仅在已分配并连通的珠宝孔中生效。\n"+str(preview.description),
			"preview":preview,"icon_path":str(preview.get("icon_path","")),"size":preview.size,
			"cost":_cost(),"paid":true,"purchase_kind":"jewel","price_label":"%d 校准碎片" % _cost(),
			"available":reason.is_empty(),"reason":reason})
	return rows
