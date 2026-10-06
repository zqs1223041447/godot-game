class_name SupportRegistry
extends RefCounted
## One admission boundary for all providers; global slot/identity checks precede programs.
const Legacy = preload("res://scripts/combat/support_catalog.gd")
const Extension = preload("res://scripts/combat/projectile_support_rules.gd")
const Area = preload("res://scripts/combat/area_support_rules.gd")
const ResourceRules = preload("res://scripts/combat/resource_support_rules.gd")
const ElementRules = preload("res://scripts/combat/element_support_rules.gd")
const DeliveryRules = preload("res://scripts/combat/delivery_support_rules.gd")
const Ignite = preload("res://scripts/combat/ignite_support_rules.gd")
const Ember = preload("res://scripts/combat/ember_proliferation_support_rules.gd")
const Shock = preload("res://scripts/combat/shock_support_rules.gd")
const Ambush = preload("res://scripts/combat/ambush_support_rules.gd")
const Program = preload("res://scripts/combat/support_program.gd")
const Data = preload("res://scripts/game_data.gd")
const MAX_SUPPORTS: int = Legacy.MAX_SUPPORTS
const GROUP_MAX_SUPPORTS: int = 5
const EXTENSION_SAVE_VERSION: int = 10
const BATCH_SAVE_VERSION: int = 13
static var SUPPORTS: Dictionary = _definitions()

static func _providers() -> Array:
	return [Legacy, Extension, Area, ResourceRules, ElementRules, DeliveryRules, Ignite, Ember, Shock, Ambush]
static func _program_providers() -> Array:
	return [ResourceRules, ElementRules, DeliveryRules, Ignite, Ember, Shock, Ambush]
static func _definitions() -> Dictionary:
	var result: Dictionary = {}
	for provider: Variant in _providers():
		for id: String in provider.SUPPORTS:
			assert(not result.has(id), "Support identity collision")
			result[id] = provider.get_definition(id)
	return result
static func get_definition(id: String) -> Dictionary:
	for provider: Variant in _providers():
		if provider.SUPPORTS.has(id): return provider.get_definition(id)
	return {}
static func select_owned(ids: Array, catalog: Dictionary) -> Array:
	var result: Array = []
	for id: Variant in ids:
		if id is String and catalog.has(id): result.append(id)
	result.sort()
	return result
static func is_program_support(id: String) -> bool:
	for provider: Variant in _program_providers():
		if provider.SUPPORTS.has(id): return true
	return false
static func supports_for_skill(skill_id: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in SUPPORTS:
		if compatibility_reason(skill_id, [id]).is_empty(): result.append(id)
	return result
static func compatibility_reason(skill_id: String, support_ids: Variant, slot_limit: int = MAX_SUPPORTS) -> String:
	if slot_limit not in [MAX_SUPPORTS, GROUP_MAX_SUPPORTS]: return "辅助槽容量无效"
	if not Data.SKILLS.has(skill_id): return "未知技能"
	if not support_ids is Array or support_ids.size() > slot_limit: return "辅助数量超过本版本槽位容量"
	var seen: Dictionary = {}
	for value: Variant in support_ids:
		if not value is String or not SUPPORTS.has(value): return "未知辅助"
		if seen.has(value): return "同一技能不能重复装配辅助"
		seen[value] = true
		if get_definition(value).is_empty(): return "辅助元数据无效"
	if seen.has("ignite") and seen.has("ember_proliferation"): return "点燃辅助与余烬扩散辅助不能同时装配"
	var reason: String = Legacy.compatibility_reason(skill_id, select_owned(support_ids, Legacy.SUPPORTS))
	if not reason.is_empty(): return reason
	var skill: Dictionary = Data.SKILLS[skill_id]
	var selected: Array = select_owned(support_ids, Extension.SUPPORTS)
	if not selected.is_empty():
		reason = str(Extension.compile_extension(skill_id, skill.get("projectile_recipe", {}), selected).error)
		if not reason.is_empty(): return reason
	selected = select_owned(support_ids, Area.SUPPORTS)
	if not selected.is_empty():
		reason = str(Area.compile_area(skill_id, skill.get("area_recipe"), selected).error)
		if not reason.is_empty(): return reason
	for provider: Variant in _program_providers():
		selected = select_owned(support_ids, provider.SUPPORTS)
		if selected.is_empty(): continue
		reason = str(provider.compile_program(skill_id, selected, slot_limit).error)
		if not reason.is_empty(): return reason
	return ""
static func compile_programs(skill_id: String, support_ids: Array, slot_limit: int = MAX_SUPPORTS) -> Dictionary:
	var reason: String = compatibility_reason(skill_id, support_ids, slot_limit)
	if not reason.is_empty(): return Program.failure(reason)
	var result: Dictionary = Program.empty()
	for provider: Variant in _program_providers():
		var selected: Array = select_owned(support_ids, provider.SUPPORTS)
		if selected.is_empty(): continue
		var part: Dictionary = provider.compile_program(skill_id, selected, slot_limit)
		if not part.error.is_empty(): return Program.failure(part.error)
		result.modifiers.append_array(part.modifiers)
		result.mana_multiplier *= float(part.mana_multiplier)
		result.cooldown_multiplier *= float(part.cooldown_multiplier)
		for key: String in part.recipe_factors:
			if key == "chain_extra_targets": result.recipe_factors[key] = int(result.recipe_factors.get(key, 0)) + int(part.recipe_factors[key])
			else: result.recipe_factors[key] = float(result.recipe_factors.get(key, 1.0)) * float(part.recipe_factors[key])
	if not Program.number(result.mana_multiplier) or not Program.number(result.cooldown_multiplier): return Program.failure("辅助消耗或冷却倍率无效")
	return result
static func saved_links_reason(skill_id: String, support_ids: Variant, save_version: int) -> String:
	if Data.NEW_SKILL_IDS.has(skill_id) and save_version < Data.NEW_SKILL_SAVE_VERSION: return "此存档版本不支持新增主动技能"
	var reason: String = compatibility_reason(skill_id, support_ids)
	if not reason.is_empty(): return reason
	for id: String in support_ids:
		var minimum: int = 1
		if Ambush.SUPPORTS.has(id): minimum = Ambush.SAVE_VERSION
		elif Shock.SUPPORTS.has(id): minimum = Shock.SAVE_VERSION
		elif Ember.SUPPORTS.has(id): minimum = Ember.SAVE_VERSION
		elif Ignite.SUPPORTS.has(id): minimum = Ignite.SAVE_VERSION
		elif Extension.SUPPORTS.has(id): minimum = EXTENSION_SAVE_VERSION
		elif Area.SUPPORTS.has(id): minimum = int(Area.SAVE_VERSIONS[id])
		elif is_program_support(id): minimum = BATCH_SAVE_VERSION
		if save_version < minimum: return "此存档版本不支持" + str(get_definition(id).name)
	return ""
static func definition_error(value: Variant) -> String:
	if value is Dictionary and value.has("family"):
		match value.family:
			"ambush": return Ambush.definition_error(value)
			"shock": return Shock.definition_error(value)
			"burning":
				if Ember.definition_error(value).is_empty(): return ""
				return Ignite.definition_error(value)
			"resource": return ResourceRules.definition_error(value)
			"element": return ElementRules.definition_error(value)
			"delivery", "control", "chain": return DeliveryRules.definition_error(value)
		return "辅助类别无效"
	if value is Dictionary and value.get("requires") == ["area_hit"]: return Area.definition_error(value)
	if value is Dictionary and value.has("skills"): return Extension.definition_error(value)
	return Legacy.definition_error(value)
static func _string_array(value: Variant) -> bool: return Legacy._string_array(value)
static func _number(value: Variant) -> bool: return Legacy._number(value)
