class_name IronGripMigration
extends RefCounted
## Strict complete frozen56 validation precedes the sole version change.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v56(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v56(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 57
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
