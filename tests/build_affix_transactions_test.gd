extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Gear=preload("res://scripts/items/equipment_catalog.gd")
const Craft=preload("res://scripts/items/crafting_rules.gd")
const Items=preload("res://scripts/items/unified_item_catalog.gd")
class FaultModel extends Model:
	var fail_save:=false
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:return ERR_CANT_CREATE if fail_save else super._write_bytes(path,bytes)
var checks:=0
var failures:=0
var changes:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func source_for(operation:String)->Dictionary:
	var result:Dictionary={"id":"gear_000001","base_id":"nine_slot_etched_ring","rarity":"normal","item_level":16,"affixes":[]}
	if operation in ["elevate","augment"]:
		result.rarity="magic";result.affixes=[{"id":"attack_life_leech","tier":3,"value":60}]
	elif operation!="enchant":
		result.rarity="rare"
		for id:String in Gear.BuildAffixes.AFFIX_IDS:result.affixes.append({"id":id,"tier":3,"value":Gear.affix_definition(id).tiers[2].max})
	return result
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	for operation:String in Craft.operation_ids():
		var model:=FaultModel.new();var source:=source_for(operation);source.id="gear_%06d"%int(model.snapshot().next_item_serial)
		check(model._admit_reward_item(Items.wrap_equipment(source)),"Admit actual valid new affix payload")
		var economics:=Craft.operation_quote(source,operation);var cost:int=int(economics.cost.get(Craft.MATERIAL_ID,0));var credit:int=int(economics.materials.get(Craft.MATERIAL_ID,0))
		var candidate:=model.snapshot();check(model._set_bag_currency_balance(candidate,cost).ok,"Actual currency fixture")
		model._accept_memory(candidate);var path:="user://affix-"+operation+".json";check(model.save_build(path)==OK,"Coherent full save fixture")
		var before:=model.snapshot();var disk:=FileAccess.get_file_as_bytes(path);var location:=model.location(source.id)
		var metadata:=model.crafting_operations(source.id,path);check(metadata.size()==6 and model._craft_quotes.is_empty() and model.snapshot()==before,"Metadata remains lightweight, no quote or random output")
		var quote:=model.crafting_quote(operation,source.id,path)
		check(quote.ok and quote.cost==economics.cost and quote.rules_version==Craft.CURRENT_RULES_VERSION,"Current authoritative versioned quote")
		check(not quote.has("seed") and not quote.has("candidate") and not quote.has("instance"),"No future random result exposed")
		model.cancel_crafting_quote(quote.handle);check(not model.execute_crafting(quote.handle,source).ok and model.snapshot()==before,"Cancel leaves new families and money untouched")
		quote=model.crafting_quote(operation,source.id,path)
		var wrong:=source.duplicate(true);wrong.item_level=15
		check(not model.execute_crafting(quote.handle,wrong).ok and model.snapshot()==before,"Different selected source rejected")
		var seed_text:=JSON.stringify({"rules":Craft.seed_rules_version(operation),"revision":before.crafting.revision,"item":source},"",true,true)
		var expected:=Craft.operation_plan(source,operation,seed_text.sha256_text().substr(0,15).hex_to_int())
		model.fail_save=true;var saves:int=model.successful_saves;changes=0;model.changed.connect(func():changes+=1)
		check(not model.execute_crafting(quote.handle,source).ok and var_to_bytes(model.snapshot())==var_to_bytes(before) and FileAccess.get_file_as_bytes(path)==disk,"Failed write restores all authoritative bytes")
		check(changes==0 and model.successful_saves==saves,"No failure notification or save success")
		model.fail_save=false;seed(42127);var next:=randi();seed(42127)
		check(model.execute_crafting(quote.handle,source).ok and randi()==next,"Successful transaction uses private seed")
		check(changes==1 and model.successful_saves==saves+1 and model.crafting_balance()==credit,"One commit and exact unchanged economic debit/credit")
		var after:=model.snapshot()
		check(after.version==27 and after.crafting.revision==before.crafting.revision+1 and after.journey==before.journey,"Correct schema, one revision, formal journey unaffected")
		if operation=="salvage":check(model.item(source.id).is_empty(),"Salvage consumes same UID")
		else:
			check(model.item(source.id).payload==expected.instance and model.location(source.id)==location,"Real seeded current-pool output exact, stable UID/base/cells")
			if operation in ["elevate","augment"]:check(model.item(source.id).payload.affixes[0]==source.affixes[0],"Existing leech roll retained")
		for uid:String in before.items:
			if uid==source.id or before.items[uid].kind=="currency":continue
			check(after.items[uid]==before.items[uid] and after.locations[uid]==before.locations[uid],"Unrelated UID remains unchanged")
		check(not model.execute_crafting(quote.handle,source).ok and model.snapshot()==after,"Repeated confirm cannot consume twice")
		var loaded:=Model.new();check(loaded.load_build(path) and loaded.snapshot()==after,"New four-family schema27 roundtrip")
	# Declared selected-vocabulary APIs cannot launder new families into old plans.
	for op:String in Craft.operation_ids():
		check(not Craft.operation_quote(source_for("reforge"),op,26).ok,"Old explicit vocabulary rejects new payload before planning")
	print("Build affix transactions: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
