class_name DefenseRatingAffixProfile
extends RefCounted
## Vocabulary39 adds only two flat rating prefixes to the existing emberhide vest.
## Integer points stay the same float value in Catalog's stats. SourceTreeRuntime
## applies global increases once after the equipped item stats have been summed.

const MIN_SAVE_VERSION: int = 39
const AFFIX_IDS: Array[String] = ["ironhide", "mistweave"]
const STAT_STAGES: Dictionary = {"armour": "hit_mitigation", "evasion": "hit_admission"}
const AFFIXES: Dictionary = {
	"ironhide": {"name": "铁革", "kind": "prefix", "group": "armour_rating", "stat": "armour", "unit": "flat", "label": "护甲", "slots": ["armor"],
		"stage": "hit_mitigation", "scope": "equipped_character", "actors": ["player", "monster"], "allowed_base_ids": ["emberhide_vest"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 30, "max": 50}, {"tier": 2, "level": 8, "weight": 60, "min": 55, "max": 80}, {"tier": 3, "level": 16, "weight": 30, "min": 85, "max": 120}]},
	"mistweave": {"name": "雾织", "kind": "prefix", "group": "evasion_rating", "stat": "evasion", "unit": "flat", "label": "闪避值", "slots": ["armor"],
		"stage": "hit_admission", "scope": "equipped_character", "actors": ["player", "monster"], "allowed_base_ids": ["emberhide_vest"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 200, "max": 260}, {"tier": 2, "level": 8, "weight": 60, "min": 270, "max": 350}, {"tier": 3, "level": 16, "weight": 30, "min": 360, "max": 450}]},
}
## Append to the frozen37 order. Five eligible prefixes compete for three slots.
const POOL_PROFILE: Dictionary = {"base_ids": ["emberhide_vest"],
	"affix_ids": ["rootwell", "deepwell", "lanternveil", "coalglow", "rimeecho", "sparkthread", "wellturn", "trailstep", "emberward", "rimeward", "stormward", "ironhide", "mistweave"], "min_save_version": 39}


static func valid_family(family: Dictionary) -> bool:
	for field: String in ["stat", "group", "kind", "unit", "stage", "scope"]:
		if not family.get(field) is String: return false
	for field: String in ["slots", "allowed_base_ids", "actors"]:
		if not family.get(field) is Array: return false
	return STAT_STAGES.has(family.stat) and family.group == family.stat + "_rating" \
		and family.stage == STAT_STAGES[family.stat] and family.kind == "prefix" \
		and family.unit == "flat" and family.scope == "equipped_character" \
		and family.slots == ["armor"] and family.allowed_base_ids == ["emberhide_vest"] \
		and family.actors == ["player", "monster"]
