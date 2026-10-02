class_name MonsterCatalog
extends RefCounted
## Species, rarity, and stateful death templates are orthogonal to shared talents.
const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const SCHEMA_VERSION: int = 1
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
	"brute": {"name": "重壳体", "kind": 2, "rarity": "normal", "mechanisms": [], "death_spawns": []},
	"splitter": {"name": "裂殖巡游体", "kind": 0, "rarity": "magic", "mechanisms": ["grove_vitality"],
		"death_spawns": [{"template": "crawler", "count": 2}, {"template": "skitter", "count": 1}]},
	"brood_host": {"name": "孵化重壳体", "kind": 2, "rarity": "rare", "mechanisms": ["grove_mastery", "aegis_recovery"],
		"death_spawns": [{"template": "splitter", "count": 2}]},
	"rift_warden": {"name": "裂隙守卫", "kind": 2, "rarity": "boss", "mechanisms": ["ember_mastery", "aegis_mastery"],
		"death_spawns": [{"template": "crawler", "count": 4}]},
}

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
		var rarity: String = str(entry.get("rarity", ""))
		if not RARITIES.has(rarity) or rarity == "reserved":
			errors.append("%s: 未知/预留稀有度" % id)
		if not entry.get("kind") is int or int(entry.kind) < 0 or int(entry.kind) >= SPECIES.size():
			errors.append("%s: 物种无效" % id)
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
	return {"id": id, "template_id": template_id, "name": template.get("name", template_id), "kind": kind,
		"rarity": rarity, "mechanism_ids": resolved.mechanism_ids.duplicate(),
		"mechanism_schema": resolved.schema_version, "mechanism_revision": resolved.definition_revision, "mechanism_policy": resolved.policy_version, "mechanism_stats": modifiers.duplicate(),
		"pos": position, "health": hp, "max_health": hp, "shield": maximum_shield, "max_shield": maximum_shield,
		"shield_regen": float(modifiers.get("shield_regen", 0.0)), "damage_delay": 0.0,
		"speed": float(species.speed) + mini(wave, 15) * 1.4 + float(modifiers.get("move_speed", 0.0)),
		"damage": (float(species.damage) + (wave - 1) * 0.7) * float(tier.damage) + float(modifiers.get("damage", 0.0)),
		"attack_speed": 1.0 / 0.85 + float(modifiers.get("attack_speed", 0.0)),
		"radius": float(species.radius) * (1.25 if rarity == "boss" else 1.0), "attack_timer": 0.5,
		"slow": 0.0, "flash": 0.0, "spawn": 0.6, "knockback": Vector2.ZERO,
		"death_spawns": template.get("death_spawns", []).duplicate(true), "death_processed": false,
		"root_id": id, "generation": 0, "wave": wave, "reward_eligible": true,
		"xp_reward": (6 if kind == 2 else 3) * int(tier.xp)}

static func mechanism_text(enemy: Dictionary) -> String:
	var labels: PackedStringArray = []
	for id: String in enemy.get("mechanism_ids", []):
		labels.append(str(Registry.get_definition(id).get("name", id)))
	if not enemy.get("death_spawns", []).is_empty():
		labels.append("死亡分裂")
	return " · ".join(labels) if not labels.is_empty() else "无额外机制"
