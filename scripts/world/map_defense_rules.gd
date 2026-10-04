class_name MapDefenseRules
extends RefCounted
## Map grants use the same raw-stat -> effective defense authority as actors.
const Compiler=preload("res://scripts/world/map_compiler.gd")
const Catalog=preload("res://scripts/world/map_catalog.gd")
const Defense=preload("res://scripts/mechanics/defense_rules.gd")
const Monsters=preload("res://scripts/monsters/monster_catalog.gd")
const SOURCE_FIELD:="map_defense_source"
const MODIFIER_ID:="elemental_aegis"

static func active(profile:Dictionary)->bool:
	return profile.get("special_ids",[]).has(MODIFIER_ID)

static func apply_to_enemy(source:Variant,profile:Variant)->Dictionary:
	var reason:=Compiler.profile_reason(profile)
	if not reason.is_empty():return _failure(reason)
	if not source is Dictionary or not source.has_all(["id","template_id","defense_stats","resistances"]):return _failure("缺少标准怪物防御字段")
	if source.has(SOURCE_FIELD):return _failure("地图防御已经应用，不能重复叠加")
	if not source.id is int or source.id<=0 or not source.template_id is String or not Monsters.TEMPLATES.has(source.template_id):return _failure("怪物防御来源无效")
	if not source.defense_stats is Dictionary or not source.resistances is Dictionary:return _failure("怪物防御必须是字典")
	var before:=Defense.source_profile(source.defense_stats,"monster")
	if not before.ok:return _failure(before.reason)
	for element:String in ["fire","cold","lightning"]:
		var effective:Variant=source.resistances.get(element,0.0)
		if not (effective is int or effective is float) or not is_finite(float(effective)) or not is_equal_approx(float(effective),float(before.effective_resistances[element])):return _failure("怪物原始抗性与有效抗性不一致")
	var enemy:Dictionary=source.duplicate(true)
	if not active(profile):return {"ok":true,"error":"","enemy":enemy}
	var definition:Dictionary=Catalog.SPECIAL[MODIFIER_ID]
	var stats:Dictionary=source.defense_stats.duplicate(true)
	for element:String in definition.damage_types:
		stats[element+"_resistance"]=float(stats.get(element+"_resistance",0.0))+float(definition.resistance_bonus)
	var after:=Defense.source_profile(stats,"monster")
	if not after.ok:return _failure(after.reason)
	enemy.defense_stats=stats
	# Retain any existing physical/chaos entries; only the three authored types change.
	for element:String in definition.damage_types:enemy.resistances[element]=after.effective_resistances[element]
	enemy[SOURCE_FIELD]={"modifier_id":MODIFIER_ID,"source_stats":source.defense_stats.duplicate(true),"raw_resistances":after.raw_resistances.duplicate(true),"effective_resistances":after.effective_resistances.duplicate(true)}
	return {"ok":true,"error":"","enemy":enemy}

static func _failure(reason:String)->Dictionary:return {"ok":false,"error":reason}
