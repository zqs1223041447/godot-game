class_name BuildAffixProfile
extends RefCounted
## Pure four-family vocabulary for v0.42 equipment consumers.
## These values are an initial tunable prototype, not balance proof.
## basis_points divides integer rolls by 10000; existing percent divides by 100.

const MIN_SAVE_VERSION: int = 27
const AFFIX_IDS: Array[String] = [
	"attack_life_leech",
	"attack_mana_leech",
	"global_critical_chance",
	"global_critical_multiplier",
]
const ALLOWED_BASE_IDS: Array[String] = [
	"wayglass_token",
	"pulse_seed",
	"nine_slot_etched_ring",
	"nine_slot_threaded_gloves",
]
const AFFIXES: Dictionary = {
	"attack_life_leech": {
		"name": "血汲", "kind": "prefix", "group": "attack_life_leech",
		"stat": "attack_life_leech", "unit": "basis_points", "label": "攻击伤害偷取为生命",
		"slots": ["charm", "ring", "gloves"],
		"allowed_base_ids": ["wayglass_token", "pulse_seed", "nine_slot_etched_ring", "nine_slot_threaded_gloves"],
		"tiers": [
			{"tier": 1, "level": 1, "weight": 100, "min": 20, "max": 30},
			{"tier": 2, "level": 8, "weight": 60, "min": 31, "max": 45},
			{"tier": 3, "level": 16, "weight": 30, "min": 46, "max": 60},
		],
	},
	"attack_mana_leech": {
		"name": "灵汲", "kind": "prefix", "group": "attack_mana_leech",
		"stat": "attack_mana_leech", "unit": "basis_points", "label": "攻击伤害偷取为魔力",
		"slots": ["charm", "ring", "gloves"],
		"allowed_base_ids": ["wayglass_token", "pulse_seed", "nine_slot_etched_ring", "nine_slot_threaded_gloves"],
		"tiers": [
			{"tier": 1, "level": 1, "weight": 100, "min": 10, "max": 15},
			{"tier": 2, "level": 8, "weight": 60, "min": 16, "max": 25},
			{"tier": 3, "level": 16, "weight": 30, "min": 26, "max": 35},
		],
	},
	"global_critical_chance": {
		"name": "锐察", "kind": "suffix", "group": "global_critical_chance",
		"stat": "crit_chance_increased", "unit": "percent", "label": "全局暴击几率提高",
		"slots": ["charm", "ring", "gloves"],
		"allowed_base_ids": ["wayglass_token", "pulse_seed", "nine_slot_etched_ring", "nine_slot_threaded_gloves"],
		"tiers": [
			{"tier": 1, "level": 1, "weight": 100, "min": 15, "max": 20},
			{"tier": 2, "level": 8, "weight": 60, "min": 21, "max": 30},
			{"tier": 3, "level": 16, "weight": 30, "min": 31, "max": 40},
		],
	},
	"global_critical_multiplier": {
		"name": "重创", "kind": "suffix", "group": "global_critical_multiplier",
		"stat": "crit_multiplier_add", "unit": "percent", "display_unit": "percentage_points",
		"label": "全局暴击伤害倍率", "slots": ["charm", "ring", "gloves"],
		"allowed_base_ids": ["wayglass_token", "pulse_seed", "nine_slot_etched_ring", "nine_slot_threaded_gloves"],
		"tiers": [
			{"tier": 1, "level": 1, "weight": 100, "min": 5, "max": 7},
			{"tier": 2, "level": 8, "weight": 60, "min": 8, "max": 11},
			{"tier": 3, "level": 16, "weight": 30, "min": 12, "max": 15},
		],
	},
}


static func affixes() -> Dictionary:
	return AFFIXES.duplicate(true)


static func affix_ids() -> Array[String]:
	return AFFIX_IDS.duplicate()


static func allowed_base_ids() -> Array[String]:
	return ALLOWED_BASE_IDS.duplicate()
