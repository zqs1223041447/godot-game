class_name ChaosResistanceAffixProfile
extends RefCounted
## Vocabulary51 appends one chaos-resistance suffix to the existing etched ring.
## Stored rolls are integer percent ticks; Catalog performs the sole /100 conversion.
## There are only two ring slots: authored gear can supply at most 50% raw chaos resistance.
const MIN_SAVE_VERSION: int = 51
const RING_BASE_ID: String = "nine_slot_etched_ring"
const AFFIX_IDS: Array[String] = ["ring_voidward"]
const AFFIXES: Dictionary = {
	"ring_voidward": {"name": "护虚", "kind": "suffix", "group": "chaos_resistance", "stat": "chaos_resistance", "unit": "percent", "label": "混沌抗性", "slots": ["ring"],
		"stage": "hit_mitigation", "scope": "equipped_character", "actors": ["player", "monster"], "allowed_base_ids": [RING_BASE_ID], "damage_type": "chaos",
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 8, "max": 12}, {"tier": 2, "level": 8, "weight": 60, "min": 13, "max": 18}, {"tier": 3, "level": 16, "weight": 30, "min": 19, "max": 25}]},
}
## Preserve every existing base/family and its order before appending the new family.
const POOL_PROFILE: Dictionary = {
	"base_ids": ["nine_slot_etched_ring", "nine_slot_trail_boots", "nine_slot_folded_belt", "nine_slot_threaded_gloves", "nine_slot_slate_helmet"],
	"affix_ids": ["nine_slot_prefix_vitality", "nine_slot_prefix_clarity", "nine_slot_prefix_aegis", "nine_slot_suffix_endurance", "nine_slot_suffix_mana_flow", "nine_slot_suffix_stride", "nine_slot_suffix_skill_row", "attack_life_leech", "attack_mana_leech", "global_critical_chance", "global_critical_multiplier", "glove_accuracy", "ring_emberward", "ring_rimeward", "ring_stormward", "ring_voidward"],
	"min_save_version": MIN_SAVE_VERSION,
}


static func valid_family(family: Dictionary) -> bool:
	for field: String in ["stat", "group", "kind", "unit", "stage", "scope", "damage_type"]:
		if not family.get(field) is String: return false
	for field: String in ["slots", "allowed_base_ids", "actors"]:
		if not family.get(field) is Array: return false
	return family.stat == "chaos_resistance" and family.group == "chaos_resistance" \
		and family.kind == "suffix" and family.unit == "percent" and family.damage_type == "chaos" \
		and family.stage == "hit_mitigation" and family.scope == "equipped_character" \
		and family.slots == ["ring"] and family.allowed_base_ids == [RING_BASE_ID] \
		and family.actors == ["player", "monster"]
