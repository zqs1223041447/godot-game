class_name FlaskCatalog
extends RefCounted
## Original prototype recovery items; no affix, ailment removal or player stats here.
const Locations=preload("res://scripts/items/item_location_rules.gd")
const SAVE_VERSION:=18
const MAX_CHARGES:=30
const USE_COST:=10
const DURATION:=3.0
const RECOVERY_FRACTION:=0.35
const REWARD_INTERVAL:=60
const DEFINITIONS:Dictionary={
	"flask:life":{"name":"生命药剂","resource":"health","icon_path":"res://assets/ui/grimoire/life_flask.png","color":Color("aa5046")},
	"flask:mana":{"name":"魔力药剂","resource":"mana","icon_path":"res://assets/ui/grimoire/mana_flask.png","color":Color("587da2")},
}
static func definition(id:Variant)->Dictionary:
	if not id is String or not DEFINITIONS.has(id):return {}
	var result:Dictionary=DEFINITIONS[id].duplicate(true)
	result.merge({"definition_id":id,"kind":"flask","size":Vector2i(1,2),"max_charges":MAX_CHARGES,"cost":USE_COST,"duration":DURATION,"recovery_fraction":RECOVERY_FRACTION,"rarity":"normal","effects":[],"stats":{},"category":"","description":"%.0f秒内恢复%.0f%%对应最大资源；消耗%d充能。同资源恢复不叠加，已满或充能不足时不消耗。"%[DURATION,RECOVERY_FRACTION*100.0,USE_COST]})
	return result
static func create_instance(uid:Variant,definition_id:Variant)->Dictionary:
	if not Locations._stable_id(uid) or definition(definition_id).is_empty():return {}
	return {"uid":uid,"kind":"flask","definition_id":definition_id,"payload":{}}
static func validate_instance(value:Variant)->bool:
	return Locations._exact_string_keys(value,["uid","kind","definition_id","payload"]) and Locations._stable_id(value.uid) and value.kind is String and value.kind=="flask" and value.definition_id is String and DEFINITIONS.has(value.definition_id) and value.payload is Dictionary and value.payload.is_empty()
static func reward_definition(eligible_root_kills:int)->String:
	if eligible_root_kills<=0 or eligible_root_kills%REWARD_INTERVAL!=0:return ""
	return "flask:life" if (eligible_root_kills/REWARD_INTERVAL as int)%2==1 else "flask:mana"
