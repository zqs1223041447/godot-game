class_name EncirclingCleaveGemMigration
extends RefCounted
## Open only the Encircling Cleave gem after complete frozen51 validation.
## Source policy49, equipment51 and every nonversion field stay intact.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v51(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v51(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 52
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
