extends RefCounted
## Pure, opt-in data for a future nine-slot equipment consumer.
## This file deliberately does not extend EquipmentCatalog or own generation.

const _BASES: Dictionary = {
	"nine_slot_etched_ring": {"name": "纹刻指环", "slot": "ring", "size": Vector2i(1, 1),
		"description": "最大生命 +4，最大魔力 +2。", "stats": {"max_health": 4.0, "max_mana": 2.0}},
	"nine_slot_trail_boots": {"name": "踏纹短靴", "slot": "boots", "size": Vector2i(2, 2),
		"description": "最大生命 +3，移动速度 +1。", "stats": {"max_health": 3.0, "move_speed": 1.0}},
	"nine_slot_folded_belt": {"name": "折纹腰带", "slot": "belt", "size": Vector2i(2, 1),
		"description": "最大生命 +4，最大护盾 +2。", "stats": {"max_health": 4.0, "max_shield": 2.0}},
	"nine_slot_threaded_gloves": {"name": "织纹手套", "slot": "gloves", "size": Vector2i(2, 2),
		"description": "最大魔力 +2，魔力恢复 +0.1 / 秒。", "stats": {"max_mana": 2.0, "mana_regen": 0.1}},
	"nine_slot_slate_helmet": {"name": "石脊头盔", "slot": "helmet", "size": Vector2i(2, 2),
		"description": "最大生命 +4，最大护盾 +2。", "stats": {"max_health": 4.0, "max_shield": 2.0}},
}

const _AFFIXES: Dictionary = {
	"nine_slot_prefix_vitality": {"name": "坚生", "kind": "prefix", "group": "nine_slot_life_capacity", "stat": "max_health", "unit": "flat", "label": "最大生命", "slots": ["ring", "boots", "belt", "gloves", "helmet"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 4, "max": 6}, {"tier": 2, "level": 8, "weight": 60, "min": 7, "max": 9}, {"tier": 3, "level": 16, "weight": 30, "min": 10, "max": 12}]},
	"nine_slot_prefix_clarity": {"name": "澄意", "kind": "prefix", "group": "nine_slot_mana_capacity", "stat": "max_mana", "unit": "flat", "label": "最大魔力", "slots": ["ring", "boots", "belt", "gloves", "helmet"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 3, "max": 4}, {"tier": 2, "level": 8, "weight": 60, "min": 5, "max": 7}, {"tier": 3, "level": 16, "weight": 30, "min": 8, "max": 10}]},
	"nine_slot_prefix_aegis": {"name": "厚障", "kind": "prefix", "group": "nine_slot_shield_capacity", "stat": "max_shield", "unit": "flat", "label": "最大护盾", "slots": ["ring", "boots", "belt", "gloves", "helmet"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 2, "max": 3}, {"tier": 2, "level": 8, "weight": 60, "min": 4, "max": 6}, {"tier": 3, "level": 16, "weight": 30, "min": 7, "max": 9}]},
	"nine_slot_suffix_endurance": {"name": "耐守", "kind": "suffix", "group": "nine_slot_endurance", "stat": "max_health", "unit": "flat", "label": "最大生命", "slots": ["ring", "boots", "belt", "gloves", "helmet"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 2, "max": 3}, {"tier": 2, "level": 8, "weight": 60, "min": 4, "max": 5}, {"tier": 3, "level": 16, "weight": 30, "min": 6, "max": 7}]},
	"nine_slot_suffix_mana_flow": {"name": "泉行", "kind": "suffix", "group": "nine_slot_mana_recovery", "stat": "mana_regen_increased", "unit": "percent", "label": "魔力恢复速度提高", "slots": ["ring", "boots", "belt", "gloves", "helmet"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 2, "max": 3}, {"tier": 2, "level": 8, "weight": 60, "min": 4, "max": 5}, {"tier": 3, "level": 16, "weight": 30, "min": 6, "max": 8}]},
	"nine_slot_suffix_stride": {"name": "轻步", "kind": "suffix", "group": "nine_slot_movement", "stat": "move_speed_increased", "unit": "percent", "label": "移动速度提高", "slots": ["ring", "boots", "belt", "gloves", "helmet"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 1, "max": 2}, {"tier": 2, "level": 8, "weight": 60, "min": 3, "max": 4}, {"tier": 3, "level": 16, "weight": 30, "min": 5, "max": 6}]},
	"nine_slot_suffix_skill_row": {"name": "引技", "kind": "suffix", "group": "nine_slot_additional_skill_slot", "stat": "additional_skill_slots", "unit": "flat", "label": "额外技能行", "slots": ["belt", "helmet"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 1, "max": 1}, {"tier": 2, "level": 8, "weight": 60, "min": 1, "max": 1}, {"tier": 3, "level": 16, "weight": 30, "min": 1, "max": 1}]},
}

const _POOL_PROFILE: Dictionary = {
	"base_ids": ["nine_slot_etched_ring", "nine_slot_trail_boots", "nine_slot_folded_belt", "nine_slot_threaded_gloves", "nine_slot_slate_helmet"],
	"affix_ids": ["nine_slot_prefix_vitality", "nine_slot_prefix_clarity", "nine_slot_prefix_aegis", "nine_slot_suffix_endurance", "nine_slot_suffix_mana_flow", "nine_slot_suffix_stride", "nine_slot_suffix_skill_row"],
	"min_save_version": 14,
}


static func bases() -> Dictionary:
	return _BASES.duplicate(true)


static func affixes() -> Dictionary:
	return _AFFIXES.duplicate(true)


static func pool_profile() -> Dictionary:
	return _POOL_PROFILE.duplicate(true)
