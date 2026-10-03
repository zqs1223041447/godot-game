class_name AttackHitRules
extends RefCounted
## Accuracy/evasion affect attack admission only, before resistance/shield/life.
## No global RNG or permanent state: a defender-owned entropy value is advanced.
## Initial entropy 50 is this game's deterministic choice, not a PoE RNG claim.
static func monster_profile(kind: int) -> Dictionary:
	# Small authored encounter distinction, not a copy of PoE's level tables.
	return {"accuracy":100.0,"evasion":320.0 if kind==1 else 0.0,"armour":0.0}


static func chance(accuracy: float,evasion: float) -> float:
	if not is_finite(accuracy) or not is_finite(evasion) or accuracy < 0.0 or evasion < 0.0: return -1.0
	if evasion <= 0.0: return 1.0
	if accuracy <= 0.0: return 0.05
	return clampf(roundf(125.0*accuracy/(accuracy+pow(evasion/5.0,0.9))),5.0,100.0)/100.0


static func resolve(accuracy: float,evasion: float,entropy: float = 50.0) -> Dictionary:
	var probability := chance(accuracy,evasion)
	if probability < 0.0 or not is_finite(entropy) or entropy < 0.0 or entropy >= 100.0:
		return {"ok":false,"hit":false,"chance":0.0,"entropy":entropy}
	var accumulated := entropy+probability*100.0
	var hit := accumulated >= 100.0
	return {"ok":true,"hit":hit,"chance":probability,"entropy":accumulated-100.0 if hit else accumulated}
