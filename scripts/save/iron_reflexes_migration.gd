class_name IronReflexesMigration
extends RefCounted
## Open the full Iron Reflexes source entry only after complete frozen39 validation.
## Preserve equipment vocabulary39 and every item, roll, point, UID and revision.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v39(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v39(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 40
	return candidate if Rules.reason_v40(candidate, validate_talents, socket_ids).is_empty() else {}
