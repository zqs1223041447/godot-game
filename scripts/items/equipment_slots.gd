class_name EquipmentSlots
extends RefCounted
## Pure mapping between canonical equipment targets and item categories.
## This directory does not own inventory state, equip transactions, or balance.

const ERROR_UNKNOWN_CATEGORY: String = "unknown_category"
const ERROR_UNKNOWN_SLOT: String = "unknown_slot"
const ERROR_CATEGORY_MISMATCH: String = "category_mismatch"

const _SLOT_ORDER: Array[String] = [
	"weapon", "body_armour", "amulet", "ring_1", "ring_2",
	"boots", "belt", "gloves", "helmet",
]

const _SLOT_CATEGORIES: Dictionary = {
	"weapon": "weapon",
	"body_armour": "body_armour",
	"amulet": "amulet",
	"ring_1": "ring",
	"ring_2": "ring",
	"boots": "boots",
	"belt": "belt",
	"gloves": "gloves",
	"helmet": "helmet",
}

const _CATEGORY_TARGETS: Dictionary = {
	"weapon": ["weapon"],
	"body_armour": ["body_armour"],
	"amulet": ["amulet"],
	"ring": ["ring_1", "ring_2"],
	"boots": ["boots"],
	"belt": ["belt"],
	"gloves": ["gloves"],
	"helmet": ["helmet"],
}

const _LEGACY_ALIASES: Dictionary = {
	"armor": "body_armour",
	"charm": "amulet",
}


static func all_slots() -> Array[String]:
	return _SLOT_ORDER.duplicate()


static func category_for_slot(id: Variant) -> String:
	if not id is String or not _SLOT_CATEGORIES.has(id):
		return ""
	return _SLOT_CATEGORIES[id]


static func targets_for_category(category: Variant) -> Array[String]:
	if not category is String or not _CATEGORY_TARGETS.has(category):
		return []
	var result: Array[String] = []
	for target: String in _CATEGORY_TARGETS[category]:
		result.append(target)
	return result


static func legacy_slot(id: Variant) -> String:
	if not id is String:
		return ""
	if _LEGACY_ALIASES.has(id):
		return _LEGACY_ALIASES[id]
	if _SLOT_CATEGORIES.has(id):
		return id
	return ""


static func target_reason(category: Variant, target: Variant) -> String:
	if not category is String or not _CATEGORY_TARGETS.has(category):
		return ERROR_UNKNOWN_CATEGORY
	if not target is String or not _SLOT_CATEGORIES.has(target):
		return ERROR_UNKNOWN_SLOT
	if _SLOT_CATEGORIES[target] != category:
		return ERROR_CATEGORY_MISMATCH
	return ""
