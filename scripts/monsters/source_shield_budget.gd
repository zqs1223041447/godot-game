class_name SourceShieldBudget
extends RefCounted
## Original monster balance supply, separate from source percentage grants.
## Activated only by the new shield identities. Never supplied to players.
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const POLICY := "monster-shield-supply-v1"
const FIELD := "source_shield_profile"
const SUPPLIES: Dictionary = {
	"source_aegis_capacity": {"max_shield":3.12,"shield_regen":0.0},
	"source_aegis_recovery": {"max_shield":1.56,"shield_regen":0.4225},
}
const PROFILE_KEYS := ["budget_policy","supplies","legacy_base_shield","legacy_base_recharge_rate",
	"base_max_shield","base_recharge_rate","capacity_increased","capacity_multiplier"]


static func build(ids: Array, legacy: Dictionary, increases: Dictionary) -> Dictionary:
	var supplies: Array[Dictionary] = []
	for id: Variant in ids:
		if not id is String: return _failure("Shield supply identities must be strings")
		if SUPPLIES.has(id):
			supplies.append({"id":id,"max_shield":float(SUPPLIES[id].max_shield),
				"shield_regen":float(SUPPLIES[id].shield_regen)})
	if supplies.is_empty(): return {"ok":true,"reason":"","enabled":false}
	if supplies.size() > 2: return _failure("Shield supply exceeds actor affix budget")
	for amount: Variant in [legacy.get("max_shield",0.0),legacy.get("shield_regen",0.0),increases.get("max_shield",0.0)]:
		if not _amount(amount): return _failure("Shield supply bases and increase must be finite nonnegative scalars")
	var old_shield := float(legacy.get("max_shield",0.0))
	var old_rate := float(legacy.get("shield_regen",0.0))
	var base_shield := old_shield
	var base_rate := old_rate
	for supply: Dictionary in supplies:
		base_shield += float(supply.max_shield)
		base_rate += float(supply.shield_regen)
	var increase := float(increases.get("max_shield",0.0))
	var multiplier := 1.0 + increase
	var maximum := base_shield * multiplier
	if not _amount(base_shield) or not _amount(base_rate) or not _amount(multiplier) or not _amount(maximum):
		return _failure("Shield supply result overflow")
	var profile := {"budget_policy":POLICY,"supplies":supplies,"legacy_base_shield":old_shield,
		"legacy_base_recharge_rate":old_rate,"base_max_shield":base_shield,"base_recharge_rate":base_rate,
		"capacity_increased":increase,"capacity_multiplier":multiplier}
	return {"ok":true,"reason":"","enabled":true,"max_shield":maximum,
		"base_recharge_rate":base_rate,"profile":profile}


## Read only the actor's frozen source metadata, never a live source definition.
## The normal encounter admission calls this before adding map resources.
static func snapshot_reason(enemy: Dictionary) -> String:
	if not enemy.has(FIELD):
		var ids: Variant = enemy.get("mechanism_ids", [])
		if ids is Array:
			for id: Variant in ids:
				if id is String and SUPPLIES.has(id): return "Missing frozen source shield profile"
		return ""
	var profile: Variant = enemy[FIELD]
	if not profile is Dictionary or profile.size() != PROFILE_KEYS.size() or not profile.has_all(PROFILE_KEYS):
		return "Invalid frozen source shield profile"
	if profile.budget_policy != POLICY: return "Unknown monster shield supply budget"
	for key: String in PROFILE_KEYS:
		if key not in ["budget_policy","supplies"] and not _amount(profile[key]): return "Invalid frozen shield scalar: " + key
	if profile.capacity_multiplier != 1.0 + float(profile.capacity_increased): return "Frozen shield multiplier is inconsistent"
	var stats: Variant = enemy.get("mechanism_stats")
	if not stats is Dictionary: return "Missing frozen mechanism stats"
	for key: String in ["max_shield", "shield_regen"]:
		if not _amount(stats.get(key, 0.0)): return "Invalid legacy shield base: " + key
	if profile.legacy_base_shield != float(stats.get("max_shield", 0.0)) or profile.legacy_base_recharge_rate != float(stats.get("shield_regen", 0.0)):
		return "Frozen legacy shield bases differ from mechanism stats"
	if not profile.supplies is Array or profile.supplies.is_empty() or profile.supplies.size() > 2:
		return "Invalid frozen shield supplies"
	var ids: Variant = enemy.get("mechanism_ids")
	var grants: Variant = enemy.get("mechanism_source_grants")
	if not ids is Array or not grants is Array: return "Missing frozen shield provenance"
	var expected_ids: Array[String] = []
	for id: Variant in ids:
		if not id is String: return "Invalid frozen mechanism identity"
		if SUPPLIES.has(id): expected_ids.append(id)
	var actual_ids: Array[String] = []
	var base_shield := float(profile.legacy_base_shield)
	var base_rate := float(profile.legacy_base_recharge_rate)
	for supply: Variant in profile.supplies:
		if not supply is Dictionary or supply.size()!=3 or not supply.has_all(["id","max_shield","shield_regen"]) \
				or not supply.id is String or not SUPPLIES.has(supply.id): return "Invalid frozen shield supply identity"
		if not _amount(supply.max_shield) or not _amount(supply.shield_regen): return "Invalid frozen shield supply amount"
		if supply.max_shield != SUPPLIES[supply.id].max_shield or supply.shield_regen != SUPPLIES[supply.id].shield_regen:
			return "Frozen shield supply differs from its versioned budget"
		actual_ids.append(supply.id)
		base_shield += float(supply.max_shield)
		base_rate += float(supply.shield_regen)
	if actual_ids != expected_ids: return "Frozen shield supply identities do not match actor"
	if profile.base_max_shield != base_shield or profile.base_recharge_rate != base_rate: return "Frozen shield bases are inconsistent"
	var source_ids: Array[String] = []
	var increase := 0.0
	for grant: Variant in grants:
		if not grant is Dictionary or not grant.get("id") is String: return "Invalid frozen source grant"
		if not SUPPLIES.has(grant.id): continue
		var capacity: Variant = grant.get("capacity_increased")
		if not capacity is Dictionary or not _amount(capacity.get("max_shield")): return "Missing frozen shield increase"
		increase += float(capacity.max_shield)
		source_ids.append(grant.id)
	if source_ids != expected_ids or increase != profile.capacity_increased: return "Frozen shield source increases are inconsistent"
	if not _amount(enemy.get("max_shield")) or enemy.max_shield != base_shield * float(profile.capacity_multiplier):
		return "Actor maximum shield differs from frozen source profile"
	if not _amount(enemy.get("shield_regen")) or enemy.shield_regen != base_rate: return "Actor recharge base differs from frozen source profile"
	var recharge_inputs: Dictionary = stats.duplicate(true)
	recharge_inputs.shield_regen = base_rate
	var recharge := Defense.recharge_profile(recharge_inputs, "monster")
	if not recharge.ok: return recharge.reason
	var rate: Variant = enemy.get("shield_recharge_rate", enemy.shield_regen)
	var delay: Variant = enemy.get("shield_recharge_delay", Defense.RECHARGE_BASE_DELAY)
	if not _amount(rate) or not _amount(delay) or rate != recharge.rate or delay != recharge.delay:
		return "Actor recharge result differs from frozen stats"
	return ""


static func _amount(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)>=0.0


static func _failure(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason,"enabled":false}
