extends SceneTree
## v103: bounded coverage of the four appended resistance targets, using lawful
## Catalog-generated source items and byte-exact b7d98c5 old-operation oracles.
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Expansion = preload("res://scripts/items/crafting_expansion_rules.gd")
const Targeted = preload("res://scripts/items/targeted_reforge_rules.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const OldTargeted = preload("res://docs/qa/v103-rules/frozen/targeted_reforge_rules.gd")
const OldCraft = preload("res://docs/qa/v103-rules/frozen/crafting_rules.gd")
const TARGETS: Dictionary = {
	"targeted_reforge_fire_resistance": ["emberward", "ring_emberward"],
	"targeted_reforge_cold_resistance": ["rimeward", "ring_rimeward"],
	"targeted_reforge_lightning_resistance": ["stormward", "ring_stormward"],
	"targeted_reforge_chaos_resistance": ["ring_voidward"],
}
const LEVELS: Array[int] = [1, 8, 16, 30]
const SEEDS: Array[int] = [0, 1, 7, 42, 103, 49049, -103, 2147483647]
const OLD_OPERATIONS: Array[String] = ["salvage", "recalibrate", "enchant", "elevate", "augment", "reforge"]
const REPORT_DEFAULT: String = "res://docs/qa/v103-rules/results.json"
var checks: int = 0
var failures: int = 0
var matrix_quotes: int = 0
var matrix_plans: int = 0
var historical_quotes: int = 0
var historical_plans: int = 0
var old_target_quotes: int = 0
var old_target_plans: int = 0
var old_six_quotes: int = 0
var old_six_plans: int = 0
var fixture_cache: Dictionary = {}
var fixture_provenance: Dictionary = {}
var witnesses: Array[Dictionary] = []
var observed_counts: Dictionary = {"magic": {}, "rare": {}}
var observed_tiers: Dictionary = {}
var start_msec: int = 0


func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v103-"):
		printerr("Use an isolated /tmp/godot-m1-v103-* XDG_DATA_HOME")
		quit(78)
		return
	start_msec = Time.get_ticks_msec()
	if OS.get_environment("V103_RESISTANCE_RULES_SCOPE") in ["current_matrix", "current_and_historical"]:
		_test_frozen_integrity()
		_test_current_matrix()
		if OS.get_environment("V103_RESISTANCE_RULES_SCOPE") == "current_and_historical":
			_test_historical_vocabularies()
		_write_report()
		print("Resistance current-matrix rerun: %d checks, %d failures; %d quotes, %d plans" % [checks, failures, matrix_quotes, matrix_plans])
		quit(1 if failures else 0)
		return
	_test_frozen_integrity()
	_test_metadata()
	_test_rejections()
	_test_current_matrix()
	_test_historical_vocabularies()
	_test_whole_reforge_and_isolation()
	_test_old_four_differential()
	_test_old_six_differential()
	_write_report()
	print("Resistance targeted reforge: %d checks, %d failures; %d current quotes, %d current plans; %d old-target quotes, %d old-target plans; %d old-six quotes, %d old-six plans" % [checks, failures, matrix_quotes, matrix_plans, old_target_quotes, old_target_plans, old_six_quotes, old_six_plans])
	quit(1 if failures else 0)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _same(actual: Variant, expected: Variant, label: String) -> void:
	check(var_to_bytes(actual) == var_to_bytes(expected), label)


func _rejected(result: Dictionary, code: String, label: String) -> void:
	check(not result.ok and result.code == code and not result.reason.is_empty(), label)
	check(result.cost.is_empty() and not result.has("instance") and not result.has("definition"), "No debit/partial result: " + label)


func _test_frozen_integrity() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v103-rules/frozen/manifest.json"))
	check(manifest.baseline_commit == "b7d98c5b94c2c39f6f258835b28cfc32c4cd34d9", "Pinned exact predecessor commit")
	for entry: Dictionary in manifest.frozen:
		check(FileAccess.get_sha256("res://" + entry.path) == entry.transformed_sha256, "Frozen oracle integrity: " + entry.path)
		if entry.original_path == "scripts/items/crafting_rules.gd":
			check(FileAccess.get_sha256("res://" + entry.original_path) == entry.source_sha256, "CraftingRules source unchanged from b7")
	for entry: Dictionary in manifest.shared_unchanged_dependencies:
		check(FileAccess.get_sha256("res://" + entry.path) == entry.sha256, "Shared catalog/dependency unchanged from b7: " + entry.path)


func _test_metadata() -> void:
	var expected: Array[String] = OldTargeted.operation_ids()
	expected.append_array(TARGETS.keys())
	check(Targeted.operation_ids() == expected, "Old target order followed by four resistance targets")
	check(Targeted.COSTS == {"magic": 16, "rare": 40}, "Unchanged magic16/rare40 fee")
	for operation: String in OldTargeted.operation_ids():
		_same(Targeted.metadata(operation), OldTargeted.metadata(operation), "Original metadata byte-identical: " + operation)
	for operation: String in TARGETS:
		check(Targeted.TARGETS[operation].families == TARGETS[operation], "Exact resistance family mapping: " + operation)
		var metadata: Dictionary = Targeted.metadata(operation)
		check(metadata.operation == operation and metadata.targeted and metadata.target_id == operation.trim_prefix("targeted_reforge_"), "Stable target metadata: " + operation)
		check(metadata.description.contains("至少一条") and metadata.description.contains("替换全部") and metadata.risk.contains("不保证高阶"), "Guarantee, whole reforge, and risk disclosed")
		_same(Craft.operation_metadata(operation), metadata, "Craft exposes target metadata")
		metadata.target_label = "changed"
		check(Targeted.metadata(operation).target_label != "changed", "Metadata is detached")
		check(Craft.seed_rules_version(operation) == OldCraft.TARGETED_RULES_VERSION + ":" + operation, "New operations use existing target namespace")
	var detached_ids: Array[String] = Targeted.operation_ids()
	detached_ids.clear()
	check(Targeted.operation_ids() == expected and Targeted.metadata("missing").is_empty(), "Detached operation IDs and unknown metadata")


func _test_rejections() -> void:
	var source: Dictionary = _fixture("nine_slot_etched_ring", "rare", 30)
	var before: PackedByteArray = var_to_bytes(source)
	var operation: String = "targeted_reforge_chaos_resistance"
	for invalid: Variant in [null, false, 1, 1.0, "", "reforge", "targeted_reforge_resistance"]:
		_rejected(Targeted.quote(source, invalid), "invalid_operation", "Invalid operation")
		_rejected(Targeted.plan(source, invalid, 0), "invalid_operation", "Invalid operation plan")
	for invalid: Variant in [null, false, 1, [], {}, "gear_103001"]:
		_rejected(Targeted.quote(invalid, operation), "invalid_instance", "Non-instance input")
	for invalid: Variant in [null, false, 1.0, "1", []]:
		_rejected(Targeted.plan(source, operation, invalid), "invalid_seed", "Actual integer seed required")
	for version: int in [0, 35, 36, 38, 40, 50, 52]:
		_rejected(Targeted.quote(source, operation, version), "invalid_instance", "Unsupported explicit vocabulary %d" % version)
	var malformed: Dictionary = source.duplicate(true)
	malformed.extra = true
	_rejected(Targeted.quote(malformed, operation), "invalid_instance", "Unknown instance field")
	malformed = source.duplicate(true)
	malformed.affixes.resize(3)
	_rejected(Targeted.quote(malformed, operation), "invalid_instance", "Three-affix ordinary rare is invalid")
	malformed = source.duplicate(true)
	malformed.affixes[0].value = 999999
	_rejected(Targeted.quote(malformed, operation), "invalid_instance", "Out-of-range ticks")
	malformed = source.duplicate(true)
	malformed.affixes[1] = malformed.affixes[0].duplicate(true)
	_rejected(Targeted.quote(malformed, operation), "invalid_instance", "Duplicate family/group")
	malformed = source.duplicate(true)
	malformed.item_level = 8.5
	_rejected(Targeted.quote(malformed, operation), "invalid_instance", "Non-integral ilvl")
	for target: String in TARGETS:
		_rejected(Targeted.quote(_fixture("nine_slot_etched_ring", "normal", 30), target), "unsupported_rarity", "Normal gear rejects target")
	_same(source, bytes_to_var(before), "Invalid calls preserve input bytes")


func _test_current_matrix() -> void:
	for base_id: String in Catalog.all_base_ids():
		for level: int in LEVELS:
			for rarity: String in ["magic", "rare"]:
				var source: Dictionary = _fixture(base_id, rarity, level)
				var source_bytes: PackedByteArray = var_to_bytes(source)
				for operation: String in TARGETS:
					var context: String = "%s/%s/%d/%s" % [base_id, rarity, level, operation]
					var legal: bool = base_id == "nine_slot_etched_ring" or (base_id == "emberhide_vest" and operation != "targeted_reforge_chaos_resistance")
					seed(103001)
					var expected_global: int = randi()
					seed(103001)
					var quote: Dictionary = Targeted.quote(source, operation)
					matrix_quotes += 1
					check(randi() == expected_global, "Quote consumes no global RNG: " + context)
					check(quote.ok == legal, "Exact legal base scope: " + context)
					check(not quote.has("instance") and not quote.has("definition") and not quote.has("seed"), "Quote does not roll: " + context)
					if not legal:
						_rejected(quote, "no_legal_target", "Unrelated base rejects: " + context)
						seed(103002)
						expected_global = randi()
						seed(103002)
						_same(Targeted.plan(source, operation, null), quote, "Unavailable target rejects before seed validation")
						check(randi() == expected_global, "Rejected plan consumes no global RNG")
						continue
					check(quote.cost == {"calibration_shard": 16 if rarity == "magic" else 40}, "Exact rarity fee: " + context)
					check(quote.reachable_counts == ([1, 2] if rarity == "magic" else [4, 5, 6]), "All legal counts reachable: " + context)
					_check_target_pool(base_id, level, operation, quote)
					for seed_value: int in SEEDS:
						seed(103003)
						expected_global = randi()
						seed(103003)
						var result: Dictionary = Targeted.plan(source, operation, seed_value)
						matrix_plans += 1
						check(randi() == expected_global, "Successful plan uses local RNG: " + context)
						check(result.ok, "Legal plan succeeds: " + context)
						if result.ok:
							_check_result(source, result, operation, Catalog.CURRENT_VOCABULARY)
							_same(result, Targeted.plan(source, operation, seed_value), "Same integer seed is byte-deterministic")
							if level == 30 and seed_value == 0:
								witnesses.append({"operation": operation, "plan_seed": seed_value, "generation": fixture_provenance[_fixture_key(base_id, rarity, level, Catalog.CURRENT_VOCABULARY, 103103)], "source": source.duplicate(true), "result": result.duplicate(true)})
				check(var_to_bytes(source) == source_bytes, "Current matrix source remains untouched")
	check(matrix_quotes == Catalog.all_base_ids().size() * LEVELS.size() * 2 * TARGETS.size(), "Complete bounded all-base quote coverage")
	check(matrix_plans == 7 * LEVELS.size() * 2 * SEEDS.size(), "Exactly 448 legal current plans")
	check(observed_counts.magic.size() == 2 and observed_counts.rare.size() == 3, "Bounded sample reaches magic1/2 and rare4/5/6 counts")
	check(observed_tiers.has(1), "High ilvl still permits low target tier; an eight-seed sample need not visit every weighted tier")


func _check_target_pool(base_id: String, level: int, operation: String, quote: Dictionary) -> void:
	var pool: Array[Dictionary] = Targeted._target_pool(Expansion._pool(base_id, level, []), operation)
	var tiers: int = 1 if level < 8 else (2 if level < 16 else 3)
	check(pool.size() == tiers and quote.eligible_target_tiers == tiers, "One legal family with exact unlocked tier count")
	for entry: Dictionary in pool:
		var family: Dictionary = Catalog.affix_definition(entry.id)
		var tier: Dictionary = family.tiers[int(entry.tier) - 1]
		check(TARGETS[operation].has(entry.id) and Catalog.family_eligible(entry.id, base_id), "Target pool contains only legal resistance family")
		check(family.kind == "suffix" and family.unit == "percent" and family.stat == operation.trim_prefix("targeted_reforge_"), "Existing percent resistance suffix only")
		check(tier.level <= level and entry.weight == tier.weight and entry.min == tier.min and entry.max == tier.max, "Existing tier gate, weights and inclusive tick range")


func _check_result(source: Dictionary, result: Dictionary, operation: String, vocabulary: int) -> void:
	var output: Dictionary = result.instance
	check(Catalog.validate_instance_for_version(output, vocabulary), "Result validates against exact vocabulary")
	check(output.keys() == source.keys() and output.id == source.id and output.base_id == source.base_id and output.item_level == source.item_level and output.rarity == source.rarity, "UID/base/ilvl/rarity/shape preserved")
	var groups: Dictionary = {}
	var counts: Dictionary = {"prefix": 0, "suffix": 0}
	var target_hits: int = 0
	var profile: Dictionary = Catalog.pool_profile(Catalog.pool_for_base_version(output.base_id, vocabulary))
	for affix: Dictionary in output.affixes:
		var family: Dictionary = Catalog.affix_definition(affix.id)
		var tier: Dictionary = family.tiers[int(affix.tier) - 1]
		if TARGETS[operation].has(affix.id):
			target_hits += 1
		check(not groups.has(family.group), "No repeated affix group")
		groups[family.group] = true
		counts[family.kind] += 1
		check(profile.affix_ids.has(affix.id) and Catalog.family_eligible(affix.id, output.base_id), "Every affix belongs to selected base/version")
		check(tier.level <= output.item_level and affix.value is int and affix.value >= tier.min and affix.value <= tier.max, "Every tier/value obeys existing bounds")
	var limits: Dictionary = Catalog.RARITIES[output.rarity]
	check(target_hits >= 1 and TARGETS[operation].has(output.affixes[0].id), "At least one mandatory legal resistance family")
	check(output.affixes.size() >= limits.min_affixes and output.affixes.size() <= limits.max_affixes and counts.prefix <= limits.max_prefixes and counts.suffix <= limits.max_suffixes, "Magic1–2 / rare4–6 and prefix/suffix caps")
	check(result.cost == {"calibration_shard": 16 if source.rarity == "magic" else 40}, "Plan charges unchanged rarity fee")
	_same(result.definition, Catalog.definition(output), "Definition uses actual Catalog result")
	_check_resistance_stats(output, result.definition.stats)
	if output.item_level == 30:
		observed_counts[output.rarity][output.affixes.size()] = true
		observed_tiers[output.affixes[0].tier] = true


func _check_resistance_stats(output: Dictionary, stats: Dictionary) -> void:
	var base_stats: Dictionary = Catalog.base_definition(output.base_id).stats
	for stat: String in ["fire_resistance", "cold_resistance", "lightning_resistance", "chaos_resistance"]:
		var expected: float = float(base_stats.get(stat, 0.0))
		for affix: Dictionary in output.affixes:
			var family: Dictionary = Catalog.affix_definition(affix.id)
			if family.stat == stat:
				check(family.unit == "percent", "Resistance is stored as percent ticks")
				expected += float(affix.value) / 100.0
		check(is_equal_approx(float(stats.get(stat, 0.0)), expected), "Catalog derived percent ticks /100: " + stat)
		check(not stats.has("maximum_" + stat + "_add") and not stats.has("max_" + stat) and not stats.has("maximum_" + stat), "No maximum resistance granted, including actual DefenseRules maximum_*_resistance_add key: " + stat)
	_same(stats, Catalog.get_stats(output), "Actual Catalog get_stats agrees with definition")


func _test_historical_vocabularies() -> void:
	for vocabulary: int in [34, 37, 39, 46, 51]:
		for base_id: String in ["emberhide_vest", "nine_slot_etched_ring"]:
			var source: Dictionary = _fixture(base_id, "rare", 30, vocabulary)
			for operation: String in TARGETS:
				var legal: bool = false
				if base_id == "emberhide_vest":
					legal = operation == "targeted_reforge_fire_resistance" or (vocabulary >= 37 and operation != "targeted_reforge_chaos_resistance")
				else:
					legal = vocabulary >= (51 if operation == "targeted_reforge_chaos_resistance" else 46)
				var quote: Dictionary = Targeted.quote(source, operation, vocabulary)
				historical_quotes += 1
				check(quote.ok == legal, "Historical target gate: %s/%d/%s" % [base_id, vocabulary, operation])
				var result: Dictionary = Targeted.plan(source, operation, 103, vocabulary)
				historical_plans += 1
				if legal:
					check(result.ok, "Legal historical plan succeeds")
					if result.ok:
						_check_result(source, result, operation, vocabulary)
				else:
					_rejected(quote, "no_legal_target", "Pre-introduction vocabulary has no target")
					_same(result, quote, "Historical rejected plan matches quote")
	var chaos: Dictionary = Targeted.plan(_fixture("nine_slot_etched_ring", "magic", 30), "targeted_reforge_chaos_resistance", 103)
	if chaos.ok:
		_rejected(Targeted.quote(chaos.instance, "targeted_reforge_fire_resistance", 46), "invalid_instance", "Current chaos-bearing source rejects old vocabulary")


func _test_whole_reforge_and_isolation() -> void:
	for base_id: String in ["emberhide_vest", "nine_slot_etched_ring"]:
		for rarity: String in ["magic", "rare"]:
			var source: Dictionary = _fixture(base_id, rarity, 30)
			var other: Dictionary = _fixture(base_id, rarity, 30, Catalog.CURRENT_VOCABULARY, 103104)
			check(var_to_bytes(source.affixes) != var_to_bytes(other.affixes), "Independent legal source affix set differs")
			for operation: String in TARGETS:
				if base_id == "emberhide_vest" and operation == "targeted_reforge_chaos_resistance":
					continue
				var before: PackedByteArray = var_to_bytes(source)
				var result: Dictionary = Targeted.plan(source, operation, 42)
				_same(result, Targeted.plan(other, operation, 42), "Same seed ignores every old affix, proving whole reforge")
				var original: Dictionary = result.duplicate(true)
				result.instance.affixes.clear()
				result.definition.stats.clear()
				result.cost.calibration_shard = 0
				result.reachable_counts.clear()
				check(var_to_bytes(source) == before, "Mutating nested plan output leaves source unchanged")
				_same(Targeted.plan(source, operation, 42), original, "Plan payload, costs, stats and reachability detached")
				var quote: Dictionary = Targeted.quote(source, operation)
				quote.cost.calibration_shard = 0
				quote.reachable_counts.clear()
				check(Targeted.quote(source, operation).cost.calibration_shard == (16 if rarity == "magic" else 40), "Quote cost detached")
				check(Targeted.quote(source, operation).reachable_counts == ([1, 2] if rarity == "magic" else [4, 5, 6]), "Quote reachability detached")


func _test_old_four_differential() -> void:
	var cases: Dictionary = {"wayglass_token": 26, "pulse_seed": 26, "nine_slot_etched_ring": 46, "nine_slot_threaded_gloves": 46, "emberhide_vest": 39, "ashwood_bow": 26}
	for base_id: String in cases:
		for vocabulary: int in [Catalog.CURRENT_VOCABULARY, int(cases[base_id])]:
			for rarity: String in ["magic", "rare"]:
				var source: Dictionary = _fixture(base_id, rarity, 30, vocabulary)
				var before: PackedByteArray = var_to_bytes(source)
				for operation: String in OldTargeted.operation_ids():
					var context: String = "%s/%s/v%d/%s" % [base_id, rarity, vocabulary, operation]
					_same(Targeted.quote(source, operation, vocabulary), OldTargeted.quote(source, operation, vocabulary), "Old target quote strict bytes: " + context)
					_same(Craft.operation_quote(source, operation, vocabulary), OldCraft.operation_quote(source, operation, vocabulary), "Old target Craft quote strict bytes: " + context)
					old_target_quotes += 1
					check(Craft.seed_rules_version(operation, vocabulary) == OldCraft.seed_rules_version(operation, vocabulary), "Original target seed salt unchanged")
					for seed_value: int in SEEDS:
						_same(Targeted.plan(source, operation, seed_value, vocabulary), OldTargeted.plan(source, operation, seed_value, vocabulary), "Old target plan strict bytes: " + context)
						_same(Craft.operation_plan(source, operation, seed_value, vocabulary), OldCraft.operation_plan(source, operation, seed_value, vocabulary), "Old target Craft plan strict bytes: " + context)
						old_target_plans += 1
				check(var_to_bytes(source) == before, "Old-target differential leaves source unchanged")


func _test_old_six_differential() -> void:
	for base_id: String in ["emberhide_vest", "nine_slot_etched_ring"]:
		for vocabulary: int in [Catalog.CURRENT_VOCABULARY, 26]:
			for operation: String in OLD_OPERATIONS:
				var rarity: String = "normal" if operation == "enchant" else ("magic" if operation in ["elevate", "augment"] else "rare")
				var source: Dictionary = _fixture(base_id, rarity, 30, vocabulary)
				if operation == "augment" and not Craft.operation_quote(source, operation, vocabulary).ok:
					for fixture_seed: int in range(103104, 103112):
						source = _fixture(base_id, rarity, 30, vocabulary, fixture_seed)
						if Craft.operation_quote(source, operation, vocabulary).ok:
							break
				var expected_salt: String = "original-crafting-prototype-v1" if operation in ["salvage", "recalibrate"] else ("original-crafting-prototype-v3-affix27" if vocabulary >= 27 else "original-crafting-prototype-v2") + ":" + operation
				check(Craft.seed_rules_version(operation, vocabulary) == expected_salt and Craft.seed_rules_version(operation, vocabulary) == OldCraft.seed_rules_version(operation, vocabulary), "Literal old-six salt retained")
				var quote: Dictionary = Craft.operation_quote(source, operation, vocabulary)
				check(quote.ok, "Representative old-six source is eligible: " + operation)
				_same(quote, OldCraft.operation_quote(source, operation, vocabulary), "Old-six quote strict bytes")
				old_six_quotes += 1
				for seed_value: int in SEEDS:
					_same(Craft.operation_plan(source, operation, seed_value, vocabulary), OldCraft.operation_plan(source, operation, seed_value, vocabulary), "Old-six plan strict bytes")
					old_six_plans += 1


func _fixture_key(base_id: String, rarity: String, level: int, vocabulary: int, fixture_seed: int) -> String:
	return "%s/%s/%d/v%d/s%d" % [base_id, rarity, level, vocabulary, fixture_seed]


func _fixture(base_id: String, rarity: String, level: int, vocabulary: int = Catalog.CURRENT_VOCABULARY, fixture_seed: int = 103103) -> Dictionary:
	var key: String = _fixture_key(base_id, rarity, level, vocabulary, fixture_seed)
	if fixture_cache.has(key):
		return fixture_cache[key].duplicate(true)
	var pool_id: String = Catalog.pool_for_base_version(base_id, vocabulary)
	var rng := RandomNumberGenerator.new()
	rng.seed = fixture_seed
	for attempt: int in range(128):
		var candidate: Dictionary = Catalog.generate_for_pool(rng, "gear_103001", level, rarity, pool_id)
		if not candidate.is_empty() and candidate.base_id == base_id:
			check(Catalog.validate_instance_for_version(candidate, vocabulary), "Real Catalog-generated fixture validates: " + key)
			fixture_cache[key] = candidate.duplicate(true)
			fixture_provenance[key] = {"method": "Catalog.generate_for_pool", "pool_id": pool_id, "vocabulary": vocabulary, "rng_seed": fixture_seed, "candidate_number": attempt + 1}
			return candidate
	check(false, "Could not generate requested lawful fixture in bounded attempts: " + key)
	return {}


func _write_report() -> void:
	var report: Dictionary = {"baseline_commit": "b7d98c5b94c2c39f6f258835b28cfc32c4cd34d9", "checks": checks, "failures": failures,
		"scope": OS.get_environment("V103_RESISTANCE_RULES_SCOPE") if not OS.get_environment("V103_RESISTANCE_RULES_SCOPE").is_empty() else "full_focused_suite", "current_base_count": Catalog.all_base_ids().size(), "levels": LEVELS, "seeds": SEEDS, "matrix_quotes": matrix_quotes, "matrix_plans": matrix_plans,
		"historical_quotes": historical_quotes, "historical_plans": historical_plans, "old_target_quotes": old_target_quotes, "old_target_plans": old_target_plans,
		"old_six_quotes": old_six_quotes, "old_six_plans": old_six_plans, "elapsed_msec": Time.get_ticks_msec() - start_msec,
		"equality": "var_to_bytes on entire quote and plan dictionaries, including typed numbers, array and dictionary order; JSON is reporting only",
		"oracle": "Stripped-class b7 TargetedReforgeRules and CraftingRules (targeted preload relocated); 13 shared unchanged dependencies SHA-256 guarded",
		"rng_scope": "Pure rules prove untouched global RNG and deterministic private seeded RNG only. External item/currency/global RNG ownership is tested by the separate model suite.",
		"observed_counts_at_level30": observed_counts, "observed_guaranteed_tiers_at_level30": observed_tiers.keys(), "generated_witnesses": witnesses}
	var path: String = OS.get_environment("V103_RESISTANCE_RULES_REPORT")
	if path.is_empty():
		path = REPORT_DEFAULT
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Report file can be written")
	if file != null:
		report.checks = checks
		report.failures = failures
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
