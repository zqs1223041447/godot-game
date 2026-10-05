class_name ElementalDefenseAffixMigration
extends RefCounted
## Open schema37 equipment vocabulary only after complete frozen36 validation.
## Preserve source policy36 and every existing item, roll, point, UID and revision.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v36(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v36(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 37
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
