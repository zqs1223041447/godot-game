extends RefCounted
## Pure four-operation batch. Existing catalog remains the eligibility, tier,
## weight, group and instance authority; this module owns no wallet or save.
const Catalog = preload("res://docs/qa/v060-rules/frozen/equipment_catalog_v059.gd")
const MATERIAL_ID: String = "calibration_shard"
const OPERATIONS: Dictionary = {
	"enchant": {"name": "赋魔", "rarities": ["normal"], "result_rarity": "magic", "cost": 8,
		"preserves_affixes": false, "description": "普通装备变为魔法，随机获得1至2条合法词缀。"},
	"elevate": {"name": "升格", "rarities": ["magic"], "result_rarity": "rare", "cost": 24,
		"preserves_affixes": true, "description": "保留魔法装备已有词缀，升为稀有并补至4至6条。"},
	"augment": {"name": "补缀", "rarities": ["magic", "rare"], "result_rarity": "", "cost": 6,
		"preserves_affixes": true, "description": "保留已有词缀，向一个合法空位添加1条随机词缀。"},
	"reforge": {"name": "重铸", "rarities": ["magic", "rare"], "result_rarity": "", "cost_by_rarity": {"magic": 10, "rare": 28},
		"preserves_affixes": false, "description": "保持稀有度，重新生成全部词缀种类、阶级和数值；可能相同或更差。"},
}


static func metadata() -> Dictionary:
	return {"operations": OPERATIONS.duplicate(true), "material_id": MATERIAL_ID,
		"origin": "original", "tier_selection": "catalog_positive_weighted_family_tiers",
		"count_selection": "uniform_among_reachable_counts", "can_roll_same_values": true,
		"preserves": ["id", "base_id", "item_level"], "mutates_state": false,
		"economy": "Each operation costs more than the maximum possible increase in salvage value."}


static func quote(instance: Variant, operation: Variant, vocabulary: int = Catalog.CURRENT_VOCABULARY) -> Dictionary:
	if not operation is String or not OPERATIONS.has(operation):
		return _failure("invalid_operation", "未知工艺。")
	if not Catalog.validate_instance_for_version(instance, vocabulary):
		return _failure("invalid_instance", "装备实例未通过当前目录验证。")
	var rule: Dictionary = OPERATIONS[operation]
	if not rule.rarities.has(instance.rarity):
		return _failure("unsupported_rarity", "此装备稀有度不适用所选工艺。")
	var rarity: String = instance.rarity if rule.result_rarity.is_empty() else rule.result_rarity
	var kept: Array = instance.affixes.duplicate(true) if rule.preserves_affixes else []
	var limits: Dictionary = Catalog.RARITIES[rarity]
	var counts: Dictionary = _counts(kept)
	var pool: Array[Dictionary] = _pool(instance.base_id, int(instance.item_level), kept, vocabulary)
	var reachable: Array[int] = []
	var first: int = kept.size() + 1 if operation == "augment" else int(limits.min_affixes)
	var last: int = first if operation == "augment" else int(limits.max_affixes)
	for target: int in range(first, last + 1):
		if target >= int(limits.min_affixes) and target <= int(limits.max_affixes) \
				and _can_complete(pool, counts, limits, target - kept.size()):
			reachable.append(target)
	if reachable.is_empty():
		return _failure("no_legal_result", "没有可达的合法词缀结果；装备和碎片均不会消耗。")
	var cost: int = int(rule.cost_by_rarity[instance.rarity]) if rule.has("cost_by_rarity") else int(rule.cost)
	return {"ok": true, "code": "", "reason": "", "cost": {MATERIAL_ID: cost},
		"result_rarity": rarity, "kept": kept, "reachable_counts": reachable}


static func plan(instance: Variant, operation: Variant, seed_value: Variant, vocabulary: int = Catalog.CURRENT_VOCABULARY) -> Dictionary:
	var quoted: Dictionary = quote(instance, operation, vocabulary)
	if not quoted.ok:
		return quoted
	if not seed_value is int:
		return _failure("invalid_seed", "工艺种子必须为整数类型。")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var output: Dictionary = instance.duplicate(true)
	output.rarity = quoted.result_rarity
	output.affixes = quoted.kept.duplicate(true)
	var targets: Array = quoted.reachable_counts
	var target: int = int(targets[rng.randi_range(0, targets.size() - 1)])
	var limits: Dictionary = Catalog.RARITIES[output.rarity]
	while output.affixes.size() < target:
		var pool: Array[Dictionary] = _pool(output.base_id, int(output.item_level), output.affixes, vocabulary)
		var counts: Dictionary = _counts(output.affixes)
		var viable_groups: Dictionary = {}
		for entry: Dictionary in pool:
			var group_kind: String = str(entry.group) + ":" + str(entry.kind)
			if viable_groups.has(group_kind):
				continue
			var next_counts: Dictionary = counts.duplicate()
			next_counts[entry.kind] += 1
			var remaining: Array[Dictionary] = []
			for other: Dictionary in pool:
				if other.group != entry.group:
					remaining.append(other)
			viable_groups[group_kind] = _can_complete(remaining, next_counts, limits, target - output.affixes.size() - 1)
		var viable: Array[Dictionary] = []
		var total: int = 0
		for entry: Dictionary in pool:
			if viable_groups[str(entry.group) + ":" + str(entry.kind)]:
				viable.append(entry)
				total += int(entry.weight)
		if total <= 0:
			return _failure("no_legal_result", "没有可达的合法词缀结果；装备和碎片均不会消耗。")
		var roll: int = rng.randi_range(1, total)
		var chosen: Dictionary = {}
		for entry: Dictionary in viable:
			roll -= int(entry.weight)
			if roll <= 0:
				chosen = entry
				break
		output.affixes.append({"id": chosen.id, "tier": int(chosen.tier),
			"value": rng.randi_range(int(chosen.min), int(chosen.max))})
	if not Catalog.validate_instance_for_version(output, vocabulary):
		return _failure("invalid_result", "工艺结果未通过装备目录验证。")
	var definition: Dictionary = Catalog.definition(output)
	if definition.is_empty():
		return _failure("invalid_result", "工艺结果无法派生装备属性。")
	return {"ok": true, "code": "", "reason": "", "instance": output,
		"definition": definition, "cost": quoted.cost.duplicate(true)}


static func _pool(base_id: String, item_level: int, kept: Array, vocabulary: int = Catalog.CURRENT_VOCABULARY) -> Array[Dictionary]:
	var blocked: Dictionary = {}
	for entry: Dictionary in kept:
		blocked[Catalog.affix_definition(entry.id).group] = true
	var result: Array[Dictionary] = []
	var profile: Dictionary = Catalog.pool_profile(Catalog.pool_for_base_version(base_id, vocabulary))
	for id: String in profile.affix_ids:
		var family: Dictionary = Catalog.affix_definition(id)
		if blocked.has(family.group) or not Catalog.family_eligible(id, base_id):
			continue
		for tier: Dictionary in family.tiers:
			if item_level >= int(tier.level) and int(tier.weight) > 0:
				result.append({"id": id, "tier": int(tier.tier), "weight": int(tier.weight),
					"group": family.group, "kind": family.kind, "min": int(tier.min), "max": int(tier.max)})
	return result


static func _counts(affixes: Array) -> Dictionary:
	var result: Dictionary = {"prefix": 0, "suffix": 0}
	for affix: Dictionary in affixes:
		result[Catalog.affix_definition(affix.id).kind] += 1
	return result


## Group-level dynamic programming proves a completion exists before any RNG.
## A group shared across prefix/suffix may be selected at most once.
static func _can_complete(pool: Array[Dictionary], counts: Dictionary, limits: Dictionary, needed: int) -> bool:
	var prefix_room: int = int(limits.max_prefixes) - int(counts.prefix)
	var suffix_room: int = int(limits.max_suffixes) - int(counts.suffix)
	if needed < 0 or prefix_room < 0 or suffix_room < 0 or needed > prefix_room + suffix_room:
		return false
	if needed == 0:
		return true
	var groups: Dictionary = {}
	for entry: Dictionary in pool:
		var flags: int = 1 if entry.kind == "prefix" else 2
		groups[entry.group] = int(groups.get(entry.group, 0)) | flags
	var reachable: Dictionary = {Vector2i.ZERO: true}
	for group: String in groups:
		var following: Dictionary = reachable.duplicate()
		for counts_pair: Vector2i in reachable:
			for axis: int in range(2):
				if (int(groups[group]) & (1 << axis)) == 0:
					continue
				var next: Vector2i = counts_pair + (Vector2i.RIGHT if axis == 0 else Vector2i.DOWN)
				if next.x > prefix_room or next.y > suffix_room or next.x + next.y > needed:
					continue
				if next.x + next.y == needed:
					return true
				following[next] = true
		reachable = following
	return false


static func _failure(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason}
