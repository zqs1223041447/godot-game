extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Catalog=preload("res://scripts/items/flask_catalog.gd")
const Runtime=preload("res://scripts/combat/flask_runtime.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Migration=preload("res://scripts/save/flask_item_migration.gd")
const Locations=preload("res://scripts/items/item_location_rules.gd")
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func near(actual:float,expected:float,label:String)->void:check(is_equal_approx(actual,expected),label+" %.8f / %.8f"%[actual,expected])
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	test_runtime();test_models()
	print("Flask model: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func test_runtime()->void:
	var own:Dictionary={"life_a":"flask:life","life_b":"flask:life","mana_a":"flask:mana"}
	var runtime:=Runtime.new();check(runtime.reset(own),"Validated owned flask set resets")
	check(runtime.snapshot().charges_by_uid=={"life_a":30,"life_b":30,"mana_a":30},"Each UID starts exactly30")
	var before:=runtime.snapshot()
	check(not runtime.use("life_a",100.0,100.0).ok and runtime.snapshot()==before,"Full life rejects without charge")
	check(runtime.use("life_a",10.0,100.0).ok,"Actual life use admitted")
	check(runtime.snapshot().charges_by_uid.life_a==20,"Successful use costs10")
	check(not runtime.use("life_b",10.0,100.0).ok and runtime.snapshot().charges_by_uid.life_b==30,"Different UID cannot stack same resource")
	check(runtime.use("mana_a",0.0,200.0).ok,"Mana can recover concurrently")
	var current:Dictionary={"health":10.0,"mana":0.0};var maxima:Dictionary={"health":100.0,"mana":200.0}
	for unused:int in range(30):
		var gain:=runtime.advance(0.1,current,maxima)
		current.health+=gain.health;current.mana+=gain.mana
	near(current.health,45.0,"Exactly35 percent life over3s")
	near(current.mana,70.0,"Exactly35 percent mana over3s")
	check(runtime.snapshot().active_by_resource.is_empty(),"Both finite effects expire")
	check(runtime.sync_owned(own) and runtime.snapshot().charges_by_uid.life_a==20,"Unchanged ownedUID sync cannot refill")
	runtime.use("life_a",10.0,100.0)
	near(runtime.advance(3.0,{"health":10.0,"mana":0.0},{"health":200.0,"mana":200.0}).health,35.0,"Maximum changed mid-effect cannot rescale locked amount")
	runtime.use("life_a",95.0,100.0)
	near(runtime.advance(3.0,{"health":95.0,"mana":0.0},maxima).health,5.0,"Recovery clamps without overflow")
	check(not runtime.status("life_a",0.0,100.0).can_use,"Three charges spent refuse a fourth use")
	runtime.charge_rewarded_kill(["life_a","life_a","mana_a"])
	check(runtime.snapshot().charges_by_uid.life_a==1 and runtime.snapshot().charges_by_uid.mana_a==21,"One per equippedUID even if caller repeats a UID")
	check(runtime.snapshot().charges_by_uid.life_b==30,"UnequippedUID receives no charge")
	for unused:int in range(60):runtime.charge_rewarded_kill(["life_a"])
	check(runtime.snapshot().charges_by_uid.life_a==30,"Kill charge clamps at30")
	runtime.use("life_b",0.0,100.0)
	var state:=runtime.snapshot();state.charges_by_uid.life_b=1000
	check(runtime.snapshot().charges_by_uid.life_b==20,"Read snapshot cannot mutate runtime")
	var invalid:=runtime.snapshot();check(not runtime.sync_owned({"life_b":"flask:mana"}) and runtime.snapshot()==invalid,"Changing definition under sameUID is atomic rejection")
	check(runtime.sync_owned({"life_a":"flask:life","mana_a":"flask:mana"}),"Discard removes UID")
	check(runtime.snapshot().active_by_resource.has("health"),"Already consumed recovery remains frozen after discard")
	runtime.clear_effects();check(runtime.snapshot().active_by_resource.is_empty() and runtime.snapshot().charges_by_uid.life_a==30,"Death clears effects only")
	runtime.reset(own);check(runtime.snapshot().charges_by_uid.life_b==30,"Actual new battle reset refills")
	for invalid_resource:float in [NAN,INF,-1.0]:
		before=runtime.snapshot();check(not runtime.use("life_a",invalid_resource,100).ok and runtime.snapshot()==before,"Invalid resource rejects atomically")
	for index:int in range(1,121):
		var expected:String="flask:life" if index==60 else "flask:mana" if index==120 else ""
		check(Catalog.reward_definition(index)==expected,"Deterministic60root cadence without RNG")
func test_models()->void:
	var model:=Model.new();var original:=model.snapshot()
	check(original.version==18 and Rules.reason(original).is_empty(),"Fresh canonical schema18 is fully valid")
	check(model.flask_slots().size()==5 and model.owned_flasks().size()==2,"Two starter bottles and five real slots")
	check(model.flask_slots()[0].definition_id=="flask:life" and model.flask_slots()[1].definition_id=="flask:mana","Starter kinds match fixed first two slots")
	var life:String=model.flask_slots()[0].uid;var mana:String=model.flask_slots()[1].uid
	var definition:=model.item_definition(life)
	check(definition.size==Vector2i(1,2) and definition.resource=="health" and definition.icon_path.ends_with("life_flask.png"),"Definition exposes actual1x2 and icon contract")
	var path:="user://flask-model.json";check(model.save_build(path)==OK,"Isolated starter build saved")
	var empty:Dictionary=model.first_bag_position(life)
	check(not empty.is_empty(),"Real bag has1x2 space")
	check(model.move_item(life,empty,model.revision(),path).ok,"Starter flask moves into actual bag footprint")
	var occupied:=model.location(life);check(occupied==empty,"Exact authoritative bag coordinates")
	check(model.move_item(life,{"kind":"flask_slot","slot_id":"flask_2"},model.revision(),path).ok,"Flask swaps through common slot transaction")
	check(model.location(mana)==empty and model.location(life).slot_id=="flask_2","Displaced bottle keeps original bag position")
	var before:=model.snapshot()
	check(not model.move_item(life,{"kind":"equipment","slot_id":"weapon"},model.revision(),path).ok and model.snapshot()==before,"Flask cannot become equipment")
	var equipment_uid:String=model.equipped_items().weapon
	check(not model.move_item(equipment_uid,{"kind":"flask_slot","slot_id":"flask_1"},model.revision(),path).ok and model.snapshot()==before,"Equipment cannot become flask")
	check(not model.move_item(life,{"kind":"flask_slot","slot_id":"flask_6"},model.revision(),path).ok and model.snapshot()==before,"Sixth slot atomically rejected")
	var legacy:=original.duplicate(true);legacy.version=17
	for uid:String in model.owned_flasks():
		legacy.items.erase(uid);legacy.locations.erase(uid)
	check(Rules.reason_v17(legacy).is_empty(),"Frozen17 fixture without new types validates")
	check(not Rules.reason_v17(original).is_empty(),"Version18 source not accepted as17")
	var injected:=legacy.duplicate(true);injected.items[life]=original.items[life];injected.locations[life]={"kind":"bag","page":0,"x":0,"y":0}
	check(not Rules.reason_v17(injected).is_empty() and Rules.decode_v17(injected).is_empty(),"Flask injected under17 is rejected before migration")
	var migrated:=Migration.migrate_v17(legacy)
	check(not migrated.is_empty() and migrated.items.size()==legacy.items.size()+2,"Exactlytwo starters added in version migration")
	for uid:String in legacy.items:check(migrated.items[uid]==legacy.items[uid] and migrated.locations[uid]==legacy.locations[uid],"Every oldUID andlocation retained")
	for field:String in ["revision","next_item_serial","progress","talents","skill_groups","bindings","crafting","migration_ledger"]:check(migrated[field]==legacy[field],"Non-flask state unchanged: "+field)
	check(Migration.migrate_v17(migrated).is_empty(),"Already18 cannot be granted again")
	var reload:=Model.new();check(reload.load_build(path) and reload.snapshot()==model.snapshot(),"Current18 save reload preserves all exact instances and arrangement")
