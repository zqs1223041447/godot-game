class_name ForgebladeMigration
extends RefCounted
## Schema34 opens only the equipment vocabulary after complete frozen33 validation.
## Preserve every field except version: no item, point, currency or revision grant.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v33(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v33(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 34
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
