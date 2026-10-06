extends RefCounted
## Authored cost-efficiency formula for the current mana-only active skills.
## Applied after existing support multipliers. A zero source preserves old bits.
const STATS:Array[String]=["mana_cost_efficiency_increased","mana_cost_increased"]
static func from_stats(stats:Dictionary)->Dictionary:
	var result:Dictionary={}
	for stat:String in STATS:
		var value:Variant=stats.get(stat,0.0)
		if not _number(value) or float(value)!=0.0:result[stat]=value
	return result
static func error(snapshot:Dictionary)->String:
	if not snapshot.has("resource_modifiers"):return ""
	var fields:Variant=snapshot.resource_modifiers
	if not fields is Dictionary:return "资源成本增幅必须为属性字典"
	for field:Variant in fields:
		if not field is String or field not in STATS or not _number(fields[field]) or float(fields[field])<0.0:return "资源成本字段或数值无效"
	var denominator:float=1.0+float(fields.get("mana_cost_efficiency_increased",0.0))
	if not is_finite(denominator) or denominator<=0.0:return "成本效率分母必须有限且大于零"
	return ""
static func apply(mana:float,snapshot:Dictionary)->Dictionary:
	var reason:=error(snapshot)
	if not reason.is_empty():return {"ok":false,"error":reason}
	if not _number(mana) or mana<0.0:return {"ok":false,"error":"技能魔力成本无效"}
	var fields:Dictionary=snapshot.get("resource_modifiers",{})
	var increase:float=float(fields.get("mana_cost_increased",0.0))
	var efficiency:float=float(fields.get("mana_cost_efficiency_increased",0.0))
	if increase==0.0 and efficiency==0.0:return {"ok":true,"error":"","mana":mana,"factors":{}}
	var numerator:float=1.0+increase;var denominator:float=1.0+efficiency
	var final:float=mana*numerator/denominator
	if not is_finite(final) or final<0.0:return {"ok":false,"error":"最终魔力成本超出有限边界"}
	return {"ok":true,"error":"","mana":final,"factors":{"support_mana":mana,"increased_cost":increase,"increased_efficiency":efficiency,"numerator":numerator,"denominator":denominator,"final_mana":final}}
static func _number(value:Variant)->bool:return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))
