class_name CombatData
extends RefCounted
## Small declarative recipes: movement, payload and effect grants are separate data.
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const TORNADO: Dictionary = {
	"parent_count": 3, "child_count": 3, "spread": 0.16,
	"parent": {"speed": 420.0, "range": 150.0, "lifetime": 0.9, "coefficient": 1.0,
		"pierce": -1, "radius": 6.0, "role": "parent", "split": true},
	"child": {"speed": 260.0, "range": 150.0, "lifetime": 1.7, "coefficient": 0.7,
		"pierce": -1, "radius": 4.5, "role": "child", "split": false},
	"explosion": {"coefficient": 0.9, "radius": 76.0},
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
	}
	for stat: String in scopes:
		if not is_zero_approx(float(stats.get(stat, 0.0))):
			var modifier: Dictionary = scopes[stat].duplicate(true)
			modifier.merge({"id": stat, "mode": "increased", "value": float(stats[stat])})
			result.append(modifier)
	return result


static func snapshot(stats: Dictionary, effects: Array) -> Dictionary:
	return {"base_damage": float(stats.get("damage", 18.0)), "modifiers": modifiers(stats),
		"effects": effects.duplicate(), "projectile_count": int(stats.get("projectile_count", 0)),
		"tornado_recipe": TORNADO.duplicate(true), "explosion_recipe": TORNADO.explosion.duplicate(true)}


static func tornado_packet(snapshot_value: Dictionary, role: String) -> Dictionary:
	var base: float = float(snapshot_value.base_damage)
	if role == "explosion":
		return Damage.packet({"fire": base * float(snapshot_value.get("explosion_recipe", TORNADO.explosion).coefficient)},
			["hit", "area", "secondary", "explosion"], "tornado")
	var amount: float = base * float(snapshot_value.get("tornado_recipe", TORNADO)[role].coefficient)
	return Damage.packet({"physical": amount * 0.6, "fire": amount * 0.4},
		["hit", "attack", "projectile"], "tornado")
