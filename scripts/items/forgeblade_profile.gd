class_name ForgebladeProfile
extends RefCounted
## Vocabulary34 adds one melee local weapon and reuses six frozen family budgets.
## This profile owns eligibility only; WeaponLocalRules owns physical base damage.

const BASES: Dictionary = {
	"forgeblade": {"name": "锻纹短刃", "slot": "weapon", "size": Vector2i(1, 3),
		"description": "本武器物理单独结算，仅增强裂刃斩直接命中。详情列出基底、本地点数与本地提高。", "stats": {},
		"stage": "weapon_local", "scope": "equipped_weapon", "balance_origin": "original"},
}
const POOL_PROFILE: Dictionary = {
	"base_ids": ["forgeblade"],
	"affix_ids": ["whetstone_edge", "tempered_edge", "deepwell", "wellturn", "global_critical_chance", "global_critical_multiplier"],
	"min_save_version": 34, "balance_origin": "original",
}
const LOCAL_AFFIX_IDS: Array[String] = ["whetstone_edge", "tempered_edge"]
const CRITICAL_AFFIX_IDS: Array[String] = ["global_critical_chance", "global_critical_multiplier"]


## Detached current records preserve every authored field except the explicitly
## expanded base/slot allowlists. Historical constant dictionaries stay frozen.
static func extend_affixes(local_affixes: Dictionary, build_affixes: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in LOCAL_AFFIX_IDS + CRITICAL_AFFIX_IDS:
		var authored: Dictionary = local_affixes[id] if LOCAL_AFFIX_IDS.has(id) else build_affixes[id]
		var current: Dictionary = authored.duplicate(true)
		current.allowed_base_ids.append("forgeblade")
		if not current.slots.has("weapon"):
			current.slots.append("weapon")
		result[id] = current
	return result


static func valid_local_base_ids(base_ids: Array) -> bool:
	return base_ids == ["ashwood_bow"] or base_ids == ["ashwood_bow", "forgeblade"]
