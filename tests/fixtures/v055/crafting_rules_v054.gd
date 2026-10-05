extends RefCounted
## Pure quotes/plans only. The integration owner must validate ownership, commit
## inventory + materials atomically, refresh derived stats and persist once.
const Catalog = preload("res://tests/fixtures/v055/equipment_catalog_v054.gd")
const Expansion = preload("res://tests/fixtures/v055/crafting_expansion_rules_v054.gd")
const Targeted = preload("res://tests/fixtures/v055/targeted_reforge_rules_v054.gd")
const TARGETED_RULES_VERSION: String = "original-targeted-reforge-v1-affix27"
const LEGACY_SEED_VERSION: String = "original-crafting-prototype-v1"
const RULES_VERSION: String = "original-crafting-prototype-v2"
const CURRENT_RULES_VERSION: String = "original-crafting-prototype-v3-affix27"
const MATERIAL_ID: String = "calibration_shard"
## ORIGINAL, tunable prototype economy; not a live wallet or final balance.
const BALANCE: Dictionary = {
	"salvage_rarity_units": {"magic": 1, "rare": 3},
	"salvage_units_per_tier": 1,
	"recalibrate_cost_multiplier": 2,
}


static func metadata() -> Dictionary:
	var eligible: Dictionary = {}
	for base_id: String in Catalog.all_base_ids():
		var families: Array[String] = []
		for affix_id: String in Catalog.all_affix_ids():
			if Catalog.family_eligible(affix_id, base_id):
				families.append(affix_id)
		eligible[base_id] = families
	var result: Dictionary = {
		"id": "crafting_rules", "name": "装备工艺", "schema_version": 2,
		"rules_version": CURRENT_RULES_VERSION, "origin": "original", "status": "prototype",
		"catalog_source": "res://tests/fixtures/v055/equipment_catalog_v054.gd",
		"catalog_vocabulary": Catalog.CURRENT_VOCABULARY,
		"base_ids": Catalog.all_base_ids(), "affix_ids": Catalog.all_affix_ids(),
		"eligible_families_by_base": eligible,
		"rarities": ["normal", "magic", "rare"], "salvage_rarities": BALANCE.salvage_rarity_units.keys(),
		"materials": {MATERIAL_ID: {"name": "校准碎片", "unit": "枚"}},
		"balance": BALANCE.duplicate(true),
		"operations": {
			"salvage": {"name": "回收", "consumes_item": true, "cost": {},
				"yield_formula": "rarity_units + sum(tier) * salvage_units_per_tier"},
			"recalibrate": {"name": "数值校准", "consumes_item": false,
				"cost_formula": "salvage_yield * recalibrate_cost_multiplier",
				"preserves": ["id", "base_id", "rarity", "item_level", "affix_order", "affix_id", "tier"],
				"roll": "inclusive_integer_ticks_in_existing_tier", "can_roll_same_values": true},
		},
		"persistence_owner": "main_integration", "mutates_state": false,
	}
	for operation: String in Expansion.OPERATIONS:
		result.operations[operation] = Expansion.OPERATIONS[operation].duplicate(true)
		result.operations[operation]["consumes_item"] = false
	result["expansion"] = Expansion.metadata()
	for operation: String in Targeted.operation_ids():
		result.operations[operation] = Targeted.metadata(operation)
		result.operations[operation]["consumes_item"] = false
		result.operations[operation]["cost"] = Targeted.COSTS.duplicate()
		result.operations[operation]["rules_version"] = TARGETED_RULES_VERSION
	return result


static func operation_ids() -> Array[String]:
	var result: Array[String] = ["salvage", "recalibrate", "enchant", "elevate", "augment", "reforge"]
	result.append_array(Targeted.operation_ids())
	return result


## Detached display metadata. Prices and eligibility come from operation_quote.
static func operation_metadata(operation: String) -> Dictionary:
	if Targeted.operation_ids().has(operation):
		return Targeted.metadata(operation)
	var labels := {"salvage":"回收", "recalibrate":"校准"}
	var descriptions := {
		"salvage":"消耗这件装备，获得由稀有度和词缀阶级决定的校准碎片。",
		"recalibrate":"保留词缀种类与阶级，在原区间内重新随机数值。"}
	var risks := {
		"salvage":"装备会被消耗，无法撤销。",
		"recalibrate":"数值可能相同或降低，碎片仍会消耗。",
		"enchant":"随机获得合法词缀，结果不保证适合当前构筑。",
		"elevate":"原有词缀保持，新词缀随机；升格后重铸费用按稀有装备计算。",
		"augment":"仅在存在合法空位时可用，新词缀随机。",
		"reforge":"全部原词缀会被替换，结果可能相同或更差，碎片仍会消耗。"}
	if not operation_ids().has(operation): return {}
	return {"operation":operation,
		"label":labels.get(operation, Expansion.OPERATIONS.get(operation, {}).get("name", "")),
		"description":descriptions.get(operation, Expansion.OPERATIONS.get(operation, {}).get("description", "")),
		"risk":risks[operation]}


static func seed_rules_version(operation: String, vocabulary: int = Catalog.CURRENT_VOCABULARY) -> String:
	if Targeted.operation_ids().has(operation):
		return TARGETED_RULES_VERSION + ":" + operation
	return LEGACY_SEED_VERSION if operation in ["salvage", "recalibrate"] else (CURRENT_RULES_VERSION if vocabulary >= 27 else RULES_VERSION) + ":" + operation


## Economics-only quote: expanded operations never roll a replacement here.
static func operation_quote(instance: Variant, operation: Variant, vocabulary: int = Catalog.CURRENT_VOCABULARY) -> Dictionary:
	var result := _operation_quote_core(instance, operation, vocabulary)
	result.rules_version = TARGETED_RULES_VERSION if operation is String and Targeted.operation_ids().has(operation) else (CURRENT_RULES_VERSION if vocabulary >= 27 else RULES_VERSION)
	return result


static func _operation_quote_core(instance: Variant, operation: Variant, vocabulary: int) -> Dictionary:
	if not operation is String or not operation_ids().has(operation):
		return _rejected("", "invalid_operation", "未知工艺。")
	if not Catalog.validate_instance_for_version(instance, vocabulary):
		return _rejected(operation, "invalid_instance", "装备实例未通过所选词汇验证。")
	if operation == "salvage":
		return salvage_quote(instance)
	if operation == "recalibrate":
		var checked: Dictionary = _check_item(instance)
		if not checked.ok:
			return _rejected(operation, checked.code, checked.reason)
		var quoted: Dictionary = _result(operation)
		quoted.ok = true
		quoted.source_instance = instance.duplicate(true)
		quoted.cost = {MATERIAL_ID: _salvage_units(instance) * int(BALANCE.recalibrate_cost_multiplier)}
		return quoted
	var raw: Dictionary = Targeted.quote(instance, operation, vocabulary) if Targeted.operation_ids().has(operation) else Expansion.quote(instance, operation, vocabulary)
	if not raw.ok:
		return _rejected(operation, raw.code, raw.reason)
	var result: Dictionary = _result(operation)
	result.ok = true
	result.source_instance = instance.duplicate(true)
	result.cost = raw.cost.duplicate(true)
	return result


static func operation_plan(instance: Variant, operation: Variant, seed_value: Variant, vocabulary: int = Catalog.CURRENT_VOCABULARY) -> Dictionary:
	var result := _operation_plan_core(instance, operation, seed_value, vocabulary)
	result.rules_version = TARGETED_RULES_VERSION if operation is String and Targeted.operation_ids().has(operation) else (CURRENT_RULES_VERSION if vocabulary >= 27 else RULES_VERSION)
	return result


static func _operation_plan_core(instance: Variant, operation: Variant, seed_value: Variant, vocabulary: int) -> Dictionary:
	var quoted: Dictionary = operation_quote(instance, operation, vocabulary)
	if not quoted.ok:
		return quoted
	if not seed_value is int:
		return _rejected(operation, "invalid_seed", "工艺种子必须为整数类型。")
	if operation == "salvage":
		return quoted
	if operation == "recalibrate":
		return recalibrate_plan(instance, seed_value)
	var raw: Dictionary = Targeted.plan(instance, operation, seed_value, vocabulary) if Targeted.operation_ids().has(operation) else Expansion.plan(instance, operation, seed_value, vocabulary)
	if not raw.ok:
		return _rejected(operation, raw.code, raw.reason)
	quoted.instance = raw.instance.duplicate(true)
	quoted.definition = raw.definition.duplicate(true)
	return quoted


static func salvage_quote(instance: Variant) -> Dictionary:
	var checked: Dictionary = _check_item(instance)
	if not checked.ok:
		return _rejected("salvage", checked.code, checked.reason)
	var result: Dictionary = _result("salvage")
	result.ok = true
	result.source_instance = instance.duplicate(true)
	result.consumes_item = true
	result.materials = {MATERIAL_ID: _salvage_units(instance)}
	return result


## Accept an actual signed 64-bit int, including zero/negative seeds. Variant
## prevents implicit coercion of bool/string/float into a seemingly valid seed.
static func recalibrate_plan(instance: Variant, seed_value: Variant) -> Dictionary:
	var checked: Dictionary = _check_item(instance)
	if not checked.ok:
		return _rejected("recalibrate", checked.code, checked.reason)
	if not seed_value is int:
		return _rejected("recalibrate", "invalid_seed", "校准种子必须为整数类型。")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var replacement: Dictionary = instance.duplicate(true)
	for index: int in range(replacement.affixes.size()):
		var tier: Dictionary = checked.tiers[index]
		replacement.affixes[index].value = rng.randi_range(int(tier.min), int(tier.max))
	if not Catalog.validate_instance(replacement):
		return _rejected("recalibrate", "invalid_result", "校准结果未通过装备目录验证。")
	# This existing catalog path derives local W through WeaponLocalRules.resolve;
	# never duplicate the weapon formula or store derived fields on the instance.
	var definition: Dictionary = Catalog.definition(replacement)
	if definition.is_empty():
		return _rejected("recalibrate", "invalid_result", "校准结果无法派生装备属性。")
	var result: Dictionary = _result("recalibrate")
	result.ok = true
	result.source_instance = instance.duplicate(true)
	result.instance = replacement
	result.definition = definition
	result.cost = {MATERIAL_ID: _salvage_units(instance) * int(BALANCE.recalibrate_cost_multiplier)}
	return result


static func _check_item(instance: Variant) -> Dictionary:
	if not Catalog.validate_instance(instance):
		return {"ok": false, "code": "invalid_instance", "reason": "装备实例未通过当前目录验证。"}
	if instance.affixes.is_empty():
		return {"ok": false, "code": "no_affixes", "reason": "普通无词缀装备不支持回收或数值校准。"}
	if not BALANCE.salvage_rarity_units.has(instance.rarity):
		return {"ok": false, "code": "unsupported_rarity", "reason": "此稀有度尚未定义工艺成本。"}
	var base: Dictionary = Catalog.base_definition(instance.base_id)
	var tiers: Array[Dictionary] = []
	for affix: Dictionary in instance.affixes:
		var family: Dictionary = Catalog.affix_definition(affix.id)
		if base.is_empty() or family.is_empty() or not Catalog.family_eligible(affix.id, instance.base_id):
			return {"ok": false, "code": "invalid_instance", "reason": "底材或词缀资格无效。"}
		var existing_tier: Dictionary = {}
		for tier: Dictionary in family.tiers:
			if int(tier.tier) == int(affix.tier):
				existing_tier = tier
				break
		if existing_tier.is_empty():
			return {"ok": false, "code": "invalid_instance", "reason": "词缀阶级不存在。"}
		tiers.append(existing_tier)
	return {"ok": true, "tiers": tiers}


static func _salvage_units(instance: Dictionary) -> int:
	var units: int = int(BALANCE.salvage_rarity_units[instance.rarity])
	for affix: Dictionary in instance.affixes:
		units += int(affix.tier) * int(BALANCE.salvage_units_per_tier)
	return units


## Both operations share a detached result envelope. Empty payloads on failure
## cannot be mistaken for a partially applicable successful transaction.
static func _result(operation: String) -> Dictionary:
	return {"ok": false, "code": "", "reason": "", "operation": operation,
		"rules_version": RULES_VERSION, "cost": {}, "materials": {},
		"consumes_item": false, "source_instance": {}, "instance": {}, "definition": {}}


static func _rejected(operation: String, code: String, reason: String) -> Dictionary:
	var result: Dictionary = _result(operation)
	result.code = code
	result.reason = reason
	return result
