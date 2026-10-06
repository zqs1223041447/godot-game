extends RefCounted
## Vocabulary37 adds only cold/lightning suffixes to the existing emberhide vest.
## Integer percent ticks use Catalog's single /100 conversion. Frozen fire-only
## definitions and interfaces retain their original eligibility and RNG order.

const Defense = preload("res://docs/qa/v062-rules/frozen/scripts/mechanics/defense_rules.gd")
const MIN_SAVE_VERSION: int = 37
const AFFIX_IDS: Array[String] = ["rimeward", "stormward"]
const STAT_ELEMENTS: Dictionary = {"cold_resistance": "cold", "lightning_resistance": "lightning"}
const AFFIXES: Dictionary = {
	"rimeward": {"name": "护寒", "kind": "suffix", "group": "cold_resistance", "stat": "cold_resistance", "unit": "percent", "label": "冰霜抗性", "slots": ["armor"],
		"stage": "hit_mitigation", "scope": "equipped_character", "actors": ["player", "monster"], "allowed_base_ids": ["emberhide_vest"], "damage_type": "cold",
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 8, "max": 12}, {"tier": 2, "level": 8, "weight": 60, "min": 13, "max": 18}, {"tier": 3, "level": 16, "weight": 30, "min": 19, "max": 25}]},
	"stormward": {"name": "护雷", "kind": "suffix", "group": "lightning_resistance", "stat": "lightning_resistance", "unit": "percent", "label": "闪电抗性", "slots": ["armor"],
		"stage": "hit_mitigation", "scope": "equipped_character", "actors": ["player", "monster"], "allowed_base_ids": ["emberhide_vest"], "damage_type": "lightning",
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 8, "max": 12}, {"tier": 2, "level": 8, "weight": 60, "min": 13, "max": 18}, {"tier": 3, "level": 16, "weight": 30, "min": 19, "max": 25}]},
}
## Append to the historical nine-family order, never modify the old pool.
const POOL_PROFILE: Dictionary = {"base_ids": ["emberhide_vest"],
	"affix_ids": ["rootwell", "deepwell", "lanternveil", "coalglow", "rimeecho", "sparkthread", "wellturn", "trailstep", "emberward", "rimeward", "stormward"], "min_save_version": 37}


## This capability belongs to the source-tree elemental consumer. The older
## Defense.supports_stat/defense_profile contracts intentionally remain fire-only.
static func valid_family(family: Dictionary) -> bool:
	for field: String in ["stat", "group", "kind", "unit", "stage", "scope", "damage_type"]:
		if not family.get(field) is String: return false
	for field: String in ["slots", "allowed_base_ids", "actors"]:
		if not family.get(field) is Array: return false
	if not STAT_ELEMENTS.has(family.stat) or family.group != family.stat \
			or family.damage_type != STAT_ELEMENTS[family.stat] \
			or family.kind != "suffix" or family.unit != "percent" \
			or family.stage != Defense.STAGE or family.scope != "equipped_character" \
			or family.slots != ["armor"] or family.allowed_base_ids != ["emberhide_vest"] \
			or family.actors != ["player", "monster"]:
		return false
	for actor: String in family.actors:
		var profile: Dictionary = Defense.source_profile({family.stat: 0.25}, actor)
		if not profile.ok or profile.raw_resistances.get(family.damage_type) != 0.25 \
				or profile.effective_resistances.get(family.damage_type) != 0.25:
			return false
	return true
