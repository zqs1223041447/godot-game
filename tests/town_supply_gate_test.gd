extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Catalog=preload("res://scripts/town/town_catalog.gd")
var checks:=0
var failures:=0
func _initialize()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	for service:String in ["skill_merchant","equipment_merchant","jewel_merchant"]:
		for row:Dictionary in Catalog.offers(service):check(Catalog.offer(row.id)==row,"Direct lookup equals full catalog entry "+row.id)
	for bad:Variant in [null,4,true,{},"skill:missing","base:unknown","fixed:unknown","jewel:unknown","currency:other","flask:unknown"]:check(Catalog.offer(bad).is_empty(),"Reject invalid offer without alternative lookup")
	var normal:=Model.new();var normal_path:="user://build_save.json";check(normal.save_build(normal_path)==OK,"Open normal profile")
	check(not normal.can_discard_item("swift_blade"),"Normal fixed equipment cannot be discarded")
	var base:Dictionary={"id":"gear_000001","base_id":"cinder_reed","item_level":30,"rarity":"normal","affixes":[]}
	check(normal._admit_reward_item(Model.Items.wrap_equipment(base)),"Normal white item admitted")
	check(not normal.can_discard_item(base.id) and not normal.discard_item(base.id,normal.revision(),normal_path).ok,"Normal white equipment rule unchanged")
	var test:=Model.new();test._accept_memory(normal.snapshot());var path:="user://town_test_build_save.json";check(test.save_build(path)==OK,"Open distinct test profile")
	check(test.can_discard_item(base.id),"Test bag white item can be discarded")
	var before:=test.snapshot();var result:=test.discard_item(base.id,test.revision(),path)
	check(result.ok and test.item(base.id).is_empty() and normal.item(base.id)==before.items[base.id],"Test disposal removes one UID atomically, normal profile untouched")
	for uid:String in test.equipped.values():check(not test.can_discard_item(uid),"Equipped reference cannot be discarded")
	var owned:String=""
	for uid:String in test.snapshot().items:
		if test.item(uid).kind=="equipment" and test.location(uid).kind=="bag":owned=uid;break
	check(not owned.is_empty() and test.can_discard_item(owned),"Unworn fixed test supply is clearable")
	print("Town supply gates: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func check(ok:bool,why:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(why)
