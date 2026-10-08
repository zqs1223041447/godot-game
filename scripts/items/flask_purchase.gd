extends "res://scripts/items/equipment_purchase.gd"
## Existing life/mana bottles only; share the issued quote and atomic inventory commit.
const Flasks = preload("res://scripts/items/flask_catalog.gd")
static func make_flask(definition_id: Variant, serial: int) -> Dictionary:
	if typeof(definition_id) != TYPE_STRING or serial < 1 or serial >= Rules.MAX_SERIAL: return {}
	return Flasks.create_instance("item_%06d" % serial,definition_id)
func _make_item(definition_id: Variant, serial: int) -> Dictionary: return make_flask(definition_id,serial)
func _quote_details(definition_id: String) -> Dictionary:
	var preview := Flasks.definition(definition_id)
	return {"name":preview.name,"description":preview.description}
func offers(model: RefCounted, path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var guard := _guard(model,model.revision(),path)
	for definition_id: String in Flasks.DEFINITIONS:
		var preview := Flasks.definition(definition_id)
		var reason := str(guard.reason)
		if guard.ok: reason = str(_plan(model,definition_id).reason)
		rows.append({"id":definition_id,"base_id":definition_id,"definition_id":definition_id,"kind":"flask",
			"name":preview.name,"description":preview.description,"preview":preview,
			"icon_path":preview.icon_path,"size":preview.size,"cost":_cost(),"paid":true,
			"purchase_kind":"flask","price_label":"%d 校准碎片" % _cost(),
			"available":reason.is_empty(),"reason":reason})
	return rows
