extends SceneTree
const Gear=preload("res://scripts/items/equipment_catalog.gd")
const Craft=preload("res://scripts/items/crafting_rules.gd")
const Export=preload("res://tools/export_reference.gd")
static func fingerprints(operations:Array)->Dictionary:
	var results:Dictionary={}
	for base:String in ["emberhide_vest","nine_slot_etched_ring","forgeblade"]:
		for level:int in [1,8,16]:
			for rarity:String in ["magic","rare"]:
				var source:=Export._crafting_probe_instance(base,level,rarity)
				for operation:String in operations:
					for seed_value:int in [0,7,42]:
						var key:="%s/%d/%s/%s/%d"%[base,level,rarity,operation,seed_value]
						results[key]=var_to_bytes(Craft.operation_plan(source,operation,seed_value)).hex_encode().sha256_text()
	return results
func _initialize()->void:
	assert(not Craft.operation_ids().has("targeted_reforge_armour"))
	var coverage:Dictionary={}
	for base:String in Gear.all_base_ids():
		for row:Dictionary in Craft.Expansion._pool(base,30,[]):
			var key:="%s/T%d"%[row.id,row.tier]
			if not coverage.has(key):coverage[key]=[]
			coverage[key].append(base)
	for id:String in Gear.all_affix_ids():
		for tier:Dictionary in Gear.affix_definition(id).tiers:assert(coverage.has("%s/T%d"%[id,tier.tier]))
	var result:Dictionary={"baseline":"a071697f85496b8dd0f7e63aa68f7e00d74c5d80","operations":Craft.operation_ids(),"fingerprints":fingerprints(Craft.operation_ids()),"legal_pool_coverage":coverage,"base_count":Gear.all_base_ids().size(),"family_count":Gear.all_affix_ids().size()}
	FileAccess.open("res://docs/qa/armour-targeted-reforge/baseline.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("ARMOUR_BASELINE old cases=",result.fingerprints.size()," all family/tier opportunities=",coverage.size());quit()
