extends RefCounted
## Pure target guarantees over the existing versioned catalog. No wallet, save,
## vocabulary, tier bonus, or retained affix is introduced here.
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Expansion = preload("res://scripts/items/crafting_expansion_rules.gd")
const MATERIAL_ID: String = "calibration_shard"
const TARGETS: Dictionary = {
	"targeted_reforge_critical": {"id": "critical", "label": "暴击",
		"families": ["global_critical_chance", "global_critical_multiplier"]},
	"targeted_reforge_life_leech": {"id": "life_leech", "label": "生命偷取",
		"families": ["attack_life_leech"]},
	"targeted_reforge_mana_leech": {"id": "mana_leech", "label": "魔力偷取",
		"families": ["attack_mana_leech"]},
	"targeted_reforge_damage": {"id": "damage", "label": "伤害",
		"families": ["runesong", "prismedge", "farweave", "coalglow", "rimeecho", "sparkthread",
			"attack_added_physical", "attack_added_fire", "spell_added_cold", "spell_added_lightning",
			"whetstone_edge", "tempered_edge"]},
}
const COSTS: Dictionary = {"magic": 16, "rare": 40}


static func operation_ids() -> Array[String]:
	return ["targeted_reforge_critical", "targeted_reforge_life_leech",
		"targeted_reforge_mana_leech", "targeted_reforge_damage"]


static func metadata(operation: String) -> Dictionary:
	if not TARGETS.has(operation):
		return {}
	var target: Dictionary = TARGETS[operation]
	return {"operation": operation, "label": "定向重铸", "targeted": true,
		"target_id": target.id, "target_label": target.label,
		"description": "保持稀有度，替换全部词缀；保证至少一条符合底材与物品等级的%s词缀。" % target.label,
		"risk": "全部原词缀会被替换，不保证高阶或更强；结果可能相同或更差，碎片仍会消耗。"}


## Economics and deterministic feasibility only; even an unavailable target is
## rejected before a local RNG is constructed by plan().
static func quote(instance: Variant, operation: Variant, vocabulary: int = Catalog.CURRENT_VOCABULARY) -> Dictionary:
	if not operation is String or not TARGETS.has(operation):
		return _failure("invalid_operation", "未知定向重铸目标。")
	if not Catalog.validate_instance_for_version(instance, vocabulary):
		return _failure("invalid_instance", "装备实例未通过所选词汇验证。")
	if not COSTS.has(instance.rarity):
		return _failure("unsupported_rarity", "定向重铸仅适用于魔法或稀有装备。")
	var pool: Array[Dictionary] = Expansion._pool(instance.base_id, int(instance.item_level), [], vocabulary)
	var targeted: Array[Dictionary] = _target_pool(pool, operation)
	if targeted.is_empty():
		return _failure("no_legal_target", "此底材与物品等级没有可用的%s词缀；装备和碎片均不会消耗。" % TARGETS[operation].label)
	var limits: Dictionary = Catalog.RARITIES[instance.rarity]
	var reachable: Array[int] = []
	var empty_counts: Dictionary = {"prefix": 0, "suffix": 0}
	for count: int in range(int(limits.min_affixes), int(limits.max_affixes) + 1):
		if not _viable_pool(targeted, pool, empty_counts, limits, count - 1).is_empty():
			reachable.append(count)
	if reachable.is_empty():
		return _failure("no_legal_result", "目标词缀无法组成合法结果；装备和碎片均不会消耗。")
	var result: Dictionary = metadata(operation)
	result.merge({"ok": true, "code": "", "reason": "",
		"cost": {MATERIAL_ID: int(COSTS[instance.rarity])},
		"result_rarity": instance.rarity, "reachable_counts": reachable,
		"eligible_target_tiers": targeted.size()})
	return result


static func plan(instance: Variant, operation: Variant, seed_value: Variant, vocabulary: int = Catalog.CURRENT_VOCABULARY) -> Dictionary:
	var quoted: Dictionary = quote(instance, operation, vocabulary)
	if not quoted.ok:
		return quoted
	if not seed_value is int:
		return _failure("invalid_seed", "工艺种子必须为整数类型。")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var output: Dictionary = instance.duplicate(true)
	output.affixes = []
	var counts: Array = quoted.reachable_counts
	var count: int = int(counts[rng.randi_range(0, counts.size() - 1)])
	var limits: Dictionary = Catalog.RARITIES[output.rarity]
	while output.affixes.size() < count:
		var pool: Array[Dictionary] = Expansion._pool(output.base_id, int(output.item_level), output.affixes, vocabulary)
		var candidates: Array[Dictionary] = _target_pool(pool, operation) if output.affixes.is_empty() else pool
		var viable: Array[Dictionary] = _viable_pool(candidates, pool, Expansion._counts(output.affixes),
			limits, count - output.affixes.size() - 1)
		var chosen: Dictionary = _weighted_entry(rng, viable)
		if chosen.is_empty():
			return _failure("no_legal_result", "目标词缀无法组成合法结果；装备和碎片均不会消耗。")
		output.affixes.append({"id": chosen.id, "tier": int(chosen.tier),
			"value": rng.randi_range(int(chosen.min), int(chosen.max))})
	if not Catalog.validate_instance_for_version(output, vocabulary):
		return _failure("invalid_result", "定向重铸结果未通过装备目录验证。")
	var definition: Dictionary = Catalog.definition(output)
	if definition.is_empty():
		return _failure("invalid_result", "定向重铸结果无法派生装备属性。")
	var result: Dictionary = quoted.duplicate(true)
	result["instance"] = output
	result["definition"] = definition
	return result


static func _target_pool(pool: Array[Dictionary], operation: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in pool:
		if TARGETS[operation].families.has(entry.id):
			result.append(entry)
	return result


## Completion depends only on group and prefix/suffix, so prove it once for
## each pair and retain every eligible family-tier with its catalog weight.
static func _viable_pool(candidates: Array[Dictionary], pool: Array[Dictionary], counts: Dictionary,
		limits: Dictionary, remaining_count: int) -> Array[Dictionary]:
	var viable_groups: Dictionary = {}
	var result: Array[Dictionary] = []
	for entry: Dictionary in candidates:
		var key: String = str(entry.group) + ":" + str(entry.kind)
		if not viable_groups.has(key):
			var next_counts: Dictionary = counts.duplicate()
			next_counts[entry.kind] += 1
			var remaining: Array[Dictionary] = []
			for other: Dictionary in pool:
				if other.group != entry.group:
					remaining.append(other)
			viable_groups[key] = Expansion._can_complete(remaining, next_counts, limits, remaining_count)
		if viable_groups[key]:
			result.append(entry)
	return result


static func _weighted_entry(rng: RandomNumberGenerator, pool: Array[Dictionary]) -> Dictionary:
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


static func _failure(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason, "cost": {}}
