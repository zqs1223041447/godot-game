extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Purchase = preload("res://scripts/items/jewel_purchase.gd")
const Equipment = preload("res://scripts/items/equipment_purchase.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const PATH := "user://build_save.json"
var CONTEXT := PackedByteArray([3,2,1])
class FaultModel extends Model:
	var fail_writes := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_writes else super._write_bytes(path,bytes)
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func observe(model: Model) -> Array:
	return [model.snapshot(), FileAccess.get_file_as_bytes(PATH), model.successful_saves]
func fixture(balance: int = 100, full: bool = false) -> FaultModel:
	if FileAccess.file_exists(PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var model := FaultModel.new()
	var candidate := model.snapshot()
	for uid: String in candidate.locations.keys():
		if candidate.locations[uid].kind in ["bag","recovery"]: candidate.locations.erase(uid); candidate.items.erase(uid)
	if full:
		for page: int in range(Locations.CURRENT_BAG_PAGES):
			for y: int in range(Locations.CURRENT_BAG_ROWS):
				for x: int in range(Locations.CURRENT_BAG_COLUMNS):
					var uid := "item_%06d" % int(candidate.next_item_serial)
					candidate.next_item_serial += 1
					candidate.items[uid] = Gems.create_instance(uid,"support:efficiency")
					candidate.locations[uid] = {"kind":"bag","page":page,"x":x,"y":y}
		var first: String = candidate.locations.keys().filter(func(uid: String) -> bool: return candidate.locations[uid].kind=="bag")[0]
		candidate.items[first] = Model.Items.calibration_shard(first,balance)
	else: check(model._set_bag_currency_balance(candidate,balance).ok,"Explicit physical currency fixture fits")
	candidate.revision += 1
	check(model._commit(candidate,PATH).ok,"Fixture is fully canonical and saved")
	return model
func reject(model: Model, call: Callable, label: String) -> void:
	var before := observe(model)
	check(not call.call().ok and observe(model)==before,label)
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"): quit(78); return
	var model := fixture()
	var service := Purchase.new()
	var before := observe(model)
	var rows := service.offers(model,PATH)
	check(rows.size()==3 and observe(model)==before,"Only three implemented ordinary templates offered without mutation")
	for row: Dictionary in rows:
		var expected := Purchase.Town.make_item({"supply_kind":"jewel","catalog_id":row.base_id},int(model.snapshot().next_item_serial))
		var quote := service.quote(model,row.base_id,model.revision(),PATH,CONTEXT)
		check(quote.ok and quote.cost.calibration_shard==Purchase.JewelCraft.REFORGE_COSTS.magic and not quote.has("item_level"),"Quote derives existing magic reforge price without invented item level")
		var result := service.execute(model,quote.handle,row.base_id,CONTEXT)
		check(result.ok and model.item(result.uid)==expected and model.snapshot().locations[result.uid].kind=="bag","Exact existing minimum magic sample purchased and placed: "+row.base_id)
		check(model.item(result.uid).payload.affixes.size()==2 and Purchase.Jewels.allocation_rule(model.item(result.uid).payload).is_empty(),"Ordinary purchase adds no special allocation rule")
		check(Purchase.JewelCraft.operation_quote(model.item(result.uid).payload,"salvage").materials.calibration_shard==1,"Existing salvage returns one, below eight-price")
		var restored := Model.new()
		check(restored.load_build(PATH) and restored.snapshot()==model.snapshot(),"Exact purchased jewel survives current-schema reload")
		reject(model,func():return service.execute(model,quote.handle,row.base_id,CONTEXT),"Used quote cannot replay")
	for invalid: Variant in ["branchfinder","unknown",1,null,[]]:
		reject(model,func():return service.quote(model,invalid,model.revision(),PATH,CONTEXT),"Special/unknown/typed targets reject")
	check(Purchase.make_jewel("emberheart",0).is_empty() and Purchase.make_jewel("emberheart",Model.Rules.MAX_SERIAL).is_empty(),"Serial bounds remain authoritative")
	reject(model,func():return service.quote(model,"emberheart",float(model.revision()),PATH,CONTEXT),"Float revision rejects")
	reject(model,func():return service.quote(model,"emberheart",model.revision(),"user://town_test_build_save.json",CONTEXT),"Test profile path rejects")
	var quote := service.quote(model,"emberheart",model.revision(),PATH,CONTEXT)
	service.cancel(quote.handle)
	reject(model,func():return service.execute(model,quote.handle,"emberheart",CONTEXT),"Explicit cancel invalidates quote")
	quote = service.quote(model,"emberheart",model.revision(),PATH,CONTEXT)
	reject(model,func():return service.execute(model,quote.handle,"tideglass",CONTEXT),"Quote target cannot change")
	quote = service.quote(model,"emberheart",model.revision(),PATH,CONTEXT)
	reject(model,func():return service.execute(model,quote.handle,"emberheart",PackedByteArray([9])),"World context cannot change")
	quote = service.quote(model,"emberheart",model.revision(),PATH,CONTEXT)
	reject(model,func():return Equipment.new().execute(model,quote.handle,"emberheart",CONTEXT),"Jewel handle cannot execute in equipment service")
	var oldest := service.quote(model,"emberheart",model.revision(),PATH,CONTEXT)
	for unused: int in range(8): service.quote(model,"emberheart",model.revision(),PATH,CONTEXT)
	reject(model,func():return service.execute(model,oldest.handle,"emberheart",CONTEXT),"Ninth quote evicts oldest")
	quote = service.quote(model,"emberheart",model.revision(),PATH,CONTEXT)
	check(model.allocate_passive("2151",0,model.revision(),PATH).ok,"Real inventory-independent allocation changes snapshot")
	reject(model,func():return service.execute(model,quote.handle,"emberheart",CONTEXT),"Changed model rejects old quote")
	quote = service.quote(model,"emberheart",model.revision(),PATH,CONTEXT)
	var disk := FileAccess.get_file_as_bytes(PATH)
	var output := FileAccess.open(PATH,FileAccess.WRITE); output.store_buffer(disk); output.store_string(" "); output.close()
	reject(model,func():return service.execute(model,quote.handle,"emberheart",CONTEXT),"External disk change rejects without debit")
	model = fixture(8)
	quote = service.quote(model,"emberheart",model.revision(),PATH,CONTEXT)
	model.fail_writes = true
	reject(model,func():return service.execute(model,quote.handle,"emberheart",CONTEXT),"Failed save keeps item, currency and serial unchanged")
	model.fail_writes = false
	quote = service.quote(model,"emberheart",model.revision(),PATH,CONTEXT)
	quote.cost.calibration_shard = 0
	check(service.execute(model,quote.handle,"emberheart",CONTEXT).ok and model.crafting_balance()==0,"Fresh retry charges authority price despite mutable displayed quote")
	model = fixture(7)
	reject(model,func():return service.quote(model,"emberheart",model.revision(),PATH,CONTEXT),"Insufficient physical shards reject")
	model = fixture(16,true)
	reject(model,func():return service.quote(model,"emberheart",model.revision(),PATH,CONTEXT),"Full bag with remaining currency stack rejects")
	model = fixture(8,true)
	quote = service.quote(model,"emberheart",model.revision(),PATH,CONTEXT)
	check(quote.ok and service.execute(model,quote.handle,"emberheart",CONTEXT).ok and model.crafting_balance()==0,"Exact debit frees one cell for real one-cell jewel")
	var report := {"checks":checks,"failures":failures.size(),"failed_labels":failures}
	var target := OS.get_environment("JEWEL_TRANSACTION_REPORT")
	if not target.is_empty():
		output = FileAccess.open(target,FileAccess.WRITE); output.store_string(JSON.stringify(report,"\t")+"\n"); output.close()
	print("JEWEL_PURCHASE_TRANSACTIONS "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
