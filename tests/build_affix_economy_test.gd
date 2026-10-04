extends SceneTree
## v0.42 independent current-vocabulary economy/reachability proof.
## Tier-sum DP and exhaustive retained group/kind states establish bounds.
## Seeded plans supplement the proof; they do not establish reachability.
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Expand = preload("res://scripts/items/crafting_expansion_rules.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Build = preload("res://scripts/items/build_affix_profile.gd")
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
var retained_states: int = 0
var topology_count: int = 0
var new_family_sources: int = 0
var forced_new_family_outcomes: int = 0
var current_outputs: int = 0
var bound_rows: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for test: Callable in [_metadata_and_legacy, _current_profile_contract,
			_catalog_intervals_and_bounds, _exhaustive_retained_topologies,
			_public_operation_probes, _new_family_operation_contract, _invalid_slots_and_tiers]:
		completed = false
		test.call()
		_expect(completed, "Case completed without a script exception: " + test.get_method())
	_expect(interval_count == 42, "Fourteen current bases have exactly 42 unlock intervals")
	print("Build affix economy: %d catalog intervals, %d topology classes, %d exhaustive retained states, %d representative fixtures, %d plans, %d new-family sources; %d checks, %d failures" % [
		interval_count, topology_count, retained_states, fixtures, plans, new_family_sources, checks, failures])
	print("Current-catalog validated outputs: %d" % current_outputs)
	print("Forced new-family/tier output count witnesses: %d" % forced_new_family_outcomes)
	for label: String in failure_labels:
		print("REVIEW FAIL: " + label)
	for operation: String in worst_bounds:
		print("  %s all-result salvage increase upper bound: %d" % [operation, int(worst_bounds[operation])])
	for row: Dictionary in bound_rows:
		print("BOUND " + JSON.stringify(row))
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
		_expect(ranges == [[1, 7], [8, 15], [16, 30]], "Derived interval partition uses every positive-weight tier gate: " + base_id)
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
	current_outputs += 1
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
	var pool_id: String = Catalog.current_pool_for_base(output.base_id)
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
		# Retained affixes cancel from salvage delta; only rarity + added tiers remain.
		"elevate": _elevation_gain_bound(base_id, level),
		"augment": highest_tier,
		"reforge_magic": (1 + magic_max) - (1 + magic_min),
		"reforge_rare": (3 + rare_max) - (3 + rare_min),
	}
	var costs: Dictionary = {"enchant": 8, "elevate": 24, "augment": 6,
		"reforge_magic": 10, "reforge_rare": 28}
	bound_rows.append({"base": base_id, "level": level, "pool": Catalog.current_pool_for_base(base_id), "bounds": bounds.duplicate(true)})
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
	var profile: Dictionary = Catalog.pool_profile(Catalog.current_pool_for_base(base_id))
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
	var profile: Dictionary = Catalog.pool_profile(Catalog.current_pool_for_base(base_id))
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
	var profile: Dictionary = Catalog.pool_profile(Catalog.current_pool_for_base(base_id))
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


func level_of(item: Dictionary) -> int:
	return int(item.item_level)


func _current_profile_contract() -> void:
	_expect(Catalog.CURRENT_VOCABULARY == 27 and Catalog.all_base_ids().size() == 14,
		"Proof domain is vocabulary 27 and the fourteen existing bases")
	_expect(Catalog.RARITIES.magic.min_affixes == 1 and Catalog.RARITIES.magic.max_affixes == 2
		and Catalog.RARITIES.magic.max_prefixes == 1 and Catalog.RARITIES.magic.max_suffixes == 1,
		"Magic proof domain is one or two affixes with one slot per kind")
	_expect(Catalog.RARITIES.rare.min_affixes == 4 and Catalog.RARITIES.rare.max_affixes == 6
		and Catalog.RARITIES.rare.max_prefixes == 3 and Catalog.RARITIES.rare.max_suffixes == 3,
		"Rare proof domain is four, five or six affixes with three slots per kind")
	for base_id: String in Catalog.all_base_ids():
		var current: String = Catalog.current_pool_for_base(base_id)
		var original: String = Catalog.pool_for_base(base_id)
		_expect(current == Catalog.pool_for_base_version(base_id, 27), "Current and explicit v27 profile match: " + base_id)
		_expect(original == Catalog.pool_for_base_version(base_id, 26), "Historical v26 retains the original profile: " + base_id)
		for family_id: String in Catalog.pool_profile(current).affix_ids:
			if not Catalog.family_eligible(family_id, base_id): continue
			var family: Dictionary = Catalog.affix_definition(family_id)
			_expect(family.kind in ["prefix", "suffix"] and not str(family.group).is_empty(),
				"Every valid source family belongs to the proved group/kind domain")
			for tier_index: int in range(family.tiers.size()):
				var tier: Dictionary = family.tiers[tier_index]
				_expect(int(tier.weight) > 0 and int(tier.tier) == tier_index + 1
					and int(tier.level) >= Catalog.MIN_ITEM_LEVEL and int(tier.level) <= Catalog.MAX_ITEM_LEVEL,
					"No catalog-valid source tier is excluded by the positive-weight proof pool")
		for interval: Array in _level_intervals(base_id):
			for level: int in [int(interval[0]), int(interval[1])]:
				var expected: Array[Dictionary] = _pool(base_id, level)
				_expect(_pool_signature(expected) == _pool_signature(Expand._pool(base_id, level, [])),
					"Production default crafting pool equals independently read current profile: %s/%d" % [base_id, level])
				_expect(_pool_signature(expected) == _pool_signature(Expand._pool(base_id, level, [], 27)),
					"Explicit v27 crafting pool equals the current profile: %s/%d" % [base_id, level])
				for entry: Dictionary in expected:
					_expect(int(entry.tier) >= 1 and int(entry.tier) <= 3 and int(entry.weight) > 0,
						"All proof entries have positive weights and T1..T3")
					_expect(entry.kind in ["prefix", "suffix"] and int(entry.min) <= int(entry.max),
						"All proof entries have a supported kind and nonempty integer roll range")
		var current_ids: Array[String] = []
		for entry: Dictionary in _pool(base_id, 16):
			if not current_ids.has(entry.id): current_ids.append(entry.id)
		for family_id: String in Build.AFFIX_IDS:
			_expect(current_ids.has(family_id) == Build.ALLOWED_BASE_IDS.has(base_id),
				"New family is craftable exactly on its four allowed existing bases: %s/%s" % [base_id, family_id])
			var historical: Array[Dictionary] = Expand._pool(base_id, 16, [], 26)
			var historical_has_new: bool = false
			for entry: Dictionary in historical:
				if entry.id == family_id: historical_has_new = true
			_expect(not historical_has_new, "Historical crafting pool never rolls a v27 family")
	# A deliberately shared cross-kind group tests the independent extremum model.
	var shared: Array[Dictionary] = [
		{"group": "shared", "kind": "prefix", "tier": 3},
		{"group": "shared", "kind": "suffix", "tier": 3},
	]
	_expect(_extreme_affix_sum(shared, {"prefix": 0, "suffix": 0}, Catalog.RARITIES.magic, true, 2) == -1,
		"Independent DP cannot spend one exclusion group on both a prefix and suffix")
	completed = true


## Family/tier/value variants with the same retained (group, kind) set have the
## same completion problem. Enumerate every such source set, not random seeds.
## Each current pool keeps its group/kind topology across all tier intervals;
## that checked equivalence lets us enumerate it once per base at level 1.
func _exhaustive_retained_topologies() -> void:
	for base_id: String in Catalog.all_base_ids():
		var choices: Array[Dictionary] = _group_kind_choices(_pool(base_id, Catalog.MIN_ITEM_LEVEL))
		var graph: Array[String] = _topology_signature(choices)
		for interval: Array in _level_intervals(base_id):
			_expect(_topology_signature(_group_kind_choices(_pool(base_id, int(interval[0])))) == graph,
				"Every tier interval has the same retained-state topology: " + base_id)
		topology_count += 1
		var before: int = retained_states
		_enumerate_retained(base_id, choices, 0, [], {}, 0, 0)
		print("TOPOLOGY %s groups/kinds=%d retained_states=%d" % [base_id, choices.size(), retained_states - before])
	completed = true


func _group_kind_choices(pool: Array[Dictionary]) -> Array[Dictionary]:
	var seen: Dictionary = {}
	var result: Array[Dictionary] = []
	for entry: Dictionary in pool:
		var key: String = str(entry.group) + ":" + str(entry.kind)
		if not seen.has(key):
			seen[key] = true
			result.append(entry.duplicate(true))
	return result


func _topology_signature(choices: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in choices:
		result.append(str(entry.group) + ":" + str(entry.kind))
	result.sort()
	return result


func _enumerate_retained(base_id: String, choices: Array[Dictionary], start: int,
		affixes: Array, groups: Dictionary, prefixes: int, suffixes: int) -> void:
	var count: int = affixes.size()
	if count > 0 and prefixes <= 1 and suffixes <= 1:
		_verify_retained_state(_item(base_id, Catalog.MIN_ITEM_LEVEL, "magic", affixes), ["elevate", "augment"])
	if count >= 4:
		_verify_retained_state(_item(base_id, Catalog.MIN_ITEM_LEVEL, "rare", affixes), ["augment"])
	if count == 6: return
	for index: int in range(start, choices.size()):
		var choice: Dictionary = choices[index]
		if groups.has(choice.group): continue
		var next_p: int = prefixes + int(choice.kind == "prefix")
		var next_s: int = suffixes + int(choice.kind == "suffix")
		if next_p > 3 or next_s > 3: continue
		groups[choice.group] = true
		affixes.append({"id": choice.id, "tier": int(choice.tier), "value": int(choice.min)})
		_enumerate_retained(base_id, choices, index + 1, affixes, groups, next_p, next_s)
		affixes.pop_back()
		groups.erase(choice.group)


func _verify_retained_state(source: Dictionary, operations: Array) -> void:
	retained_states += 1
	_expect(Catalog.validate_instance(source), "Exhaustive retained-state representative is catalog valid")
	var before: PackedByteArray = var_to_bytes(source)
	for operation: String in operations:
		var independently_reachable: Array[int] = _reachable_counts(source, operation)
		var actual: Dictionary = Expand.quote(source, operation)
		_expect(actual.ok == not independently_reachable.is_empty(),
			"Every retained group/kind state agrees on availability: %s/%s/%s" % [source.base_id, source.rarity, operation])
		if actual.ok:
			_expect(actual.reachable_counts == independently_reachable,
				"Every advertised target count is reachable and every reachable count is advertised")
		else:
			_expect(actual.code == "no_legal_result", "Empty completion set has the exact no-result rejection")
		if operation == "elevate":
			_expect(independently_reachable == [4, 5, 6], "Every legal magic group/kind state can elevate to rare 4/5/6")
		elif source.affixes.size() == int(Catalog.RARITIES[source.rarity].max_affixes):
			_expect(independently_reachable.is_empty(), "Saturated rarity has no augment result")
		else:
			_expect(independently_reachable == [source.affixes.size() + 1],
				"Every unsaturated legal source has exactly one remaining-slot augment count")
	_expect(var_to_bytes(source) == before, "Exhaustive availability checks leave source bytes untouched")


## Enumerating retained one/two-affix group/kind sets is sufficient for exact
## elevation bounds: kept tiers/values cancel from salvage-output minus input.
func _elevation_gain_bound(base_id: String, level: int) -> int:
	var pool: Array[Dictionary] = _pool(base_id, level)
	var choices: Array[Dictionary] = _group_kind_choices(pool)
	var result: int = -1
	for first: int in range(choices.size()):
		result = maxi(result, _elevation_completion_bound(pool, [choices[first]]))
		for second: int in range(first + 1, choices.size()):
			if choices[first].group == choices[second].group or choices[first].kind == choices[second].kind: continue
			result = maxi(result, _elevation_completion_bound(pool, [choices[first], choices[second]]))
	return result


func _elevation_completion_bound(pool: Array[Dictionary], kept: Array) -> int:
	var blocked: Dictionary = {}
	var counts: Dictionary = {"prefix": 0, "suffix": 0}
	for entry: Dictionary in kept:
		blocked[entry.group] = true
		counts[entry.kind] += 1
	var remaining: Array[Dictionary] = []
	for entry: Dictionary in pool:
		if not blocked.has(entry.group): remaining.append(entry)
	var maximum: int = -1
	for target: int in [4, 5, 6]:
		var added: int = _extreme_affix_sum(remaining, counts, Catalog.RARITIES.rare, true, target - kept.size())
		if added >= 0: maximum = maxi(maximum, 2 + added)
	return maximum


func _new_family_operation_contract() -> void:
	for base_id: String in Build.ALLOWED_BASE_IDS:
		for interval: Array in _level_intervals(base_id):
			var level: int = int(interval[0])
			for family_id: String in Build.AFFIX_IDS:
				var family: Dictionary = Catalog.affix_definition(family_id)
				for tier: Dictionary in family.tiers:
					if int(tier.level) > level: continue
					var source: Dictionary = _item(base_id, level, "magic", [
						{"id": family_id, "tier": int(tier.tier), "value": int(tier.max)}])
					new_family_sources += 1
					_expect(Catalog.validate_instance(source) and not Catalog.validate_instance_for_version(source, 26),
						"Every new eligible family/tier source is current-valid and historical-invalid")
					_prove_forced_new_family_output_sizes(source)
					_check_salvage_calibration(source)
					for operation: String in ["elevate", "augment", "reforge"]:
						_probe(source, operation)
						var explicit: Dictionary = Craft.operation_plan(source, operation, 41, 27)
						_expect(explicit == Craft.operation_plan(source, operation, 41),
							"Explicit v27 and default current produce identical plans with new family sources")
						_assert_rejected_quote(Craft.operation_quote(source, operation, 26), "invalid_instance", operation)
			var all_new: Array = []
			for family_id: String in Build.AFFIX_IDS:
				var tier: Dictionary = Catalog.affix_definition(family_id).tiers[0]
				all_new.append({"id": family_id, "tier": 1, "value": int(tier.min)})
			var rare: Dictionary = _item(base_id, level, "rare", all_new)
			_expect(Catalog.validate_instance(rare), "All four new families coexist in one legal rare 2-prefix/2-suffix source")
			_check_salvage_calibration(rare)
			_probe(rare, "augment")
			_probe(rare, "reforge")
	completed = true


## Fix the new family/tier first, then solve the remaining group/slot problem.
## Every such fixed entry can occur in magic 1/2 and rare 4/5/6 output sets.
## Removing it from a 2/5/6-affix witness leaves a legal augment source; keeping
## any other one affix of a rare witness leaves a legal elevation source.
func _prove_forced_new_family_output_sizes(source: Dictionary) -> void:
	var family: Dictionary = Catalog.affix_definition(source.affixes[0].id)
	var remaining: Array[Dictionary] = _pool(source.base_id, int(source.item_level), {family.group: true})
	var initial: Dictionary = {"prefix": 0, "suffix": 0}
	initial[family.kind] = 1
	for target: int in [1, 2, 4, 5, 6]:
		var rarity: String = "magic" if target <= 2 else "rare"
		_expect(_extreme_affix_sum(remaining, initial, Catalog.RARITIES[rarity], true, target - 1) >= 0,
			"Fixed new family/tier has a legal output completion: %s/%s/T%d/count%d" % [
				source.base_id, source.affixes[0].id, int(source.affixes[0].tier), target])
		forced_new_family_outcomes += 1


func _check_salvage_calibration(source: Dictionary) -> void:
	var before: PackedByteArray = var_to_bytes(source)
	var expected_yield: int = 1 if source.rarity == "magic" else 3
	for entry: Dictionary in source.affixes: expected_yield += int(entry.tier)
	var salvage: Dictionary = Craft.operation_quote(source, "salvage")
	_expect(salvage.ok and salvage.materials == {MATERIAL: expected_yield}
		and salvage.cost.is_empty() and salvage.consumes_item and salvage.instance.is_empty(),
		"New families retain rarity-plus-tier-sum salvage formula without a replacement")
	var quote: Dictionary = Craft.operation_quote(source, "recalibrate")
	_expect(quote.ok and quote.cost == {MATERIAL: expected_yield * 2}
		and quote.instance.is_empty() and quote.definition.is_empty() and quote.materials.is_empty(),
		"New-family calibration quote costs twice salvage and never rolls a candidate")
	var plan: Dictionary = Craft.operation_plan(source, "recalibrate", -17)
	plans += 1
	_expect(plan.ok and plan.cost == quote.cost and Catalog.validate_instance(plan.instance),
		"New-family calibration plan remains catalog valid at the quoted price")
	if plan.ok:
		current_outputs += 1
		_assert_output_pool_and_slots(plan.instance)
		_expect(_yield(plan.instance) == expected_yield, "Calibration preserves salvage potential for all new families")
		_expect(plan.instance.id == source.id and plan.instance.base_id == source.base_id
			and plan.instance.item_level == source.item_level and plan.instance.rarity == source.rarity,
			"Calibration keeps item identity, base, level and rarity")
		for index: int in range(source.affixes.size()):
			_expect(plan.instance.affixes[index].id == source.affixes[index].id
				and plan.instance.affixes[index].tier == source.affixes[index].tier,
				"Calibration preserves each family/tier and its order")
		_expect(plan == Craft.operation_plan(source, "recalibrate", -17), "Calibration repeats deterministically")
	_expect(var_to_bytes(source) == before, "Salvage and calibration quotes/plans never mutate source")
	quote.source_instance.affixes[0].value = 99999
	quote.cost[MATERIAL] = 0
	_expect(var_to_bytes(source) == before, "Returned nested quote metadata is detached from source")


func _invalid_slots_and_tiers() -> void:
	for base_id: String in Build.ALLOWED_BASE_IDS:
		var rare: Dictionary = _fixture(base_id, 16, "rare", 2, 2)
		var source_before: PackedByteArray = var_to_bytes(rare)
		for family_id: String in Build.AFFIX_IDS:
			var family: Dictionary = Catalog.affix_definition(family_id)
			var duplicate: Dictionary = rare.duplicate(true)
			duplicate.affixes = [
				{"id": family_id, "tier": 1, "value": int(family.tiers[0].min)},
				{"id": family_id, "tier": 2, "value": int(family.tiers[1].min)},
				rare.affixes[2].duplicate(true), rare.affixes[3].duplicate(true)]
			_expect(not Catalog.validate_instance(duplicate), "Same new family at different tiers is never a legal combination")
			_assert_rejected_quote(Craft.operation_quote(duplicate, "reforge"), "invalid_instance", "reforge")
			var locked: Dictionary = _item(base_id, 7, "magic", [
				{"id": family_id, "tier": 2, "value": int(family.tiers[1].min)}])
			_expect(not Catalog.validate_instance(locked), "New T2 cannot appear below its level-8 gate")
			locked.item_level = 15
			locked.affixes[0] = {"id": family_id, "tier": 3, "value": int(family.tiers[2].min)}
			_expect(not Catalog.validate_instance(locked), "New T3 cannot appear below its level-16 gate")
		var over_prefix: Dictionary = _item(base_id, 16, "magic", [
			{"id": "attack_life_leech", "tier": 1, "value": 20},
			{"id": "attack_mana_leech", "tier": 1, "value": 10}])
		var over_suffix: Dictionary = _item(base_id, 16, "magic", [
			{"id": "global_critical_chance", "tier": 1, "value": 15},
			{"id": "global_critical_multiplier", "tier": 1, "value": 5}])
		_expect(not Catalog.validate_instance(over_prefix) and not Catalog.validate_instance(over_suffix),
			"New families cannot bypass the one-prefix/one-suffix magic slot capacities")
		var rare_prefix_overflow: Dictionary = _fixture(base_id, 16, "rare", 4, 2)
		var rare_suffix_overflow: Dictionary = _fixture(base_id, 16, "rare", 2, 4)
		_expect(not rare_prefix_overflow.is_empty() and not rare_suffix_overflow.is_empty()
			and not Catalog.validate_instance(rare_prefix_overflow) and not Catalog.validate_instance(rare_suffix_overflow),
			"Six distinct families cannot bypass the three-prefix/three-suffix rare slot capacities")
		for invalid: Dictionary in [over_prefix, over_suffix, rare_prefix_overflow, rare_suffix_overflow]:
			_assert_rejected_quote(Craft.operation_quote(invalid, "reforge"), "invalid_instance", "reforge")
		_expect(var_to_bytes(rare) == source_before, "Invalid-fixture construction keeps its valid source untouched")
	completed = true
