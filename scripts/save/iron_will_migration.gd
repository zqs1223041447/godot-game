class_name IronWillMigration
extends RefCounted
## Complete frozen57 validation precedes the sole version change to58.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v57(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v57(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 58
	return candidate if Rules.reason_v58(candidate, validate_talents, socket_ids).is_empty() else {}
