extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Purchase = preload("res://scripts/items/equipment_purchase.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const PATH := "user://build_save.json"
var CONTEXT := PackedByteArray([1,2,3])
class FaultModel extends Model:
	var fail_writes := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_writes else super._write_bytes(path,bytes)
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func observed(model: Model) -> Array:
	return [var_to_bytes(model.snapshot()),FileAccess.get_file_as_bytes(PATH),model.successful_saves]
func fixture(balance: int = 1000, full: bool = false) -> FaultModel:
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
		# A single stack can free only one cell; large gear still cannot fit.
		var first: String = candidate.locations.keys().filter(func(uid: String) -> bool: return candidate.locations[uid].kind=="bag")[0]
		candidate.items[first] = Model.Items.calibration_shard(first,balance)
	else: check(model._set_bag_currency_balance(candidate,balance).ok,"Fixture physical currency fits")
	candidate.revision += 1
	check(model._commit(candidate,PATH).ok,"Fixture commits through authoritative validator")
	return model
func rejected(model: Model, call: Callable, label: String) -> void:
	var before := observed(model)
	var result: Dictionary = call.call()
	check(not result.ok and observed(model)==before,label)
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"): quit(78); return
	var model := fixture()
	var service := Purchase.new()
	var before := observed(model)
	var rows := service.offers(model,PATH)
	check(rows.size()==Purchase.Gear.all_base_ids().size() and observed(model)==before,"All existing bases offered without mutation")
	for row: Dictionary in rows:
		var quote := service.quote(model,row.base_id,model.revision(),PATH,CONTEXT)
		check(quote.ok and quote.cost.calibration_shard==8 and quote.item_level==1,"Catalog base has fixed paid level-one quote")
		if not quote.ok: continue
		var balance := model.crafting_balance()
		var saves: int = model.successful_saves
		var result := service.execute(model,quote.handle,row.base_id,CONTEXT)
		check(result.ok and model.crafting_balance()==balance-8 and model.successful_saves==saves+1,"One purchase commits exact debit and one item")
		if not result.ok: continue
		var owned: Dictionary = model.item(result.uid)
		check(owned.payload.base_id==row.base_id and owned.payload.rarity=="normal" and owned.payload.item_level==1 and owned.payload.affixes.is_empty(),"Original catalog normal base, no RNG or hidden affixes")
		check(model.location(result.uid).kind=="bag" and Craft.operation_quote(owned.payload,"enchant").ok,"Purchased base enters actual bag and existing crafting eligibility")
		rejected(model,func(): return service.execute(model,quote.handle,row.base_id,CONTEXT),"No replay minting")
	var base_id: String = rows[0].base_id
	for value: Variant in [null,true,1,1.0,&"forgeblade","missing","equipment:forgeblade",{},[]]:
		rejected(model,func(): return service.quote(model,value,model.revision(),PATH,CONTEXT),"Strict catalog target rejects malformed or prefixed input")
	rejected(model,func(): return service.quote(model,base_id,float(model.revision()),PATH,CONTEXT),"Float revision rejected")
	rejected(model,func(): return service.quote(model,base_id,model.revision(),"user://town_test_build_save.json",CONTEXT),"Test path cannot buy paid normal gear")
	var quote := service.quote(model,base_id,model.revision(),PATH,CONTEXT)
	var forged := quote.duplicate(true); forged.cost.calibration_shard=0; forged.item_level=100
	before=observed(model)
	check(not service.execute(model,forged,base_id,CONTEXT).ok and observed(model)==before,"Only issued opaque handle executes, not client-edited quote")
	rejected(model,func(): return service.execute(model,quote.handle,"missing",CONTEXT),"Target substitution consumes quote without debit")
	quote=service.quote(model,base_id,model.revision(),PATH,CONTEXT)
	rejected(model,func(): return service.execute(model,quote.handle,base_id,PackedByteArray([4])),"Changed world context rejects")
	quote=service.quote(model,base_id,model.revision(),PATH,CONTEXT); service.cancel(quote.handle)
	rejected(model,func(): return service.execute(model,quote.handle,base_id,CONTEXT),"Cancelled confirmation cannot execute")
	quote=service.quote(model,base_id,model.revision(),PATH,CONTEXT)
	var candidate:=model.snapshot();candidate.revision+=1;check(model._commit(candidate,PATH).ok,"Advance inventory revision fixture")
	rejected(model,func(): return service.execute(model,quote.handle,base_id,CONTEXT),"Stale snapshot rejects")
	quote=service.quote(model,base_id,model.revision(),PATH,CONTEXT)
	var original:=FileAccess.get_file_as_bytes(PATH)
	var file:=FileAccess.open(PATH,FileAccess.WRITE);file.store_buffer(original);file.store_string(" ");file.close()
	rejected(model,func(): return service.execute(model,quote.handle,base_id,CONTEXT),"External disk edit rejects byte-for-byte")
	file=FileAccess.open(PATH,FileAccess.WRITE);file.store_buffer(original);file.close()
	quote=service.quote(model,base_id,model.revision(),PATH,CONTEXT);model.fail_writes=true
	rejected(model,func(): return service.execute(model,quote.handle,base_id,CONTEXT),"Write failure rolls back item, serial and physical money")
	model.fail_writes=false
	quote=service.quote(model,base_id,model.revision(),PATH,CONTEXT)
	check(service.execute(model,quote.handle,base_id,CONTEXT).ok,"Fresh quote retries after write failure")
	var first_handle := ""
	for ordinal: int in range(9):
		quote=service.quote(model,base_id,model.revision(),PATH,CONTEXT)
		if ordinal==0:first_handle=quote.handle
	check(service._quotes.size()==8,"Unconfirmed quotes are bounded to eight")
	rejected(model,func(): return service.execute(model,first_handle,base_id,CONTEXT),"Oldest evicted handle cannot execute")
	var other:=Model.new();check(other.load_build(PATH),"Second live model loads exact same file")
	rejected(model,func(): return service.execute(other,quote.handle,base_id,CONTEXT),"Same path and bytes on another model do not adopt quote")
	quote=service.quote(model,base_id,model.revision(),PATH,CONTEXT)
	var nested: Array[Dictionary]=[]
	var reenter := func() -> void: nested.append(service.quote(model,base_id,model.revision(),PATH,CONTEXT))
	model.changed.connect(reenter)
	check(service.execute(model,quote.handle,base_id,CONTEXT).ok and nested.size()==1 and not nested[0].ok and nested[0].code=="busy","Changed-signal reentry cannot quote a second purchase during commit")
	model.changed.disconnect(reenter)
	var serial_candidate:=model.snapshot();serial_candidate.next_item_serial=Purchase.Rules.MAX_SERIAL;serial_candidate.revision+=1
	check(model._commit(serial_candidate,PATH).ok,"Terminal serial fixture remains schema-valid")
	rejected(model,func(): return service.quote(model,base_id,model.revision(),PATH,CONTEXT),"Terminal UID sequence cannot charge money")
	model=fixture(7)
	rejected(model,func(): return service.quote(model,base_id,model.revision(),PATH,CONTEXT),"Insufficient real shards rejects")
	model=fixture(8,true)
	var large_base := ""
	for row: Dictionary in service.offers(model,PATH):
		var size: Vector2i = row.size
		if size.x*size.y>1: large_base=row.base_id;check(not row.available,"One freed currency cell cannot promise large gear");break
	check(not large_base.is_empty(),"Real catalog includes non-one-cell equipment")
	rejected(model,func(): return service.quote(model,large_base,model.revision(),PATH,CONTEXT),"Full fragmented bag remains intact after tentative debit")
	# Free the rest of an actual weapon footprint; exact debit removes stack first.
	var candidate2:=model.snapshot()
	for uid: String in candidate2.locations.keys():
		if candidate2.locations[uid].kind=="bag" and candidate2.locations[uid].page==0 and candidate2.locations[uid].x<4 and candidate2.locations[uid].y<4 and candidate2.items[uid].kind!="currency":candidate2.items.erase(uid);candidate2.locations.erase(uid)
	candidate2.revision+=1;check(model._commit(candidate2,PATH).ok,"Make actual rectangular bag space")
	quote=service.quote(model,large_base,model.revision(),PATH,CONTEXT)
	check(quote.ok and service.execute(model,quote.handle,large_base,CONTEXT).ok and model.crafting_balance()==0,"Exact debit and freed cells place gear together")
	var reload:=Model.new();check(reload.load_build(PATH) and reload.snapshot()==model.snapshot(),"Current schema reload preserves purchase exactly")
	print("Equipment purchase transactions: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
