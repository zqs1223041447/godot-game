extends SceneTree
## Deterministic, read-only export of the current equipment crafting economy.
## Bounds enumerate legal family sets and analytically select tier endpoints;
## all reported item witnesses are revalidated through the live catalog/rules.
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Craft = preload("res://scripts/items/crafting_rules.gd")

const JSON_PATH: String = "res://docs/qa/crafting-budget.json"
const MARKDOWN_PATH: String = "res://docs/qa/CRAFTING_BUDGET.zh-CN.md"
const EXAMPLE_SEEDS: Array[int] = [20261003, 20261004]
const RARITY_ORDER: Array[String] = ["normal", "magic", "rare"]
const CRAFTABLE_RARITIES: Array[String] = ["magic", "rare"]
const LEVEL_BANDS: Array[Dictionary] = [
	{"id": "t1", "minimum": 1, "maximum": 7},
	{"id": "t2", "minimum": 8, "maximum": 15},
	{"id": "t3", "minimum": 16, "maximum": 30},
]
const SALVAGE_FORMULA: String = "rarity_units + sum(tier) * salvage_units_per_tier"
const RECALIBRATE_FORMULA: String = "salvage_yield * recalibrate_cost_multiplier"


func _initialize() -> void:
	var report: Dictionary = collect()
	var json_text: String = JSON.stringify(report, "\t", true, true) + "\n"
	var markdown_text: String = render_markdown(report)
	if not _write(JSON_PATH, json_text) or not _write(MARKDOWN_PATH, markdown_text):
		quit(1)
		return
	print("Crafting budget exported: %d matrix rows, %d family pairs; exact family-set enumeration, %d examples" % [
		report.analysis.matrix_rows, report.analysis.family_eligibility_rows, report.analysis.sample_examples])
	quit(0)


static func collect() -> Dictionary:
	var base_ids: Array[String] = Catalog.all_base_ids()
	var family_ids: Array[String] = Catalog.all_affix_ids()
	var metadata: Dictionary = Craft.metadata()
	assert(metadata.rules_version == Craft.RULES_VERSION)
	assert(metadata.operations.salvage.yield_formula == SALVAGE_FORMULA)
	assert(metadata.operations.recalibrate.cost_formula == RECALIBRATE_FORMULA)
	assert(int(Craft.BALANCE.recalibrate_cost_multiplier) >= 0,
		"Cost extrema must be monotonic with yield for this exact endpoint summary")
	assert(base_ids.size() == 9 and family_ids.size() == 19,
		"This export is scoped to the requested v0.19 catalog of 9 bases and 19 families")

	var cache: Dictionary = {}
	var family_presence: Dictionary = {}
	for base_id: String in base_ids:
		family_presence[base_id] = {}
		for family_id: String in family_ids:
			family_presence[base_id][family_id] = {"magic": [], "rare": []}

	var matrix: Array[Dictionary] = []
	var total_subset_masks: int = 0
	var total_legal_family_sets: int = 0
	var total_tier_assignments: int = 0
	var enumeration_runs: int = 0
	for base_id: String in base_ids:
		var pool_id: String = Catalog.pool_for_base(base_id)
		var pool: Dictionary = Catalog.pool_profile(pool_id)
		for item_level: int in range(Catalog.MIN_ITEM_LEVEL, Catalog.MAX_ITEM_LEVEL + 1):
			var band: Dictionary = _level_band(item_level)
			for rarity: String in RARITY_ORDER:
				if rarity == "normal":
					matrix.append(_normal_row(base_id, item_level))
					continue
				var cache_key: String = "%s|%s|%s" % [base_id, band.id, rarity]
				if not cache.has(cache_key):
					var state: Dictionary = _enumerate_band(base_id, int(band.minimum), rarity, family_ids, pool.affix_ids)
					cache[cache_key] = state
					enumeration_runs += 1
					total_subset_masks += int(state.subset_masks_tested)
					total_legal_family_sets += int(state.legal_family_set_count)
					total_tier_assignments += int(state.legal_tier_assignment_count)
				var active_state: Dictionary = cache[cache_key]
				assert(int(active_state.legal_family_set_count) > 0,
					"The actual catalog must allow at least one %s instance for %s at ilvl %d" % [rarity, base_id, item_level])
				matrix.append(_material_row(base_id, item_level, rarity, band, active_state))
				for family_id: String in active_state.families_by_rarity:
					family_presence[base_id][family_id][rarity].append(item_level)

	var family_matrix: Array[Dictionary] = _family_matrix(base_ids, family_ids, family_presence)
	var summary: Dictionary = _budget_summary(base_ids, matrix)
	var examples: Dictionary = _examples(matrix)
	var domain_rows: int = base_ids.size() * (Catalog.MAX_ITEM_LEVEL - Catalog.MIN_ITEM_LEVEL + 1) * RARITY_ORDER.size()
	assert(matrix.size() == domain_rows)
	assert(family_matrix.size() == base_ids.size() * family_ids.size())
	return {
		"schema_version": 1,
		"game_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
		"rules_version": Craft.RULES_VERSION,
		"catalog_vocabulary": Catalog.CURRENT_VOCABULARY,
		"sources": {
			"equipment_catalog": "res://scripts/items/equipment_catalog.gd",
			"crafting_rules": "res://scripts/items/crafting_rules.gd",
			"crafting_metadata": metadata,
		},
		"domain": {
			"base_ids": base_ids,
			"base_count": base_ids.size(),
			"family_ids": family_ids,
			"family_count": family_ids.size(),
			"item_level_inclusive": [Catalog.MIN_ITEM_LEVEL, Catalog.MAX_ITEM_LEVEL],
			"rarity_ids": RARITY_ORDER,
			"matrix_rows": matrix.size(),
			"family_eligibility_rows": family_matrix.size(),
		},
		"rarity_rules": _rarity_rules(),
		"bases": _base_records(base_ids),
		"affix_families": _family_records(family_ids),
		"family_eligibility_matrix": family_matrix,
		"economy_matrix": matrix,
		"budget_summary": summary,
		"examples": examples,
		"analysis": {
			"exact_enumeration": true,
			"enumeration_runs": enumeration_runs,
			"distinct_tier_unlock_bands": LEVEL_BANDS,
			"family_subset_masks_tested_across_distinct_bands": total_subset_masks,
			"legal_family_sets_across_distinct_bands": total_legal_family_sets,
			"legal_tier_assignments_covered_by_analytic_endpoints": total_tier_assignments,
			"matrix_rows": matrix.size(),
			"family_eligibility_rows": family_matrix.size(),
			"sample_examples": EXAMPLE_SEEDS.size(),
			"example_records": examples.size(),
			"example_seeds": EXAMPLE_SEEDS,
			"bounds_depend_on_seed": false,
			"bound_scope": "Every non-empty subset of in-profile, base-eligible families is examined for each distinct tier-unlock band and supported rarity; legal subsets are checked with EquipmentCatalog.validate_instance. Every unlocked tier assignment is covered by the exact additive per-tier rule using CraftingRules metadata and BALANCE. Minimum/maximum witness instances are then quoted and recalibrated through CraftingRules.",
			"roll_value_assignments_enumerated": false,
			"roll_value_economic_effect": "The current salvage and recalibration rules use rarity and affix tier only; affix value ticks do not change either amount.",
			"sample_scope": "Two fixed-seed recalibration examples demonstrate reproducible outputs only. They do not estimate probabilities or establish economic bounds.",
			"normal_scope": "All 9 bases x all 30 item levels were checked as legal no-affix normal instances; CraftingRules returned the actual no_affixes rejection for both operations.",
		},
	}


static func _level_band(item_level: int) -> Dictionary:
	for band: Dictionary in LEVEL_BANDS:
		if item_level >= int(band.minimum) and item_level <= int(band.maximum):
			return band
	return {}


static func _enumerate_band(base_id: String, representative_level: int, rarity: String,
		all_family_ids: Array[String], profile_family_ids: Array) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for family_id: String in all_family_ids:
		if not profile_family_ids.has(family_id) or not Catalog.family_eligible(family_id, base_id):
			continue
		var family: Dictionary = Catalog.affix_definition(family_id)
		var unlocked: Array[Dictionary] = []
		for tier: Dictionary in family.tiers:
			if int(tier.level) <= representative_level:
				unlocked.append(tier)
		if not unlocked.is_empty():
			candidates.append({"id": family_id, "kind": family.kind, "group": family.group, "tiers": unlocked})

	var rarity_rule: Dictionary = Catalog.RARITIES[rarity]
	var result: Dictionary = {
		"base_id": base_id,
		"rarity": rarity,
		"representative_item_level": representative_level,
		"subset_masks_tested": (1 << candidates.size()) - 1,
		"legal_family_set_count": 0,
		"legal_tier_assignment_count": 0,
		"families_by_rarity": [],
		"minimum": {},
		"maximum": {},
	}
	var family_presence: Dictionary = {}
	var prefix_limit: int = int(rarity_rule.max_prefixes)
	var suffix_limit: int = int(rarity_rule.max_suffixes)
	var min_count: int = int(rarity_rule.min_affixes)
	var max_count: int = int(rarity_rule.max_affixes)
	var tier_unit: int = int(Craft.BALANCE.salvage_units_per_tier)

	for mask: int in range(1, 1 << candidates.size()):
		var selected: Array[Dictionary] = []
		var groups: Dictionary = {}
		var prefixes: int = 0
		var suffixes: int = 0
		var structurally_possible: bool = true
		for index: int in range(candidates.size()):
			if (mask & (1 << index)) == 0:
				continue
			var candidate: Dictionary = candidates[index]
			if groups.has(candidate.group):
				structurally_possible = false
				break
			groups[candidate.group] = true
			if candidate.kind == "prefix":
				prefixes += 1
				if prefixes > prefix_limit:
					structurally_possible = false
					break
			else:
				suffixes += 1
				if suffixes > suffix_limit:
					structurally_possible = false
					break
			selected.append(candidate)
		if not structurally_possible or selected.size() < min_count or selected.size() > max_count:
			continue

		var minimum_instance: Dictionary = _witness(base_id, representative_level, rarity, selected, true)
		var maximum_instance: Dictionary = _witness(base_id, representative_level, rarity, selected, false)
		if not Catalog.validate_instance(minimum_instance) or not Catalog.validate_instance(maximum_instance):
			continue
		var minimum_quote: Dictionary = Craft.salvage_quote(minimum_instance)
		var maximum_quote: Dictionary = Craft.salvage_quote(maximum_instance)
		assert(minimum_quote.ok and maximum_quote.ok,
			"Catalog-validated endpoint witnesses must be accepted by current CraftingRules")
		var minimum_units: int = int(minimum_quote.materials[Craft.MATERIAL_ID])
		var maximum_units: int = int(maximum_quote.materials[Craft.MATERIAL_ID])
		assert(minimum_units <= maximum_units)
		var tier_assignments: int = 1
		for family: Dictionary in selected:
			tier_assignments *= family.tiers.size()
		for family: Dictionary in selected:
			family_presence[family.id] = true
		result.legal_family_set_count += 1
		result.legal_tier_assignment_count += tier_assignments
		var minimum_candidate: Dictionary = {"salvage_units": minimum_units, "source_instance": minimum_instance}
		var maximum_candidate: Dictionary = {"salvage_units": maximum_units, "source_instance": maximum_instance}
		if result.minimum.is_empty() or minimum_units < int(result.minimum.salvage_units):
			result.minimum = minimum_candidate
		if result.maximum.is_empty() or maximum_units > int(result.maximum.salvage_units):
			result.maximum = maximum_candidate

	var families: Array[String] = []
	for family_id: String in all_family_ids:
		if family_presence.has(family_id):
			families.append(family_id)
	result.families_by_rarity = families
	return result


static func _witness(base_id: String, item_level: int, rarity: String,
		selected: Array[Dictionary], minimize_yield: bool) -> Dictionary:
	var affixes: Array[Dictionary] = []
	var per_tier: int = int(Craft.BALANCE.salvage_units_per_tier)
	for family: Dictionary in selected:
		var tier_options: Array = family.tiers
		var chosen: Dictionary = tier_options[0]
		var chosen_contribution: int = int(chosen.tier) * per_tier
		for tier: Dictionary in tier_options:
			var contribution: int = int(tier.tier) * per_tier
			if (minimize_yield and contribution < chosen_contribution) \
					or (not minimize_yield and contribution > chosen_contribution):
				chosen = tier
				chosen_contribution = contribution
		var value: int = int(chosen.min) if minimize_yield else int(chosen.max)
		affixes.append({"id": family.id, "tier": int(chosen.tier), "value": value})
	return {"id": "gear_000001", "base_id": base_id, "rarity": rarity,
		"item_level": item_level, "affixes": affixes}


static func _material_row(base_id: String, item_level: int, rarity: String,
		band: Dictionary, state: Dictionary) -> Dictionary:
	var minimum: Dictionary = _row_endpoint(state.minimum, item_level, true)
	var maximum: Dictionary = _row_endpoint(state.maximum, item_level, false)
	var accessible: Array[String] = state.families_by_rarity.duplicate()
	return {
		"base_id": base_id,
		"item_level": item_level,
		"rarity": rarity,
		"tier_unlock_band": band.id,
		"craftable": true,
		"legal_family_set_count": state.legal_family_set_count,
		"legal_tier_assignment_count": state.legal_tier_assignment_count,
		"families_that_can_appear": accessible,
		"minimum": minimum,
		"maximum": maximum,
	}


static func _row_endpoint(endpoint: Dictionary, item_level: int, minimum: bool) -> Dictionary:
	var source: Dictionary = endpoint.source_instance.duplicate(true)
	source.item_level = item_level
	assert(Catalog.validate_instance(source), "Every matrix witness must be a legal real-catalog item")
	var before: PackedByteArray = var_to_bytes(source)
	var salvage: Dictionary = Craft.salvage_quote(source)
	var plan: Dictionary = Craft.recalibrate_plan(source, EXAMPLE_SEEDS[0])
	assert(salvage.ok and plan.ok and Catalog.validate_instance(plan.instance))
	assert(salvage.source_instance == source and plan.source_instance == source)
	assert(var_to_bytes(source) == before, "Quotes and plans must not mutate the witness")
	var units: int = int(salvage.materials[Craft.MATERIAL_ID])
	var cost: int = int(plan.cost[Craft.MATERIAL_ID])
	assert(units == int(endpoint.salvage_units))
	return {
		"salvage_units": units,
		"recalibrate_cost": cost,
		"affix_count": source.affixes.size(),
		"affixes": _affix_tiers(source),
		"witness_instance": source,
		"witness_catalog_valid": true,
		"endpoint": "minimum yield" if minimum else "maximum yield",
	}


static func _affix_tiers(instance: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for affix: Dictionary in instance.affixes:
		result.append({"id": affix.id, "tier": int(affix.tier)})
	return result


static func _normal_row(base_id: String, item_level: int) -> Dictionary:
	var item: Dictionary = {"id": "gear_000001", "base_id": base_id, "rarity": "normal",
		"item_level": item_level, "affixes": []}
	assert(Catalog.validate_instance(item))
	var salvage: Dictionary = Craft.salvage_quote(item)
	var recalibrate: Dictionary = Craft.recalibrate_plan(item, EXAMPLE_SEEDS[0])
	assert(not salvage.ok and not recalibrate.ok)
	assert(salvage.code == "no_affixes" and recalibrate.code == "no_affixes")
	return {
		"base_id": base_id,
		"item_level": item_level,
		"rarity": "normal",
		"tier_unlock_band": _level_band(item_level).id,
		"craftable": false,
		"reason_code": salvage.code,
		"reason": salvage.reason,
		"recalibrate_reason_code": recalibrate.code,
		"recalibrate_reason": recalibrate.reason,
		"witness_instance": item,
		"witness_catalog_valid": true,
	}


static func _base_records(base_ids: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for base_id: String in base_ids:
		var base: Dictionary = Catalog.base_definition(base_id)
		result.append({"id": base_id, "name": base.name, "slot": base.slot,
			"pool_id": Catalog.pool_for_base(base_id),
			"item_level_inclusive": [Catalog.MIN_ITEM_LEVEL, Catalog.MAX_ITEM_LEVEL]})
	return result


static func _family_records(family_ids: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for family_id: String in family_ids:
		var family: Dictionary = Catalog.affix_definition(family_id)
		var tiers: Array[Dictionary] = []
		for tier: Dictionary in family.tiers:
			tiers.append({"tier": int(tier.tier), "unlocked_at_item_level": int(tier.level),
				"weight": int(tier.weight), "value_ticks_inclusive": [int(tier.min), int(tier.max)]})
		result.append({"id": family_id, "name": family.name, "kind": family.kind,
			"group": family.group, "stat": family.stat, "unit": family.unit,
			"label": family.label, "slots": family.slots.duplicate(), "tiers": tiers})
	return result


static func _family_matrix(base_ids: Array[String], family_ids: Array[String],
		presence: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for base_id: String in base_ids:
		var base: Dictionary = Catalog.base_definition(base_id)
		var profile: Dictionary = Catalog.pool_profile(Catalog.pool_for_base(base_id))
		for family_id: String in family_ids:
			var family: Dictionary = Catalog.affix_definition(family_id)
			var catalog_eligible: bool = Catalog.family_eligible(family_id, base_id)
			var profile_allows: bool = profile.affix_ids.has(family_id)
			var rarity_levels: Dictionary = {"normal": [], "magic": [], "rare": []}
			for rarity: String in CRAFTABLE_RARITIES:
				rarity_levels[rarity] = _compress_levels(presence[base_id][family_id][rarity])
			var tier_rows: Array[Dictionary] = []
			for tier: Dictionary in family.tiers:
				tier_rows.append({"tier": int(tier.tier),
					"item_level_inclusive": [int(tier.level), Catalog.MAX_ITEM_LEVEL]})
			result.append({
				"base_id": base_id,
				"base_slot": base.slot,
				"family_id": family_id,
				"catalog_family_eligible": catalog_eligible,
				"generation_profile_allows": profile_allows,
				"applicable": catalog_eligible and profile_allows,
				"rarity_item_level_ranges": rarity_levels,
				"tier_item_level_ranges": tier_rows,
			})
	return result


static func _compress_levels(levels: Array) -> Array[Array]:
	var result: Array[Array] = []
	if levels.is_empty():
		return result
	var start: int = int(levels[0])
	var previous: int = start
	for index: int in range(1, levels.size()):
		var current: int = int(levels[index])
		if current == previous + 1:
			previous = current
			continue
		result.append([start, previous])
		start = current
		previous = current
	result.append([start, previous])
	return result


static func _rarity_rules() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rarity: String in RARITY_ORDER:
		var rule: Dictionary = Catalog.RARITIES[rarity]
		result.append({"id": rarity, "name": rule.name,
			"min_affixes": int(rule.min_affixes), "max_affixes": int(rule.max_affixes),
			"max_prefixes": int(rule.max_prefixes), "max_suffixes": int(rule.max_suffixes),
			"craft_supported_by_current_rules": CRAFTABLE_RARITIES.has(rarity)})
	return result


static func _budget_summary(base_ids: Array[String], matrix: Array[Dictionary]) -> Dictionary:
	var by_base: Array[Dictionary] = []
	var overall: Dictionary = {"magic": {}, "rare": {}}
	for base_id: String in base_ids:
		var base: Dictionary = Catalog.base_definition(base_id)
		var record: Dictionary = {"base_id": base_id, "name": base.name, "rarities": {}}
		for rarity: String in CRAFTABLE_RARITIES:
			var minimum_row: Dictionary = {}
			var maximum_row: Dictionary = {}
			for row: Dictionary in matrix:
				if row.base_id != base_id or row.rarity != rarity:
					continue
				if minimum_row.is_empty() or int(row.minimum.salvage_units) < int(minimum_row.minimum.salvage_units):
					minimum_row = row
				if maximum_row.is_empty() or int(row.maximum.salvage_units) > int(maximum_row.maximum.salvage_units):
					maximum_row = row
			var local_range: Dictionary = {
				"minimum_salvage_units": int(minimum_row.minimum.salvage_units),
				"minimum_at_item_level": int(minimum_row.item_level),
				"minimum_recalibrate_cost": int(minimum_row.minimum.recalibrate_cost),
				"maximum_salvage_units": int(maximum_row.maximum.salvage_units),
				"maximum_at_item_level": int(maximum_row.item_level),
				"maximum_recalibrate_cost": int(maximum_row.maximum.recalibrate_cost),
			}
			record.rarities[rarity] = local_range
			if not overall[rarity].has("minimum") or local_range.minimum_salvage_units < overall[rarity].minimum.salvage_units:
				overall[rarity].minimum = {"base_id": base_id, "item_level": local_range.minimum_at_item_level,
					"salvage_units": local_range.minimum_salvage_units,
					"recalibrate_cost": local_range.minimum_recalibrate_cost}
			if not overall[rarity].has("maximum") or local_range.maximum_salvage_units > overall[rarity].maximum.salvage_units:
				overall[rarity].maximum = {"base_id": base_id, "item_level": local_range.maximum_at_item_level,
					"salvage_units": local_range.maximum_salvage_units,
					"recalibrate_cost": local_range.maximum_recalibrate_cost}
		by_base.append(record)
	return {"by_base": by_base, "global_by_rarity": overall}


static func _examples(matrix: Array[Dictionary]) -> Dictionary:
	var minimum_row: Dictionary = {}
	var maximum_row: Dictionary = {}
	for row: Dictionary in matrix:
		if not row.craftable:
			continue
		if minimum_row.is_empty() or int(row.minimum.salvage_units) < int(minimum_row.minimum.salvage_units):
			minimum_row = row
		if maximum_row.is_empty() or int(row.maximum.salvage_units) > int(maximum_row.maximum.salvage_units):
			maximum_row = row
	assert(not minimum_row.is_empty() and not maximum_row.is_empty())
	var normal_item: Dictionary = {"id": "gear_000001", "base_id": Catalog.all_base_ids()[0],
		"rarity": "normal", "item_level": Catalog.MIN_ITEM_LEVEL, "affixes": []}
	var normal_salvage: Dictionary = Craft.salvage_quote(normal_item)
	var normal_recalibrate: Dictionary = Craft.recalibrate_plan(normal_item, EXAMPLE_SEEDS[0])
	assert(Catalog.validate_instance(normal_item) and not normal_salvage.ok and not normal_recalibrate.ok)
	return {
		"normal_white_rejection": {
			"source_instance": normal_item,
			"catalog_valid": Catalog.validate_instance(normal_item),
			"salvage": _rejection_summary(normal_salvage),
			"recalibrate": _rejection_summary(normal_recalibrate),
		},
		"global_minimum_yield": _success_example(minimum_row.minimum.witness_instance, EXAMPLE_SEEDS[0]),
		"global_maximum_yield": _success_example(maximum_row.maximum.witness_instance, EXAMPLE_SEEDS[1]),
	}


static func _success_example(source: Dictionary, seed_value: int) -> Dictionary:
	var before: PackedByteArray = var_to_bytes(source)
	var salvage: Dictionary = Craft.salvage_quote(source)
	var recalibrate: Dictionary = Craft.recalibrate_plan(source, seed_value)
	assert(Catalog.validate_instance(source) and salvage.ok and recalibrate.ok)
	assert(Catalog.validate_instance(recalibrate.instance) and var_to_bytes(source) == before)
	return {
		"source_instance": source.duplicate(true),
		"catalog_valid": true,
		"salvage": {"ok": salvage.ok, "rules_version": salvage.rules_version,
			"materials": salvage.materials.duplicate(true), "cost": salvage.cost.duplicate(true),
			"consumes_item": salvage.consumes_item},
		"recalibrate": {"ok": recalibrate.ok, "rules_version": recalibrate.rules_version,
			"seed": seed_value, "cost": recalibrate.cost.duplicate(true),
			"output_instance": recalibrate.instance.duplicate(true),
			"output_catalog_valid": Catalog.validate_instance(recalibrate.instance)},
	}


static func _rejection_summary(result: Dictionary) -> Dictionary:
	return {"ok": result.ok, "code": result.code, "reason": result.reason,
		"cost": result.cost.duplicate(true), "materials": result.materials.duplicate(true),
		"consumes_item": result.consumes_item}


static func render_markdown(report: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("# 回收与数值校准预算核算")
	lines.append("")
	lines.append("本报告由 `tools/export_crafting_budget.gd` 从 `EquipmentCatalog` 与 `CraftingRules` 生成；规则版本：`%s`，装备目录词汇版本：`%d`，游戏版本：`%s`。这是现有原型规则的核算，不实现或定价任何新工艺。" % [report.rules_version, report.catalog_vocabulary, report.game_version])
	lines.append("")
	lines.append("## 覆盖范围与证明口径")
	lines.append("")
	lines.append("- 完整矩阵枚举 **%d 个底材 × %d 个物品等级（%d–%d）× %d 种稀有度 = %d 行**；普通、魔法、稀有各覆盖全部底材和等级。" % [report.domain.base_count, Catalog.MAX_ITEM_LEVEL - Catalog.MIN_ITEM_LEVEL + 1, Catalog.MIN_ITEM_LEVEL, Catalog.MAX_ITEM_LEVEL, RARITY_ORDER.size(), report.domain.matrix_rows])
	lines.append("- 词族资格矩阵枚举 **%d 底材 × %d 词族 = %d 对**。记录分别给出目录槽位资格、所在生成池许可、可出现稀有度与物品等级段，以及每个 tier 的解锁等级。" % [report.domain.base_count, report.domain.family_count, report.domain.family_eligibility_rows])
	lines.append("- 魔法/稀有预算对 1/8/16 三个 tier 解锁阶段的每种合法词族集合做完整子集枚举；枚举 %d 个集合位掩码，%d 个合法族集合及其 %d 种可用 tier 指派。合法见证逐个通过目录验证，再由 `CraftingRules.salvage_quote()` 取回收量、`recalibrate_plan()` 取校准成本。" % [report.analysis.family_subset_masks_tested_across_distinct_bands, report.analysis.legal_family_sets_across_distinct_bands, report.analysis.legal_tier_assignments_covered_by_analytic_endpoints])
	lines.append("- 数值上下界对每个合法族集合按现有可用 tier 的独立加和规则解析；全部端点见证均经真实规则报价。词缀掷值不参与回收或校准数量，因此没有枚举掷值组合，也没有用随机种子证明边界。")
	lines.append("- 两个固定种子样例只用于复现具体校准输出；不代表概率、期望收益或经济上界。普通白装在完整 270 项底材/等级矩阵中逐项验证，现有规则均以 `no_affixes` 拒绝回收和校准。")
	lines.append("")
	lines.append("## 当前规则")
	lines.append("")
	lines.append("- 材料：`%s`（%s）。回收消耗物品、只产出该材料；数值校准不消耗物品、只扣材料。" % [Craft.MATERIAL_ID, report.sources.crafting_metadata.materials[Craft.MATERIAL_ID].name])
	lines.append("- 精确公式来自当前元数据：回收 `%s`；校准 `%s`。实际费率全部从 `CraftingRules.BALANCE` 读取，未另抄平衡表。" % [report.sources.crafting_metadata.operations.salvage.yield_formula, report.sources.crafting_metadata.operations.recalibrate.cost_formula])
	lines.append("- 只支持有词缀的魔法与稀有实例。回收不看掷值；校准保留底材、等级、稀有度、族、阶级和顺序，只重掷已有整数值，可能下降或不变。")
	lines.append("")
	lines.append("## 每个底材的完整等级段预算区间")
	lines.append("")
	lines.append("每段对应当前装备目录的 tier 可用集合：物品等级 1–7、8–15、16–30。区间覆盖该段全部合法词族组合与各可用阶级；校准成本端点直接由相同源实例的 `recalibrate_plan()` 取得。完整 810 行与逐行见证在 [JSON 矩阵](crafting-budget.json)。")
	lines.append("")
	lines.append("| 底材 | 等级段 | 魔法回收量 | 魔法校准成本 | 稀有回收量 | 稀有校准成本 |")
	lines.append("|---|---:|---:|---:|---:|---:|")
	for base: Dictionary in report.budget_summary.by_base:
		for band: Dictionary in LEVEL_BANDS:
			var magic: Dictionary = _range_for_band(report.economy_matrix, base.base_id, "magic", band)
			var rare: Dictionary = _range_for_band(report.economy_matrix, base.base_id, "rare", band)
			lines.append("| %s (`%s`) | %d–%d | %d–%d | %d–%d | %d–%d | %d–%d |" % [base.name, base.base_id,
				band.minimum, band.maximum, magic.minimum_units, magic.maximum_units,
				magic.minimum_cost, magic.maximum_cost, rare.minimum_units, rare.maximum_units,
				rare.minimum_cost, rare.maximum_cost])
	lines.append("")
	lines.append("### 各底材稀有装备回收上限")
	lines.append("")
	lines.append("| 底材 | 物品等级 | 回收上限 | 同件校准成本 |")
	lines.append("|---|---:|---:|---:|")
	for base: Dictionary in report.budget_summary.by_base:
		var rare: Dictionary = base.rarities.rare
		lines.append("| %s (`%s`) | %d | %d | %d |" % [base.name, base.base_id,
			rare.maximum_at_item_level, rare.maximum_salvage_units, rare.maximum_recalibrate_cost])
	var global_rare: Dictionary = report.budget_summary.global_by_rarity.rare.maximum
	lines.append("")
	lines.append("全目录稀有回收上界为 **%d 枚**（`%s`，物品等级 %d）；按当前规则，同件数值校准扣 **%d 枚**。这是已枚举合法物品域内的精确上限，不是样本估计。" % [global_rare.salvage_units, global_rare.base_id, global_rare.item_level, global_rare.recalibrate_cost])
	lines.append("")
	lines.append("## 底材可用词族")
	lines.append("")
	lines.append("下表仅列能在当前生成池和底材资格中进入合法物品的族。每项后的 `T1/T2/T3@等级` 来自目录原始档位；是否能出现在魔法/稀有完整实例按当前稀有度词缀数与前后缀上限另行穷举，逐族等级见 JSON。")
	lines.append("")
	lines.append("| 底材 | 可出现词族（ID：T1/T2/T3 解锁等级） |")
	lines.append("|---|---|")
	for base: Dictionary in report.bases:
		var labels: Array[String] = []
		for family: Dictionary in report.affix_families:
			var pair: Dictionary = _find_family_pair(report.family_eligibility_matrix, base.id, family.id)
			if not pair.applicable:
				continue
			var unlocks: Array[String] = []
			for tier: Dictionary in family.tiers:
				unlocks.append("T%d@%d" % [tier.tier, tier.unlocked_at_item_level])
			labels.append("`%s`（%s）" % [family.id, "/".join(unlocks)])
		lines.append("| %s (`%s`) | %s |" % [base.name, base.id, "、".join(labels)])
	lines.append("")
	lines.append("## 可重现样例")
	lines.append("")
	var white: Dictionary = report.examples.normal_white_rejection
	lines.append("- 普通白装：`%s`，等级 %d，目录合法；回收与校准都由规则返回 `%s`：%s" % [white.source_instance.base_id, white.source_instance.item_level, white.salvage.code, white.salvage.reason])
	for key: String in ["global_minimum_yield", "global_maximum_yield"]:
		var example: Dictionary = report.examples[key]
		lines.append("- `%s`：输入 `%s`（%s / ilvl %d / %d 条词缀）→ 回收 %d 枚；校准种子 `%d`、消耗 %d 枚，结果 `%s`。" % [key,
			example.source_instance.base_id, example.source_instance.rarity, example.source_instance.item_level,
			example.source_instance.affixes.size(), example.salvage.materials[Craft.MATERIAL_ID],
			example.recalibrate.seed, example.recalibrate.cost[Craft.MATERIAL_ID],
			JSON.stringify(example.recalibrate.output_instance)])
	lines.append("")
	lines.append("样例的输入、完整输出与固定种子均记录在 JSON `examples` 字段中。当前无新工艺实现；此交付只给后续定价提供既有规则回收上界与资格矩阵。")
	lines.append("")
	return "\n".join(lines)


static func _range_for_band(matrix: Array[Dictionary], base_id: String, rarity: String,
		band: Dictionary) -> Dictionary:
	var minimum_units: int = 9223372036854775807
	var maximum_units: int = -9223372036854775807 - 1
	var minimum_cost: int = 9223372036854775807
	var maximum_cost: int = -9223372036854775807 - 1
	for row: Dictionary in matrix:
		if row.base_id != base_id or row.rarity != rarity or row.tier_unlock_band != band.id:
			continue
		minimum_units = mini(minimum_units, int(row.minimum.salvage_units))
		maximum_units = maxi(maximum_units, int(row.maximum.salvage_units))
		minimum_cost = mini(minimum_cost, int(row.minimum.recalibrate_cost))
		maximum_cost = maxi(maximum_cost, int(row.maximum.recalibrate_cost))
	assert(minimum_units != 9223372036854775807)
	return {"minimum_units": minimum_units, "maximum_units": maximum_units,
		"minimum_cost": minimum_cost, "maximum_cost": maximum_cost}


static func _find_family_pair(pairs: Array[Dictionary], base_id: String, family_id: String) -> Dictionary:
	for pair: Dictionary in pairs:
		if pair.base_id == base_id and pair.family_id == family_id:
			return pair
	return {}


static func _write(path: String, content: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot open crafting budget output: " + path)
		return false
	file.store_string(content)
	file.close()
	return true
