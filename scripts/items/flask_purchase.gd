extends "res://scripts/items/equipment_purchase.gd"
## Existing recovery bottles, using the shared atomic purchase authority.
const Flasks = preload("res://scripts/items/flask_catalog.gd")
const CraftCost = preload("res://scripts/items/jewel_craft_rules.gd")
static func make_flask(definition_id: Variant, serial: int) -> Dictionary:
	if typeof(definition_id) != TYPE_STRING or not Flasks.DEFINITIONS.has(definition_id) or serial < 1 or serial >= Rules.MAX_SERIAL: return {}
	return Flasks.create_instance("item_%06d" % serial,definition_id)
func _make_item(base_id: Variant, serial: int) -> Dictionary: return make_flask(base_id,serial)
# Reference the existing eight-shard magic reforge/basic procurement tier.
# This is a purchase price; FlaskCatalog.USE_COST remains runtime charge only.
func _cost() -> int: return CraftCost.REFORGE_COSTS.magic
func _quote_details(base_id: String) -> Dictionary:
	var preview := Flasks.definition(base_id)
	return {"name":preview.name,"description":preview.description}
func offers(model: RefCounted, path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var guard := _guard(model,model.revision(),path)
	for definition_id: String in Flasks.DEFINITIONS:
		var preview := Flasks.definition(definition_id)
		var reason := str(guard.reason)
		if guard.ok: reason = str(_plan(model,definition_id).reason)
		rows.append({"id":definition_id,"base_id":definition_id,"definition_id":definition_id,"kind":"flask",
			"name":preview.name,"description":preview.description,"preview":preview,"icon_path":preview.icon_path,"size":preview.size,
			"cost":_cost(),"paid":true,"purchase_kind":"flask","price_label":"%d 校准碎片" % _cost(),
			"available":reason.is_empty(),"reason":reason})
	return rows
