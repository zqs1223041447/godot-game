class_name SkillCompiler
extends RefCounted
## Pure cast compilation. The same detached result drives execution and previews.
const Data = preload("res://scripts/game_data.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
const Supports = preload("res://scripts/combat/support_catalog.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const MAX_INITIAL_PROJECTILES: int = 9


static func compile_skill(skill_id: String, snapshot: Dictionary, support_ids: Array) -> Dictionary:
	var error: String = Supports.compatibility_reason(skill_id, support_ids)
	if not error.is_empty():
		return _failure(error)
	error = _snapshot_error(snapshot)
	if not error.is_empty():
		return _failure(error)
	var skill: Dictionary = Data.SKILLS[skill_id]
	if not _nonnegative(skill.get("mana")) or not _nonnegative(skill.get("cooldown")):
		return _failure("技能消耗或冷却元数据无效")
	var recipe: Dictionary = {}
	var initial_count: int = 0
	if skill_id == "tornado":
		recipe = snapshot.tornado_recipe.duplicate(true)
		error = _tornado_error(recipe)
		if not error.is_empty():
			return _failure(error)
		initial_count = int(recipe.parent_count) + int(snapshot.projectile_count)
	elif skill.capabilities.has("initial_projectiles"):
		error = _projectile_recipe_error(skill.get("projectile_recipe"))
		if not error.is_empty():
			return _failure(error)
		recipe = skill.projectile_recipe.duplicate(true)
		# Equipment's arrow bonus is tornado-only, never a spell projectile bonus.
		initial_count = int(recipe.initial_count)
	elif skill.capabilities.has("projectile_hit"):
		return _failure("投射物技能缺少已支持的发射配方")
	var canonical: Array[String] = []
	for id: String in support_ids:
		canonical.append(id)
	canonical.sort()
	var compiled_snapshot: Dictionary = snapshot.duplicate(true)
	var mana: float = float(skill.mana)
	# Compatibility validates every definition before this execution stage.
	for id: String in canonical:
		var definition: Dictionary = Supports.get_definition(id)
		if definition.is_empty():
			return _failure("辅助元数据无效")
		for operation: Dictionary in definition.operations:
			match operation.op:
				"add_initial_projectiles":
					initial_count += int(operation.value)
				"projectile_hit_more":
					compiled_snapshot.modifiers.append({"id": "support:" + id,
						"mode": "more", "value": float(operation.value),
						"all_tags": ["hit", "projectile"], "skills": [skill_id], "damage_types": []})
				"mana_multiplier":
					mana *= float(operation.value)
				_:
					return _failure("辅助操作未受支持")
	if not recipe.is_empty():
		initial_count = clampi(initial_count, 1, MAX_INITIAL_PROJECTILES)
		recipe.initial_count = initial_count
		compiled_snapshot.initial_count = initial_count
	if not is_finite(mana):
		return _failure("编译后的魔力消耗无效")
	return {"ok": true, "error": "", "skill_id": skill_id,
		"snapshot": compiled_snapshot, "mana": mana, "cooldown": float(skill.cooldown),
		"initial_count": initial_count, "recipe": recipe, "support_ids": canonical}


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}


static func _snapshot_error(snapshot: Dictionary) -> String:
	# initial_count is reserved for compiled projectile snapshots, including empty supports.
	# Reject re-entry instead of applying support more factors a second time.
	if snapshot.has("initial_count"):
		return "施放快照已编译；必须从基础构筑快照重新编译"
	if not snapshot.has_all(["base_damage", "modifiers", "effects", "projectile_count", "tornado_recipe", "explosion_recipe"]):
		return "施放快照缺少必要字段"
	if not _nonnegative(snapshot.base_damage) or not _integer(snapshot.projectile_count, -1000000, 1000000):
		return "施放快照基础数值无效"
	if not snapshot.modifiers is Array or not snapshot.effects is Array:
		return "施放快照效果或修饰器无效"
	for effect: Variant in snapshot.effects:
		if not effect is String or not Recipes.EFFECTS.has(effect):
			return "施放快照含未支持的装备效果"
	for modifier: Variant in snapshot.modifiers:
		if not modifier is Dictionary or not modifier.get("mode") in ["increased", "more"] or not _number(modifier.get("value")):
			return "施放快照伤害修饰器无效"
		# Also catch support-bearing snapshots whose compiled count was removed.
		if str(modifier.get("id", "")).begins_with("support:"):
			return "施放快照含已编译辅助；必须从基础构筑快照重新编译"
		for key: String in ["all_tags", "skills", "damage_types"]:
			if not Supports._string_array(modifier.get(key, [])):
				return "施放快照伤害作用域无效"
		for type: String in modifier.get("damage_types", []):
			if not Damage.TYPES.has(type):
				return "施放快照伤害类型无效"
	var error: String = _tornado_error(snapshot.tornado_recipe)
	if not error.is_empty():
		return error
	var explosion: Variant = snapshot.explosion_recipe
	if not explosion is Dictionary or not _nonnegative(explosion.get("coefficient")) or not _nonnegative(explosion.get("radius")):
		return "独立爆炸配方无效"
	return ""


static func _projectile_recipe_error(recipe: Variant) -> String:
	if not recipe is Dictionary or recipe.size() != 7 or not recipe.has_all(["initial_count", "spread", "coefficient", "pierce", "slow", "speed", "damage_type"]):
		return "投射物配方结构无效"
	if not _integer(recipe.initial_count, 1, MAX_INITIAL_PROJECTILES) or not _integer(recipe.pierce, -1, 100):
		return "投射物数量或穿透无效"
	for key: String in ["spread", "coefficient", "slow", "speed"]:
		if not _nonnegative(recipe[key]):
			return "投射物配方数值无效"
	if float(recipe.speed) <= 0.0 or not recipe.damage_type is String or not Damage.TYPES.has(recipe.damage_type):
		return "投射物速度或伤害类型无效"
	return ""


static func _tornado_error(recipe: Variant) -> String:
	if not recipe is Dictionary or not recipe.has_all(["parent_count", "child_count", "spread", "parent", "child", "explosion"]):
		return "龙卷配方结构无效"
	if not _integer(recipe.parent_count, 1, MAX_INITIAL_PROJECTILES) or not _integer(recipe.child_count, 1, MAX_INITIAL_PROJECTILES) or not _nonnegative(recipe.spread):
		return "龙卷数量或间距无效"
	for role: String in ["parent", "child"]:
		var spec: Variant = recipe[role]
		if not spec is Dictionary or not spec.has_all(["speed", "range", "lifetime", "coefficient", "pierce", "radius", "role", "split"]):
			return "龙卷载体配方无效"
		for key: String in ["speed", "range", "lifetime", "coefficient", "radius"]:
			if not _nonnegative(spec[key]):
				return "龙卷载体数值无效"
		if float(spec.speed) <= 0.0 or not _integer(spec.pierce, -1, 100) or spec.role != role or not spec.split is bool:
			return "龙卷载体行为无效"
	if not recipe.explosion is Dictionary or not _nonnegative(recipe.explosion.get("coefficient")) or not _nonnegative(recipe.explosion.get("radius")):
		return "龙卷爆炸配方无效"
	return ""


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _nonnegative(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum
