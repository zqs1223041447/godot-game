extends RefCounted
## Shared pure program envelope for the batched support providers.
const Data = preload("res://docs/qa/v061-rules/frozen/scripts/game_data.gd")
const Damage = preload("res://docs/qa/v061-rules/frozen/scripts/combat/damage_resolver.gd")
const MAX_SUPPORTS: int = 2
const PRIMARY_TAGS: Dictionary = {
	"tornado": ["hit", "attack", "projectile"],
	"bolt": ["hit", "spell", "projectile"], "frost": ["hit", "spell", "projectile"],
	"nova": ["hit", "spell", "area"], "meteor": ["hit", "spell", "area"],
	"chain": ["hit", "spell", "chain"],
	"cleave": ["hit", "attack", "melee", "area"],
	"shade_bolt": ["hit", "spell", "projectile"],
}
static func empty() -> Dictionary:
	return {"error": "", "modifiers": [], "mana_multiplier": 1.0, "cooldown_multiplier": 1.0, "recipe_factors": {}}
static func failure(error: String) -> Dictionary:
	var result: Dictionary = empty()
	result.error = error
	return result
static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
static func strings(value: Variant) -> bool:
	if not value is Array: return false
	for entry: Variant in value:
		if not entry is String or entry.is_empty(): return false
	return true
static func selection_error(skill_id: Variant, support_ids: Variant, catalog: Dictionary, slot_limit: int = MAX_SUPPORTS) -> String:
	if slot_limit not in [2, 5]: return "辅助槽容量无效"
	if not skill_id is String or not Data.SKILLS.has(skill_id): return "未知技能"
	if not support_ids is Array or support_ids.size() > slot_limit: return "辅助列表无效或超过可用槽位"
	var seen: Dictionary = {}
	for id: Variant in support_ids:
		if not id is String or not catalog.has(id): return "未知辅助"
		if seen.has(id): return "同一技能不能重复装配辅助"
		seen[id] = true
		var definition: Variant = catalog[id]
		if not definition is Dictionary or not strings(definition.get("skills")) or not definition.skills.has(skill_id): return "技能不支持此辅助"
	return ""
static func primary_modifier(id: String, skill_id: String, value: float, types: Array = []) -> Dictionary:
	if not PRIMARY_TAGS.has(skill_id) or not is_finite(value) or value <= -1.0 or not strings(types): return {}
	var seen: Dictionary = {}
	for type: String in types:
		if not Damage.TYPES.has(type) or seen.has(type): return {}
		seen[type] = true
	return {"id": "support:" + id, "mode": "more", "value": value,
		"all_tags": PRIMARY_TAGS[skill_id].duplicate(), "skills": [skill_id], "damage_types": types.duplicate()}
