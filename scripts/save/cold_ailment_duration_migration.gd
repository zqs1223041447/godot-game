class_name ColdAilmentDurationMigration
extends RefCounted
## Open only node14209 after complete frozen48 validation. Change only the version.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v48(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v48(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 49
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
