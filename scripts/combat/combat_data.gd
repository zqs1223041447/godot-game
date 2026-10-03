class_name CombatData
extends RefCounted
## Small declarative recipes: movement, payload and effect grants are separate data.
const Data = preload("res://scripts/game_data.gd")
const BaseCompiler = preload("res://scripts/combat/damage_base_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const TORNADO: Dictionary = {
	"parent_count": 3, "child_count": 3, "spread": 0.16,
	"parent": {"speed": 420.0, "range": 150.0, "lifetime": 0.9, "coefficient": 1.0, "added_effectiveness": 1.0,
		"pierce": -1, "radius": 6.0, "role": "parent", "split": true},
	"child": {"speed": 260.0, "range": 150.0, "lifetime": 1.7, "coefficient": 0.7, "added_effectiveness": 0.7,
		"pierce": -1, "radius": 4.5, "role": "child", "split": false},
	"explosion": {"coefficient": 0.9, "added_effectiveness": 0.0, "radius": 76.0},
}
const EFFECTS: Dictionary = {
	"return_on_range": {"event": "range_reached", "action": "return", "priority": 20, "once": "projectile"},
	"explode_on_flight_end": {"event": "flight_ended", "action": "explode", "priority": 30, "once": "projectile"},
}

static func modifiers(stats: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var scopes: Dictionary = {
		"global_increased": {"all_tags": [], "damage_types": []},
		"projectile_increased": {"all_tags": ["projectile"], "damage_types": []},
		"elemental_increased": {"all_tags": [], "damage_types": Damage.ELEMENTS},
		"area_increased": {"all_tags": ["area"], "damage_types": []},
		"spell_increased": {"all_tags": ["spell"], "damage_types": []},
		"fire_increased": {"all_tags": [], "damage_types": ["fire"]},
		"cold_increased": {"all_tags": [], "damage_types": ["cold"]},
		"lightning_increased": {"all_tags": [], "damage_types": ["lightning"]},
		"attack_elemental_increased": {"all_tags": ["attack"], "damage_types": Damage.ELEMENTS},
	}
	for stat: String in scopes:
		if not is_zero_approx(float(stats.get(stat, 0.0))):
			var modifier: Dictionary = scopes[stat].duplicate(true)
			modifier.merge({"id": stat, "mode": "increased", "value": float(stats[stat])})
			result.append(modifier)
	return result


static func snapshot(stats: Dictionary, effects: Array) -> Dictionary:
	var value: Dictionary = {"base_damage": float(stats.get("damage", 18.0)), "modifiers": modifiers(stats),
		"effects": effects.duplicate(true), "projectile_count": int(stats.get("projectile_count", 0)),
		"tornado_recipe": TORNADO.duplicate(true), "explosion_recipe": TORNADO.explosion.duplicate(true),
		"added_damage": {"attack": {"physical": stats.get("attack_added_physical", 0.0), "fire": stats.get("attack_added_fire", 0.0)},
			"spell": {"cold": stats.get("spell_added_cold", 0.0), "lightning": stats.get("spell_added_lightning", 0.0)}}}
	if stats.has("added_damage_sources"):
		value.added_damage_sources = stats.added_damage_sources.duplicate(true) if stats.added_damage_sources is Array else stats.added_damage_sources
	return value


## Compatibility wrapper: explosion is the previous public name for secondary.
static func tornado_packet(snapshot_value: Dictionary, role: String) -> Dictionary:
	return secondary_packet(snapshot_value, "tornado") if role == "explosion" or role == "secondary" else event_packet(snapshot_value, "tornado", role)


static func event_packet(snapshot_value: Dictionary, skill_id: String, role: String = "direct", index: int = 0) -> Dictionary:
	if role == "secondary":
		return secondary_packet(snapshot_value, skill_id)
	if snapshot_value.has("compiled_packets") or snapshot_value.has("compiled_skill_id"):
		return _frozen_packet(snapshot_value, skill_id, role, index)
	if snapshot_value.has("weapon_profile") and snapshot_value.weapon_profile is Dictionary and snapshot_value.weapon_profile.is_empty():
		return {}
	var recipe: Dictionary = _event_recipe(snapshot_value, skill_id, role, index)
	return BaseCompiler.assemble(snapshot_value.get("base_damage"), recipe,
		snapshot_value.get("added_damage", {}), snapshot_value.get("added_damage_sources", []), snapshot_value.get("weapon_profile", {}))


static func secondary_packet(snapshot_value: Dictionary, skill_id: String) -> Dictionary:
	if not skill_id in ["basic", "tornado", "bolt", "frost"]:
		return {}
	if snapshot_value.has("compiled_packets") or snapshot_value.has("compiled_skill_id"):
		return _frozen_packet(snapshot_value, skill_id, "secondary", 0)
	if snapshot_value.has("weapon_profile") and snapshot_value.weapon_profile is Dictionary and snapshot_value.weapon_profile.is_empty():
		return {}
	var spec: Variant = snapshot_value.get("explosion_recipe", TORNADO.explosion)
	if not spec is Dictionary or not spec.has_all(["coefficient", "added_effectiveness", "radius"]) or not BaseCompiler._nonnegative(spec.radius):
		return {}
	return BaseCompiler.assemble(snapshot_value.get("base_damage"), _hit_recipe(skill_id, "secondary",
		{"fire": 1.0}, spec.coefficient, spec.added_effectiveness, ["hit", "area", "secondary", "explosion"]),
		snapshot_value.get("added_damage", {}), snapshot_value.get("added_damage_sources", []), snapshot_value.get("weapon_profile", {}))


static func _event_recipe(snapshot_value: Dictionary, skill_id: String, role: String, index: int) -> Dictionary:
	if index != 0 and skill_id != "chain":
		return {}
	if skill_id == "basic":
		return _hit_recipe(skill_id, "projectile", {"physical": 1.0}, 1.0, 1.0, ["hit", "projectile", "attack"]) if role == "projectile" else {}
	if skill_id == "tornado":
		var tornado: Variant = snapshot_value.get("tornado_recipe", TORNADO)
		if not role in ["parent", "child"] or not tornado is Dictionary:
			return {}
		var spec: Variant = tornado.get(role)
		if not spec is Dictionary or not spec.has_all(["coefficient", "added_effectiveness"]):
			return {}
		# Authored 60/40 intrinsic distribution, not physical-to-fire conversion.
		return _hit_recipe(skill_id, role, {"physical": 0.6, "fire": 0.4}, spec.coefficient, spec.added_effectiveness, ["hit", "attack", "projectile"])
	if not Data.SKILLS.has(skill_id):
		return {}
	var skill: Dictionary = Data.SKILLS[skill_id]
	if skill_id in ["bolt", "frost"]:
		var spec: Variant = skill.get("projectile_recipe")
		if role != "projectile" or not spec is Dictionary or not spec.has_all(["coefficient", "added_effectiveness", "damage_type"]):
			return {}
		return _hit_recipe(skill_id, role, {spec.damage_type: 1.0}, spec.coefficient, spec.added_effectiveness, ["hit", "projectile", "spell"])
	if skill_id in ["nova", "meteor", "chain"]:
		var spec: Variant = skill.get("hit_recipe")
		if not spec is Dictionary or not spec.has_all(["base_coefficient", "added_effectiveness", "damage_type"]):
			return {}
		if skill_id != "chain":
			return _hit_recipe(skill_id, role, {spec.damage_type: 1.0}, spec.base_coefficient, spec.added_effectiveness, ["hit", "spell", "area"]) if role == "direct" else {}
		if not role in ["direct", "bounce"] or not spec.has_all(["bounce_count", "base_coefficient_loss_per_bounce", "added_effectiveness_loss_per_bounce"]):
			return {}
		return chain_hit_recipe(spec, index)
	return {}


static func chain_hit_recipe(spec: Dictionary, index: int) -> Dictionary:
	if not _valid_chain_recipe(spec) or index < 0 or index >= int(spec.bounce_count): return {}
	return _hit_recipe("chain", "bounce", {spec.damage_type: 1.0},
		float(spec.base_coefficient) - index * float(spec.base_coefficient_loss_per_bounce),
		float(spec.added_effectiveness) - index * float(spec.added_effectiveness_loss_per_bounce), ["hit", "spell", "chain"])


static func chain_packet(snapshot_value: Dictionary, spec: Dictionary, index: int) -> Dictionary:
	return BaseCompiler.assemble(snapshot_value.get("base_damage"), chain_hit_recipe(spec, index),
		snapshot_value.get("added_damage", {}), snapshot_value.get("added_damage_sources", []), snapshot_value.get("weapon_profile", {}))


static func _valid_chain_recipe(spec: Dictionary) -> bool:
	for key: String in ["base_coefficient", "added_effectiveness", "bounce_count", "base_coefficient_loss_per_bounce", "added_effectiveness_loss_per_bounce"]:
		if not BaseCompiler._nonnegative(spec.get(key)):
			return false
	return float(spec.bounce_count) == floorf(float(spec.bounce_count)) and int(spec.bounce_count) >= 1 and int(spec.bounce_count) <= 32


static func _hit_recipe(skill_id: String, role: String, distribution: Dictionary, coefficient: Variant, effectiveness: Variant, tags: Array) -> Dictionary:
	return {"stage": BaseCompiler.STAGE, "intrinsic_distribution": distribution, "base_coefficient": coefficient,
		"added_effectiveness": effectiveness, "tags": tags, "skill_id": skill_id, "role": role}


## A corrupt or wrong-skill compiled snapshot fails closed; it never reassembles.
static func _frozen_packet(snapshot_value: Dictionary, skill_id: String, role: String, index: int) -> Dictionary:
	if snapshot_value.get("compiled_skill_id") != skill_id or not snapshot_value.get("compiled_packets") is Dictionary:
		return {}
	var allowed: Dictionary = {"basic": ["projectile", "secondary"], "tornado": ["parent", "child", "secondary"], "bolt": ["projectile", "secondary"],
		"frost": ["projectile", "secondary"], "nova": ["direct"], "meteor": ["direct"], "chain": ["direct", "bounce"]}
	if not allowed.has(skill_id) or not allowed[skill_id].has(role):
		return {}
	var packets: Dictionary = snapshot_value.compiled_packets
	var packet: Variant = null
	var expected_role: String = role
	if skill_id == "chain" and role in ["direct", "bounce"]:
		var bounces: Variant = packets.get("bounces")
		if not bounces is Array or index < 0 or index >= bounces.size():
			return {}
		packet = bounces[index]
		expected_role = "bounce"
	else:
		if index != 0:
			return {}
		packet = packets.get(role)
	if not BaseCompiler.packet_error(packet).is_empty() or packet.skill_id != skill_id or packet.role != expected_role:
		return {}
	return packet.duplicate(true)
