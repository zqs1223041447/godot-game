extends SceneTree

const Presenter = preload("res://scripts/ui/unified_item_presentation.gd")
const GemCatalogScript = preload("res://scripts/items/gem_catalog.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const ElementSupports = preload("res://scripts/combat/element_support_rules.gd")

class PresentationModel extends RefCounted:
	var items: Dictionary = {}
	var definitions: Dictionary = {}
	var locations: Dictionary = {}
	var casts: Dictionary = {}
	var equipped: Dictionary = {}
	var cast_reads: int = 0

	func item(uid: String) -> Dictionary:
		return items.get(uid, {}).duplicate(true)

	func item_definition(uid: String) -> Dictionary:
		return definitions.get(uid, {}).duplicate(true)

	func location(uid: String) -> Dictionary:
		return locations.get(uid, {}).duplicate(true)

	func get_group_cast(group_id: String) -> Dictionary:
		cast_reads += 1
		return casts.get(group_id, {}).duplicate(true)

	func equipped_items() -> Dictionary:
		return equipped.duplicate(true)


var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run()


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	var model := PresentationModel.new()
	var skill_item: Dictionary = GemCatalogScript.create_instance("test-main-bolt", "skill:bolt")
	var skill_definition: Dictionary = GemCatalogScript.metadata_for_instance(skill_item)
	model.items[skill_item.uid] = skill_item.duplicate(true)
	model.definitions[skill_item.uid] = skill_definition.duplicate(true)
	model.locations[skill_item.uid] = {"kind":"skill_main", "group_id":"test-group"}
	model.casts["test-group"] = Compiler.compile_group("bolt", Combat.snapshot({"damage":9999.0}, []), ["focus"])
	var original_items: Dictionary = model.items.duplicate(true)
	var original_definitions: Dictionary = model.definitions.duplicate(true)
	var original_cast: Dictionary = model.casts.duplicate(true)
	var compile_count_before: int = Presenter._base_recipe_tag_compile_count

	var skill_view: Dictionary = Presenter.view(model, skill_item.uid)
	_expect(skill_view.get("name", "") == "奥术飞弹", "active-gem name comes from GemCatalog")
	_expect(skill_view.get("function", "") == skill_definition.description, "function section comes from catalog definition text")
	_expect(skill_view.get("tags", []) is Array and (skill_view.tags as Array).has("投射物"), "capability tag comes from GemCatalog metadata")
	_expect((skill_view.tags as Array).has("法术") and (skill_view.tags as Array).has("命中"), "recipe tags come from actual compiled packets")
	_expect(skill_view.get("base_stats", []) is Array, "base stats use the typed structured array")
	_expect(_stat_value(skill_view.get("base_stats", []), "基础魔力消耗") == "7.0", "base mana uses the static level-one skill definition")
	_expect(_stat_value(skill_view.get("base_stats", []), "基础命中系数") == "160.0%", "base coefficient comes from the skill recipe")
	_expect(_stat_value(skill_view.get("base_stats", []), "当前组合消耗").is_empty(), "live group costs do not leak into base properties")
	_expect(skill_view.get("preview_lines", []) is Array and skill_view.preview_lines.size() == 2, "current group preview is an independent field")
	_expect(skill_view.preview_lines[0].contains("8.4") and skill_view.preview_lines[1] == Preview.summary(model.casts["test-group"]), "current preview reads the cached model cast and current build damage")
	_expect(skill_view.get("effect_lines", []) == skill_view.preview_lines, "legacy effect_lines remains populated for old view consumers")
	_expect(_modifier_polarity(skill_view.get("modifiers", []), "凝束辅助 · 投射物命中伤害") == "benefit", "linked support gain comes from its typed operation")
	_expect(_modifier_polarity(skill_view.get("modifiers", []), "凝束辅助 · 魔力消耗") == "cost", "linked support cost comes from its typed operation")
	_expect(Presenter._base_recipe_tag_compile_count == compile_count_before + 1, "base recipe tags compile once on first view")
	var repeated_view: Dictionary = Presenter.view(model, skill_item.uid)
	_expect(repeated_view.tags == skill_view.tags and Presenter._base_recipe_tag_compile_count == compile_count_before + 1, "repeated hover reuses cached recipe tags")
	_expect(model.cast_reads == 2, "adapter asks for current cast only during view construction")
	_expect(model.items == original_items and model.definitions == original_definitions and model.casts == original_cast, "view assembly leaves model snapshots untouched")
	skill_view.tags.clear()
	(skill_view.base_stats as Array).clear()
	_expect(model.items == original_items and model.definitions == original_definitions, "consumer mutation of the view cannot mutate model-owned data")

	var support_item: Dictionary = GemCatalogScript.create_instance("test-support-heavy", "support:heavy_projectiles")
	var support_definition: Dictionary = GemCatalogScript.metadata_for_instance(support_item)
	model.items[support_item.uid] = support_item.duplicate(true)
	model.definitions[support_item.uid] = support_definition.duplicate(true)
	model.locations[support_item.uid] = {"kind":"skill_support", "group_id":"test-group"}
	var applicability_scans_before: int = Presenter._support_applicability_scan_count
	var support_view: Dictionary = Presenter.view(model, support_item.uid)
	_expect(support_view.kind_label == "辅助宝石" and support_view.rarity_label == "等级 1 · 品质 0", "support view keeps the old category/quality labels")
	_expect((support_view.tags as Array).has("发射辅助"), "support family tag comes from SupportRegistry")
	_expect(not (support_view.tags as Array).has("适配·飞弹") and not (support_view.tags as Array).has("适配·冰霜") and str(support_view.requirements).contains(GemCatalogScript.definition("skill:bolt").name) and str(support_view.requirements).contains(GemCatalogScript.definition("skill:frost").name), "support applicability is disclosed separately from tags")
	_expect(not (support_view.tags as Array).has("需要投射物命中"), "support tags do not contain requirement prose")
	_expect(_modifier_polarity(support_view.modifiers, "主命中伤害") == "benefit", "support modifier label/value comes from operation metadata")
	_expect(_modifier_polarity(support_view.modifiers, "魔力消耗") == "cost", "support cost is represented by typed polarity")
	_expect(_modifier_value(support_view.modifiers, "主命中伤害") == "总增 20%", "more modifier copy distinguishes a total increase from additive increased")
	_expect(support_view.preview_lines == skill_view.preview_lines, "support displays the same current group preview separately from its base properties")
	_expect(support_view.base_stats.is_empty(), "support fixed level/quality remain in header without duplicate effect rows")
	var repeated_support_view: Dictionary = Presenter.view(model, support_item.uid)
	_expect(repeated_support_view.tags == support_view.tags and Presenter._support_applicability_scan_count == applicability_scans_before + 1, "repeated support hovers reuse cached compatibility results")
	_test_all_catalog_gems_and_element_modifiers(model)

	print("unified_item_presentation_test: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_all_catalog_gems_and_element_modifiers(model: PresentationModel) -> void:
	var definitions: Dictionary = GemCatalogScript.definitions()
	_expect(definitions.size() == 26, "coverage traverses every10 skill and16 support gem in GemCatalog")
	var skill_count: int = 0
	for definition_id: String in definitions:
		var uid: String = "coverage-" + definition_id.replace(":", "-")
		var item: Dictionary = GemCatalogScript.create_instance(uid, definition_id)
		var definition: Dictionary = GemCatalogScript.metadata_for_instance(item)
		model.items[uid] = item
		model.definitions[uid] = definition
		var item_view: Dictionary = Presenter.view(model, uid)
		_expect(not item_view.is_empty(), "catalog view builds for %s" % definition_id)
		if item.kind != "skill_gem":
			continue
		skill_count += 1
		var skill_id: String = str(definition.skill_id)
		var tags: Array = item_view.get("tags", [])
		if skill_id in ["bolt", "frost", "tornado", "shade_bolt"]:
			_expect(not tags.has("爆炸") and not tags.has("次级") and not tags.has("范围"), "%s does not inherit the compiler's always-prepared secondary explosion tags" % skill_id)
		if skill_id == "tornado":
			_expect(tags.has("投射物") and tags.has("分裂"), "tornado keeps its own projectile and split capability tags")
		if skill_id in ["nova", "meteor"]:
			_expect(tags.has("范围"), "%s retains its intrinsic direct area tag" % skill_id)
	_expect(skill_count == 10, "all ten active skill gems were checked")

	var element_cases: Array[Dictionary] = [
		{"id":"physical_focus", "type":"physical", "label":"物理"},
		{"id":"fire_focus", "type":"fire", "label":"火焰"},
		{"id":"cold_focus", "type":"cold", "label":"冰霜"},
		{"id":"lightning_focus", "type":"lightning", "label":"闪电"},
	]
	for case: Dictionary in element_cases:
		var definition: Dictionary = ElementSupports.get_definition(str(case.id))
		var primary_operation: Dictionary = _operation_for(definition.operations, "primary_component_more")
		var other_operation: Dictionary = _operation_for(definition.operations, "other_components_more")
		var primary: Dictionary = Presenter._operation_entry(primary_operation, str(definition.name))
		var other: Dictionary = Presenter._operation_entry(other_operation, str(definition.name))
		_expect(primary.label == "%s · 主命中%s伤害" % [definition.name, case.label], "%s identifies its selected native component" % case.id)
		_expect(other.label == "%s · 非%s伤害" % [definition.name, case.label], "%s uses the exclusion scope for all other components" % case.id)
		_expect(primary.value == "总增 20%" and primary.polarity == "benefit", "%s presents multiplicative gains as total increase" % case.id)
		_expect(other.value == "总降 20%" and other.polarity == "cost", "%s presents multiplicative losses as total decrease" % case.id)
	var negative_more: Dictionary = Presenter._operation_entry({"op":"projectile_hit_more", "value":-0.2}, "测试辅助")
	_expect(negative_more.value == "总降 20%", "negative more modifiers use total decrease wording")
	var positive_more: Dictionary = Presenter._operation_entry({"op":"projectile_hit_more", "value":0.25}, "测试辅助")
	_expect(positive_more.value == "总增 25%", "positive more modifiers use total increase wording")


func _operation_for(operations: Array, operation_id: String) -> Dictionary:
	for operation: Variant in operations:
		if operation is Dictionary and operation.get("op", "") == operation_id:
			return operation
	return {}


func _stat_value(entries: Variant, label: String) -> String:
	if not entries is Array:
		return ""
	for row: Variant in entries:
		if row is Dictionary and row.get("label", "") == label:
			return str(row.get("value", ""))
	return ""


func _modifier_polarity(entries: Variant, label: String) -> String:
	if not entries is Array:
		return ""
	for row: Variant in entries:
		if row is Dictionary and row.get("label", "") == label:
			return str(row.get("polarity", ""))
	return ""


func _modifier_value(entries: Variant, label: String) -> String:
	if not entries is Array:
		return ""
	for row: Variant in entries:
		if row is Dictionary and row.get("label", "") == label:
			return str(row.get("value", ""))
	return ""
