class_name ElementalConversionMigration
extends RefCounted
## Open the four exact schema48 source entries only after full frozen47 validation.
## This migration changes only version; items, gear46, points and rewards stay intact.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v47(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v47(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 48
	return candidate if Rules.reason_v48(candidate, validate_talents, socket_ids).is_empty() else {}
