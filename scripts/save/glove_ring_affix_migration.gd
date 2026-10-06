class_name GloveRingAffixMigration
extends RefCounted
## Open equipment vocabulary46 only after complete frozen45 validation.
## Preserve source policy45 and every item, roll, location, point and revision.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v45(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v45(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 46
	return candidate if Rules.reason_v46(candidate, validate_talents, socket_ids).is_empty() else {}
