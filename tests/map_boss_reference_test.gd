extends SceneTree
const Exporter=preload("res://tools/export_reference.gd")
const Bosses=preload("res://scripts/monsters/map_boss_profiles.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/catalog.json"));var current:=Exporter.map_boss_examples()
	check(data.game_version=="0.36.0" and data.save_version==23,"Reference uses current release and unchanged save schema")
	check(data.map_bosses==JSON.parse_string(JSON.stringify(Exporter.clean(current),"",true,true)),"Saved map-boss examples exactly reproduce current production exporter")
	check(current.size()==2,"Both map policies shipped in one batch")
	for id:String in current:
		var row:Dictionary=current[id];var definition:=Bosses.definition(row.definition.id)
		check(row.definition==definition and row.policy.target_rule==definition.target_rule and row.event.visual_pattern==definition.id,"Definition, actual policy and frozen event share one identity")
		check(row.cases.standing.inside and not row.cases.moving.inside,"Each actual circle can be escaped by the documented straight retreat")
		check(row.cases.standing.settlement.shield_spent==5.0 and row.cases.standing.settlement.health_lost>0,"Reference damage resolves shield before health")
		check(data.town_maps.examples[id].compiled.boss_attack_id==row.definition.id,"Finite map card points to the actual selected boss policy")
	var html:=FileAccess.get_file_as_string("res://docs/reference/index.html")
	check(html.contains("近身震地 · 起手锁点与退离示意") and html.contains("断垣落印 · 起手锁点与退离示意") and html.contains("结算不追踪"),"Both map cards include proportionate diagrams and frozen-point disclosure")
	print("Map boss reference: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
