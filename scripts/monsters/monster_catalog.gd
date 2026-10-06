class_name MonsterCatalog
extends RefCounted
## Species, rarity, and stateful death templates are orthogonal to shared talents.
const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Burn=preload("res://scripts/combat/burn_rules.gd")
const Shock=preload("res://scripts/combat/shock_rules.gd")
const TelegraphProfiles = preload("res://scripts/monsters/telegraph_profiles.gd")
const MapBossAttacks=preload("res://scripts/monsters/map_boss_profiles.gd")
const SCHEMA_VERSION: int = 1
const BASE_ATTACK_SPEED: float = 1.0 / 0.85
## Authored ordinary encounter budget. Final evasion enters the same
## AttackHitRules admission used for player talent-derived accuracy/evasion.
const MIST_SKITTER_POLICY: Dictionary = {
	"evasion": 1600.0, "health_multiplier": 0.80, "damage_multiplier": 0.85,
}
const TELEGRAPH_TEMPLATES: Dictionary = {
	"ember_guard": {"trigger_distance": 150.0},
	"frost_guard": {"trigger_distance": 150.0},
	"storm_skitter": {"trigger_distance": 140.0},
}
const ELEMENTAL_ENCOUNTERS: Dictionary = {
	"frost_guard": {"source_template": "brute", "minimum_wave": 4, "admission_modulus": 8, "admission_remainder": 4, "element": "cold"},
	"storm_skitter": {"source_template": "skitter", "minimum_wave": 5, "admission_modulus": 8, "admission_remainder": 6, "element": "lightning"},
}
const FIRE_ENCOUNTER: Dictionary = {
	"template_id": "ember_guard", "minimum_wave": 3, "ordinary_admission_interval": 8,
	"reward_pool": "defense", "reward_rarity": "rare", "reward_count": 1,
	"reward_rule": "eligible_original_death_once", "balance_source": "original_game_balance",
}
const ORDINARY_RARITIES: Array[String] = ["normal", "magic", "rare"]
const RARITIES: Dictionary = {
	"normal": {"name": "白 · 普通", "color": Color("e1e7ef"), "health": 1.0, "damage": 1.0, "xp": 1, "affixes": 0},
	"magic": {"name": "蓝 · 魔法", "color": Color("6cafff"), "health": 1.55, "damage": 1.10, "xp": 2, "affixes": 1},
	"rare": {"name": "金 · 稀有", "color": Color("f3cb66"), "health": 2.5, "damage": 1.20, "xp": 4, "affixes": 2},
	"boss": {"name": "橙 · 首领", "color": Color("ff9854"), "health": 4.0, "damage": 1.40, "xp": 8, "affixes": 2},
	"reserved": {"name": "黑 · 预留", "color": Color("474a56"), "health": 1.0, "damage": 1.0, "xp": 0, "affixes": 0},
}
const SPECIES: Array[Dictionary] = [
	{"name": "巡游体", "health": 38.0, "speed": 64.0, "damage": 10.0, "radius": 14.0},
	{"name": "掠行体", "health": 25.0, "speed": 103.0, "damage": 8.0, "radius": 10.0},
	{"name": "重壳体", "health": 95.0, "speed": 43.0, "damage": 18.0, "radius": 22.0},
]
const AFFIX_POOL: Array[String] = ["ember_power", "gale_stride", "grove_vitality", "aegis_capacity", "aegis_recovery"]
const TEMPLATES: Dictionary = {
	"crawler": {"name": "巡游体", "kind": 0, "rarity": "normal", "mechanisms": [], "death_spawns": []},
	"skitter": {"name": "掠行体", "kind": 1, "rarity": "normal", "mechanisms": [], "death_spawns": []},
	"mist_skitter": {"name": "雾羽掠行体", "kind": 1, "rarity": "normal", "mechanisms": [], "death_spawns": []},
	"brute": {"name": "重壳体", "kind": 2, "rarity": "normal", "mechanisms": [], "death_spawns": []},
	"splitter": {"name": "裂殖巡游体", "kind": 0, "rarity": "magic", "mechanisms": ["grove_vitality"],
		"death_spawns": [{"template": "crawler", "count": 2}, {"template": "skitter", "count": 1}]},
	"brood_host": {"name": "孵化重壳体", "kind": 2, "rarity": "rare", "mechanisms": ["grove_mastery", "aegis_recovery"],
		"death_spawns": [{"template": "splitter", "count": 2}]},
	"rift_warden": {"name": "裂隙守卫", "kind": 2, "rarity": "boss", "mechanisms": ["ember_mastery", "aegis_mastery"],
		"death_spawns": [{"template": "crawler", "count": 4}]},
	"frost_guard": {"name": "霜纹守卫", "kind": 2, "rarity": "normal", "mechanisms": [], "death_spawns": [], "contact_weights": {"cold": 1.0}},
	"storm_skitter": {"name": "雷纹掠行体", "kind": 1, "rarity": "normal", "mechanisms": [], "death_spawns": [], "contact_weights": {"lightning": 1.0}},
	"ember_guard": {"name": "灰烬守卫", "kind": 2, "rarity": "rare", "mechanisms": [], "death_spawns": [],
		"defense_stats": {"fire_resistance": 0.25}, "contact_weights": {"physical": 0.5, "fire": 0.5},
		"equipment_pool": "defense"},
}

static func fire_encounter_policy() -> Dictionary:
	return FIRE_ENCOUNTER.duplicate(true)


static func encounter_for_admission(wave: int, admission: int) -> String:
	if wave >= int(FIRE_ENCOUNTER.minimum_wave) and admission > 0 and admission % int(FIRE_ENCOUNTER.ordinary_admission_interval) == 0:
		return str(FIRE_ENCOUNTER.template_id)
	return ""


static func elemental_encounter_policy() -> Dictionary:
	return {"rules": ELEMENTAL_ENCOUNTERS.duplicate(true), "selection": "after_original_ordinary_roll",
		"preserves": ["kind", "rarity", "mechanisms", "health", "damage", "speed", "xp", "reward_eligibility"],
		"extra_rewards": false, "extra_rng": false, "balance_source": "original_game_balance"}


static func elemental_template_for_roll(wave: int, admission: int, roll: Dictionary) -> String:
	if admission <= 0 or roll.get("rarity", "") not in ORDINARY_RARITIES:
		return ""
	for id: String in ELEMENTAL_ENCOUNTERS:
		var policy: Dictionary = ELEMENTAL_ENCOUNTERS[id]
		if wave >= int(policy.minimum_wave) and roll.get("template", "") == policy.source_template and admission % int(policy.admission_modulus) == int(policy.admission_remainder):
			return id
	return ""


static func contact_components(enemy: Dictionary) -> Dictionary:
	var components: Dictionary = {}
	var weights: Dictionary = enemy.get("contact_weights", {"physical": 1.0})
	for type: String in weights:
		components[type] = float(enemy.get("damage", 0.0)) * float(weights[type])
	return components


static func uses_telegraph(enemy:Dictionary)->bool:
	# Invalid attached metadata cannot silently fall back to contact damage.
	return TELEGRAPH_TEMPLATES.has(str(enemy.get("template_id",""))) or enemy.has("map_boss_attack_id")


static func telegraph_policy(enemy: Dictionary) -> Dictionary:
	# The guard replaces contact attacks with an explicit locked-ground action.
	# Attack speed shortens recovery, never the readable warning. All defaults
	# and legal limits still come from the reviewed runtime's profile authority.
	var id: String = str(enemy.get("template_id", ""))
	var map_rule:Dictionary=MapBossAttacks.for_enemy(enemy) if enemy.has("map_boss_attack_id") else {}
	if enemy.has("map_boss_attack_id") and map_rule.is_empty():return {}
	if not TELEGRAPH_TEMPLATES.has(id) and map_rule.is_empty():
		return {}
	var speed: Variant = enemy.get("attack_speed", BASE_ATTACK_SPEED)
	if typeof(speed) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(speed)) or float(speed) <= 0.0:
		return {}
	var base: Dictionary = TelegraphProfiles.resolve(map_rule.profile if not map_rule.is_empty() else TelegraphProfiles.ELEMENTAL.get(id, {})).profile
	var recovery: float = float(base.recovery_seconds) * BASE_ATTACK_SPEED / maxf(0.2, float(speed))
	recovery = clampf(recovery, float(TelegraphProfiles.LIMITS.recovery_seconds.minimum), float(TelegraphProfiles.LIMITS.recovery_seconds.maximum))
	base.recovery_seconds = recovery
	var checked: Dictionary = TelegraphProfiles.resolve(base)
	if not checked.ok:
		return {}
	var policy:Dictionary={"profile_id": TelegraphProfiles.PROFILE_ID, "profile": checked.profile,
		"trigger_distance": float(map_rule.trigger_distance if not map_rule.is_empty() else TELEGRAPH_TEMPLATES[id].trigger_distance),
		"replaces_contact": true, "hold_pursuit_during_action": true,
		"recovery_scaling": "base_attack_speed_divided_by_current_attack_speed",
		"minimum_attack_speed": 0.2, "base_attack_speed": BASE_ATTACK_SPEED}
	if id=="ember_guard" and map_rule.is_empty():
		policy.burn_policy=Burn.ENEMY_POLICY.duplicate(true);policy.visual_pattern="ember_burn";policy.name="余烬锁点重击"
	if id=="storm_skitter" and map_rule.is_empty():
		policy.shock_policy=Shock.ENEMY_POLICY.duplicate(true);policy.visual_pattern="storm_shock";policy.name="雷纹锁点震击"
	if not map_rule.is_empty():
		policy.target_rule=map_rule.target_rule;policy.visual_pattern=map_rule.id;policy.name=map_rule.name
	return policy

static func ordinary_roll(rng: RandomNumberGenerator, wave: int) -> Dictionary:
	var kind: int = 0
	var roll: float = rng.randf()
	if roll > 0.8 and wave >= 2:
		kind = 2
	elif roll > 0.58:
		kind = 1
	var special: float = rng.randf()
	if wave >= 3 and special < 0.06:
		return {"template": "brood_host", "rarity": "rare", "mechanisms": TEMPLATES.brood_host.mechanisms.duplicate()}
	if special < 0.18:
		return {"template": "splitter", "rarity": "magic", "mechanisms": TEMPLATES.splitter.mechanisms.duplicate()}
	var rarity: String = "normal"
	var rarity_roll: float = rng.randf()
	if wave >= 2 and rarity_roll < 0.08:
		rarity = "rare"
	elif rarity_roll < 0.30:
		rarity = "magic"
	var affixes: Array[String] = []
	var pool: Array[String] = AFFIX_POOL.duplicate()
	for index: int in range(int(RARITIES[rarity].affixes)):
		var selected: int = rng.randi_range(0, pool.size() - 1)
		affixes.append(pool[selected])
		pool.remove_at(selected)
	return {"template": ["crawler", "skitter", "brute"][kind], "rarity": rarity, "mechanisms": affixes}

static func validate_templates(templates: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if templates.size() > 256 or templates.is_empty():
		errors.append("模板数量必须为 1—256")
		return errors
	for id: Variant in templates:
		if not id is String or not templates[id] is Dictionary:
			errors.append("模板标识/数据格式错误")
			continue
		var entry: Dictionary = templates[id]
		if id == "mist_skitter" and entry != TEMPLATES.mist_skitter:
			errors.append("雾羽模板必须保留普通掠行体的完整来源")
		var rarity: String = str(entry.get("rarity", ""))
		if not RARITIES.has(rarity) or rarity == "reserved":
			errors.append("%s: 未知/预留稀有度" % id)
		if not entry.get("kind") is int or int(entry.kind) < 0 or int(entry.kind) >= SPECIES.size():
			errors.append("%s: 物种无效" % id)
		var defense: Dictionary = Defense.defense_profile(entry.get("defense_stats", {}), "monster")
		if not defense.ok:
			errors.append("%s: 防御定义无效: %s" % [id, defense.reason])
		var weights: Variant = entry.get("contact_weights", {"physical": 1.0})
		var validated_weights: Dictionary = Defense.validate_components(weights)
		if not validated_weights.ok:
			errors.append("%s: 接触伤害分量无效: %s" % [id, validated_weights.reason])
		else:
			if not is_equal_approx(float(validated_weights.total), 1.0):
				errors.append("%s: 接触伤害分量权重总和必须为 1" % id)
		if entry.get("equipment_pool", "") not in ["", "defense"]:
			errors.append("%s: 未实现的装备奖励池" % id)
		if not entry.get("mechanisms", []) is Array:
			errors.append("%s: 机制列表无效" % id)
		else:
			var resolved: Dictionary = Registry.resolve_grants(entry.get("mechanisms", []), "monster")
			if not resolved.ok:
				errors.append("%s: %s" % [id, "; ".join(resolved.errors)])
			if RARITIES.has(rarity) and entry.get("mechanisms", []).size() > int(RARITIES[rarity].affixes):
				errors.append("%s: 机制数量超出稀有度上限" % id)
		var children: Variant = entry.get("death_spawns", [])
		if not children is Array:
			errors.append("%s: 生成列表无效" % id)
			continue
		var total: int = 0
		for child: Variant in children:
			if not child is Dictionary or not child.get("count") is int or int(child.get("count", 0)) < 1 or int(child.get("count", 0)) > 6:
				errors.append("%s: 子怪数量必须为 1—6 整数" % id)
				continue
			total += int(child.count)
			var target: String = str(child.get("template", ""))
			if target == "mist_skitter":
				errors.append("雾羽不进入死亡后代模板")
			if not templates.has(target) or not templates[target] is Dictionary:
				errors.append("%s: 缺失子怪模板 %s" % [id, target])
			elif str(templates[target].get("rarity", "")) not in ORDINARY_RARITIES:
				errors.append("%s: 子怪不能为首领/预留" % id)
		if total > 6:
			errors.append("%s: 单次死亡超过 6 子怪" % id)
	if not errors.is_empty():
		return errors
	var visiting: Dictionary = {}
	var visited: Dictionary = {}
	for id: String in templates:
		if _has_cycle(id, templates, visiting, visited):
			errors.append("死亡模板存在直接或间接循环: " + id)
			break
	return errors

static func _has_cycle(id: String, templates: Dictionary, visiting: Dictionary, visited: Dictionary) -> bool:
	if visiting.has(id):
		return true
	if visited.has(id):
		return false
	visiting[id] = true
	for child: Dictionary in templates[id].get("death_spawns", []):
		if _has_cycle(str(child.template), templates, visiting, visited):
			return true
	visiting.erase(id)
	visited[id] = true
	return false

static func make_enemy(id: int, template_id: String, wave: int, position: Vector2, context: String = "ordinary",
		rarity_override: String = "", mechanisms_override: Array = [], templates: Dictionary = TEMPLATES) -> Dictionary:
	if not validate_templates(templates).is_empty():
		return {}
	if not templates.has(template_id) or id <= 0 or wave < 1 or not position.is_finite():
		return {}
	var template: Dictionary = templates[template_id]
	var base_rarity: String = str(template.get("rarity", ""))
	var rarity: String = base_rarity if rarity_override.is_empty() else rarity_override
	if not RARITIES.has(rarity) or rarity == "reserved":
		return {}
	if base_rarity == "boss" or rarity == "boss":
		if base_rarity != "boss" or rarity != "boss" or context not in ["level_boss", "map_boss"]:
			return {}
	elif context not in ["ordinary", "death_child", "demo"]:
		return {}
	var mechanisms: Array = template.get("mechanisms", []) if rarity_override.is_empty() else mechanisms_override
	if template_id == "mist_skitter" and (context != "ordinary" or rarity != "normal" or not mechanisms.is_empty()):
		return {}
	if mechanisms.size() > int(RARITIES[rarity].affixes):
		return {}
	var resolved: Dictionary = Registry.resolve_grants(mechanisms, "monster")
	if not resolved.ok:
		return {}
	var kind: int = int(template.kind)
	if kind < 0 or kind >= SPECIES.size():
		return {}
	var species: Dictionary = SPECIES[kind]
	var tier: Dictionary = RARITIES[rarity]
	var modifiers: Dictionary = resolved.stats
	var hp: float = float(species.health) * (1.0 + (wave - 1) * 0.16) * float(tier.health) + float(modifiers.get("max_health", 0.0))
	var maximum_shield: float = float(modifiers.get("max_shield", 0.0))
	var defense: Dictionary = Defense.defense_profile(template.get("defense_stats", {}), "monster")
	var recharge:=Defense.recharge_profile(modifiers,"monster")
	if not recharge.ok:return {}
	var result:Dictionary={"id": id, "template_id": template_id, "name": template.get("name", template_id), "kind": kind,
		"rarity": rarity, "mechanism_ids": resolved.mechanism_ids.duplicate(),
		"mechanism_schema": resolved.schema_version, "mechanism_revision": resolved.definition_revision, "mechanism_policy": resolved.policy_version, "mechanism_stats": modifiers.duplicate(),
		"pos": position, "health": hp, "max_health": hp, "shield": maximum_shield, "max_shield": maximum_shield,
		"shield_regen": float(modifiers.get("shield_regen", 0.0)), "damage_delay": 0.0,
		"defense_stats": template.get("defense_stats", {}).duplicate(true), "resistances": defense.effective_resistances,
		"contact_weights": template.get("contact_weights", {"physical": 1.0}).duplicate(true),
		"equipment_pool": template.get("equipment_pool", ""),
		"speed": float(species.speed) + mini(wave, 15) * 1.4 + float(modifiers.get("move_speed", 0.0)),
		"damage": (float(species.damage) + (wave - 1) * 0.7) * float(tier.damage) + float(modifiers.get("damage", 0.0)),
		"attack_speed": BASE_ATTACK_SPEED + float(modifiers.get("attack_speed", 0.0)),
		"radius": float(species.radius) * (1.25 if rarity == "boss" else 1.0), "attack_timer": 0.5,
		"slow": 0.0, "flash": 0.0, "spawn": 0.6, "knockback": Vector2.ZERO,
		"death_spawns": template.get("death_spawns", []).duplicate(true), "death_processed": false,
		"root_id": id, "generation": 0, "wave": wave, "reward_eligible": true,
		"xp_reward": (6 if kind == 2 else 3) * int(tier.xp)}
	if float(modifiers.get("shield_recharge_rate_increased",0.0))!=0.0 or float(modifiers.get("shield_recharge_start_faster",0.0))!=0.0:
		result.shield_recharge_rate=recharge.rate;result.shield_recharge_delay=recharge.delay
	if template_id == "mist_skitter":
		result.health *= float(MIST_SKITTER_POLICY.health_multiplier)
		result.max_health *= float(MIST_SKITTER_POLICY.health_multiplier)
		result.damage *= float(MIST_SKITTER_POLICY.damage_multiplier)
		result.evasion = float(MIST_SKITTER_POLICY.evasion)
	return result

static func mechanism_text(enemy: Dictionary) -> String:
	var labels: PackedStringArray = []
	if enemy.get("template_id", "") == "mist_skitter":
		labels.append("高闪避·较脆")
	var telegraph: Dictionary = telegraph_policy(enemy)
	if not telegraph.is_empty():
		labels.append("%s %.1f秒 · 范围 %.0f" % [telegraph.get("name","锁点重击"),telegraph.profile.windup_seconds, telegraph.profile.radius])
		if telegraph.has("burn_policy"):labels.append("火焰一半立即结算，另一半分3秒燃烧；单目标不叠加")
	for id: String in enemy.get("mechanism_ids", []):
		labels.append(str(Registry.get_definition(id).get("name", id)))
	if not enemy.get("death_spawns", []).is_empty():
		labels.append("死亡分裂")
	var resistance_label := resistance_text(enemy)
	if not resistance_label.is_empty(): labels.append(resistance_label)
	if float(enemy.get("contact_weights", {}).get("fire", 0.0)) > 0.0:
		labels.append(("重击含 %.0f%% 火焰" if not telegraph.is_empty() else "接触含 %.0f%% 火焰") % (float(enemy.contact_weights.fire) * 100.0))
	for element: String in ["cold", "lightning"]:
		if float(enemy.get("contact_weights", {}).get(element, 0.0)) > 0.0:
			labels.append("冰冷预警攻击" if element == "cold" else "闪电预警攻击")
	return " · ".join(labels) if not labels.is_empty() else "无额外机制"


static func resistance_text(enemy: Dictionary, compact: bool = false) -> String:
	# Runtime resistances are already effective/capped by the defense resolver.
	# Never display the raw map bonus as if it were the final resistance.
	var values: Dictionary = enemy.get("resistances",{})
	var names := {"fire":"火抗","cold":"冰抗","lightning":"电抗"}
	var labels := PackedStringArray()
	for element: String in ["fire","cold","lightning"]:
		var value: float = float(values.get(element,0.0))
		if not is_zero_approx(value):
			labels.append("%s%s%d%%" % [names[element],"" if compact else " ",roundi(value*100.0)])
	return " · ".join(labels)
