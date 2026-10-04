extends SceneTree
const Gear=preload("res://scripts/items/equipment_catalog.gd")
const Craft=preload("res://scripts/items/crafting_rules.gd")
var checks:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func item(base_id:String,tier:int=3)->Dictionary:
	var affixes:Array=[]
	for id:String in Gear.BuildAffixes.AFFIX_IDS:
		var family:Dictionary=Gear.affix_definition(id)
		affixes.append({"id":id,"tier":tier,"value":family.tiers[tier-1].max})
	return {"id":"gear_000123","base_id":base_id,"rarity":"rare","item_level":16,"affixes":affixes}
func run()->void:
	var baseline:Dictionary=bytes_to_var(FileAccess.get_file_as_bytes("res://docs/qa/v042/v041-pools-and-crafting.bin"))
	check(baseline.version=="0.41.0","Baseline comes from frozen actual v41 PCK")
	for row:Dictionary in baseline.records:
		var rng:=RandomNumberGenerator.new();rng.seed=row.seed
		var actual:Dictionary=Gear.generate_for_pool(rng,"gear_000123",row.level,row.rarity,row.profile) if row.kind=="pool" else Gear.generate_loot_profile(rng,"gear_000123",row.level,row.rarity,row.profile)
		check(var_to_bytes(actual)==var_to_bytes(row.item) and rng.state==row.rng,"Historical generator and next RNG exact: "+row.profile)
	for row:Dictionary in baseline.crafts:
		check(var_to_bytes(Craft.operation_quote(row.item,row.operation,14))==var_to_bytes(row.quote),"Explicit old crafting quote exact: "+row.operation)
		check(var_to_bytes(Craft.operation_plan(row.item,row.operation,row.seed,14))==var_to_bytes(row.plan),"Explicit old crafting plan exact: "+row.operation)
		if row.operation in ["salvage","recalibrate"]:
			var direct:Dictionary=Craft.salvage_quote(row.item) if row.operation=="salvage" else Craft.recalibrate_plan(row.item,row.seed)
			check(var_to_bytes(direct)==var_to_bytes(row.plan),"Direct original salvage/calibration output exact")
	check(Craft.seed_rules_version("recalibrate")==Craft.LEGACY_SEED_VERSION and Craft.seed_rules_version("enchant",14)==Craft.RULES_VERSION+":enchant","Old seed contract accessible without new pool")
	check(Gear.all_base_ids().size()==14 and Gear.all_affix_ids().size()==30,"No new bases; exactly four added affix families")
	for base:String in Gear.all_base_ids():
		for tier:int in [1,2,3]:
			var source:=item(base,tier)
			var allowed:bool=Gear.BuildAffixes.ALLOWED_BASE_IDS.has(base)
			check(Gear.validate_instance(source)==allowed,"Exact base allowlist "+base)
			check(not Gear.validate_instance_for_version(source,26),"Old26 rejects all new families")
			if not allowed:continue
			var stats:=Gear.get_stats(source)
			check(is_equal_approx(stats.attack_life_leech,float(source.affixes[0].value)/10000.0),"Life exact basis point conversion")
			check(is_equal_approx(stats.attack_mana_leech,float(source.affixes[1].value)/10000.0),"Mana exact basis point conversion")
			check(is_equal_approx(stats.crit_chance_increased,float(source.affixes[2].value)/100.0) and is_equal_approx(stats.crit_multiplier_add,float(source.affixes[3].value)/100.0),"Both crit percentage semantics")
			var before:=var_to_bytes(source)
			for affix:Dictionary in source.affixes:
				var display:=Gear.affix_display(affix);check(display.ok and display.line==display.label+" "+display.value_text,"One catalog display contract")
			check(var_to_bytes(source)==before,"Pure display/stat readers preserve source")
			var bad:=source.duplicate(true);bad.affixes[1]=bad.affixes[0].duplicate();check(not Gear.validate_instance(bad),"One family never repeats across tiers")
			bad=source.duplicate(true);bad.item_level=0;check(not Gear.validate_instance(bad),"Invalid ilvl")
			if tier>1:
				bad=source.duplicate(true);bad.item_level=int(Gear.affix_definition(source.affixes[0].id).tiers[tier-1].level)-1;check(not Gear.validate_instance(bad),"New tier gate rejects one below")
	for malformed:Variant in [{},{"id":"unknown","tier":1,"value":20},{"id":"attack_life_leech","tier":true,"value":20},{"id":"attack_life_leech","tier":1,"value":20.5},{"id":"attack_life_leech","tier":1,"value":19}]:check(not Gear.affix_display(malformed).ok,"Malformed display rejected")
	check(Gear.affix_display({"id":"attack_life_leech","tier":1,"value":20}).value_text=="+0.20%","Fractional percent display exact")
	check(Gear.affix_display({"id":"global_critical_multiplier","tier":3,"value":15}).value_text=="+15个百分点","Multiplier additions distinguished")
	var seen:Dictionary={};var rng:=RandomNumberGenerator.new();rng.seed=412742
	for i:int in range(1600):
		var rolled:=Gear.generate_loot_profile(rng,"gear_000123",16,"rare",Gear.CANONICAL_LOOT_PROFILE_ID)
		check(Gear.validate_instance(rolled),"New natural weighted pool always yields valid instance")
		for affix:Dictionary in rolled.affixes:
			if Gear.BuildAffixes.AFFIX_IDS.has(affix.id):seen[str(rolled.base_id)+":"+str(affix.id)]=true
	for base:String in Gear.BuildAffixes.ALLOWED_BASE_IDS:
		for id:String in Gear.BuildAffixes.AFFIX_IDS:check(seen.has(base+":"+id),"Actual seeded natural acquisition witness "+base+":"+id)
	print("Build affix catalog: %d checks, %d failures; frozen480 generators/648crafts, natural1600 samples are reachability witnesses only"%[checks,failures]);quit(1 if failures else 0)
