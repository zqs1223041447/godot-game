class_name CraftingTransactionPlanner
extends RefCounted
## Stateless transaction preparation. The integration owner validates the full
## build candidate, commits once, advances the authoritative revision and saves.
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
const Data = preload("res://scripts/game_data.gd")
const MAX_MATERIAL_COUNT: int = 9223372036854775807
const MAX_REVISION: int = 9223372036854775807
const CONTEXT_FIELDS: Array[String] = ["revision", "inventory", "equipment_instances",
	"equipped", "backpack_positions", "materials", "save_writable"]
const QUOTE_FIELDS: Array[String] = ["ok", "code", "reason", "operation", "item_id",
	"revision", "rules_version", "source_instance", "cost", "materials", "consumes_item"]


## Quote economics only; neither the seed nor a rolled replacement is exposed.
## Variant arguments reject coercion of bool/float/object into IDs or revisions.
static func quote(context: Variant, operation: Variant, item_id: Variant) -> Dictionary:
	if not operation is String or not Craft.operation_ids().has(operation):
		return _failure("invalid_operation", "未知工艺。")
	if not item_id is String or item_id.is_empty():
		return _failure("invalid_item_id", "物品标识必须为非空字符串。")
	var checked: Dictionary = _check_context(context)
	if not checked.ok:
		return checked
	if not context.save_writable:
		return _failure("save_read_only", "当前存档受写保护，不能进行工艺事务。")
	if not context.inventory.has(item_id):
		return _failure("not_owned", "当前库存未持有此物品。")
	if Data.ITEMS.has(item_id):
		return _failure("fixed_item", "固定示例或机制物品不支持工艺事务。")
	if context.equipped.values().has(item_id):
		return _failure("item_equipped", "请先卸下物品，再进行工艺操作。")
	if context.revision == MAX_REVISION:
		return _failure("revision_overflow", "修订号已达上限，不能产生下一次事务。")
	var source: Dictionary = context.equipment_instances[item_id]
	var rule: Dictionary = Craft.operation_quote(source, operation)
	if not rule.ok:
		return _failure(rule.code, rule.reason)
	if not _valid_amounts(rule.cost) or not _valid_amounts(rule.materials):
		return _failure("invalid_rule_result", "工艺规则返回了无效材料数量。")
	var wallet: Dictionary = _wallet_after(context.materials, rule.cost, rule.materials)
	if not wallet.ok:
		return wallet
	return {"ok": true, "code": "", "reason": "", "operation": operation,
		"item_id": item_id, "revision": context.revision, "rules_version": Craft.RULES_VERSION,
		"source_instance": source.duplicate(true), "cost": rule.cost.duplicate(true),
		"materials": rule.materials.duplicate(true), "consumes_item": rule.consumes_item}


## Recompute from the current authoritative context before considering a seed.
## A failure has no candidate or other partially applicable payload.
static func plan(context: Variant, quoted: Variant, seed_value: Variant) -> Dictionary:
	if not quoted is Dictionary or quoted.size() != QUOTE_FIELDS.size() or not quoted.has_all(QUOTE_FIELDS):
		return _failure("invalid_quote", "报价结构无效，请重新获取报价。")
	if not quoted.ok is bool or not quoted.ok or not quoted.operation is String \
			or not Craft.operation_ids().has(quoted.operation) or not quoted.item_id is String \
			or not quoted.revision is int or not quoted.rules_version is String:
		return _failure("invalid_quote", "报价标识或类型无效，请重新获取报价。")
	var current: Dictionary = quote(context, quoted.operation, quoted.item_id)
	if not current.ok:
		return current
	if quoted.revision != current.revision or quoted.rules_version != current.rules_version \
			or not _same_data(quoted.source_instance, current.source_instance):
		return _failure("stale_quote", "物品、修订号或工艺规则已变化，请重新获取报价。")
	if not _same_data(quoted, current):
		return _failure("invalid_quote", "报价与权威规则不一致，请重新获取报价。")
	if not seed_value is int:
		return _failure("invalid_seed", "事务种子必须为整数类型。")
	var wallet: Dictionary = _wallet_after(context.materials, current.cost, current.materials)
	if not wallet.ok:
		return wallet
	var replacement: Dictionary = {}
	if current.operation != "salvage":
		var rule: Dictionary = Craft.operation_plan(current.source_instance, current.operation, seed_value)
		if not rule.ok:
			return _failure(rule.code, rule.reason)
		if rule.rules_version != current.rules_version or not _same_data(rule.cost, current.cost) \
				or not _same_data(rule.materials, current.materials) \
				or not _same_data(rule.source_instance, current.source_instance):
			return _failure("invalid_rule_result", "工艺规则的计划与报价不一致。")
		replacement = rule.instance
	# All rejection paths precede candidate construction. No input alias is kept.
	var candidate: Dictionary = context.duplicate(true)
	if current.operation == "salvage":
		candidate.inventory.erase(current.item_id)
		candidate.equipment_instances.erase(current.item_id)
		candidate.backpack_positions.erase("item:" + current.item_id)
	else:
		candidate.equipment_instances[current.item_id] = replacement.duplicate(true)
	candidate.materials[Craft.MATERIAL_ID] = wallet.balance
	candidate.revision = context.revision + 1
	return {"ok": true, "code": "", "reason": "", "candidate": candidate}


## Check the seven-field projection, identity/ownership links and location
## shapes. Full layout, jewel ownership, capacity and save schema belong to the
## integration validator; this module cannot validate fields it never receives.
static func _check_context(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != CONTEXT_FIELDS.size() or not value.has_all(CONTEXT_FIELDS):
		return _failure("invalid_context", "工艺上下文必须恰好包含约定的七个字段。")
	if not value.revision is int or value.revision < 0:
		return _failure("invalid_revision", "修订号必须为非负整数类型。")
	if not value.materials is Dictionary or value.materials.size() != 1 \
			or not value.materials.has(Craft.MATERIAL_ID) \
			or not value.materials[Craft.MATERIAL_ID] is int or value.materials[Craft.MATERIAL_ID] < 0:
		return _failure("invalid_materials", "材料仅允许非负整数类型的 calibration_shard 余额。")
	if not value.inventory is Array or not value.equipment_instances is Dictionary \
			or not value.equipped is Dictionary or not value.backpack_positions is Dictionary \
			or not value.save_writable is bool:
		return _failure("invalid_context", "库存、实例、穿戴、位置或存档权限类型无效。")
	var seen: Dictionary = {}
	for id: Variant in value.inventory:
		if not id is String or seen.has(id) or (not Data.ITEMS.has(id) and not value.equipment_instances.has(id)):
			return _failure("invalid_context", "库存包含重复、无效或缺少实例的物品标识。")
		seen[id] = true
	for id: Variant in value.equipment_instances:
		var instance: Variant = value.equipment_instances[id]
		if not id is String or not Catalog.validate_instance(instance) \
				or instance.id != id or not seen.has(id):
			return _failure("invalid_context", "装备实例与目录、表键或所有权不一致。")
	for slot: Variant in value.equipped:
		var id: Variant = value.equipped[slot]
		if not slot is String or slot not in ["weapon", "armor", "charm"] or not id is String or not seen.has(id):
			return _failure("invalid_context", "穿戴槽或物品所有权无效。")
		var definition: Dictionary = Data.ITEMS[id] if Data.ITEMS.has(id) \
			else Catalog.base_definition(value.equipment_instances[id].base_id)
		if definition.slot != slot:
			return _failure("invalid_context", "物品与穿戴槽不匹配。")
	var worn: Array = value.equipped.values()
	for key: Variant in value.backpack_positions:
		if not key is String or not _valid_position(value.backpack_positions[key]):
			return _failure("invalid_context", "背包位置键或坐标类型无效。")
		if key.begins_with("item:"):
			if not seen.has(key.substr(5)) or worn.has(key.substr(5)):
				return _failure("invalid_context", "背包物品位置与所有权或穿戴状态不一致。")
		elif not key.begins_with("jewel:") or key.length() <= 6:
			return _failure("invalid_context", "未知背包位置键。")
	for id: String in value.inventory:
		if not worn.has(id) and not value.backpack_positions.has("item:" + id):
			return _failure("invalid_context", "未穿戴物品缺少背包位置。")
	return {"ok": true}


static func _valid_position(value: Variant) -> bool:
	if value is Vector2i:
		return value.x >= 0 and value.y >= 0
	if not value is Array or value.size() != 2:
		return false
	for coordinate: Variant in value:
		if not (coordinate is int or coordinate is float):
			return false
		var number: float = float(coordinate)
		if not is_finite(number) or number < 0.0 or number != floorf(number):
			return false
	return true


static func _valid_amounts(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 1:
		return false
	for id: Variant in value:
		if not id is String or id != Craft.MATERIAL_ID or not value[id] is int or value[id] < 0:
			return false
	return true


static func _wallet_after(materials: Dictionary, cost: Dictionary, gains: Dictionary) -> Dictionary:
	var balance: int = materials[Craft.MATERIAL_ID]
	var debit: int = cost.get(Craft.MATERIAL_ID, 0)
	var credit: int = gains.get(Craft.MATERIAL_ID, 0)
	if balance < debit:
		return _failure("insufficient_materials", "校准碎片余额不足。")
	var remainder: int = balance - debit
	# Compare before addition so signed 64-bit arithmetic can never wrap.
	if credit > MAX_MATERIAL_COUNT - remainder:
		return _failure("material_overflow", "回收收益会使材料余额溢出。")
	return {"ok": true, "balance": remainder + credit}


## Dictionary order is irrelevant, but int and float are not interchangeable.
static func _same_data(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _same_data(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _same_data(left[index], right[index]):
				return false
		return true
	return left == right


static func _failure(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason}
