class_name TownCatalog
extends RefCounted
## Test-only supply from implemented catalogs. No random rolls or account wallet.
const Items=preload("res://scripts/items/unified_item_catalog.gd")
const Gear=preload("res://scripts/items/equipment_catalog.gd")
const Gems=preload("res://scripts/items/gem_catalog.gd")
const Jewels=preload("res://scripts/jewel_data.gd")
const Flasks=preload("res://scripts/items/flask_catalog.gd")
const Data=preload("res://scripts/game_data.gd")
const SERVICES={
	"skill_merchant":{"name":"宝石商人","description":"免费测试供应全部已实现主动与辅助宝石。"},
	"equipment_merchant":{"name":"装备商人","description":"免费测试供应全部底材、机制装备、生命/魔力药剂和测试碎片。"},
	"passive_reset":{"name":"天赋重置师","description":"退还已花普通天赋点，保留起点；珠宝保留，放不下进入待安置。"},
	"jewel_merchant":{"name":"珠宝商人","description":"供应全部已实现珠宝底材与特殊珠宝。"},
	"crafter":{"name":"制造工匠","description":"使用测试档的真实碎片进行六项现有工艺。"},
	"map_device":{"name":"地图装置","description":"选择有限地图，免费制作普通与特殊词缀，开始战斗并返城。"}}
static func services()->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for id:String in SERVICES:
		var row:Dictionary=SERVICES[id].duplicate(true);row.id=id;result.append(row)
	return result
static func offers(service_id:String)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if service_id=="skill_merchant":
		for id:String in Gems.definitions():result.append(_offer(id,"gem",id))
	elif service_id=="equipment_merchant":
		for id:String in Gear.all_base_ids():result.append(_offer("base:"+id,"base",id))
		for id:String in Data.ITEMS:result.append(_offer("fixed:"+id,"fixed",id))
		for id:String in ["flask:life","flask:mana"]:result.append(_offer(id,"flask",id))
		result.append(_offer("currency:calibration_shard","currency","calibration_shard"))
	elif service_id=="jewel_merchant":
		for id:String in Jewels.BASES:result.append(_offer("jewel:"+id,"jewel",id))
		for id:String in Jewels.SPECIAL_BASES:result.append(_offer("jewel:"+id,"jewel",id))
	return result
static func offer(id:Variant)->Dictionary:
	if not id is String:return {}
	if id.begins_with("skill:") or id.begins_with("support:"):
		return _offer(id,"gem",id) if not Gems.definition(id).is_empty() else {}
	if id.begins_with("base:"):
		var base_id:String=id.substr(5)
		return _offer(id,"base",base_id) if not Gear.base_definition(base_id).is_empty() else {}
	if id.begins_with("fixed:"):
		var fixed_id:String=id.substr(6)
		return _offer(id,"fixed",fixed_id) if Data.ITEMS.has(fixed_id) else {}
	if id.begins_with("jewel:"):
		var base_id:String=id.substr(6)
		return _offer(id,"jewel",base_id) if Jewels.BASES.has(base_id) or Jewels.SPECIAL_BASES.has(base_id) else {}
	if id in ["flask:life","flask:mana"]:return _offer(id,"flask",id)
	if id=="currency:calibration_shard":return _offer(id,"currency","calibration_shard")
	return {}
static func _offer(id:String,type:String,definition:String)->Dictionary:
	var specification:Dictionary={"id":id,"supply_kind":type,"catalog_id":definition}
	var sample:=make_item(specification,1)
	var preview:=Items.definition_for_instance(sample)
	return {"id":id,"supply_kind":type,"catalog_id":definition,"name":str(preview.get("name",id))+(" ×100" if type=="currency" else ""),"quantity":100 if type=="currency" else 1,
		"kind":sample.get("kind",""),"definition_id":sample.get("definition_id",""),
		"description":preview.get("description",""),"icon_path":preview.get("icon_path",""),
		"size":preview.get("size",Vector2i.ONE),"category":preview.get("category",""),
		"price_label":"测试免费", "preview":preview,"available":not sample.is_empty(),"reason":""}
static func make_item(spec:Dictionary,serial:int)->Dictionary:
	if serial<1 or serial>=1000000000:return {}
	var id:String=spec.get("catalog_id","");var kind:String=spec.get("supply_kind","")
	match kind:
		"gem":return Gems.create_instance("item_%06d"%serial,id)
		"flask":return Flasks.create_instance("item_%06d"%serial,id)
		"fixed":return Items.fixed_equipment("item_%06d"%serial,id)
		"currency":return Items.calibration_shard("item_%06d"%serial,100)
		"base":return Items.wrap_equipment({"id":"gear_%06d"%serial,"base_id":id,"rarity":"normal","item_level":30,"affixes":[]})
		"jewel":
			if Jewels.SPECIAL_BASES.has(id):return Items.wrap_jewel(Jewels.generate_special("jewel_%06d"%serial))
			if not Jewels.BASES.has(id):return {}
			var affixes:Array=[]
			for field:String in ["prefixes","suffixes"]:
				var affix:String=Jewels.BASES[id][field][0]
				affixes.append({"id":affix,"value":float(Jewels.AFFIXES[affix].min)})
			return Items.wrap_jewel({"id":"jewel_%06d"%serial,"base":id,"rarity":"magic","affixes":affixes})
	return {}
