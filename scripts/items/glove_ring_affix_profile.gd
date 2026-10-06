class_name GloveRingAffixProfile
extends RefCounted
## Vocabulary46 adds one glove accuracy prefix and three ring resistance suffixes.
## Existing families stay frozen. Ring budgets are copied from the authored
## armour families; only their slot/base eligibility changes in the new records.

const MIN_SAVE_VERSION: int = 46
const GLOVE_BASE_ID: String = "nine_slot_threaded_gloves"
const RING_BASE_ID: String = "nine_slot_etched_ring"
const AFFIX_IDS: Array[String] = ["glove_accuracy", "ring_emberward", "ring_rimeward", "ring_stormward"]
const RESISTANCE_SOURCE_IDS: Dictionary = {"ring_emberward": "emberward", "ring_rimeward": "rimeward", "ring_stormward": "stormward"}
const RESISTANCE_STATS: Array[String] = ["fire_resistance", "cold_resistance", "lightning_resistance"]
const ACCURACY_AFFIXES: Dictionary = {
	"glove_accuracy": {"name": "精瞄", "kind": "prefix", "group": "accuracy_rating", "stat": "accuracy", "unit": "flat", "label": "命中值", "slots": ["gloves"],
		"stage": "hit_admission", "scope": "equipped_character", "actors": ["player", "monster"], "allowed_base_ids": [GLOVE_BASE_ID],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 35, "max": 60}, {"tier": 2, "level": 8, "weight": 60, "min": 70, "max": 110}, {"tier": 3, "level": 16, "weight": 30, "min": 120, "max": 160}]},
}
## Preserve all v27 base/family ordering before appending the four new families.
const POOL_PROFILE: Dictionary = {
	"base_ids": ["nine_slot_etched_ring", "nine_slot_trail_boots", "nine_slot_folded_belt", "nine_slot_threaded_gloves", "nine_slot_slate_helmet"],
	"affix_ids": ["nine_slot_prefix_vitality", "nine_slot_prefix_clarity", "nine_slot_prefix_aegis", "nine_slot_suffix_endurance", "nine_slot_suffix_mana_flow", "nine_slot_suffix_stride", "nine_slot_suffix_skill_row", "attack_life_leech", "attack_mana_leech", "global_critical_chance", "global_critical_multiplier", "glove_accuracy", "ring_emberward", "ring_rimeward", "ring_stormward"],
	"min_save_version": MIN_SAVE_VERSION,
}


static func build_affixes(defense_affixes: Dictionary, elemental_affixes: Dictionary) -> Dictionary:
	var result: Dictionary = ACCURACY_AFFIXES.duplicate(true)
	for id: String in RESISTANCE_SOURCE_IDS:
		var source_id: String = RESISTANCE_SOURCE_IDS[id]
		var source: Dictionary = defense_affixes[source_id] if defense_affixes.has(source_id) else elemental_affixes[source_id]
		var family: Dictionary = source.duplicate(true)
		family.slots = ["ring"]
		family.allowed_base_ids = [RING_BASE_ID]
		result[id] = family
	return result


static func valid_family(family: Dictionary) -> bool:
	for field: String in ["stat", "group", "kind", "unit", "stage", "scope"]:
		if not family.get(field) is String: return false
	for field: String in ["slots", "allowed_base_ids", "actors"]:
		if not family.get(field) is Array: return false
	if family.scope != "equipped_character" or family.actors != ["player", "monster"]:
		return false
	if family.stat == "accuracy":
		return family.group == "accuracy_rating" and family.kind == "prefix" and family.unit == "flat" \
			and family.stage == "hit_admission" and family.slots == ["gloves"] and family.allowed_base_ids == [GLOVE_BASE_ID]
	if not RESISTANCE_STATS.has(family.stat) or family.group != family.stat \
			or family.kind != "suffix" or family.unit != "percent" or family.stage != "hit_mitigation" \
			or family.slots != ["ring"] or family.allowed_base_ids != [RING_BASE_ID]:
		return false
	# Fire's historical family has no damage_type field; preserve that shape.
	return not family.has("damage_type") if family.stat == "fire_resistance" else family.get("damage_type") == family.stat.trim_suffix("_resistance")
