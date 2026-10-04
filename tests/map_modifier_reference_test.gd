extends SceneTree
const Exporter=preload("res://tools/export_reference.gd")
const Catalog=preload("res://scripts/encounters/encounter_catalog.gd")
const Compiler=preload("res://scripts/encounters/encounter_compiler.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	var current:Dictionary=Exporter.encounter_examples();var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/catalog.json"))
	check(JSON.parse_string(JSON.stringify(Exporter.clean(current),"",true,true))==saved.encounters,"Published six modifier data exactly matches current runtime export")
	check(current.size()==6,"All current modifiers included")
	for id:String in current:
		var row:Dictionary=current[id]
		check(row.description==Catalog.get_definition(id).description and Compiler.profile_error(row.profile).is_empty(),"Descriptions and profiles use the same current definition")
		for sample:Dictionary in row.examples.values():
			var applied:Dictionary=Compiler.apply_to_enemy(sample.before,row.profile)
			check(applied.ok and applied.enemy==sample.after,"Each before/after example is the real candidate")
			if row.field=="max_shield":check(is_equal_approx(sample.after.max_shield-sample.before.max_shield,sample.before.max_health*0.2),"Shield diagrams use fixed original health")
			if row.field=="attack_speed" and not sample.before_telegraph.is_empty():check(sample.before_telegraph.profile.windup_seconds==sample.after_telegraph.profile.windup_seconds,"Reference never claims faster warning")
	print("Map modifier reference: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
