class_name FrostLockRules
extends RefCounted
## Frozen player frost-lock policy. Eligibility reads settled cold shield/health
## loss; the caller owns settlement, spawn protection, and current actor liveness.
const PLAYER_POLICY: Dictionary = {
	"duration_by_rarity": {"normal": 0.60, "magic": 0.60, "rare": 0.35, "boss": 0.20},
	"immunity_seconds": 1.50, "hit_multiplier": 0.75, "mana_multiplier": 1.20,
}
const POLICY_KEYS: Array[String] = [
	"duration_by_rarity", "immunity_seconds", "hit_multiplier", "mana_multiplier",
]
const RARITY_KEYS: Array[String] = ["normal", "magic", "rare", "boss"]


static func policy_error(policy: Variant) -> String:
	if not policy is Dictionary or policy.size() != POLICY_KEYS.size():
		return "Frost-lock policy must have the exact frozen player shape"
	for key: Variant in policy:
		if typeof(key) != TYPE_STRING or key not in POLICY_KEYS:
			return "Unknown or non-String frost-lock policy field"
	var durations: Variant = policy.get("duration_by_rarity")
	if not durations is Dictionary or durations.size() != RARITY_KEYS.size():
		return "Frost-lock durations must have the exact frozen rarity shape"
	for rarity: Variant in durations:
		if typeof(rarity) != TYPE_STRING or rarity not in RARITY_KEYS:
			return "Unknown or non-String frost-lock rarity"
		if not positive_number(durations[rarity]):
			return "Frost-lock durations must be finite positive numbers"
		if float(durations[rarity]) != float(PLAYER_POLICY.duration_by_rarity[rarity]):
			return "Frost-lock durations must match the frozen player policy"
	for key: String in ["immunity_seconds", "hit_multiplier", "mana_multiplier"]:
		if not positive_number(policy.get(key)):
			return "Frost-lock policy values must be finite positive numbers"
		if float(policy[key]) != float(PLAYER_POLICY[key]):
			return "Frost-lock policy must match the frozen player policy"
	return ""


## The amount is actual cold shield + health loss, never tooltip/base damage.
## A compiled profile includes `enabled`; pass its exact snapshot policy here.
static func eligible(packet: Variant, policy: Variant, actual_cold_loss: Variant,
		target_alive: Variant) -> bool:
	if not policy_error(policy).is_empty() or not packet is Dictionary:
		return false
	if typeof(target_alive) != TYPE_BOOL or not target_alive or not positive_number(actual_cold_loss):
		return false
	if typeof(packet.get("skill_id")) != TYPE_STRING or packet.skill_id != "frost" \
			or typeof(packet.get("role")) != TYPE_STRING or packet.role != "projectile":
		return false
	var tags: Variant = packet.get("tags")
	if not tags is Array or not tags.has("hit") or tags.has("dot"):
		return false
	for tag: Variant in tags:
		if typeof(tag) != TYPE_STRING: return false
	return true


static func positive_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0
