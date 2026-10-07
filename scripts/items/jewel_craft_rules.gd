class_name JewelCraftRules
extends RefCounted
## Ordinary jewel crafting is separate from natural drops and equipment RNG.
const Jewels = preload("res://scripts/jewel_data.gd")
const RULES_VERSION := "ordinary-jewel-crafting-v1"
const MATERIAL_ID := "calibration_shard"
const SALVAGE_UNITS := {"magic": 1, "rare": 2}
const REFORGE_COSTS := {"magic": 8, "rare": 16}


static func operation_ids() -> Array[String]:
	return ["salvage", "reforge"]


static func operation_metadata(operation: String) -> Dictionary:
	if operation == "salvage":
		return {"operation": operation, "label": "回收", "description": "消耗这颗普通珠宝，魔法返还1枚、稀有返还2枚校准碎片。", "risk": "这颗珠宝会被消耗，无法撤销。"}
	if operation == "reforge":
		return {"operation": operation, "label": "整体重铸", "description": "保留珠宝身份、底材和稀有度，重新随机全部合法词缀及数值；魔法8枚、稀有16枚校准碎片。", "risk": "全部原词缀会被替换，结果可能相同或更差，碎片仍会消耗。"}
	return {}


static func operation_quote(instance: Variant, operation: Variant) -> Dictionary:
	if not operation is String or not operation_ids().has(operation):
		return _failure("invalid_operation", "普通珠宝只支持回收与整体重铸。")
	if not Jewels.validate_instance(instance):
		return _failure("invalid_instance", "珠宝实例无效。")
	if not Jewels.BASES.has(instance.base) or not Jewels.RARITIES.has(instance.rarity):
		return _failure("special_jewel", "特殊珠宝不支持回收或整体重铸。")
	return {"ok": true, "code": "", "reason": "", "operation": operation,
		"rules_version": RULES_VERSION, "source_instance": instance.duplicate(true),
		"cost": {MATERIAL_ID: REFORGE_COSTS[instance.rarity]} if operation == "reforge" else {},
		"materials": {MATERIAL_ID: SALVAGE_UNITS[instance.rarity]} if operation == "salvage" else {},
		"consumes_item": operation == "salvage"}


static func operation_plan(instance: Variant, operation: Variant, seed_value: Variant) -> Dictionary:
	var result := operation_quote(instance, operation)
	if not result.ok: return result
	if not seed_value is int: return _failure("invalid_seed", "珠宝工艺种子必须为整数。")
	if operation == "salvage": return result
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var replacement: Dictionary = instance.duplicate(true)
	replacement.affixes = []
	var prefix_count := 1 if instance.rarity == "magic" else rng.randi_range(1, 2)
	var suffix_count := 1 if instance.rarity == "magic" else 2
	for kind: String in ["prefix", "suffix"]:
		var pool: Array = Jewels.BASES[instance.base][kind + "es"].duplicate()
		for unused: int in range(prefix_count if kind == "prefix" else suffix_count):
			var chosen := rng.randi_range(0, pool.size() - 1)
			var affix_id: String = pool[chosen]
			pool.remove_at(chosen)
			var definition: Dictionary = Jewels.AFFIXES[affix_id]
			var steps := roundi((float(definition.max) - float(definition.min)) / float(definition.step))
			var amount := float(definition.min) + float(rng.randi_range(0, steps)) * float(definition.step)
			replacement.affixes.append({"id": affix_id, "value": float(roundi(amount * 100.0)) / 100.0})
	if not Jewels.validate_instance(replacement, false):
		return _failure("invalid_rule_result", "珠宝重铸结果未通过合法性验证。")
	result.instance = replacement
	return result


static func _failure(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason}
