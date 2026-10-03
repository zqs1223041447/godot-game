extends SceneTree
const Exporter=preload("res://tools/export_reference.gd")
const Catalog=preload("res://scripts/town/town_catalog.gd")
const Maps=preload("res://scripts/world/map_compiler.gd")
var checks:=0
var failures:=0
func _initialize()->void:
	var actual:=Exporter.town_map_examples()
	var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/catalog.json"))
	check(JSON.parse_string(JSON.stringify(Exporter.clean(actual),"",true,true))==saved.town_maps,"Exported town/map section exactly equals runtime catalogs")
	check(actual.save_version==19 and actual.services.size()==6 and actual.mode=="optional_town_test","Source schema and optional services disclosed")
	check(actual.normal_save!=actual.test_save and not actual.map_reward_bonus and not actual.map_runtime_persistent and not actual.retired_profile_writes,"Isolation and runtime-only map boundaries explicit")
	for service:String in ["skill_merchant","equipment_merchant","jewel_merchant"]:check(actual.stock[service]==Catalog.offers(service),"Entire real supplier catalog exported")
	for key:String in actual.examples:
		check(Maps.profile_reason(actual.examples[key].compiled).is_empty(),"Reference map example uses executable profile")
		check(actual.examples[key].compiled.ordinary_target in [24,36] and actual.examples[key].compiled.boss_id=="rift_warden","Finite goal has real boss")
	check(actual.options.cost_policy.cost.is_empty() and not actual.options.cost_policy.affects_legacy_currency,"Map test crafting creates no wallet or debit")
	print("Town map reference: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(why)
