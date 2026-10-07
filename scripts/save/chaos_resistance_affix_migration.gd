class_name ChaosResistanceAffixMigration
extends RefCounted
## Open equipment vocabulary51 only after complete frozen50 validation.
## No items, rolls, currency, points, revision or journey fields are changed.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v50(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v50(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 51
	return candidate if Rules.reason_v51(candidate, validate_talents, socket_ids).is_empty() else {}
