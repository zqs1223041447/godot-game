class_name MapCompiler
extends RefCounted
const Catalog=preload("res://scripts/world/map_catalog.gd")
const Encounters=preload("res://scripts/encounters/encounter_compiler.gd")
static func compile(map_id:Variant,normal_ids:Variant,special_ids:Variant)->Dictionary:
	if not map_id is String or not Catalog.MAPS.has(map_id):return _failure("未知地图")
	var encounter:=Encounters.compile(normal_ids)
	if not encounter.ok:return _failure(encounter.error)
	if not special_ids is Array or special_ids.size()>1:return _failure("最多选择一个特殊词缀")
	var ids:Array[String]=[]
	for id:Variant in special_ids:
		if not id is String or not Catalog.SPECIAL.has(id):return _failure("未知特殊词缀")
		if int(Catalog.MAPS[map_id].wave)<int(Catalog.SPECIAL[id].minimum_wave):return _failure("此地图等级不支持该特殊词缀")
		ids.append(id)
	var profile:Dictionary=Catalog.MAPS[map_id].duplicate(true)
	profile.id=map_id;profile.normal_ids=encounter.profile.modifier_ids.duplicate();profile.special_ids=ids
	profile.encounter_profile=encounter.profile
	var summary:PackedStringArray=[profile.name]
	for row:Dictionary in encounter.profile.definitions:summary.append(row.name)
	for id:String in ids:summary.append(Catalog.SPECIAL[id].name)
	profile.summary=" · ".join(summary)
	return {"ok":true,"code":"","reason":"","profile":profile}
static func profile_reason(profile:Variant)->String:
	if not profile is Dictionary:return "地图配置无效"
	var expected:=compile(profile.get("id"),profile.get("normal_ids"),profile.get("special_ids"))
	return "" if expected.ok and expected.profile==profile else "地图配置来源或参数已变化"
static func special_template(profile:Dictionary,roll:Dictionary)->String:
	if not profile_reason(profile).is_empty():return ""
	for id:String in profile.special_ids:
		var definition:Dictionary=Catalog.SPECIAL[id]
		if definition.get("kind","template")!="template":continue
		if roll.get("template","")==definition.species:return definition.template
	return ""
static func _failure(reason:String)->Dictionary:return {"ok":false,"code":"invalid_map","reason":reason}
