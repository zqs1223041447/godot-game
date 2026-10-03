extends SceneTree
const Model=preload("res://scripts/canonical_game_state.gd")
const Craft=preload("res://scripts/items/crafting_rules.gd")
const Items=preload("res://scripts/items/unified_item_catalog.gd")
var checks:=0
var failures:=0
func _initialize()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var state:=Model.new()
	var path:="user://craft-operations-%d.json"%Time.get_ticks_usec()
	for invalid:Variant in [null,"",false,17,"missing"]:
		var entries:=state.crafting_operations(invalid,path)
		check(entries.size()==6,"Every invalid selection retains six operations")
		for entry:Dictionary in entries:check(not entry.available and not entry.reason.is_empty(),"Invalid selection disabled with explanation")
	var uid:="gear_000001"
	var normal:Dictionary={"id":uid,"base_id":"cinder_reed","rarity":"normal","item_level":30,"affixes":[]}
	check(state._admit_reward_item(Items.wrap_equipment(normal)),"Normal legal gear admitted")
	var candidate:=state.snapshot()
	check(state._set_bag_currency_balance(candidate,200).ok,"Fund isolated transaction fixture using real shard items")
	state._accept_memory(candidate)
	check(state.save_build(path)==OK,"Coherent schema18 fixture saved")
	var before:=var_to_bytes(state.snapshot())
	var saves:=state.save_attempts
	var sequence:=state._craft_sequence
	seed(813)
	var expected_rng:=randi()
	seed(813)
	var entries:=state.crafting_operations(uid,path)
	check(randi()==expected_rng,"Metadata consumes no global RNG")
	check(var_to_bytes(state.snapshot())==before and state._craft_sequence==sequence and state._craft_quotes.is_empty() and saves==state.save_attempts,"Metadata creates no handle, state or disk write")
	for entry:Dictionary in entries:
		check(entry.has_all(["operation","label","description","risk","cost","materials","available","reason"]),"Stable metadata fields")
		check(entry.available==(entry.operation=="enchant"),"Only enchant accepts white gear")
		if entry.operation=="enchant":check(entry.cost=={Craft.MATERIAL_ID:8} and entry.materials.is_empty(),"Metadata derives exact enchant fee")
	entries[2].cost[Craft.MATERIAL_ID]=0
	check(state.crafting_operations(uid,path)[2].cost[Craft.MATERIAL_ID]==8,"Metadata is detached")
	for operation:String in ["enchant","elevate","reforge"]:
		var source:Dictionary=state.item(uid).payload
		var quote:=state.crafting_quote(operation,uid,path)
		check(quote.ok and not quote.has("seed") and not quote.has("instance"),"Only authoritative economics exposed: "+operation)
		var result:=state.execute_crafting(quote.handle,source)
		check(result.ok,"Real canonical transaction: "+operation)
		check(state.item(uid).payload.id==uid and state.item(uid).payload.base_id==normal.base_id and state.item(uid).payload.item_level==30,"Identity/base/ilvl preserved")
		check(not state.execute_crafting(quote.handle,source).ok,"Duplicate confirmation rejected")
	var one:Dictionary={"id":"gear_000002","base_id":"cinder_reed","rarity":"magic","item_level":30,"affixes":[{"id":"deepwell","tier":1,"value":5}]}
	check(state._admit_reward_item(Items.wrap_equipment(one)),"One affix fixture admitted")
	check(state.save_build(path)==OK,"Save one-affix fixture")
	var add:=state.crafting_quote("augment",one.id,path)
	check(add.ok,"Augment quote reachable")
	if add.ok:
		check(state.execute_crafting(add.handle,one).ok,"Augment real transaction")
		check(state.item(one.id).payload.affixes.size()==2 and state.item(one.id).payload.affixes[0]==one.affixes[0],"Augment retains original and adds exactly one")
	var reopened:=Model.new()
	check(reopened.load_build(path) and reopened.snapshot()==state.snapshot(),"All new results reopen unchanged under schema18")
	check(state.snapshot().version==18 and state.snapshot().crafting.keys()==["revision"],"No schema or second wallet added")
	print("Crafting operations: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
