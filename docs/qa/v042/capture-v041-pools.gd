extends SceneTree
const Gear=preload("res://scripts/items/equipment_catalog.gd")
const Craft=preload("res://scripts/items/crafting_rules.gd")
func _initialize()->void:
	var out:=OS.get_environment("V042_BASELINE_OUTPUT")
	if out.is_empty():quit(78);return
	var records:Array=[];var examples:Dictionary={}
	for pool:String in Gear.POOL_PROFILES:
		for level:int in [1,8,16]:
			for rarity:String in ["normal","magic","rare"]:
				for seed:int in [1,7,19,42,98,2026,8841,717171]:
					var rng:=RandomNumberGenerator.new();rng.seed=seed
					var item:Dictionary=Gear.generate_for_pool(rng,"gear_000123",level,rarity,pool)
					records.append({"kind":"pool","profile":pool,"level":level,"rarity":rarity,"seed":seed,"item":item,"rng":rng.state})
					if not item.is_empty():examples[str(item.base_id)+":"+rarity+":"+str(level)]=item
	for profile:String in Gear.LOOT_PROFILES:
		for seed:int in range(1,41):
			var rng:=RandomNumberGenerator.new();rng.seed=seed
			var item:Dictionary=Gear.generate_loot_profile(rng,"gear_000123",16,"",profile)
			records.append({"kind":"loot","profile":profile,"level":16,"rarity":"","seed":seed,"item":item,"rng":rng.state})
	var crafts:Array=[]
	for item:Dictionary in examples.values():
		for operation:String in Craft.operation_ids():
			var seed:=72881
			crafts.append({"item":item,"operation":operation,"seed":seed,"quote":Craft.operation_quote(item,operation),"plan":Craft.operation_plan(item,operation,seed)})
	var data:Dictionary={"version":ProjectSettings.get_setting("application/config/version"),"records":records,"crafts":crafts}
	var f:=FileAccess.open(out,FileAccess.WRITE);f.store_buffer(var_to_bytes(data));f.close()
	print("Frozen v41 legacy capture: ",records.size()," generated results with RNG; ",crafts.size()," operation quotes/plans; ",examples.size()," item examples");quit()
