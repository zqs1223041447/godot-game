class_name DefenseRules
extends RefCounted
## Original, bounded hit-defense rules shared by the player and monsters.
## DamageResolver owns the per-component formula; this module validates authored
## defenses and settles its result against shield first, then health. No RNG.

const Damage = preload("res://scripts/combat/damage_resolver.gd")
const STAGE: String = "hit_mitigation"
const FIRE_RESISTANCE_CAP: float = 0.75
const ACTORS: Array[String] = ["player", "monster"]
const RECHARGE_BASE_DELAY:=4.0


static func recharge_profile(stats:Dictionary,actor:String="player")->Dictionary:
	if actor not in ACTORS:return _failure("Unknown recharge actor")
	for field:String in ["shield_regen","shield_recharge_rate_increased","shield_recharge_start_faster"]:
		if not _amount(stats.get(field,0.0)):return _failure("Invalid shield recharge stat: "+field)
	var base_rate:float=float(stats.get("shield_regen",0.0))
	var rate:float=base_rate*(1.0+float(stats.get("shield_recharge_rate_increased",0.0)))
	var delay:float=RECHARGE_BASE_DELAY/(1.0+float(stats.get("shield_recharge_start_faster",0.0)))
	if not is_finite(rate) or not is_finite(delay) or delay<=0.0:return _failure("Shield recharge profile overflow")
	return {"ok":true,"reason":"","base_rate":base_rate,"rate":rate,"delay":delay}


static func supports_stat(stat: String, actor: String, stage: String = STAGE) -> bool:
	return support_reason(stat, actor, stage).is_empty()


static func support_reason(stat: String, actor: String, stage: String = STAGE) -> String:
	if not ACTORS.has(actor):
		return "Unknown defense actor: " + actor
	if stage != STAGE:
		return "Unsupported defense stage: " + stage
	if stat != "fire_resistance":
		return "Unsupported defense stat: " + stat
	return ""


static func metadata() -> Dictionary:
	return {
		"id": "fire_resistance", "name": "火焰抗性", "kind": "hit_defense",
		"stage": STAGE, "stat": "fire_resistance", "damage_type": "fire",
		"supported_actors": ACTORS.duplicate(), "schema_version": 1,
		"origin": "original", "source_refs": [], "balance_version": "original-fire-defense-v1",
		"minimum_effective": 0.0, "maximum_effective": FIRE_RESISTANCE_CAP,
		"stacking": "additive_raw_then_clamp", "settlement_order": ["resistance", "shield", "health"],
		"description": "本项目原创火焰命中防御；原始抗性相加，有效值限制在 0%–75%，再依次消耗护盾和生命。",
		"unsupported": ["armor", "penetration", "ailments", "chaos_bypass"],
	}


static func defense_profile(stats: Variant, actor: String = "player", stage: String = STAGE) -> Dictionary:
	var reason: String = support_reason("fire_resistance", actor, stage)
	if not reason.is_empty():
		return _failure(reason)
	if not stats is Dictionary:
		return _failure("Defense stats must be an object")
	for stat: Variant in stats:
		if not stat is String:
			return _failure("Defense stat names must be strings")
		reason = support_reason(stat, actor, stage)
		if not reason.is_empty():
			return _failure(reason)
		if not _finite_number(stats[stat]):
			return _failure("Defense stat must be a finite scalar: " + stat)
	var raw: float = float(stats.get("fire_resistance", 0.0))
	return {"ok": true, "reason": "", "actor": actor, "stage": stage,
		"raw_resistances": {"fire": raw},
		"effective_resistances": {"fire": clampf(raw, 0.0, FIRE_RESISTANCE_CAP)}}


static func incoming_hit(components: Variant, defense_stats: Variant, shield: Variant,
		health: Variant, actor: String = "player") -> Dictionary:
	var checked: Dictionary = validate_components(components)
	if not checked.ok:
		return checked
	var resources_error: String = _resources_error(shield, health)
	if not resources_error.is_empty():
		return _failure(resources_error)
	var profile: Dictionary = defense_profile(defense_stats, actor)
	if not profile.ok:
		return profile
	var packet: Dictionary = Damage.packet(checked.components, ["hit"], "incoming_hit")
	var resolved: Dictionary = Damage.resolve(packet, [], profile.effective_resistances)
	var result: Dictionary = settle_resolved(resolved, shield, health)
	if not result.ok:
		return result
	result["actor"] = actor
	result["stage"] = STAGE
	result["raw_resistances"] = profile.raw_resistances.duplicate(true)
	result["effective_resistances"] = profile.effective_resistances.duplicate(true)
	return result


## Source-tree defense adapter. The legacy fire-only schema remains stable.
## Both actors use this same formula; armour is hit-size dependent and never a
## permanently cached percentage. Elemental caps precede shield, then life.
static func source_profile(stats: Dictionary, actor: String = "player") -> Dictionary:
	if not ACTORS.has(actor): return _failure("Unknown defense actor")
	var raw := {}
	var effective := {}
	for type: String in ["fire","cold","lightning"]:
		var amount: Variant = stats.get(type+"_resistance",0.0)
		if not _finite_number(amount): return _failure("Non-finite source resistance")
		raw[type] = float(amount)
		effective[type] = clampf(float(amount),0.0,0.75)
	if not _amount(stats.get("armour",0.0)): return _failure("Invalid armour")
	return {"ok":true,"reason":"","actor":actor,"armour":float(stats.get("armour",0.0)),"raw_resistances":raw,"effective_resistances":effective}


static func apply_armour(resolved: Dictionary, armour: float) -> Dictionary:
	var result := resolved.duplicate(true)
	if armour <= 0.0 or not is_finite(armour): return result
	for detail: Dictionary in result.details:
		if detail.type != "physical" or float(detail.before_defense)<=0.0: continue
		var reduction := minf(0.9,armour/(armour+5.0*float(detail.before_defense)))
		detail.resistance = minf(0.9,float(detail.resistance)+reduction)
		detail.final = float(detail.before_defense)*(1.0-float(detail.resistance))
		result.components.physical=detail.final
	result.total=0.0
	for amount: float in result.components.values(): result.total+=amount
	return result


static func incoming_source_hit(components: Variant,stats: Dictionary,shield: Variant,health: Variant,actor: String="player")->Dictionary:
	var checked := validate_components(components)
	if not checked.ok: return checked
	var profile := source_profile(stats,actor)
	if not profile.ok: return profile
	var packet := Damage.packet(checked.components,["hit"],"incoming_hit")
	var resolved := apply_armour(Damage.resolve(packet,[],profile.effective_resistances),profile.armour)
	var result := settle_resolved(resolved,shield,health)
	if result.ok:
		result.actor=actor
		result.stage=STAGE
		result.raw_resistances=profile.raw_resistances
		result.effective_resistances=profile.effective_resistances
		result.armour=profile.armour
	return result


static func validate_components(components: Variant) -> Dictionary:
	if not components is Dictionary:
		return _failure("Hit components must be an object")
	var copied: Dictionary = {}
	var total: float = 0.0
	for type: Variant in components:
		if not type is String or not Damage.TYPES.has(type):
			return _failure("Unknown damage component: " + str(type))
		if not _amount(components[type]):
			return _failure("Damage component must be a finite nonnegative scalar: " + type)
		var value: float = float(components[type])
		total += value
		if not is_finite(total):
			return _failure("Damage component total overflow")
		copied[type] = value
	return {"ok": true, "reason": "", "components": copied, "total": total}


static func settle_resolved(resolved: Variant, shield: Variant, health: Variant) -> Dictionary:
	# Accept exactly the resolver's existing contract, including its compatibility
	# resistance range (-100%..90%). Never apply the authored fire cap a second time.
	var reason: String = _resources_error(shield, health)
	if not reason.is_empty():
		return _failure(reason)
	if not resolved is Dictionary or resolved.size() != 3 or not resolved.has("total") or not resolved.has("components") or not resolved.has("details"):
		return _failure("Resolved hit must contain only total, components and details")
	if not _amount(resolved.total):
		return _failure("Resolved damage total must be finite and nonnegative")
	var checked: Dictionary = validate_components(resolved.components)
	if not checked.ok:
		return checked
	if not _same_amount(float(resolved.total), float(checked.total)):
		return _failure("Resolved total does not match its components")
	if not resolved.details is Array:
		return _failure("Resolved details must be an array")
	var raw: Dictionary = {}
	var prevented: Dictionary = {}
	var details: Array[Dictionary] = []
	for entry: Variant in resolved.details:
		if not entry is Dictionary:
			return _failure("Resolved component detail must be an object")
		var type: Variant = entry.get("type")
		if not type is String or not checked.components.has(type) or raw.has(type):
			return _failure("Resolved detail has an unknown or repeated damage type")
		if not _amount(entry.get("before_defense")) or not _amount(entry.get("final")):
			return _failure("Resolved detail damage must be finite and nonnegative")
		if not _finite_number(entry.get("resistance")) or float(entry.resistance) < -1.0 or float(entry.resistance) > 0.9:
			return _failure("Resolved resistance is outside the resolver compatibility range")
		if not _same_amount(float(entry.final), float(checked.components[type])):
			return _failure("Resolved detail does not match its final component")
		raw[type] = float(entry.before_defense)
		prevented[type] = float(entry.before_defense) - float(entry.final)
		details.append(entry.duplicate(true))
	if raw.size() != checked.components.size():
		return _failure("Resolved hit is missing component details")
	var total: float = float(checked.total)
	var shield_spent: float = minf(float(shield), total)
	var after_shield: float = maxf(0.0, total - shield_spent)
	var health_lost: float = minf(float(health), after_shield)
	return {"ok": true, "reason": "", "raw_components": raw,
		"components": checked.components, "mitigated_components": prevented,
		"damage_total": total, "shield_spent": shield_spent, "health_lost": health_lost,
		"remaining_shield": float(shield) - shield_spent,
		"remaining_health": float(health) - health_lost,
		"overkill": maxf(0.0, after_shield - health_lost), "details": details}


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _amount(value: Variant) -> bool:
	return _finite_number(value) and float(value) >= 0.0


static func _resources_error(shield: Variant, health: Variant) -> String:
	if not _amount(shield):
		return "Shield must be a finite nonnegative scalar"
	if not _amount(health):
		return "Health must be a finite nonnegative scalar"
	return ""


static func _same_amount(first: float, second: float) -> bool:
	return absf(first - second) <= maxf(0.000001, maxf(absf(first), absf(second)) * 0.000000001)


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
