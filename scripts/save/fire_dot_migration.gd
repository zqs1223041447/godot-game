class_name FireDotMigration
extends RefCounted
## Validate the frozen schema31 envelope before opening the schema32 vocabulary.
## Only the version changes; existing legal allocations gain no new effects.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v31(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v31(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 32
	return candidate if Rules.reason_v32(candidate, validate_talents, socket_ids).is_empty() else {}
