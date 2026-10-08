extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Purchase = preload("res://scripts/items/flask_purchase.gd")
const Equipment = preload("res://scripts/items/equipment_purchase.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const PATH := "user://build_save.json"
var context := PackedByteArray([5,8,1])
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
	return [var_to_bytes(model.snapshot()),FileAccess.get_file_as_bytes(PATH),model.successful_saves]
func fixture(balance: int = 40, full: bool = false) -> FaultModel:
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
		var first: String = candidate.locations.keys().filter(func(uid: String):return candidate.locations[uid].kind=="bag")[0]
		candidate.items[first] = Model.Items.calibration_shard(first,balance)
	else: check(model._set_bag_currency_balance(candidate,balance).ok,"Explicit physical currency fixture fits")
	candidate.revision += 1
	check(model._commit(candidate,PATH).ok,"Fixture is canonical and saved")
	return model
func reject(model: Model, call: Callable, label: String) -> void:
	var before := observe(model)
	check(not call.call().ok and observe(model)==before,label)
func free_cell(model: Model, x: int, y: int) -> void:
	var candidate := model.snapshot()
	for uid: String in candidate.locations.keys():
		if candidate.locations[uid]=={"kind":"bag","page":0,"x":x,"y":y}:
			candidate.items.erase(uid);candidate.locations.erase(uid)
	candidate.revision += 1
	check(model._commit(candidate,PATH).ok,"Controlled cell release saves a valid fixture")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-flask-purchase."): quit(78); return
	var model := fixture()
	var service := Purchase.new()
	var before := observe(model)
	var rows := service.offers(model,PATH)
	check(rows.size()==2 and rows.all(func(row: Dictionary):return row.definition_id in ["flask:life","flask:mana"] and row.cost==8 and row.purchase_kind=="flask" and row.size==Vector2i(1,2)) and observe(model)==before,"Only two existing1x2bottles offered at eight with no mutation")
	for row: Dictionary in rows:
		var prior := model.snapshot()
		var expected := Purchase.Flasks.create_instance("item_%06d" % int(prior.next_item_serial),row.definition_id)
		var quote := service.quote(model,row.definition_id,model.revision(),PATH,context)
		check(quote.ok and quote.cost.calibration_shard==8 and not quote.has("item_level"),"Flask quote uses purchase price, not use-charge or equipment level")
		var saves := model.successful_saves
		var balance := model.crafting_balance()
		var result := service.execute(model,quote.handle,row.definition_id,context)
		check(result.ok and model.item(result.uid)==expected and model.location(result.uid).kind=="bag","Exact existing bottle enters bag: "+row.definition_id)
		check(model.crafting_balance()==balance-8 and model.successful_saves==saves+1 and model.snapshot().next_item_serial==prior.next_item_serial+1,"Eight physical shards, one UID and one save commit together")
		check(model.snapshot().version==55 and model.snapshot().journey==prior.journey and model.item(result.uid).payload.is_empty(),"Schema55, gift/reward counters and empty bottle payload stay unchanged")
		reject(model,func():return model.crafting_quote("salvage",result.uid,PATH),"Flask cannot generate an equipment/jewel salvage credit")
		reject(model,func():return model.gem_trade_quote("recycle",result.uid,model.revision(),PATH),"Flask cannot generate a gem recycling credit")
		var restored := Model.new()
		check(restored.load_build(PATH) and restored.snapshot()==model.snapshot(),"Paid bottle survives exact current-schema reload")
		reject(model,func():return service.execute(model,quote.handle,row.definition_id,context),"Used quote cannot mint a duplicate bottle")
	for invalid: Variant in ["flask:unknown","life","base:forgeblade",&"flask:life",true,1,null,{}]:
		reject(model,func():return service.quote(model,invalid,model.revision(),PATH,context),"Unknown or mistyped bottle target rejects")
	check(Purchase.make_flask("flask:life",0).is_empty() and Purchase.make_flask("flask:mana",Model.Rules.MAX_SERIAL).is_empty(),"Bottle UID serial bounds are authoritative")
	reject(model,func():return service.quote(model,"flask:life",float(model.revision()),PATH,context),"Float revision rejects")
	reject(model,func():return service.quote(model,"flask:life",model.revision(),"user://town_test_build_save.json",context),"Test profile path cannot buy normal bottles")
	var quote := service.quote(model,"flask:life",model.revision(),PATH,context)
	service.cancel(quote.handle)
	reject(model,func():return service.execute(model,quote.handle,"flask:life",context),"Cancelled bottle quote is single-use")
	quote = service.quote(model,"flask:life",model.revision(),PATH,context)
	reject(model,func():return service.execute(model,quote.handle,"flask:mana",context),"Life quote cannot substitute mana")
	quote = service.quote(model,"flask:life",model.revision(),PATH,context)
	reject(model,func():return service.execute(model,quote.handle,"flask:life",PackedByteArray([9])),"Changed world context rejects")
	quote = service.quote(model,"flask:life",model.revision(),PATH,context)
	reject(model,func():return Equipment.new().execute(model,quote.handle,"flask:life",context),"Bottle handle cannot execute in equipment service")
	var other := Model.new()
	check(other.load_build(PATH),"Another model reads same normal file")
	reject(model,func():return service.execute(other,quote.handle,"flask:life",context),"Same disk on another model cannot adopt bottle quote")
	quote = service.quote(model,"flask:life",model.revision(),PATH,context)
	check(model.allocate_passive("2151",0,model.revision(),PATH).ok,"Existing allocation changes model revision")
	reject(model,func():return service.execute(model,quote.handle,"flask:life",context),"Stale build quote retains bottle and currency")
	quote = service.quote(model,"flask:life",model.revision(),PATH,context)
	var bytes := FileAccess.get_file_as_bytes(PATH)
	var output := FileAccess.open(PATH,FileAccess.WRITE);output.store_buffer(bytes);output.store_string(" ");output.close()
	reject(model,func():return service.execute(model,quote.handle,"flask:life",context),"External disk byte change rejects without debit")
	model = fixture(8)
	quote = service.quote(model,"flask:mana",model.revision(),PATH,context)
	model.fail_writes = true
	reject(model,func():return service.execute(model,quote.handle,"flask:mana",context),"Failed write retains exact inventory, physical currency and serial")
	model.fail_writes = false
	reject(model,func():return service.execute(model,quote.handle,"flask:mana",context),"Failed-write quote cannot replay")
	quote = service.quote(model,"flask:mana",model.revision(),PATH,context)
	quote.cost.calibration_shard = 0
	var result := service.execute(model,quote.handle,"flask:mana",context)
	check(result.ok and model.crafting_balance()==0,"Fresh retry debits eight despite changed displayed price")
	before = observe(model)
	check(model.discard_item(result.uid,model.revision(),PATH).ok and model.crafting_balance()==0,"Existing bottle discard grants no refund or arbitrage currency")
	model = fixture(7)
	reject(model,func():return service.quote(model,"flask:life",model.revision(),PATH,context),"Insufficient physical shards reject")
	model = fixture(8,true)
	reject(model,func():return service.quote(model,"flask:life",model.revision(),PATH,context),"One freed currency cell cannot fit a1x2bottle; debit rolls back")
	free_cell(model,1,0)
	reject(model,func():return service.quote(model,"flask:life",model.revision(),PATH,context),"Two horizontal free cells cannot fit a vertical bottle")
	model = fixture(16,true)
	free_cell(model,0,1)
	reject(model,func():return service.quote(model,"flask:mana",model.revision(),PATH,context),"Remaining currency occupies top cell; tentative eight debit rolls back")
	model = fixture(8,true)
	free_cell(model,0,1)
	quote = service.quote(model,"flask:mana",model.revision(),PATH,context)
	result = service.execute(model,quote.handle,"flask:mana",context)
	check(quote.ok and result.ok and model.crafting_balance()==0 and model.location(result.uid)=={"kind":"bag","page":0,"x":0,"y":0},"Exact debit releases stack into a true vertical1x2footprint atomically")
	var report := {"checks":checks,"failures":failures.size(),"failed_labels":failures,"save_version":model.snapshot().version}
	var target := OS.get_environment("FLASK_TRANSACTION_REPORT")
	if not target.is_empty():
		output = FileAccess.open(target,FileAccess.WRITE);output.store_string(JSON.stringify(report,"\t")+"\n");output.close()
	print("FLASK_PURCHASE_TRANSACTIONS "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
