extends SceneTree
## One existing exporter operation; no full catalog rebuild or live save.
const Export=preload("res://tools/export_reference.gd")
const OP="targeted_reforge_armour"
func _initialize()->void:
	var data:=Export.crafting_examples([OP])
	assert(data.size()==2 and data[OP].eligible_base_ids==["emberhide_vest"])
	var result:Dictionary={"operation":data[OP],"rule":data.calibration_shard.rules.operations[OP]}
	FileAccess.open("res://docs/qa/armour-targeted-reforge/reference-fragment.json",FileAccess.WRITE).store_string(JSON.stringify(Export.clean(result),"\t",true,true)+"\n")
	print("ARMOUR_REFERENCE one current operation; schema61 vocabulary51");quit()
