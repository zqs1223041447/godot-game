class_name UnifiedItemPresentation
extends RefCounted
## Shared compact views for bag, equipment, passive jewels and skill rows.
## Derived values come from the owning model; this adapter never mutates a build.

const Gear = preload("res://scripts/items/equipment_catalog.gd")
const LegacyText = preload("res://scripts/passive_data.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Slots = preload("res://scripts/items/equipment_slots.gd")
const Data = preload("res://scripts/game_data.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const CATEGORIES := {"weapon":"武器","body_armour":"护甲","amulet":"项链","ring":"戒指","boots":"鞋","belt":"腰带","gloves":"手套","helmet":"头盔"}
const RARITIES := {"normal":"普通","magic":"魔法","rare":"稀有","unique":"机制装备","special":"特殊"}
const CAPABILITY_LABELS: Dictionary = {
	"initial_projectiles":"投射物", "projectile_hit":"投射物命中", "split_projectiles":"分裂",
	"area_hit":"范围命中", "movement":"位移", "shield_recovery":"护盾回复",
	"chain_hit":"连锁命中", "finite_projectile_pierce":"可穿透",
}
const RECIPE_TAG_LABELS: Dictionary = {
	"hit":"命中", "projectile":"投射物", "spell":"法术", "area":"范围",
	"attack":"攻击", "chain":"连锁", "secondary":"次级", "explosion":"爆炸", "melee":"近战",
}
const DAMAGE_LABELS: Dictionary = {
	"physical":"物理", "fire":"火焰", "cold":"冰霜", "lightning":"闪电", "chaos":"混沌",
}
const SUPPORT_FAMILY_LABELS: Dictionary = {
	"resource":"资源", "element":"元素", "delivery":"发射", "control":"控制", "chain":"连锁",
}
const OPERATION_LABELS: Dictionary = {
	"mana_multiplier":"魔力消耗", "cooldown_multiplier":"冷却时间",
	"projectile_hit_more":"投射物命中伤害", "primary_hit_more":"主命中伤害",
	"area_hit_more":"范围命中伤害", "area_multiplier":"范围面积",
	"projectile_speed_multiplier":"投射物速度", "slow_duration_multiplier":"减速时长",
	"chain_extra_targets":"额外连锁目标", "chain_followup_range_multiplier":"后续寻敌距离",
	"add_initial_projectiles":"初始投射物", "add_pierce":"穿透",
	"primary_component_more":"主命中伤害", "other_components_more":"非所选类型伤害",
}

static var _base_recipe_tag_cache: Dictionary = {}
static var _support_applicability_cache: Dictionary = {}
static var _base_recipe_tag_compile_count: int = 0
static var _support_applicability_scan_count: int = 0


## The top-level return schema keeps legacy line fields and adds typed structured data.
## tags: Array[String]; function: String; base_stats: Array[{label:String,value:String}].
## modifiers: Array[{label:String,value:String,polarity:"benefit"|"cost"|"neutral"}].
## preview_lines: Array[String] describes the cached current combo, never base properties.
static func view(model: RefCounted, uid: String) -> Dictionary:
	var item: Dictionary = model.item(uid)
	var definition: Dictionary = model.item_definition(uid)
	if item.is_empty() or definition.is_empty():
		return {}
	var result := {
		"uid":uid,
		"rarity":str(definition.get("rarity","normal")),
		"name":str(definition.get("name","")),
		"kind_label":"",
		"rarity_label":"",
		"description":str(definition.get("description","")),
		"requirements":[],
		"base_lines":[],
		"affix_lines":[],
		"effect_lines":[],
		"tags":[],
		"function":str(definition.get("description","")),
		"base_stats":[],
		"modifiers":[],
		"preview_lines":[],
	}
	match str(item.kind):
		"flask":
			result.kind_label = "药剂"
			result.tags = ["回复", "生命" if definition.get("resource") == "health" else "魔力"]
			result.base_stats = [{"label":"最大充能","value":str(definition.max_charges)},{"label":"使用消耗","value":str(definition.cost)},{"label":"持续时间","value":"%.1f秒" % float(definition.duration)},{"label":"回复比例","value":"%.0f%%" % (100.0*float(definition.recovery_fraction))}]
			if model.has_method("get_flask_profile"):
				result.preview_lines = flask_preview_lines(model.call("get_flask_profile",uid))
				result.effect_lines = result.preview_lines.duplicate(true)
		"currency":
			result.kind_label = "制作材料"
			result.tags = ["可堆叠"]
			result.base_stats = [{"label":"数量","value":str(item.payload.quantity)},
				{"label":"单堆上限","value":str(definition.get("stack_limit",1000000000))}]
		"equipment":
			result.kind_label = CATEGORIES.get(str(definition.get("category","")), "装备")
			result.rarity_label = RARITIES.get(str(definition.get("rarity","")), str(definition.get("rarity","")))
			result.function = ""
			result.description = ""
			var base_stats: Dictionary=definition.get("stats",{}).duplicate(true)
			if not item.payload.is_empty():
				result.kind_label += " · 物品等级 %d" % int(item.payload.get("item_level",1))
				base_stats=Gear.base_definition(str(item.payload.get("base_id",""))).get("stats",{}).duplicate(true)
				for affix: Dictionary in item.payload.get("affixes",[]):
					var family: Dictionary=Gear.affix_definition(str(affix.id))
					result.affix_lines.append("%s +%d%s" % [str(family.get("label",family.get("name",""))),int(affix.value),"%" if family.get("unit")=="percent" else ""])
			for stat: String in base_stats:
				result.base_lines.append(LegacyText.describe_stats({stat:base_stats[stat]}))
			if definition.has("weapon_profile"):
				result.base_lines.append("本武器基础物理伤害 %.2f" % float(definition.weapon_profile.base.physical))
			for effect: String in definition.get("effects",[]):
				result.effect_lines.append("投射物抵达射程后返回" if effect=="return_on_range" else "飞行结束触发独立爆炸" if effect=="explode_on_flight_end" else effect)

		"jewel":
			result.kind_label = "天赋珠宝"
			result.rarity_label = RARITIES.get(str(definition.get("rarity","")), str(definition.get("rarity","")))
			result.tags = ["天赋珠宝"]
		"skill_gem":
			result.kind_label = "主动宝石"
			result.rarity_label = "等级 %s · 品质 %s" % [
				str(item.payload.get("level", 1)), str(item.payload.get("quality", 0))]
			var skill_id: String = str(definition.get("skill_id",""))
			result.tags = _skill_tags(definition, skill_id)
			result.base_stats = _base_skill_stats(skill_id, item.payload)
			var skill_location: Dictionary = model.location(uid)
			_append_current_preview(model, skill_location, result, true)
		"support_gem":
			result.kind_label = "辅助宝石"
			result.rarity_label = "等级 %s · 品质 %s" % [
				str(item.payload.get("level", 1)), str(item.payload.get("quality", 0))]
			var support_id: String = str(definition.get("support_id",""))
			result.tags = _support_tags(definition, support_id)
			result.function = "改变相连主动技能的效果，不能单独施放。"
			result.description = ""
			var supported_names: PackedStringArray=[]
			for skill_id: String in _applicable_skill_ids(support_id):
				supported_names.append(str(Data.SKILLS[skill_id].get("name",skill_id)))
			result.requirements = ["适用技能："+"、".join(supported_names)]

			result.base_stats = []
			result.modifiers = _support_modifiers(support_id, false)
			var support_location: Dictionary = model.location(uid)
			_append_current_preview(model, support_location, result)
	return result


static func comparisons(model: RefCounted, uid: String) -> Array:
	var source: Dictionary = model.item(uid)
	if source.get("kind", "") != "equipment":
		return []
	var definition: Dictionary = model.item_definition(uid)
	var equipped: Dictionary = model.equipped_items()
	var result: Array = []
	for target: String in Slots.targets_for_category(str(definition.get("category",""))):
		var other: String = str(equipped.get(target, ""))
		if not other.is_empty() and other != uid:
			result.append(view(model, other))
	return result


static func _skill_tags(definition: Dictionary, skill_id: String) -> Array[String]:
	var tags: Array[String] = []
	# These capabilities are copied from GemCatalog metadata, not from prose.
	_append_capability_tags(tags, definition.get("capabilities", []), false)
	for recipe_tag: String in _cached_base_recipe_tags(skill_id):
		_append_tag(tags, recipe_tag)
	return tags


static func _support_tags(definition: Dictionary, support_id: String) -> Array[String]:
	var tags: Array[String] = ["辅助"]
	# GemCatalog exposes the support's actual requirements as its capabilities field.

	var support: Dictionary = Supports.get_definition(support_id)
	var family: String = str(support.get("family",""))
	if SUPPORT_FAMILY_LABELS.has(family):
		_append_tag(tags, str(SUPPORT_FAMILY_LABELS[family]) + "辅助")

	return tags


static func _append_capability_tags(target: Array[String], value: Variant, is_requirement: bool) -> void:
	if not value is Array:
		return
	for capability: Variant in value:
		if not capability is String or not CAPABILITY_LABELS.has(capability):
			continue
		var label: String = str(CAPABILITY_LABELS[capability])
		_append_tag(target, ("需要" if is_requirement else "") + label)


static func _append_mapped_tag(target: Array[String], value: String, labels: Dictionary) -> void:
	if labels.has(value):
		_append_tag(target, str(labels[value]))


static func _append_tag(target: Array[String], value: String) -> void:
	if not value.is_empty() and not target.has(value):
		target.append(value)


static func _cached_base_recipe_tags(skill_id: String) -> Array[String]:
	if _base_recipe_tag_cache.has(skill_id):
		var cached: Array[String] = []
		cached.assign(_base_recipe_tag_cache[skill_id])
		return cached
	var tags: Array[String] = []
	if Data.SKILLS.has(skill_id):
		# Compile one neutral, fixed snapshot per skill; its damage is discarded.
		# Only exact packet recipe tags are cached and shown.
		var compiled: Dictionary = Compiler.compile_skill(skill_id, Combat.snapshot({"damage":18.0}, []), [])
		_base_recipe_tag_compile_count += 1
		if bool(compiled.get("ok", false)):
			var packets: Dictionary = compiled.get("packets", {})
			for packet: Dictionary in _intrinsic_recipe_packets(skill_id, packets):
				_append_packet_tags(tags, packet)
	_base_recipe_tag_cache[skill_id] = tags.duplicate()
	return tags


static func _intrinsic_recipe_packets(skill_id: String, packets: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var roles: Array[String] = []
	match skill_id:
		"bolt", "frost": roles = ["projectile"]
		"tornado": roles = ["parent", "child"]
		"nova", "meteor": roles = ["direct"]
		"chain": roles = ["bounces"]
	for role: String in roles:
		var value: Variant = packets.get(role)
		if value is Dictionary:
			result.append(value)
		elif value is Array:
			for packet: Variant in value:
				if packet is Dictionary:
					result.append(packet)
	return result


static func _append_packet_tags(target: Array[String], packet: Dictionary) -> void:
	var values: Variant = packet.get("tags", [])
	if not values is Array:
		return
	for tag: Variant in values:
		if tag is String:
			_append_mapped_tag(target, tag, RECIPE_TAG_LABELS)


static func _applicable_skill_ids(support_id: String) -> Array[String]:
	if _support_applicability_cache.has(support_id):
		var cached: Array[String] = []
		cached.assign(_support_applicability_cache[support_id])
		return cached
	_support_applicability_scan_count += 1
	var result: Array[String] = []
	var ids: Array = Data.SKILLS.keys()
	ids.sort()
	for raw_id: Variant in ids:
		if raw_id is String and Supports.compatibility_reason(raw_id, [support_id]).is_empty():
			result.append(raw_id)
	_support_applicability_cache[support_id] = result.duplicate()
	return result


static func _base_skill_stats(skill_id: String, payload: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"label":"宝石等级", "value":str(payload.get("level", 1))},
		{"label":"品质", "value":str(payload.get("quality", 0))},
	]
	if not Data.SKILLS.has(skill_id):
		return result
	var skill: Dictionary = Data.SKILLS[skill_id]
	_append_numeric_stat(result, "基础魔力消耗", skill.get("mana"))
	_append_numeric_stat(result, "基础冷却", skill.get("cooldown"), " 秒")
	if skill.has("projectile_recipe"):
		var projectile: Dictionary = skill.projectile_recipe
		_append_numeric_stat(result, "基础投射物数", projectile.get("initial_count"))
		_append_percent_stat(result, "基础命中系数", projectile.get("coefficient"))
		_append_type_stat(result, projectile.get("damage_type"))
		_append_numeric_stat(result, "基础穿透", projectile.get("pierce"))
		_append_numeric_stat(result, "基础速度", projectile.get("speed"))
		_append_numeric_stat(result, "基础减速", projectile.get("slow"), " 秒")
	elif skill_id == "tornado":
		_append_numeric_stat(result, "基础母箭数", Combat.TORNADO.get("parent_count"))
		_append_numeric_stat(result, "每母箭子箭", Combat.TORNADO.get("child_count"))
		_append_percent_stat(result, "基础母箭系数", Combat.TORNADO.get("parent", {}).get("coefficient"))
		_append_percent_stat(result, "基础子箭系数", Combat.TORNADO.get("child", {}).get("coefficient"))
	elif skill.has("hit_recipe"):
		var hit: Dictionary = skill.hit_recipe
		_append_percent_stat(result, "基础命中系数", hit.get("base_coefficient"))
		_append_percent_stat(result, "附加伤害效用", hit.get("added_effectiveness"))
		_append_type_stat(result, hit.get("damage_type"))
		if hit.has("bounce_count"):
			_append_numeric_stat(result, "基础弹跳目标数", hit.get("bounce_count"))
			_append_percent_stat(result, "每跳系数递减", hit.get("base_coefficient_loss_per_bounce"))
		var area: Dictionary = skill.get("area_recipe", {})
		if area.has("radius"):
			_append_numeric_stat(result, "基础范围半径", area.get("radius"))
		var targeting: Dictionary = skill.get("targeting_recipe", {})
		if targeting.has("first_range"):
			_append_numeric_stat(result, "首次寻敌距离", targeting.get("first_range"))
		if targeting.has("followup_range"):
			_append_numeric_stat(result, "后续寻敌距离", targeting.get("followup_range"))
	return result


static func _append_numeric_stat(target: Array[Dictionary], label: String, value: Variant,
		suffix: String = "") -> void:
	if value is int or value is float:
		target.append({"label":label, "value":str(value) + suffix})


static func _append_percent_stat(target: Array[Dictionary], label: String, value: Variant) -> void:
	if value is int or value is float:
		target.append({"label":label, "value":"%s%%" % str(float(value) * 100.0)})


static func _append_type_stat(target: Array[Dictionary], value: Variant) -> void:
	if value is String and DAMAGE_LABELS.has(value):
		target.append({"label":"基础伤害类型", "value":str(DAMAGE_LABELS[value])})


static func _support_modifiers(support_id: String, include_source: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var definition: Dictionary = Supports.get_definition(support_id)
	var operations: Variant = definition.get("operations", [])
	if not operations is Array:
		return result
	for value: Variant in operations:
		if not value is Dictionary:
			continue
		var entry: Dictionary = _operation_entry(value, str(definition.get("name","")) if include_source else "")
		if not entry.is_empty():
			result.append(entry)
	return result


static func _support_modifiers_for_ids(support_ids: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not support_ids is Array:
		return result
	for support_id: Variant in support_ids:
		if support_id is String:
			result.append_array(_support_modifiers(support_id))
	return result


static func _operation_entry(operation: Dictionary, source_name: String) -> Dictionary:
	var operation_id: String = str(operation.get("op",""))
	if not OPERATION_LABELS.has(operation_id):
		return {}
	var raw: Variant = operation.get("value")
	if not (raw is int or raw is float) or not is_finite(float(raw)):
		return {}
	var amount: float = float(raw)
	var label: String = str(OPERATION_LABELS[operation_id])
	var display_value: String = ""
	var polarity: String = "neutral"
	if operation_id in ["mana_multiplier", "cooldown_multiplier", "projectile_speed_multiplier",
			"slow_duration_multiplier", "area_multiplier", "chain_followup_range_multiplier"]:
		display_value = "×%.2f" % amount
		polarity = _factor_polarity(amount, operation_id in ["mana_multiplier", "cooldown_multiplier"])
	elif operation_id in ["projectile_hit_more", "primary_hit_more", "area_hit_more"]:
		display_value = _total_more_percent(amount)
		polarity = _delta_polarity(amount)
	elif operation_id in ["add_initial_projectiles", "add_pierce", "chain_extra_targets"]:
		display_value = _signed_number(amount)
		polarity = _delta_polarity(amount)
	elif operation_id in ["primary_component_more", "other_components_more"]:
		var damage_type: String = str(operation.get("damage_type",""))
		if not DAMAGE_LABELS.has(damage_type):
			return {}
		label = ("主命中" + str(DAMAGE_LABELS[damage_type]) if operation_id == "primary_component_more" else "非" + str(DAMAGE_LABELS[damage_type])) + "伤害"
		display_value = _total_more_percent(amount)
		polarity = _delta_polarity(amount)
	if polarity == "neutral":
		return {}
	if not source_name.is_empty():
		label = source_name + " · " + label
	return {"label":label, "value":display_value, "polarity":polarity}


static func _factor_polarity(amount: float, lower_is_better: bool) -> String:
	if is_equal_approx(amount, 1.0):
		return "neutral"
	if lower_is_better:
		return "benefit" if amount < 1.0 else "cost"
	return "benefit" if amount > 1.0 else "cost"


static func _delta_polarity(amount: float) -> String:
	if is_zero_approx(amount):
		return "neutral"
	return "benefit" if amount > 0.0 else "cost"


static func _signed_number(amount: float) -> String:
	return ("+" if amount > 0.0 else "") + str(amount)


static func _total_more_percent(amount: float) -> String:
	var direction: String = "总增" if amount > 0.0 else "总降"
	var percent: float = absf(amount) * 100.0
	var percent_text: String = str(roundi(percent)) if is_equal_approx(percent, roundf(percent)) else str(percent)
	return "%s %s%%" % [direction, percent_text]


static func _append_current_preview(model: RefCounted, location: Dictionary, result: Dictionary,
		include_linked_modifiers: bool = false) -> void:
	if not location.has("group_id") or not model.has_method("get_group_cast"):
		return
	var cast: Dictionary = model.call("get_group_cast", str(location.group_id))
	if bool(cast.get("ok", false)):
		if include_linked_modifiers:
			result.modifiers = _support_modifiers_for_ids(cast.get("support_ids", []))
		result.preview_lines.append("当前组合消耗：%s 魔力 · %s 秒冷却" % [
			str(cast.get("mana", "")), str(cast.get("cooldown", ""))])
		var summary: String = Preview.summary(cast)
		if not summary.is_empty():
			result.preview_lines.append(summary)
		result.effect_lines = result.preview_lines.duplicate(true)
	else:
		var error: String = str(cast.get("error",""))
		if not error.is_empty():
			result.preview_lines.append("当前组合暂不可施放：" + error)
			result.effect_lines = result.preview_lines.duplicate(true)


static func flask_preview_lines(profile: Dictionary) -> Array[String]:
	if not profile.get("ok",false): return []
	return ["当前构筑：%.2f 秒内回复 %.2f %s" % [float(profile.duration),float(profile.recovery_total),"生命" if profile.resource=="health" else "魔力"],
		"每只有效原生怪获得 %.2f 充能（小数累计）" % float(profile.charges_per_root)]
