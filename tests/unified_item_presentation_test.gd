extends SceneTree

const Presenter = preload("res://scripts/ui/unified_item_presentation.gd")
const GemCatalogScript = preload("res://scripts/items/gem_catalog.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")

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
	_expect((support_view.tags as Array).has("适配·飞弹") and (support_view.tags as Array).has("适配·冰霜"), "support applicability tags come from SupportRegistry compatibility")
	_expect((support_view.tags as Array).has("需要投射物命中"), "support requirement tag comes from GemCatalog capabilities")
	_expect(_modifier_polarity(support_view.modifiers, "缓速强击辅助 · 主命中伤害") == "benefit", "support modifier label/value comes from operation metadata")
	_expect(_modifier_polarity(support_view.modifiers, "缓速强击辅助 · 魔力消耗") == "cost", "support cost is represented by typed polarity")
	_expect(support_view.preview_lines == skill_view.preview_lines, "support displays the same current group preview separately from its base properties")
	_expect(_stat_value(support_view.base_stats, "宝石等级") == "1" and _stat_value(support_view.base_stats, "品质") == "0", "support base properties use the fixed level/quality payload")
	var repeated_support_view: Dictionary = Presenter.view(model, support_item.uid)
	_expect(repeated_support_view.tags == support_view.tags and Presenter._support_applicability_scan_count == applicability_scans_before + 1, "repeated support hovers reuse cached compatibility results")

	print("unified_item_presentation_test: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


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
