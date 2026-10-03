extends SceneTree
## Independent, read-only review of the four v0.20 crafting operations.
## Economy bounds use catalog tier gates, pool membership, group exclusivity
## and affix slots; seeds below are counterexample probes, not a proof.
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Expand = preload("res://scripts/items/crafting_expansion_rules.gd")
const Planner = preload("res://scripts/items/crafting_transaction_planner.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const ITEM_ID: String = "gear_000123"
const MATERIAL: String = "calibration_shard"
var checks: int = 0
var failures: int = 0
var failure_labels: Array[String] = []
var plans: int = 0
var fixtures: int = 0
var interval_count: int = 0
var worst_bounds: Dictionary = {}
var completed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for test: Callable in [_metadata_and_legacy, _catalog_intervals_and_bounds,
			_public_operation_probes, _planner_projection_contract]:
		completed = false
		test.call()
		_expect(completed, "Case completed without a script exception: " + test.get_method())
	print("Crafting economy review: %d catalog intervals, %d source fixtures, %d plans; %d checks, %d failures" % [
		interval_count, fixtures, plans, checks, failures])
	for label: String in failure_labels:
		print("REVIEW FAIL: " + label)
	for operation: String in worst_bounds:
		print("  %s conservative max salvage increase: %d" % [operation, int(worst_bounds[operation])])
	quit(0 if failures == 0 else 1)


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failure_labels.size() < 100:
			failure_labels.append(label)


func _item(base_id: String, level: int, rarity: String, affixes: Array = []) -> Dictionary:
	return {"id": ITEM_ID, "base_id": base_id, "rarity": rarity,
		"item_level": level, "affixes": affixes.duplicate(true)}


func _yield(item: Dictionary) -> int:
	if item.rarity == "normal":
		return 0
	var quote: Dictionary = Craft.salvage_quote(item)
	return int(quote.materials.get(MATERIAL, -1)) if quote.ok else -1


func _metadata_and_legacy() -> void:
	var expected_costs: Dictionary = {"enchant": 8, "elevate": 24, "augment": 6}
	_expect(Craft.operation_ids() == ["salvage", "recalibrate", "enchant", "elevate", "augment", "reforge"],
		"Four expansion operations append without replacing legacy salvage/calibration IDs")
	_expect(Expand.MATERIAL_ID == MATERIAL and Craft.MATERIAL_ID == MATERIAL,
		"Legacy and expansion rules share the existing single material")
	for operation: String in ["enchant", "elevate", "augment"]:
		_expect(int(Expand.OPERATIONS[operation].cost) == int(expected_costs[operation]),
			"Authored expansion cost is read from production rules: " + operation)
	_expect(Expand.OPERATIONS.reforge.cost_by_rarity == {"magic": 10, "rare": 28},
		"Reforge uses the authored rarity-specific prices")
	_expect(Craft.BALANCE.salvage_rarity_units == {"magic": 1, "rare": 3}
		and int(Craft.BALANCE.salvage_units_per_tier) == 1
		and int(Craft.BALANCE.recalibrate_cost_multiplier) == 2,
		"Existing salvage and recalibration arithmetic remains the sole legacy balance")
	_expect(Craft.seed_rules_version("salvage") == "original-crafting-prototype-v1"
		and Craft.seed_rules_version("recalibrate") == "original-crafting-prototype-v1",
		"Legacy operations keep their seed derivation version")
	var base_id: String = "cinder_reed"
	var source: Dictionary = _fixture(base_id, 16, "magic", 1, 0)
	if not source.is_empty():
		var salvage: Dictionary = Craft.operation_quote(source, "salvage")
		var recalibrate: Dictionary = Craft.operation_quote(source, "recalibrate")
		_expect(salvage.ok and salvage.materials.keys() == [MATERIAL] and salvage.cost.is_empty(),
			"Legacy recovery still pays the single calibration-shard material")
		_expect(recalibrate.ok and recalibrate.cost[MATERIAL] == 2 * salvage.materials[MATERIAL]
			and recalibrate.materials.is_empty(), "Legacy recalibration cost still derives from salvage value")
		_expect(Craft.operation_plan(source, "recalibrate", -17).ok,
			"Legacy recalibration remains executable through the original pure planner")
	completed = true


func _catalog_intervals_and_bounds() -> void:
	for base_id: String in Catalog.all_base_ids():
		var ranges: Array = _level_intervals(base_id)
		_expect(not ranges.is_empty(), "Catalog pool has level equivalence classes: " + base_id)
		for interval: Array in ranges:
			interval_count += 1
			var low: int = int(interval[0])
			var high: int = int(interval[1])
			var low_pool: Array[Dictionary] = _pool(base_id, low)
			var high_pool: Array[Dictionary] = _pool(base_id, high)
			_expect(_pool_signature(low_pool) == _pool_signature(high_pool),
				"Pool is constant throughout its tier-threshold interval: %s %d..%d" % [base_id, low, high])
			_bounds_for_interval(base_id, low)
			# Probe both sides of every authored threshold interval. The intervals
			# are derived from actual tier unlocks, not an arbitrary level sample.
			_probe_level(base_id, low)
			if high != low:
				_probe_level(base_id, high)
	completed = true


func _public_operation_probes() -> void:
	for base_id: String in Catalog.all_base_ids():
		for interval: Array in _level_intervals(base_id):
			var level: int = int(interval[0])
			var full_magic: Dictionary = _fixture(base_id, level, "magic", 1, 1)
			var full_rare: Dictionary = _fixture(base_id, level, "rare", 3, 3)
			for source: Dictionary in [full_magic, full_rare]:
				if source.is_empty():
					_expect(false, "Saturated affix fixture exists for every pool interval: " + base_id)
					continue
				var operation: String = "augment"
				var before: PackedByteArray = var_to_bytes(source)
				var raw: Dictionary = Expand.quote(source, operation)
				var quote: Dictionary = Craft.operation_quote(source, operation)
				_expect(not raw.ok and raw.code == "no_legal_result",
					"Magic-2 and rare-6 saturated sources reject before rolling: %s ilvl=%d %s" % [
					base_id, level, source.rarity])
				_assert_rejected_quote(quote, "no_legal_result", operation)
				var plan: Dictionary = Craft.operation_plan(source, operation, 55)
				_expect(not plan.ok and plan.code == "no_legal_result",
					"No-completion plan rejects with its quote reason: " + source.rarity)
				_assert_empty_failure_payload(plan)
				_expect(var_to_bytes(source) == before,
					"No-result quote and plan leave source fixture byte-identical")
	completed = true


func _probe_level(base_id: String, level: int) -> void:
	var normal: Dictionary = _item(base_id, level, "normal")
	_expect(Catalog.validate_instance(normal), "Normal source fixture passes the real catalog")
	_probe(normal, "enchant")
	for magic: Dictionary in _fixtures(base_id, level, "magic"):
		fixtures += 1
		_probe(magic, "elevate")
		_probe(magic, "augment")
		_probe(magic, "reforge")
	for rare: Dictionary in _fixtures(base_id, level, "rare"):
		fixtures += 1
		_probe(rare, "augment")
		_probe(rare, "reforge")


func _probe(source: Dictionary, operation: String) -> void:
	var before: PackedByteArray = var_to_bytes(source)
	var independent: Array[int] = _reachable_counts(source, operation)
	var raw: Dictionary = Expand.quote(source, operation)
	var quote: Dictionary = Craft.operation_quote(source, operation)
	_expect(var_to_bytes(source) == before, "Both quote implementations leave source unchanged: " + operation)
	if independent.is_empty():
		_expect(not raw.ok and raw.code == "no_legal_result",
			"Production rejects a state with no legal completion: %s/%s/%d/%d" % [source.base_id, operation, level_of(source), source.affixes.size()])
		_assert_rejected_quote(quote, "no_legal_result", operation)
		return
	_expect(raw.ok and raw.reachable_counts == independent,
		"Quote reachable counts match independent pool/group/slot DP: %s/%s/%d" % [source.base_id, operation, level_of(source)])
	_expect(quote.ok and quote.cost.keys() == [MATERIAL]
		and quote.cost[MATERIAL] == _price(operation, source.rarity),
		"Public quote exposes exact single-material price: " + operation)
	if not quote.ok:
		return
	_expect(quote.instance.is_empty() and quote.definition.is_empty() and quote.materials.is_empty(),
		"Quote contains no candidate, derived definition or material credit: " + operation)
	for seed_value: int in [-17, 0, 41]:
		_exercise_plan(source, operation, seed_value, independent)
	_expect(var_to_bytes(source) == before, "Plans cannot mutate the nested source fixture: " + operation)


func _exercise_plan(source: Dictionary, operation: String, seed_value: int, reachable: Array[int]) -> void:
	var before: PackedByteArray = var_to_bytes(source)
	var quote: Dictionary = Craft.operation_quote(source, operation)
	var plan: Dictionary = Craft.operation_plan(source, operation, seed_value)
	plans += 1
	_expect(plan.ok and plan.operation == operation and plan.cost == quote.cost
		and plan.materials.is_empty() and not plan.consumes_item,
		"Plan matches quote without crediting materials: %s/%s" % [operation, seed_value])
	if not plan.ok:
		_assert_empty_failure_payload(plan)
		return
	var output: Dictionary = plan.instance
	_expect(Catalog.validate_instance(output) and output.size() == 5,
		"Output remains a five-field catalog-valid equipment instance: " + operation)
	_expect(Catalog.validate_instance(JSON.parse_string(JSON.stringify(output))),
		"Output remains valid after serialized roundtrip: " + operation)
	_expect(output.id == source.id and output.base_id == source.base_id
		and output.item_level == source.item_level,
		"Craft preserves item identity, base and level: " + operation)
	_expect(plan.definition == Catalog.definition(output),
		"Output definition is delegated to EquipmentCatalog: " + operation)
	_expect(reachable.has(output.affixes.size()),
		"Rolled count is in independently verified reachable count set: " + operation)
	_assert_output_pool_and_slots(output)
	if operation in ["elevate", "augment"]:
		_expect(output.rarity == ("rare" if operation == "elevate" else source.rarity),
			"Preserving operation has the production result rarity: " + operation)
		for index: int in range(source.affixes.size()):
			_expect(var_to_bytes(output.affixes[index]) == var_to_bytes(source.affixes[index]),
				"Existing affix and order are byte-identical: %s #%d" % [operation, index])
	if operation == "augment":
		_expect(output.affixes.size() == source.affixes.size() + 1,
			"Augment adds exactly one affix")
	var cost: int = int(plan.cost[MATERIAL])
	var gain: int = _yield(output) - _yield(source)
	_expect(cost - gain > 0,
		"This concrete operation result strictly sinks balance plus salvage potential: %s cost=%d delta=%d" % [operation, cost, gain])
	_expect(var_to_bytes(source) == before, "Plan result retains no mutable alias to source")
	_expect(plan == Craft.operation_plan(source, operation, seed_value),
		"Same source and seed reproduce the same complete plan: " + operation)


func _assert_output_pool_and_slots(output: Dictionary) -> void:
	var pool_id: String = Catalog.pool_for_base(output.base_id)
	var profile: Dictionary = Catalog.pool_profile(pool_id)
	var limits: Dictionary = Catalog.RARITIES[output.rarity]
	var prefixes: int = 0
	var suffixes: int = 0
	var groups: Dictionary = {}
	for affix: Dictionary in output.affixes:
		var family: Dictionary = Catalog.affix_definition(affix.id)
		_expect(profile.affix_ids.has(affix.id) and Catalog.family_eligible(affix.id, output.base_id),
			"Rolled family is in this base's real pool and eligible: " + affix.id)
		_expect(not groups.has(family.group), "No mutually exclusive group repeats: " + str(family.group))
		groups[family.group] = true
		if family.kind == "prefix": prefixes += 1
		else: suffixes += 1
		var tier: Dictionary = family.tiers[int(affix.tier) - 1]
		_expect(int(output.item_level) >= int(tier.level) and int(tier.weight) > 0,
			"Rolled tier is unlocked and positive-weight: %s T%d" % [affix.id, int(affix.tier)])
		_expect(affix.value is int and int(affix.value) >= int(tier.min) and int(affix.value) <= int(tier.max),
			"Rolled value respects its finite inclusive tick range: " + affix.id)
	_expect(prefixes <= int(limits.max_prefixes) and suffixes <= int(limits.max_suffixes),
		"Rolled output respects prefix/suffix capacities: " + output.rarity)


func _bounds_for_interval(base_id: String, level: int) -> void:
	var pool: Array[Dictionary] = _pool(base_id, level)
	var magic_limits: Dictionary = Catalog.RARITIES.magic
	var rare_limits: Dictionary = Catalog.RARITIES.rare
	var magic_max: int = _extreme_affix_sum(pool, {"prefix": 0, "suffix": 0}, magic_limits, true)
	var magic_min: int = _legal_affix_sum(pool, magic_limits, false)
	var rare_max: int = _legal_affix_sum(pool, rare_limits, true)
	var rare_min: int = _legal_affix_sum(pool, rare_limits, false)
	_expect(magic_max >= 0 and magic_min >= 0 and rare_max >= 0 and rare_min >= 0,
		"Actual pool admits legal magic and rare counts at this threshold class: " + base_id)
	if min(min(magic_max, magic_min), min(rare_max, rare_min)) < 0:
		return
	var highest_tier: int = 0
	for entry: Dictionary in pool:
		highest_tier = maxi(highest_tier, int(entry.tier))
	var bounds: Dictionary = {
		"enchant": 1 + magic_max,
		# Deliberately conservative: maximum legal rare output minus minimum
		# legal magic input, even where retained groups make that pair impossible.
		"elevate": (3 + rare_max) - (1 + magic_min),
		"augment": highest_tier,
		"reforge_magic": (1 + magic_max) - (1 + magic_min),
		"reforge_rare": (3 + rare_max) - (3 + rare_min),
	}
	var costs: Dictionary = {"enchant": 8, "elevate": 24, "augment": 6,
		"reforge_magic": 10, "reforge_rare": 28}
	for operation: String in bounds:
		var bound: int = int(bounds[operation])
		_expect(int(costs[operation]) > bound,
			"Authored cost strictly exceeds all-result salvage increase upper bound: %s %s ilvl=%d cost=%d bound=%d" % [
			base_id, operation, level, int(costs[operation]), bound])
		if not worst_bounds.has(operation): worst_bounds[operation] = bound
		else: worst_bounds[operation] = maxi(int(worst_bounds[operation]), bound)


func _legal_affix_sum(pool: Array[Dictionary], limits: Dictionary, maximize: bool) -> int:
	var result: int = -1
	for count: int in range(int(limits.min_affixes), int(limits.max_affixes) + 1):
		var value: int = _extreme_affix_sum(pool, {"prefix": 0, "suffix": 0}, limits, maximize, count)
		if value < 0:
			continue
		if result < 0 or (value > result if maximize else value < result):
			result = value
	return result


func _extreme_affix_sum(pool: Array[Dictionary], initial_counts: Dictionary, limits: Dictionary,
		maximize: bool, exact_added: int = -1) -> int:
	var group_options: Dictionary = {}
	for entry: Dictionary in pool:
		var group_id: String = str(entry.group)
		if not group_options.has(group_id): group_options[group_id] = {"prefix": [], "suffix": []}
		group_options[group_id][entry.kind].append(int(entry.tier))
	var states: Dictionary = {Vector2i.ZERO: 0}
	for group_id: String in group_options:
		var following: Dictionary = states.duplicate()
		for state: Vector2i in states:
			for kind: String in ["prefix", "suffix"]:
				if group_options[group_id][kind].is_empty():
					continue
				var next: Vector2i = state + (Vector2i.RIGHT if kind == "prefix" else Vector2i.DOWN)
				if exact_added >= 0 and next.x + next.y > exact_added:
					continue
				var max_key: String = "max_" + kind + "es"
				if int(initial_counts[kind]) + (next.x if kind == "prefix" else next.y) > int(limits[max_key]):
					continue
				var tier: int = int(group_options[group_id][kind][0])
				for candidate_tier: int in group_options[group_id][kind]:
					if candidate_tier > tier if maximize else candidate_tier < tier:
						tier = candidate_tier
				var value: int = int(states[state]) + tier
				if not following.has(next) or (value > int(following[next]) if maximize else value < int(following[next])):
					following[next] = value
		states = following
	var result: int = -1
	for state: Vector2i in states:
		if exact_added >= 0 and state.x + state.y != exact_added:
			continue
		if exact_added < 0 and state.x + state.y < int(limits.min_affixes):
			continue
		if state.x + state.y > int(limits.max_affixes):
			continue
		var value: int = int(states[state])
		if result < 0 or (value > result if maximize else value < result):
			result = value
	return result


func _reachable_counts(source: Dictionary, operation: String) -> Array[int]:
	var rule: Dictionary = Expand.OPERATIONS[operation]
	var rarity: String = source.rarity if str(rule.result_rarity).is_empty() else str(rule.result_rarity)
	var kept: Array = source.affixes.duplicate(true) if rule.preserves_affixes else []
	var counts: Dictionary = _counts(kept)
	var blocked: Dictionary = {}
	for affix: Dictionary in kept:
		blocked[Catalog.affix_definition(affix.id).group] = true
	var pool: Array[Dictionary] = _pool(source.base_id, int(source.item_level), blocked)
	var limits: Dictionary = Catalog.RARITIES[rarity]
	var first: int = kept.size() + 1 if operation == "augment" else int(limits.min_affixes)
	var last: int = first if operation == "augment" else int(limits.max_affixes)
	var result: Array[int] = []
	for target: int in range(first, last + 1):
		if target < int(limits.min_affixes) or target > int(limits.max_affixes):
			continue
		if _extreme_affix_sum(pool, counts, limits, true, target - kept.size()) >= 0:
			result.append(target)
	return result


func _pool(base_id: String, level: int, blocked: Dictionary = {}) -> Array[Dictionary]:
	var profile: Dictionary = Catalog.pool_profile(Catalog.pool_for_base(base_id))
	var result: Array[Dictionary] = []
	for family_id: String in profile.affix_ids:
		if not Catalog.family_eligible(family_id, base_id):
			continue
		var family: Dictionary = Catalog.affix_definition(family_id)
		if blocked.has(family.group):
			continue
		for tier: Dictionary in family.tiers:
			if level >= int(tier.level) and int(tier.weight) > 0:
				result.append({"id": family_id, "group": family.group, "kind": family.kind,
					"tier": int(tier.tier), "weight": int(tier.weight), "min": int(tier.min), "max": int(tier.max)})
	return result


func _pool_signature(pool: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in pool:
		result.append("%s:%s:%d:%d" % [entry.id, entry.kind, int(entry.tier), int(entry.weight)])
	result.sort()
	return result


func _level_intervals(base_id: String) -> Array:
	var profile: Dictionary = Catalog.pool_profile(Catalog.pool_for_base(base_id))
	var starts: Array[int] = [Catalog.MIN_ITEM_LEVEL]
	for family_id: String in profile.affix_ids:
		if not Catalog.family_eligible(family_id, base_id):
			continue
		for tier: Dictionary in Catalog.affix_definition(family_id).tiers:
			var unlock: int = int(tier.level)
			if int(tier.weight) > 0 and unlock >= Catalog.MIN_ITEM_LEVEL and unlock <= Catalog.MAX_ITEM_LEVEL \
				and not starts.has(unlock):
				starts.append(unlock)
	starts.sort()
	var result: Array = []
	for index: int in range(starts.size()):
		var low: int = starts[index]
		var high: int = Catalog.MAX_ITEM_LEVEL if index + 1 == starts.size() else starts[index + 1] - 1
		result.append([low, high])
	return result


func _pool_choices(base_id: String, level: int, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var profile: Dictionary = Catalog.pool_profile(Catalog.pool_for_base(base_id))
	for family_id: String in profile.affix_ids:
		if not Catalog.family_eligible(family_id, base_id):
			continue
		var family: Dictionary = Catalog.affix_definition(family_id)
		if family.kind != kind:
			continue
		var first: Dictionary = {}
		for tier: Dictionary in family.tiers:
			if level >= int(tier.level) and int(tier.weight) > 0:
				first = tier
				break
		if first.is_empty():
			continue
		result.append({"id": family_id, "group": family.group, "kind": kind,
			"tier": int(first.tier), "value": int(first.min)})
	return result


func _fixture(base_id: String, level: int, rarity: String, prefixes: int, suffixes: int) -> Dictionary:
	var by_group: Dictionary = {}
	var order: Array[String] = []
	for kind: String in ["prefix", "suffix"]:
		for choice: Dictionary in _pool_choices(base_id, level, kind):
			var group_id: String = str(choice.group)
			if not by_group.has(group_id):
				by_group[group_id] = []
				order.append(group_id)
			by_group[group_id].append(choice)
	var selected: Array = _select_groups(order, by_group, 0, prefixes, suffixes, [])
	if selected.size() != prefixes + suffixes:
		return {}
	var canonical: Array = []
	for choice: Dictionary in selected:
		canonical.append({"id": choice.id, "tier": choice.tier, "value": choice.value})
	return _item(base_id, level, rarity, canonical)


func _select_groups(order: Array[String], by_group: Dictionary, index: int,
		prefixes_left: int, suffixes_left: int, selected: Array) -> Array:
	if prefixes_left == 0 and suffixes_left == 0:
		return selected.duplicate(true)
	if index >= order.size():
		return []
	var group_id: String = order[index]
	for choice: Dictionary in by_group[group_id]:
		if choice.kind == "prefix" and prefixes_left > 0:
			selected.append(choice.duplicate(true))
			var found: Array = _select_groups(order, by_group, index + 1,
				prefixes_left - 1, suffixes_left, selected)
			selected.pop_back()
			if not found.is_empty():
				return found
		elif choice.kind == "suffix" and suffixes_left > 0:
			selected.append(choice.duplicate(true))
			var found: Array = _select_groups(order, by_group, index + 1,
				prefixes_left, suffixes_left - 1, selected)
			selected.pop_back()
			if not found.is_empty():
				return found
	return _select_groups(order, by_group, index + 1, prefixes_left, suffixes_left, selected)


func _fixtures(base_id: String, level: int, rarity: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var splits: Array = []
	if rarity == "magic":
		splits = [[1, 0], [0, 1], [1, 1]]
	else:
		splits = [[1, 3], [2, 2], [3, 1], [2, 3], [3, 2], [3, 3]]
	for split: Array in splits:
		var item: Dictionary = _fixture(base_id, level, rarity, int(split[0]), int(split[1]))
		if item.is_empty():
			_expect(false, "Catalog has a legal fixture for rarity/count/slot split: %s ilvl=%d %s %s" % [
				base_id, level, rarity, split])
			continue
		_expect(Catalog.validate_instance(item), "Built source fixture passes actual catalog: " + str(item))
		result.append(item)
	return result


func _counts(affixes: Array) -> Dictionary:
	var result: Dictionary = {"prefix": 0, "suffix": 0}
	for affix: Dictionary in affixes:
		result[Catalog.affix_definition(affix.id).kind] += 1
	return result


func _price(operation: String, rarity: String) -> int:
	var rule: Dictionary = Expand.OPERATIONS[operation]
	return int(rule.cost_by_rarity[rarity]) if rule.has("cost_by_rarity") else int(rule.cost)


func _assert_rejected_quote(result: Dictionary, code: String, operation: String) -> void:
	_expect(not result.ok and result.code == code and not result.reason.is_empty(),
		"Rejected quote has stable code and explanation: " + operation)
	_assert_empty_failure_payload(result)


func _assert_empty_failure_payload(result: Dictionary) -> void:
	for key: String in ["cost", "materials", "source_instance", "instance", "definition"]:
		_expect(result[key].is_empty(), "Failure exposes no partial transaction field: " + key)
	_expect(not result.consumes_item, "Rejected plan never requests consumption")


func _planner_projection_contract() -> void:
	var states: Array = []
	var normal: Dictionary = _item("cinder_reed", 16, "normal")
	states.append([normal, "enchant"])
	var magic_one: Dictionary = _fixture("cinder_reed", 16, "magic", 1, 0)
	var magic_pair: Dictionary = _fixture("cinder_reed", 16, "magic", 1, 1)
	var rare_four: Dictionary = _fixture("cinder_reed", 16, "rare", 2, 2)
	var rare_five: Dictionary = _fixture("cinder_reed", 16, "rare", 2, 3)
	var rare_six: Dictionary = _fixture("cinder_reed", 16, "rare", 3, 3)
	states.append([magic_one, "elevate"])
	states.append([magic_one, "augment"])
	states.append([magic_pair, "reforge"])
	states.append([rare_four, "augment"])
	states.append([rare_five, "augment"])
	states.append([rare_six, "reforge"])
	for entry: Array in states:
		var source: Dictionary = entry[0]
		var operation: String = entry[1]
		if source.is_empty():
			_expect(false, "Planner contract source fixture exists: " + operation)
			continue
		var context: Dictionary = _context(source, 1000)
		var context_before: PackedByteArray = var_to_bytes(context)
		var quote: Dictionary = Planner.quote(context, operation, ITEM_ID)
		_expect(quote.ok and quote.keys().size() == Planner.QUOTE_FIELDS.size()
			and not quote.has("seed") and not quote.has("candidate") and not quote.has("instance"),
			"Planner quote is detached economics only: " + operation)
		_expect(var_to_bytes(context) == context_before,
			"Quote leaves the caller-owned context and material balance byte-identical: " + operation)
		if not quote.ok:
			continue
		var quote_for_plan: Dictionary = quote.duplicate(true)
		quote.source_instance.item_level = 1
		quote.cost[MATERIAL] = 0
		_expect(var_to_bytes(context) == context_before,
			"Mutating returned quote source/cost cannot mutate context or wallet: " + operation)
		quote = quote_for_plan
		var quote_before: PackedByteArray = var_to_bytes(quote)
		var projection: Dictionary = Planner.plan(context, quote, 20261003)
		_expect(projection.ok and projection.candidate.revision == context.revision + 1
			and projection.candidate.materials[MATERIAL] == context.materials[MATERIAL] - quote.cost[MATERIAL],
			"Projection debits a candidate balance and advances only its candidate revision: " + operation)
		_expect(var_to_bytes(context) == context_before and var_to_bytes(quote) == quote_before,
			"Planning does not mutate authoritative context, wallet or old quote: " + operation)
		if projection.ok:
			var candidate_before: PackedByteArray = var_to_bytes(projection.candidate)
			var repeat: Dictionary = Planner.plan(context, quote, 20261003)
			_expect(repeat.ok and var_to_bytes(repeat.candidate) == candidate_before,
				"Stateless planner repeats an uncommitted quote deterministically: " + operation)
			projection.candidate.equipment_instances[ITEM_ID].affixes.clear()
			projection.candidate.materials[MATERIAL] = 0
			_expect(var_to_bytes(context) == context_before and var_to_bytes(quote) == quote_before,
				"Mutating a candidate cannot mutate quote or authoritative balance: " + operation)
		var read_only: Dictionary = context.duplicate(true)
		read_only.save_writable = false
		var rejected: Dictionary = Planner.quote(read_only, operation, ITEM_ID)
		_expect(not rejected.ok and rejected.code == "save_read_only" and rejected.size() == 3,
			"Read-only context rejects before exposing a partial quote: " + operation)
		var denied_plan: Dictionary = Planner.plan(read_only, quote, 20261003)
		_expect(not denied_plan.ok and denied_plan.code == "save_read_only" and denied_plan.size() == 3
			and not denied_plan.has("candidate"),
			"Read-only context rejects before candidate construction: " + operation)
		_expect(var_to_bytes(read_only) == var_to_bytes(context.duplicate(true).merged({"save_writable": false}, true)),
			"Read-only rejection does not mutate its context: " + operation)
		var poor: Dictionary = context.duplicate(true)
		poor.materials[MATERIAL] = int(quote.cost[MATERIAL]) - 1
		var poor_before: PackedByteArray = var_to_bytes(poor)
		var poor_quote: Dictionary = Planner.quote(poor, operation, ITEM_ID)
		_expect(not poor_quote.ok and poor_quote.code == "insufficient_materials"
			and poor_quote.size() == 3 and not poor_quote.has("cost"),
			"Insufficient balance rejects with no partial quote: " + operation)
		var poor_plan: Dictionary = Planner.plan(poor, quote, 20261003)
		_expect(not poor_plan.ok and poor_plan.code == "insufficient_materials"
			and poor_plan.size() == 3 and not poor_plan.has("candidate"),
			"Insufficient balance rejects before candidate construction: " + operation)
		_expect(var_to_bytes(poor) == poor_before,
			"Insufficient-balance paths leave the caller wallet unchanged: " + operation)
		var stale: Dictionary = context.duplicate(true)
		stale.revision += 1
		var stale_result: Dictionary = Planner.plan(stale, quote, 20261003)
		_expect(not stale_result.ok and stale_result.code == "stale_quote" and stale_result.size() == 3
			and not stale_result.has("candidate"), "Projection rejects an old revision without partial state: " + operation)
		_expect(var_to_bytes(stale) == var_to_bytes(context.duplicate(true).merged({"revision": context.revision + 1}, true)),
			"Stale quote rejection leaves revised caller context unchanged: " + operation)
	# Nested detachment at the pure rules API boundary.
	var source: Dictionary = _fixture("cinder_reed", 16, "magic", 1, 0)
	var source_before: PackedByteArray = var_to_bytes(source)
	var quote: Dictionary = Craft.operation_quote(source, "elevate")
	quote.source_instance.affixes[0].value = 999
	quote.cost[MATERIAL] = 0
	_expect(var_to_bytes(source) == source_before,
		"Mutating a returned pure-rule quote cannot mutate the nested source item")
	completed = true


func _context(source: Dictionary, balance: int) -> Dictionary:
	return {"revision": 9, "inventory": [ITEM_ID], "equipment_instances": {ITEM_ID: source.duplicate(true)},
		"equipped": {}, "backpack_positions": {"item:" + ITEM_ID: Vector2i(0, 0)},
		"materials": {MATERIAL: balance}, "save_writable": true}


func level_of(item: Dictionary) -> int:
	return int(item.item_level)
