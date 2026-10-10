extends RefCounted
## Preserve every canonical field under complete frozen60 validation.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")

static func migrate_v60(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v60(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 61
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
