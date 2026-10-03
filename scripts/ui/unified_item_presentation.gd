class_name UnifiedItemPresentation
extends RefCounted
## Shared compact views for bag, equipment, passive jewels and skill rows.
## Derived values come from the owning model; this file never mutates a build.
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const LegacyText = preload("res://scripts/passive_data.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Slots = preload("res://scripts/items/equipment_slots.gd")
const CATEGORIES := {"weapon":"武器","body_armour":"护甲","amulet":"项链","ring":"戒指","boots":"鞋","belt":"腰带","gloves":"手套","helmet":"头盔"}
const RARITIES := {"normal":"普通","magic":"魔法","rare":"稀有","unique":"机制装备","special":"特殊"}


static func view(model: RefCounted,uid: String) -> Dictionary:
	var item: Dictionary = model.item(uid)
	var definition: Dictionary = model.item_definition(uid)
	if item.is_empty() or definition.is_empty(): return {}
	var result := {"uid":uid,"name":str(definition.name),"kind_label":"","rarity_label":"",
		"description":str(definition.get("description","")),"requirements":[],"base_lines":[],"affix_lines":[],"effect_lines":[]}
	match item.kind:
		"equipment":
			result.kind_label = CATEGORIES.get(definition.category,"装备")
			result.rarity_label = RARITIES.get(definition.rarity,definition.rarity)
			if not item.payload.is_empty():
				result.kind_label += " · 物品等级 %d" % int(item.payload.item_level)
				result.description = Gear.base_definition(item.payload.base_id).description
			result.affix_lines = definition.get("affix_lines",[]).duplicate(true)
			var stats: Dictionary = definition.get("stats",{}).duplicate(true)
			if stats.has("additional_skill_slots"):
				result.effect_lines.append("额外技能行 +%d；卸下仅停用超出行，保留宝石与配置" % int(stats.additional_skill_slots))
				stats.erase("additional_skill_slots")
			if not stats.is_empty(): result.base_lines.append("装备合计：" + LegacyText.describe_stats(stats))
			if definition.has("weapon_damage_summary"): result.base_lines.append(definition.weapon_damage_summary)
			for effect: String in definition.get("effects",[]):
				result.effect_lines.append("投射物抵达射程后返回" if effect == "return_on_range" else "飞行结束触发独立爆炸" if effect == "explode_on_flight_end" else effect)
		"jewel":
			result.kind_label = "天赋珠宝"
			result.rarity_label = RARITIES.get(definition.rarity,definition.rarity)
		"skill_gem", "support_gem":
			result.kind_label = "主动宝石" if item.kind == "skill_gem" else "辅助宝石"
			result.rarity_label = "等级 1 · 品质 0"
			var location: Dictionary = model.location(uid)
			if location.has("group_id"):
				var cast: Dictionary = model.get_group_cast(location.group_id)
				if cast.get("ok",false):
					result.effect_lines.append("当前行：%.2f 魔力 · %.2f 秒冷却" % [cast.mana,cast.cooldown])
					result.effect_lines.append(Preview.summary(cast))
				else: result.effect_lines.append(str(cast.get("error","")))
	return result


static func comparisons(model: RefCounted,uid: String) -> Array:
	var source: Dictionary = model.item(uid)
	if source.get("kind","") != "equipment": return []
	var definition: Dictionary = model.item_definition(uid)
	var equipped: Dictionary = model.equipped_items()
	var result: Array = []
	for target: String in Slots.targets_for_category(definition.category):
		var other: String = equipped.get(target,"")
		if not other.is_empty() and other != uid: result.append(view(model,other))
	return result
