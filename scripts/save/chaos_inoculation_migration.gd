class_name ChaosInoculationMigration
extends RefCounted
## Freeze complete schema58 validation; migration only changes the version.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")


static func migrate_v58(source: Variant, validate_talents: Callable = Callable(), socket_ids: Array = []) -> Dictionary:
	if not Rules.reason_v58(source, validate_talents, socket_ids).is_empty(): return {}
	var candidate: Dictionary = source.duplicate(true)
	candidate.version = 59
	return candidate if Rules.reason(candidate, validate_talents, socket_ids).is_empty() else {}
