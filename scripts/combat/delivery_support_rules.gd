class_name DeliverySupportRules
extends RefCounted
## Pure delivery/control/chain programs. The compiler applies factors to validated recipes.
## No runtime state, RNG, packet assembly, recipe mutation or save writes live here.
const Data = preload("res://scripts/game_data.gd")
const Program = preload("res://scripts/combat/support_program.gd")
const FACTORS: Array[String] = ["projectile_speed_multiplier", "slow_duration_multiplier",
	"chain_extra_targets", "chain_followup_range_multiplier"]
const SUPPORTS: Dictionary = {
	"swift_projectiles": {
		"name": "疾速投射辅助",
		"description": "飞弹、冰霜、蚀影飞弹与龙卷：投射物速度 ×1.35，魔力 ×1.10。龙卷母箭与子箭均加速；伤害、射程与寿命不变。",
		"skills": ["bolt", "frost", "shade_bolt", "tornado"], "requires": ["projectile_hit"], "family": "delivery",
		"operations": [
			{"op": "projectile_speed_multiplier", "value": 1.35},
			{"op": "mana_multiplier", "value": 1.10},
		],
	},
	"heavy_projectiles": {
		"name": "缓速强击辅助",
		"description": "飞弹、冰霜、蚀影飞弹与龙卷：投射物速度 ×0.75，主命中伤害总增 20%，魔力 ×1.15。龙卷母箭与子箭均生效；伤害类型、射程与寿命不变，独立爆炸不增伤。",
		"skills": ["bolt", "frost", "shade_bolt", "tornado"], "requires": ["projectile_hit"], "family": "delivery",
		"operations": [
			{"op": "projectile_speed_multiplier", "value": 0.75},
			{"op": "primary_hit_more", "value": 0.20},
			{"op": "mana_multiplier", "value": 1.15},
		],
	},
	"lingering_chill": {
		"name": "寒意延长辅助",
		"description": "冰霜与奥能新星：原减速时长×1.50，冰霜3秒至4.5秒，新星0.6秒至0.9秒。主命中伤害×0.90，魔力×1.10；新星范围、击退与冷却不变，伏击冻结最终时长。新星仍为普通减速，不受冰霜异常时长属性加成。",
		"skills": ["frost", "nova"], "requires": ["native_slow"], "family": "control",
		"operations": [
			{"op": "slow_duration_multiplier", "value": 1.50},
			{"op": "primary_hit_more", "value": -0.10},
			{"op": "mana_multiplier", "value": 1.10},
		],
	},
	"chain_extension": {
		"name": "连锁延展辅助",
		"description": "连锁闪电：总命中目标数 +2（5 至 7），每次主命中伤害总降 20%，魔力 ×1.30；逐次系数递减不变。",
		"skills": ["chain"], "requires": ["chain_hit"], "family": "chain",
		"operations": [
			{"op": "chain_extra_targets", "value": 2},
			{"op": "primary_hit_more", "value": -0.20},
			{"op": "mana_multiplier", "value": 1.30},
		],
	},
	"chain_reach": {
		"name": "远链辅助",
		"description": "连锁闪电：后续寻敌距离 ×1.30（220 至 286），主命中伤害总降 10%，魔力 ×1.15；首次寻敌距离仍为 600。",
		"skills": ["chain"], "requires": ["chain_hit"], "family": "chain",
		"operations": [
			{"op": "chain_followup_range_multiplier", "value": 1.30},
			{"op": "primary_hit_more", "value": -0.10},
			{"op": "mana_multiplier", "value": 1.15},
		],
	},
}


static func get_definition(id: String) -> Dictionary:
	if not SUPPORTS.has(id) or not definition_error(SUPPORTS[id]).is_empty():
		return {}
	return SUPPORTS[id].duplicate(true)


static func compile_program(skill_id: Variant, support_ids: Variant, slot_limit: int = Program.MAX_SUPPORTS) -> Dictionary:
	var error: String = Program.selection_error(skill_id, support_ids, SUPPORTS, slot_limit)
	if not error.is_empty():
		return Program.failure(error)
	# Preflight every owned definition and all selected capabilities before effects.
	for id: String in SUPPORTS:
		error = definition_error(SUPPORTS[id])
		if not error.is_empty():
			return Program.failure(error)
	var capabilities: Variant = Data.SKILLS[skill_id].get("capabilities")
	if not Program.strings(capabilities):
		return Program.failure("技能能力列表无效")
	for id: String in support_ids:
		for capability: String in SUPPORTS[id].requires:
			if not capabilities.has(capability):
				return Program.failure("技能缺少辅助所需能力")
	var canonical: Array = support_ids.duplicate()
	canonical.sort()
	var result: Dictionary = Program.empty()
	for id: String in canonical:
		for operation: Dictionary in SUPPORTS[id].operations:
			var amount: float = float(operation.value)
			match operation.op:
				"mana_multiplier":
					result.mana_multiplier *= amount
				"primary_hit_more":
					var modifier: Dictionary = Program.primary_modifier(id, skill_id, amount)
					if modifier.is_empty():
						return Program.failure("主命中伤害范围无效")
					result.modifiers.append(modifier)
				"chain_extra_targets":
					result.recipe_factors[operation.op] = int(result.recipe_factors.get(operation.op, 0)) + int(amount)
				_:
					result.recipe_factors[operation.op] = float(result.recipe_factors.get(operation.op, 1.0)) * amount
	return result


## Validate detached metadata without accepting unknown, repeated or no-op operations.
static func definition_error(value: Variant) -> String:
	if not value is Dictionary or value.size() != 6 or not value.has_all(["name", "description", "skills", "requires", "operations", "family"]):
		return "投射与连锁辅助元数据结构无效"
	if not value.name is String or value.name.is_empty() or not value.description is String or value.description.is_empty():
		return "辅助说明无效"
	if not value.family is String or value.family not in ["delivery", "control", "chain"]:
		return "辅助类别无效"
	if not Program.strings(value.skills) or not Program.strings(value.requires):
		return "辅助技能或能力列表无效"
	var requires: Array = ["chain_hit"] if value.family == "chain" else (["native_slow"] if value.family == "control" else ["projectile_hit"])
	if value.requires != requires:
		return "辅助技能或能力与类别不匹配"
	if not value.operations is Array or value.operations.size() < 2 or value.operations.size() > 3:
		return "辅助操作列表无效"
	var seen: Dictionary = {}
	var factor: String = ""
	for operation: Variant in value.operations:
		if not operation is Dictionary or operation.size() != 2 or not operation.has_all(["op", "value"]):
			return "辅助操作结构无效"
		if not operation.op is String or seen.has(operation.op) or not Program.number(operation.value):
			return "辅助操作重复或数值无效"
		var amount: float = float(operation.value)
		match operation.op:
			"mana_multiplier":
				if amount <= 1.0 or amount > 10.0:
					return "魔力倍率无效"
			"primary_hit_more":
				if amount <= -1.0 or amount > 1.0 or amount == 0.0:
					return "主命中倍率无效"
			"projectile_speed_multiplier":
				if value.family != "delivery" or amount < 0.25 or amount > 4.0 or amount == 1.0:
					return "投射物速度倍率无效"
			"slow_duration_multiplier":
				if value.family != "control" or amount <= 1.0 or amount > 4.0:
					return "减速时间倍率无效"
			"chain_extra_targets":
				if value.family != "chain" or amount < 1.0 or amount > 27.0 or amount != floorf(amount):
					return "连锁总目标增量无效"
			"chain_followup_range_multiplier":
				if value.family != "chain" or amount <= 1.0 or amount > 4.0:
					return "后续寻敌距离倍率无效"
			_:
				return "未知辅助操作"
		seen[operation.op] = amount
		if FACTORS.has(operation.op):
			if not factor.is_empty():
				return "单个辅助必须只有一种配方变换"
			factor = operation.op
	if factor.is_empty() or not seen.has("mana_multiplier"):
		return "辅助缺少配方变换或魔力代价"
	var fast: bool = factor == "projectile_speed_multiplier" and float(seen[factor]) > 1.0
	var skills: Array = ["chain"] if value.family == "chain" else (["frost", "nova"] if value.family == "control" else ["bolt", "frost", "shade_bolt"])
	if factor == "projectile_speed_multiplier": skills.append("tornado")
	if value.skills != skills:
		return "辅助技能与配方变换不匹配"
	if fast:
		if seen.has("primary_hit_more"):
			return "疾速投射不改变命中伤害"
	else:
		if not seen.has("primary_hit_more"):
			return "辅助缺少命中伤害取舍"
		if (factor == "projectile_speed_multiplier") != (float(seen.primary_hit_more) > 0.0):
			return "辅助命中伤害取舍方向无效"
	return ""
