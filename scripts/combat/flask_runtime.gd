class_name FlaskRuntime
extends RefCounted
## Per-run recovery state keyed by owned UID. It never saves a build or emits changed.
const Modifiers=preload("res://scripts/combat/flask_modifier_rules.gd")
const Catalog=preload("res://scripts/items/flask_catalog.gd")
var _definitions:Dictionary={}
var _charges:Dictionary={}
var _active:Dictionary={}
var _charge_remainders_micro:Dictionary={}
func reset(owned:Dictionary)->bool:
	if not _valid_owned(owned):return false
	_definitions=owned.duplicate();_charges.clear();_active.clear();_charge_remainders_micro.clear()
	for uid:String in owned:_charges[uid]=Catalog.MAX_CHARGES
	return true
func sync_owned(owned:Dictionary)->bool:
	if not _valid_owned(owned):return false
	for uid:String in owned:
		if _definitions.has(uid) and _definitions[uid]!=owned[uid]:return false
	for uid:String in _charges.keys():
		if not owned.has(uid):_charges.erase(uid);_charge_remainders_micro.erase(uid)
	for uid:String in owned:
		if not _charges.has(uid):_charges[uid]=Catalog.MAX_CHARGES
	_definitions=owned.duplicate()
	# Consumed recovery remains frozen if its bottle is moved or discarded.
	return true
func snapshot()->Dictionary:
	var result:Dictionary={"charges_by_uid":_charges.duplicate(true),"active_by_resource":_active.duplicate(true)}
	if not _charge_remainders_micro.is_empty():result.charge_remainders_micro=_charge_remainders_micro.duplicate(true)
	return result
func status(uid:String,current:float,maximum:float)->Dictionary:
	if not _definitions.has(uid):return _failure("unknown_flask","药剂已变化")
	var definition:=Catalog.definition(_definitions[uid]);var resource:String=definition.resource
	var active:Dictionary=_active.get(resource,{})
	var result:Dictionary={"ok":true,"code":"","reason":"","uid":uid,"resource":resource,"charges":int(_charges[uid]),"max_charges":Catalog.MAX_CHARGES,"cost":Catalog.USE_COST,"active":active.get("uid","")==uid,"resource_active":not active.is_empty(),"remaining_seconds":float(active.get("remaining_seconds",0.0)),"can_use":false}
	if not is_finite(current) or not is_finite(maximum) or current<0.0 or maximum<=0.0:result.code="invalid_resource";result.reason="资源数据无效"
	elif current>=maximum:result.code="resource_full";result.reason="对应资源已满"
	elif not active.is_empty():result.code="resource_active";result.reason="对应资源正在恢复"
	elif int(_charges[uid])<Catalog.USE_COST:result.code="insufficient_charges";result.reason="药剂充能不足"
	else:result.can_use=true
	return result
func use(uid:String,current:float,maximum:float,stats:Dictionary={})->Dictionary:
	var checked:=status(uid,current,maximum)
	if not checked.get("can_use",false):checked.ok=false;return checked
	var profile:=Modifiers.profile(_definitions[uid],stats,maximum)
	if not profile.ok:
		checked.ok=false;checked.can_use=false;checked.code="invalid_modifiers";checked.reason=profile.reason;return checked
	_charges[uid]=int(_charges[uid])-Catalog.USE_COST
	_active[checked.resource]={"uid":uid,"remaining_seconds":Catalog.DURATION,"rate":maximum*Catalog.RECOVERY_FRACTION/Catalog.DURATION if profile.recovery_multiplier==1.0 else profile.recovery_total/profile.duration,"locked_maximum":maximum}
	var result:=status(uid,current,maximum);result.ok=true;result.code="";result.reason="";return result
func advance(delta:float,current:Dictionary,maxima:Dictionary)->Dictionary:
	var gain:Dictionary={"health":0.0,"mana":0.0}
	if not is_finite(delta) or delta<=0.0:return gain
	for resource:String in ["health","mana"]:
		if not _valid_resource(current.get(resource)) or not _valid_resource(maxima.get(resource)):return gain
	for resource:String in _active.keys():
		var effect:Dictionary=_active[resource];var room:float=maxf(0.0,float(maxima[resource])-float(current[resource]))
		var elapsed:float=minf(delta,float(effect.remaining_seconds))
		gain[resource]=minf(room,elapsed*float(effect.rate))
		effect.remaining_seconds=maxf(0.0,float(effect.remaining_seconds)-elapsed)
		if gain[resource]>=room or float(effect.remaining_seconds)<=0.000000001:_active.erase(resource)
	return gain
func charge_rewarded_kill(equipped_uids:Array,stats:Dictionary={})->void:
	var gain:=Modifiers.charge_gain(stats)
	if not gain.ok:return
	var seen:Dictionary={}
	for uid:Variant in equipped_uids:
		if not uid is String or seen.has(uid) or not _charges.has(uid):continue
		seen[uid]=true
		if int(_charges[uid])>=Catalog.MAX_CHARGES:
			_charge_remainders_micro.erase(uid);continue
		var total:int=int(_charge_remainders_micro.get(uid,0))+int(gain.units)
		var whole:int=total/Modifiers.CHARGE_UNIT
		_charges[uid]=mini(Catalog.MAX_CHARGES,int(_charges[uid])+whole)
		var remainder:int=total%Modifiers.CHARGE_UNIT
		if int(_charges[uid])>=Catalog.MAX_CHARGES or remainder==0:_charge_remainders_micro.erase(uid)
		else:_charge_remainders_micro[uid]=remainder
func clear_effects()->void:_active.clear()
static func _valid_owned(owned:Dictionary)->bool:
	for uid:Variant in owned:
		if Catalog.create_instance(uid,owned[uid]).is_empty():return false
	return true
static func _valid_resource(value:Variant)->bool:return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)>=0.0
static func _failure(code:String,reason:String)->Dictionary:return {"ok":false,"code":code,"reason":reason,"can_use":false,"uid":"","resource":"","charges":0,"remaining_seconds":0.0}
