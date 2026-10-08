class_name OneWithNatureMigration
extends RefCounted
## Validate complete frozen55 first; only the version changes to open notable15842.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v55(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v55(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 56
	return candidate if Rules.reason_v56(candidate, validate_talents, socket_ids).is_empty() else {}
