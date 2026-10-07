extends RefCounted
## Original equipment and immutable ordered loot profiles; reference exports never enter runtime.
## BASES/AFFIXES and generate() remain the frozen six-base/twelve-family legacy pool.
## Rolls store integer points / percentage ticks; runtime percentages are ticks / 100.
## Historical base "damage" remains the character scalar; local weapon terms are separate.

const DefenseRules = preload("res://scripts/mechanics/defense_rules.gd")
const WeaponLocalRules = preload("res://scripts/items/weapon_local_rules.gd")
const NineSlotProfile = preload("res://scripts/items/nine_slot_equipment_profile.gd")
const NINE_SLOT_BASES: Dictionary = NineSlotProfile._BASES
const NINE_SLOT_AFFIXES: Dictionary = NineSlotProfile._AFFIXES
const BuildAffixes = preload("res://scripts/items/build_affix_profile.gd")
const ForgebladeProfile = preload("res://scripts/items/forgeblade_profile.gd")
const ElementalDefense = preload("res://scripts/items/elemental_defense_affix_profile.gd")
const DefenseRatings = preload("res://scripts/items/defense_rating_affix_profile.gd")
const GloveRingAffixes = preload("res://scripts/items/glove_ring_affix_profile.gd")
const CURRENT_VOCABULARY: int = 46
const CANONICAL_LOOT_PROFILE_ID: String = "canonical_v46"
const CURRENT_DEFENSE_POOL_ID: String = "defense_v39"
const MIN_ITEM_LEVEL: int = 1
const MAX_ITEM_LEVEL: int = 30
const MAX_SERIAL: int = 999999999
const BASES: Dictionary = {
	"cinder_reed": {"name": "烬芦杖", "slot": "weapon", "size": Vector2i(1, 3),
		"description": "基础伤害 +3，魔力恢复 +0.25 / 秒。基础伤害为角色通用加值。", "stats": {"damage": 3.0, "mana_regen": 0.25}},
	"gale_spindle": {"name": "岚纺刃", "slot": "weapon", "size": Vector2i(1, 3),
		"description": "基础伤害 +2，攻击速度 +0.08 / 秒。基础伤害为角色通用加值。", "stats": {"damage": 2.0, "attack_speed": 0.08}},
	"woven_bastion": {"name": "绳垒衣", "slot": "armor", "size": Vector2i(2, 3),
		"description": "最大生命 +12，最大护盾 +5。护盾为角色全局加值。", "stats": {"max_health": 12.0, "max_shield": 5.0}},
	"tidebound_coat": {"name": "潮缄袍", "slot": "armor", "size": Vector2i(2, 3),
		"description": "最大护盾 +10，护盾恢复 +0.6 / 秒。护盾为角色全局加值。", "stats": {"max_shield": 10.0, "shield_regen": 0.6}},
	"wayglass_token": {"name": "途镜坠", "slot": "charm", "size": Vector2i(1, 1),
		"description": "最大魔力 +6，魔力恢复 +0.3 / 秒。", "stats": {"max_mana": 6.0, "mana_regen": 0.3}},
	"pulse_seed": {"name": "脉籽符", "slot": "charm", "size": Vector2i(1, 1),
		"description": "最大生命 +8，移动速度 +3。", "stats": {"max_health": 8.0, "move_speed": 3.0}},
}
const RARITIES: Dictionary = {
	"normal": {"name": "普通", "color": Color("e1e7ef"), "weight": 30, "min_affixes": 0, "max_affixes": 0, "max_prefixes": 0, "max_suffixes": 0},
	"magic": {"name": "魔法", "color": Color("8eb8ff"), "weight": 55, "min_affixes": 1, "max_affixes": 2, "max_prefixes": 1, "max_suffixes": 1},
	"rare": {"name": "稀有", "color": Color("e9ce7c"), "weight": 15, "min_affixes": 4, "max_affixes": 6, "max_prefixes": 3, "max_suffixes": 3},
}
## T1 is the entry tier, T2 unlocks at 8, T3 at 16. These are ORIGINAL tier labels.
## A group's tiers are mutually exclusive. Slots are an explicit eligibility allowlist.
## Each selected (family, tier) carries its own positive weight and inclusive tick range.
const AFFIXES: Dictionary = {
	"rootwell": {"name": "根泉", "kind": "prefix", "group": "life_capacity", "stat": "max_health", "unit": "flat", "label": "最大生命", "slots": ["armor", "charm"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 8, "max": 14}, {"tier": 2, "level": 8, "weight": 60, "min": 15, "max": 22}, {"tier": 3, "level": 16, "weight": 30, "min": 23, "max": 32}]},
	"deepwell": {"name": "深汲", "kind": "prefix", "group": "mana_capacity", "stat": "max_mana", "unit": "flat", "label": "最大魔力", "slots": ["weapon", "armor", "charm"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 5, "max": 9}, {"tier": 2, "level": 8, "weight": 60, "min": 10, "max": 15}, {"tier": 3, "level": 16, "weight": 30, "min": 16, "max": 22}]},
	"lanternveil": {"name": "灯帷", "kind": "prefix", "group": "shield_capacity", "stat": "max_shield", "unit": "flat", "label": "全局最大护盾", "slots": ["armor", "charm"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 5, "max": 9}, {"tier": 2, "level": 8, "weight": 60, "min": 10, "max": 15}, {"tier": 3, "level": 16, "weight": 30, "min": 16, "max": 22}]},
	"runesong": {"name": "符歌", "kind": "prefix", "group": "spell_amplification", "stat": "spell_increased", "unit": "percent", "label": "法术伤害提高", "slots": ["weapon", "charm"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 4, "max": 7}, {"tier": 2, "level": 8, "weight": 60, "min": 8, "max": 12}, {"tier": 3, "level": 16, "weight": 30, "min": 13, "max": 18}]},
	"prismedge": {"name": "折辉", "kind": "prefix", "group": "attack_elemental_amplification", "stat": "attack_elemental_increased", "unit": "percent", "label": "攻击元素伤害提高", "slots": ["weapon", "charm"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 4, "max": 7}, {"tier": 2, "level": 8, "weight": 60, "min": 8, "max": 12}, {"tier": 3, "level": 16, "weight": 30, "min": 13, "max": 18}]},
	"farweave": {"name": "远织", "kind": "prefix", "group": "projectile_amplification", "stat": "projectile_increased", "unit": "percent", "label": "投射物伤害提高（不含独立爆炸）", "slots": ["weapon", "charm"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 4, "max": 7}, {"tier": 2, "level": 8, "weight": 60, "min": 8, "max": 12}, {"tier": 3, "level": 16, "weight": 30, "min": 13, "max": 18}]},
	"coalglow": {"name": "藏炭", "kind": "suffix", "group": "fire_amplification", "stat": "fire_increased", "unit": "percent", "label": "火焰伤害提高", "slots": ["weapon", "armor", "charm"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 5, "max": 8}, {"tier": 2, "level": 8, "weight": 60, "min": 9, "max": 14}, {"tier": 3, "level": 16, "weight": 30, "min": 15, "max": 20}]},
	"rimeecho": {"name": "霜回", "kind": "suffix", "group": "cold_amplification", "stat": "cold_increased", "unit": "percent", "label": "冰霜伤害提高", "slots": ["weapon", "armor", "charm"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 5, "max": 8}, {"tier": 2, "level": 8, "weight": 60, "min": 9, "max": 14}, {"tier": 3, "level": 16, "weight": 30, "min": 15, "max": 20}]},
	"sparkthread": {"name": "引霆", "kind": "suffix", "group": "lightning_amplification", "stat": "lightning_increased", "unit": "percent", "label": "闪电伤害提高", "slots": ["weapon", "armor", "charm"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 5, "max": 8}, {"tier": 2, "level": 8, "weight": 60, "min": 9, "max": 14}, {"tier": 3, "level": 16, "weight": 30, "min": 15, "max": 20}]},
	"wellturn": {"name": "泉旋", "kind": "suffix", "group": "mana_recovery", "stat": "mana_regen_increased", "unit": "percent", "label": "魔力恢复速度提高", "slots": ["weapon", "armor", "charm"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 3, "max": 5}, {"tier": 2, "level": 8, "weight": 60, "min": 6, "max": 9}, {"tier": 3, "level": 16, "weight": 30, "min": 10, "max": 14}]},
	"trailstep": {"name": "循迹", "kind": "suffix", "group": "movement_timing", "stat": "move_speed_increased", "unit": "percent", "label": "移动速度提高", "slots": ["armor", "charm"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 1, "max": 2}, {"tier": 2, "level": 8, "weight": 60, "min": 3, "max": 4}, {"tier": 3, "level": 16, "weight": 30, "min": 5, "max": 6}]},
	"beatlink": {"name": "连拍", "kind": "suffix", "group": "attack_timing", "stat": "attack_speed_increased", "unit": "percent", "label": "普通攻击速度提高", "slots": ["weapon", "charm"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 2, "max": 3}, {"tier": 2, "level": 8, "weight": 60, "min": 4, "max": 6}, {"tier": 3, "level": 16, "weight": 30, "min": 7, "max": 9}]},
}


## Separate opt-in vocabulary: existing bases never gain these four prefix families.
const EXPANSION_BASES: Dictionary = {
	"runewood_focus": {"name": "符木法器", "slot": "weapon", "size": Vector2i(1, 3),
		"description": "最大魔力 +8，魔力恢复 +0.25 / 秒。附加伤害仅作用于词缀指定的攻击或法术命中。", "stats": {"max_mana": 8.0, "mana_regen": 0.25}},
}
const EXPANSION_AFFIXES: Dictionary = {
	"attack_added_physical": {"name": "砾刻", "kind": "prefix", "group": "attack_added_physical", "stat": "attack_added_physical", "unit": "flat", "label": "攻击命中附加物理伤害", "slots": ["weapon"],
		"stage": "skill_added_damage", "scope": "equipped_character", "required_tags": ["hit", "attack"], "damage_type": "physical", "allowed_base_ids": ["runewood_focus"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 1, "max": 2}, {"tier": 2, "level": 8, "weight": 60, "min": 3, "max": 4}, {"tier": 3, "level": 16, "weight": 30, "min": 5, "max": 6}]},
	"attack_added_fire": {"name": "焰刻", "kind": "prefix", "group": "attack_added_fire", "stat": "attack_added_fire", "unit": "flat", "label": "攻击命中附加火焰伤害", "slots": ["weapon"],
		"stage": "skill_added_damage", "scope": "equipped_character", "required_tags": ["hit", "attack"], "damage_type": "fire", "allowed_base_ids": ["runewood_focus"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 1, "max": 2}, {"tier": 2, "level": 8, "weight": 60, "min": 3, "max": 4}, {"tier": 3, "level": 16, "weight": 30, "min": 5, "max": 6}]},
	"spell_added_cold": {"name": "霜铭", "kind": "prefix", "group": "spell_added_cold", "stat": "spell_added_cold", "unit": "flat", "label": "法术命中附加冰霜伤害", "slots": ["weapon"],
		"stage": "skill_added_damage", "scope": "equipped_character", "required_tags": ["hit", "spell"], "damage_type": "cold", "allowed_base_ids": ["runewood_focus"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 1, "max": 2}, {"tier": 2, "level": 8, "weight": 60, "min": 3, "max": 4}, {"tier": 3, "level": 16, "weight": 30, "min": 5, "max": 6}]},
	"spell_added_lightning": {"name": "雷铭", "kind": "prefix", "group": "spell_added_lightning", "stat": "spell_added_lightning", "unit": "flat", "label": "法术命中附加闪电伤害", "slots": ["weapon"],
		"stage": "skill_added_damage", "scope": "equipped_character", "required_tags": ["hit", "spell"], "damage_type": "lightning", "allowed_base_ids": ["runewood_focus"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 1, "max": 2}, {"tier": 2, "level": 8, "weight": 60, "min": 3, "max": 4}, {"tier": 3, "level": 16, "weight": 30, "min": 5, "max": 6}]},
}
const ADDED_STAT_TYPES: Dictionary = {
	"attack_added_physical": ["attack", "physical"], "attack_added_fire": ["attack", "fire"],
	"spell_added_cold": ["spell", "cold"], "spell_added_lightning": ["spell", "lightning"],
}
const EXPANSION_LOOT_PERCENT: int = 25


## A separate defense vocabulary never extends either historical dictionary.
const DEFENSE_BASES: Dictionary = {
	"emberhide_vest": {"name": "灰烬皮甲", "slot": "armor", "size": Vector2i(2, 3),
		"description": "最大生命 +8，火焰抗性 +15%。火焰抗性降低火焰命中与燃烧伤害；默认上限75%，最大抗性天赋可提高至本游戏安全上限83%，仍需另外取得足够原始抗性。", "stats": {"max_health": 8.0, "fire_resistance": 0.15},
		"stage": "hit_mitigation", "scope": "equipped_character", "actors": ["player", "monster"]},
}
const DEFENSE_AFFIXES: Dictionary = {
	"emberward": {"name": "护火", "kind": "suffix", "group": "fire_resistance", "stat": "fire_resistance", "unit": "percent", "label": "火焰抗性", "slots": ["armor"],
		"stage": "hit_mitigation", "scope": "equipped_character", "actors": ["player", "monster"], "allowed_base_ids": ["emberhide_vest"],
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 8, "max": 12}, {"tier": 2, "level": 8, "weight": 60, "min": 13, "max": 18}, {"tier": 3, "level": 16, "weight": 30, "min": 19, "max": 25}]},
}
## ORIGINAL game balance, not imported reference values. These prefixes compete
## with the four eligible legacy weapon prefixes for the same three rare slots.
const LOCAL_WEAPON_BASES: Dictionary = {
	"ashwood_bow": {"name": "白蜡长弓", "slot": "weapon", "size": Vector2i(2, 3),
		"description": "本武器物理单独结算，仅增强普攻和龙卷箭体。详情列出基底、本地点数与本地提高。", "stats": {},
		"stage": "weapon_local", "scope": "equipped_weapon", "balance_origin": "original"},
}
const LOCAL_WEAPON_AFFIXES: Dictionary = {
	"whetstone_edge": {"name": "砥刃", "kind": "prefix", "group": "weapon_added_physical", "stat": "weapon_added_physical", "unit": "flat", "label": "本武器附加物理伤害", "slots": ["weapon"],
		"stage": "weapon_local", "scope": "equipped_weapon", "damage_type": "physical", "allowed_base_ids": ["ashwood_bow"], "balance_origin": "original",
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 1, "max": 2}, {"tier": 2, "level": 8, "weight": 60, "min": 3, "max": 4}, {"tier": 3, "level": 16, "weight": 30, "min": 5, "max": 6}]},
	"tempered_edge": {"name": "淬锋", "kind": "prefix", "group": "weapon_physical_increased", "stat": "weapon_physical_increased", "unit": "percent", "label": "本武器物理伤害提高", "slots": ["weapon"],
		"stage": "weapon_local", "scope": "equipped_weapon", "damage_type": "physical", "allowed_base_ids": ["ashwood_bow"], "balance_origin": "original",
		"tiers": [{"tier": 1, "level": 1, "weight": 100, "min": 10, "max": 15}, {"tier": 2, "level": 8, "weight": 60, "min": 16, "max": 22}, {"tier": 3, "level": 16, "weight": 30, "min": 23, "max": 30}]},
}
## Derive only the new eligibility from frozen authored budgets.
static var _current_extended_affixes: Dictionary = ForgebladeProfile.extend_affixes(LOCAL_WEAPON_AFFIXES, BuildAffixes.AFFIXES)
static var _glove_ring_affixes: Dictionary = GloveRingAffixes.build_affixes(DEFENSE_AFFIXES, ElementalDefense.AFFIXES)

## Ordering is part of the RNG contract. Do not derive these arrays from a registry
## that later releases can extend. New content belongs in a new profile.
const POOL_PROFILES: Dictionary = {
	"nine_slot": NineSlotProfile._POOL_PROFILE,
	"legacy": {"base_ids": ["cinder_reed", "gale_spindle", "woven_bastion", "tidebound_coat", "wayglass_token", "pulse_seed"],
		"affix_ids": ["rootwell", "deepwell", "lanternveil", "runesong", "prismedge", "farweave", "coalglow", "rimeecho", "sparkthread", "wellturn", "trailstep", "beatlink"], "min_save_version": 4},
	"runewood": {"base_ids": ["runewood_focus"],
		"affix_ids": ["rootwell", "deepwell", "lanternveil", "runesong", "prismedge", "farweave", "coalglow", "rimeecho", "sparkthread", "wellturn", "trailstep", "beatlink", "attack_added_physical", "attack_added_fire", "spell_added_cold", "spell_added_lightning"], "min_save_version": 6},
	"defense": {"base_ids": ["emberhide_vest"],
		"affix_ids": ["rootwell", "deepwell", "lanternveil", "coalglow", "rimeecho", "sparkthread", "wellturn", "trailstep", "emberward"], "min_save_version": 8},
	"local_weapon": {"base_ids": ["ashwood_bow"],
		"affix_ids": ["deepwell", "runesong", "prismedge", "farweave", "coalglow", "rimeecho", "sparkthread", "wellturn", "beatlink", "whetstone_edge", "tempered_edge"], "min_save_version": 9, "balance_origin": "original"},
	"build_legacy_v27": {"base_ids": ["cinder_reed", "gale_spindle", "woven_bastion", "tidebound_coat", "wayglass_token", "pulse_seed"],
		"affix_ids": ["rootwell", "deepwell", "lanternveil", "runesong", "prismedge", "farweave", "coalglow", "rimeecho", "sparkthread", "wellturn", "trailstep", "beatlink", "attack_life_leech", "attack_mana_leech", "global_critical_chance", "global_critical_multiplier"], "min_save_version": 27},
	"build_nine_slot_v27": {"base_ids": ["nine_slot_etched_ring", "nine_slot_trail_boots", "nine_slot_folded_belt", "nine_slot_threaded_gloves", "nine_slot_slate_helmet"],
		"affix_ids": ["nine_slot_prefix_vitality", "nine_slot_prefix_clarity", "nine_slot_prefix_aegis", "nine_slot_suffix_endurance", "nine_slot_suffix_mana_flow", "nine_slot_suffix_stride", "nine_slot_suffix_skill_row", "attack_life_leech", "attack_mana_leech", "global_critical_chance", "global_critical_multiplier"], "min_save_version": 27},
	"forgeblade_v34": ForgebladeProfile.POOL_PROFILE,
	"defense_v37": ElementalDefense.POOL_PROFILE,
	"defense_v39": DefenseRatings.POOL_PROFILE,
	"build_nine_slot_v46": GloveRingAffixes.POOL_PROFILE,
}
const LOOT_PROFILES: Dictionary = {
	"canonical_v27": [{"pool_id":"build_legacy_v27","weight":30},{"pool_id":"runewood","weight":20},{"pool_id":"defense","weight":10},{"pool_id":"local_weapon","weight":10},{"pool_id":"build_nine_slot_v27","weight":30}],
	"canonical_v14": [{"pool_id":"legacy","weight":30},{"pool_id":"runewood","weight":20},{"pool_id":"defense","weight":10},{"pool_id":"local_weapon","weight":10},{"pool_id":"nine_slot","weight":30}],
	"v0.11": [{"pool_id": "legacy", "weight": 60}, {"pool_id": "runewood", "weight": 25}, {"pool_id": "defense", "weight": 15}],
	"v0.13": [{"pool_id": "legacy", "weight": 45}, {"pool_id": "runewood", "weight": 25}, {"pool_id": "defense", "weight": 15}, {"pool_id": "local_weapon", "weight": 15}],
	"canonical_v34": [{"pool_id":"build_legacy_v27","weight":25},{"pool_id":"runewood","weight":20},{"pool_id":"defense","weight":10},{"pool_id":"local_weapon","weight":10},{"pool_id":"build_nine_slot_v27","weight":30},{"pool_id":"forgeblade_v34","weight":5}],
	"canonical_v37": [{"pool_id":"build_legacy_v27","weight":25},{"pool_id":"runewood","weight":20},{"pool_id":"defense_v37","weight":10},{"pool_id":"local_weapon","weight":10},{"pool_id":"build_nine_slot_v27","weight":30},{"pool_id":"forgeblade_v34","weight":5}],
	"canonical_v39": [{"pool_id":"build_legacy_v27","weight":25},{"pool_id":"runewood","weight":20},{"pool_id":"defense_v39","weight":10},{"pool_id":"local_weapon","weight":10},{"pool_id":"build_nine_slot_v27","weight":30},{"pool_id":"forgeblade_v34","weight":5}],
	"canonical_v46": [{"pool_id":"build_legacy_v27","weight":25},{"pool_id":"runewood","weight":20},{"pool_id":"defense_v39","weight":10},{"pool_id":"local_weapon","weight":10},{"pool_id":"build_nine_slot_v46","weight":30},{"pool_id":"forgeblade_v34","weight":5}],
}
const CURRENT_LOOT_PROFILE_ID: String = "canonical_v46"


static func all_base_ids() -> Array[String]:
	var result: Array[String] = []
	for profile: Dictionary in POOL_PROFILES.values():
		for id: String in profile.base_ids:
			if not result.has(id):
				result.append(id)
	return result


static func all_affix_ids() -> Array[String]:
	var result: Array[String] = []
	for profile: Dictionary in POOL_PROFILES.values():
		for id: String in profile.affix_ids:
			if not result.has(id):
				result.append(id)
	return result


static func pool_profiles() -> Dictionary:
	return POOL_PROFILES.duplicate(true)


static func pool_profile(pool_id: String) -> Dictionary:
	return POOL_PROFILES.get(pool_id, {}).duplicate(true)


static func current_loot_profile() -> Array[Dictionary]:
	return loot_profile(CURRENT_LOOT_PROFILE_ID)


static func loot_profiles() -> Dictionary:
	return LOOT_PROFILES.duplicate(true)


static func loot_profile(profile_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(LOOT_PROFILES.get(profile_id, []).duplicate(true))
	return result


static func pool_for_base(base_id: String) -> String:
	for id: String in POOL_PROFILES:
		if POOL_PROFILES[id].base_ids.has(base_id):
			return id
	return ""


## Base availability is historical; rolling/validation vocabulary is explicit.
static func pool_for_base_version(base_id: String, vocabulary: int) -> String:
	var original := pool_for_base(base_id)
	if original == "defense":
		if vocabulary in [DefenseRatings.MIN_SAVE_VERSION, GloveRingAffixes.MIN_SAVE_VERSION]: return "defense_v39"
		if vocabulary == ElementalDefense.MIN_SAVE_VERSION: return "defense_v37"
	if original == "nine_slot" and vocabulary == GloveRingAffixes.MIN_SAVE_VERSION:
		return "build_nine_slot_v46"
	if vocabulary >= 27:
		if original == "legacy": return "build_legacy_v27"
		if original == "nine_slot": return "build_nine_slot_v27"
	return original


static func current_pool_for_base(base_id: String) -> String:
	return pool_for_base_version(base_id, CURRENT_VOCABULARY)


static func family_eligible(affix_id: String, base_id: String) -> bool:
	var family: Dictionary = _affix_record(affix_id)
	return not family.is_empty() and _family_eligible(affix_id, family, base_id)


## Lookups are detached, including nested stats, tiers and eligibility arrays.
static func base_definition(id: String) -> Dictionary:
	return _base_record(id).duplicate(true)


static func affix_definition(id: String) -> Dictionary:
	return _affix_record(id).duplicate(true)


## One pure formatter for inventory cards, long definitions and reference output.
## Integer payload ticks remain authoritative; presentation never recalculates stats.
static func affix_display(affix: Variant) -> Dictionary:
	var empty := {"ok":false,"label":"","value_text":"","line":""}
	if not affix is Dictionary or affix.size()!=3 or not affix.has_all(["id","tier","value"]) or not affix.id is String: return empty
	var family: Dictionary = _affix_record(affix.id)
	if family.is_empty() or not _is_bounded_int(affix.tier,1,family.tiers.size()): return empty
	var tier: Dictionary = family.tiers[int(affix.tier)-1]
	if not _is_bounded_int(affix.value,int(tier.min),int(tier.max)): return empty
	var amount: String
	if family.unit == "basis_points": amount = "+%.2f%%" % (float(affix.value)/100.0)
	elif family.get("display_unit","") == "percentage_points": amount = "+%d个百分点" % int(affix.value)
	else: amount = "+%d%s" % [int(affix.value), "%" if family.unit == "percent" else ""]
	var label: String = str(family.label)
	return {"ok":true,"label":label,"value_text":amount,"line":label+" "+amount}


static func affix_stat_value(family: Dictionary, ticks: Variant) -> float:
	return float(ticks) / (10000.0 if family.unit == "basis_points" else 100.0 if family.unit == "percent" else 1.0)


static func _base_record(id: String) -> Dictionary:
	return BASES.get(id, EXPANSION_BASES.get(id, DEFENSE_BASES.get(id, LOCAL_WEAPON_BASES.get(id, NINE_SLOT_BASES.get(id, ForgebladeProfile.BASES.get(id, {}))))))


static func _affix_record(id: String) -> Dictionary:
	if _glove_ring_affixes.has(id):
		return _glove_ring_affixes[id]
	if DefenseRatings.AFFIXES.has(id):
		return DefenseRatings.AFFIXES[id]
	if ElementalDefense.AFFIXES.has(id):
		return ElementalDefense.AFFIXES[id]
	return _current_extended_affixes.get(id, BuildAffixes.AFFIXES.get(id, AFFIXES.get(id, EXPANSION_AFFIXES.get(id, DEFENSE_AFFIXES.get(id, LOCAL_WEAPON_AFFIXES.get(id, NINE_SLOT_AFFIXES.get(id, {})))))))


static func generate(rng: RandomNumberGenerator, id: String, item_level: int, rarity: String = "") -> Dictionary:
	return generate_for_pool(rng, id, item_level, rarity, "legacy")


## Historical runewood-only adapter; preserves its item and post-RNG stream.
static func generate_expanded(rng: RandomNumberGenerator, id: String, item_level: int, rarity: String = "") -> Dictionary:
	return generate_for_pool(rng, id, item_level, rarity, "runewood")


static func _valid_request(rng: RandomNumberGenerator, id: String, item_level: int, rarity: String) -> bool:
	return rng != null and serial_from_id(id) > 0 and item_level >= MIN_ITEM_LEVEL and item_level <= MAX_ITEM_LEVEL \
		and (rarity.is_empty() or RARITIES.has(rarity))


static func generate_for_pool(rng: RandomNumberGenerator, id: String, item_level: int, rarity: String, pool_id: String) -> Dictionary:
	if not POOL_PROFILES.has(pool_id) or not _valid_request(rng, id, item_level, rarity):
		return {}
	if rarity.is_empty():
		rarity = _roll_rarity(rng)
	var profile: Dictionary = POOL_PROFILES[pool_id]
	var base_ids: Array = profile.base_ids
	var base_id: String = base_ids[rng.randi_range(0, base_ids.size() - 1)]
	var rules: Dictionary = RARITIES[rarity]
	var count: int = rng.randi_range(int(rules.min_affixes), int(rules.max_affixes))
	var prefix_count: int = rng.randi_range(maxi(0, count - int(rules.max_suffixes)), mini(count, int(rules.max_prefixes)))
	var affixes: Array = []
	var groups: Dictionary = {}
	for kind: String in ["prefix", "suffix"]:
		var pool: Array[Dictionary] = _profile_eligible_tiers(base_id, item_level, kind, profile)
		var kind_count: int = prefix_count if kind == "prefix" else count - prefix_count
		for unused: int in range(kind_count):
			var choice: Dictionary = _weighted_choice(rng, pool)
			if choice.is_empty():
				return {}
			var family: Dictionary = _affix_record(choice.id)
			var tier: Dictionary = family.tiers[int(choice.tier) - 1]
			affixes.append({"id": choice.id, "tier": int(choice.tier), "value": rng.randi_range(int(tier.min), int(tier.max))})
			groups[family.group] = true
			var remaining: Array[Dictionary] = []
			for candidate: Dictionary in pool:
				if not groups.has(_affix_record(candidate.id).group):
					remaining.append(candidate)
			pool = remaining
	var instance: Dictionary = {"id": id, "base_id": base_id, "rarity": rarity, "item_level": item_level, "affixes": affixes}
	return instance if validate_instance(instance) else {}


## Natural rewards intentionally advance to the explicitly named current profile.
static func generate_current_loot(rng: RandomNumberGenerator, id: String, item_level: int, rarity: String = "") -> Dictionary:
	return generate_loot_profile(rng, id, item_level, rarity, CURRENT_LOOT_PROFILE_ID)


## Versioned dispatch preserves both item rolls and the post-roll RNG stream.
static func generate_loot_profile(rng: RandomNumberGenerator, id: String, item_level: int, rarity: String, profile_id: String) -> Dictionary:
	if not LOOT_PROFILES.has(profile_id) or not _valid_request(rng, id, item_level, rarity):
		return {}
	var roll: int = rng.randi_range(1, 100)
	for entry: Dictionary in LOOT_PROFILES[profile_id]:
		roll -= int(entry.weight)
		if roll <= 0:
			return generate_for_pool(rng, id, item_level, rarity, entry.pool_id)
	return {}


## Natural rewards still create one item; pool choice happens before its rarity/base roll.
## Invalid requests reject before the pool roll, so they never advance the caller's RNG.
static func generate_loot(rng: RandomNumberGenerator, id: String, item_level: int, rarity: String = "") -> Dictionary:
	if rng == null or serial_from_id(id) == 0 or item_level < MIN_ITEM_LEVEL or item_level > MAX_ITEM_LEVEL:
		return {}
	if not rarity.is_empty() and not RARITIES.has(rarity):
		return {}
	if rng.randi_range(1, 100) <= EXPANSION_LOOT_PERCENT:
		return generate_expanded(rng, id, item_level, rarity)
	return generate(rng, id, item_level, rarity)


## Omitted vocabulary means current runtime. Explicit booleans retain the old
## false=pre-v6 / true=v6 meaning; save callers use the named version API.
static func validate_instance(value: Variant, vocabulary: Variant = null) -> bool:
	if vocabulary == null:
		return validate_instance_for_version(value, CURRENT_VOCABULARY)
	if vocabulary is bool:
		return validate_instance_for_version(value, 6 if vocabulary else 5)
	if not _is_bounded_int(vocabulary, 1, CURRENT_VOCABULARY):
		return false
	return validate_instance_for_version(value, int(vocabulary))


static func validate_instance_for_version(value: Variant, save_version: int) -> bool:
	# Source-only schemas35/36/38/40..45 never opened an equipment vocabulary. Their
	# save adapters retain their previous vocabulary; explicit requests reject.
	if save_version < 1 or (save_version > 34 and save_version not in [ElementalDefense.MIN_SAVE_VERSION, DefenseRatings.MIN_SAVE_VERSION, GloveRingAffixes.MIN_SAVE_VERSION]):
		return false
	if not value is Dictionary:
		return false
	var instance: Dictionary = value
	if instance.size() != 5 or not instance.has_all(["id", "base_id", "rarity", "item_level", "affixes"]):
		return false
	if not instance.id is String or serial_from_id(instance.id) == 0:
		return false
	if not instance.base_id is String or _base_record(instance.base_id).is_empty():
		return false
	var pool_id: String = pool_for_base(instance.base_id)
	if pool_id.is_empty() or save_version < int(POOL_PROFILES[pool_id].min_save_version):
		return false
	if DEFENSE_BASES.has(instance.base_id) and not _valid_defense_base(_base_record(instance.base_id)):
		return false
	if _is_local_weapon_base(instance.base_id) and not _valid_local_weapon_base(_base_record(instance.base_id), instance.base_id):
		return false
	if not instance.rarity is String or not RARITIES.has(instance.rarity):
		return false
	if not _is_bounded_int(instance.item_level, MIN_ITEM_LEVEL, MAX_ITEM_LEVEL):
		return false
	if not instance.affixes is Array:
		return false
	var rules: Dictionary = RARITIES[instance.rarity]
	if instance.affixes.size() < int(rules.min_affixes) or instance.affixes.size() > int(rules.max_affixes):
		return false
	var counts: Dictionary = {"prefix": 0, "suffix": 0}
	var families: Dictionary = {}
	var groups: Dictionary = {}
	for entry: Variant in instance.affixes:
		if not entry is Dictionary:
			return false
		var affix: Dictionary = entry
		if affix.size() != 3 or not affix.has_all(["id", "tier", "value"]):
			return false
		if not affix.id is String or _affix_record(affix.id).is_empty() or families.has(affix.id):
			return false
		var family: Dictionary = _affix_record(affix.id)
		var vocabulary_pool: String = pool_for_base_version(instance.base_id, save_version)
		if not POOL_PROFILES[vocabulary_pool].affix_ids.has(affix.id):
			return false
		if groups.has(family.group) or not _family_eligible(affix.id, family, instance.base_id):
			return false
		if not _is_bounded_int(affix.tier, 1, family.tiers.size()):
			return false
		var tier: Dictionary = family.tiers[int(affix.tier) - 1]
		if int(instance.item_level) < int(tier.level):
			return false
		if not _is_bounded_int(affix.value, int(tier.min), int(tier.max)):
			return false
		counts[family.kind] += 1
		if int(counts[family.kind]) > int(rules["max_" + family.kind + "es"]):
			return false
		families[affix.id] = true
		groups[family.group] = true
	return true


static func get_stats(instance: Dictionary) -> Dictionary:
	if not validate_instance(instance):
		return {}
	return _validated_stats(instance)


static func definition(instance: Dictionary) -> Dictionary:
	if not validate_instance(instance):
		return {}
	var base: Dictionary = _base_record(instance.base_id)
	var lines: Array[String] = []
	for affix: Dictionary in instance.affixes:
		var family: Dictionary = _affix_record(affix.id)
		var kind: String = "前缀" if family.kind == "prefix" else "后缀"
		var amount: String = str(affix_display(affix).value_text)
		lines.append("%s · %s T%d：%s %s" % [kind, family.name, int(affix.tier), family.label, amount])
	var description: String = base.description
	if not lines.is_empty():
		description += "\n" + "\n".join(lines)
	var result: Dictionary = {"id": instance.id, "base_id": instance.base_id, "name": "%s · %s" % [RARITIES[instance.rarity].name, base.name],
		"slot": base.slot, "size": base.size, "description": description, "stats": _validated_stats(instance),
		"effects": [], "added_sources": _added_sources(instance), "rarity": instance.rarity, "item_level": instance.item_level, "affix_lines": lines, "base_name": base.name}
	if _is_local_weapon_base(instance.base_id):
		var profile: Dictionary = weapon_profile(instance)
		var resolved: Dictionary = WeaponLocalRules.resolve(profile)
		if not resolved.ok:
			return {}
		result["weapon_profile"] = profile
		result["weapon_damage"] = resolved.components.duplicate(true)
		var consumer_summary: String = "普通近战攻击与裂刃斩" if ForgebladeProfile.BASES.has(instance.base_id) else "仅普攻与龙卷箭体"
		result["weapon_damage_summary"] = "本武器物理：(%s + %s) × (1 + %s%%) = %s；%s" % [str(profile.base.physical), str(profile.flat.physical), str(snappedf(float(profile.increased.physical) * 100.0, 0.01)), str(snappedf(float(resolved.components.physical), 0.01)), consumer_summary]
	return result


## Persist only the five canonical item fields. Derive this detached profile
## from authored metadata and validated rolls whenever an item is inspected.
static func weapon_profile(instance: Dictionary) -> Dictionary:
	if not validate_instance(instance) or not _is_local_weapon_base(instance.base_id):
		return {}
	var profile: Dictionary = {"stage": "weapon_local", "item_id": instance.id, "base_id": instance.base_id,
		"base": {"physical": float(WeaponLocalRules.BASE_PHYSICAL_BY_ID[instance.base_id])},
		"flat": {"physical": 0.0}, "increased": {"physical": 0.0}, "sources": []}
	for affix: Dictionary in instance.affixes:
		if not LOCAL_WEAPON_AFFIXES.has(affix.id):
			continue
		var family: Dictionary = LOCAL_WEAPON_AFFIXES[affix.id]
		var amount: float = affix_stat_value(family, affix.value)
		profile["flat" if family.unit == "flat" else "increased"].physical += amount
		profile.sources.append({"affix_id": affix.id, "stat": family.stat, "value": amount})
	return profile


static func serial_from_id(id: String) -> int:
	if not id.begins_with("gear_") or id.length() > 14:
		return 0
	var suffix: String = id.substr(5)
	if not suffix.is_valid_int():
		return 0
	var serial: int = suffix.to_int()
	if serial < 1 or serial > MAX_SERIAL or id != "gear_%06d" % serial:
		return 0
	return serial


static func _validated_stats(instance: Dictionary) -> Dictionary:
	var result: Dictionary = _base_record(instance.base_id).stats.duplicate(true)
	for affix: Dictionary in instance.affixes:
		var family: Dictionary = _affix_record(affix.id)
		if LOCAL_WEAPON_AFFIXES.has(affix.id):
			continue # Local weapon terms never become character/global modifiers.
		var amount: float = affix_stat_value(family, affix.value)
		result[family.stat] = float(result.get(family.stat, 0.0)) + amount
	return result


static func _added_sources(instance: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for affix: Dictionary in instance.affixes:
		if not EXPANSION_AFFIXES.has(affix.id):
			continue
		var family: Dictionary = EXPANSION_AFFIXES[affix.id]
		result.append({"item_id": instance.id, "affix_id": affix.id, "stat": family.stat,
			"scope": ADDED_STAT_TYPES[family.stat][0], "damage_type": family.damage_type, "value": float(affix.value)})
	return result


static func _family_eligible(id: String, family: Dictionary, base_id: String) -> bool:
	if ForgebladeProfile.BASES.has(base_id) and not ForgebladeProfile.POOL_PROFILE.affix_ids.has(id):
		return false
	var base: Dictionary = _base_record(base_id)
	if base.is_empty() or not family.slots.has(base.slot):
		return false
	if EXPANSION_AFFIXES.has(id):
		return _valid_expansion_family(family) and family.allowed_base_ids.has(base_id)
	if DEFENSE_AFFIXES.has(id):
		return _valid_defense_family(family) and family.allowed_base_ids.has(base_id)
	if ElementalDefense.AFFIXES.has(id):
		return ElementalDefense.valid_family(family) and family.allowed_base_ids.has(base_id)
	if DefenseRatings.AFFIXES.has(id):
		return DefenseRatings.valid_family(family) and family.allowed_base_ids.has(base_id)
	if _glove_ring_affixes.has(id):
		return GloveRingAffixes.valid_family(family) and family.allowed_base_ids.has(base_id)
	if LOCAL_WEAPON_AFFIXES.has(id):
		return _valid_local_weapon_family(family) and family.allowed_base_ids.has(base_id)
	if BuildAffixes.AFFIXES.has(id): return family.allowed_base_ids.has(base_id)
	return AFFIXES.has(id) or NINE_SLOT_AFFIXES.has(id)


static func _is_local_weapon_base(base_id: String) -> bool:
	return LOCAL_WEAPON_BASES.has(base_id) or ForgebladeProfile.BASES.has(base_id)


static func _valid_local_weapon_base(base: Dictionary, base_id: String) -> bool:
	for field: String in ["stage", "scope", "slot"]:
		if not base.get(field) is String:
			return false
	return base.get("stage") == "weapon_local" and base.get("scope") == "equipped_weapon" \
		and base.get("slot") == "weapon" and base.get("stats") is Dictionary and base.stats.is_empty() \
		and WeaponLocalRules.BASE_PHYSICAL_BY_ID.has(base_id)


static func _valid_local_weapon_family(family: Dictionary) -> bool:
	if not family.has_all(["stage", "scope", "stat", "kind", "unit", "slots", "allowed_base_ids", "damage_type"]):
		return false
	for field: String in ["stage", "scope", "stat", "kind", "unit", "damage_type"]:
		if not family[field] is String:
			return false
	if not family.slots is Array or not family.allowed_base_ids is Array:
		return false
	if family.stage != "weapon_local" or family.scope != "equipped_weapon" or family.kind != "prefix" \
		or family.slots != ["weapon"] or not ForgebladeProfile.valid_local_base_ids(family.allowed_base_ids) or family.damage_type != "physical":
		return false
	return (family.stat == "weapon_added_physical" and family.unit == "flat") \
		or (family.stat == "weapon_physical_increased" and family.unit == "percent")


## Only the four explicit hit-addition semantics are executable. Unknown metadata
## fails closed rather than falling back to a scalar, local weapon, or global hit.
static func _valid_expansion_family(family: Dictionary) -> bool:
	if not family.has_all(["stage", "scope", "stat", "required_tags", "damage_type", "allowed_base_ids", "kind", "unit", "slots"]):
		return false
	for key: String in ["stage", "scope", "stat", "damage_type", "kind", "unit"]:
		if not family[key] is String:
			return false
	for key: String in ["required_tags", "allowed_base_ids", "slots"]:
		if not family[key] is Array:
			return false
	if family.stage != "skill_added_damage" or family.scope != "equipped_character":
		return false
	if not ADDED_STAT_TYPES.has(family.stat):
		return false
	var type: Array = ADDED_STAT_TYPES[family.stat]
	return family.kind == "prefix" and family.unit == "flat" and family.slots == ["weapon"] \
		and family.required_tags == ["hit", type[0]] and family.damage_type == type[1] \
		and family.allowed_base_ids == ["runewood_focus"]


static func _valid_defense_metadata(record: Dictionary) -> bool:
	if not record.get("scope") is String or not record.get("stage") is String or not record.get("actors") is Array:
		return false
	if record.get("scope") != "equipped_character" or record.get("stage") != "hit_mitigation" or record.get("actors") != ["player", "monster"]:
		return false
	for actor: String in record.actors:
		if not DefenseRules.supports_stat("fire_resistance", actor, record.stage):
			return false
	return true


static func _valid_defense_base(base: Dictionary) -> bool:
	if not base.get("slot") is String or not base.get("stats") is Dictionary:
		return false
	return _valid_defense_metadata(base) and base.slot == "armor" \
		and base.stats.has("fire_resistance") \
		and DefenseRules.defense_profile({"fire_resistance": base.stats.fire_resistance}).ok


static func _valid_defense_family(family: Dictionary) -> bool:
	for field: String in ["stat", "kind", "unit"]:
		if not family.get(field) is String:
			return false
	if not family.get("slots") is Array or not family.get("allowed_base_ids") is Array:
		return false
	return _valid_defense_metadata(family) and family.get("stat") == "fire_resistance" \
		and family.get("kind") == "suffix" and family.get("unit") == "percent" \
		and family.get("slots") == ["armor"] and family.get("allowed_base_ids") == ["emberhide_vest"]


static func _expanded_eligible_tiers(base_id: String, item_level: int, kind: String) -> Array[Dictionary]:
	return _profile_eligible_tiers(base_id, item_level, kind, POOL_PROFILES.runewood)


static func _eligible_tiers(base_id: String, item_level: int, kind: String) -> Array[Dictionary]:
	return _profile_eligible_tiers(base_id, item_level, kind, POOL_PROFILES.legacy)


static func _profile_eligible_tiers(base_id: String, item_level: int, kind: String, profile: Dictionary) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	if not profile.base_ids.has(base_id):
		return pool
	for id: String in profile.affix_ids:
		var family: Dictionary = _affix_record(id)
		if family.kind != kind or not _family_eligible(id, family, base_id):
			continue
		for tier: Dictionary in family.tiers:
			if item_level >= int(tier.level) and int(tier.weight) > 0:
				pool.append({"id": id, "tier": int(tier.tier), "weight": int(tier.weight)})
	return pool


static func _weighted_choice(rng: RandomNumberGenerator, pool: Array[Dictionary]) -> Dictionary:
	var total: int = 0
	for entry: Dictionary in pool:
		total += int(entry.weight)
	if total <= 0:
		return {}
	var roll: int = rng.randi_range(1, total)
	for entry: Dictionary in pool:
		roll -= int(entry.weight)
		if roll <= 0:
			return entry
	return {}


static func _roll_rarity(rng: RandomNumberGenerator) -> String:
	var pool: Array[Dictionary] = []
	for id: String in RARITIES:
		pool.append({"id": id, "weight": int(RARITIES[id].weight)})
	return _weighted_choice(rng, pool).id


static func _is_bounded_int(value: Variant, minimum: int, maximum: int) -> bool:
	# JSON stores numeric literals as floats. Accept only exact finite whole ticks.
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and number == floorf(number)
