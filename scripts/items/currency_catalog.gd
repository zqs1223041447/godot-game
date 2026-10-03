class_name CurrencyCatalog
extends RefCounted
## Immutable definition for the stackable calibration shard item.
## Quantities are payload state; the catalog keeps identity and presentation.

const Locations = preload("res://scripts/items/item_location_rules.gd")
const KIND := "currency"
const CALIBRATION_SHARD_ID := "currency:calibration_shard"
const CALIBRATION_SHARD_NAME := "校准碎片"
const STACK_LIMIT := 1000000000
const INVENTORY_LIMIT := 1000000000


static func make_instance(uid: Variant, quantity: Variant) -> Dictionary:
	if not Locations._stable_id(uid) or not _valid_quantity(quantity):
		return {}
	return {
		"uid": uid,
		"kind": KIND,
		"definition_id": CALIBRATION_SHARD_ID,
		"payload": {"quantity": quantity},
	}


static func validate_instance(value: Variant) -> bool:
	return Locations._exact_string_keys(value, ["uid", "kind", "definition_id", "payload"]) \
		and Locations._stable_id(value.uid) and typeof(value.kind) == TYPE_STRING and value.kind == KIND \
		and typeof(value.definition_id) == TYPE_STRING and value.definition_id == CALIBRATION_SHARD_ID \
		and Locations._exact_string_keys(value.payload, ["quantity"]) and _valid_quantity(value.payload.quantity)


static func definition(quantity: Variant) -> Dictionary:
	if not _valid_quantity(quantity):
		return {}
	return {
		"id": CALIBRATION_SHARD_ID,
		"base_id": CALIBRATION_SHARD_ID,
		"name": CALIBRATION_SHARD_NAME,
		"description": "用于数值校准的结晶碎片。仅背包中的碎片可用于工艺。",
		"quantity": quantity,
		"stack_limit": STACK_LIMIT,
		"color": Color("#8bd8df"),
		"size": Vector2i.ONE,
		"category": "",
	}


static func total_quantity(items: Variant) -> Dictionary:
	if not items is Dictionary:
		return {"ok": false, "error_code": "invalid_inventory", "quantity": 0}
	var total := 0
	for uid: Variant in items:
		var item: Variant = items[uid]
		if item is Dictionary and item.get("kind", "") == KIND:
			if not validate_instance(item) or item.uid != uid:
				return {"ok": false, "error_code": "invalid_currency", "quantity": 0}
			var quantity: int = item.payload.quantity
			if quantity > INVENTORY_LIMIT - total:
				return {"ok": false, "error_code": "currency_inventory_limit", "quantity": 0}
			total += quantity
	return {"ok": true, "error_code": "", "quantity": total}


static func _valid_quantity(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 1 and value <= STACK_LIMIT
