class_name UnifiedItemCatalog
extends RefCounted
## One immutable item envelope for equipment, passive jewels and active/support gems.
## This adapter resolves definitions; locations and transactions remain separate.
const Data = preload("res://scripts/game_data.gd")
const Equipment = preload("res://scripts/items/equipment_catalog.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const Slots = preload("res://scripts/items/equipment_slots.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
const Currency = preload("res://scripts/items/currency_catalog.gd")
const Locations = preload("res://scripts/items/item_location_rules.gd")
const FIELDS: Array[String] = ["uid", "kind", "definition_id", "payload"]


static func fixed_equipment(uid: Variant, fixed_id: Variant) -> Dictionary:
	if not Locations._stable_id(uid) or not fixed_id is String or not Data.ITEMS.has(fixed_id):
		return {}
	return {"uid": uid, "kind": "equipment", "definition_id": "equipment:" + fixed_id, "payload": {}}


static func wrap_equipment(instance: Variant) -> Dictionary:
	if not Equipment.validate_instance(instance):
		return {}
	return {"uid": instance.id, "kind": "equipment", "definition_id": "equipment:" + str(instance.base_id), "payload": instance.duplicate(true)}


static func wrap_jewel(instance: Variant) -> Dictionary:
	if not Jewels.validate_instance(instance):
		return {}
	return {"uid": instance.id, "kind": "jewel", "definition_id": "jewel:" + str(instance.base), "payload": instance.duplicate(true)}


static func calibration_shard(uid: Variant, quantity: Variant) -> Dictionary:
	return Currency.make_instance(uid, quantity)


static func validate_instance(value: Variant) -> bool:
	if not Locations._exact_string_keys(value, FIELDS) or not Locations._stable_id(value.uid) \
			or not value.kind is String or not value.definition_id is String or not value.payload is Dictionary:
		return false
	match value.kind:
		"equipment":
			if not value.definition_id.begins_with("equipment:"):
				return false
			var id: String = value.definition_id.substr("equipment:".length())
			if value.payload.is_empty():
				return Data.ITEMS.has(id)
			return Equipment.validate_instance(value.payload) and value.payload.id == value.uid and value.payload.base_id == id
		"jewel":
			return value.definition_id.begins_with("jewel:") and Jewels.validate_instance(value.payload) \
				and value.payload.id == value.uid and "jewel:" + str(value.payload.base) == value.definition_id
		"currency":
			return Currency.validate_instance(value)
		"skill_gem", "support_gem":
			return Gems.validate_instance(value)
	return false


static func definition_for_instance(value: Variant) -> Dictionary:
	if not validate_instance(value):
		return {}
	var result: Dictionary = {}
	match value.kind:
		"equipment":
			if value.payload.is_empty():
				var fixed_id: String = value.definition_id.substr("equipment:".length())
				result = Data.ITEMS[fixed_id].duplicate(true)
				result.merge({"id": value.uid, "base_id": fixed_id, "base_name": result.name,
					"rarity": "unique", "item_level": 1, "affix_lines": []})
			else:
				result = Equipment.definition(value.payload)
			result["category"] = str(result.slot) if not Slots.targets_for_category(str(result.slot)).is_empty() else Slots.legacy_slot(str(result.slot))
		"jewel":
			var jewel: Dictionary = value.payload
			result = {"id": value.uid, "base_id": jewel.base, "base": jewel.base, "name": Jewels.display_name(jewel),
				"description": Jewels.get_description(jewel), "rarity": jewel.rarity,
				"color": Jewels.get_color(jewel), "stats": Jewels.get_stats(jewel),
				"size": Vector2i.ONE, "category": "", "effects": []}
		"currency":
			result = Currency.definition(value.payload.quantity)
		"skill_gem", "support_gem":
			result = Gems.metadata_for_instance(value)
			result["category"] = ""
	result["uid"] = value.uid
	result["kind"] = value.kind
	result["definition_id"] = value.definition_id
	return result


static func metadata_for_instance(value: Variant) -> Dictionary:
	var definition: Dictionary = definition_for_instance(value)
	if definition.is_empty():
		return {}
	var size: Variant = definition.size
	var dimensions: Array = [int(size.x), int(size.y)] if size is Vector2i else [int(size[0]), int(size[1])]
	return {"kind": value.kind, "category": str(definition.category), "size": dimensions}


static func metadata_for_items(items: Variant) -> Dictionary:
	if not items is Dictionary:
		return {}
	var metadata: Dictionary = {}
	for uid: Variant in items:
		var item: Variant = items[uid]
		if not uid is String or not validate_instance(item) or item.uid != uid:
			return {}
		metadata[uid] = metadata_for_instance(item)
	return metadata


## Only explicitly declared integer fields are normalized after JSON parsing.
## Jewelry affix values remain exact floating point values; no global rounding.
static func decode_instance(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not Locations._exact_string_keys(raw, FIELDS):
		return {}
	var item: Dictionary = raw.duplicate(true)
	if item.get("kind") in ["skill_gem", "support_gem"]:
		if not item.payload is Dictionary or not Locations._exact_string_keys(item.payload, ["level", "quality"]):
			return {}
		if not _whole(item.payload.level, 1, 1) or not _whole(item.payload.quality, 0, 0):
			return {}
		item.payload.level = int(item.payload.level)
		item.payload.quality = int(item.payload.quality)
	elif item.get("kind") == "currency":
		if not item.payload is Dictionary or not Locations._exact_string_keys(item.payload, ["quantity"]) \
				or not _whole(item.payload.quantity, 1, Currency.STACK_LIMIT):
			return {}
		item.payload.quantity = int(item.payload.quantity)
	elif item.get("kind") == "equipment" and item.payload is Dictionary and not item.payload.is_empty():
		if not Equipment.validate_instance(item.payload):
			return {}
		item.payload.item_level = int(item.payload.item_level)
		for affix: Dictionary in item.payload.affixes:
			affix.tier = int(affix.tier)
			affix.value = int(affix.value)
	elif item.get("kind") == "jewel" and Jewels.validate_instance(item.payload):
		for affix: Dictionary in item.payload.affixes:
			affix.value = float(affix.value)
	return item if validate_instance(item) else {}


static func decode_location(raw: Variant) -> Dictionary:
	return _decode_location(raw, false)


static func decode_paged_location(raw: Variant) -> Dictionary:
	return _decode_location(raw, true)

static func decode_current_location(raw: Variant) -> Dictionary:
	return _decode_location(raw,true,true)


static func _decode_location(raw: Variant, paged: bool, expanded: bool=false) -> Dictionary:
	if not raw is Dictionary or not raw.get("kind") is String:
		return {}
	var value: Dictionary = raw.duplicate(true)
	var fields: Array[String] = []
	match value.kind:
		"bag":
			fields = ["x", "y"]
			if paged:
				fields = ["page", "x", "y"]
		"skill_support", "recovery": fields = ["index"]
	for field: String in fields:
		# Specific kind bounds and field shape are enforced by ItemLocationRules.
		var maximum: int = 1 if paged and field == "page" else 1000000000
		if not value.has(field) or not _whole(value[field], 0, maximum):
			return {}
		value[field] = int(value[field])
	var shape_error: String = Locations._current_location_shape_error(value,str(value.kind)) if expanded else Locations._paged_location_shape_error(value, str(value.kind)) if paged else Locations._location_shape_error(value, str(value.kind))
	return value if shape_error.is_empty() else {}


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and number == floorf(number)
