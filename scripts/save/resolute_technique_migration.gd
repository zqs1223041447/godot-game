class_name ResoluteTechniqueMigration
extends RefCounted
## Open the indivisible Resolute Technique source entry only after strict37 validation.
## Equipment vocabulary37, items, rolls, points, UIDs, currency and journey are unchanged.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v37(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v37(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 38
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
