extends SceneTree
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Expansion = preload("res://scripts/items/crafting_expansion_rules.gd")
const Targeted = preload("res://scripts/items/targeted_reforge_rules.gd")
const EXPECTED_TARGETS: Dictionary = {
	"targeted_reforge_critical": ["global_critical_chance", "global_critical_multiplier"],
	"targeted_reforge_life_leech": ["attack_life_leech"],
	"targeted_reforge_mana_leech": ["attack_mana_leech"],
	"targeted_reforge_damage": ["runesong", "prismedge", "farweave", "coalglow", "rimeecho", "sparkthread",
		"attack_added_physical", "attack_added_fire", "spell_added_cold", "spell_added_lightning",
		"whetstone_edge", "tempered_edge"],
}
const BUILD_BASES: Array[String] = ["wayglass_token", "pulse_seed", "nine_slot_etched_ring", "nine_slot_threaded_gloves"]
const LEVELS: Array[int] = [1, 7, 8, 15, 16, 30]
var checks: int = 0
var failures: int = 0
var matrix_quotes: int = 0
var planned: int = 0


func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):
		quit(78)
		return
	_test_metadata()
	_test_invalid_requests()
	_test_feasible_target_filter()
	_test_catalog_matrix()
	_test_versioned_pools()
	_test_weights_and_tiers()
	print("Targeted reforge rules: %d checks, %d failures; %d quotes, %d bounded matrix plans" % [checks, failures, matrix_quotes, planned])
	quit(1 if failures else 0)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _test_metadata() -> void:
	check(Targeted.operation_ids() == EXPECTED_TARGETS.keys(), "Exactly four stable target operation IDs")
	check(Targeted.COSTS == {"magic": 16, "rare": 40}, "Explicit original prototype costs")
	for operation: String in EXPECTED_TARGETS:
		var meta: Dictionary = Targeted.metadata(operation)
		check(meta.has_all(["operation", "label", "description", "risk", "targeted", "target_id", "target_label"]), "Complete target metadata")
		check(meta.operation == operation and meta.label == "定向重铸" and meta.targeted, "Stable operation display metadata")
		check(meta.target_id == operation.trim_prefix("targeted_reforge_"), "Explicit target identifier")
		check(meta.description.contains("至少一条") and meta.risk.contains("不保证高阶"), "Guarantee and limitation are disclosed")
		check(Targeted.TARGETS[operation].families == EXPECTED_TARGETS[operation], "Target family membership is exact")
		meta.target_label = "mutated"
		check(Targeted.metadata(operation).target_label != "mutated", "Metadata detached")
	var ids: Array[String] = Targeted.operation_ids()
	ids.clear()
	check(Targeted.operation_ids().size() == 4 and Targeted.metadata("missing").is_empty(), "IDs detached and unknown metadata empty")


func _test_invalid_requests() -> void:
	var source: Dictionary = _fixture("wayglass_token", "magic", 30)
	var before: PackedByteArray = var_to_bytes(source)
	var operation: String = "targeted_reforge_critical"
	for invalid: Variant in [null, false, 1, 1.0, "", "reforge", "targeted_reforge_crit", "targeted_reforge_missing"]:
		_assert_rejected(Targeted.quote(source, invalid), "invalid_operation", "Unknown/non-string operation")
		_assert_rejected(Targeted.plan(source, invalid, 1), "invalid_operation", "Plan rejects unknown/non-string operation")
	for invalid: Variant in [null, false, 1, [], {}, "gear_490001"]:
		_assert_rejected(Targeted.quote(invalid, operation), "invalid_instance", "Non-instance input")
	var bad: Dictionary = source.duplicate(true)
	bad["extra"] = true
	_assert_rejected(Targeted.quote(bad, operation), "invalid_instance", "Extra instance field rejected")
	bad = source.duplicate(true)
	bad.affixes[0].value = 999999
	_assert_rejected(Targeted.quote(bad, operation), "invalid_instance", "Affix value range validated")
	bad = source.duplicate(true)
	bad.affixes.append(bad.affixes[0].duplicate(true))
	_assert_rejected(Targeted.quote(bad, operation), "invalid_instance", "Duplicate family/group rejected")
	bad = source.duplicate(true)
	bad.affixes[0].id = "attack_added_physical"
	_assert_rejected(Targeted.quote(bad, operation), "invalid_instance", "Cross-base affix rejected")
	bad = source.duplicate(true)
	bad.item_level = 8.5
	_assert_rejected(Targeted.quote(bad, operation), "invalid_instance", "Non-integral item level rejected")
	bad = source.duplicate(true)
	bad.item_level = 1
	bad.affixes[0].tier = 3
	_assert_rejected(Targeted.quote(bad, operation), "invalid_instance", "Locked tier rejected")
	_assert_rejected(Targeted.quote(_fixture("wayglass_token", "normal", 30), operation), "unsupported_rarity", "Normal equipment rejected")
	for invalid: Variant in [null, false, 1.0, "1", []]:
		_assert_rejected(Targeted.plan(source, operation, invalid), "invalid_seed", "Seed requires actual integer")
	for invalid_version: int in [0, 28]:
		_assert_rejected(Targeted.quote(source, operation, invalid_version), "invalid_instance", "Invalid vocabulary rejected")
	var unavailable: Dictionary = _fixture("ashwood_bow", "rare", 30)
	seed(49071)
	var next: int = randi()
	seed(49071)
	_assert_rejected(Targeted.quote(unavailable, operation), "no_legal_target", "Ineligible target quote")
	_assert_rejected(Targeted.plan(unavailable, operation, null), "no_legal_target", "No-target rejection precedes seed handling")
	check(randi() == next, "Rejected quote and plan leave global RNG untouched")
	check(var_to_bytes(source) == before, "All invalid calls preserve source bytes")


func _assert_rejected(result: Dictionary, code: String, label: String) -> void:
	check(not result.ok and result.code == code and not result.reason.is_empty(), label)
	check(result.cost.is_empty() and not result.has("instance") and not result.has("definition"), "Failure contains no debit or partial result")


func _test_feasible_target_filter() -> void:
	# Taking blocked_target consumes the only group with a suffix. Although a
	# different target remains, magic's one-prefix cap makes completion impossible.
	var bad: Dictionary = {"id": "blocked_target", "group": "shared", "kind": "prefix", "weight": 100, "tier": 1}
	var good: Dictionary = {"id": "safe_target", "group": "free", "kind": "prefix", "weight": 60, "tier": 1}
	var good_tier: Dictionary = {"id": "safe_target", "group": "free", "kind": "prefix", "weight": 30, "tier": 2}
	var suffix: Dictionary = {"id": "suffix", "group": "shared", "kind": "suffix", "weight": 100, "tier": 1}
	var candidates: Array[Dictionary] = [bad, good, good_tier]
	var pool: Array[Dictionary] = [bad, good, good_tier, suffix]
	var viable: Array[Dictionary] = Targeted._viable_pool(candidates, pool, {"prefix": 0, "suffix": 0}, Catalog.RARITIES.magic, 1)
	check(viable == [good, good_tier], "Guaranteed target excludes group dead end and retains both original weighted tiers")
	check(Targeted._viable_pool(candidates, pool, {"prefix": 1, "suffix": 0}, Catalog.RARITIES.magic, 0).is_empty(), "Full prefix cap excludes every additional prefix")
	check(Targeted._viable_pool(candidates, pool, {"prefix": 0, "suffix": 0}, Catalog.RARITIES.rare, 5).is_empty(), "Raw candidate count cannot bypass distinct-group capacity")


func _test_catalog_matrix() -> void:
	var bases: Array[String] = Catalog.all_base_ids()
	check(bases.size() == 14, "Matrix includes all fourteen current bases")
	for base_id: String in bases:
		for level: int in LEVELS:
			for rarity: String in ["magic", "rare"]:
				var source: Dictionary = _fixture(base_id, rarity, level)
				check(Catalog.validate_instance(source), "Matrix source is legal: %s/%s/%d" % [base_id, rarity, level])
				var before: PackedByteArray = var_to_bytes(source)
				for operation: String in EXPECTED_TARGETS:
					var available: bool = not base_id.begins_with("nine_slot_") if operation == "targeted_reforge_damage" else BUILD_BASES.has(base_id)
					var context: String = "%s/%s/%d/%s" % [base_id, rarity, level, operation]
					seed(49072)
					var next: int = randi()
					seed(49072)
					var quote: Dictionary = Targeted.quote(source, operation)
					matrix_quotes += 1
					check(randi() == next, "Quote leaves global RNG untouched: " + context)
					check(quote.ok == available, "Availability matches catalog base scope: " + context)
					check(not quote.has("instance") and not quote.has("seed") and not quote.has("definition"), "Quote contains no roll: " + context)
					if not available:
						_assert_rejected(quote, "no_legal_target", "No eligible family: " + context)
						continue
					check(quote.cost == {"calibration_shard": 16 if rarity == "magic" else 40}, "Exact fee: " + context)
					check(quote.reachable_counts == ([1, 2] if rarity == "magic" else [4, 5, 6]), "All legal counts reachable: " + context)
					var target_pool: Array[Dictionary] = Targeted._target_pool(Expansion._pool(base_id, level, []), operation)
					_check_target_tiers(target_pool, base_id, level, operation)
					check(quote.eligible_target_tiers == target_pool.size(), "Quote reports actual available family-tiers")
					for seed_value: int in [0, -49049]:
						seed(49073)
						var expected_global: int = randi()
						seed(49073)
						var result: Dictionary = Targeted.plan(source, operation, seed_value)
						planned += 1
						check(randi() == expected_global, "Plan uses only local RNG: " + context)
						check(result.ok, "Reachable target planned: " + context)
						if not result.ok:
							continue
						check(result == Targeted.plan(source, operation, seed_value), "Same signed seed is deterministic: " + context)
						_check_result(source, result, operation, Catalog.CURRENT_VOCABULARY)
					check(var_to_bytes(source) == before, "Source preserved: " + context)
	check(matrix_quotes == 672 and planned == 504, "Bounded matrix has expected coverage")


func _check_target_tiers(pool: Array[Dictionary], base_id: String, level: int, operation: String) -> void:
	var expected_count: int = 0
	var profile: Dictionary = Catalog.pool_profile(Catalog.current_pool_for_base(base_id))
	for family_id: String in EXPECTED_TARGETS[operation]:
		if not profile.affix_ids.has(family_id) or not Catalog.family_eligible(family_id, base_id):
			continue
		for tier: Dictionary in Catalog.affix_definition(family_id).tiers:
			if int(tier.level) > level or int(tier.weight) <= 0:
				continue
			expected_count += 1
			var matching: Array[Dictionary] = []
			for entry: Dictionary in pool:
				if entry.id == family_id and entry.tier == tier.tier:
					matching.append(entry)
			check(matching.size() == 1, "Every eligible family-tier appears exactly once")
			if matching.size() == 1:
				check(matching[0].weight == tier.weight and matching[0].min == tier.min and matching[0].max == tier.max, "Catalog weights and inclusive ranges preserved")
	check(pool.size() == expected_count, "No locked or non-target family-tier enters guarantee pool")


func _check_result(source: Dictionary, result: Dictionary, operation: String, vocabulary: int) -> void:
	var output: Dictionary = result.instance
	check(Catalog.validate_instance_for_version(output, vocabulary), "Final result passes selected vocabulary validation")
	check(output.keys() == source.keys() and output.id == source.id and output.base_id == source.base_id and output.item_level == source.item_level and output.rarity == source.rarity, "Instance shape, ID, base, ilvl and rarity preserved")
	var hit: bool = false
	var groups: Dictionary = {}
	var counts: Dictionary = {"prefix": 0, "suffix": 0}
	var profile: Dictionary = Catalog.pool_profile(Catalog.pool_for_base_version(output.base_id, vocabulary))
	for affix: Dictionary in output.affixes:
		var family: Dictionary = Catalog.affix_definition(affix.id)
		var tier: Dictionary = family.tiers[int(affix.tier) - 1]
		hit = hit or EXPECTED_TARGETS[operation].has(affix.id)
		check(not groups.has(family.group), "No repeated affix group")
		groups[family.group] = true
		counts[family.kind] += 1
		check(profile.affix_ids.has(affix.id) and Catalog.family_eligible(affix.id, output.base_id), "Affix remains in eligible versioned base pool")
		check(tier.level <= output.item_level and affix.value >= tier.min and affix.value <= tier.max, "Tier unlock and inclusive roll limits")
	var limits: Dictionary = Catalog.RARITIES[output.rarity]
	check(hit and EXPECTED_TARGETS[operation].has(output.affixes[0].id), "Guaranteed first family matches selected target")
	check(output.affixes.size() >= limits.min_affixes and output.affixes.size() <= limits.max_affixes and counts.prefix <= limits.max_prefixes and counts.suffix <= limits.max_suffixes, "Rarity count and prefix/suffix limits")
	check(result.definition == Catalog.definition(output), "Derived definition delegates to existing catalog")
	check(result.cost == {"calibration_shard": 16 if source.rarity == "magic" else 40}, "Plan fee matches rarity")


func _test_versioned_pools() -> void:
	# One supported historical vocabulary proves filtering; no historical sweep.
	var source: Dictionary = _fixture("wayglass_token", "rare", 30, 26)
	for operation: String in EXPECTED_TARGETS:
		var result: Dictionary = Targeted.plan(source, operation, 49026, 26)
		if operation == "targeted_reforge_damage":
			check(result.ok, "Legacy damage target remains available without new vocabulary")
			if result.ok:
				_check_result(source, result, operation, 26)
		else:
			_assert_rejected(result, "no_legal_target", "Build target absent from pre-v27 pool")
	var modern: Dictionary = {"id": "gear_490002", "base_id": "wayglass_token", "rarity": "magic", "item_level": 1,
		"affixes": [{"id": "attack_life_leech", "tier": 1, "value": 20}]}
	_assert_rejected(Targeted.quote(modern, "targeted_reforge_damage", 26), "invalid_instance", "Source itself must belong to selected vocabulary")


func _test_weights_and_tiers() -> void:
	var source: Dictionary = _fixture("wayglass_token", "magic", 30)
	var operation: String = "targeted_reforge_life_leech"
	var pool: Array[Dictionary] = Targeted._target_pool(Expansion._pool(source.base_id, 30, []), operation)
	var histogram: Dictionary = {1: 0, 2: 0, 3: 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 49098
	for _sample: int in range(1900):
		var picked: Dictionary = Targeted._weighted_entry(rng, pool)
		histogram[int(picked.tier)] += 1
	# Wide deterministic tolerances detect uniform-tier or best-tier selection.
	check(histogram[1] >= 850 and histogram[1] <= 1150, "T1 follows catalog weight 100")
	check(histogram[2] >= 450 and histogram[2] <= 750, "T2 follows catalog weight 60")
	check(histogram[3] >= 190 and histogram[3] <= 410, "T3 follows catalog weight 30")
	var seen_tiers: Dictionary = {}
	var seen_counts: Dictionary = {}
	var rare_counts: Dictionary = {}
	var changed: bool = false
	for seed_value: int in range(32):
		var result: Dictionary = Targeted.plan(source, operation, seed_value)
		check(result.ok, "Bounded high-ilvl sample succeeds")
		if result.ok:
			seen_tiers[result.instance.affixes[0].tier] = true
			seen_counts[result.instance.affixes.size()] = true
			changed = changed or result.instance.affixes != source.affixes
		var rare_result: Dictionary = Targeted.plan(_fixture(source.base_id, "rare", 30), operation, seed_value)
		check(rare_result.ok, "Bounded rare count sample succeeds")
		if rare_result.ok:
			rare_counts[rare_result.instance.affixes.size()] = true
	check(seen_tiers.size() == 3 and seen_tiers.has(1), "High ilvl permits every target tier and does not guarantee high tier")
	check(seen_counts.size() == 2 and rare_counts.size() == 3, "Every feasible magic and rare affix count is reachable")
	check(changed, "Reforge replaces the source affix set")
	var detached: Dictionary = Targeted.plan(source, operation, 49099)
	detached.instance.affixes.clear()
	detached.cost.calibration_shard = 0
	check(Catalog.validate_instance(source) and Targeted.plan(source, operation, 49099).cost.calibration_shard == 16, "Plan nested payload and costs are detached")
	print("Weighted target tier sample: ", histogram)


func _fixture(base_id: String, rarity: String, level: int, vocabulary: int = Catalog.CURRENT_VOCABULARY) -> Dictionary:
	var result: Dictionary = {"id": "gear_490001", "base_id": base_id, "rarity": rarity, "item_level": level, "affixes": []}
	if rarity == "normal":
		return result
	var needed: Dictionary = {"prefix": 1 if rarity == "magic" else 2, "suffix": 0 if rarity == "magic" else 2}
	var used_groups: Dictionary = {}
	var profile: Dictionary = Catalog.pool_profile(Catalog.pool_for_base_version(base_id, vocabulary))
	for family_id: String in profile.affix_ids:
		var family: Dictionary = Catalog.affix_definition(family_id)
		if not Catalog.family_eligible(family_id, base_id) or needed[family.kind] == 0 or used_groups.has(family.group):
			continue
		var tier: Dictionary = family.tiers[0]
		result.affixes.append({"id": family_id, "tier": int(tier.tier), "value": int(tier.min)})
		needed[family.kind] -= 1
		used_groups[family.group] = true
	return result
