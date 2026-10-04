class_name EncounterCompiler
extends RefCounted
## Pure post-MonsterCatalog transform. Call once before an enemy enters simulation.
const Catalog = preload("res://scripts/encounters/encounter_catalog.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const HitRules = preload("res://scripts/combat/attack_hit_rules.gd")
const SOURCE_FIELD: String = "encounter_source"


## Success: {ok, error, profile}. profile and all nested containers are read-only.
## Recompile from IDs when changing selection; never edit a compiled profile.
static func compile(ids: Variant) -> Dictionary:
	var error: String = Catalog.selection_error(ids)
	if not error.is_empty():
		return _failure(error)
	var canonical: Array[String] = []
	canonical.assign(ids)
	canonical.sort()
	var definitions: Array[Dictionary] = []
	var risks: Array[Dictionary] = []
	var multipliers: Dictionary = {"max_health": 1.0, "speed": 1.0,"damage":1.0,"attack_speed":1.0}
	var additions: Dictionary = {"shield_from_base_health":0.0,"armour":0.0}
	for id: String in canonical:
		var definition: Dictionary = Catalog.get_definition(id)
		definitions.append(definition)
		risks.append(definition.risk.duplicate(true))
		match definition.operation:
			"multiply": multipliers[definition.field] = definition.value
			"add_base_health_fraction": additions.shield_from_base_health = definition.value
			"add_flat": additions[definition.field] = definition.value
	var profile: Dictionary = {"modifier_ids": canonical, "source": Catalog.source_metadata(),
		"definitions": definitions, "multipliers": multipliers,"additions":additions, "risk_parameters": risks,
		"resource_policy": Catalog.resource_policy(), "reward_budget": Catalog.reward_budget_metadata()}
	_freeze(profile)
	return {"ok": true, "error": "", "profile": profile}


## Accept only a complete current catalog snapshot, including metadata and policy.
## This is an in-process contract, not a signature or a persistent save format.
static func profile_error(profile: Variant) -> String:
	if not profile is Dictionary:
		return "挑战配置必须为已编译字典"
	var expected: Dictionary = compile(profile.get("modifier_ids"))
	if not expected.ok:
		return str(expected.error)
	if profile != expected.profile:
		return "挑战配置来源、版本、参数或政策不匹配；请从 ID 重新编译"
	return ""


## Success: {ok, error, enemy}. Only the explicitly authored actor fields and
## SOURCE_FIELD can change. Every formula reads canonical inputs, not prior mods.
## The original enemy and profile are never mutated, including on failure.
static func apply_to_enemy(canonical_enemy: Variant, profile: Variant) -> Dictionary:
	var error: String = profile_error(profile)
	if not error.is_empty():
		return _failure(error)
	error = _enemy_error(canonical_enemy)
	if not error.is_empty():
		return _failure(error)
	var enemy: Dictionary = canonical_enemy.duplicate(true)
	var life_multiplier: float = float(profile.multipliers.max_health)
	var speed_multiplier: float = float(profile.multipliers.speed)
	if life_multiplier != 1.0:
		enemy.max_health = float(canonical_enemy.max_health) * life_multiplier
		# Scale both values by the same factor; no ratio refill or resurrection.
		enemy.health = float(canonical_enemy.health) * life_multiplier
	if speed_multiplier != 1.0:
		enemy.speed = float(canonical_enemy.speed) * speed_multiplier
	for field:String in ["damage","attack_speed"]:
		if float(profile.multipliers[field])!=1.0:enemy[field]=float(canonical_enemy[field])*float(profile.multipliers[field])
	var shield_bonus:float=float(canonical_enemy.max_health)*float(profile.additions.shield_from_base_health)
	if shield_bonus!=0.0:
		enemy.max_shield=float(canonical_enemy.max_shield)+shield_bonus
		enemy.shield=float(canonical_enemy.shield)+shield_bonus
	var base_armour:float=float(canonical_enemy.get("armour",HitRules.monster_profile(int(canonical_enemy.kind)).armour))
	if float(profile.additions.armour)!=0.0:enemy.armour=base_armour+float(profile.additions.armour)
	for field: String in ["max_health", "health", "speed","max_shield","shield","damage","attack_speed"]:
		if not _nonnegative(enemy[field]):
			return _failure("挑战应用后数值溢出")
	if not _nonnegative(enemy.get("armour",base_armour)):return _failure("挑战护甲无效")
	var source: Dictionary = {"profile": profile.duplicate(true),
		"enemy_id": canonical_enemy.id, "template_id": canonical_enemy.template_id,
		"rarity": canonical_enemy.rarity, "wave": canonical_enemy.wave,
		"mechanism_schema": canonical_enemy.mechanism_schema,
		"mechanism_revision": canonical_enemy.mechanism_revision,
		"mechanism_policy": canonical_enemy.mechanism_policy,
		"before": {"health": canonical_enemy.health, "max_health": canonical_enemy.max_health,
			"shield": canonical_enemy.shield, "max_shield": canonical_enemy.max_shield,
			"speed": canonical_enemy.speed,"damage":canonical_enemy.damage,"attack_speed":canonical_enemy.attack_speed,"armour":base_armour},
		"shield_bonus":shield_bonus}
	_freeze(source)
	enemy[SOURCE_FIELD] = source
	return {"ok": true, "error": "", "enemy": enemy}


static func _enemy_error(enemy: Variant) -> String:
	if not enemy is Dictionary:
		return "怪物必须为 MonsterCatalog 生成的字典"
	# Any marker value rejects, even null, {}, a different profile or an empty selection.
	if enemy.has(SOURCE_FIELD):
		return "怪物已应用遭遇配置；必须从标准怪物重新生成"
	if not enemy.has_all(["id", "template_id", "kind", "rarity", "wave", "health", "max_health",
		"shield", "max_shield", "speed","damage","attack_speed", "mechanism_schema", "mechanism_revision", "mechanism_policy",
		"root_id", "generation", "reward_eligible", "death_processed"]):
		return "怪物缺少标准来源或资源字段"
	if not enemy.id is int or enemy.id <= 0 or not enemy.wave is int or enemy.wave < 1:
		return "怪物身份或波次无效"
	if not enemy.template_id is String or not Monsters.TEMPLATES.has(enemy.template_id):
		return "未知怪物模板"
	if not enemy.rarity is String or not Monsters.RARITIES.has(enemy.rarity) or enemy.rarity == "reserved":
		return "未知或预留怪物稀有度"
	var template: Dictionary = Monsters.TEMPLATES[enemy.template_id]
	if enemy.kind != template.kind or (enemy.rarity == "boss") != (template.rarity == "boss"):
		return "怪物模板物种或首领稀有度不匹配"
	if not enemy.mechanism_schema is int or enemy.mechanism_schema != Monsters.Registry.SCHEMA_VERSION \
		or not enemy.mechanism_revision is int or enemy.mechanism_revision < 1 \
		or not enemy.mechanism_policy is String or enemy.mechanism_policy.is_empty():
		return "怪物机制来源版本无效"
	if not enemy.root_id is int or enemy.root_id <= 0 or not enemy.generation is int or enemy.generation < 0 \
		or not enemy.reward_eligible is bool or not enemy.death_processed is bool:
		return "怪物谱系或奖励标记无效"
	for field: String in ["health", "max_health", "shield", "max_shield", "speed","damage","attack_speed"]:
		if not _nonnegative(enemy[field]):
			return "怪物资源必须为有限非负数值"
	if enemy.has("armour") and not _nonnegative(enemy.armour):return "怪物原始护甲必须有限非负"
	if float(enemy.max_health) <= 0.0 or float(enemy.health) > float(enemy.max_health) \
		or float(enemy.shield) > float(enemy.max_shield):
		return "怪物生命或护盾超出上限"
	return ""


static func _nonnegative(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0


static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for entry: Variant in value.values():
			_freeze(entry)
		value.make_read_only()
	elif value is Array:
		for entry: Variant in value:
			_freeze(entry)
		value.make_read_only()


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
