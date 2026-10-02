class_name JewelData
extends RefCounted
## Original basic jewels only: no radius, cluster, timeless or hidden multipliers.
## Affixes are bounded, quantized flat bonuses to actual combat statistics.

const BASES: Dictionary = {
	"emberheart": {"name": "烬心晶玉", "color": Color("ec987f"), "prefixes": ["force", "vitality", "barrier"], "suffixes": ["tempo", "stride", "recharge"]},
	"tideglass": {"name": "雾潮晶玉", "color": Color("89bfea"), "prefixes": ["force", "clarity", "barrier"], "suffixes": ["renewal", "recharge", "tempo"]},
	"windweave": {"name": "岚纹晶玉", "color": Color("88d3b9"), "prefixes": ["force", "vitality", "clarity"], "suffixes": ["tempo", "stride", "renewal"]},
}
const RARITIES: Dictionary = {
	"magic": {"name": "魔法", "color": Color("8eb8ff"), "max_affixes": 2, "max_prefixes": 1, "max_suffixes": 1},
	"rare": {"name": "稀有", "color": Color("e9ce7c"), "max_affixes": 4, "max_prefixes": 2, "max_suffixes": 2},
}
const AFFIXES: Dictionary = {
	"force": {"name": "炽烈", "kind": "prefix", "stat": "damage", "min": 2.0, "max": 6.0, "step": 1.0},
	"vitality": {"name": "丰茂", "kind": "prefix", "stat": "max_health", "min": 12.0, "max": 28.0, "step": 2.0},
	"clarity": {"name": "澄明", "kind": "prefix", "stat": "max_mana", "min": 8.0, "max": 22.0, "step": 2.0},
	"barrier": {"name": "凝光", "kind": "prefix", "stat": "max_shield", "min": 8.0, "max": 22.0, "step": 2.0},
	"tempo": {"name": "节律", "kind": "suffix", "stat": "attack_speed", "min": 0.04, "max": 0.12, "step": 0.01},
	"stride": {"name": "疾行", "kind": "suffix", "stat": "move_speed", "min": 4.0, "max": 12.0, "step": 1.0},
	"renewal": {"name": "回流", "kind": "suffix", "stat": "mana_regen", "min": 0.3, "max": 1.1, "step": 0.1},
	"recharge": {"name": "复苏", "kind": "suffix", "stat": "shield_regen", "min": 0.5, "max": 1.5, "step": 0.1},
}
const Passives = preload("res://scripts/passive_data.gd")


static func starter_jewels() -> Dictionary:
	return {
		"jewel_000001": {"id": "jewel_000001", "base": "emberheart", "rarity": "magic", "affixes": [{"id": "force", "value": 4.0}, {"id": "tempo", "value": 0.08}]},
		"jewel_000002": {"id": "jewel_000002", "base": "tideglass", "rarity": "magic", "affixes": [{"id": "barrier", "value": 16.0}, {"id": "renewal", "value": 0.7}]},
		"jewel_000003": {"id": "jewel_000003", "base": "windweave", "rarity": "rare", "affixes": [{"id": "vitality", "value": 20.0}, {"id": "clarity", "value": 14.0}, {"id": "stride", "value": 8.0}, {"id": "tempo", "value": 0.06}]},
	}.duplicate(true)


static func generate(rng: RandomNumberGenerator, instance_id: String) -> Dictionary:
	var bases: Array = BASES.keys()
	var base_id: String = bases[rng.randi_range(0, bases.size() - 1)]
	var rarity: String = "rare" if rng.randf() < 0.30 else "magic"
	var prefix_pool: Array = BASES[base_id]["prefixes"].duplicate()
	var suffix_pool: Array = BASES[base_id]["suffixes"].duplicate()
	var prefix_count: int = 1 if rarity == "magic" else rng.randi_range(1, 2)
	var suffix_count: int = 1 if rarity == "magic" else 2
	var affixes: Array = []
	for count: int in [prefix_count, suffix_count]:
		var pool: Array = prefix_pool if affixes.is_empty() else suffix_pool
		for unused: int in range(count):
			var chosen: int = rng.randi_range(0, pool.size() - 1)
			var affix_id: String = pool[chosen]
			pool.remove_at(chosen)
			var definition: Dictionary = AFFIXES[affix_id]
			var steps: int = roundi((float(definition["max"]) - float(definition["min"])) / float(definition["step"]))
			var value: float = float(definition["min"]) + float(rng.randi_range(0, steps)) * float(definition["step"])
			affixes.append({"id": affix_id, "value": float(roundi(value * 100.0)) / 100.0})
	return {"id": instance_id, "base": base_id, "rarity": rarity, "affixes": affixes}


static func display_name(jewel: Dictionary) -> String:
	if jewel.is_empty():
		return "空珠宝孔"
	return "%s · %s" % [RARITIES.get(jewel.get("rarity", ""), {}).get("name", "未知"), BASES.get(jewel.get("base", ""), {}).get("name", "未知晶玉")]


static func get_color(jewel: Dictionary) -> Color:
	return RARITIES.get(jewel.get("rarity", ""), {}).get("color", Color.WHITE)


static func get_description(jewel: Dictionary) -> String:
	var lines: PackedStringArray = []
	for affix: Dictionary in jewel.get("affixes", []):
		var definition: Dictionary = AFFIXES.get(affix.get("id", ""), {})
		if not definition.is_empty():
			var kind: String = "前缀" if definition["kind"] == "prefix" else "后缀"
			lines.append("%s · %s：%s" % [kind, definition["name"], Passives.describe_stats({definition["stat"]: affix["value"]})])
	return "\n".join(lines)


static func get_stats(jewel: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for affix: Dictionary in jewel.get("affixes", []):
		if AFFIXES.has(affix.get("id", "")):
			var stat: String = AFFIXES[affix["id"]]["stat"]
			result[stat] = float(result.get(stat, 0.0)) + float(affix.get("value", 0.0))
	return result


static func validate_instance(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var jewel: Dictionary = value
	if jewel.size() != 4 or not jewel.has_all(["id", "base", "rarity", "affixes"]):
		return false
	if not jewel["id"] is String or serial_from_id(jewel["id"]) <= 0:
		return false
	if not jewel["base"] is String or not BASES.has(jewel["base"]):
		return false
	if not jewel["rarity"] is String or not RARITIES.has(jewel["rarity"]):
		return false
	if not jewel["affixes"] is Array:
		return false
	var rarity: Dictionary = RARITIES[jewel["rarity"]]
	var affixes: Array = jewel["affixes"]
	if affixes.is_empty() or affixes.size() > int(rarity["max_affixes"]):
		return false
	var counts: Dictionary = {"prefix": 0, "suffix": 0}
	var seen: Dictionary = {}
	for value_affix: Variant in affixes:
		if not value_affix is Dictionary:
			return false
		var affix: Dictionary = value_affix
		if affix.size() != 2 or not affix.has_all(["id", "value"]):
			return false
		if not affix["id"] is String or not AFFIXES.has(affix["id"]) or seen.has(affix["id"]):
			return false
		seen[affix["id"]] = true
		var definition: Dictionary = AFFIXES[affix["id"]]
		var kind: String = definition["kind"]
		if not BASES[jewel["base"]][kind + "es"].has(affix["id"]):
			return false
		counts[kind] += 1
		if int(counts[kind]) > int(rarity["max_" + kind + "es"]):
			return false
		if not (affix["value"] is float or affix["value"] is int):
			return false
		var amount: float = float(affix["value"])
		if not is_finite(amount) or amount < float(definition["min"]) - 0.00001 or amount > float(definition["max"]) + 0.00001:
			return false
		var steps: float = (amount - float(definition["min"])) / float(definition["step"])
		if not is_equal_approx(steps, roundf(steps)):
			return false
	return true


static func serial_from_id(id: String) -> int:
	if not id.begins_with("jewel_") or id.length() > 16:
		return 0
	var suffix: String = id.substr(6)
	if not suffix.is_valid_int():
		return 0
	var serial: int = suffix.to_int()
	if serial < 1 or serial > 999999999 or id != "jewel_%06d" % serial:
		return 0
	return serial
