extends SceneTree
const Controls=preload("res://scripts/ui/encounter_controls.gd")
const Catalog=preload("res://scripts/encounters/encounter_catalog.gd")
func _initialize() -> void:
	var checks: Array[bool]=[]
	checks.append(Controls.selection_summary("普通遭遇",[])=="普通遭遇")
	var definitions: Array=[{"description":"护甲 +80"},{"description":"护盾增加基础生命的20%"}]
	checks.append(Controls.selection_summary("已选择 2 / 2 条",definitions)=="已选择 2 / 2 条\n护甲 +80\n护盾增加基础生命的20%")
	var panel=Controls.new()
	for id: String in Catalog.get_ids():
		var definition: Dictionary=Catalog.get_definition(id)
		var label=panel.find_child("EncounterDescription_"+id,true,false)
		checks.append(label.text==str(definition.description))
		checks.append(panel.set_context([id]))
		checks.append(panel.find_child("EncounterPreview",true,false).text.contains(str(definition.description)))
	panel.free()
	print("Map modifier text: %d checks, %d failures" % [checks.size(),checks.count(false)])
	quit(0 if checks.count(false)==0 else 1)
