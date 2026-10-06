class_name MechanicRegistry
extends RefCounted
## The authoritative additive stat bundles used by both talents and monsters.
## IDs are content identity, not executable effect names. Unknown IDs fail closed.
## Adding a stat/actor requires an explicit supported-stat entry and runtime consumer.

const Balance = preload("res://scripts/mechanics/passive_balance_adapter.gd")
const SourceGrants = preload("res://scripts/mechanics/source_monster_grants.gd")
const SCHEMA_VERSION: int = 1
const PLAYER_STATS: Array[String] = [
	"damage", "max_health", "max_mana", "max_shield", "attack_speed", "move_speed",
	"mana_regen", "shield_regen", "fire_resistance", "shield_recharge_rate_increased", "shield_recharge_start_faster",
	"global_increased", "projectile_increased", "elemental_increased", "area_increased",
	"spell_increased", "fire_increased", "cold_increased", "lightning_increased",
	"attack_elemental_increased", "attack_speed_increased", "move_speed_increased", "mana_regen_increased",
	"attack_added_physical", "attack_added_fire", "spell_added_cold", "spell_added_lightning",
]
const MONSTER_STATS: Array[String] = [
	"move_speed_increased",
	"damage", "max_health", "max_shield", "attack_speed", "move_speed", "shield_regen", "fire_resistance", "shield_recharge_rate_increased", "shield_recharge_start_faster",
]
# Explicit compatibility spellings. Never infer an alias from a prefix or substring.
# Saves retain stable tree node IDs; item-instance migrations do not rewrite them.
const ALIASES: Dictionary = {
	"talent.ember.power": "ember_power",
	"talent.gale.stride": "gale_stride",
	"talent.aegis.recovery": "aegis_recovery",
}
static var _revision: int = 1
# Source-backed definitions are loaded once; there is no numeric fallback/copy.
static var _definitions: Dictionary = Balance.definitions()


static func get_revision() -> int:
	return _revision


static func policy_version() -> String:
	return Balance.policy_version()


static func canonical_id(id: String) -> String:
	if id == SourceGrants.ID: return id
	if _definitions.has(id):
		return id
	var target: String = str(ALIASES.get(id, ""))
	return target if _definitions.has(target) else ""


static func get_ids(actor: String = "") -> Array[String]:
	var result: Array[String] = []
	for id: String in _definitions:
		if actor.is_empty() or is_supported(id, actor):
			result.append(id)
	if actor.is_empty() or is_supported(SourceGrants.ID, actor): result.append(SourceGrants.ID)
	return result


static func get_definition(id: String) -> Dictionary:
	var canonical: String = canonical_id(id)
	if canonical.is_empty():
		return {}
	var result: Dictionary
	if canonical == SourceGrants.ID:
		var source := SourceGrants.resolve(canonical)
		if not source.ok: return {}
		result = source.definition.duplicate(true)
	else:
		result = _definitions[canonical].duplicate(true)
	var actors: Array[String] = []
	for actor: String in ["player", "monster"]:
		if is_supported(canonical, actor):
			actors.append(actor)
	result["id"] = canonical
	result["kind"] = "stat_bundle"
	result["schema_version"] = SCHEMA_VERSION
	result["definition_revision"] = _revision
	if canonical != SourceGrants.ID: result["policy_version"] = policy_version()
	result["supported_actors"] = actors
	result["support_reason"] = support_reason(canonical, "monster")
	return result


static func support_reason(id: String, actor: String) -> String:
	if actor not in ["player", "monster"]:
		return "Unknown actor: " + actor
	var canonical: String = canonical_id(id)
	if canonical.is_empty():
		return "Unknown mechanism: " + id
	var stats: Dictionary
	if canonical == SourceGrants.ID:
		var source := SourceGrants.resolve(canonical)
		if not source.ok: return source.reason
		stats = source.stats
	else:
		stats = _definitions[canonical]["stats"]
	var invalid: String = _stats_error(stats)
	if not invalid.is_empty():
		return "Invalid mechanism %s: %s" % [canonical, invalid]
	if actor == "monster":
		for stat: String in stats:
			if not MONSTER_STATS.has(stat):
				return "Player-only mechanism %s: monster does not support %s; full bundle rejected" % [canonical, stat]
	return ""


static func is_supported(id: String, actor: String) -> bool:
	return support_reason(id, actor).is_empty()


static func migrate_ids(ids: Array) -> Dictionary:
	var canonical_ids: Array[String] = []
	var errors: Array[String] = []
	var aliases_applied: Dictionary = {}
	for value: Variant in ids:
		if not value is String:
			errors.append("Mechanism ID must be a string")
			continue
		var id: String = value
		var canonical: String = canonical_id(id)
		if canonical.is_empty():
			errors.append("Unknown mechanism: " + id)
			continue
		canonical_ids.append(canonical)
		if id != canonical:
			aliases_applied[id] = canonical
	if not errors.is_empty():
		canonical_ids.clear()
	return {"ok": errors.is_empty(), "ids": canonical_ids, "errors": errors, "aliases_applied": aliases_applied}


static func resolve(id: String, actor: String = "player", role_coefficient: float = 1.0) -> Dictionary:
	return resolve_grants([id], actor, role_coefficient)


static func resolve_grants(ids: Array, actor: String = "player", role_coefficient: float = 1.0) -> Dictionary:
	# Every grant uses the same additive semantics. Repeated grants intentionally stack.
	# An explicit role coefficient scales the entire bundle, never selected fields.
	var migration: Dictionary = migrate_ids(ids)
	var errors: Array[String] = []
	errors.assign(migration.errors)
	var canonical_ids: Array[String] = []
	canonical_ids.assign(migration.ids)
	if actor not in ["player", "monster"]:
		errors.append("Unknown actor: " + actor)
	if not is_finite(role_coefficient) or role_coefficient < 0.0:
		errors.append("Role coefficient must be finite and nonnegative")
	for id: String in canonical_ids:
		var reason: String = support_reason(id, actor)
		if not reason.is_empty():
			errors.append(reason)
	var stats: Dictionary = {}
	var source_grants: Array[Dictionary] = []
	if errors.is_empty():
		for id: String in canonical_ids:
			var definition_stats: Dictionary
			if id == SourceGrants.ID:
				var source := SourceGrants.resolve(id)
				if not source.ok:
					errors.append(source.reason)
					break
				definition_stats = source.stats
				source_grants.append(source.definition.duplicate(true))
			else:
				definition_stats = _definitions[id]["stats"]
			for stat: String in definition_stats:
				var value: float = float(stats.get(stat, 0.0)) + float(definition_stats[stat]) * role_coefficient
				if not is_finite(value):
					errors.append("Mechanism stat overflow: " + stat)
				else:
					stats[stat] = value
	if not errors.is_empty():
		stats.clear()
		canonical_ids.clear()
		source_grants.clear()
	var result := {"ok": errors.is_empty(), "stats": stats, "mechanism_ids": canonical_ids,
		"errors": errors, "actor": actor, "role_coefficient": role_coefficient,
		"schema_version": SCHEMA_VERSION, "definition_revision": _revision, "policy_version": policy_version()}
	if not source_grants.is_empty():
		result.source_grants = source_grants
		result.policy_version = policy_version() + "+" + str(source_grants[0].policy_version)
	return result


static func set_definition_stats(id: String, stats: Dictionary) -> bool:
	# Content tuning is atomic and preserves the complete existing effect contract.
	# New mechanisms/stat fields belong in this registry, not arbitrary runtime payloads.
	var canonical: String = canonical_id(id)
	if canonical.is_empty() or canonical == SourceGrants.ID or not _stats_error(stats).is_empty():
		return false
	var original: Dictionary = _definitions[canonical]["stats"]
	if stats.size() != original.size():
		return false
	for stat: String in original:
		if not stats.has(stat):
			return false
	_definitions[canonical]["stats"] = stats.duplicate(true)
	_revision += 1
	return true


static func _stats_error(stats: Dictionary) -> String:
	if stats.is_empty():
		return "Empty stat bundle"
	for key: Variant in stats:
		if not key is String or not PLAYER_STATS.has(key):
			return "Unsupported stat field: " + str(key)
		var value: Variant = stats[key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
			return "Stat must be numeric: " + str(key)
		if not is_finite(float(value)) or float(value) < 0.0:
			return "Stat must be finite and nonnegative: " + str(key)
	return ""
