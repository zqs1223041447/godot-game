class_name SourceSpatialRules
extends RefCounted
## Player skill geometry, separate from damage increases. Called once at cast
## compilation; carriers only read the frozen final recipes afterwards.
const STATS:Array[String]=["area_size_increased","spell_area_size_increased","melee_area_size_increased","projectile_speed_increased"]
const AREA_SCOPE={"nova":"spell_area_size_increased","meteor":"spell_area_size_increased","cleave":"melee_area_size_increased"}
const MAX_RADIUS:=500.0
const MAX_SPEED:=3000.0

static func from_stats(stats:Dictionary)->Dictionary:
	var result:Dictionary={}
	for stat:String in STATS:
		var value:Variant=stats.get(stat,0.0)
		# Preserve invalid values for the compiler to reject, never silently wash
		# an invalid source into a valid zero-modifier cast.
		if not _number(value) or float(value)!=0.0:result[stat]=value
	return result

static func error(snapshot:Dictionary)->String:
	if not snapshot.has("spatial_modifiers"):return ""
	var values:Variant=snapshot.spatial_modifiers
	if not values is Dictionary:return "空间增幅必须为属性字典"
	for stat:Variant in values:
		if not stat is String or stat not in STATS or not _number(values[stat]):return "空间增幅字段或数值无效"
		if stat!="projectile_speed_increased" and float(values[stat])<0.0:return "本批未支持范围面积减幅来源"
	if 1.0+float(values.get("projectile_speed_increased",0.0))<=0.0:return "投射速度增减后的倍率必须大于零"
	return ""

static func apply(skill_id:String,recipe:Dictionary,snapshot:Dictionary,base_speed:float=0.0)->Dictionary:
	var reason:=error(snapshot)
	if not reason.is_empty():return {"error":reason}
	var result:Dictionary=recipe.duplicate(true)
	var frozen:Dictionary=snapshot.duplicate(true)
	var values:Dictionary=snapshot.get("spatial_modifiers",{})
	var area:float=float(values.get("area_size_increased",0.0))
	if AREA_SCOPE.has(skill_id):
		var applicable:float=area+float(values.get(AREA_SCOPE[skill_id],0.0))
		if applicable!=0.0:
			var before:float=float(result.radius)
			var total:float=float(result.get("area_multiplier",1.0))*(1.0+applicable)
			var original:float=float(result.get("base_radius",before))
			var radius:float=original*sqrt(total)
			if not is_finite(radius) or radius>MAX_RADIUS:return {"error":"面积增幅后的半径超出边界"}
			result.base_radius=original;result.area_multiplier=total;result.source_area_multiplier=1.0+applicable;result.radius=radius
	if area!=0.0 and skill_id in ["basic","tornado","bolt","frost","shade_bolt"]:
		var original:float=float(frozen.explosion_recipe.radius)
		var radius:float=original*sqrt(1.0+area)
		if not is_finite(radius) or radius>MAX_RADIUS:return {"error":"爆炸面积增幅后的半径超出边界"}
		frozen.explosion_recipe.radius=radius
		frozen.explosion_recipe.base_radius=original
		frozen.explosion_recipe.area_multiplier=1.0+area
	var speed:float=float(values.get("projectile_speed_increased",0.0))
	if speed!=0.0:
		if skill_id=="tornado":
			for role:String in ["parent","child"]:
				var changed:=_speed(result[role],float(recipe[role].speed),1.0+speed)
				if not changed.error.is_empty():return changed
				result[role]=changed.recipe
			frozen.tornado_recipe=result.duplicate(true)
		elif skill_id in ["basic","bolt","frost","shade_bolt"]:
			var changed:=_speed(result,base_speed,1.0+speed)
			if not changed.error.is_empty():return changed
			result=changed.recipe
	return {"error":"","recipe":result,"snapshot":frozen}

static func _speed(recipe:Dictionary,base:float,factor:float)->Dictionary:
	var result:Dictionary=recipe.duplicate(true)
	var speed:float=float(recipe.speed)*factor
	if not is_finite(speed) or speed<=0.0 or speed>MAX_SPEED or not is_finite(base) or base<=0.0:return {"error":"增减幅后的投射速度超出边界"}
	result.speed=speed;result.base_speed=base;result.speed_multiplier=speed/base;result.source_speed_multiplier=factor
	return {"error":"","recipe":result}

static func _number(value:Variant)->bool:return (value is int or value is float) and is_finite(float(value))
