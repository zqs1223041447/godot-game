extends RefCounted
## Preserve every canonical field under complete frozen59 validation.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")

static func migrate_v59(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v59(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 60
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
