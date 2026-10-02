class_name DamageBaseCompiler
extends RefCounted
## Assemble raw typed hit points only. Increased/more and current target defenses
## remain exclusively in DamageResolver. Local weapon points are resolved first;
## the authored intrinsic distribution never converts the weapon contribution.
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Weapon = preload("res://scripts/items/weapon_local_rules.gd")
const STAGE: String = "hit_base"
const SCOPES: Array[String] = ["attack", "spell"]
const TAGS: Array[String] = ["hit", "attack", "spell", "projectile", "area", "secondary", "explosion", "chain"]
const SOURCE_STATS: Dictionary = {
	"attack_added_physical": ["attack", "physical"], "attack_added_fire": ["attack", "fire"],
	"spell_added_cold": ["spell", "cold"], "spell_added_lightning": ["spell", "lightning"],
}
const ROLES: Array[String] = ["direct", "projectile", "parent", "child", "secondary", "bounce"]


static func assemble(base_damage: Variant, recipe: Variant, added_damage: Variant = {}, added_damage_sources: Variant = [], weapon_profile: Variant = {}) -> Dictionary:
	if not _nonnegative(base_damage) or not recipe_error(recipe).is_empty() or not additions_error(added_damage).is_empty() or not sources_error(added_damage_sources).is_empty():
		return {}
	var weapon: Dictionary = Weapon.resolve(weapon_profile)
	if not weapon.ok:
		return {}
	var weapon_trace: Dictionary = {}
	if not weapon.profile.is_empty() and _weapon_consumer(recipe.skill_id, recipe.role, recipe.tags):
		var contribution: float = float(weapon.components.physical) * float(recipe.base_coefficient)
		if not is_finite(contribution):
			return {}
		weapon_trace = {"profile": weapon.profile, "components": weapon.components,
			"coefficient": float(recipe.base_coefficient), "contribution": {"physical": contribution}}
	var scope: String = ""
	if recipe.tags.has("attack"):
		scope = "attack"
	elif recipe.tags.has("spell"):
		scope = "spell"
	var additions: Dictionary = added_damage.get(scope, {})
	var intrinsic: Dictionary = {}
	var added: Dictionary = {}
	var raw: Dictionary = {}
	for type: String in Damage.TYPES:
		var intrinsic_value: float = float(base_damage) * float(recipe.intrinsic_distribution.get(type, 0.0)) * float(recipe.base_coefficient)
		var added_value: float = float(additions.get(type, 0.0)) * float(recipe.added_effectiveness)
		var amount: float = intrinsic_value + added_value
		var weapon_value: float = float(weapon_trace.get("contribution", {}).get(type, 0.0))
		if not weapon_trace.is_empty():
			amount += weapon_value
		if not is_finite(amount):
			return {}
		if intrinsic_value > 0.0:
			intrinsic[type] = intrinsic_value
		if added_value > 0.0:
			added[type] = added_value
		# Retain authored zero components for legacy packet readers.
		if recipe.intrinsic_distribution.has(type) or added_value > 0.0 or weapon_value > 0.0:
			raw[type] = amount
	var packet: Dictionary = Damage.packet(raw, recipe.tags, recipe.skill_id)
	packet.role = recipe.role
	packet.assembly = {"stage": STAGE, "intrinsic": intrinsic, "added": added,
		"base_coefficient": float(recipe.base_coefficient), "added_effectiveness": float(recipe.added_effectiveness)}
	var applicable_sources: Array[Dictionary] = []
	if float(recipe.added_effectiveness) > 0.0:
		for source: Dictionary in added_damage_sources:
			if source.scope == scope:
				applicable_sources.append(source.duplicate(true))
	if not applicable_sources.is_empty():
		packet.assembly.added_damage_sources = applicable_sources
	if not weapon_trace.is_empty():
		packet.assembly.weapon = weapon_trace
	return packet


static func recipe_error(recipe: Variant) -> String:
	if not recipe is Dictionary or recipe.size() != 7 or not recipe.has_all(["stage", "intrinsic_distribution", "base_coefficient", "added_effectiveness", "tags", "skill_id", "role"]):
		return "基础伤害配方结构无效"
	if recipe.stage != STAGE or not _nonnegative(recipe.base_coefficient) or not _nonnegative(recipe.added_effectiveness):
		return "基础伤害阶段或倍率无效"
	if not recipe.skill_id is String or recipe.skill_id.is_empty() or not recipe.role is String or not ROLES.has(recipe.role):
		return "基础伤害来源无效"
	if not _typed_points(recipe.intrinsic_distribution) or recipe.intrinsic_distribution.is_empty():
		return "固有伤害类型分布无效"
	var total: float = 0.0
	for value: Variant in recipe.intrinsic_distribution.values():
		total += float(value)
	if not is_finite(total) or not is_equal_approx(total, 1.0):
		return "固有伤害类型分布必须合计为一"
	return _event_error(recipe.tags, recipe.role, float(recipe.added_effectiveness))


static func additions_error(value: Variant) -> String:
	if not value is Dictionary:
		return "附加伤害必须按攻击与法术分组"
	for scope: Variant in value:
		if not scope is String or not SCOPES.has(scope) or not _typed_points(value[scope]):
			return "附加伤害作用域、类型或点数无效"
	return ""


## Provenance never adds points a second time; the numeric scope map is authoritative.
static func sources_error(value: Variant) -> String:
	if not value is Array:
		return "附加伤害来源必须是数组"
	for source: Variant in value:
		if not source is Dictionary or source.size() != 6 or not source.has_all(["item_id", "affix_id", "stat", "scope", "damage_type", "value"]):
			return "附加伤害来源结构无效"
		for key: String in ["item_id", "affix_id", "stat", "scope", "damage_type"]:
			if not source[key] is String or source[key].is_empty():
				return "附加伤害来源标识无效"
		if not SOURCE_STATS.has(source.stat) or not _nonnegative(source.value):
			return "附加伤害来源词缀或点数无效"
		if SOURCE_STATS[source.stat] != [source.scope, source.damage_type]:
			return "附加伤害来源作用域与词缀不一致"
	return ""


static func packet_error(packet: Variant) -> String:
	if not packet is Dictionary or packet.size() != 5 or not packet.has_all(["base", "tags", "skill_id", "role", "assembly"]):
		return "冻结伤害包结构无效"
	if not _typed_points(packet.base) or not packet.skill_id is String or packet.skill_id.is_empty() or not packet.role is String or not ROLES.has(packet.role):
		return "冻结伤害包来源或点数无效"
	var trace: Variant = packet.assembly
	if not trace is Dictionary:
		return "冻结伤害阶段缺失"
	var expected_keys: Array[String] = ["stage", "intrinsic", "added", "base_coefficient", "added_effectiveness"]
	for optional: String in ["added_damage_sources", "weapon"]:
		if trace.has(optional):
			expected_keys.append(optional)
	if trace.size() != expected_keys.size() or not trace.has_all(expected_keys):
		return "冻结伤害阶段缺失"
	if trace.stage != STAGE or not _typed_points(trace.intrinsic) or not _typed_points(trace.added) or not _nonnegative(trace.base_coefficient) or not _nonnegative(trace.added_effectiveness):
		return "冻结伤害阶段无效"
	if not sources_error(trace.get("added_damage_sources", [])).is_empty():
		return "冻结伤害来源无效"
	for source: Dictionary in trace.get("added_damage_sources", []):
		if float(trace.added_effectiveness) == 0.0 or not packet.tags is Array or not packet.tags.has(source.scope):
			return "冻结伤害来源不匹配实际命中"
	if trace.has("weapon"):
		var weapon_error: String = _weapon_trace_error(trace.weapon, packet, trace.base_coefficient)
		if not weapon_error.is_empty():
			return weapon_error
	for type: String in Damage.TYPES:
		var summed: float = float(trace.intrinsic.get(type, 0.0)) + float(trace.added.get(type, 0.0))
		if trace.has("weapon"):
			summed += float(trace.weapon.contribution.get(type, 0.0))
		var matches: bool = float(packet.base.get(type, 0.0)) == summed if trace.has("weapon") else is_equal_approx(float(packet.base.get(type, 0.0)), summed)
		if not is_finite(summed) or not matches:
			return "冻结伤害包与组装记录不一致"
	if packet.role == "secondary" and not trace.added.is_empty():
		return "独立爆炸不可继承附加伤害"
	return _event_error(packet.tags, packet.role, float(trace.added_effectiveness))


static func _weapon_consumer(skill_id: String, role: String, tags: Variant) -> bool:
	return tags is Array and tags.has("hit") and tags.has("attack") and tags.has("projectile") \
		and not tags.has("spell") and not tags.has("secondary") and not tags.has("explosion") \
		and ((skill_id == "basic" and role == "projectile") or (skill_id == "tornado" and role in ["parent", "child"]))


static func _weapon_trace_error(trace: Variant, packet: Dictionary, coefficient: float) -> String:
	if not _weapon_consumer(packet.skill_id, packet.role, packet.tags):
		return "此命中不可使用武器局部伤害"
	if not trace is Dictionary or trace.size() != 4 or not trace.has_all(["profile", "components", "coefficient", "contribution"]):
		return "冻结武器局部阶段结构无效"
	var weapon: Dictionary = Weapon.resolve(trace.profile)
	if not weapon.ok or weapon.profile.is_empty() or not Weapon.physical_map(trace.components) or not Weapon.physical_map(trace.contribution) or not _nonnegative(trace.coefficient):
		return "冻结武器局部阶段无效"
	var contribution: float = float(weapon.components.physical) * coefficient
	if not is_finite(contribution) or float(trace.coefficient) != coefficient or float(trace.components.physical) != float(weapon.components.physical) or float(trace.contribution.physical) != contribution:
		return "冻结武器局部阶段与来源不一致"
	return ""


static func _event_error(tags: Variant, role: String, effectiveness: float) -> String:
	if not tags is Array or not tags.has("hit"):
		return "只支持真实命中事件"
	var seen: Dictionary = {}
	for tag: Variant in tags:
		if not tag is String or not TAGS.has(tag) or seen.has(tag):
			return "命中事件标签未知或重复"
		seen[tag] = true
	if role == "secondary":
		if tags.size() != 4 or not tags.has("area") or not tags.has("secondary") or not tags.has("explosion") or effectiveness != 0.0:
			return "独立爆炸必须使用独立标签且附加效用为零"
	elif tags.has("secondary") or tags.has("explosion") or tags.has("attack") == tags.has("spell"):
		return "附加伤害要求唯一的攻击或法术命中作用域"
	return ""


static func _typed_points(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for type: Variant in value:
		if not type is String or not Damage.TYPES.has(type) or not _nonnegative(value[type]):
			return false
	return true


static func _nonnegative(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0
