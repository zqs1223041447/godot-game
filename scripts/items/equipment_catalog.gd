class_name EquipmentCatalog
extends RefCounted
## Original equipment and bounded v0.7 expansion; reference exports never enter runtime.
## BASES/AFFIXES and generate() remain the frozen six-base/twelve-family legacy pool.
## Rolls store integer points / percentage ticks; runtime percentages are ticks / 100.
## Base damage is the game's existing character scalar, NOT local weapon damage.

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


## Lookups are detached, including nested stats, tiers and eligibility arrays.
static func base_definition(id: String) -> Dictionary:
	return _base_record(id).duplicate(true)


static func affix_definition(id: String) -> Dictionary:
	return _affix_record(id).duplicate(true)


static func _base_record(id: String) -> Dictionary:
	return BASES.get(id, EXPANSION_BASES.get(id, {}))


static func _affix_record(id: String) -> Dictionary:
	return AFFIXES.get(id, EXPANSION_AFFIXES.get(id, {}))


static func generate(rng: RandomNumberGenerator, id: String, item_level: int, rarity: String = "") -> Dictionary:
	if rng == null or serial_from_id(id) == 0 or item_level < MIN_ITEM_LEVEL or item_level > MAX_ITEM_LEVEL:
		return {}
	if not rarity.is_empty() and not RARITIES.has(rarity):
		return {}
	if rarity.is_empty():
		rarity = _roll_rarity(rng)
	var base_ids: Array = BASES.keys()
	var base_id: String = base_ids[rng.randi_range(0, base_ids.size() - 1)]
	var rules: Dictionary = RARITIES[rarity]
	var count: int = rng.randi_range(int(rules.min_affixes), int(rules.max_affixes))
	var prefix_count: int = rng.randi_range(maxi(0, count - int(rules.max_suffixes)), mini(count, int(rules.max_prefixes)))
	var affixes: Array = []
	var groups: Dictionary = {}
	for kind: String in ["prefix", "suffix"]:
		var pool: Array[Dictionary] = _eligible_tiers(base_id, item_level, kind)
		var kind_count: int = prefix_count if kind == "prefix" else count - prefix_count
		for unused: int in range(kind_count):
			var choice: Dictionary = _weighted_choice(rng, pool)
			if choice.is_empty():
				return {}
			var family: Dictionary = AFFIXES[choice.id]
			var tier: Dictionary = family.tiers[int(choice.tier) - 1]
			affixes.append({"id": choice.id, "tier": int(choice.tier), "value": rng.randi_range(int(tier.min), int(tier.max))})
			groups[family.group] = true
			# Filtering all tiers prevents rolling the same family or group twice.
			var remaining: Array[Dictionary] = []
			for candidate: Dictionary in pool:
				if not groups.has(AFFIXES[candidate.id].group):
					remaining.append(candidate)
			pool = remaining
	var instance: Dictionary = {"id": id, "base_id": base_id, "rarity": rarity, "item_level": item_level, "affixes": affixes}
	return instance if validate_instance(instance) else {}


## Same roll contract as generate(), but explicitly selects the expansion base only.
static func generate_expanded(rng: RandomNumberGenerator, id: String, item_level: int, rarity: String = "") -> Dictionary:
	if rng == null or serial_from_id(id) == 0 or item_level < MIN_ITEM_LEVEL or item_level > MAX_ITEM_LEVEL:
		return {}
	if not rarity.is_empty() and not RARITIES.has(rarity):
		return {}
	if rarity.is_empty():
		rarity = _roll_rarity(rng)
	var base_ids: Array = EXPANSION_BASES.keys()
	var base_id: String = base_ids[rng.randi_range(0, base_ids.size() - 1)]
	var rules: Dictionary = RARITIES[rarity]
	var count: int = rng.randi_range(int(rules.min_affixes), int(rules.max_affixes))
	var prefix_count: int = rng.randi_range(maxi(0, count - int(rules.max_suffixes)), mini(count, int(rules.max_prefixes)))
	var affixes: Array = []
	var groups: Dictionary = {}
	for kind: String in ["prefix", "suffix"]:
		var pool: Array[Dictionary] = _expanded_eligible_tiers(base_id, item_level, kind)
		var kind_count: int = prefix_count if kind == "prefix" else count - prefix_count
		for unused: int in range(kind_count):
			var choice: Dictionary = _weighted_choice(rng, pool)
			if choice.is_empty():
				return {}
			var family: Dictionary = _affix_record(choice.id)
			var tier: Dictionary = family.tiers[int(choice.tier) - 1]
			affixes.append({"id": choice.id, "tier": int(choice.tier), "value": rng.randi_range(int(tier.min), int(tier.max))})
			groups[family.group] = true
			# Filtering all tiers prevents rolling the same family or group twice.
			var remaining: Array[Dictionary] = []
			for candidate: Dictionary in pool:
				if not groups.has(_affix_record(candidate.id).group):
					remaining.append(candidate)
			pool = remaining
	var instance: Dictionary = {"id": id, "base_id": base_id, "rarity": rarity, "item_level": item_level, "affixes": affixes}
	return instance if validate_instance(instance) else {}


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


static func validate_instance(value: Variant, allow_expanded: bool = true) -> bool:
	if not value is Dictionary:
		return false
	var instance: Dictionary = value
	if instance.size() != 5 or not instance.has_all(["id", "base_id", "rarity", "item_level", "affixes"]):
		return false
	if not instance.id is String or serial_from_id(instance.id) == 0:
		return false
	if not instance.base_id is String or _base_record(instance.base_id).is_empty():
		return false
	if not allow_expanded and not BASES.has(instance.base_id):
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
		if not allow_expanded and not AFFIXES.has(affix.id):
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
		var amount: String = "+%d%s" % [int(affix.value), "%" if family.unit == "percent" else ""]
		lines.append("%s · %s T%d：%s %s" % [kind, family.name, int(affix.tier), family.label, amount])
	var description: String = base.description
	if not lines.is_empty():
		description += "\n" + "\n".join(lines)
	return {"id": instance.id, "base_id": instance.base_id, "name": "%s · %s" % [RARITIES[instance.rarity].name, base.name],
		"slot": base.slot, "size": base.size, "description": description, "stats": _validated_stats(instance),
		"effects": [], "added_sources": _added_sources(instance), "rarity": instance.rarity, "item_level": instance.item_level, "affix_lines": lines, "base_name": base.name}


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
		var amount: float = float(affix.value) / (100.0 if family.unit == "percent" else 1.0)
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
	var base: Dictionary = _base_record(base_id)
	if base.is_empty() or not family.slots.has(base.slot):
		return false
	if EXPANSION_AFFIXES.has(id):
		return _valid_expansion_family(family) and family.allowed_base_ids.has(base_id)
	return AFFIXES.has(id)


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


static func _expanded_eligible_tiers(base_id: String, item_level: int, kind: String) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var ids: Array = AFFIXES.keys() + EXPANSION_AFFIXES.keys()
	for id: String in ids:
		var family: Dictionary = _affix_record(id)
		if family.kind != kind or not _family_eligible(id, family, base_id):
			continue
		for tier: Dictionary in family.tiers:
			if item_level >= int(tier.level) and int(tier.weight) > 0:
				pool.append({"id": id, "tier": int(tier.tier), "weight": int(tier.weight)})
	return pool


static func _eligible_tiers(base_id: String, item_level: int, kind: String) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for id: String in AFFIXES:
		var family: Dictionary = AFFIXES[id]
		if family.kind != kind or not family.slots.has(BASES[base_id].slot):
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
