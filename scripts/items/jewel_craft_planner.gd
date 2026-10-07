class_name JewelCraftPlanner
extends RefCounted
## Narrow projection only. CanonicalGameState validates the full build, currency
## placement, saved receipt and profile before committing one complete candidate.
const Craft = preload("res://scripts/items/jewel_craft_rules.gd")
const ExistingPlanner = preload("res://scripts/items/crafting_transaction_planner.gd")
const Currency = preload("res://scripts/items/currency_catalog.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const MAX_REVISION := 1000000000
const CONTEXT_FIELDS := ["revision", "jewels", "locations", "materials", "save_writable"]


static func quote(context: Variant, operation: Variant, uid: Variant) -> Dictionary:
	if not operation is String or not Craft.operation_ids().has(operation):
		return _failure("invalid_operation", "普通珠宝只支持回收与整体重铸。")
	if not uid is String or Craft.Jewels.serial_from_id(uid) <= 0:
		return _failure("invalid_item_id", "珠宝标识无效。")
	if not context is Dictionary or not Locations._exact_string_keys(context, CONTEXT_FIELDS) \
			or not context.revision is int or context.revision < 0 or context.revision >= MAX_REVISION \
			or not context.jewels is Dictionary or not context.locations is Dictionary \
			or context.jewels.size() != 1 or context.locations.size() != 1 \
			or not context.jewels.has(uid) or not context.locations.has(uid) \
			or not context.save_writable is bool:
		return _failure("invalid_context", "珠宝工艺上下文无效。")
	if not context.save_writable: return _failure("save_read_only", "当前存档受写保护。")
	if not ExistingPlanner._valid_amounts(context.materials) or context.materials.size() != 1 \
			or context.materials[Craft.MATERIAL_ID] > Currency.INVENTORY_LIMIT:
		return _failure("invalid_materials", "校准碎片库存无效。")
	var rule := Craft.operation_quote(context.jewels[uid], operation)
	if not rule.ok: return rule
	if rule.source_instance.id != uid: return _failure("invalid_context", "珠宝所有权与身份不一致。")
	var cell: Variant = context.locations[uid]
	if not cell is Dictionary or not cell.get("kind") is String:
		return _failure("invalid_context", "珠宝位置无效。")
	if cell.kind != "bag": return _failure("item_equipped", "请先把珠宝放入背包。")
	if not Locations._exact_string_keys(cell, ["kind", "page", "x", "y"]) \
			or not cell.page is int or cell.page < 0 or cell.page >= Locations.CURRENT_BAG_PAGES \
			or not cell.x is int or cell.x < 0 or cell.x >= Locations.CURRENT_BAG_COLUMNS \
			or not cell.y is int or cell.y < 0 or cell.y >= Locations.CURRENT_BAG_ROWS:
		return _failure("invalid_context", "珠宝背包坐标无效。")
	var balance: int = context.materials[Craft.MATERIAL_ID]
	var debit: int = rule.cost.get(Craft.MATERIAL_ID, 0)
	var credit: int = rule.materials.get(Craft.MATERIAL_ID, 0)
	if balance < debit: return _failure("insufficient_materials", "背包中的校准碎片不足。")
	if credit > Currency.INVENTORY_LIMIT - (balance - debit):
		return _failure("material_overflow", "校准碎片总量已达上限。")
	rule.item_id = uid
	rule.revision = context.revision
	return rule


static func plan(context: Variant, quoted: Variant, seed_value: Variant) -> Dictionary:
	if not quoted is Dictionary or not Locations._exact_string_keys(quoted, ExistingPlanner.QUOTE_FIELDS) \
			or not quoted.ok is bool or not quoted.ok or not quoted.operation is String or not quoted.item_id is String:
		return _failure("invalid_quote", "珠宝报价结构无效。")
	var current := quote(context, quoted.operation, quoted.item_id)
	if not current.ok: return current
	if not ExistingPlanner._same_data(quoted, current):
		return _failure("stale_quote", "珠宝、修订号或报价已变化，请重新获取报价。")
	var rule := Craft.operation_plan(current.source_instance, current.operation, seed_value)
	if not rule.ok: return rule
	var candidate: Dictionary = context.duplicate(true)
	if current.consumes_item:
		candidate.jewels.erase(current.item_id)
		candidate.locations.erase(current.item_id)
	else:
		candidate.jewels[current.item_id] = rule.instance.duplicate(true)
	candidate.materials[Craft.MATERIAL_ID] += int(current.materials.get(Craft.MATERIAL_ID, 0)) - int(current.cost.get(Craft.MATERIAL_ID, 0))
	candidate.revision += 1
	return {"ok": true, "code": "", "reason": "", "candidate": candidate}


static func _failure(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason}
