extends SceneTree
const Catalog=preload("res://scripts/items/equipment_catalog.gd")
const Expansion=preload("res://scripts/items/crafting_expansion_rules.gd")
const Craft=preload("res://scripts/items/crafting_rules.gd")
const Planner=preload("res://scripts/items/crafting_transaction_planner.gd")
const OLD_OPERATIONS=["salvage","recalibrate","enchant","elevate","augment","reforge"]
func _initialize()->void:
	var output:=OS.get_environment("CRAFT_COMPAT_OUTPUT")
	if output.is_empty() or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):quit(78);return
	var records:Array=[]
	var rng:=RandomNumberGenerator.new();rng.seed=492311
	for base_id:String in Catalog.all_base_ids():
		for level:int in [1,8,16,30]:
			var normal:Dictionary={"id":"gear_000001","base_id":base_id,"rarity":"normal","item_level":level,"affixes":[]}
			var magic:Dictionary=Expansion.plan(normal,"enchant",rng.randi(),Catalog.CURRENT_VOCABULARY).instance
			var rare:Dictionary=Expansion.plan(magic,"elevate",rng.randi(),Catalog.CURRENT_VOCABULARY).instance
			for source:Dictionary in [normal,magic,rare]:
				var context:Dictionary={"revision":7,"inventory":[source.id],"equipment_instances":{source.id:source},"equipped":{},"backpack_positions":{"item:"+source.id:[2,3]},"materials":{"calibration_shard":10000},"save_writable":true}
				for operation:String in OLD_OPERATIONS:
					var quoted:=Planner.quote(context,operation,source.id)
					var record:Dictionary={"source":source,"operation":operation,"metadata":Craft.operation_metadata(operation),"seed_version":Craft.seed_rules_version(operation),"quote":quoted,"plans":[]}
					for value:int in [0,4927,-817]:
						seed(81711);var expected_global:=randi();seed(81711)
						var planned:=Craft.operation_plan(source,operation,value)
						record.plans.append({"rules":planned,"transaction":Planner.plan(context,quoted,value),"global_rng_preserved":randi()==expected_global})
					records.append(record)
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("Cannot write comparison");quit(1);return
	file.store_buffer(var_to_bytes({"records":records,"catalog_rng":rng.state}));file.close()
	print("Legacy crafting probe: %d records, %d plan pairs"%[records.size(),records.size()*3]);quit(0)
