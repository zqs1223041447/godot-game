extends SceneTree
## Scoped v0.49 reference checks. --artifacts additionally verifies generated output.
const Exporter = preload("res://tools/export_reference.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Canonical = preload("res://scripts/canonical_game_state.gd")
const OLD_OPERATIONS = ["salvage", "recalibrate", "enchant", "elevate", "augment", "reforge"]
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	var current: Dictionary = Exporter.crafting_examples()
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v049-reference/reference-baseline.json"))
	check(current.size() == 11 and Craft.operation_ids().size() == 10, "One material, six original operations and four targets")
	for operation: String in OLD_OPERATIONS:
		check(same(current[operation], baseline.crafting[operation]), "Original reference example preserved: " + operation)
		check(current[operation].rules_version == Craft.CURRENT_RULES_VERSION, "Original quote version remains v3: " + operation)
	var names: Array[String] = []
	for operation: String in Craft.Targeted.operation_ids():
		var entry: Dictionary = current[operation]
		var target: Dictionary = Craft.Targeted.TARGETS[operation]
		var sample: Dictionary = entry.example
		check(entry.targeted and entry.target_id == target.id and entry.target_label == target.label, "Distinct target metadata: " + operation)
		check(entry.name.contains(target.label) and not names.has(entry.name), "Distinct visible target name: " + operation)
		names.append(entry.name)
		check(entry.rules_version == Craft.TARGETED_RULES_VERSION and entry.rules_version == sample.quote.rules_version, "Actual targeted quote rules version: " + operation)
		check(entry.target_family_ids == target.families and entry.catalog_vocabulary == Equipment.CURRENT_VOCABULARY, "Actual target families and vocabulary: " + operation)
		check(entry.cost_by_rarity == {"magic":16, "rare":40}, "Independent targeted price contract: " + operation)
		check(Equipment.validate_instance(sample.source) and Equipment.validate_instance(sample.after_instance), "Catalog-valid source and result: " + operation)
		check(sample.full_candidate_valid and sample.save_version == Canonical.Rules.VERSION, "Full current canonical candidate was validated: " + operation)
		check(sample.revision_before == 0 and sample.revision_after == 1 and sample.balance_before == 100 and sample.balance_after == 84, "Single transaction and actual magic cost: " + operation)
		check(sample.quote.cost == {Craft.MATERIAL_ID:16} and sample.quote.materials.is_empty(), "Targeted crafting has a cost and no yield: " + operation)
		var actual: Dictionary = Craft.operation_plan(sample.source, operation, int(sample.example_seed))
		check(actual.ok and actual.instance == sample.after_instance, "Example reproduces the actual deterministic planner: " + operation)
		check(Equipment.definition(sample.after_instance) == sample.after_definition, "Result text derives from the result instance: " + operation)
		var has_target: bool = false
		for affix: Dictionary in sample.after_instance.affixes:
			if target.families.has(affix.id): has_target = true
		check(has_target, "Example contains a guaranteed legal target: " + operation)
		for field: String in ["id", "base_id", "item_level", "rarity"]:
			check(sample.after_instance[field] == sample.source[field], "Reference preserves " + field + ": " + operation)
		if operation != "targeted_reforge_damage":
			check(entry.eligible_base_ids.size() == 4, "Critical and leech expose only four legal bases: " + operation)
			check(not entry.eligible_base_ids.has("ashwood_bow") and sample.source.base_id == "wayglass_token", "Critical and leech do not claim bow support: " + operation)
		else:
			for base_id: String in entry.eligible_base_ids:
				check(not base_id.begins_with("nine_slot_"), "Damage rejects nine-slot bases without damage families")
		var expected_bases: Array[String] = []
		for base_id: String in Equipment.all_base_ids():
			var accepted: bool = false
			for rarity: String in ["magic", "rare"]:
				var source: Dictionary = Exporter._crafting_probe_instance(base_id, Equipment.MAX_ITEM_LEVEL, rarity)
				if not source.is_empty() and Craft.operation_quote(source, operation).ok: accepted = true
			if accepted: expected_bases.append(base_id)
		check(entry.eligible_base_ids == expected_bases and entry.eligibility.size() == expected_bases.size(), "All base links reflect viable current quotes: " + operation)
		for eligible: Dictionary in entry.eligibility:
			check(entry.eligible_base_ids.has(eligible.base_id), "Eligibility detail matches a linked base")
			var actual_tiers: Array[Dictionary] = []
			for tier: Dictionary in Craft.Expansion._pool(eligible.base_id, Equipment.MAX_ITEM_LEVEL, []):
				if target.families.has(tier.id): actual_tiers.append(tier)
			check(eligible.target_tiers_at_maximum_level == actual_tiers, "All weights, tick ranges and tiers derive from the catalog")
			for rarity: String in eligible.minimum_item_level_by_rarity:
				var minimum: int = int(eligible.minimum_item_level_by_rarity[rarity])
				var source: Dictionary = Exporter._crafting_probe_instance(eligible.base_id, minimum, rarity)
				var quote: Dictionary = Craft.operation_quote(source, operation)
				check(quote.ok and quote.cost[Craft.MATERIAL_ID] == entry.cost_by_rarity[rarity], "Minimum level and rarity cost have viable quotes")
				for level: int in range(Equipment.MIN_ITEM_LEVEL, minimum):
					var lower: Dictionary = Exporter._crafting_probe_instance(eligible.base_id, level, rarity)
					check(lower.is_empty() or not Craft.operation_quote(lower, operation).ok, "No lower level is falsely excluded")
	if OS.get_cmdline_user_args().has("--artifacts"):
		check_artifacts(current)
	print("Targeted reforge reference: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check_artifacts(current: Dictionary) -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/reference/catalog.json"))
	check(catalog.game_version == "0.49.0" and catalog.save_version == 30, "Current release version with unchanged save schema")
	check(same(catalog.crafting, current), "Generated crafting catalog exactly matches current production export")
	var html: String = FileAccess.get_file_as_string("res://docs/reference/index.html")
	var ids: Dictionary = {}
	var id_regex := RegEx.create_from_string('(?<![\\w-])id="([^"]+)"')
	for match_id: RegExMatch in id_regex.search_all(html):
		var id: String = match_id.get_string(1)
		check(not ids.has(id), "Unique HTML anchor: " + id)
		ids[id] = true
	for link: RegExMatch in RegEx.create_from_string('href="([^"]+)"').search_all(html):
		var href: String = link.get_string(1)
		if href.begins_with("#"):
			check(ids.has(href.substr(1)), "Resolved internal link: " + href)
		elif not href.begins_with("https://") and not href.begins_with("http://"):
			check(FileAccess.file_exists("res://docs/reference/" + href.split("#")[0]), "Resolved local link: " + href)
	for asset: RegExMatch in RegEx.create_from_string('src="([^"]+)"').search_all(html):
		var source: String = asset.get_string(1)
		check(not source.contains("://") and not source.begins_with("//") and FileAccess.file_exists("res://docs/reference/" + source), "Local asset exists: " + source)
	for operation: String in Craft.Targeted.operation_ids():
		var entry: Dictionary = current[operation]
		var start: int = html.find('id="crafting-' + operation + '"')
		check(start >= 0, "Targeted entry is browsable: " + operation)
		if start < 0: continue
		var article: String = html.substr(start, html.find("</article>", start) - start)
		check(article.contains(entry.name) and article.contains(entry.rules_version), "Rendered unique name and actual quote version")
		check(article.contains("实际规则示例 · " + entry.example.before_definition.base_name), "Figure labels the actual source base")
		check(article.contains("不保证高阶或更强") and article.contains("无合法目标不收费"), "Rendered risks and no-target rejection")
		for rarity: String in entry.cost_by_rarity:
			check(article.contains('data-targeted-cost="%s-%s" data-value="%d"' % [operation, rarity, entry.cost_by_rarity[rarity]]), "Rendered same-source cost: " + rarity)
		for family: String in entry.target_family_ids:
			check(article.contains('href="#affixes-' + family + '"'), "Target family is linked: " + family)
		for base_id: String in Equipment.all_base_ids():
			check(article.contains('href="#equipment-' + base_id + '"') == entry.eligible_base_ids.has(base_id), "Rendered eligibility is exact: " + base_id)


func same(left: Variant, right: Variant) -> bool:
	var normalized: Variant = JSON.parse_string(JSON.stringify(Exporter.clean(left), "", true, true))
	var expected: Variant = JSON.parse_string(JSON.stringify(Exporter.clean(right), "", true, true))
	return JSON.stringify(normalized, "", true, true) == JSON.stringify(expected, "", true, true)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
