class_name SupportRegistry
extends RefCounted
## Unified catalog adapter: legacy rules never import their optional extension.
const Legacy = preload("res://scripts/combat/support_catalog.gd")
const Extension = preload("res://scripts/combat/projectile_support_rules.gd")
const Area = preload("res://scripts/combat/area_support_rules.gd")
const Data = preload("res://scripts/game_data.gd")
const MAX_SUPPORTS: int = Legacy.MAX_SUPPORTS
const EXTENSION_SAVE_VERSION: int = 10
static var SUPPORTS: Dictionary = _definitions()

static func _definitions() -> Dictionary:
	var result: Dictionary = Legacy.SUPPORTS.duplicate(true)
	for id: String in Extension.SUPPORTS:
		assert(not result.has(id), "Support identity collision")
		result[id] = Extension.get_definition(id)
	for id: String in Area.SUPPORTS:
		assert(not result.has(id), "Support identity collision")
		result[id] = Area.get_definition(id)
	return result

static func get_definition(id: String) -> Dictionary:
	if Legacy.SUPPORTS.has(id):
		return Legacy.get_definition(id)
	if Area.SUPPORTS.has(id):
		return Area.get_definition(id)
	return Extension.get_definition(id)

static func supports_for_skill(skill_id: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in SUPPORTS:
		if compatibility_reason(skill_id, [id]).is_empty():
			result.append(id)
	return result

static func compatibility_reason(skill_id: String, support_ids: Variant) -> String:
	if not support_ids is Array:
		return Legacy.compatibility_reason(skill_id, support_ids)
	for value: Variant in support_ids:
		if value is String and Area.SUPPORTS.has(value):
			return str(Area.compile_area(skill_id, Data.SKILLS.get(skill_id, {}).get("area_recipe"), support_ids).error)
	var has_extension: bool = false
	for value: Variant in support_ids:
		if value is String and Extension.SUPPORTS.has(value):
			has_extension = true
	if not has_extension:
		return Legacy.compatibility_reason(skill_id, support_ids)
	var skill: Dictionary = Data.SKILLS.get(skill_id, {})
	return str(Extension.compile_extension(skill_id, skill.get("projectile_recipe", {}), support_ids).error)

static func saved_links_reason(skill_id: String, support_ids: Variant, save_version: int) -> String:
	var reason: String = compatibility_reason(skill_id, support_ids)
	if not reason.is_empty():
		return reason
	for id: String in support_ids:
		if Area.SUPPORTS.has(id) and save_version < Area.SAVE_VERSION:
			return "此存档版本不支持广域辅助"
		if Extension.SUPPORTS.has(id) and save_version < EXTENSION_SAVE_VERSION:
			return "此存档版本不支持贯穿辅助"
	return ""

static func definition_error(value: Variant) -> String:
	if value is Dictionary and value.get("requires") == ["area_hit"]:
		return Area.definition_error(value)
	if value is Dictionary and value.has("skills"):
		return Extension.definition_error(value)
	return Legacy.definition_error(value)

static func _string_array(value: Variant) -> bool:
	return Legacy._string_array(value)

static func _number(value: Variant) -> bool:
	return Legacy._number(value)
