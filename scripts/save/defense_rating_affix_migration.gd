class_name DefenseRatingAffixMigration
extends RefCounted
## Open schema39 equipment vocabulary only after complete frozen38 validation.
## Preserve source policy38 and every existing item, roll, point, UID and revision.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v38(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v38(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 39
	return candidate if Rules.reason_v39(candidate, validate_talents, socket_ids).is_empty() else {}
