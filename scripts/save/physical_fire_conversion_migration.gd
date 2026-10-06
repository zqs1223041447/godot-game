class_name PhysicalFireConversionMigration
extends RefCounted
## Open only Fire Mastery65020 after complete frozen43 envelope validation.
## This migration changes only version; points, items and rewards stay intact.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v43(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v43(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 44
	return candidate if Rules.reason_v44(candidate, validate_talents, socket_ids).is_empty() else {}
