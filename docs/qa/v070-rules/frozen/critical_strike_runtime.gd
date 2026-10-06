extends RefCounted
## Only accepted combat events draw from this private stream. Never use loot RNG.
const Rules=preload("res://docs/qa/v070-rules/frozen/critical_strike_rules.gd")
var _rng:=RandomNumberGenerator.new()
var draws:=0
var events:=0

func reset(run_seed:int)->void:
	_rng.seed=run_seed ^ 0x43524954
	draws=0;events=0

func checkpoint()->Dictionary:
	return {"state":_rng.state,"draws":draws,"events":events}

func restore(value:Dictionary)->void:
	_rng.state=value.state;draws=value.draws;events=value.events

static func snapshot_error(snapshot:Dictionary)->String:
	if not snapshot.has("critical"):return ""
	var profiles:Variant=snapshot.critical
	if not profiles is Dictionary or not profiles.has("primary") or profiles.size()<1 or profiles.size()>2:return "Invalid compiled critical profiles"
	for role:Variant in profiles:
		if not role is String or role not in ["primary","secondary"]:return "Unknown critical role"
		var reason:String=Rules.profile_error(profiles[role])
		if not reason.is_empty():return reason
	return ""

func freeze(snapshot:Dictionary,role:String="primary")->Dictionary:
	if role not in ["primary","secondary"]:return {"ok":false,"error":"Unknown critical role","snapshot":{}}
	var reason:=snapshot_error(snapshot)
	if not reason.is_empty():return {"ok":false,"error":reason,"snapshot":{}}
	var profile:Dictionary=snapshot.get("critical",{}).get(role,{})
	if profile.is_empty() or float(profile.chance)==0.0:
		# A zero-chance secondary may not inherit its parent hit's result.
		if snapshot.has("critical_roll"):
			var clean:=snapshot.duplicate(true);clean.erase("critical_roll")
			return {"ok":true,"error":"","snapshot":clean}
		return {"ok":true,"error":"","snapshot":snapshot}
	var sample:=0.0
	if float(profile.chance)<1.0:
		sample=float(_rng.randi())/4294967296.0;draws+=1
	var result:Dictionary=Rules.roll(profile,sample)
	if not result.ok:return {"ok":false,"error":result.error,"snapshot":{}}
	events+=1
	var frozen:=snapshot.duplicate(true)
	frozen.critical_roll={"critical":result.critical,"multiplier":result.multiplier,"chance":result.chance}
	return {"ok":true,"error":"","snapshot":frozen}
