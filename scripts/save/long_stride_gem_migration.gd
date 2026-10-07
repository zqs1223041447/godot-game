class_name LongStrideGemMigration
extends RefCounted
## Open only Long Stride after complete frozen52 validation.
## Source policy49, equipment51 and every nonversion field stay intact.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v52(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v52(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 53
	return candidate if Rules.reason_v53(candidate, validate_talents, socket_ids).is_empty() else {}
