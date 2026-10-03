extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Craft=preload("res://scripts/items/crafting_rules.gd")
const Items=preload("res://scripts/items/unified_item_catalog.gd")
const Rules=preload("res://scripts/save/canonical_build_rules.gd")
const Flasks=preload("res://scripts/combat/flask_runtime.gd")
class FaultModel extends Model:
	var fail_save:=false
	func _write_bytes(path:String,bytes:PackedByteArray)->Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path,bytes)
var checks:=0
var failures:=0
var changes:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func normal(uid:String)->Dictionary:return {"id":uid,"base_id":"ashwood_bow","rarity":"normal","item_level":30,"affixes":[]}
func source_for(op:String)->Dictionary:
	var item:=normal("gear_000001")
	if op!="enchant":item={"id":item.id,"base_id":item.base_id,"rarity":"magic","item_level":30,"affixes":[{"id":"whetstone_edge","tier":1,"value":1}]}
	return item
func fixture(source:Dictionary,cost:int,path:String)->FaultModel:
	var state:=FaultModel.new()
	check(state._admit_reward_item(Items.wrap_equipment(source)),"Admit legal craft source")
	check(state._admit_reward_item(Items.calibration_shard("shards_a",1)),"First actual shard stack")
	check(state._admit_reward_item(Items.calibration_shard("shards_b",cost-1)),"Second actual shard stack")
	check(state.save_build(path)==OK,"Save coherent fixture")
	return state
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	for operation:String in ["enchant","elevate","augment","reforge"]:
		var source:=source_for(operation)
		var cost:=int(Craft.operation_quote(source,operation).cost[Craft.MATERIAL_ID])
		var path:="user://growth-%s-%d.json"%[operation,Time.get_ticks_usec()]
		var state:=fixture(source,cost,path)
		var before:=state.snapshot();var disk:=FileAccess.get_file_as_bytes(path)
		var old_position:=state.location(source.id)
		var quote:=state.crafting_quote(operation,source.id,path)
		check(quote.ok and quote.cost[Craft.MATERIAL_ID]==cost,"Authoritative exact fee "+operation)
		check(not quote.has("seed") and not quote.has("instance") and not quote.has("candidate"),"Quote hides random result")
		state.cancel_crafting_quote(quote.handle)
		check(not state.execute_crafting(quote.handle,source).ok and state.snapshot()==before,"Cancel prevents consumption")
		quote=state.crafting_quote(operation,source.id,path)
		var mismatched:=source.duplicate(true);mismatched.item_level=1
		check(not state.execute_crafting(quote.handle,mismatched).ok and state.snapshot()==before,"Wrong selection source rejected")
		var seed_text:=JSON.stringify({"rules":Craft.seed_rules_version(operation),"revision":before.crafting.revision,"item":source},"",true,true)
		var expected:=Craft.operation_plan(source,operation,seed_text.sha256_text().substr(0,15).hex_to_int())
		var save_count:=state.successful_saves
		changes=0;state.changed.connect(func():changes+=1)
		state.fail_save=true
		var failed:=state.execute_crafting(quote.handle,source)
		check(not failed.ok and state.snapshot()==before and FileAccess.get_file_as_bytes(path)==disk,"Failed atomic write preserves all bytes/items/currency/revision")
		check(changes==0 and state.successful_saves==save_count,"Failed write emits no changed or successful save")
		state.fail_save=false
		seed(91927);var next:=randi();seed(91927)
		var result:=state.execute_crafting(quote.handle,source)
		check(result.ok and randi()==next,"Retry uses isolated seed without global RNG")
		check(state.item(source.id).payload==expected.instance and state.location(source.id)==old_position,"Same seed candidate and same actual page/cells")
		check(changes==1 and state.successful_saves==save_count+1,"Exactly one successful save and notification")
		check(state.crafting_balance()==0 and state.item("shards_a").is_empty() and state.item("shards_b").is_empty(),"Exact debit spans actual stacks and erases zero stacks")
		var after:=state.snapshot()
		for uid:String in before.items:
			if uid in [source.id,"shards_a","shards_b"]:continue
			check(after.items[uid]==before.items[uid] and after.locations[uid]==before.locations[uid],"Other UID/payload/location preserved: "+uid)
		check(after.next_item_serial==before.next_item_serial and after.crafting.revision==before.crafting.revision+1 and after.version==18,"No new UID or schema; crafting revision once")
		check(not state.execute_crafting(quote.handle,source).ok and state.snapshot()==after,"Repeated confirmation cannot pay twice")
		var restored:=Model.new();check(restored.load_build(path) and restored.snapshot()==after,"Full schema18 roundtrip")
		var fresh:=fixture(source,cost,"user://stale-"+operation+".json")
		var q:=fresh.crafting_quote(operation,source.id,"user://stale-"+operation+".json")
		fresh.add_xp(1);var current:=fresh.snapshot()
		check(not fresh.execute_crafting(q.handle,source).ok and fresh.snapshot()==current,"Any intervening build change invalidates quote")
		var external_path:="user://external-"+operation+".json"
		var external:=fixture(source,cost,external_path)
		q=external.crafting_quote(operation,source.id,external_path)
		var file:=FileAccess.open(external_path,FileAccess.WRITE);file.store_string(JSON.stringify(external.snapshot(),"  "));file.close()
		var altered:=FileAccess.get_file_as_bytes(external_path);current=external.snapshot()
		check(not external.execute_crafting(q.handle,source).ok and external.snapshot()==current and FileAccess.get_file_as_bytes(external_path)==altered,"External re-encoding blocks all writes")
		check(not external.crafting_operations(source.id,external_path)[2].available,"Known save protection reflected by metadata")
		var loaded:=fixture(source,cost,"user://load-"+operation+".json")
		q=loaded.crafting_quote(operation,source.id,"user://load-"+operation+".json")
		check(loaded.load_build("user://load-"+operation+".json") and not loaded.execute_crafting(q.handle,source).ok,"Reload clears issued authority")
	var invalid:=Model.new();var s:=normal("gear_000001");check(invalid._admit_reward_item(Items.wrap_equipment(s)),"Invalid-candidate control source admitted")
	var bad:=invalid.snapshot();bad.items[bad.items.keys()[0]].payload={"forged":true};invalid._accept_memory(bad)
	check(not invalid.crafting_quote("enchant",s.id,"user://bad.json").ok,"Full candidate validation rejects unrelated malformed owned payload")
	print("Crafting growth transactions: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
