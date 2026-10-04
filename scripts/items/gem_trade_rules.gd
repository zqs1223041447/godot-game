class_name GemTradeRules
extends RefCounted
## Pure economics only. Ownership, locations, funds, snapshots and atomic commits
## belong to the inventory model. Quotes never allocate UIDs or change an instance.
const Gems = preload("res://scripts/items/gem_catalog.gd")
const MATERIAL_ID: String = "calibration_shard"
const ACTIVE_COST: int = 8
const SUPPORT_COST: int = 4
const RECYCLE_CREDIT: int = 1


## Rebuild detached display entries from the real catalog, without a second ID list.
static func offers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var definitions: Dictionary = Gems.definitions()
	for definition_id: String in definitions:
		var definition: Dictionary = definitions[definition_id]
		var cost: int = _purchase_cost(definition.get("kind", ""))
		if cost > 0:
			result.append({"definition_id": definition_id, "kind": definition.kind,
				"name": definition.name, "cost": cost})
	return result


## Buy targets an exact definition ID and accepts only an empty instance argument.
## Recycle targets the UID of the exact catalog-valid instance supplied by the model.
## Variant parameters prevent coercion of bools, numbers and StringNames into IDs.
static func quote(operation: Variant, target: Variant, instance: Variant = {}) -> Dictionary:
	var result: Dictionary = _result(operation, target)
	if typeof(operation) != TYPE_STRING or operation not in ["buy", "recycle"]:
		return _rejected(result, "invalid_operation", "未知宝石交易。")
	if typeof(target) != TYPE_STRING or target.is_empty():
		return _rejected(result, "invalid_target", "交易目标必须为非空字符串。")
	var definition: Dictionary = {}
	if operation == "buy":
		if not instance is Dictionary or not instance.is_empty():
			return _rejected(result, "invalid_instance", "购买只接受宝石定义，不接受实例。")
		definition = Gems.definition(target)
		if definition.is_empty() or _purchase_cost(definition.get("kind", "")) == 0:
			return _rejected(result, "unknown_definition", "宝石定义不存在。")
		result.cost = {MATERIAL_ID: _purchase_cost(definition.kind)}
	else:
		if not Gems.validate_instance(instance):
			return _rejected(result, "invalid_instance", "宝石实例未通过目录验证。")
		if instance.uid != target:
			return _rejected(result, "target_mismatch", "交易目标与宝石实例标识不一致。")
		definition = Gems.definition(instance.definition_id)
		result.materials = {MATERIAL_ID: RECYCLE_CREDIT}
	result.ok = true
	result.definition_id = definition.definition_id
	result.name = definition.name
	return result


static func _purchase_cost(kind: String) -> int:
	if kind == "skill_gem":
		return ACTIVE_COST
	if kind == "support_gem":
		return SUPPORT_COST
	return 0


static func _result(operation: Variant, target: Variant) -> Dictionary:
	return {"ok": false, "code": "", "reason": "",
		"operation": operation if typeof(operation) == TYPE_STRING else "",
		"target": target if typeof(target) == TYPE_STRING else "",
		"definition_id": "", "name": "", "cost": {}, "materials": {}}


static func _rejected(result: Dictionary, code: String, reason: String) -> Dictionary:
	result.code = code
	result.reason = reason
	return result
