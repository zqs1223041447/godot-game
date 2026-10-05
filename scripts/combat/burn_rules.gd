class_name BurnRules
extends RefCounted
## Original prototype policies. The input fire hit is already fully resolved
## before defense; no hit, projectile, critical, or leech rule runs here.
const MAX_DURATION: float = 60.0
const PLAYER_POLICY: Dictionary = {
	"duration": 3.0, "rate_fraction": 0.30,
	"hit_multiplier": 0.75, "mana_multiplier": 1.20,
}
const ENEMY_POLICY: Dictionary = {
	"duration": 3.0, "rate_fraction": 1.0 / 3.0,
	"upfront_fire_multiplier": 0.50,
}
const POLICY_KEYS: Array[String] = [
	"duration", "rate_fraction", "hit_multiplier", "mana_multiplier", "upfront_fire_multiplier",
]


static func from_fire_hit(fire_before_defense: Variant, policy: Variant, fire_dot_multiplier: Variant = 0.0) -> Dictionary:
	var reason: String = policy_error(policy)
	if not reason.is_empty():
		return _result(0.0, 0.0, reason)
	if not positive_number(fire_before_defense):
		return _result(0.0, 0.0, "Fire before defense must be a finite positive number")
	if not _nonnegative_number(fire_dot_multiplier):
		return _result(0.0, 0.0, "Fire DoT multiplier must be finite and nonnegative")
	# Optional policy multipliers describe the upstream hit/cost only. Applying
	# any of them here would charge the same hit modifier a second time.
	var raw_dps: float = raw_fire_dps(float(fire_before_defense), float(policy.rate_fraction), float(fire_dot_multiplier))
	var duration: float = float(policy.duration)
	reason = rate_duration_error(raw_dps, duration)
	return _result(raw_dps, duration) if reason.is_empty() else _result(0.0, 0.0, reason)


static func policy_error(policy: Variant) -> String:
	if not policy is Dictionary or not policy.has_all(["duration", "rate_fraction"]):
		return "Burn policy requires duration and rate_fraction"
	for key: Variant in policy:
		if typeof(key) != TYPE_STRING or key not in POLICY_KEYS:
			return "Unknown or non-String burn policy field"
		if not positive_number(policy[key]):
			return "Burn policy values must be finite positive numbers"
	if float(policy.duration) > MAX_DURATION:
		return "Burn duration exceeds the 60-second bound"
	return ""


static func rate_duration_error(raw_dps: Variant, duration: Variant) -> String:
	if not positive_number(raw_dps) or not positive_number(duration):
		return "Burn DPS and duration must be finite positive numbers"
	if float(duration) > MAX_DURATION:
		return "Burn duration exceeds the 60-second bound"
	var budget: float = float(raw_dps) * float(duration)
	if not is_finite(budget) or budget <= 0.0:
		return "Burn lifetime amount is not representable"
	return ""


static func positive_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0


static func _result(raw_dps: float, duration: float, reason: String = "") -> Dictionary:
	return {"ok": reason.is_empty(), "reason": reason, "raw_dps": raw_dps, "duration": duration}


## The source stat is additive within this one family. Existing fire/global/
## hit/critical factors are already present in fire_before_defense. The runtime
## and compiler preview share this exact expression; zero skips multiplication
## so previously compiled values retain their original floating-point bytes.
static func raw_fire_dps(fire_before_defense: float, rate_fraction: float, multiplier: float = 0.0) -> float:
	var result: float = fire_before_defense * rate_fraction
	return result if multiplier == 0.0 else result * (1.0 + multiplier)


static func multiplier_from_stats(stats: Dictionary) -> Dictionary:
	var amount: Variant = stats.get("fire_dot_multiplier_add", 0.0)
	if _nonnegative_number(amount) and float(amount) == 0.0: return {}
	# Preserve invalid input for the compiler's rejection; do not coerce or hide it.
	return {"fire_dot_multiplier": amount}


static func snapshot_multiplier_error(snapshot: Dictionary) -> String:
	if not snapshot.has("fire_dot_multiplier"): return ""
	return "" if positive_number(snapshot.fire_dot_multiplier) else "Fire DoT snapshot multiplier must be finite and positive"


static func _nonnegative_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0
