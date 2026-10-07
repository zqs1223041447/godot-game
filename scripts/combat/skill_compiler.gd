class_name SkillCompiler
extends RefCounted
## Pure cast compilation. The same detached result drives execution and previews.
const Data = preload("res://scripts/game_data.gd")
const Recipes = preload("res://scripts/combat/combat_data.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Extension = preload("res://scripts/combat/projectile_support_rules.gd")
const Ambush = preload("res://scripts/combat/ambush_support_rules.gd")
const InwardPull = preload("res://scripts/combat/inward_pull_support_rules.gd")
const EncirclingCleave = preload("res://scripts/combat/encircling_cleave_support_rules.gd")
const LongStride = preload("res://scripts/combat/long_stride_support_rules.gd")
const Area = preload("res://scripts/combat/area_support_rules.gd")
const Critical=preload("res://scripts/combat/critical_strike_rules.gd")
const Resolute = preload("res://scripts/combat/resolute_technique_rules.gd")
const Precise = preload("res://scripts/combat/precise_technique_rules.gd")
const Burn=preload("res://scripts/combat/burn_rules.gd")
const FrostLock = preload("res://scripts/combat/frost_lock_rules.gd")
const ColdDuration = preload("res://scripts/combat/cold_ailment_duration_rules.gd")
const Shock = preload("res://scripts/combat/shock_rules.gd")
const Ember=preload("res://scripts/combat/ember_proliferation_support_rules.gd")
const Proliferation=preload("res://scripts/combat/ember_proliferation_rules.gd")
const Leech=preload("res://scripts/combat/leech_rules.gd")
const ResourceCost=preload("res://scripts/combat/source_resource_rules.gd")
const Spatial = preload("res://scripts/combat/source_spatial_rules.gd")
const BaseCompiler = preload("res://scripts/combat/damage_base_compiler.gd")
const Conversion = preload("res://scripts/combat/physical_fire_conversion_rules.gd")
const Penetration = preload("res://scripts/combat/hit_penetration_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Weapon = preload("res://scripts/items/weapon_local_rules.gd")
const MAX_INITIAL_PROJECTILES: int = 9
const MAX_CHAIN_TARGETS: int = 8


static func compile_group(skill_id: String, snapshot: Dictionary, support_ids: Array) -> Dictionary:
	return compile_skill(skill_id, snapshot, support_ids, Supports.GROUP_MAX_SUPPORTS)


static func compile_skill(skill_id: String, snapshot: Dictionary, support_ids: Array, slot_limit: int = Supports.MAX_SUPPORTS) -> Dictionary:
	var error: String = Supports.compatibility_reason(skill_id, support_ids, slot_limit)
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
	elif skill_id in ["nova", "meteor", "chain", "cleave"]:
		error = _hit_recipe_error(skill.get("hit_recipe"), skill_id == "chain")
		if not error.is_empty():
			return _failure(error)
	if skill_id == "chain":
		var targeting: Variant = skill.get("targeting_recipe")
		if not targeting is Dictionary or targeting.size() != 2 or not _number(targeting.get("first_range")) or not _number(targeting.get("followup_range")):
			return _failure("连锁寻敌配方无效")
		recipe = {"hit": skill.hit_recipe.duplicate(true), "first_range": float(targeting.first_range), "followup_range": float(targeting.followup_range)}
	var canonical: Array[String] = []
	for id: String in support_ids:
		canonical.append(id)
	canonical.sort()
	var compiled_snapshot: Dictionary = snapshot.duplicate(true)
	if compiled_snapshot.has(Resolute.STAT) and not Resolute.active(compiled_snapshot):
		compiled_snapshot.erase(Resolute.STAT)
	if compiled_snapshot.has(ColdDuration.STAT) and float(compiled_snapshot[ColdDuration.STAT]) == 0.0:
		compiled_snapshot.erase(ColdDuration.STAT)
	var mana: float = float(skill.mana)
	var has_extension: bool = false
	# Compatibility validates every definition before this execution stage.
	for id: String in canonical:
		if Area.SUPPORTS.has(id) or Supports.is_program_support(id):
			continue
		if Extension.SUPPORTS.has(id):
			has_extension = true
			continue
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
	if skill.capabilities.has("initial_projectiles"):
		initial_count = clampi(initial_count, 1, MAX_INITIAL_PROJECTILES)
		recipe.initial_count = initial_count
		compiled_snapshot.initial_count = initial_count
	if has_extension:
		var extension: Dictionary = Extension.compile_extension(skill_id, recipe, Supports.select_owned(canonical, Extension.SUPPORTS))
		if not extension.error.is_empty():
			return _failure(extension.error)
		recipe = extension.recipe
		compiled_snapshot.modifiers.append_array(extension.modifiers)
		mana *= float(extension.mana_multiplier)
	if skill_id in Area.RECIPE_SKILLS:
		var area: Dictionary = Area.compile_area(skill_id, skill.get("area_recipe"), Supports.select_owned(canonical, Area.SUPPORTS))
		if not area.error.is_empty():
			return _failure(area.error)
		recipe = area.recipe
		if skill_id == "cleave":
			if not _number(skill.get("half_angle")) or float(skill.half_angle) <= 0.0 or float(skill.half_angle) > PI: return _failure("近战扇区角度无效")
			recipe.half_angle = float(skill.half_angle)
			if canonical.has("encircling_cleave"):
				recipe.half_angle = deg_to_rad(float(EncirclingCleave.POLICY.arc_degrees) / 2.0)
		compiled_snapshot.modifiers.append_array(area.modifiers)
		mana *= float(area.mana_multiplier)
	var program: Dictionary = Supports.compile_programs(skill_id, canonical, slot_limit)
	if not program.error.is_empty(): return _failure(program.error)
	compiled_snapshot.modifiers.append_array(program.modifiers)
	mana *= float(program.mana_multiplier)
	var cooldown: float = float(skill.cooldown) * float(program.cooldown_multiplier)
	var factors: Dictionary = program.recipe_factors
	if skill_id in ["bolt", "frost", "shade_bolt"]:
		recipe.speed *= float(factors.get("projectile_speed_multiplier", 1.0))
		recipe.slow *= float(factors.get("slow_duration_multiplier", 1.0))
		# The source grant lengthens existing frost chill after its support factor.
		# Nova's generic area slow is not a cold ailment and never enters this path.
		if skill_id == "frost" and compiled_snapshot.has(ColdDuration.STAT):
			var cold_duration: Dictionary = ColdDuration.duration(recipe.slow, compiled_snapshot[ColdDuration.STAT])
			if not cold_duration.ok: return _failure(cold_duration.reason)
			recipe.slow = cold_duration.duration
		if not _number(recipe.speed) or float(recipe.speed) <= 0.0 or float(recipe.speed) > 3000.0 or not _number(recipe.slow) or float(recipe.slow) < 0.0 or float(recipe.slow) > 15.0:
			return _failure("编译后的速度或减速时长无效")
	if skill_id == "chain":
		recipe.hit.bounce_count += int(factors.get("chain_extra_targets", 0))
		recipe.followup_range *= float(factors.get("chain_followup_range_multiplier", 1.0))
		error = _hit_recipe_error(recipe.hit, true)
		if not error.is_empty(): return _failure(error)
		if int(recipe.hit.bounce_count) > MAX_CHAIN_TARGETS or not _number(recipe.first_range) or not _number(recipe.followup_range) or float(recipe.first_range) <= 0.0 or float(recipe.first_range) > 1000.0 or float(recipe.followup_range) <= 0.0 or float(recipe.followup_range) > 1000.0:
			return _failure("编译后的连锁目标或距离无效")
	if not is_finite(cooldown) or cooldown <= 0.0: return _failure("编译后的冷却无效")
	if not is_finite(mana):
		return _failure("编译后的魔力消耗无效")
	var resource:Dictionary=ResourceCost.apply(mana,compiled_snapshot)
	if not resource.ok:return _failure(resource.error)
	mana=resource.mana
	var base_speed:float=float(skill.get("projectile_recipe",{}).get("speed",0.0))
	var spatial:Dictionary=Spatial.apply(skill_id,recipe,compiled_snapshot,base_speed)
	if not spatial.error.is_empty():return _failure(spatial.error)
	recipe=spatial.recipe;compiled_snapshot=spatial.snapshot
	var packets: Dictionary = _compile_packets(skill_id, compiled_snapshot, recipe)
	if not skill_id in ["dash", "ward"] and packets.is_empty():
		return _failure("命中伤害组装无效")
	var critical:Dictionary=Critical.compile(compiled_snapshot,_primary_tags(packets),packets.has("secondary"))
	if not critical.ok:return _failure(critical.error)
	if not critical.critical.is_empty():compiled_snapshot.critical=critical.critical.duplicate(true)
	var leech:Dictionary=Leech.compile(compiled_snapshot,_primary_tags(packets))
	if not leech.ok:return _failure(leech.error)
	if not leech.leech.is_empty():compiled_snapshot.leech=leech.leech.duplicate(true)
	compiled_snapshot.compiled_skill_id = skill_id
	compiled_snapshot.compiled_packets = packets.duplicate(true)
	var result:Dictionary={"ok": true, "error": "", "skill_id": skill_id,
		"snapshot": compiled_snapshot, "mana": mana, "cooldown": cooldown,
		"initial_count": initial_count, "recipe": recipe, "support_ids": canonical, "packets": packets}
	if not critical.critical.is_empty():result.critical=critical.critical.duplicate(true)
	if not leech.leech.is_empty():result.leech=leech.leech.duplicate(true)
	if not resource.factors.is_empty():result.cost_factors=resource.factors
	if canonical.has("ignite"):
		# This policy belongs only to primary hits. Preview resolves the same
		# post-support, noncritical fire amount once; ticks never resolve again.
		compiled_snapshot.burn_policy=Burn.PLAYER_POLICY.duplicate(true)
		var profile:Dictionary=Burn.PLAYER_POLICY.duplicate(true)
		profile.enabled=true;profile.stacking="strongest_refresh_equal";profile.roles={}
		if compiled_snapshot.has("burn_faster"):
			profile.burn_faster=compiled_snapshot.burn_faster;profile.base_duration=profile.duration
			profile.duration=Burn.burn_duration(float(profile.base_duration),float(profile.burn_faster))
			if not is_finite(profile.duration) or float(profile.duration)<=0.0:return _failure("加速燃烧时长超出有限范围")
		for role:String in (["parent","child"] if skill_id=="tornado" else ["direct"]):
			var resolved:Dictionary=Damage.resolve(packets[role],compiled_snapshot.modifiers)
			var fire:float=float(resolved.components.get("fire",0.0))
			var dps:float=Burn.raw_fire_dps(fire,float(profile.rate_fraction),float(compiled_snapshot.get("fire_dot_multiplier",0.0)),float(compiled_snapshot.get("burn_faster",0.0)))
			if not is_finite(dps) or not is_finite(dps*float(profile.duration)):return _failure("点燃伤害超出有限数值范围")
			profile.roles[role]={"fire_before_defense":fire,"dps":dps,"total":dps*float(profile.duration)}
		if compiled_snapshot.has("fire_dot_multiplier"):profile.fire_dot_multiplier=compiled_snapshot.fire_dot_multiplier
		result.burn_profile=profile
	elif canonical.has("ember_proliferation"):
		compiled_snapshot.burn_policy=Ember.POLICY.duplicate(true)
		compiled_snapshot.burn_proliferation=Proliferation.POLICY.duplicate(true)
		var profile:Dictionary=Ember.POLICY.duplicate(true)
		profile.enabled=true;profile.stacking="strongest_refresh_equal";profile.roles={}
		if compiled_snapshot.has("burn_faster"):
			profile.burn_faster=compiled_snapshot.burn_faster;profile.base_duration=profile.duration
			profile.duration=Burn.burn_duration(float(profile.base_duration),float(profile.burn_faster))
			if not is_finite(profile.duration) or float(profile.duration)<=0.0:return _failure("加速燃烧时长超出有限范围")
		for role:String in (["parent","child"] if skill_id=="tornado" else ["direct"]):
			var resolved:Dictionary=Damage.resolve(packets[role],compiled_snapshot.modifiers)
			var fire:float=float(resolved.components.get("fire",0.0))
			var dps:float=Burn.raw_fire_dps(fire,float(profile.rate_fraction),float(compiled_snapshot.get("fire_dot_multiplier",0.0)),float(compiled_snapshot.get("burn_faster",0.0)))
			if not is_finite(dps) or not is_finite(dps*float(profile.duration)):return _failure("余烬扩散伤害超出有限数值范围")
			profile.roles[role]={"fire_before_defense":fire,"dps":dps,"total":dps*float(profile.duration)}
		profile.proliferation=Proliferation.POLICY.duplicate(true)
		if compiled_snapshot.has("fire_dot_multiplier"):profile.fire_dot_multiplier=compiled_snapshot.fire_dot_multiplier
		result.burn_profile=profile
	if canonical.has("frost_lock"):
		compiled_snapshot.freeze_policy = FrostLock.PLAYER_POLICY.duplicate(true)
		if compiled_snapshot.has(ColdDuration.STAT):
			compiled_snapshot.freeze_policy = FrostLock.derived_policy(compiled_snapshot[ColdDuration.STAT])
			if compiled_snapshot.freeze_policy.is_empty(): return _failure("霜锁策略无效")
		var profile: Dictionary = compiled_snapshot.freeze_policy.duplicate(true)
		profile.enabled = true
		result.freeze_profile = profile
	if canonical.has("shock"):
		compiled_snapshot.shock_policy = Shock.PLAYER_POLICY.duplicate(true)
		var profile: Dictionary = Shock.PLAYER_POLICY.duplicate(true)
		profile.enabled = true
		profile.trigger = "positive_lightning_hit_after_settlement"
		profile.affects_hits_only = true
		profile.affects_dot = false
		profile.applies_after_current_hit = true
		profile.stacking = "refresh_equal"
		profile.roles = ["projectile"] if skill_id == "bolt" else ["bounce"] if skill_id == "chain" else ["direct"]
		result.shock_profile = profile
	if canonical.has("ambush"):
		var trap_profile: Dictionary = {"enabled": true}
		trap_profile.merge(Ambush.POLICY.duplicate(true))
		result.trap_profile = trap_profile
	if canonical.has("inward_pull"):
		var impulse_profile: Dictionary = {"enabled": true}
		impulse_profile.merge(InwardPull.POLICY.duplicate(true))
		compiled_snapshot.area_impulse_policy = impulse_profile.duplicate(true)
		result.area_impulse_profile = impulse_profile
	if canonical.has("encircling_cleave"):
		var profile: Dictionary = EncirclingCleave.POLICY.duplicate(true)
		profile.radius = float(recipe.radius)
		result.encircling_cleave_profile = profile
	if canonical.has("long_stride"):
		result.long_stride_profile = LongStride.POLICY.duplicate(true)
	_append_conversion_profile(result, packets, compiled_snapshot)
	_append_penetration_profile(result, packets, compiled_snapshot)
	var hit_policy: Dictionary = Resolute.compiled_profile(compiled_snapshot)
	if not hit_policy.is_empty():result.hit_policy = hit_policy
	_append_precise_profile(result)
	return result


static func compile_basic(snapshot:Dictionary)->Dictionary:
	var reason:=_snapshot_error(snapshot)
	if not reason.is_empty():return _failure(reason)
	if Recipes.is_basic_melee_snapshot(snapshot):return _compile_basic_melee(snapshot)
	var spatial:=Spatial.apply("basic",{"speed":640.0},snapshot,640.0)
	if not spatial.error.is_empty():return _failure(spatial.error)
	var frozen:Dictionary=spatial.snapshot
	if frozen.has(Resolute.STAT) and not Resolute.active(frozen):frozen.erase(Resolute.STAT)
	var packet:Dictionary=Recipes.event_packet(frozen,"basic","projectile")
	var secondary:Dictionary=Recipes.secondary_packet(frozen,"basic")
	if packet.is_empty() or secondary.is_empty():return _failure("普通攻击伤害组装无效")
	var critical:Dictionary=Critical.compile(frozen,packet.tags,true)
	if not critical.ok:return _failure(critical.error)
	if not critical.critical.is_empty():frozen.critical=critical.critical.duplicate(true)
	var leech:Dictionary=Leech.compile(frozen,packet.tags)
	if not leech.ok:return _failure(leech.error)
	if not leech.leech.is_empty():frozen.leech=leech.leech.duplicate(true)
	frozen.compiled_skill_id="basic"
	frozen.compiled_packets={"projectile":packet.duplicate(true),"secondary":secondary}
	var result:Dictionary={"ok":true,"error":"","skill_id":"basic","recipe":spatial.recipe,"snapshot":frozen,"packets":frozen.compiled_packets.duplicate(true)}
	if not critical.critical.is_empty():result.critical=critical.critical.duplicate(true)
	if not leech.leech.is_empty():result.leech=leech.leech.duplicate(true)
	_append_conversion_profile(result, result.packets, frozen)
	_append_penetration_profile(result, result.packets, frozen)
	var hit_policy: Dictionary = Resolute.compiled_profile(frozen)
	if not hit_policy.is_empty():result.hit_policy = hit_policy
	_append_precise_profile(result)
	return result


## This delivery has fixed reach, no projectile/area scaling and no secondary.
## Input validation still runs in compile_basic before selecting the branch.
static func _compile_basic_melee(snapshot: Dictionary) -> Dictionary:
	var frozen: Dictionary = snapshot.duplicate(true)
	if frozen.has(Resolute.STAT) and not Resolute.active(frozen):frozen.erase(Resolute.STAT)
	var packet: Dictionary = Recipes.event_packet(frozen, "basic", "direct")
	if packet.is_empty():return _failure("普通近战攻击伤害组装无效")
	var critical: Dictionary = Critical.compile(frozen, packet.tags, false)
	if not critical.ok:return _failure(critical.error)
	if not critical.critical.is_empty():frozen.critical = critical.critical.duplicate(true)
	var leech: Dictionary = Leech.compile(frozen, packet.tags)
	if not leech.ok:return _failure(leech.error)
	if not leech.leech.is_empty():frozen.leech = leech.leech.duplicate(true)
	frozen.compiled_skill_id = "basic"
	frozen.compiled_packets = {"direct": packet.duplicate(true)}
	var result: Dictionary = {"ok": true, "error": "", "skill_id": "basic", "recipe": Recipes.BASIC_MELEE.duplicate(true),
		"snapshot": frozen, "packets": frozen.compiled_packets.duplicate(true)}
	if not critical.critical.is_empty():result.critical = critical.critical.duplicate(true)
	if not leech.leech.is_empty():result.leech = leech.leech.duplicate(true)
	_append_conversion_profile(result, result.packets, frozen)
	_append_penetration_profile(result, result.packets, frozen)
	var hit_policy: Dictionary = Resolute.compiled_profile(frozen)
	if not hit_policy.is_empty():result.hit_policy = hit_policy
	_append_precise_profile(result)
	return result


static func _primary_tags(packets:Dictionary)->Array:
	for role:String in ["parent","projectile","direct"]:
		if packets.has(role):return packets[role].tags
	if not packets.get("bounces",[]).is_empty():return packets.bounces[0].tags
	return []


static func _compile_packets(skill_id: String, snapshot: Dictionary, recipe: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var roles: Array[String] = []
	match skill_id:
		"tornado": roles.assign(["parent", "child", "secondary"])
		"bolt", "frost", "shade_bolt": roles.assign(["projectile", "secondary"])
		"nova", "meteor", "cleave": roles.assign(["direct"])
		"chain":
			var bounces: Array[Dictionary] = []
			for index: int in range(int(recipe.hit.bounce_count)):
				var packet: Dictionary = Recipes.chain_packet(snapshot, recipe.hit, index)
				if packet.is_empty():
					return {}
				bounces.append(packet)
			result.bounces = bounces
	for role: String in roles:
		var packet: Dictionary = Recipes.event_packet(snapshot, skill_id, role)
		if packet.is_empty():
			return {}
		result[role] = packet
	return result


static func _hit_recipe_error(recipe: Variant, chain: bool) -> String:
	var keys: Array[String] = ["base_coefficient", "added_effectiveness", "damage_type"]
	if chain:
		keys.append_array(["bounce_count", "base_coefficient_loss_per_bounce", "added_effectiveness_loss_per_bounce"])
	if not recipe is Dictionary or recipe.size() != keys.size() or not recipe.has_all(keys):
		return "直接命中配方结构无效"
	if not _nonnegative(recipe.base_coefficient) or not _nonnegative(recipe.added_effectiveness) or not recipe.damage_type is String or not Damage.TYPES.has(recipe.damage_type):
		return "直接命中配方数值无效"
	if chain:
		if not Recipes._valid_chain_recipe(recipe):
			return "连锁命中配方无效"
		var last: int = int(recipe.bounce_count) - 1
		if float(recipe.base_coefficient) - last * float(recipe.base_coefficient_loss_per_bounce) < 0.0 or float(recipe.added_effectiveness) - last * float(recipe.added_effectiveness_loss_per_bounce) < 0.0:
			return "连锁命中倍率不可为负"
	return ""


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}


static func _snapshot_error(snapshot: Dictionary) -> String:
	if snapshot.has("long_stride_profile"):
		return "施放快照已编译；必须从基础构筑快照重新编译"
	if snapshot.has("encircling_cleave_profile"):
		return "施放快照已编译；必须从基础构筑快照重新编译"
	# initial_count is reserved for compiled projectile snapshots, including empty supports.
	# Reject re-entry instead of applying support more factors a second time.
	if snapshot.has("initial_count") or snapshot.has("compiled_packets") or snapshot.has("compiled_skill_id") or snapshot.has("critical") or snapshot.has("critical_roll") or snapshot.has("leech") or snapshot.has("burn_policy") or snapshot.has("burn_proliferation") or snapshot.has("shock_policy") or snapshot.has("hit_policy") or snapshot.has("area_impulse_policy") or snapshot.has("area_impulse_profile") or snapshot.has("conversion_profile") or snapshot.has("precise_technique_profile") or snapshot.has("freeze_policy") or snapshot.has("freeze_profile") or snapshot.has("penetration_profile"):
		return "施放快照已编译；必须从基础构筑快照重新编译"
	var conversion_error: String = Conversion.snapshot_error(snapshot)
	if not conversion_error.is_empty(): return conversion_error
	var penetration_error: String = Penetration.snapshot_error(snapshot)
	if not penetration_error.is_empty(): return penetration_error
	var dot_error:String=Burn.snapshot_multiplier_error(snapshot)
	if not dot_error.is_empty():return dot_error
	var critical_error:String=Critical.error(snapshot)
	if not critical_error.is_empty():return critical_error
	var leech_error:String=Leech.error(snapshot)
	if not leech_error.is_empty():return leech_error
	var spatial_error:=Spatial.error(snapshot)
	if not spatial_error.is_empty():return spatial_error
	var resource_error:String=ResourceCost.error(snapshot)
	if not resource_error.is_empty():return resource_error
	if not snapshot.has_all(["base_damage", "modifiers", "effects", "projectile_count", "tornado_recipe", "explosion_recipe", "added_damage"]):
		return "施放快照缺少必要字段"
	if not _nonnegative(snapshot.base_damage) or not _integer(snapshot.projectile_count, -1000000, 1000000):
		return "施放快照基础数值无效"
	if snapshot.has("accuracy") and not _nonnegative(snapshot.accuracy): return "施放快照命中值无效"
	if snapshot.has("weapon_profile") and snapshot.weapon_profile is Dictionary and snapshot.weapon_profile.is_empty():
		return "施放快照的武器局部配置不可为空"
	var weapon_error: String = Weapon.profile_error(snapshot.get("weapon_profile", {}))
	if not weapon_error.is_empty():
		return weapon_error
	var additions_error: String = BaseCompiler.additions_error(snapshot.added_damage)
	if not additions_error.is_empty():
		return additions_error
	var sources_error: String = BaseCompiler.sources_error(snapshot.get("added_damage_sources", []))
	if not sources_error.is_empty():
		return sources_error
	if not snapshot.modifiers is Array or not snapshot.effects is Array:
		return "施放快照效果或修饰器无效"
	for effect: Variant in snapshot.effects:
		if not effect is String or not Recipes.EFFECTS.has(effect):
			return "施放快照含未支持的装备效果"
	for modifier: Variant in snapshot.modifiers:
		if not modifier is Dictionary or not modifier.get("mode") in ["increased", "more"] or not _number(modifier.get("value")):
			return "施放快照伤害修饰器无效"
		for field: Variant in modifier:
			if not field in ["id", "mode", "value", "all_tags", "skills", "damage_types"]:
				return "施放快照伤害修饰器含未知字段"
		# Also catch support-bearing snapshots whose compiled count was removed.
		if str(modifier.get("id", "")).begins_with("support:"):
			return "施放快照含已编译辅助；必须从基础构筑快照重新编译"
		for key: String in ["all_tags", "skills", "damage_types"]:
			if not Supports._string_array(modifier.get(key, [])):
				return "施放快照伤害作用域无效"
		for tag: String in modifier.get("all_tags", []):
			if not BaseCompiler.TAGS.has(tag):
				return "施放快照伤害标签无效"
		for id: String in modifier.get("skills", []):
			if id != "basic" and not Data.SKILLS.has(id):
				return "施放快照伤害技能作用域无效"
		for type: String in modifier.get("damage_types", []):
			if not Damage.TYPES.has(type):
				return "施放快照伤害类型无效"
	var error: String = _tornado_error(snapshot.tornado_recipe)
	if not error.is_empty():
		return error
	var explosion: Variant = snapshot.explosion_recipe
	if not explosion is Dictionary or explosion.size() != 3 or not _nonnegative(explosion.get("coefficient")) or not _nonnegative(explosion.get("radius")) or not _nonnegative(explosion.get("added_effectiveness")) or float(explosion.added_effectiveness) != 0.0:
		return "独立爆炸配方无效"
	var resolute_error: String = Resolute.snapshot_error(snapshot)
	if not resolute_error.is_empty(): return resolute_error
	var precise_error: String = Precise.snapshot_error(snapshot)
	if not precise_error.is_empty(): return precise_error
	return ColdDuration.snapshot_error(snapshot)


static func _projectile_recipe_error(recipe: Variant) -> String:
	if not recipe is Dictionary or recipe.size() != 8 or not recipe.has_all(["initial_count", "spread", "coefficient", "pierce", "slow", "speed", "damage_type", "added_effectiveness"]):
		return "投射物配方结构无效"
	if not _integer(recipe.initial_count, 1, MAX_INITIAL_PROJECTILES) or not _integer(recipe.pierce, -1, 100):
		return "投射物数量或穿透无效"
	for key: String in ["spread", "coefficient", "added_effectiveness", "slow", "speed"]:
		if not _nonnegative(recipe[key]):
			return "投射物配方数值无效"
	if float(recipe.speed) <= 0.0 or not recipe.damage_type is String or not Damage.TYPES.has(recipe.damage_type):
		return "投射物速度或伤害类型无效"
	return ""


static func _tornado_error(recipe: Variant) -> String:
	if not recipe is Dictionary or recipe.size() != 6 or not recipe.has_all(["parent_count", "child_count", "spread", "parent", "child", "explosion"]):
		return "龙卷配方结构无效"
	if not _integer(recipe.parent_count, 1, MAX_INITIAL_PROJECTILES) or not _integer(recipe.child_count, 1, MAX_INITIAL_PROJECTILES) or not _nonnegative(recipe.spread):
		return "龙卷数量或间距无效"
	for role: String in ["parent", "child"]:
		var spec: Variant = recipe[role]
		if not spec is Dictionary or spec.size() != 9 or not spec.has_all(["speed", "range", "lifetime", "coefficient", "pierce", "radius", "role", "split", "added_effectiveness"]):
			return "龙卷载体配方无效"
		for key: String in ["speed", "range", "lifetime", "coefficient", "added_effectiveness", "radius"]:
			if not _nonnegative(spec[key]):
				return "龙卷载体数值无效"
		if float(spec.speed) <= 0.0 or not _integer(spec.pierce, -1, 100) or spec.role != role or not spec.split is bool:
			return "龙卷载体行为无效"
	if not recipe.explosion is Dictionary or recipe.explosion.size() != 3 or not _nonnegative(recipe.explosion.get("coefficient")) or not _nonnegative(recipe.explosion.get("radius")) or not _nonnegative(recipe.explosion.get("added_effectiveness")) or float(recipe.explosion.added_effectiveness) != 0.0:
		return "龙卷爆炸配方无效"
	return ""


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _nonnegative(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _append_conversion_profile(result: Dictionary, packets: Dictionary, snapshot: Dictionary) -> void:
	for value: Variant in packets.values():
		if value is Dictionary and value.has("conversion"):
			result.conversion_profile = Conversion.profile_from_snapshot(snapshot)
			return
		if value is Array:
			for packet: Dictionary in value:
				if packet.has("conversion"):
					result.conversion_profile = Conversion.profile_from_snapshot(snapshot)
					return
	# A zero source or hit set without physical points needs no frozen policy.
	for field: String in Conversion.STATS.values():
		if snapshot.has(field): snapshot.erase(field)


static func _append_penetration_profile(result: Dictionary, packets: Dictionary, snapshot: Dictionary) -> void:
	if not snapshot.has("hit_penetration"): return
	var fractions: Dictionary = {}
	for value: Variant in packets.values():
		var candidates: Array = value if value is Array else [value]
		for packet: Variant in candidates:
			if not packet is Dictionary: continue
			for type: String in ["cold", "lightning"]:
				if packet.get("penetration", {}).has(type):
					fractions[type] = packet.penetration[type]
	if fractions.is_empty():
		snapshot.erase("hit_penetration")
		return
	result.penetration_profile = Penetration.profile_from_snapshot({"hit_penetration":fractions})


static func _append_precise_profile(result: Dictionary) -> void:
	var snapshot: Dictionary = result.snapshot
	if not Precise.active(snapshot): return
	var profile: Dictionary = Precise.profile(snapshot)
	profile.attack_applies = bool(profile.condition_met) and _primary_tags(result.packets).has("attack")
	result.precise_technique_profile = profile
	# Resolute still owns the cannot-be-evaded flag. Precise alone only bans crit.
	if not result.has("hit_policy"):
		result.hit_policy = {"id":"precise_technique", "hits_cannot_be_evaded":false,
			"cannot_deal_critical_strikes":true}
