extends SceneTree
## Focused contract test for the read-only crafting budget exporter.
const Exporter = preload("res://tools/export_crafting_budget.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")

const JSON_PATH: String = "res://docs/qa/crafting-budget.json"
const MARKDOWN_PATH: String = "res://docs/qa/CRAFTING_BUDGET.zh-CN.md"
const EXPECTED_BASES: int = 9
const EXPECTED_FAMILIES: int = 19

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var expected_first: int
	var expected_second: int
	seed(424242)
	expected_first = randi()
	expected_second = randi()
	seed(424242)
	var observed_first: int = randi()
	var report: Dictionary = Exporter.collect()
	var observed_second: int = randi()
	_expect(observed_first == expected_first and observed_second == expected_second,
		"Exporter leaves global RNG sequence unchanged")

	var repeated: Dictionary = Exporter.collect()
	_expect(JSON.stringify(report, "\t", true, true) == JSON.stringify(repeated, "\t", true, true),
		"Repeated collection is byte-deterministic")
	_expect(Exporter.render_markdown(report) == Exporter.render_markdown(repeated),
		"Repeated Markdown rendering is deterministic")
	_check_domain(report)
	_check_family_matrix(report)
	_check_economy_matrix(report)
	_check_examples(report)
	_check_written_artifacts(report)
	print("Crafting budget export: %d matrix rows, %d family pairs; %d checks, %d failures" % [
		report.economy_matrix.size(), report.family_eligibility_matrix.size(), checks, failures])
	quit(0 if failures == 0 else 1)


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


func _check_domain(report: Dictionary) -> void:
	_expect(Catalog.all_base_ids().size() == EXPECTED_BASES and Catalog.all_affix_ids().size() == EXPECTED_FAMILIES,
		"Tested catalog contains the requested 9 bases and 19 families")
	_expect(report.domain.base_count == EXPECTED_BASES and report.domain.family_count == EXPECTED_FAMILIES,
		"Export domain includes every base and family")
	_expect(report.domain.matrix_rows == EXPECTED_BASES * 30 * 3 and report.economy_matrix.size() == 810,
		"Full 9 x 30 x 3 base/level/rarity matrix is present")
	_expect(report.family_eligibility_matrix.size() == EXPECTED_BASES * EXPECTED_FAMILIES,
		"All 171 base/family eligibility pairs are present")
	_expect(report.analysis.exact_enumeration and report.analysis.enumeration_runs == 54,
		"Three unlock bands are exhaustively enumerated for both craftable rarities across nine bases")
	_expect(report.analysis.bounds_depend_on_seed == false and report.analysis.roll_value_assignments_enumerated == false,
		"Bounds are explicitly distinguished from seed examples and value-tick combinations")
	_expect(report.analysis.sample_examples == 2 and report.analysis.example_records == 3,
		"Two fixed-seed success examples are distinguished from the white-item rejection fixture")
	_expect(report.analysis.legal_tier_assignments_covered_by_analytic_endpoints > 0,
		"Tier assignments are covered by the exact endpoint calculation")


func _check_family_matrix(report: Dictionary) -> void:
	var seen: Dictionary = {}
	var seen_pairs: Dictionary = {}
	for row: Dictionary in report.economy_matrix:
		if not row.craftable:
			continue
		for family_id: String in row.families_that_can_appear:
			var key: String = "%s|%s|%s|%d" % [row.base_id, family_id, row.rarity, row.item_level]
			seen[key] = true
	for pair: Dictionary in report.family_eligibility_matrix:
		var pair_key: String = "%s|%s" % [pair.base_id, pair.family_id]
		_expect(not seen_pairs.has(pair_key), "Base/family pair is unique: " + pair_key)
		seen_pairs[pair_key] = true
		var profile: Dictionary = Catalog.pool_profile(Catalog.pool_for_base(pair.base_id))
		var catalog_eligible: bool = Catalog.family_eligible(pair.family_id, pair.base_id)
		var profile_allows: bool = profile.affix_ids.has(pair.family_id)
		_expect(pair.catalog_family_eligible == catalog_eligible and pair.generation_profile_allows == profile_allows,
			"Pair flags come directly from current catalog and profile: " + pair_key)
		_expect(pair.applicable == (catalog_eligible and profile_allows),
			"Applicability requires both base eligibility and the generation profile")
		_expect(pair.rarity_item_level_ranges.normal.is_empty(), "Normal items cannot contain an eligible craft family")
		for rarity: String in ["magic", "rare"]:
			var ranges: Array = pair.rarity_item_level_ranges[rarity]
			for item_level: int in range(Catalog.MIN_ITEM_LEVEL, Catalog.MAX_ITEM_LEVEL + 1):
				var should_appear: bool = seen.has("%s|%s|%s|%d" % [pair.base_id, pair.family_id, rarity, item_level])
				_expect(_contains_level(ranges, item_level) == should_appear,
					"Family rarity/level range exactly matches legal matrix rows: %s/%s/%s/%d" % [pair.base_id, pair.family_id, rarity, item_level])
		_expect(pair.tier_item_level_ranges.size() == Catalog.affix_definition(pair.family_id).tiers.size(),
			"All source family tiers and unlock levels are exported")
	_expect(seen.size() > 0, "At least one family can appear on a supported item")
	_expect(seen_pairs.size() == EXPECTED_BASES * EXPECTED_FAMILIES, "Family matrix covers every unique pair")


func _check_economy_matrix(report: Dictionary) -> void:
	var seen_rows: Dictionary = {}
	var observed_global_min: int = 9223372036854775807
	var observed_global_max: int = -9223372036854775807 - 1
	for row: Dictionary in report.economy_matrix:
		var key: String = "%s|%d|%s" % [row.base_id, row.item_level, row.rarity]
		_expect(not seen_rows.has(key), "Matrix tuple is unique: " + key)
		seen_rows[key] = true
		if row.rarity == "normal":
			_expect(row.witness_catalog_valid and Catalog.validate_instance(row.witness_instance),
				"Every normal matrix witness is a legal catalog item: " + key)
			_expect(not row.craftable and row.reason_code == "no_affixes" and row.recalibrate_reason_code == "no_affixes",
				"Normal no-affix items expose the real rejection code: " + key)
			var salvage: Dictionary = Craft.salvage_quote(row.witness_instance)
			var recalibrate: Dictionary = Craft.recalibrate_plan(row.witness_instance, 20261003)
			_expect(not salvage.ok and not recalibrate.ok and salvage.code == row.reason_code
				and recalibrate.code == row.recalibrate_reason_code,
				"Normal result matches both live rule responses: " + key)
			continue
		_expect(row.craftable and row.legal_family_set_count > 0
			and row.legal_tier_assignment_count >= row.legal_family_set_count,
			"Supported rarity has a nonempty exhaustive search: " + key)
		_expect(row.families_that_can_appear.size() > 0,
			"At least one family can appear in this rarity row: " + key)
		for endpoint_name: String in ["minimum", "maximum"]:
			var endpoint: Dictionary = row[endpoint_name]
			var source: Dictionary = endpoint.witness_instance
			_expect(endpoint.witness_catalog_valid, "Exporter validated extremal witness: " + key + "/" + endpoint_name)
			_expect(source.base_id == row.base_id and source.item_level == row.item_level and source.rarity == row.rarity,
				"Witness corresponds to its exact matrix coordinates: " + key + "/" + endpoint_name)
			_expect(Catalog.validate_instance(source), "Extremal witness is catalog-valid: " + key + "/" + endpoint_name)
			var before: PackedByteArray = var_to_bytes(source)
			var salvage: Dictionary = Craft.salvage_quote(source)
			var recalibrate: Dictionary = Craft.recalibrate_plan(source, 20261003)
			_expect(salvage.ok and recalibrate.ok and Catalog.validate_instance(recalibrate.instance),
				"Both actual operations accept the extremal witness: " + key + "/" + endpoint_name)
			_expect(int(salvage.materials[Craft.MATERIAL_ID]) == endpoint.salvage_units
				and int(recalibrate.cost[Craft.MATERIAL_ID]) == endpoint.recalibrate_cost,
				"Exported amounts equal current rules: " + key + "/" + endpoint_name)
			_expect(source.affixes.size() == endpoint.affix_count and var_to_bytes(source) == before,
				"Endpoint count is exact and rules leave input unchanged: " + key + "/" + endpoint_name)
			if endpoint_name == "minimum":
				observed_global_min = mini(observed_global_min, int(endpoint.salvage_units))
			else:
				observed_global_max = maxi(observed_global_max, int(endpoint.salvage_units))
		_expect(row.minimum.salvage_units <= row.maximum.salvage_units,
			"Yield interval is ordered: " + key)
		_expect(row.minimum.recalibrate_cost <= row.maximum.recalibrate_cost,
			"Calibration cost interval is ordered: " + key)
	_expect(seen_rows.size() == 810, "All 810 base/level/rarity tuples are unique and complete")
	_expect(observed_global_min == report.budget_summary.global_by_rarity.magic.minimum.salvage_units,
		"Global magic minimum summary matches full matrix")
	_expect(observed_global_max == report.budget_summary.global_by_rarity.rare.maximum.salvage_units,
		"Global rare maximum summary matches full matrix")
	_expect(report.budget_summary.global_by_rarity.rare.maximum.salvage_units == 21,
		"Current exact rare recovery cap includes six T3 affixes")
	_expect(report.budget_summary.global_by_rarity.rare.maximum.recalibrate_cost == 42,
		"Current cost for the exact rare recovery cap matches CraftingRules")


func _check_examples(report: Dictionary) -> void:
	var white: Dictionary = report.examples.normal_white_rejection
	_expect(Catalog.validate_instance(white.source_instance) and not white.salvage.ok and not white.recalibrate.ok,
		"Normal example is valid but unsupported")
	_expect(white.salvage.code == "no_affixes" and white.recalibrate.code == "no_affixes",
		"Normal example contains the actual rejection reasons")
	var minimum: Dictionary = report.examples.global_minimum_yield
	var maximum: Dictionary = report.examples.global_maximum_yield
	for example: Dictionary in [minimum, maximum]:
		var source: Dictionary = example.source_instance
		_expect(example.catalog_valid and Catalog.validate_instance(source), "Successful example source is legal")
		var before: PackedByteArray = var_to_bytes(source)
		var salvage: Dictionary = Craft.salvage_quote(source)
		var plan: Dictionary = Craft.recalibrate_plan(source, int(example.recalibrate.seed))
		_expect(salvage.ok and plan.ok and plan == _replayed_plan(source, int(example.recalibrate.seed)),
			"Example reproduces exact quote and seeded plan")
		_expect(salvage.materials == example.salvage.materials and plan.cost == example.recalibrate.cost
			and plan.instance == example.recalibrate.output_instance,
			"Example input, material, cost and output match live rules")
		_expect(Catalog.validate_instance(plan.instance) and example.recalibrate.output_catalog_valid,
			"Example reroll output is legal")
		_expect(var_to_bytes(source) == before, "Example rules leave source item unchanged")
		var other_seed_plan: Dictionary = Craft.recalibrate_plan(source, int(example.recalibrate.seed) + 1)
		_expect(other_seed_plan.ok and other_seed_plan.cost == plan.cost,
			"Calibration cost does not vary with the seed")
	_expect(int(minimum.salvage.materials[Craft.MATERIAL_ID]) == 2,
		"Global example demonstrates current minimum magic yield")
	_expect(int(maximum.salvage.materials[Craft.MATERIAL_ID]) == 21,
		"Global example demonstrates current rare yield upper bound")


func _replayed_plan(source: Dictionary, seed_value: int) -> Dictionary:
	return Craft.recalibrate_plan(source, seed_value)


func _contains_level(ranges: Array, item_level: int) -> bool:
	for interval: Array in ranges:
		if item_level >= int(interval[0]) and item_level <= int(interval[1]):
			return true
	return false


func _check_written_artifacts(report: Dictionary) -> void:
	var expected_json: String = JSON.stringify(report, "\t", true, true) + "\n"
	var actual_json: String = FileAccess.get_file_as_string(JSON_PATH)
	_expect(not actual_json.is_empty() and actual_json == expected_json,
		"JSON artifact exactly matches deterministic live export")
	var parsed: Variant = JSON.parse_string(actual_json)
	_expect(parsed is Dictionary and parsed.domain.matrix_rows == 810,
		"JSON artifact parses and carries the full matrix")
	var expected_markdown: String = Exporter.render_markdown(report)
	var actual_markdown: String = FileAccess.get_file_as_string(MARKDOWN_PATH)
	_expect(not actual_markdown.is_empty() and actual_markdown == expected_markdown,
		"Chinese QA document exactly matches deterministic live rendering")
	_expect(actual_markdown.contains("不是样本估计") and actual_markdown.contains("no_affixes"),
		"Human report distinguishes exact bounds and ordinary-item rejection")
