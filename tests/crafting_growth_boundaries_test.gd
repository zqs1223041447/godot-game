extends SceneTree
const Craft=preload("res://scripts/items/crafting_rules.gd")
const Expand=preload("res://scripts/items/crafting_expansion_rules.gd")
const Model=preload("res://scripts/canonical_game_state.gd")
const Gear=preload("res://scripts/items/equipment_catalog.gd")
const Items=preload("res://scripts/items/unified_item_catalog.gd")
var checks:=0
var failures:=0
func _initialize()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var normal:Dictionary={"id":"gear_000001","base_id":"cinder_reed","item_level":30,"rarity":"normal","affixes":[]}
	for seed_value:Variant in [null,true,0.0,"0",[],{}]:
		var rejected:=Craft.operation_plan(normal,"enchant",seed_value)
		check(not rejected.ok and rejected.code=="invalid_seed" and rejected.instance.is_empty(),"Seed must be exact int with no partial result")
	for operation:Variant in [null,true,0,[],{},"unknown",&"enchant"]:
		check(not Craft.operation_quote(normal,operation).ok,"Malformed operation refused")
	var magic:Dictionary=Craft.operation_plan(normal,"enchant",1).instance
	for malformed:Dictionary in [magic.merged({"unexpected":1},true),magic.merged({"id":"other"},true),magic.merged({"item_level":31},true),magic.merged({"affixes":[{"id":"unknown","tier":1,"value":1}]},true)]:
		check(not Craft.operation_quote(malformed,"reforge").ok,"Full item validation remains the gate")
	var pool:Array[Dictionary]=[{"group":"shared","kind":"prefix"},{"group":"shared","kind":"suffix"}]
	check(not Expand._can_complete(pool,{"prefix":0,"suffix":0},{"max_prefixes":1,"max_suffixes":1},2),"Cross-kind shared group cannot count twice")
	pool.append({"group":"second","kind":"suffix"})
	check(Expand._can_complete(pool,{"prefix":0,"suffix":0},{"max_prefixes":1,"max_suffixes":1},2),"Independent suffix allows exact completion")
	var state:=Model.new();var path:="user://boundaries-%d.json"%Time.get_ticks_usec()
	check(state._admit_reward_item(Items.wrap_equipment(normal)),"Normal admitted")
	var before:=state.snapshot();var seq:=state._craft_sequence
	var metadata:=state.crafting_operations(normal.id,path)
	check(not metadata[2].available and metadata[2].cost=={Craft.MATERIAL_ID:8} and not metadata[2].reason.is_empty(),"Unaffordable metadata retains true price")
	var quote:=state.crafting_quote("enchant",normal.id,path)
	check(not quote.ok and state.snapshot()==before and state._craft_sequence==seq,"Unaffordable quote has no authority or mutation")
	for uid:String in state.snapshot().items:
		if state.item(uid).kind in ["currency","equipment"]:continue
		var entries:=state.crafting_operations(uid,path)
		check(entries.size()==6,"Non-gear retains six display actions")
		for entry:Dictionary in entries:check(not entry.available,"Gem/jewel/flask cannot craft")
	var bad:=normal.duplicate(true);bad.rarity="magic";bad.affixes=[{"id":"deepwell","tier":3,"value":22},{"id":"coalglow","tier":3,"value":20}]
	check(Gear.validate_instance(bad),"Saturated magic fixture legal")
	var state2:=Model.new();check(state2._admit_reward_item(Items.wrap_equipment(bad)),"Saturated item admitted")
	var candidate:=state2.snapshot();check(state2._set_bag_currency_balance(candidate,100).ok,"Fund no-result fixture");state2._accept_memory(candidate)
	var intact:=var_to_bytes(state2.snapshot());seed(411);var next:=randi();seed(411)
	check(not state2.crafting_operations(bad.id,path)[4].available,"Saturated augment disabled before quote")
	quote=state2.crafting_quote("augment",bad.id,path)
	check(not quote.ok and quote.code=="no_legal_result" and var_to_bytes(state2.snapshot())==intact and state2._craft_quotes.is_empty() and randi()==next,"No completion refuses before RNG/cost/handle")
	print("Crafting growth boundaries: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
