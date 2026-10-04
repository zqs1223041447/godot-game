class_name FlaskModifierRules
extends RefCounted
const Catalog=preload("res://scripts/items/flask_catalog.gd")
const STATS:Array[String]=["flask_life_recovery_increased","flask_mana_recovery_increased","flask_charges_gained_increased"]
const CHARGE_UNIT:=1000000
static func stats_reason(stats:Variant)->String:
	if not stats is Dictionary:return "药剂增幅必须为属性字典"
	for stat:String in STATS:
		var value:Variant=stats.get(stat,0.0)
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)<0.0:return "药剂增幅必须为有限非负数值"
	return ""
static func charge_gain(stats:Variant)->Dictionary:
	var reason:=stats_reason(stats)
	if not reason.is_empty():return {"ok":false,"reason":reason}
	var amount:float=1.0+float(stats.get("flask_charges_gained_increased",0.0))
	if not is_finite(amount):return {"ok":false,"reason":"药剂充能增幅溢出"}
	# Current pinned source percentages are exact whole-percent increments.
	# Fixed microcharge carry avoids losing the twentieth 1.15 gain to float ULPs.
	# Saturation before conversion is equivalent to the owned bottle's30 cap.
	return {"ok":true,"reason":"","amount":amount,"units":roundi(minf(amount,float(Catalog.MAX_CHARGES))*CHARGE_UNIT)}
static func profile(definition_id:Variant,stats:Variant,maximum:Variant)->Dictionary:
	var definition:=Catalog.definition(definition_id)
	if definition.is_empty():return {"ok":false,"reason":"未知药剂"}
	var gain:=charge_gain(stats)
	if not gain.ok:return gain
	if typeof(maximum) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(maximum)) or float(maximum)<=0.0:return {"ok":false,"reason":"药剂对应资源上限无效"}
	var stat:String="flask_life_recovery_increased" if definition.resource=="health" else "flask_mana_recovery_increased"
	var multiplier:float=1.0+float(stats.get(stat,0.0));var fraction:float=Catalog.RECOVERY_FRACTION*multiplier;var total:float=float(maximum)*fraction
	if not is_finite(fraction) or not is_finite(total):return {"ok":false,"reason":"药剂恢复总量溢出"}
	return {"ok":true,"reason":"","resource":definition.resource,"duration":Catalog.DURATION,"cost":Catalog.USE_COST,"max_charges":Catalog.MAX_CHARGES,"base_recovery_fraction":Catalog.RECOVERY_FRACTION,"recovery_multiplier":multiplier,"recovery_fraction":fraction,"recovery_total":total,"charges_per_root":gain.amount}
